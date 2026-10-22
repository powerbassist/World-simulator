extends SceneTree

## Headless test: godot --headless --script res://tests/test_glossary_tip.gd
## Non-zero exit on any failure.
##
## V5.1-c, the glossary's tooltip chain (src/ui/glossary_tip.gd), against
## docs/design/glossary-tooltips.md "The behaviour" -- the timing and the rules a
## frame cannot show:
##
##   - a plate opens after OPEN_DELAY_S on the term, not before; an unlocked one
##     closes GRACE_S after the pointer leaves the term, not before;
##   - it locks on a click on the term, or after LOCK_HOLD_S still on it; a locked
##     plate shows its body and takes the mouse, an unlocked one passes it through;
##   - a locked plate stays while the pointer is on it; the chain stops at
##     MAX_DEPTH; a nested plate never marks a term already open up the chain (N5);
##   - Escape, or a click away from every plate and term, closes every level;
##   - the live line is the figure the strip prints, with its source when it is a
##     poll (rule L1, "fog is shown, never silent"), and no line when there is none;
##   - P2: at 1920x1080 and at the 960x540 floor, a locked chain three deep of the
##     longest entries, opened from the screen's far corner, lies wholly inside the
##     viewport -- under pseudolocalization, which grows every tr() line of a plate
##     (the rows are English data: they keep their length).
##
## Driven through enter/leave/click/tick, the calls the label makes: a pushed mouse
## event does not move RichTextLabel's hover on a windowed root viewport (step 0).

const PanelKit = preload("res://src/ui/panel_kit.gd")
const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const GlossaryTip = preload("res://src/ui/glossary_tip.gd")
const Glossary = preload("res://src/ui/glossary.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const GlossaryLive = preload("res://src/ui/glossary_live.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []
var _frame := 0
var _tip
var _loader
var _state
var _p2_sizes: Array = [Vector2i(1920, 1080), Vector2i(960, 540)]
var _p2_at := -1

const AT := Rect2(300, 300, 1, 18)


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_state = GameState.new_game(_loader, "FRA")
	root.theme = UiTheme.build()
	root.size = Vector2i(1920, 1080)
	_tip = GlossaryTip.new()
	root.add_child(_tip)
	_tip.setup(_state, _loader)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_check_open_delay()
		_check_grace()
		_check_click_locks()
		_check_hold_locks()
		_check_locked_plate_holds_the_pointer()
		_check_depth_and_n5()
		_check_escape_and_click_away()
		_check_live_line()
		_check_keyboard_path()
		_stage_p2(0)
	elif _frame == 6:
		_check_p2()
		_stage_p2(1)
	elif _frame == 10:
		_check_p2()
		TranslationServer.pseudolocalization_enabled = false
		_finish()
		return true
	return false


func _check_open_delay() -> void:
	_tip.close_all()
	_tip.enter("approval", AT, 0)
	_tip.tick(GlossaryTip.OPEN_DELAY_S - 0.01)
	if _tip.depth() != 0:
		_fail("a plate opened before the hover delay")
	_tip.tick(0.02)
	if _tip.depth() != 1:
		_fail("no plate %.2f s into the hover" % (GlossaryTip.OPEN_DELAY_S + 0.01))


func _check_grace() -> void:
	_tip.leave(0)
	_tip.tick(GlossaryTip.GRACE_S - 0.01)
	if _tip.depth() != 1:
		_fail("an unlocked plate closed inside the grace window")
	_tip.tick(0.02)
	if _tip.depth() != 0:
		_fail("an unlocked plate outlived the grace window")


func _check_click_locks() -> void:
	_tip.close_all()
	_tip.click("approval", AT, 0)
	if _tip.depth() != 1 or not _tip.is_locked(1):
		_fail("a click on a term did not open and lock its plate at once")
		return
	if _tip.plate(1).mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("a locked plate does not take the mouse")
	if not _tip.plate_text(1).contains(Glossary.body("approval").left(30)):
		_fail("a locked plate does not show the entry's body")


func _check_hold_locks() -> void:
	_tip.close_all()
	_tip.enter("approval", AT, 0)
	_tip.tick(GlossaryTip.OPEN_DELAY_S + 0.01)
	if _tip.is_locked(1):
		_fail("a plate locked the moment it opened")
	if _tip.plate(1).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("an unlocked plate does not pass the mouse through")
	if _tip.plate_text(1).contains(Glossary.body("approval").left(30)):
		_fail("an unlocked plate shows the body")
	_tip.tick(GlossaryTip.LOCK_HOLD_S - GlossaryTip.OPEN_DELAY_S)
	if not _tip.is_locked(1):
		_fail("holding still %.1f s on a term did not lock its plate" % GlossaryTip.LOCK_HOLD_S)


func _check_locked_plate_holds_the_pointer() -> void:
	_tip.close_all()
	_tip.click("approval", AT, 0)
	_tip.plate_entered(1)
	_tip.leave(0)
	_tip.tick(GlossaryTip.GRACE_S + 0.1)
	if _tip.depth() != 1:
		_fail("a locked plate closed while the pointer was on it")
	_tip.plate_exited(1)
	_tip.tick(GlossaryTip.GRACE_S + 0.01)
	if _tip.depth() != 0:
		_fail("a locked plate stayed after the pointer left it")


func _check_depth_and_n5() -> void:
	_tip.close_all()
	_tip.click("approval", AT, 0)
	_tip.plate_entered(1)
	_tip.click("poll", AT, 1)
	_tip.plate_entered(2)
	if _tip.depth() != 2:
		_fail("a term in a locked plate did not open a second level")
	if _tip.plate_markup(2).contains("term:approval"):
		_fail("N5: poll's plate marks approval, which is open up the chain")
	_tip.click("voter_bloc", AT, 2)
	_tip.plate_entered(3)
	_tip.enter("issue", AT, GlossaryTip.MAX_DEPTH)
	_tip.tick(GlossaryTip.OPEN_DELAY_S + 0.1)
	if _tip.depth() != GlossaryTip.MAX_DEPTH:
		_fail("the chain is %d deep; the cap is %d" % [_tip.depth(), GlossaryTip.MAX_DEPTH])


func _check_escape_and_click_away() -> void:
	_tip.close_all()
	_tip.click("approval", AT, 0)
	_tip.leave(0)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_tip._input(escape)
	if _tip.depth() != 0:
		_fail("Escape left %d levels open" % _tip.depth())
	_tip.click("approval", AT, 0)
	_tip.leave(0)
	var away := InputEventMouseButton.new()
	away.button_index = MOUSE_BUTTON_LEFT
	away.pressed = true
	away.position = Vector2(1900, 1060)
	_tip._input(away)
	if _tip.depth() != 0:
		_fail("a click away from every plate left %d levels open" % _tip.depth())


## V5.1-d2, the keyboard path the design asked for (RichTextLabel has no per-tag
## focus): F1 cycles the marked terms on screen in reading order, opening each one's
## plate locked at its line; Escape closes, as for the mouse.
func _check_keyboard_path() -> void:
	_tip.close_all()
	var box := VBoxContainer.new()
	box.size = Vector2(600, 200)
	root.add_child(box)
	var first = PanelKit.rich(box, "Your [g=approval]approval[/g] and the [g=deficit]deficit[/g].")
	PanelKit.rich(box, "Then the [g=debt]debt[/g].")
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	var seen: Array[String] = []
	for i in 3:
		_tip._input(f1)
		if _tip.depth() != 1 or not _tip.is_locked(1):
			_fail("F1 press %d did not open a locked plate (depth %d)" % [i + 1, _tip.depth()])
			break
		seen.append(String(_tip._plates[0]["id"]))
	if seen != ["approval", "deficit", "debt"]:
		_fail("F1 did not walk the terms in reading order: %s" % [seen])
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_tip._input(escape)
	if _tip.depth() != 0:
		_fail("Escape did not close the plate F1 opened")
	box.queue_free()


func _check_live_line() -> void:
	_tip.close_all()
	_tip.click("approval", AT, 0)
	# V5.1-d2: the See-also line marks every entry -- a list, not prose (N2's cap
	# drew APPROVAL's fourth, "salience", plain).
	var see_also: Array = Glossary.see_also("approval")
	for other in see_also:
		if not _tip.plate_markup(1).contains("term:%s]" % other):
			_fail("APPROVAL's See-also line draws '%s' plain" % other)
	var shown := String(StripReadings.read("approval", _state, _loader)["text"])
	if not _tip.plate_text(1).contains(shown):
		_fail("approval's plate does not show the strip's %s" % shown)
	if not _tip.plate_text(1).contains("±3"):
		_fail("approval's live line does not say it is a poll")
	for live in GlossaryLive._STRIP:
		var strip := String(StripReadings.read(GlossaryLive._STRIP[live], _state, _loader)["text"])
		# The strip's "nothing yet" dash is left off a plate (V5.1-d1b, QA's C item).
		if strip == "—":
			strip = ""
		if GlossaryLive.value(live, _state, _loader) != strip:
			_fail("live %s reads '%s'; the strip prints '%s'" % [live, GlossaryLive.value(live, _state, _loader), strip])
	for live in ["debt_pct", "credit_yield", "credit_rating", "growth_and_trend", "article_49_3_available"]:
		if GlossaryLive.value(live, _state, _loader).is_empty():
			_fail("live %s shows nothing at a new game" % live)
	_tip.close_all()
	_tip.click("dissolution", AT, 0)
	if _tip.plate_text(1).contains("lockout left"):
		_fail("a new game shows a dissolution lockout")
	_tip.close_all()


## The three entries with the most text, locked three deep from the screen's
## bottom-right corner -- the placement's worst case.
func _stage_p2(index: int) -> void:
	_p2_at = index
	root.size = _p2_sizes[index]
	TranslationServer.pseudolocalization_enabled = index == 1
	var ids: Array = Array(Glossary.ids())
	ids.sort_custom(func(a, b): return _length(a) > _length(b))
	var corner := Rect2(_tip.get_viewport_rect().size - Vector2(30, 30), Vector2(1, 18))
	_tip.close_all()
	for level in 3:
		_tip.click(String(ids[level]), corner, level)
		_tip.plate_entered(level + 1)


## The project stretches canvas_items with aspect "expand" from 1920x1080, so at
## the 960x540 floor the LOGICAL viewport the plates are placed in is still
## 1920x1080: the floor halves the pixels, it does not shrink the room.
func _check_p2() -> void:
	var view: Rect2 = _tip.get_viewport_rect()
	if view.size.x < 1920.0 or view.size.y < 1080.0:
		_fail("P2 at %s: the logical viewport is %s, smaller than the 1920x1080 reference" % [root.size, view.size])
	if _tip.depth() != 3:
		_fail("P2 at %s: the chain is %d deep, not 3" % [root.size, _tip.depth()])
	for n in range(1, _tip.depth() + 1):
		var rect: Rect2 = _tip.plate(n).get_global_rect()
		if not view.encloses(rect):
			_fail("P2 at %s: plate %d at %s leaves the viewport" % [root.size, n, rect])


func _length(id: String) -> int:
	return Glossary.definition(id).length() + Glossary.body(id).length()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_glossary_tip: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
