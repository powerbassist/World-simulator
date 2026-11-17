extends SceneTree

## Headless test: godot --headless --script res://tests/test_briefing_hold.gd
## Non-zero exit on any failure.
##
## G1, the chief off the clock (chief-briefing-brief.md, "What must hold"), and G2, his plate
## retired (rework 2 S2), through the real game:
##   - a month run by the game's own month (main._on_month_elapsed) ends with no pause; the
##     chief's mark names the month, and the month's consequence card is among the inbox's
##     news (no card says it now);
##   - a real click on the mark opens the read he was asked for, the Presidency page, and
##     the clock runs on: no clock line names a briefing;
##   - the front page waits on the count's plate only, never on the briefing; out of
##     office there is no mark;
##   - no stale line: a request answered in the inbox leaves the mark at once, and the
##     chief's line is not turned by it;
##   - a load takes the mark's discarded lines and the caption down.

const Click = preload("res://tests/click.gd")
const Programme = preload("res://src/sim/programme.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const ChiefMarkView = preload("res://src/ui/chief_mark_view.gd")
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
		_check_plate_and_defeat()
		_check_no_stale_line()
		_check_after_load()
		_finish()
		return true
	return false


func _start() -> void:
	var ns = _main._state.player()
	var offer: Array = Programme.available(_main._state, ns, _main._loader)
	if not offer.is_empty():
		_main._on_programme_chosen(String(offer[0]["id"]))
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
	var holds: bool = _main._decision_holds_clock() or _main._paused_for_programme
	if _main._clock.paused and not holds:
		_fail("the month end paused the clock with nothing else holding it")
	if not _main._hud.title_bar.chief_mark.visible:
		_fail("the month end left no chief's mark")
	var news: Array = _main._hud.inbox.notes().map(func(n): return String(n["title"]))
	if not news.has(CONSEQUENCE):
		_fail("the month's consequence card is not among the inbox's news: %s" % [news])
	if news.has(ECHO):
		_fail("the ledger's echo of a lapse reached the inbox beside the lapse card")


## G2: the mark opens the Presidency page, whose lead is his read, and the clock runs on.
func _check_opened() -> void:
	if not _main._windows.is_open("overview"):
		_fail("a click on the mark did not open the Presidency page")
	if _main._clock.paused and not (_main._decision_holds_clock() or _main._paused_for_programme):
		_fail("the read paused the clock")
	var line := String(_main._hud.clock_cluster._reason.text)
	if line.contains("briefing"):
		_fail("the clock line still names a briefing: '%s'" % line)


func _check_plate_and_defeat() -> void:
	if BriefingDriver.plate_for(_main, {"election_results": []}) != null:
		_fail("the front page waits for the briefing, which no longer opens by itself")
	if BriefingDriver.plate_for(_main, {"election_results": [{}]}) != _main._election_panel:
		_fail("the front page does not wait for the count's plate")
	var ns = _main._state.player()
	ns.in_government = false
	BriefingDriver.month_end(_main, {})
	if _main._hud.title_bar.chief_mark.visible:
		_fail("out of office, the chief's mark is still up")
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
	# The re-rank runs at the frame's end (ChiefMarkView.follow): run it now.
	if _main.has_meta(ChiefMarkView.RERANK_QUEUED):
		ChiefMarkView._rerank_queued(_main)
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


## QA's RECORD on #218: a load kept the discarded game's lines. The load's own restore path
## brings down the caption; the mark is the loaded game's, ranked at the load from no memory
## (#393 pass 2, T2).
func _check_after_load() -> void:
	var game: Dictionary = BriefingDriver._games[_main.get_instance_id()]
	_main._clock.paused = false
	game["lines"] = [{"kind": "stale", "subject": "stale", "standing": false, "held": false}]
	preload("res://src/ui/desk_cards.gd").restore_after_load(_main)
	var fresh: Array = preload("res://src/ui/chief_mark_view.gd").rank(_main, {})["lines"]
	if (game["lines"] as Array).size() != fresh.size() or (game["lines"] as Array).any(func(l): return String(l["kind"]) == "stale"):
		_fail("a load left the discarded game's lines (%d of %d)" % [(game["lines"] as Array).size(), fresh.size()])
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
