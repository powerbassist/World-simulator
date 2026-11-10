extends SceneTree

## Headless test: godot --headless --script res://tests/test_called_event.gd
## Non-zero exit on any failure.
##
## V5.3 B7 (docs/design/v5.3-b7-density.md, the author's call 3, 2026-11-10): a minor
## event the quiet-month call brought (`never_holds` on its desk entry) gets its desk
## card like any arrival, NEVER holds the clock -- the lapse guard passes it by in its
## last month -- and, left unanswered, lapses to a note in the inbox rather than to the
## month's briefing. The lapse guard is unchanged for every other minor event: the same
## entry without the mark is the positive control, held in its last month and carried
## to the briefing on its default.
##
## The called event lands in the QuietEvent step, after the Events step whose hook cards
## the month's arrivals, so its card comes at the month's end (BriefingDriver.open, with
## the Regions arrival): checked through that door too.

const Events = preload("res://src/sim/events.gd")
const DeskCards = preload("res://src/ui/desk_cards.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const Inbox = preload("res://src/ui/inbox.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check_called_never_holds()
	_check_control_holds()
	_check_called_lapses_to_a_note()
	_check_control_lapses_to_the_briefing()
	_check_month_end_cards_it()
	_finish()
	return true


## A minor event with choices and no interrupt: what the quiet-month call delivers.
func _minor_event():
	for ev in _main._loader.events:
		if int(ev.severity) == 1 and not bool(ev.interrupt) and ev.choices.size() > 1 and ev.on_action == "":
			return ev
	return null


## A fresh desk holding `ev` alone, in its last month, the mark set or not; the clock
## running and no hold of any other kind.
func _stage(ev, called: bool) -> Dictionary:
	var ns = _main._state.player()
	_main._paused_for_programme = false
	_main._paused_for_decision = false
	_main._unseen_events.clear()
	ns.event_queue.clear()
	Events.announce(ns, ev, _now(), Events.region_names(ns, _main._loader))
	var entry: Dictionary = ns.event_queue[0]
	entry["months_left"] = 1
	if called:
		entry["never_holds"] = true  # Systems' mark (events.gd announce, B7)
	_main._clock.paused = false
	return entry


func _now() -> int:
	return Events._absolute_month(int(_main._state.year), int(_main._state.month))


func _check_called_never_holds() -> void:
	var ev = _minor_event()
	if ev == null:
		_fail("premise: no minor event with two choices in the content")
		return
	_stage(ev, true)
	DeskCards.card_called(_main)
	if not _main._event_cards.values().has(String(ev.id)):
		_fail("called: the called event got no desk card")
	if not _main._unseen_events.has(String(ev.id)):
		_fail("called: the called event is not in the unseen set (the answer paths would miss it)")
	DeskCards.guard_lapses(_main, _main._state.player())
	if bool(_main._unseen_events.get(String(ev.id), false)):
		_fail("called: the lapse guard marked a called event as holding")
	if _main._decision_holds_clock() or _main._clock.paused:
		_fail("called: a called event in its last month held the clock")


## The positive control: the same entry without the mark is held in its last month.
func _check_control_holds() -> void:
	var ev = _minor_event()
	if ev == null:
		return
	_stage(ev, false)
	_main._unseen_events[String(ev.id)] = false  # a quiet arrival, as card_events records it
	DeskCards.guard_lapses(_main, _main._state.player())
	if not _main._decision_holds_clock():
		_fail("control: the lapse guard no longer holds an ordinary minor event in its last month")
	_main._paused_for_decision = false
	_main._unseen_events.clear()
	_main._clock.paused = false


## Left alone: the sim's own default (Events._tick_countdowns), then the desk hook.
## Returns the briefing's held consequence cards after the hook ran.
func _lapse(ev, called: bool) -> Array:
	var entry := _stage(ev, called)
	DeskCards.card_called(_main)
	var desk_before := {String(ev.id): entry}  # main's capture: the entry itself
	var ns = _main._state.player()
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	game.erase("month_cards")
	Events._tick_countdowns(_main._state, ns, _main._loader, _now())
	if not ns.event_queue.is_empty():
		_fail("premise: the sim did not default the entry in its last month")
	DeskCards.card_events(_main, int(_main._state.year), int(_main._state.month), desk_before, {})
	return game.get("month_cards", [])


func _note_for(ev) -> String:
	var inbox = _main._hud.inbox
	for id in inbox._cards:
		if inbox.lane_of(String(id)) == Inbox.NOTES \
				and String((inbox._notes.get(id, {}) as Dictionary).get("body", "")).contains(Strings.row_name("events", ev)):
			return String(id)
	return ""


func _check_called_lapses_to_a_note() -> void:
	var ev = _minor_event()
	if ev == null:
		return
	var held := _lapse(ev, true)
	if _note_for(ev) == "":
		_fail("called: the lapse left no note in the inbox")
	if not held.is_empty():
		_fail("called: the lapse went to the month's briefing, not to a note (%d held cards)" % held.size())
	if _main._decision_holds_clock() or _main._clock.paused:
		_fail("called: the lapse held the clock")
	_clear_notes()


## The control: an ordinary minor event's default is the briefing's "Decided for you".
func _check_control_lapses_to_the_briefing() -> void:
	var ev = _minor_event()
	if ev == null:
		return
	var held := _lapse(ev, false)
	if held.size() != 1:
		_fail("control: an ordinary default no longer reaches the briefing (%d held cards)" % held.size())
	_clear_notes()


## The called event arrives after the Events step's hook: the month's end cards it.
func _check_month_end_cards_it() -> void:
	var ev = _minor_event()
	if ev == null:
		return
	_stage(ev, true)
	_main._event_cards.clear()
	BriefingDriver.finish_month(_main, {})
	if not _main._event_cards.values().has(String(ev.id)):
		_fail("called: the month's end did not card the called event")
	BriefingDriver.close(_main)


func _clear_notes() -> void:
	var inbox = _main._hud.inbox
	for id in inbox._cards.keys():
		inbox.dismiss(String(id))
	_main._event_cards.clear()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_called_event: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
