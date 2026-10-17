extends SceneTree

## Headless test: godot --headless --script res://tests/test_tip_popup.gd
## Non-zero exit on any failure.
##
## V4.8b. The strip's two-level tooltip. Three things a screenshot cannot see:
##
##   - the dismissal rule: the popup stays while the pointer is on the figure,
##     level 1 or level 2, and only then; the grace window covers the diagonal
##     move between them;
##   - level 2 opens only from a line that carries a child_id, swaps when the
##     pointer moves to another child line, and closes when it moves to a plain
##     one -- and the breakdown is asked for LAZILY, at the hover, never at open;
##   - the popup is sized to its rows once layout has run (a wrapping Label reports
##     its minimum height for the width it had before layout: the first windowed
##     capture showed a 600 px popup round three lines) and level 2 flips to the
##     left of level 1 when it would leave the screen;
##   - the bar routes a real figure's hover into the popup, draws the register's
##     own lines, and leaves Godot's built-in tooltip empty (a non-empty one would
##     draw a second tooltip beside ours).
##
## Driven a frame at a time with tick(delta) -- the same entry points the mouse
## signals call -- because a Control outside the tree is half-dead
## (docs/engine-decision.md).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const TipPopup = preload("res://src/ui/tip_popup.gd")
const TopBar = preload("res://src/ui/top_bar.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []
var _frame := 0
var _loader
var _popup
var _figure: Label
var _asked: Array[String] = []

## The wrapped three-row popup's height ceiling; the unfitted bug measured 600.
const REFIT_MAX_HEIGHT := 260.0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	root.theme = UiTheme.build()
	_figure = Label.new()
	_figure.text = "A FIGURE"
	_figure.position = Vector2(300, 6)
	root.add_child(_figure)
	_popup = TipPopup.new()
	root.add_child(_popup)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let _ready() run on both
	if _frame > 2:
		if _frame == 7:
			_check_the_refit()
			_finish()
		return false
	_check_the_dismissal_rule()
	_check_level_two_follows_the_pointer()
	_check_the_grace_window()
	_check_a_refresh_rewrites_in_place()
	_check_the_bar_routes_a_real_hover()
	_check_level_two_flips_at_the_screen_edge()
	_stage_the_refit()
	return false


## Frame 2 staged a popup of long wrapping lines; the engine's own frames (the
## popup's _process re-fits for two) ran since. Checked at the later frame.
func _stage_the_refit() -> void:
	_popup.hide_all()
	_figure.position = Vector2(300, 6)
	var long_text := "Unemployment: 17% of minds, satisfaction +0.00 and a clause long enough to wrap"
	_popup.figure_entered("k", _figure, [
		{"text": long_text, "child_id": ""}, {"text": long_text, "child_id": ""},
		{"text": long_text, "child_id": ""},
	], Callable(self, "_provider"))
	_popup.tick(TipPopup.OPEN_DELAY_S + 0.01)


func _check_the_refit() -> void:
	var height: float = _popup._l1.size.y
	# Six wrapped rows at the theme's body size are well under this; the unfitted
	# panel was 600 px.
	if height > REFIT_MAX_HEIGHT or height <= 0.0:
		_fail("level 1 is %.0f px tall round three wrapping lines -- it was not re-fitted after layout" % height)


func _check_level_two_flips_at_the_screen_edge() -> void:
	_popup.hide_all()
	var screen: Vector2 = _popup.get_viewport_rect().size
	_figure.position = Vector2(screen.x - 120.0, 6)
	_open_level_one()
	_popup.line_entered(1)
	var l1: Rect2 = Rect2(_popup._l1.position, _popup._l1.get_combined_minimum_size())
	var l2: Rect2 = Rect2(_popup._l2.position, _popup._l2.get_combined_minimum_size())
	if l2.end.x > screen.x:
		_fail("level 2 %s runs off a %s screen instead of flipping left" % [l2, screen])
	if l2.position.x >= l1.position.x:
		_fail("level 2 did not flip to the left of level 1 at the right edge (%s vs %s)" % [l2, l1])
	_figure.position = Vector2(300, 6)


func _provider(child_id: String) -> Dictionary:
	_asked.append(child_id)
	return {"title": "Child %s" % child_id, "lines": ["row of %s" % child_id]}


func _lines() -> Array:
	return [
		{"text": "plain", "child_id": ""},
		{"text": "opens a", "child_id": "a"},
		{"text": "opens b", "child_id": "b"},
	]


func _open_level_one() -> void:
	_popup.hide_all()
	_asked.clear()
	_popup.figure_entered("k", _figure, _lines(), Callable(self, "_provider"))
	_popup.tick(TipPopup.OPEN_DELAY_S + 0.01)


func _check_the_dismissal_rule() -> void:
	for pointer in [[true, false, false], [false, true, false], [false, false, true]]:
		if not TipPopup.stays_open(pointer[0], pointer[1], pointer[2]):
			_fail("pointer on %s but the popup would close" % [pointer])
	if TipPopup.stays_open(false, false, false):
		_fail("pointer on no level but the popup stays open")


func _check_level_two_follows_the_pointer() -> void:
	_popup.hide_all()
	_asked.clear()
	_popup.figure_entered("k", _figure, _lines(), Callable(self, "_provider"))
	_popup.tick(TipPopup.OPEN_DELAY_S * 0.5)
	if _popup.level1_visible:
		_fail("level 1 opened before the dwell -- a sweep along the strip would strobe")
	_popup.tick(TipPopup.OPEN_DELAY_S)
	if not _popup.level1_visible:
		_fail("level 1 did not open after the dwell")
	if not _asked.is_empty():
		_fail("a child was asked for at open (%s) -- breakdowns must be lazy" % [_asked])

	_popup.line_entered(0)
	if _popup.level2_visible:
		_fail("a line with no child opened level 2")
	_popup.line_entered(1)
	if not _popup.level2_visible or _popup.open_child_id != "a":
		_fail("hovering the child line 'a' left level 2 at '%s'" % _popup.open_child_id)
	_popup.line_entered(2)
	if _popup.open_child_id != "b":
		_fail("moving to line 'b' left level 2 on '%s'" % _popup.open_child_id)
	_popup.line_entered(0)
	if _popup.level2_visible:
		_fail("moving to a plain line left level 2 open")

	# Placement: level 1 hangs under the figure; level 2 stays on screen.
	_popup.line_entered(1)
	var screen: Vector2 = _popup.get_viewport_rect().size
	if _popup._l1.position.y < _figure.position.y + _figure.size.y:
		_fail("level 1 sits over its figure instead of under it")
	var l2: Rect2 = Rect2(_popup._l2.position, _popup._l2.get_combined_minimum_size())
	if l2.position.x < 0.0 or l2.end.x > screen.x or l2.position.y < 0.0 or l2.end.y > screen.y:
		_fail("level 2 %s leaves the %s screen" % [l2, screen])


func _check_the_grace_window() -> void:
	_open_level_one()
	_popup.line_entered(1)
	# Figure -> level 1 -> level 2, the pointer on one level at a time.
	_popup.figure_exited("k")
	_popup.popup_entered(1)
	_popup.tick(0.5)
	if not _popup.level1_visible:
		_fail("level 1 closed with the pointer on it")
	_popup.popup_exited(1)
	_popup.popup_entered(2)
	_popup.tick(0.5)
	if not (_popup.level1_visible and _popup.level2_visible):
		_fail("moving onto level 2 closed a level; both must stay while it is hovered")
	# Off every level: still open inside the grace, gone after it.
	_popup.popup_exited(2)
	_popup.tick(TipPopup.GRACE_S * 0.5)
	if not _popup.level1_visible:
		_fail("the popup closed inside its grace window -- the diagonal move would drop it")
	_popup.popup_entered(1)
	_popup.tick(TipPopup.GRACE_S * 2.0)
	_popup.popup_exited(1)
	_popup.tick(TipPopup.GRACE_S * 0.5)
	if not _popup.level1_visible:
		_fail("re-entering did not restart the grace window")
	_popup.tick(TipPopup.GRACE_S * 2.0)
	if _popup.level1_visible or _popup.level2_visible:
		_fail("leaving both levels did not dismiss them (l1 %s, l2 %s)" % [_popup.level1_visible, _popup.level2_visible])


## A day tick refreshes the figure under a stationary pointer: same shape, same
## Label instances (new ones would fire exit/enter pairs and flicker the child).
func _check_a_refresh_rewrites_in_place() -> void:
	_open_level_one()
	var before: Label = _popup._l1_labels[1]
	var next := _lines()
	next[1]["text"] = "opens a, later"
	_popup.update_lines("k", next)
	if _popup._l1_labels[1] != before:
		_fail("a same-shape refresh rebuilt the rows")
	if not before.text.begins_with("opens a, later"):
		_fail("a same-shape refresh did not rewrite the text: '%s'" % before.text)
	_popup.update_lines("k", [{"text": "only one now", "child_id": ""}])
	if _popup._l1_labels.size() != 1:
		_fail("a changed shape did not rebuild the rows")
	_popup.update_lines("other", _lines())
	if _popup._l1_labels.size() != 1:
		_fail("a refresh for another figure rewrote this popup")


func _check_the_bar_routes_a_real_hover() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var bar = TopBar.new()
	bar.theme = UiTheme.build()
	root.add_child(bar)
	bar.refresh(state, null, _loader)
	var value: Label = bar._figure_values["approval"]
	for id in StripReadings.ORDER:
		for label in [bar._figure_values[id], bar._figure_captions[id]]:
			if not (label as Label).tooltip_text.is_empty():
				_fail("'%s' still sets a built-in tooltip -- it would draw beside ours" % id)
	# The label's own mouse signal, not the handler: a figure whose hover was never
	# wired would pass a test that called the handler directly.
	value.mouse_entered.emit()
	bar._popup.tick(TipPopup.OPEN_DELAY_S + 0.01)
	if not bar._popup.level1_visible:
		_fail("hovering the approval figure opened nothing")
		return
	var read: Dictionary = StripReadings.read("approval", state, _loader)
	var first: String = String((read["lines"] as Array)[0]["text"])
	if bar._popup._l1_labels[0].text != first:
		_fail("level 1 line 0 reads '%s', the register says '%s'" % [bar._popup._l1_labels[0].text, first])
	# The first issue line opens its breakdown from the real state.
	bar._popup.line_entered(1)
	if not bar._popup.level2_visible:
		_fail("the approval issue line opened no level 2")
	if bar.tip_of("approval") != String(read["tip"]):
		var x: String = bar.tip_of("approval")
		var y := String(read["tip"])
		var at := 0
		while at < mini(x.length(), y.length()) and x[at] == y[at]:
			at += 1
		_fail("tip_of differs from the register tip at %d (%d vs %d chars): %s | %s" % [at, x.length(), y.length(), x.to_utf8_buffer().slice(maxi(at - 2, 0), at + 6), y.to_utf8_buffer().slice(maxi(at - 2, 0), at + 6)])
	value.mouse_exited.emit()
	bar._popup.tick(TipPopup.GRACE_S * 2.0)
	if bar._popup.level1_visible:
		_fail("leaving the figure did not close its popup")
	bar._figure_captions["approval"].mouse_entered.emit()
	bar._popup.tick(TipPopup.OPEN_DELAY_S + 0.01)
	if not bar._popup.level1_visible:
		_fail("the caption above a figure does not open its popup")
	bar.queue_free()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_tip_popup: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
