extends HSlider

## One line's lever on the Books page in C ("the bill is the page", G3 S4, the author's pick): the line's bar IS
## the control. The bar is drawn to ONE money scale every row of the table shares (bn a year), so the rows
## compare at a glance; its colour is the line's; the ring is today and the dot the draft, as every
## before-and-after mark on the screen draws them (ChartDots). Its end is the handle: a press or a drag
## sets the rate whose money is under the pointer, snapped to the row's step.
##
## An HSlider underneath, not a drawn Control: the value, the range, the step, value_changed and the arrow
## keys are the engine's, so the editor (finance_editor.gd), the goal panel's Go and the tests reach it as
## they reached the old slider. Only the mapping from x is ours: a press is taken in _gui_input, which the
## engine calls before the slider's own (Control::_call_gui_input), and accepted there. Its look is the
## LEVER variation (ui_theme.gd), whose track and grabber draw nothing, so _draw is the only picture.

## A press let go (a click or the end of a drag): the page reads at_today() then (pass 2 T9 on #443).
signal released

const UiTheme = preload("res://src/ui/ui_theme.gd")

## Room at each end of the bar for the dot's radius, so a dot at 0 or at the scale's end is not cut.
const PAD := 6.0
const BAR_H := 6.0
const LINE_H := 2.0
const DOT_R := 5.0
const RING_R := 5.0

## Money a year per unit of the rate (today's bn over today's rate): the bar's length is value x this.
var _per_unit := 0.0
## The table's shared scale, bn a year: a bar this long fills the control.
var _scale_bn := 1.0
## Today's rate: the ring.
var _live := 0.0
var _color := Color.WHITE
var _dragging := false
## The draft's own value, as the page paints it (NAN: the slider's value). The slider snaps its value to the step from
## its floor, so a rate today off that grid (Germany's 20.83 % income tax) drew its dot a step away from its ring, a
## move nobody made; the dot reads the draft instead.
var shown := NAN


## The table's one money scale on the DRAG head: `figures` (0, half, the whole) where x_of draws those sums on any
## bar under the head, which is as wide and as far left as the bars. On the head's second line.
static func axis(head: Label, figures: Array) -> void:
	var sides := [HORIZONTAL_ALIGNMENT_LEFT, HORIZONTAL_ALIGNMENT_CENTER, HORIZONTAL_ALIGNMENT_RIGHT]
	for i in 3:
		var mark := Label.new()
		mark.text = figures[i]
		mark.theme_type_variation = UiTheme.MICRO
		mark.horizontal_alignment = sides[i]
		mark.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		mark.grow_vertical = Control.GROW_DIRECTION_BEGIN
		mark.offset_left = PAD
		mark.offset_right = -PAD
		head.add_child(mark)


func _init() -> void:
	theme_type_variation = UiTheme.LEVER
	# The wheel scrolls the table under the bars; on a bar it changed the draft unseen (pass 2 T1 on #443).
	scrollable = false
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	custom_minimum_size = Vector2(120.0, 20.0)


## `per_unit` bn a year per point of the rate, the table's `scale_bn`, today's rate, the line's colour. A lever with
## no money per point (a kind not in force) draws nothing and takes no press.
func setup(per_unit: float, scale_bn: float, live: float, color: Color) -> void:
	_per_unit = per_unit
	_scale_bn = maxf(scale_bn, 1e-6)
	_live = live
	_color = color
	focus_mode = Control.FOCUS_ALL if editable and per_unit > 0.0 else Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_HSIZE if focus_mode == Control.FOCUS_ALL else Control.CURSOR_ARROW
	# No money per point, no mapping from x: the engine's own press would set a rate on a bar that draws nothing (T2).
	if per_unit <= 0.0:
		editable = false
	queue_redraw()


## A row at vote, or one no rate here sets: the bar is drawn, takes no press and leaves the keyboard path.
func lock() -> void:
	editable = false
	focus_mode = Control.FOCUS_NONE
	mouse_default_cursor_shape = Control.CURSOR_ARROW
	queue_redraw()


## The x of a rate on the shared money scale, clamped to the bar.
func x_of(rate: float) -> float:
	var frac := clampf(rate * _per_unit / _scale_bn, 0.0, 1.0)
	return PAD + frac * maxf(size.x - 2.0 * PAD, 1.0)


## Whether a press or a key can move it: an editable lever with money per point (a kind not in force has none).
func can_drag() -> bool:
	return editable and _per_unit > 0.0


## A press is being dragged (the page does not rebuild under it).
func is_dragging() -> bool:
	return _dragging


func ring_x() -> float:
	return x_of(_live)


func is_moved() -> bool:
	return not is_equal_approx(_at(), _live)


## Whether the slider sits on the grid point nearest today (today off the grid, or past the track's end on its side):
## a release there is "no change", since the snapped value can never equal an off-grid rate (pass 2 T9 on #443).
func at_today() -> bool:
	return absf(value - clampf(_live, min_value, max_value)) <= step * 0.5 + 1e-6


func _at() -> float:
	return value if is_nan(shown) else shown


func _rate_at(x: float) -> float:
	var frac := (x - PAD) / maxf(size.x - 2.0 * PAD, 1.0)
	return frac * _scale_bn / _per_unit


func _gui_input(event: InputEvent) -> void:
	if not editable or _per_unit <= 0.0:
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		var was := _dragging
		_dragging = button.pressed
		if button.pressed:
			value = _rate_at(button.position.x)
		elif has_focus():
			# A mouse hand lets go with the button: a focus kept would hold the page's rebuild off until a click elsewhere.
			release_focus()
		accept_event()
		if was and not button.pressed:
			released.emit()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _dragging:
		value = _rate_at(motion.position.x)
		accept_event()


func _draw() -> void:
	if _per_unit <= 0.0:
		return
	var mid := size.y * 0.5
	var at := x_of(_at())
	var live := ring_x()
	var near := minf(at, live)
	draw_rect(Rect2(PAD - 1.0, mid - BAR_H * 0.5, maxf(near - PAD + 1.0, 0.0), BAR_H), _color)
	if not editable:
		return
	if is_moved():
		draw_rect(Rect2(near, mid - LINE_H * 0.5, absf(at - live), LINE_H), _color)
		draw_circle(Vector2(live, mid), RING_R, UiTheme.SHEET)
		draw_arc(Vector2(live, mid), RING_R, 0.0, TAU, 24, UiTheme.TEXT, 2.0, true)
	draw_circle(Vector2(at, mid), DOT_R + (1.0 if has_focus() else 0.0), UiTheme.TEXT)


func _get_tooltip(_at: Vector2) -> String:
	return tooltip_text
