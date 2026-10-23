extends Control

## Horizontal bars from one zero baseline (chart_kit.gd's `bars()`): the label left
## in a text token, a bar of one hue at most BAR px thick with a rounded data end,
## the value at its tip. One series, so one colour for every bar -- colouring
## nominal bars by their value spends the identity channel on what length shows.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")

const BAR := 14.0
const ROW := 22.0
const PAD := 8.0
const ROUND := 4.0

var _rows: Array = []
var _unit := ""


func setup(rows: Array, opts := {}) -> void:
	_rows = rows
	_unit = String(opts.get("unit", ""))
	custom_minimum_size = Vector2(0.0, ROW * UiTheme.text_scale() * rows.size())
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()


func _font_size() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


## Each bar's rectangle: label column on the left, value room on the right, the
## widest value setting the scale so the longest bar still has its figure.
func bar_rects() -> Array[Rect2]:
	var font := get_theme_default_font()
	var fs := _font_size()
	var label_w := 0.0
	var value_w := 0.0
	var top := 0.0
	for r in _rows:
		label_w = maxf(label_w, font.get_string_size(String(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)  # i18n: row-ok chart data, the caller passes shown text
		value_w = maxf(value_w, font.get_string_size(ChartStyle.figure(float(r["value"])) + _unit, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		top = maxf(top, float(r["value"]))
	var x0 := label_w + PAD
	var span := maxf(size.x - x0 - value_w - PAD * 2.0, 1.0)
	var row_h := size.y / maxf(float(_rows.size()), 1.0)
	var out: Array[Rect2] = []
	for i in _rows.size():
		var w := span * maxf(float(_rows[i]["value"]), 0.0) / maxf(top, 1e-9)
		out.append(Rect2(x0, row_h * i + (row_h - BAR) * 0.5, w, BAR))
	return out


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _font_size()
	var rects := bar_rects()
	for i in _rows.size():
		var r: Rect2 = rects[i]
		var mid := r.position.y + r.size.y * 0.5 + fs * 0.35
		draw_string(font, Vector2(0.0, mid), String(_rows[i]["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)  # i18n: row-ok chart data, the caller passes shown text
		if r.size.x > 0.0:
			var box := StyleBoxFlat.new()
			box.bg_color = ChartStyle.SERIES[0]
			box.corner_radius_top_right = int(ROUND)
			box.corner_radius_bottom_right = int(ROUND)
			draw_style_box(box, r)
		draw_string(font, Vector2(r.end.x + PAD, mid), ChartStyle.figure(float(_rows[i]["value"])) + _unit,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)


func _get_tooltip(at: Vector2) -> String:
	if _rows.is_empty():
		return ""
	var i := clampi(int(at.y / (size.y / float(_rows.size()))), 0, _rows.size() - 1)
	return "%s  %s%s" % [String(_rows[i]["label"]), ChartStyle.figure(float(_rows[i]["value"])), _unit]  # i18n: row-ok chart data, the caller passes shown text
