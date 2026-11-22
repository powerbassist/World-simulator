extends Control

## A dot plot of before and after -- ChartKit.dots (V5.3 c', the bureau audit's item 4: the
## register's region chart first, Sectors and Finances next). One row per item on one axis:
## a ring is the value before, a filled dot the value after (TEXT: no quantity wears the accent), joined by a line,
## for a row that moves; a row that does not is a small dim dot. Optional:
##   reference  one vertical hairline (the nation's figure) with its value under the axis;
##   label_w    the name column's width at text 100 (LABEL_W by default);
##   value_w    the value column's width at text 100 (VALUE_W by default);
##   fixed      Vector2(lo, hi): the axis, whatever the values (the Finances tray's one 0-25 % scale);
##   band       Vector2(lo, hi) on the axis, shaded in the attention tone, and a warning
##              glyph (Material Symbols) on each row whose before lies inside it -- the tone
##              never alone (the bad-news tone: a region this far behind is bad news);
##   row        a row's height at text 100 (ROW by default; the register's rows hold a stepper);
##   head       {label, value, reference}: a head row over the plot, the columns' names and the axis there instead
##              of under the rows (reference is a "%s" sentence for the reference's value).
## Values are printed at the row's end, so the chart never gates a number (the dataviz
## method's table view); a click on a row emits `picked(id)`.
##
## Rows: [{id, label, before, after, moved, selected, text}] -- shown text and the caller's figures; `text`, when given,
## is printed in place of the row's figures (a unit the plot's decimals cannot say).

signal picked(id: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")
const Icon = preload("res://src/ui/icon.gd")

const ROW := 24.0
const LABEL_W := 200.0
const VALUE_W := 110.0
const PAD := 8.0
const RING := 5.0
const BAND_FILL := Color(UiTheme.BAD, 0.12)  ## the bad-news tone, faint: a zone, not a mark

var _rows: Array = []
var _reference := NAN
var _band := Vector2(NAN, NAN)
var _fixed := Vector2(NAN, NAN)
var _places := 2
## The value column's width at text 100 (opts.value_w): a row's own `text` with a unit needs more than a bare figure.
var _value_w := VALUE_W
## The name column's width at text 100 (opts.label_w).
var _label_w := LABEL_W
var _warning: Texture2D
var _row := ROW
var _head := {}


func setup(rows: Array, opts := {}) -> void:
	_rows = rows
	_reference = float(opts.get("reference", NAN))
	_band = opts.get("band", Vector2(NAN, NAN))
	_fixed = opts.get("fixed", Vector2(NAN, NAN))
	_places = int(opts.get("places", 2))
	_value_w = float(opts.get("value_w", VALUE_W))
	_label_w = float(opts.get("label_w", LABEL_W))
	_row = float(opts.get("row", ROW))
	_head = opts.get("head", {})
	_warning = Icon.load_icon("res://assets/icons/material/warning.svg", UiTheme.BAD, _fs()) if not is_nan(_band.x) else null
	custom_minimum_size = Vector2(0.0, row_height() * (rows.size() + 1))
	mouse_filter = Control.MOUSE_FILTER_STOP
	queue_redraw()


func data() -> Array:
	return _rows


func row_height() -> float:
	return _row * UiTheme.text_scale()


## Where the first row starts: under the head row when there is one.
func _top() -> float:
	return row_height() if not _head.is_empty() else 0.0


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


## The name and value columns grow with the text size, or a long name is cut at the former 130 % text size.
func _lw() -> float:
	return _label_w * UiTheme.text_scale()


func _vw() -> float:
	return _value_w * UiTheme.text_scale()


## The axis: every value drawn and the reference, with a margin so no mark sits on an edge.
## The band is clipped to it, never widens it.
func _span() -> Vector2:
	if not is_nan(_fixed.x):
		return _fixed
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
	var top := _top()
	var bottom := top + h * _rows.size()
	# The picked row's plate and the band first, so the hairline and the marks cross them.
	for i in _rows.size():
		if bool(_rows[i].get("selected", false)):
			draw_rect(Rect2(0.0, top + h * i, size.x, h), UiTheme.SLATE)
			draw_rect(Rect2(0.0, top + h * i, 3.0, h), accent)
	if not is_nan(_band.x):
		var bx := _x(_band.x)
		draw_rect(Rect2(bx, top, _x(_band.y) - bx, bottom - top), BAND_FILL)
	if not is_nan(_reference):
		draw_line(Vector2(_x(_reference), top), Vector2(_x(_reference), bottom), UiTheme.TEXT_DIM, 1.0)
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var mid := top + h * i + h * 0.5
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
			draw_line(Vector2(b, mid), Vector2(a, mid), UiTheme.TEXT_DIM, 2.0)
			draw_arc(Vector2(b, mid), RING, 0.0, TAU, 20, UiTheme.TEXT_DIM, 2.0)
			draw_circle(Vector2(a, mid), RING + 1.0, UiTheme.TEXT)
			value = "%s → %s" % [Num.f(float(r["before"]), _places), Num.f(float(r["after"]), _places)]
		else:
			draw_circle(Vector2(a, mid), 3.5, UiTheme.TEXT_DIM)
		value = String(r.get("text", value))  # i18n: row-ok the caller's shown figures (the Finances tray's units)
		draw_string(font, Vector2(size.x - _vw(), text_y), value, HORIZONTAL_ALIGNMENT_RIGHT, _vw(), fs, UiTheme.TEXT)
	var s := _span()
	if not _head.is_empty():
		_draw_head(font, fs, s)
		return
	var ay := bottom + fs + 2.0
	# At the chart's own decimals: a duty in EUR/l read "0.7 ... 0.7" at one.
	draw_string(font, Vector2(_x(s.x), ay), Num.f(s.x, _places), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	draw_string(font, Vector2(_x(s.y) - 60.0, ay), Num.f(s.y, _places), HORIZONTAL_ALIGNMENT_RIGHT, 60.0, fs, UiTheme.TEXT_DIM)
	if not is_nan(_reference):
		draw_string(font, Vector2(_x(_reference) - 60.0, ay), Num.f(_reference, _places), HORIZONTAL_ALIGNMENT_CENTER, 120.0, fs, UiTheme.TEXT)


func _said() -> String:
	return String(_head.get("reference", "%s")) % Num.f(_reference, _places)  # i18n: row-ok the caller passes shown text


## Where the reference's sentence sits on the head row, a little air either side.
func _said_span(font: Font, fs: int) -> Vector2:
	var half := font.get_string_size(_said(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5 + 6.0
	return Vector2(_x(_reference) - half, _x(_reference) + half)


## Which axis-end figures the head row draws, [lo, hi]: one the reference's sentence would cover is left out, the
## sentence being the one that says what the line is (pass 2 T5 on #447).
func head_ends_shown() -> Array:
	if _head.is_empty() or is_nan(_reference):
		return [true, true]
	var font := get_theme_default_font()
	var fs := _fs()
	var s := _span()
	var taken := _said_span(font, fs)
	var lo_end := _x(s.x) + font.get_string_size(Num.f(s.x, _places), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var hi_start := _x(s.y) - font.get_string_size(Num.f(s.y, _places), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	return [lo_end < taken.x or _x(s.x) > taken.y, _x(s.y) < taken.x or hi_start > taken.y]


## The head row: the name column's title, the axis's ends and the reference said, the value column's title.
func _draw_head(font: Font, fs: int, s: Vector2) -> void:
	var y := row_height() * 0.5 + fs * 0.35
	draw_string(font, Vector2(PAD, y), String(_head.get("label", "")).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, _lw() - PAD * 2.0, fs, UiTheme.TEXT_DIM)  # i18n: row-ok the caller passes shown text
	if not is_nan(_reference):
		draw_string(font, Vector2(_said_span(font, fs).x + 6.0, y), _said(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)
	var shown := head_ends_shown()
	var hi := Num.f(s.y, _places)
	if shown[0]:
		draw_string(font, Vector2(_x(s.x), y), Num.f(s.x, _places), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	if shown[1]:
		draw_string(font, Vector2(_x(s.y) - font.get_string_size(hi, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, y), hi, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	draw_string(font, Vector2(size.x - _vw(), y), String(_head.get("value", "")).to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, _vw(), fs, UiTheme.TEXT_DIM)  # i18n: row-ok the caller passes shown text


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i := int(floorf((event.position.y - _top()) / row_height()))
		if i >= 0 and i < _rows.size():
			picked.emit(String(_rows[i]["id"]))
			accept_event()


func _get_tooltip(at: Vector2) -> String:
	var i := int(floorf((at.y - _top()) / row_height()))
	if i < 0 or i >= _rows.size():
		return ""
	var r: Dictionary = _rows[i]
	return "%s  %s → %s" % [String(r["label"]), Num.f(float(r["before"]), _places), Num.f(float(r["after"]), _places)]  # i18n: row-ok chart data, the caller passes shown text
