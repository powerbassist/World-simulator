extends Control

## The register sheet's region chart (V5.3 c' slice 1, the author's "A pour commander"): one
## row per region that holds the type, on one axis of the type's own figure. A ring is the
## figure now, a filled dot in the accent the figure once the placed units stand, joined by a
## line; a region the programme does not touch is a small dim dot at its after (the netting's
## give-back is said once in the strip, not drawn as a move on every row). The nation is one
## vertical hairline. Values are printed at the row's end, so the chart never gates a number
## (the dataviz method's table view); a click on a row picks that region.
##
## data() is what is drawn: [{region, name, before, after, placed, selected}], sim figures
## the caller read (Units.shown_figure, Units.preview). Nothing here computes a figure.

signal picked(region_id: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")

const ROW := 24.0
const LABEL_W := 200.0
const VALUE_W := 110.0
const PAD := 8.0
const RING := 5.0

var _rows: Array = []
var _nation := 0.0


func setup(rows: Array, nation: float) -> void:
	_rows = rows
	_nation = nation
	custom_minimum_size = Vector2(0.0, ROW * UiTheme.text_scale() * (rows.size() + 1))
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func data() -> Array:
	return _rows


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


func _row_h() -> float:
	return ROW * UiTheme.text_scale()


## The axis: every value drawn, the nation's included, with a margin so no mark sits on an edge.
func _span() -> Vector2:
	var lo := _nation
	var hi := _nation
	for r in _rows:
		for k in ["before", "after"]:
			lo = minf(lo, float(r[k]))
			hi = maxf(hi, float(r[k]))
	var pad := maxf((hi - lo) * 0.08, 0.01)
	return Vector2(lo - pad, hi + pad)


## The name and value columns grow with the text size, or a long name is cut at 130 %.
func _lw() -> float:
	return LABEL_W * UiTheme.text_scale()


func _vw() -> float:
	return VALUE_W * UiTheme.text_scale()


func _x(v: float) -> float:
	var s := _span()
	var w := maxf(size.x - _lw() - _vw() - PAD * 2.0, 1.0)
	return _lw() + PAD + (v - s.x) / maxf(s.y - s.x, 1e-9) * w


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	var h := _row_h()
	var accent := UiTheme.accent()
	var nx := _x(_nation)
	# The picked row's plate first, so the nation's hairline crosses it rather than stopping.
	for i in _rows.size():
		if bool(_rows[i]["selected"]):
			draw_rect(Rect2(0.0, h * i, size.x, h), UiTheme.SLATE)
			draw_rect(Rect2(0.0, h * i, 3.0, h), accent)
	draw_line(Vector2(nx, 0.0), Vector2(nx, h * _rows.size()), UiTheme.TEXT_DIM, 1.0)
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var y := h * i
		var mid := y + h * 0.5
		var text_y := mid + fs * 0.35
		draw_string(font, Vector2(PAD, text_y), String(r["name"]), HORIZONTAL_ALIGNMENT_LEFT, _lw() - PAD * 2.0, fs, UiTheme.TEXT)  # i18n: row-ok chart data, the caller passes shown text
		var b := _x(float(r["before"]))
		var a := _x(float(r["after"]))
		var value := Num.f(float(r["before"]), 2)
		if int(r["placed"]) > 0:
			draw_line(Vector2(b, mid), Vector2(a, mid), accent, 2.0)
			draw_arc(Vector2(b, mid), RING, 0.0, TAU, 20, UiTheme.TEXT_DIM, 2.0)
			draw_circle(Vector2(a, mid), RING + 1.0, accent)
			value = "%s → %s" % [Num.f(float(r["before"]), 2), Num.f(float(r["after"]), 2)]
		else:
			draw_circle(Vector2(a, mid), 3.5, UiTheme.TEXT_DIM)
		draw_string(font, Vector2(size.x - _vw(), text_y), value, HORIZONTAL_ALIGNMENT_RIGHT, _vw(), fs, UiTheme.TEXT)
	# The axis under the rows: its two ends and the nation, in the figure's own unit.
	var s := _span()
	var ay := h * _rows.size() + fs + 2.0
	draw_string(font, Vector2(_x(s.x), ay), Num.f(s.x, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	draw_string(font, Vector2(_x(s.y) - 40.0, ay), Num.f(s.y, 1), HORIZONTAL_ALIGNMENT_RIGHT, 40.0, fs, UiTheme.TEXT_DIM)
	draw_string(font, Vector2(nx - 60.0, ay), Num.f(_nation, 2), HORIZONTAL_ALIGNMENT_CENTER, 120.0, fs, UiTheme.TEXT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := int(event.position.y / _row_h())
		if i >= 0 and i < _rows.size():
			picked.emit(String(_rows[i]["region"]))
			accept_event()


func _get_tooltip(at: Vector2) -> String:
	var i := int(at.y / _row_h())
	if i < 0 or i >= _rows.size():
		return ""
	var r: Dictionary = _rows[i]
	return "%s  %s → %s" % [String(r["name"]), Num.f(float(r["before"]), 2), Num.f(float(r["after"]), 2)]  # i18n: row-ok chart data, the caller passes shown text
