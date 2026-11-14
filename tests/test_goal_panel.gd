extends SceneTree

## Headless test: godot --headless --script res://tests/test_goal_panel.gd
## Non-zero exit on any failure.
##
## V5.3 screen 4, the goal panel (goal_panel.gd, goal_rows.gd): the Bills tab opens on the goals
## the player is judged on and what moves the picked one. The numbers are GoalRead's, pinned in
## tests/test_goal_read.gd; pinned here is what the screen does with them: the tiles, the list
## filling a measure a frame, a row per ranked measure with its figure and its state, a measure
## that cannot be tabled now greyed with its reason (a bill in the slot), a press on a row, and
## the catalogue one press away.

const GoalRead = preload("res://src/sim/goal_read.gd")
const GoalRows = preload("res://src/ui/goal_rows.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _phase := 0
var _waited := 0
var _went := []
var _bloc_first := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _goals():
	return _main._law_panel.find_child("Goals", true, false)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main._windows.open("legislature")
		_goals().go_requested.connect(func(id: String) -> void: _went.append(id))
		return false
	if _frame < 4:
		return false
	# One phase a frame: the panel redraws on its own _process, a frame after what changed.
	match _phase:
		0:
			_wait_for_the_read()
		1:
			_check_the_rows()
			_goals()._tiles.get_child(1).pressed.emit()
			_phase = 2
		2:
			_check_unemployment()
			_main._state.player().tabled_bill = {"law_id": "carbon_levy", "vote_year": 2026, "vote_month": 1, "vote_day": 31}
			_phase = 3
		3:
			_check_a_bill_in_the_slot_greys_rows()
			_main._state.player().tabled_bill = {}
			_goals()._pick_goal("deficit")
			_phase = 4
		4:
			# QA on #358: a second press on the bloc tile walks to the next bloc, it does not drop the goal.
			_goals()._tiles.get_child(2).pressed.emit()
			_phase = 5
		5:
			_bloc_first = _goals().goal
			_goals()._tiles.get_child(2).pressed.emit()
			_phase = 6
		6:
			_check_the_bloc_tile_walks()
			_goals()._pick_goal("deficit")
			_phase = 7
		7:
			_check_a_press()
			_check_the_catalogue()
			_finish()
	return false


func _tile_goals() -> Array:
	return _goals()._tiles.get_children().map(func(t): return t.goal)


func _wait_for_the_read() -> void:
	var goals = _goals()
	if goals == null:
		_fail("the Bills tab has no goal panel")
		_finish()
		return
	var read = goals._read
	if read != null and read.done() and goals._stamp != "":
		_phase = 1
		return
	_waited += 1
	if _waited > 900:
		_fail("the list of measures never finished reading")
		_finish()
		return
	# While it fills, the page says how far it has got.
	if read != null and not read.done() and _waited == 6 and not _box_text().contains("/"):
		_fail("a list still being read does not say how far it has got: '%s'" % _box_text())


func _box_text() -> String:
	var out := ""
	for node in _goals()._box.find_children("*", "Label", true, false):
		out += (node as Label).text + "\n"
	return out


func _check_the_rows() -> void:
	var goals = _goals()
	var tiles := _tile_goals()
	if tiles.size() < 3 or not tiles.has("deficit") or not tiles.has("unemployment"):
		_fail("the goal tiles are %s: expected the deficit, unemployment and a bloc" % [tiles])
	if not (tiles.size() > 2 and String(tiles[2]).begins_with("bloc:")):
		_fail("the third tile is not a bloc: %s" % [tiles])
	if goals.goal != "deficit" or not (goals._tiles.get_child(0) as Button).button_pressed:
		_fail("the page does not open on the deficit's tile")
	var state = _main._law_panel._state
	var want := GoalRead.rank(goals._read.reads, "deficit", state, _main._loader).size()
	var rows: Array = goals._box.get_children()
	var shown := mini(GoalRows.SHOWN, want)
	if want <= GoalRows.SHOWN or rows.size() != shown + 1:
		_fail("the deficit list shows %d rows, GoalRead ranks %d: expected the best %d and a Show all" % [rows.size(), want, GoalRows.SHOWN])
	else:
		(rows[shown] as Button).pressed.emit()
		goals._process(0.0)
		if goals._box.get_child_count() != want:
			_fail("Show all left %d rows of the %d ranked" % [goals._box.get_child_count(), want])
		goals._pick_goal("deficit")
	var text := _box_text()
	if not text.contains("bn a year"):
		_fail("the deficit rows do not word the balance as bn a year: %s" % text.left(200))
	if not (text.contains("would pass") or text.contains("would fail")):
		_fail("no row says whether the Assembly would pass it")


func _check_unemployment() -> void:
	var goals = _goals()
	if goals.goal != "unemployment":
		_fail("pressing the unemployment tile left the goal at %s" % goals.goal)
	var text := _box_text()
	if not (text.contains(" pt") or text.contains("not read here")):
		_fail("the unemployment rows give neither a shift in points nor 'not read here': %s" % text.left(200))


## A bill in the slot: every law row says why it cannot be tabled, instead of what the Assembly
## would do; a budget line, which a finance text can still amend, is not greyed by it.
func _check_a_bill_in_the_slot_greys_rows() -> void:
	var goals = _goals()
	var greyed := 0
	for press in goals._box.get_children():
		if (press as Button).get_child_count() == 0:
			continue
		var cells: Array = (press as Button).get_child(0).get_children()
		var kind := (cells[0] as Label).text
		var state_text := (cells[3] as Label).text
		if kind == "Law":
			if not state_text.contains("queue it"):
				_fail("a law row with a bill in the slot says '%s', not why it cannot be tabled" % state_text)
			greyed += 1
	if greyed == 0:
		_fail("premise: the unemployment list holds no law row")


func _check_the_bloc_tile_walks() -> void:
	var goals = _goals()
	if not _bloc_first.begins_with("bloc:"):
		_fail("the first press on the bloc tile gave the goal '%s'" % _bloc_first)
	if not goals.goal.begins_with("bloc:") or goals.goal == _bloc_first:
		_fail("a second press on the bloc tile gave '%s' after '%s', not the next bloc" % [goals.goal, _bloc_first])
	if not (goals._tiles.get_child(2) as Button).button_pressed:
		_fail("the bloc tile is not pressed after the second press")


func _check_a_press() -> void:
	var goals = _goals()
	goals._pick_goal("deficit")
	goals._show_all()
	goals._process(0.0)
	_main._state.player().tabled_bill = {}
	var lines: Array = goals._box.find_children("*", "Button", true, false)
	var by_kind := {}
	for press in lines:
		if press.get_child_count() == 0:
			continue
		by_kind[(press.get_child(0).get_child(0) as Label).text] = press
	if by_kind.has("Budget"):
		(by_kind["Budget"] as Button).pressed.emit()
		if _went != ["budget"]:
			_fail("a budget row's press asked for %s, not the Budget tab" % [_went])
		if not _main._windows.is_open("budget"):
			_fail("the wiring did not open the Budget tab for a budget row")
	else:
		_fail("no budget line among the deficit's measures")
	var law_row: Button = by_kind.get("Law")
	if law_row == null:
		_fail("no law among the deficit's measures")
		return
	law_row.pressed.emit()
	var list = _main._law_panel._laws
	if list.selected_id() == "":
		_fail("a law row's press selected nothing")


func _check_the_catalogue() -> void:
	# The budget row's press went to the Budget tab (the driver's wiring), so come back.
	_main._windows.open("legislature")
	var goals = _goals()
	var modes: HBoxContainer = goals.get_child(1)
	(modes.get_child(1) as Button).pressed.emit()
	goals._process(0.0)
	var list = _main._law_panel._laws
	if goals._scroll.visible or not list._rows.get_parent().visible:
		_fail("the Catalogue button did not swap the goal rows for the catalogue (moves %s, scroll %s, catalogue %s, in tree %s)" % [goals._moves, goals._scroll.visible, list._rows.get_parent().visible, goals.is_visible_in_tree()])
	(modes.get_child(0) as Button).pressed.emit()
	goals._process(0.0)
	if not goals._scroll.visible or list._rows.get_parent().visible:
		_fail("'What moves it' did not bring the goal rows back")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_goal_panel: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
