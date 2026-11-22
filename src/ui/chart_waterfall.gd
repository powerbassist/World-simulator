extends Control

## A total walked step by step -- ChartKit.waterfall (G3 S4, the Books page in C: "the deficit is a waterfall").
## The first row is where it stands today, then each change a floating bar from the running total to where the
## change takes it, then the total after them all. One row a bar, its name at the left and its figure at the
## right, signed for a step: the reader is never left to add the steps in the head.
##
## Tones (dataviz: status colours carry state, never identity): the two totals are the neutral bar; a step that
## makes the total WORSE is BAD and one that makes it better GOOD -- for a deficit, a rise is worse. A dashed
## connector joins each bar's end to the next bar's start. The colour is never alone: every step prints its sign.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")

const LABEL_W := 130.0
const FIGURE_W := 56.0
const BAR_H := 12.0
const ROW_GAP := 1.7

var _rows: Array = []   # [{label, from, to, kind}] kind: "total" or "step"
var _lo := 0.0
var _hi := 1.0
var _label_w := LABEL_W
var _worse_up := true
var _total_places := 0
var _step_places := 1


## `start` and `end` {label, value}; `steps` [{label, value}] each a signed change. opts: label_w (at text 100),
## worse_up (a rise is bad news; true for a deficit), total_places, step_places.
func setup(start: Dictionary, steps: Array, end: Dictionary, opts := {}) -> void:
	_label_w = float(opts.get("label_w", LABEL_W))
	_worse_up = bool(opts.get("worse_up", true))
	_total_places = int(opts.get("total_places", 0))
	_step_places = int(opts.get("step_places", 1))
	_rows = [{"label": String(start["label"]), "from": 0.0, "to": float(start["value"]), "kind": "total"}]
	var at := float(start["value"])
	for step in steps:
		_rows.append({"label": String(step["label"]), "from": at, "to": at + float(step["value"]), "kind": "step", "delta": float(step["value"])})
		at += float(step["value"])
	_rows.append({"label": String(end["label"]), "from": 0.0, "to": float(end["value"]), "kind": "total"})
	_lo = 0.0
	_hi = 0.0
	for row in _rows:
		_lo = minf(_lo, minf(float(row["from"]), float(row["to"])))
		_hi = maxf(_hi, maxf(float(row["from"]), float(row["to"])))
	if _hi - _lo < 1e-6:
		_hi = _lo + 1.0
	custom_minimum_size = Vector2(0.0, row_height() * _rows.size())
	tooltip_text = " "  # _get_tooltip names the row under the pointer
	queue_redraw()


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


func row_height() -> float:
	return ceilf(_fs() * ROW_GAP)


func _area() -> Vector2:
	var left := _label_w * UiTheme.text_scale()
	return Vector2(left, maxf(size.x - FIGURE_W * UiTheme.text_scale() - left, 1.0))


func x_of(value: float) -> float:
	var area := _area()
	return area.x + (value - _lo) / (_hi - _lo) * area.y


func bar_rect(i: int) -> Rect2:
	var row: Dictionary = _rows[i]
	var a := x_of(minf(float(row["from"]), float(row["to"])))
	var b := x_of(maxf(float(row["from"]), float(row["to"])))
	var h := row_height()
	return Rect2(a, i * h + (h - BAR_H) * 0.5, maxf(b - a, 1.0), BAR_H)


func bar_color(i: int) -> Color:
	var row: Dictionary = _rows[i]
	if String(row["kind"]) == "total":
		return UiTheme.NEUTRAL_BAR
	var up := float(row["to"]) > float(row["from"])
	return UiTheme.BAD if up == _worse_up else UiTheme.GOOD


func row_count() -> int:
	return _rows.size()


func label(i: int) -> String:
	return String(_rows[i]["label"])


func figure(i: int) -> String:
	var row: Dictionary = _rows[i]
	if String(row["kind"]) == "total":
		return Num.f(float(row["to"]), _total_places)
	# The step's own value, not to - from: a running sum's float error must not flip the last digit.
	return Num.fs(float(row["delta"]), _step_places)


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	var h := row_height()
	var label_w := _label_w * UiTheme.text_scale() - 8.0
	for i in _rows.size():
		var row: Dictionary = _rows[i]
		var bar := bar_rect(i)
		var base := i * h + (h + fs * 0.7) * 0.5
		var total := String(row["kind"]) == "total"
		draw_string(font, Vector2(0.0, base), String(row["label"]), HORIZONTAL_ALIGNMENT_LEFT, label_w, fs,
			UiTheme.TEXT if total else UiTheme.TEXT_DIM, TextServer.JUSTIFICATION_NONE)
		draw_rect(bar, bar_color(i))
		draw_string(font, Vector2(bar.end.x + 6.0, base), figure(i), HORIZONTAL_ALIGNMENT_LEFT, FIGURE_W * UiTheme.text_scale(), fs, UiTheme.TEXT)
		if i + 1 < _rows.size():
			# The connector: from where this bar leaves the running total to the next bar's row.
			var x := x_of(float(row["to"]))
			draw_dashed_line(Vector2(x, bar.end.y), Vector2(x, (i + 1) * h + (h - BAR_H) * 0.5), UiTheme.LINE_STRONG, 1.0, 3.0)


func _get_tooltip(at: Vector2) -> String:
	var i := clampi(int(at.y / row_height()), 0, _rows.size() - 1)
	return "%s: %s" % [String(_rows[i]["label"]), figure(i)]  # i18n: row-ok chart data
