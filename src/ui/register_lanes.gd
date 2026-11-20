extends Control

## The Programmes tab's lanes (V5.3 c' register slice 2, picture C's "Programmes"): one lane a
## programme on one axis of years. The build is a neutral bar from the vote to the opening;
## after it, a dashed outline to the axis's end, "open, running cost": the unit stands for
## good. Today is a hairline in the accent (identity: "you are here"). A programme with an
## overrun ask waiting wears the warning glyph at its row's end, and the ask is said in words
## on its card -- the glyph never alone. Every month is the caller's (the register's).
##
## Rows: [{label, start, opens, ask}] with absolute months (year x 12 + month).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")
const Strings = preload("res://src/ui/strings.gd")

const ROW := 26.0
const LABEL_W := 280.0
const BAR_H := 12.0
const DASH := 4.0

var _rows: Array = []
var _now := 0
var _first_year := 0
var _last_year := 0
var _warning: Texture2D


func setup(rows: Array, now: int) -> void:
	_rows = rows
	_now = now
	var last := now
	for r in rows:
		last = maxi(last, int(r["opens"]))
	_first_year = (now - 1) / 12
	# Two years past the last opening, so every lane shows its open stretch.
	_last_year = (last - 1) / 12 + 2
	_warning = Icon.load_icon("res://assets/icons/material/warning.svg", UiTheme.WARN, _fs())
	custom_minimum_size = Vector2(0.0, _row_h() * (rows.size() + 1))
	queue_redraw()


func data() -> Array:
	return _rows


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


func _row_h() -> float:
	return ROW * UiTheme.text_scale()


## The x of an absolute month on the axis, after the label column.
func x_of(month: int) -> float:
	var from := _first_year * 12 + 1
	var to := (_last_year + 1) * 12 + 1
	var w := maxf(size.x - LABEL_W - _fs() * 2.0, 1.0)
	return LABEL_W + clampf(float(month - from) / float(to - from), 0.0, 1.0) * w


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	var rh := _row_h()
	# The years along the top, one tick each.
	for year in range(_first_year, _last_year + 1):
		var x := x_of(year * 12 + 1)
		draw_string(font, Vector2(x + 2.0, fs), str(year), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)  # i18n: row-ok chart data
		draw_line(Vector2(x, fs + 4.0), Vector2(x, size.y), UiTheme.EDGE, 1.0)
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var top := rh * (i + 1)
		var mid := top + rh * 0.5
		draw_string(font, Vector2(0.0, mid + fs * 0.35), String(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, LABEL_W - 8.0, fs, UiTheme.TEXT)
		var a := x_of(int(r["start"]))
		var b := x_of(int(r["opens"]))
		draw_rect(Rect2(a, mid - BAR_H * 0.5, maxf(b - a, 2.0), BAR_H), UiTheme.NEUTRAL_BAR)
		# The open stretch: dashed, to the axis's end -- it stands for good.
		var end := x_of((_last_year + 1) * 12 + 1)
		draw_dashed_line(Vector2(b, mid - BAR_H * 0.5), Vector2(end, mid - BAR_H * 0.5), UiTheme.TEXT_DIM, 1.0, DASH)
		draw_dashed_line(Vector2(b, mid + BAR_H * 0.5), Vector2(end, mid + BAR_H * 0.5), UiTheme.TEXT_DIM, 1.0, DASH)
		draw_string(font, Vector2(b + 6.0, mid + fs * 0.35), Strings.t("open, running cost"), HORIZONTAL_ALIGNMENT_LEFT,
			maxf(end - b - 8.0, 0.0), fs, UiTheme.TEXT_DIM)
		if bool(r.get("ask", false)) and _warning != null:
			draw_texture(_warning, Vector2(b - _warning.get_width() - 2.0, mid - _warning.get_height() * 0.5))
	# Today, over every lane.
	var t := x_of(_now)
	draw_line(Vector2(t, fs + 4.0), Vector2(t, size.y), UiTheme.accent(), 2.0)


func _get_tooltip(at: Vector2) -> String:
	var i := int(at.y / _row_h()) - 1
	return String(_rows[i]["label"]) if i >= 0 and i < _rows.size() else ""
