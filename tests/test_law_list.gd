extends SceneTree

## Headless test: godot --headless --script res://tests/test_law_list.gd
## Non-zero exit on any failure.
##
## V5.2-0b, the Legislature as "Une ligne par loi + détail" (the author's call,
## docs/design/v5.2-legibility.md). One row per proposable law -- the name, two
## chips, a forecast bar with the majority marked, the second chamber's and the
## court's glyphs with their sentences on hover -- and the selected law's detail
## beside the list: its summary in full, the forecast and the after-the-division
## sentences spelled out, the verbs. A real click (press and release frames apart,
## the V5.1 dead-clicks rule) selects a row; the selection survives a refresh; the
## detail's Propose asks for the briefing as the old row's did.

const LawList = preload("res://src/ui/law_list.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Strings = preload("res://src/ui/strings.gd")
const Click = preload("res://tests/click.gd")
const LawColumns = preload("res://src/ui/law_columns.gd")

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
	var with_after := 0
	for row in rows:
		var bar: Node = null
		for child in row.get_children():
			if child is ChartStack:
				bar = child
			if child is Label and child.tooltip_text != "":
				with_after += 1
		if bar == null or not bar.has_marker():
			_fail("a row has no forecast bar with its majority marked")
			break
	if with_after == 0:
		_fail("no row carries a second-chamber or court glyph with its sentence on hover")
	_check_markers(ns, rows)
	_check_cells(ns, rows)
	# The third row's name button is the one the click will land on.
	_target = rows[2].get_child(0)
	for law in _main._loader.laws:
		if Strings.law_name(law) == _target.text:
			_target_id = String(law.id)
	if _target_id == "":
		_fail("the third row's button does not name a law: %s" % _target.text)


## Pass 2 on #220: the row's cells are exceptions only. A threshold above half is
## a figure (3/5), half is blank; a second chamber that blocks or a court that
## strikes shows its glyph, one expected to agree or let it stand is blank.
func _check_cells(ns, rows: Array) -> void:
	if LawColumns.threshold(LK.ABSOLUTE_MAJORITY_FRACTION) != "" or LawColumns.threshold(0.6) != "3/5":
		_fail("the threshold cell: half should be blank and 3/5 shown, got '%s' / '%s'" % [
			LawColumns.threshold(LK.ABSOLUTE_MAJORITY_FRACTION), LawColumns.threshold(0.6)])
	var laws: LawList = _laws()
	var counts := {"shown": 0, "blank": 0}
	for i in rows.size():
		var law = laws._shown[i]
		var cells: Array = rows[i].get_children()
		var at := cells.find(cells.filter(func(c): return c is ChartStack)[0])
		if cells[at - 1].text != LawColumns.threshold(LawList.majority_share(ns, law)):
			_fail("%s: its threshold cell reads '%s'" % [law.id, cells[at - 1].text])
		var slots := {"upper": cells[at + 1], "court": cells[at + 2]}
		for part in LawList.after_parts(ns, laws._party_list, law, _main._law_panel.FORECAST_UNCERTAIN_BAND):
			var quiet := bool(part.get("quiet", false))
			var text: String = slots[part["slot"]].text
			counts["blank" if quiet else "shown"] += 1
			if quiet and text != "":
				_fail("%s: an agreeing %s shows '%s', it should be blank" % [law.id, part["slot"], text])
			elif not quiet and text != String(part["glyph"]):
				_fail("%s: a blocking %s shows '%s', not its glyph" % [law.id, part["slot"], text])
	if int(counts["shown"]) == 0 or int(counts["blank"]) == 0:
		_fail("premise: the catalogue needs both a shown and a blank after-cell, got %s" % counts)


## QA on #96: each row's majority line is the fraction the division itself uses
## (legislature.gd reads law.majority), not a half for every ordinary law.
func _check_markers(ns, rows: Array) -> void:
	var shown: Array = _laws()._shown
	for i in rows.size():
		var law = shown[i]
		var want := LK.ABSOLUTE_MAJORITY_FRACTION
		if String(law.majority) == "two_thirds":
			want = LK.TWO_THIRDS_MAJORITY_FRACTION
		elif String(law.majority) == "amendment":
			want = float(LK.AMENDMENT_RULE_FRACTIONS[String(ns.amendment_rule)])
		for child in rows[i].get_children():
			if child is ChartStack and absf(float(child._markers[0]) - want) > 1e-9:
				_fail("%s marks its majority at %.3f; the division needs %.3f" % [law.id, child._markers[0], want])


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
	if not text.contains("Forecast:"):
		_fail("the detail does not spell the forecast out")


func _check_propose() -> void:
	_main._law_panel.brief_requested.connect(func(law): _briefed.append(law.id))
	var propose: Button = null
	for b in _laws()._detail.find_children("*", "Button", true, false):
		if (b as Button).text == "Propose":
			propose = b
	if propose == null:
		_fail("the detail has no Propose")
		return
	propose.pressed.emit()
	if _briefed != [_target_id]:
		_fail("Propose in the detail asked for %s, not the selected law" % [_briefed])


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
