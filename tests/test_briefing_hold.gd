extends SceneTree

## Headless test: godot --headless --script res://tests/test_briefing_hold.gd
## Non-zero exit on any failure.
##
## V5.3-0, the monthly briefing's hold (docs/design/v5.3-0-readability.md 2.2), through
## the real game:
##   - a month run by the game's own month (main._on_month_elapsed) ends on the
##     briefing, which holds the clock and says so on the clock line;
##   - Space under the card (press and release frames apart) neither releases the
##     hold nor closes the card -- V5.1-0c's bug, where Space forfeited the Agenda;
##   - the closing button reads Continue exactly when nothing else holds, and a real
##     click on it releases a clock that was running;
##   - with an interrupt on the desk it reads "Next: <event>", and closing leaves the
##     clock held and the inbox up (the briefing never releases another hold);
##   - the front page waits for the card; after a lost election there is none;
##   - the "Only when something is new" setting skips a month that repeats the last;
##   - key 1 is the first line's Go.

const Click = preload("res://tests/click.gd")
const Programme = preload("res://src/sim/programme.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const Priorities = preload("res://src/ui/priorities.gd")
const MessageSettings = preload("res://src/ui/message_settings.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _phase := 0
var _card
var _target: Control


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_start()
	elif _phase == 1 and _frame > 5 and not _main._month_runner.running():
		_check_opened()
		_phase = 2
		_key(KEY_SPACE, true)
	elif _phase == 2:
		_key(KEY_SPACE, false)
		_phase = 3
	elif _phase == 3:
		if not _card.visible or not _main._clock.paused:
			_fail("Space under the briefing released it (card %s, paused %s)" % [_card.visible, _main._clock.paused])
		_target = _card._close
		Click.half(_main.get_viewport(), _target, true)
		_phase = 4
	elif _phase == 4:
		_phase = 5
	elif _phase == 5:
		Click.half(_main.get_viewport(), _target, false)
		_phase = 6
	elif _phase == 6:
		_check_continue()
		_check_next_on_interrupt()
		_check_plate_and_defeat()
		_check_new_only()
		_check_key_go()
		_check_after_load()
		_finish()
		return true
	return false


func _start() -> void:
	# Every month (the default), whatever an earlier test in this run's user dir left.
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value(MessageSettings.SECTION, MessageSettings.BRIEFING_NEW_ONLY_KEY, false)
	cfg.save(SettingsPanel.CONFIG_PATH)
	var ns = _main._state.player()
	var offer: Array = Programme.available(_main._state, ns, _main._loader)
	if not offer.is_empty():
		_main._on_programme_chosen(String(offer[0]["id"]))
	_card = BriefingDriver.card_of(_main)
	if _card == null:
		_fail("no briefing card registered")
		_finish()
		return
	_main._clock.paused = false
	var state = _main._state
	var next: int = int(state.year) * 12 + int(state.month) + 1
	var year := floori((next - 1) / 12.0)
	_main._on_month_elapsed(year, next - year * 12)
	_phase = 1


func _check_opened() -> void:
	if not _card.visible:
		_fail("the month ended without the briefing")
	if not _main._clock.paused:
		_fail("the briefing does not hold the clock")
	if _card.go_buttons.size() != 3:
		_fail("the briefing shows %d priorities, not 3" % _card.go_buttons.size())
	var line := String(_main._hud.clock_cluster._reason.text)
	if not line.contains("briefing"):
		_fail("the clock line does not name the briefing: '%s'" % line)


func _check_continue() -> void:
	var holds: bool = _main._decision_holds_clock() or _main._paused_for_programme
	if _card.visible:
		_fail("a click on the closing button did not close the briefing")
	if holds == (not _main._clock.paused):
		_fail("after the briefing, the clock is %s while another hold is %s" % ["paused" if _main._clock.paused else "running", holds])


func _check_next_on_interrupt() -> void:
	var ns = _main._state.player()
	var ev = _main._loader.events[0]
	ns.event_queue.append({"event_id": String(ev.id), "event_name": ev.event_name, "months_left": 2,
		"interrupt": true, "severity": 3, "category": ev.category})
	_main._clock.paused = false
	BriefingDriver._games[_main.get_instance_id()]["pending"] = {}
	BriefingDriver.open(_main, {})
	if not String(_card._close.text).begins_with("Next:"):
		_fail("with an interrupt held the closing button reads '%s', not 'Next: ...'" % _card._close.text)
	BriefingDriver.close(_main)
	if not _main._clock.paused:
		_fail("closing the briefing released an interrupt's hold")
	if not _main._hud.inbox.visible:
		_fail("closing the briefing did not bring up the held card's inbox")
	ns.event_queue.clear()


func _check_plate_and_defeat() -> void:
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	game["pending"] = {}
	if BriefingDriver.plate_for(_main, {"election_results": []}) != _card:
		_fail("the front page does not wait for the briefing")
	var ns = _main._state.player()
	ns.in_government = false
	game["pending"] = {}
	if BriefingDriver.plate_for(_main, {"election_results": [{}]}) != _main._election_panel:
		_fail("after a defeat the front page does not wait for the count's plate")
	BriefingDriver.open(_main, {})
	if _card.visible:
		_fail("a briefing opened after a lost election")
	ns.in_government = true


func _check_new_only() -> void:
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	MessageSettings.set_foreign_news(false, SettingsPanel.CONFIG_PATH)
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value(MessageSettings.SECTION, MessageSettings.BRIEFING_NEW_ONLY_KEY, true)
	cfg.save(SettingsPanel.CONFIG_PATH)
	# A quiet month (standing reads only) does not stop; a request arriving does.
	var ns = _main._state.player()
	for register in [ns.event_queue, ns.audience_requests, ns.commitments]:
		register.clear()
	ns.person_grudges.clear()
	ns.tabled_bill = {}
	ns.draft_bills.clear()
	_main._unseen_events.clear()
	game["pending"] = {}
	game["memory"] = {}
	if BriefingDriver._will_show(_main, game, {}) and not Priorities.quiet(game["pending"]["lines"]):
		_fail("premise: the cleared state is not a quiet month: %s" % str(game["pending"]["lines"].map(func(l): return l["kind"])))
	elif BriefingDriver._will_show(_main, game, {}):
		_fail("'Only when something is new' still stopped on a quiet month")
	var now := int(_main._state.year) * 12 + int(_main._state.month)
	var pid := ""
	for person in _main._loader.people[String(ns.id)]:
		if String(person.id).begins_with(String(ns.id) + "_"):
			pid = String(person.id)
			break
	ns.audience_requests.append({"id": "%s|%d" % [pid, now], "person_id": pid, "object": "x", "status": "pending",
		"arrived_month": now, "deadline_month": now + 1})
	game["pending"] = {}
	if not BriefingDriver._will_show(_main, game, {}):
		_fail("'Only when something is new' skipped a month with a new request")
	ns.audience_requests.clear()
	cfg.set_value(MessageSettings.SECTION, MessageSettings.BRIEFING_NEW_ONLY_KEY, false)
	cfg.save(SettingsPanel.CONFIG_PATH)
	game["pending"] = {}
	if not BriefingDriver._will_show(_main, game, {}):
		_fail("'Every month' skipped a month")


func _check_key_go() -> void:
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	game["pending"] = {}
	_main._clock.paused = false
	BriefingDriver.open(_main, {})
	if not _card.visible:
		_fail("premise: the briefing did not open for the key check")
		return
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	_card._input(key)
	if _card.visible:
		_fail("key 1 did not take the first line's Go")


## QA's RECORD on #218: a load with the card up kept the discarded game's card and
## its was_running. The load's own restore path (DeskCards.restore_after_load) brings
## the card down and forgets what it held.
func _check_after_load() -> void:
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	if _card.visible:
		BriefingDriver.close(_main)
	_main._clock.paused = false
	game["pending"] = {}
	BriefingDriver.open(_main, {})
	if not _card.visible:
		_fail("premise: the briefing did not open before the load")
	preload("res://src/ui/desk_cards.gd").restore_after_load(_main)
	if _card.visible or bool(game["was_running"]) or not (game["lines"] as Array).is_empty():
		_fail("a load left the discarded game's briefing (card %s, was_running %s, lines %d)" % [
			_card.visible, game["was_running"], (game["lines"] as Array).size()])


func _key(code: Key, down: bool) -> void:
	var key := InputEventKey.new()
	key.keycode = code
	key.physical_keycode = code
	key.pressed = down
	Input.parse_input_event(key)


func _finish() -> void:
	for f in _failures:
		printerr("FAIL: %s" % f)
	if _failures.is_empty():
		print("test_briefing_hold: all checks passed")
	quit(1 if not _failures.is_empty() else 0)


func _fail(message: String) -> void:
	_failures.append(message)
