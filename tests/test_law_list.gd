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
const UiTheme = preload("res://src/ui/ui_theme.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const LawPath = preload("res://src/ui/law_path.gd")
const ChartDiverge = preload("res://src/ui/chart_diverge.gd")
const ControlStyle = preload("res://src/ui/control_style.gd")
const LawRow = preload("res://src/ui/law_row.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Chambers = preload("res://src/sim/chambers.gd")
const ChambersK = preload("res://src/sim/chambers_constants.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const JudiciaryK = preload("res://src/sim/judiciary_constants.gd")

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
			_check_bills_page()
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
			_check_picked_row_ground()
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
	# What waits after the Assembly reads on the sheet's path: some law of the shelf meets a
	# second chamber or the court, and its sheet prints that step's word.
	for law in shown:
		var steps: Array = LawPath.steps(ns, _laws()._party_list, law, _laws().counts_of(ns, _laws()._party_list, law))
		if steps.size() > 1 and _laws().why(law) == "":
			_laws().select(String(law.id))
			if not _text(_laws()._detail).contains(String(steps[1]["word"])):
				_fail("%s: the sheet does not print '%s'" % [law.id, steps[1]["word"]])
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
	if not text.contains(tr("Undecided")) or not text.contains(tr("Against")):
		_fail("the detail does not spell the vote out")


## G3 S5, Bills = C (the law's path): the page lays out its own sheets; the order paper is one slim
## line; the open law's path has a step per hurdle BY RULE (the Assembly always, the second chamber
## when it has a say on this law, the court when it reviews it); the Assembly's vote is a chamber of
## three parts in the vote's tones; Propose is the one filled verb.
func _check_bills_page() -> void:
	var panel = _main._law_panel
	var ns = _main._state.player()
	if panel.theme_type_variation != UiTheme.BARE or not WindowManager.OWN_SHEETS.has("legislature"):
		_fail("Bills does not lay out its own sheets (BARE + OWN_SHEETS)")
	var paper: Control = panel._paper
	var tall := 0.0
	for place in paper.places:
		tall = maxf(tall, (place as Control).size.y)
	if paper.places.is_empty() or tall > 44.0 * UiTheme.text_scale():
		_fail("the order paper is not one slim line: its places stand %.0f px tall" % tall)
	var law = _laws()._shown[0]
	_laws().select(String(law.id))
	var path: Node = _laws()._detail.find_child("Path", true, false)
	var want: Array = ["assembly"]
	if Chambers.power_over(ns, law) != ChambersK.VERDICT_NONE:
		want.append("upper")
	if Judiciary.reviews(ns, law):
		want.append("court")
	var steps: Array = LawPath.steps(ns, _laws()._party_list, law, _laws().counts_of(ns, _laws()._party_list, law))
	if path == null or steps.map(func(s): return s["slot"]) != want or path.get_child_count() != want.size() * 2 - 1:
		_fail("the law's path is not its hurdles by rule: %s, want %s" % [steps.map(func(s): return s["slot"]), want])
	_check_path_tiles(steps)
	_check_scroll_clip_leaves_room()
	# A nation with fewer hurdles: no second chamber's say and no review, the Assembly alone.
	var saved := [ns.upper_ordinary, ns.upper_amendment, ns.judicial_review]
	ns.upper_ordinary = ChambersK.VERDICT_NONE
	ns.upper_amendment = ChambersK.VERDICT_NONE
	ns.judicial_review = JudiciaryK.REVIEW_NONE
	var alone: Array = LawPath.steps(ns, _laws()._party_list, law, _laws().counts_of(ns, _laws()._party_list, law))
	if alone.map(func(s): return s["slot"]) != ["assembly"]:
		_fail("with no second chamber and no review the path still reads %s" % [alone.map(func(s): return s["slot"])])
	ns.upper_ordinary = saved[0]
	ns.upper_amendment = saved[1]
	ns.judicial_review = saved[2]
	var chamber: Array = _laws()._detail.find_children("*", "Control", true, false).filter(func(c): return c.has_method("seat_count"))
	if chamber.size() != 1 or chamber[0]._colors.slice(0, 3) != [UiTheme.GOOD, LawList.UNDECIDED, UiTheme.BAD] 			or chamber[0]._parts.size() != 3 or not chamber[0].has_marker():
		_fail("the Assembly's vote is not one chamber of for / undecided / against with its line")
	var filled: Array = _laws()._detail.find_children("*", "Button", true, false).filter(
		func(b): return b.visible and b.theme_type_variation == UiTheme.PRIMARY)
	if filled.size() != 1 or not (filled[0].text.begins_with(tr("Propose").left(7)) or filled[0].name == "Queue"):
		_fail("the law's sheet has %d filled verbs, not one Propose: %s" % [filled.size(), filled.map(func(b): return b.text)])
	elif filled[0].get_index() != 0:
		_fail("the filled verb is not first in its row")
	# The in-flight sheet stands only while something is in flight (an empty sheet would float).
	var flight: Control = panel._flight.get_parent()
	if flight.visible != (panel._result_box.get_child_count() + panel._list.get_child_count() > 0):
		_fail("the in-flight sheet shows %s with %d things in flight" % [flight.visible, panel._result_box.get_child_count() + panel._list.get_child_count()])
	# A shut law has no division coming: no path, no address, no polls.
	for shut in _laws()._shown:
		if _laws().why(shut) != "":
			_laws().select(String(shut.id))
			for node_name in ["Path", "PollIt"]:
				if _laws()._detail.find_child(node_name, true, false) != null:
					_fail("%s is shut and its sheet still draws %s" % [shut.id, node_name])
			break


## Design's T1, T2 on #449: a hurdle's verdict is the lead size in its tone with a glyph, a plain word is never amber,
## the kill takes a BAD outline, the court carries its meter, and every tile holds its words 12 px inside.
## T10: the picked row's ground runs under the whole row -- name, summary and vote bar -- and the
## name and the summary start at one x. The rows that are not picked wear no ground.
func _check_picked_row_ground() -> void:
	var grounds := 0
	for row in _rows():
		var picked: bool = (row.get_meta("pick") as Button).button_pressed
		var has_ground: bool = row is PanelContainer and String((row as Control).theme_type_variation) == UiTheme.TILE_PANEL
		if has_ground != picked:
			_fail("a row is %s and %s a ground" % ["picked" if picked else "not picked", "has" if has_ground else "has not"])
		if not picked:
			continue
		grounds += 1
		var rect := (row as Control).get_global_rect()
		var name_button: Button = row.get_meta("pick")
		var under := row.find_child("Under", true, false) as Control
		if not rect.encloses(name_button.get_global_rect()) or not rect.encloses(under.get_global_rect()):
			_fail("the picked row's ground does not reach its name and its summary")
		for bar in row.find_children("*", "", true, false).filter(func(c): return c is ChartStack):
			if not rect.encloses((bar as Control).get_global_rect()):
				_fail("the picked row's ground stops short of its vote bar")
		var name_x := name_button.get_global_position().x + name_button.get_theme_stylebox("normal").content_margin_left
		var summary_x: float = (under.get_child(0) as Control).get_global_position().x
		if absf(name_x - summary_x) > 0.5:
			_fail("the picked row's name starts at %.1f and its summary at %.1f" % [name_x, summary_x])
	if grounds != 1:
		_fail("%d rows carry the picked ground, not one" % grounds)
	# T1 (#451): the name wears no ground of its own while the row's ground is there; T2: the rows'
	# padding and the list's gap come to main's 10 px between rows; the ground follows a pick.
	for row in _rows():
		var picked_row: bool = (row.get_meta("pick") as Button).button_pressed
		var name_button: Button = row.get_meta("pick")
		var on := name_button.get_theme_stylebox("pressed") as StyleBoxFlat
		if picked_row and (String(name_button.theme_type_variation) != UiTheme.PICKED_NAME or on.bg_color.a > 0.0):
			_fail("the picked row's name still draws a ground of its own")
		if not picked_row and String(name_button.theme_type_variation) != UiTheme.PICKED_ROW:
			_fail("a row that is not picked wears '%s', not PICKED_ROW" % name_button.theme_type_variation)
	if _laws()._rows.get_theme_constant("separation") + 2 * LawRow.GROUND_PAD_V > 10:
		_fail("the rows' gap and padding come to more than main's 10 px between rows")
	var other := ""
	for row in _rows():
		if not (row.get_meta("pick") as Button).button_pressed:
			other = String(row.get_meta("law_id"))
			break
	if other != "":
		var before := _laws().selected_id()
		_laws().select(other)
		for row in _rows():
			var is_it := String(row.get_meta("law_id")) == other
			if (String((row as Control).theme_type_variation) == UiTheme.TILE_PANEL) != is_it:
				_fail("after a pick the ground did not follow it to %s" % other)
		_laws().select(before)


## T14 (the author: "the blur around the blue button is cropped"): a filled press on the sheet's
## edge has its glow and its focus ring inside the scroll's clip. The content keeps its x; the clip
## opens GLOW_ROOM px past it on each side, still inside the sheet.
func _check_scroll_clip_leaves_room() -> void:
	for box in [_laws()._rows, _laws()._detail]:
		var scroll := _laws().scroll_of(box)
		if scroll == null:
			_fail("a Bills column is not a scroll over its box")
			continue
		var sheet: Control = scroll
		while sheet != null and String(sheet.theme_type_variation) != UiTheme.PLATE:
			sheet = sheet.get_parent() as Control
		var room_left: float = (box as Control).global_position.x - scroll.global_position.x
		var room_right: float = scroll.get_global_rect().end.x - (box as Control).get_global_rect().end.x
		if room_left < LawList.GLOW_ROOM - 0.5:
			_fail("a column's content starts %.1f px inside its clip: a filled press there loses its glow" % room_left)
		if sheet != null and scroll.get_global_rect().end.x > sheet.get_global_rect().end.x + 0.5:
			_fail("a column's scroll bar leaves its sheet (%.1f px)" % (scroll.get_global_rect().end.x - sheet.get_global_rect().end.x))
		if room_right < 0.0:
			_fail("a column's content runs past its clip")


func _check_path_tiles(steps: Array) -> void:
	for step in steps:
		var tone := Color(step["tone"])
		if tone == UiTheme.WARN:
			_fail("the %s step's word '%s' is amber: amber is what waits on the player, with a date" % [step["slot"], step["word"]])
		var glyph := "check" if tone == UiTheme.GOOD else ("warning" if tone == UiTheme.BAD else "")
		if String(step["glyph"]) != glyph or bool(step["fails"]) != (tone == UiTheme.BAD):
			_fail("the %s step has glyph '%s' and fails=%s for tone %s" % [step["slot"], step["glyph"], step["fails"], tone])
		var tile: Node = _laws()._detail.find_child("Step_%s" % step["slot"], true, false)
		if tile == null:
			_fail("no tile for the %s step" % step["slot"])
			continue
		if String(tile.theme_type_variation) != (ControlStyle.TILE_FAILS if bool(step["fails"]) else UiTheme.TILE_PANEL):
			_fail("the %s tile wears %s: only a kill takes the outline" % [step["slot"], tile.theme_type_variation])
		if PanelKit.tile_body(tile).get_theme_constant("margin_left") != PanelKit.TILE_PAD:
			_fail("the %s tile's words sit on its edge, not %d px inside" % [step["slot"], PanelKit.TILE_PAD])
		if (tile.find_child("Glyph", true, false) != null) != (glyph != ""):
			_fail("the %s tile's glyph does not follow its verdict" % step["slot"])
		if (tile.find_child("CourtMeter", true, false) != null) != (step["slot"] == "court"):
			_fail("the %s tile and the court's meter: only the court shows what the law reaches against what it allows" % step["slot"])
	if ChartDiverge.colour_of(0.2) != UiTheme.GOOD or ChartDiverge.colour_of(-0.2) != UiTheme.BAD:
		_fail("a bloc's gain is not the vote's green and its loss the vote's red")
	for toggle_name in ["PollIt"]:
		var toggle: Button = _laws()._detail.find_child(toggle_name, true, false)
		if toggle != null and String(toggle.theme_type_variation) != ControlStyle.OPENER:
			_fail("%s, a verb that opens its own section, is armed (%s), not an opener" % [toggle_name, toggle.theme_type_variation])


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
