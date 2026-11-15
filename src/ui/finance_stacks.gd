extends Control

## What comes in and what goes out, drawn to one scale -- the picture of the Finances page
## (finances_panel.gd). Two stacks side by side, in above out; the spending stack standing taller
## than the revenue stack is the deficit, and that overhang is the page's one BAD mark, with its
## sign and the word beside it. A chart never gates (chart_kit.gd): the rows beside the stacks are
## the controls and carry every name and figure, so no block has a label inside it -- a part that
## is 2 % of the bar has no room for one. A part's colour follows the part (ChartStyle.SERIES by
## its slot, never its rank); what no row sets is a muted neutral, never a pattern.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

const STACK_WIDTH := 56.0
const GAP_WIDTH := 112.0
const GAP := 2.0
const HEIGHT := 520.0

var _revenue: Array = []
var _spending: Array = []
var _deficit := 0.0
var _word: Label
var _figure: Label


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_word = Label.new()
	_word.theme_type_variation = UiTheme.MICRO
	_word.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_word)
	_figure = Label.new()
	_figure.theme_type_variation = UiTheme.FIGURE_ALERT
	_figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_figure)


## `revenue` and `spending` are parts top to bottom, [{label, value, color}]; `deficit_bn` is
## spending less revenue (negative: a surplus, drawn without the bad mark).
func setup(revenue: Array, spending: Array, deficit_bn: float) -> void:
	_revenue = revenue
	_spending = spending
	_deficit = deficit_bn
	var scale_ := UiTheme.text_scale()
	custom_minimum_size = Vector2((STACK_WIDTH * 2.0 + GAP_WIDTH) * scale_, HEIGHT)
	_word.text = Strings.t("Deficit") if deficit_bn > 0.0 else Strings.t("Surplus")
	_figure.text = Strings.t("%s bn") % Num.fs(-deficit_bn, 0)
	_figure.theme_type_variation = UiTheme.FIGURE_ALERT if deficit_bn > 0.0 else UiTheme.FIGURE
	queue_redraw()
	_place()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_place()


## The heights in px of the two stacks on the shared scale: they are what the picture claims.
func heights() -> Dictionary:
	var scale_ := _scale()
	return {"revenue": _total(_revenue) * scale_, "spending": _total(_spending) * scale_}


func _total(parts: Array) -> float:
	var sum := 0.0
	for p in parts:
		sum += maxf(float(p["value"]), 0.0)
	return sum


func _scale() -> float:
	var tallest := maxf(_total(_revenue), _total(_spending))
	return 0.0 if tallest <= 0.0 else (HEIGHT - 4.0) / tallest


func _stack_x() -> Array:
	var w := STACK_WIDTH * UiTheme.text_scale()
	return [0.0, w + GAP_WIDTH * UiTheme.text_scale()]


func _place() -> void:
	if _word == null or _revenue.is_empty():
		return
	var h := heights()
	var top := HEIGHT - float(h["spending"])
	var bottom := HEIGHT - float(h["revenue"])
	var stack_w := STACK_WIDTH * UiTheme.text_scale()
	var gap_w := GAP_WIDTH * UiTheme.text_scale()
	var mid := (top + bottom) * 0.5
	for label in [_word, _figure]:
		label.size.x = gap_w - 22.0
		label.position.x = stack_w + 4.0
	_word.position.y = mid - _word.get_combined_minimum_size().y - 2.0
	_figure.position.y = mid - 2.0
	_word.visible = _deficit > 0.0
	_figure.visible = _deficit != 0.0


func _draw() -> void:
	var scale_ := _scale()
	var xs := _stack_x()
	var w := STACK_WIDTH * UiTheme.text_scale()
	_draw_stack(_revenue, xs[0], w, scale_)
	_draw_stack(_spending, xs[1], w, scale_)
	var h := heights()
	var top := HEIGHT - float(h["spending"])
	var bottom := HEIGHT - float(h["revenue"])
	# The revenue stack's top, carried across to the spending stack: the gap between is the deficit.
	draw_line(Vector2(xs[0] + w, bottom), Vector2(xs[1], bottom), UiTheme.TEXT_DIM, 1.0)
	if _deficit > 0.0:
		var x: float = xs[1] - 6.0
		draw_polyline(PackedVector2Array([Vector2(x + 5.0, top), Vector2(x, top), Vector2(x, bottom), Vector2(x + 5.0, bottom)]), UiTheme.BAD, 2.0)


func _draw_stack(parts: Array, x: float, w: float, scale_: float) -> void:
	var total := _total(parts)
	var y := HEIGHT - total * scale_
	for p in parts:
		var part_h := maxf(float(p["value"]), 0.0) * scale_
		if part_h > 0.0:
			draw_rect(Rect2(x, y, w, maxf(part_h - GAP, 1.0)), p["color"])
		y += part_h
