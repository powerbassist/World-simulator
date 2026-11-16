extends SceneTree

## Headless test: godot --headless --script res://tests/test_briefing_hold.gd
## Non-zero exit on any failure.
##
## G1, the chief off the clock (chief-briefing-brief.md, "What must hold"), through the
## real game:
##   - a month run by the game's own month (main._on_month_elapsed) ends with no card
##     and no pause; the chief's mark names the month, and the month's consequence card
##     is in the inbox (no card says it now);
##   - a real click on the mark opens the read he was asked for: it holds the clock and
##     says so on the clock line, Space under it (press and release frames apart)
##     neither releases the hold nor closes it (V5.1-0c's bug), and a real click on
##     Continue gives a running clock back;
##   - with an interrupt on the desk the read's closing button reads "Next: <event>",
##     and closing leaves the clock held and the inbox up;
##   - the front page waits on the count's plate only, never on the briefing; out of
##     office there is no mark;
##   - no stale line: a request answered in the inbox leaves the mark at once, and the
##     chief's line is not turned by it;
##   - key 1 is the read's first Go; a load takes the read, the mark and the caption down.

const Click = preload("res://tests/click.gd")
const Programme = preload("res://src/sim/programme.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const PriorityWords = preload("res://src/ui/priority_words.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const RequestLane = preload("res://src/ui/request_lane.gd")
const InboxFiles = preload("res://src/ui/inbox_files.gd")

const CONSEQUENCE := "G1 consequence note"
const ECHO := "G1 echo of a lapse"

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
		_check_month_end()
		_target = _main._hud.title_bar.chief_mark
		Click.half(_main.get_viewport(), _target, true)
		_phase = 2
	elif _phase == 2:
		Click.half(_main.get_viewport(), _target, false)
		_phase = 3
	elif _phase == 3:
		_check_opened()
		_key(KEY_SPACE, true)
		_phase = 4
	elif _phase == 4:
		_key(KEY_SPACE, false)
		_phase = 5
	elif _phase == 5:
		if not _card.visible or not _main._clock.paused:
			_fail("Space under the read released it (card %s, paused %s)" % [_card.visible, _main._clock.paused])
		_target = _card._close
		Click.half(_main.get_viewport(), _target, true)
		_phase = 6
	elif _phase == 6:
		Click.half(_main.get_viewport(), _target, false)
		_phase = 7
	elif _phase == 7:
		_check_continue()
		_check_next_on_interrupt()
		_check_plate_and_defeat()
		_check_no_stale_line()
		_check_key_go()
		_check_after_load()
		_finish()
		return true
	return false


func _start() -> void:
	var ns = _main._state.player()
	var offer: Array = Programme.available(_main._state, ns, _main._loader)
	if not offer.is_empty():
		_main._on_programme_chosen(String(offer[0]["id"]))
	_card = BriefingDriver.card_of(_main)
	if _card == null:
		_fail("no briefing card registered")
		_finish()
		return
	ns.event_queue.clear()
	_main._unseen_events.clear()
	BriefingDriver.hold_card(_main, {"title": CONSEQUENCE, "body": "x", "tone": ""})
	# A month only the clock decided: the ledger's echo of the lapse card stays out.
	BriefingDriver.hold_card(_main, {"title": ECHO, "body": "Since then", "tone": "", "since": "Since then"})
	_main._clock.paused = false
	var state = _main._state
	var next: int = int(state.year) * 12 + int(state.month) + 1
	var year := floori((next - 1) / 12.0)
	_main._on_month_elapsed(year, next - year * 12)
	_phase = 1


func _check_month_end() -> void:
	if _card.visible:
		_fail("the month end opened the briefing by itself")
	var holds: bool = _main._decision_holds_clock() or _main._paused_for_programme
	if _main._clock.paused and not holds:
		_fail("the month end paused the clock with nothing else holding it")
	if not _main._hud.title_bar.chief_mark.visible:
		_fail("the month end left no chief's mark")
	if not _shows(_main._hud.inbox, CONSEQUENCE.to_upper()) and not _shows(_main._hud.inbox, CONSEQUENCE):
		_fail("the month's consequence card is not in the inbox")
	if _shows(_main._hud.inbox, ECHO.to_upper()) or _shows(_main._hud.inbox, ECHO):
		_fail("the ledger's echo of a lapse reached the inbox beside the lapse card")


func _check_opened() -> void:
	if not _card.visible:
		_fail("a click on the mark did not open the read")
	if not _main._clock.paused:
		_fail("the read does not hold the clock")
	var line := String(_main._hud.clock_cluster._reason.text)
	if not line.contains("briefing"):
		_fail("the clock line does not name the briefing: '%s'" % line)


func _check_continue() -> void:
	var holds: bool = _main._decision_holds_clock() or _main._paused_for_programme
	if _card.visible:
		_fail("a click on the closing button did not close the read")
	if holds == (not _main._clock.paused):
		_fail("after the read, the clock is %s while another hold is %s" % ["paused" if _main._clock.paused else "running", holds])


func _check_next_on_interrupt() -> void:
	var ns = _main._state.player()
	var ev = _main._loader.events[0]
	ns.event_queue.append({"event_id": String(ev.id), "event_name": ev.event_name, "months_left": 2,
		"interrupt": true, "severity": 3, "category": ev.category})
	_main._clock.paused = false
	BriefingDriver.read(_main)
	if not String(_card._close.text).begins_with("Next:"):
		_fail("with an interrupt held the closing button reads '%s', not 'Next: ...'" % _card._close.text)
	BriefingDriver.close(_main)
	if not _main._clock.paused:
		_fail("closing the read released an interrupt's hold")
	if not _main._hud.inbox.visible:
		_fail("closing the read did not bring up the held card's inbox")
	ns.event_queue.clear()
	_main._clock.paused = false


func _check_plate_and_defeat() -> void:
	if BriefingDriver.plate_for(_main, {"election_results": []}) != null:
		_fail("the front page waits for the briefing, which no longer opens by itself")
	if BriefingDriver.plate_for(_main, {"election_results": [{}]}) != _main._election_panel:
		_fail("the front page does not wait for the count's plate")
	var ns = _main._state.player()
	ns.in_government = false
	BriefingDriver.month_end(_main, {})
	if _main._hud.title_bar.chief_mark.visible or _card.visible:
		_fail("out of office, the chief's mark or read is still up")
	ns.in_government = true
	BriefingDriver._games[_main.get_instance_id()]["pending"] = {}
	BriefingDriver.month_end(_main, {})


## The brief's new row: a request on the mark, declined in the inbox, leaves the mark at
## once; the month's chief line (its turn) is not moved by the re-rank.
func _check_no_stale_line() -> void:
	var ns = _main._state.player()
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	ns.event_queue.clear()
	_main._unseen_events.clear()
	var now := int(_main._state.year) * 12 + int(_main._state.month)
	var pid := ""
	for person in _main._loader.people[String(ns.id)]:
		if String(person.kind) == "politician" and String(person.id) != preload("res://src/sim/president.gd").leader_id(ns):
			pid = String(person.id)
			break
	var rid := "%s|%d" % [pid, now]
	ns.audience_requests.append({"id": rid, "person_id": pid, "object": "programme:none", "stance": "sponsor",
		"arrived_month": now, "deadline_month": now, "status": "pending", "date": {}, "resolved_month": -1})
	AudienceDriver.refresh(_main)
	game["pending"] = {}
	BriefingDriver.month_end(_main, {})
	var mark = _main._hud.title_bar.chief_mark
	var named: bool = (game["lines"] as Array).any(func(l): return String(l["subject"]) == rid)
	if not named or String(game["lines"][0]["subject"]) != rid:
		_fail("premise: the request due now is not the first line (%s)" % str((game["lines"] as Array).map(func(l): return l["subject"])))
		return
	# A line due this month wears the WARN tone on its chip, with its words (GLM's gap 5).
	if mark._chip.theme_type_variation != preload("res://src/ui/ui_theme.gd").WARN_TEXT:
		_fail("the mark's chip for a line due now is not WARN ('%s')" % mark._chip.theme_type_variation)
	var before: String = mark.title_text()
	var turns: Dictionary = (game["turns"] as Dictionary).duplicate()
	var card_id := String(AudienceDriver.lane_of(_main).card_of(rid))
	if card_id == "" or not InboxFiles.press(_main._hud.inbox, card_id, RequestLane.DECLINE):
		_fail("premise: the request could not be declined in the inbox (card '%s')" % card_id)
		return
	if (game["lines"] as Array).any(func(l): return String(l["subject"]) == rid):
		_fail("the declined request is still among the month's lines")
	if mark.title_text() == before:
		_fail("the mark still names the declined request: '%s'" % before)
	if game["turns"] != turns:
		_fail("answering a file turned the chief's line: %s -> %s" % [turns, game["turns"]])
	# A month with no line at all (no vote dated, nothing real): the mark says so, no chip
	# (GLM's gap 3).
	game["lines"] = []
	preload("res://src/ui/chief_mark_view.gd").refresh(_main)
	if mark.title_text() != tr("A quiet month") or mark.chip_text() != "":
		_fail("a month with no line: the mark reads '%s' / '%s'" % [mark.title_text(), mark.chip_text()])


func _check_key_go() -> void:
	# A desk with no file: a file's Go opens its page inside the read and keeps it up.
	var ns = _main._state.player()
	ns.audience_requests.clear()
	ns.event_queue.clear()
	_main._unseen_events.clear()
	AudienceDriver.refresh(_main)
	_main._clock.paused = false
	BriefingDriver.read(_main)
	if not _card.visible:
		_fail("premise: the read did not open for the key check")
		return
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	_card._input(key)
	if _card.visible and _card.go_buttons.size() > 0:
		_fail("key 1 did not take the first line's Go")
	BriefingDriver.close(_main)


## QA's RECORD on #218: a load with the read up kept the discarded game's card and its
## was_running. The load's own restore path brings down the read and the caption; the mark
## is the loaded game's, ranked at the load from no memory (#393 pass 2, T2).
func _check_after_load() -> void:
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	_main._clock.paused = false
	BriefingDriver.read(_main)
	if not _card.visible:
		_fail("premise: the read did not open before the load")
	game["lines"] = [{"kind": "stale", "subject": "stale", "standing": false, "held": false}]
	preload("res://src/ui/desk_cards.gd").restore_after_load(_main)
	var fresh: Array = preload("res://src/ui/chief_mark_view.gd").rank(_main, {})["lines"]
	if _card.visible or bool(game["was_running"]) or (game["lines"] as Array).size() != fresh.size() 			or (game["lines"] as Array).any(func(l): return String(l["kind"]) == "stale"):
		_fail("a load left the discarded game's briefing (card %s, was_running %s, lines %d of %d)" % [
			_card.visible, game["was_running"], (game["lines"] as Array).size(), fresh.size()])
	if _main._hud.chief_caption.visible:
		_fail("a load left the discarded game's caption up")
	if bool(_main._state.player().in_government) and not _main._hud.title_bar.chief_mark.visible:
		_fail("after a load the loaded game's mark is blank")


func _shows(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text and (node as Label).is_visible_in_tree():
		return true
	for child in node.get_children():
		if _shows(child, text):
			return true
	return false


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
