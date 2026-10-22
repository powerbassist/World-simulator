extends SceneTree

## Headless test: godot --headless --script res://tests/test_hold_reason.gd
## Non-zero exit on any failure.
##
## V5.1-d1b3, the parent's call after QA's "the clock paused with no cause I saw":
## since d1a the inbox can already be up over a tab, so a hold that slides it in
## moves nothing on screen and the clock just stops. Every hold says why, where
## the clock is -- "Paused: <the event> needs an answer." -- and brings its card to
## the top of the inbox, whether the inbox slid in or was already there. The line
## goes when the clock runs again.

const Events = preload("res://src/sim/events.gd")
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
	_check_a_hold_says_why()
	_check_an_arrival_says_why()
	_finish()
	return true


func _check_a_hold_says_why() -> void:
	var clock = _main._clock
	var inbox = _main._hud.inbox
	var ns = _main._state.player()
	_main._paused_for_programme = false
	_main._windows.close_all()
	_main._windows.open("budget")
	if not inbox.visible:
		_fail("premise: the inbox is not already up over the tab")
	var ev = null
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt) and not candidate.choices.is_empty():
			ev = candidate
			break
	ns.event_queue.clear()
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	for entry in ns.event_queue:
		entry["months_left"] = 1
	# The event's card was shown earlier and newer decisions sit above it now.
	var card: String = inbox.push(Strings.row_name("events", ev), "body", [], null, true)
	_main._event_cards[card] = String(ev.id)
	inbox.push("A newer decision", "body", [], null, true)
	_main._unseen_events[String(ev.id)] = false
	_main._paused_for_decision = false
	clock.paused = false

	_main._guard_lapses(ns)

	if not clock.paused:
		_fail("premise: the lapse guard did not hold the clock")
	var reason: String = _main._hud.clock_cluster.hold_reason()
	if not reason.contains(Strings.row_name("events", ev)):
		_fail("the clock stopped without saying why: '%s'" % reason)
	var lane: String = inbox.lane_of(card)
	if inbox._rows[lane].get_child(0) != inbox._cards[card]:
		_fail("the holding decision's card is not at the top of the inbox")

	clock.paused = false
	_main._hud.clock_cluster.refresh(clock)
	if _main._hud.clock_cluster.hold_reason() != "":
		_fail("the hold's reason stayed after the clock ran again")
	_main._windows.close_all()


## QA on #73: an ARRIVAL hold (the path _card_events runs). The line was empty
## when the desk was otherwise empty -- the hold came before the arrival was
## recorded -- and named a quiet event already on the desk when there was one.
func _check_an_arrival_says_why() -> void:
	var clock = _main._clock
	var ns = _main._state.player()
	_main._windows.close_all()
	_main._unseen_events.clear()
	_main._event_cards.clear()
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	ns.event_queue.clear()
	var quiet = null
	var loud = null
	for candidate in _main._loader.events:
		if candidate.choices.is_empty():
			continue
		if quiet == null and not bool(candidate.interrupt):
			quiet = candidate
		elif loud == null and not bool(candidate.interrupt) and candidate != quiet:
			loud = candidate
	var month: int = Events._absolute_month(int(_main._state.year), int(_main._state.month))
	# A quiet event on the desk, unseen and not holding.
	Events.announce(ns, quiet, month, Events.region_names(ns, _main._loader))
	_main._unseen_events[String(quiet.id)] = false
	var desk := {String(quiet.id): true}
	# The arrival, set to hold whatever its band says.
	_main._messages = {}
	Events.announce(ns, loud, month, Events.region_names(ns, _main._loader))
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) == String(loud.id):
			entry["interrupt"] = false
			entry["severity"] = 3
	clock.paused = false
	_main._card_events(_main._state.year, _main._state.month, desk, {})
	if not clock.paused:
		_fail("premise: the arrival did not hold the clock")
		return
	var reason: String = _main._hud.clock_cluster.hold_reason()
	if not reason.contains(Strings.row_name("events", loud)):
		_fail("an arrival hold names '%s', not the arrival '%s'" % [reason, Strings.row_name("events", loud)])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_hold_reason: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
