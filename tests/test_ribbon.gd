extends SceneTree

## Headless test: godot --headless --script res://tests/test_ribbon.gd
## Non-zero exit on any failure.
##
## V2.4a's surface. Loads the actual main scene and drives it a frame at a
## time -- the same pattern test_calendar_panel.gd runs, for the same reason: a
## Control outside the scene tree has not run _ready(), and a draw call on one
## is nothing at all.
##
## The ribbon is a DRAWN surface, so what a headless suite can assert is
## narrower than what it can see. The assertions here are the ones that can
## fail silently:
##
##   - the ribbon is BUILT and FED. main.gd hands it the real state and the
##     real loader; a ribbon that builds empty and stays empty passes every
##     "no crash" walk, which is the failure class V2.1b's `must name
##     PanelKit` scan exists for.
##   - main.gd MARKS IT DIRTY on the day tick. The today-mark is the one thing
##     that moves every day; a ribbon that only repainted on booking would
##     show yesterday forever, and nothing else in the suite reads it.
##   - the furniture test COVERS it. The ribbon is the bottom plate; if
##     is_over_furniture() did not list it, a drag started on the strip would
##     pan Europe -- hud.gd's own documented contract.
##
## What is deliberately NOT asserted headlessly: which pixels turn brass. The
## screenshot pass owns that; it was kept out of here because a colour
## assertion against a raster is a change-detector, not a test.

const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return
	var hud = _main._hud
	if hud == null or hud.ribbon == null:
		_fail("hud did not build the ribbon")
		return
	var ribbon = hud.ribbon

	# Fed, not orphaned: setup() ran with the live state, so a frame later the
	# title carries the month the game actually opened on -- a ribbon whose
	# state reference is null draws nothing and never errors.
	if ribbon._state == null or ribbon._loader == null:
		_fail("ribbon was not handed the live state and loader")
	var title: String = String(ribbon._title.text)
	if title.is_empty():
		_fail("ribbon title is empty after the first frame -- it drew nothing")
	if not title.to_upper() == title:
		_fail("ribbon title '%s' is not the tracked-uppercase style every MICRO label wears" % title)

	# The furniture contract: the ribbon is in hud.gd's own list, so a point
	# over the strip claims to be over furniture. Read from the PLATE's rect,
	# exactly as is_over_furniture() does.
	var centre: Vector2 = ribbon.global_position + ribbon.size * 0.5
	if not hud.is_over_furniture(centre):
		_fail("a point over the ribbon is not over furniture -- a drag there would pan Europe")

	# The source pins the WIRING that a frame cannot show: the day tick marks
	# the ribbon dirty, so the today-mark moves with the clock rather than
	# only with a booking. Read like the preload checks -- the behaviour is
	# one line in another file's handler.
	var main_file := FileAccess.open("res://src/ui/main.gd", FileAccess.READ)
	var main_text := main_file.get_as_text()
	main_file.close()
	var in_day_handler := false
	var marked := false
	for line in main_text.split("\n"):
		if line.begins_with("func _on_day_advanced"):
			in_day_handler = true
		elif in_day_handler and line.begins_with("func "):
			break
		if in_day_handler and line.contains("ribbon.mark_dirty()"):
			marked = true
	if not marked:
		_fail("_on_day_advanced does not mark the ribbon dirty -- the today-mark would freeze")

	# And the booking path repaints it: the diary's diary_changed handler is
	# what carries a new block onto the line the moment it is made.
	if not main_text.contains("_hud.ribbon.mark_dirty()"):
		_fail("main.gd never marks the ribbon dirty -- a booking would not appear on the line")

	# The tooltip resolves from the REGISTER, not from its own memory: book a
	# visit through the sim, ask the ribbon for the day, and the name it
	# prints must be the booked act's. Delivered by feeding the input handler
	# a motion event over the booked day's cell, which is the thing the
	# player's pointer actually does.
	var state = _main._state
	var entry := Calendar.make_entry(
		K.KIND_DIPLOMATIC, int(state.year), int(state.month), 16,
		"state_visit", "DEU", "", "", "", "DEU_vogler", 2
	)
	var result: Dictionary = Calendar.book(state, entry)
	if not bool(result["ok"]):
		_fail("fixture booking was refused: %s" % String(result["error"]))
	ribbon.mark_dirty()
	var cells: Array = Calendar.day_cells(state, int(state.year), int(state.month))
	var cell_w: float = ribbon._cells.size.x / cells.size()
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(15 * cell_w + 1.0, 5.0)
	ribbon._on_cells_input(motion)
	var tip: String = String(ribbon._cells.tooltip_text)
	if tip.is_empty():
		_fail("hovering a booked day left the tooltip empty -- the ribbon cannot name what occupies it")
	if not tip.contains("State Visit"):
		_fail("tooltip said '%s' -- it did not name the booked act" % tip)

	# And a booking paints TWO kinds of day: the meeting solid, the legs
	# travel. The drawn pixels are the screenshot pass's; the CELLS the draw
	# reads are assertable, and the ribbon owns no rule about them -- if these
	# drift, the drift is in the sim read the ribbon shares with the diary.
	var booked: Dictionary = cells[15]
	if not bool(booked["meeting"]):
		_fail("the booked meeting day did not classify as a meeting after the booking")
	var leg: Dictionary = cells[14]
	if not bool(leg["travel"]):
		_fail("the booked travel day did not classify as travel after the booking")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_ribbon: all checks passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	quit(1)
