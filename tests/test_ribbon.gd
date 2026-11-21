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
const UiTheme = preload("res://src/ui/ui_theme.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Ribbon = preload("res://src/ui/ribbon.gd")

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

	if _frame == 2:
		_run()
		# #439 pass 2 T4: the clock's slot holds the widest date at the largest text size with a
		# hold reason under it, so the horizon never shifts on a long month.
		UiTheme.set_text_scale(1.15)
		UiTheme.rebuild(_main)
		var clock = _main._hud.clock_cluster
		clock._date_label.text = DateText.weekday_long(14, 9, 2026)
		clock._reason.text = "The month is closing, and every hold says why"  # i18n: ok test fixture
		clock._reason.show()
	elif _frame == 5:
		_check_the_pane_seats_its_lane()
		_check_the_clock_fits_its_slot()
		UiTheme.set_text_scale(1.0)
		_finish()
	return false


## T3: the horizon draws at fixed y's from its cells' top, laid out for the docked pane's 10 px
## margin; the floating PANE has 3, so the strip adds the rest itself or the line runs 7 px high.
func _check_the_pane_seats_its_lane() -> void:
	var ribbon = _main._hud.ribbon
	var inset: float = ribbon._cells.global_position.y - ribbon.global_position.y
	if not is_equal_approx(inset, 10.0):
		_fail("the horizon's cells start %.0f px into the time bar, not 10: LINE_Y no longer sits on the line" % inset)


func _check_the_clock_fits_its_slot() -> void:
	var clock = _main._hud.clock_cluster
	var slot: Control = clock.get_parent()
	if slot.size.x > Ribbon.CLOCK_WIDTH + 0.5:
		_fail("'%s' at text 115 with a hold reason widens the clock's slot to %.0f (of %d): the horizon shifts" % [clock._date_label.text, slot.size.x, Ribbon.CLOCK_WIDTH])
	if clock._date_label.get_combined_minimum_size().x > clock._date_label.size.x + 0.5:
		_fail("the date '%s' is cut in its slot at text 115" % clock._date_label.text)


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return
	var hud = _main._hud
	if hud == null or hud.ribbon == null:
		_fail("hud did not build the ribbon")
		return
	var ribbon = hud.ribbon

	# The diary has five kinds, and a row's tooltip names each in words, never the raw kind.
	for kind in K.KINDS:
		if String(ribbon._booking_name({"kind": kind})) == kind:
			_fail("the ribbon's tooltip names a %s row by its raw kind" % kind)

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

	# A due read last month is still in the horizon's items for the frame between the day tick
	# and its refresh: it has no segment (-1) and is neither chipped nor drawn (test_briefing_go
	# caught the negative index as a script error).
	var this_month: int = int(_main._state.year) * 12 + int(_main._state.month)
	if ribbon._index_of(this_month - 6) != -1 or ribbon._index_of(this_month + 3) != -1:
		_fail("a month outside the horizon's three has a segment")
	if ribbon._index_of(this_month) != 0 or ribbon._index_of(this_month + 2) != 2:
		_fail("this month and the one two after are not segments 0 and 2")

	# QA #332 T1: this month's name, today's mark and the day numbers never overlap, for any today
	# (the name printed over the 8, the "1" mark clipped the J). Read off the one layout the drawing uses.
	var real_day: int = int(_main._state.day)
	for day in range(1, 32):
		_main._state.day = day
		var lay: Dictionary = ribbon._labels()
		var name_rect: Rect2 = lay["title"]
		var mark: Rect2 = lay["mark"]
		if mark.position.x < 0.0 or mark.end.x > ribbon._cells.size.x + 0.5:
			_fail("today %d: the mark %s leaves the line (0..%.0f)" % [day, mark, ribbon._cells.size.x])
		if name_rect.intersects(mark):
			_fail("today %d: the month's name %s runs under today's mark %s" % [day, name_rect, mark])
		for n in (lay["numbers"] as Array):
			if (n["rect"] as Rect2).intersects(name_rect) or (n["rect"] as Rect2).intersects(mark):
				_fail("today %d: the day number %s overlaps the month's name or today's mark" % [day, n["text"]])
	_main._state.day = real_day

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
	# The horizon draws the booking as a chip on its meeting day, named by the act, from
	# the register (horizon_items.gd), not from its own memory.
	ribbon._process(0.0)
	var named := false
	for chip in ribbon._chips:
		if String(chip.tooltip_text).contains("State Visit"):
			named = true
	if not named:
		_fail("the booked state visit has no chip on the horizon -- it cannot name what occupies the day")

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
