extends SceneTree

## Headless test: godot --headless --script res://tests/test_law_list.gd
## Non-zero exit on any failure.
##
## V5.2-0b, the Legislature as "Une ligne par loi + détail" (the author's call,
## docs/design/v5.2-legibility.md), as the Bills second pass lays it out (law_row.gd): one row
## per law of the open shelf -- the name, the summary, and an open law's forecast bar with the
## majority marked -- and the selected law's sheet beside the list: its summary in full, the vote
## spelled out with what waits after the division, the bloc chart, the verbs. A real click (press and release frames apart,
## the V5.1 dead-clicks rule) selects a row; the selection survives a refresh; the
## detail's Propose asks for the briefing as the old row's did.

const LawList = preload("res://src/ui/law_list.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Strings = preload("res://src/ui/strings.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _target: Button
var _target_id := ""
var _briefed := []


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._windows.open("legislature")
		6:
			_check_rows()
			_press(true)
		10:
			_press(false)
		13:
			_check_selected()
			_main._law_panel.mark_dirty()
		16:
			if _laws().selected_id() != _target_id:
				_fail("a refresh dropped the selection (%s, wanted %s)" % [_laws().selected_id(), _target_id])
			_check_polls_closed()
			_laws()._detail.find_child("PollIt", true, false).pressed.emit()
		20:
			_check_propose()
			_finish()
			return true
	return false


func _laws() -> LawList:
	return _main._law_panel._laws


func _rows() -> Array:
	return _laws()._rows.get_children()


func _check_rows() -> void:
	var ns = _main._state.player()
	var rows := _rows()
	if rows.size() < 3:
		_fail("the catalogue shows %d rows" % rows.size())
		return
	var shown: Array = _laws()._shown
	for i in rows.size():
		var law = shown[i]
		var bars: Array = rows[i].find_children("*", "", true, false).filter(func(c): return c is ChartStack)
		if _laws().why(law) != "":
			if not bars.is_empty():
				_fail("%s is shut and still draws a vote bar" % law.id)
			continue
		if bars.size() != 1 or not bars[0].has_marker():
			_fail("%s: an open row has no forecast bar with its majority marked" % law.id)
			continue
		# QA on #96: each row's majority line is the fraction the division itself uses
		# (legislature.gd reads law.majority), not a half for every ordinary law.
		var want := LK.ABSOLUTE_MAJORITY_FRACTION
		if String(law.majority) == "two_thirds":
			want = LK.TWO_THIRDS_MAJORITY_FRACTION
		elif String(law.majority) == "amendment":
			want = float(LK.AMENDMENT_RULE_FRACTIONS[String(ns.amendment_rule)])
		if absf(float(bars[0]._markers[0]) - want) > 1e-9:
			_fail("%s marks its majority at %.3f; the division needs %.3f" % [law.id, bars[0]._markers[0], want])
	# The third row's name button is the one the click will land on.
	_target = rows[2].get_meta("pick")
	for law in _main._loader.laws:
		if Strings.law_name(law) == _target.text:
			_target_id = String(law.id)
	if _target_id == "":
		_fail("the third row's button does not name a law: %s" % _target.text)
	# What waits after the Assembly reads on the sheet, not as a column: some law of the
	# shelf carries a second-chamber or court sentence, and its sheet prints it.
	var said := false
	for law in shown:
		var parts := LawList.after_parts(ns, _laws()._party_list, law, _main._law_panel.FORECAST_UNCERTAIN_BAND)
		if not parts.is_empty():
			_laws().select(String(law.id))
			said = _text(_laws()._detail).contains(String(parts[0]["text"]))
			if not said:
				_fail("%s: the sheet does not print '%s'" % [law.id, parts[0]["text"]])
			break
	_laws().select(String(shown[0].id))


func _press(down: bool) -> void:
	if _target == null:
		return
	Click.half(_main.get_viewport(), _target, down)


func _check_selected() -> void:
	if _laws().selected_id() != _target_id:
		_fail("a click held for frames on a row did not select it (%s, wanted %s)" % [_laws().selected_id(), _target_id])
		return
	var law = _main._law_panel._find_law(_target_id)
	var text := _text(_laws()._detail)
	if not text.contains(Strings.law_name(law)):
		_fail("the detail does not name the selected law")
	var summary: String = Strings.law_summary(law)
	if summary.length() > 20 and not text.contains(summary.left(20)):
		_fail("the detail does not carry the law's summary: %s" % summary.left(40))
	if not text.contains("to pass"):
		_fail("the detail does not spell the vote out")


## V5.3 screen 4 PR 2b: the sheet carries the briefing's price and polls inline, a poll bought there
## books the baseline the popup's does (`polled`), and Propose divides at once -- no popup between.
func _check_polls_closed() -> void:
	if _laws()._detail.find_child("BlocChart", true, false) == null:
		_fail("the sheet carries no bloc chart (the price, per bloc)")
	if _laws()._detail.find_child("AssemblyPoll", true, false) != null:
		_fail("the polls stand open before 'Poll it' was pressed")
	if _laws()._detail.find_child("PollIt", true, false) == null:
		_fail("the sheet has no 'Poll it'")


func _check_propose() -> void:
	var panel = _main._law_panel
	if not _text(_laws()._detail).to_lower().contains("the polls"):
		_fail("'Poll it' did not open the polls")
	var whip: Button = _laws()._detail.find_child("AssemblyPoll", true, false)
	if whip == null:
		_fail("the sheet has no assembly poll to commission")
	else:
		var polled := []
		panel.polled.connect(func(_before, label): polled.append(label))
		var debt: float = _main._state.player().debt_eur_bn
		whip.pressed.emit()
		if polled.size() != 1 or _main._state.player().debt_eur_bn <= debt:
			_fail("a poll bought on the sheet booked %d baselines and moved the debt %.6f" % [polled.size(), _main._state.player().debt_eur_bn - debt])
		# QA's M3 on #352: the end of the path -- main's handler queues the decision card the popup's
		# poll queues (main.gd connects the panel's `polled` to it).
		var carded: Array = _main._pending_effects.filter(func(e) -> bool: return String(e["label"]).begins_with("Commissioned an assembly poll: "))
		if carded.size() != 1:
			_fail("a poll bought on the sheet queued %d 'Commissioned an assembly poll' cards in main" % carded.size())
	panel.brief_requested.connect(func(law): _briefed.append(law.id))
	var proposed := []
	panel.proposed.connect(func(_before, law_name, _result): proposed.append(law_name))
	var propose: Button = null
	for b in _laws()._detail.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with("Propose"):
			propose = b
	if propose == null:
		_fail("the detail has no Propose")
		return
	propose.pressed.emit()
	var law = panel._find_law(_target_id)
	if proposed != [Strings.law_name(law)]:
		_fail("Propose in the detail divided %s, not the selected law" % [proposed])
	if not _briefed.is_empty():
		_fail("Propose in the detail still asks for the briefing popup")


func _text(node: Node) -> String:
	var out := ""
	if node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	elif node is Label or node is Button:
		out += String(node.text) + "\n"
	for child in node.get_children():
		out += _text(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_law_list: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
