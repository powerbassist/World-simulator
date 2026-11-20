extends Control

## A dot plot of before and after -- ChartKit.dots (V5.3 c', the bureau audit's item 4: the
## register's region chart first, Sectors and Finances next). One row per item on one axis:
## a ring is the value before, a filled dot in the accent the value after, joined by a line,
## for a row that moves; a row that does not is a small dim dot. Optional:
##   reference  one vertical hairline (the nation's figure) with its value under the axis;
##   band       Vector2(lo, hi) on the axis, shaded in the attention tone, and a warning
##              glyph (Material Symbols) on each row whose before lies inside it -- the tone
##              never alone.
## Values are printed at the row's end, so the chart never gates a number (the dataviz
## method's table view); a click on a row emits `picked(id)`.
##
## Rows: [{id, label, before, after, moved, selected}] -- shown text and the caller's figures.

signal picked(id: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")
const Icon = preload("res://src/ui/icon.gd")

const ROW := 24.0
const LABEL_W := 200.0
const VALUE_W := 110.0
const PAD := 8.0
const RING := 5.0
const BAND_FILL := Color(0.890, 0.651, 0.227, 0.10)  ## UiTheme.WARN at 10 %: a zone, not a mark

var _rows: Array = []
var _reference := NAN
var _band := Vector2(NAN, NAN)
var _places := 2
var _warning: Texture2D


func setup(rows: Array, opts := {}) -> void:
	_rows = rows
	_reference = float(opts.get("reference", NAN))
	_band = opts.get("band", Vector2(NAN, NAN))
	_places = int(opts.get("places", 2))
	_warning = Icon.load_icon("res://assets/icons/material/warning.svg", UiTheme.WARN, _fs()) if not is_nan(_band.x) else null
	custom_minimum_size = Vector2(0.0, row_height() * (rows.size() + 1))
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func data() -> Array:
	return _rows


func row_height() -> float:
	return ROW * UiTheme.text_scale()


func in_band(i: int) -> bool:
	if is_nan(_band.x):
		return false
	var v := float(_rows[i]["before"])
	return v >= _band.x and v <= _band.y


func mark_x(i: int, key: String) -> float:
	return _x(float(_rows[i][key]))


func reference_x() -> float:
	return _x(_reference) if not is_nan(_reference) else NAN


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


## The name and value columns grow with the text size, or a long name is cut at 130 %.
func _lw() -> float:
	return LABEL_W * UiTheme.text_scale()


func _vw() -> float:
	return VALUE_W * UiTheme.text_scale()


## The axis: every value drawn and the reference, with a margin so no mark sits on an edge.
## The band is clipped to it, never widens it.
func _span() -> Vector2:
	var lo := INF
	var hi := -INF
	for r in _rows:
		for k in ["before", "after"]:
			lo = minf(lo, float(r[k]))
			hi = maxf(hi, float(r[k]))
	if not is_nan(_reference):
		lo = minf(lo, _reference)
		hi = maxf(hi, _reference)
	if lo == INF:
		return Vector2(0.0, 1.0)
	var pad := maxf((hi - lo) * 0.08, 0.01)
	return Vector2(lo - pad, hi + pad)


func _x(v: float) -> float:
	var s := _span()
	var w := maxf(size.x - _lw() - _vw() - PAD * 2.0, 1.0)
	return _lw() + PAD + (clampf(v, s.x, s.y) - s.x) / maxf(s.y - s.x, 1e-9) * w


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	var h := row_height()
	var accent := UiTheme.accent()
	var bottom := h * _rows.size()
	# The picked row's plate and the band first, so the hairline and the marks cross them.
	for i in _rows.size():
		if bool(_rows[i].get("selected", false)):
			draw_rect(Rect2(0.0, h * i, size.x, h), UiTheme.SLATE)
			draw_rect(Rect2(0.0, h * i, 3.0, h), accent)
	if not is_nan(_band.x):
		var bx := _x(_band.x)
		draw_rect(Rect2(bx, 0.0, _x(_band.y) - bx, bottom), BAND_FILL)
	if not is_nan(_reference):
		draw_line(Vector2(_x(_reference), 0.0), Vector2(_x(_reference), bottom), UiTheme.TEXT_DIM, 1.0)
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var mid := h * i + h * 0.5
		var text_y := mid + fs * 0.35
		var name_x := PAD
		if in_band(i) and _warning != null:
			draw_texture(_warning, Vector2(PAD, mid - fs * 0.5))
			name_x += fs + 4.0
		draw_string(font, Vector2(name_x, text_y), String(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, _lw() - name_x - PAD, fs, UiTheme.TEXT)  # i18n: row-ok chart data, the caller passes shown text
		var b := _x(float(r["before"]))
		var a := _x(float(r["after"]))
		# The value printed is the value drawn: an untouched row's dot sits at its after.
		var value := Num.f(float(r["after"]), _places)
		if bool(r.get("moved", false)):
			draw_line(Vector2(b, mid), Vector2(a, mid), accent, 2.0)
			draw_arc(Vector2(b, mid), RING, 0.0, TAU, 20, UiTheme.TEXT_DIM, 2.0)
			draw_circle(Vector2(a, mid), RING + 1.0, accent)
			value = "%s → %s" % [Num.f(float(r["before"]), _places), Num.f(float(r["after"]), _places)]
		else:
			draw_circle(Vector2(a, mid), 3.5, UiTheme.TEXT_DIM)
		draw_string(font, Vector2(size.x - _vw(), text_y), value, HORIZONTAL_ALIGNMENT_RIGHT, _vw(), fs, UiTheme.TEXT)
	var s := _span()
	var ay := bottom + fs + 2.0
	draw_string(font, Vector2(_x(s.x), ay), Num.f(s.x, 1), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	draw_string(font, Vector2(_x(s.y) - 40.0, ay), Num.f(s.y, 1), HORIZONTAL_ALIGNMENT_RIGHT, 40.0, fs, UiTheme.TEXT_DIM)
	if not is_nan(_reference):
		draw_string(font, Vector2(_x(_reference) - 60.0, ay), Num.f(_reference, _places), HORIZONTAL_ALIGNMENT_CENTER, 120.0, fs, UiTheme.TEXT)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := int(event.position.y / row_height())
		if i >= 0 and i < _rows.size():
			picked.emit(String(_rows[i]["id"]))
			accept_event()


func _get_tooltip(at: Vector2) -> String:
	var i := int(at.y / row_height())
	if i < 0 or i >= _rows.size():
		return ""
	var r: Dictionary = _rows[i]
	return "%s  %s → %s" % [String(r["label"]), Num.f(float(r["before"]), _places), Num.f(float(r["after"]), _places)]  # i18n: row-ok chart data, the caller passes shown text
