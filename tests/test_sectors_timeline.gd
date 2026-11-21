extends SceneTree

## Headless test: godot --headless --script res://tests/test_sectors_timeline.gd
## Non-zero exit on any failure.
##
## G3 S3, the Sectors overview "C La frise": every running thing is a dated row on one time
## scale (sectors_timeline.gd), the picked row's decision is answered in the side sheet
## (sectors_decision.gd). Checked against the sim: a stake whose price waits on the player,
## a plant closure announced, a failing major's rescue window and a sector programme each
## make one row, with the months to its answer and to its end the sim's own; the waiting rows
## come first and the soonest answer is the one the sheet opens on; a row picked opens its
## own decision, and an answer pressed there reaches the sim. A quiet world says so.

const Companies = preload("res://src/sim/companies.gd")
const Processes = preload("res://src/sim/processes.gd")
const ProcessAsks = preload("res://src/sim/process_asks.gd")
const Closures = preload("res://src/sim/closures.gd")
const SectorsTimeline = preload("res://src/ui/sectors_timeline.gd")
const SectorProgramme = preload("res://src/ui/sector_programme.gd")
const TimelineBar = preload("res://src/ui/timeline_bar.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _stake := ""
var _closing := ""
var _failing := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._companies_panel
			_main._windows.open("companies")
			_check_dates()
		4:
			_check_quiet()
			_stage()
		6:
			_check_rows()
			_check_page()
			_press(_with_meta("timeline_pick", "closure|%s" % _closing_id()))
		8:
			_check_picked_closure()
			_press(_with_meta("timeline_pick", "process|%s" % _process_id()))
		10:
			_press(_with_meta("answer_id", "accept"))
		12:
			var row := Processes.live(_main._state.player(), _stake)
			if String(row.get("answer", "")) != "accept":
				_fail("Accept pressed in the side sheet did not reach the sim: %s" % row.get("answer", "none"))
			_check_choose_order()
			_finish()
	return false


## date_in: the first day of month now + n, across a year's end.
func _check_dates() -> void:
	var state = _main._state
	var keep := [state.year, state.month]
	state.year = 2027
	state.month = 12
	var want := "%s %s" % [DateText.weekday(1, 1, 2028), DateText.day_mon(1, 1)]
	if SectorsTimeline.date_in(state, 1) != want:
		_fail("date_in(Dec 2027, 1) is '%s', want '%s'" % [SectorsTimeline.date_in(state, 1), want])
	state.year = keep[0]
	state.month = keep[1]


func _check_quiet() -> void:
	var rows := SectorsTimeline.rows(_main._state, _main._loader, _main._state.player())
	if not rows.is_empty():
		_fail("a fresh game already has %d timeline rows: %s" % [rows.size(), rows.map(func(r): return r["key"])])
	var lead = _node_with_meta("timeline", "lead")
	if lead == null or (lead as Label).text != Strings.t("Nothing is under way."):
		_fail("the quiet timeline's lead is not 'Nothing is under way.'")
	if _node_with_meta("decision", "") == null:
		_fail("the quiet side sheet is missing")


## A stake asking its price, a plant closure, a failing major, an Industry programme.
func _stage() -> void:
	var state = _main._state
	var ns = state.player()
	var now: int = state.year * 12 + state.month
	var majors: Array = Companies.majors_of(_main._loader, ns.id)
	var stake = _action("minority_stake")
	for company in majors:
		if bool(Processes.start(state, ns, _main._loader, stake, String(company.id)).get("applied", false)):
			_stake = String(company.id)
			var row := Processes.live(ns, _stake)
			row["stage"] = "negotiation"
			row["months_left"] = 1
			ProcessAsks.post(ns, row, stake, now, company)
			break
	for company in majors:
		if String(company.id) != _stake and _closing == "" and ns.companies.has(company.id):
			Closures._announce(ns, company, ns.companies[company.id], 0.2, _main._loader.closure_rule, now)
			_closing = String(company.id)
		elif String(company.id) not in [_stake, _closing] and _failing == "" and ns.companies.has(company.id):
			ns.companies[company.id]["failed"] = true
			ns.companies[company.id]["rescue_months_left"] = 5
			_failing = String(company.id)
	var stops: Array = SectorProgramme.stops(_main._loader, "industry")
	ns.sector_investment["industry"] = {"intensity": float(stops[1]["intensity"]), "capital": 0.0}
	_panel.mark_dirty()


func _check_rows() -> void:
	var state = _main._state
	var ns = state.player()
	var now: int = state.year * 12 + state.month
	var rows := SectorsTimeline.rows(state, _main._loader, ns)
	var by_kind := {}
	for r in rows:
		by_kind[String(r["kind"])] = r
	if _stake == "" or not by_kind.has("ask"):
		_fail("setup: no stake asking its price (%s)" % [by_kind.keys()])
		return
	var ask: Dictionary = by_kind["ask"]
	if int(ask["due"]) != 1 or not bool(ask["waits"]) or String(ask["style"]) != TimelineBar.DUE:
		_fail("the stake's ask: due %d, waits %s, style %s (want 1, true, due)" % [int(ask["due"]), ask["waits"], ask["style"]])
	var closure: Dictionary = by_kind.get("closure", {})
	var due := int(Closures.announced(ns, _closing).get("due", now)) - now
	if closure.is_empty() or int(closure["due"]) != due or String(closure["bad"]) == "":
		_fail("the closure row: %s (want due %d and its 'unanswered, it shuts')" % [closure, due])
	var failing: Dictionary = by_kind.get("failing", {})
	if failing.is_empty() or int(failing["ends"]) != 5 or String(failing["style"]) != TimelineBar.WINDOW or int(failing["due"]) != -1:
		_fail("the rescue window: %s (want ends 5, a window, no answer date)" % [failing])
	var programme: Dictionary = by_kind.get("programme", {})
	if programme.is_empty() or int(programme["ends"]) != -1 or String(programme["style"]) != TimelineBar.RUNNING:
		_fail("the Industry programme: %s (want an open-ended running bar)" % [programme])
	# Waiting rows first, the soonest answer first.
	var seen_quiet := false
	for r in rows:
		if not bool(r["waits"]):
			seen_quiet = true
		elif seen_quiet:
			_fail("a waiting row (%s) sits under a row that waits for nothing" % r["key"])
	if String(rows[0]["key"]) != String(ask["key"]):
		_fail("the first row is %s, the soonest answer is the stake's %s" % [rows[0]["key"], ask["key"]])


func _check_page() -> void:
	var rows := SectorsTimeline.rows(_main._state, _main._loader, _main._state.player())
	for r in rows:
		if _node_with_meta("timeline_row", String(r["key"])) == null:
			_fail("no timeline row on screen for %s" % r["key"])
	var lead = _node_with_meta("timeline", "lead")
	var waiting := rows.filter(func(r): return bool(r["waits"])).size()
	if lead == null or not (lead as Label).text.begins_with("%d " % waiting):
		_fail("the lead '%s' does not count the %d answers due" % [lead.text if lead != null else "", waiting])
	# The sheet opens on the soonest answer: the stake's, with its answers.
	if _node_with_meta("decision", "process|%s" % _process_id()) == null:
		_fail("the side sheet did not open on the stake's ask")
	if _with_meta("answer_id", "accept") == null:
		_fail("the stake's Accept is not in the side sheet")
	var chip := Strings.t("answer by %s") % SectorsTimeline.date_in(_main._state, 1)
	var lane = _node_with_meta("timeline_row", "process|%s" % _process_id())
	if lane == null or not _text_under(lane).contains(chip):
		_fail("the stake's lane does not carry '%s'" % chip)


func _check_picked_closure() -> void:
	if _node_with_meta("decision", "closure|%s" % _closing_id()) == null:
		_fail("picking the closure's row did not open its sheet")
	var answers: Array = _panel._side.find_children("*", "Button", true, false).filter(func(b): return b.has_meta("closure_answer"))
	if answers.is_empty():
		_fail("the closure's sheet has no answers")
	var plate = _node_with_meta("timeline_row", "closure|%s" % _closing_id())
	if plate == null or not plate is PanelContainer:
		_fail("the picked row does not sit on a tile")


## The side sheet's row: the player's pick, then a waiting row, then the row last answered
## (it stays once it stops waiting), then the first.
func _check_choose_order() -> void:
	var held: Array = [_panel._pick, _panel._held, _panel._open_firm]
	_panel._pick = ""
	_panel._open_firm = ""
	_panel._held = "c"
	var rows := [{"key": "a", "company_id": "", "waits": false}, {"key": "b", "company_id": "", "waits": true},
		{"key": "c", "company_id": "", "waits": false}]
	if String(_panel._choose(rows)["key"]) != "b":
		_fail("choose: a waiting row did not come before the one answered")
	rows[1]["waits"] = false
	if String(_panel._choose(rows)["key"]) != "c":
		_fail("choose: the row answered did not stay on the sheet once it stopped waiting")
	_panel._pick = "a"
	if String(_panel._choose(rows)["key"]) != "a":
		_fail("choose: the player's pick did not come first")
	_panel._pick = held[0]
	_panel._held = held[1]
	_panel._open_firm = held[2]


func _process_id() -> String:
	return String(Processes.live(_main._state.player(), _stake).get("id", ""))


func _closing_id() -> String:
	return String(Closures.announced(_main._state.player(), _closing).get("id", ""))


func _action(id: String):
	for a in _main._loader.company_actions:
		if String(a.id) == id:
			return a
	return null


func _node_with_meta(key: String, value: String):
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta(key) and String(node.get_meta(key)) == value and (node as Control).is_visible_in_tree() and not node.is_queued_for_deletion():
			return node
	return null


func _with_meta(key: String, value: String):
	for b in _panel.find_children("*", "Button", true, false):
		if b.has_meta(key) and String(b.get_meta(key)) == value and (b as Control).is_visible_in_tree() and not b.is_queued_for_deletion():
			return b
	return null


func _press(button) -> void:
	if button == null:
		_fail("frame %d: the control to press is not on screen" % _frame)
		return
	(button as Button).pressed.emit()


func _text_under(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_sectors_timeline: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: " + f)
		quit(1)
