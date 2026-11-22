extends Control

## The Programmes tab's lanes (V5.3 c' register slice 2, picture C's "Programmes"): one lane a
## programme on one axis of years. The build is a neutral bar from the vote to the opening;
## after it, a dashed outline to the axis's end, "open, running cost": the unit stands for
## good. Today is a hairline in the accent (identity: "you are here"). A programme with an
## overrun ask waiting wears an amber mark ON THE DATE IT IS ANSWERED BY, its tag beside it
## ("answer by March 2026", the hourglass in an amber chip): a timeline says when (Design T1 on
## #448). Every month is the caller's (the register's).
##
## Rows: [{label, start, opens, due, tag, sub, bar_text}] with absolute months (year x 12 + month); `sub` is a dim
## second line under the label, `bar_text` is said inside the build bar, `due` (an absolute month, 0 for none) is
## where the ask's mark sits and `tag` its words. Opts (G3 S4, Building in C): label_w (0 for
## a chart with no name column), until (an absolute month the axis reaches at least: several small charts share one
## axis), axis (false: no years over the lanes), row (a lane's height at text 100), ends (true: the first lane's
## start year and opening said under it, so a small chart with no axis still reads -- Design T3 on #448).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const HOURGLASS := "res://assets/icons/ui/hourglass.svg"

const ROW := 26.0
const LABEL_W := 280.0
const BAR_H := 12.0
const DASH := 4.0

var _rows: Array = []
var _now := 0
var _first_year := 0
var _last_year := 0
var _glass: Texture2D
var _ends := false
var _label_w := LABEL_W
var _axis := true
var _row := ROW


func setup(rows: Array, now: int, opts := {}) -> void:
	_rows = rows
	_now = now
	_label_w = float(opts.get("label_w", LABEL_W))
	_axis = bool(opts.get("axis", true))
	_row = float(opts.get("row", ROW))
	_ends = bool(opts.get("ends", false))
	var last := maxi(now, int(opts.get("until", now)))
	for r in rows:
		last = maxi(last, int(r["opens"]))
	_first_year = (now - 1) / 12
	# Two years past the last opening, so every lane shows its open stretch.
	_last_year = (last - 1) / 12 + 2
	_glass = Icon.load_icon(HOURGLASS, UiTheme.WARN, _fs())
	custom_minimum_size = Vector2(0.0, _lane_h() * rows.size() + _head() + _foot())
	queue_redraw()


func data() -> Array:
	return _rows


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


func _row_h() -> float:
	return _row * UiTheme.text_scale()


## A lane: its bar's row, plus a band over it for the ask's tag when any lane has one.
func _lane_h() -> float:
	return _row_h() + _tag_h()


func _tag_h() -> float:
	for r in _rows:
		if int(r.get("due", 0)) > 0:
			return _fs() * 1.8
	return 0.0


## The row under the lanes for the ends' words, or nothing.
func _foot() -> float:
	return _fs() * 1.5 if _ends else 0.0


## The x of lane i's ask mark (its answer-by date), or -1 for a lane with no ask.
func ask_x(i: int) -> float:
	var due := int(_rows[i].get("due", 0))
	return x_of(due) if due > 0 else -1.0


## The words under a small chart: its start year and its opening, short ([] without the `ends` opt).
func ends() -> Array:
	if not _ends or _rows.is_empty():
		return []
	var start := int(_rows[0]["start"])
	var opens := int(_rows[0]["opens"])
	return [str((start - 1) / 12), DateText.mon_year((opens - 1) % 12 + 1, (opens - 1) / 12)]


## The years' row over the lanes, or nothing.
func _head() -> float:
	return ROW * UiTheme.text_scale() if _axis else 0.0


## The axis's last year: small charts built with one `until` end on the same year.
func axis_end() -> int:
	return _last_year


## The x of an absolute month on the axis, after the label column.
func x_of(month: int) -> float:
	var from := _first_year * 12 + 1
	var to := (_last_year + 1) * 12 + 1
	var w := maxf(size.x - _label_w - _fs() * 2.0, 1.0)
	return _label_w + clampf(float(month - from) / float(to - from), 0.0, 1.0) * w


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	var rh := _row_h()
	var head := _head()
	# The years along the top, one tick each (or under the lane, for a small chart with no head).
	for year in range(_first_year, _last_year + 1):
		var x := x_of(year * 12 + 1)
		if _axis:
			draw_string(font, Vector2(x + 2.0, fs), str(year), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)  # i18n: row-ok chart data
		draw_line(Vector2(x, head * 0.6 if _axis else 0.0), Vector2(x, size.y), UiTheme.EDGE, 1.0)
	var bar_h := maxf(BAR_H, rh * 0.5)
	var tag_h := _tag_h()
	for i in _rows.size():
		var r: Dictionary = _rows[i]
		var top := head + _lane_h() * i
		var mid := top + tag_h + rh * 0.5
		var sub := String(r.get("sub", ""))
		if _label_w > 0.0:
			var ly := mid + fs * 0.35 - (fs * 0.6 if sub != "" else 0.0)
			draw_string(font, Vector2(0.0, ly), String(r["label"]), HORIZONTAL_ALIGNMENT_LEFT, _label_w - 8.0, fs, UiTheme.TEXT)  # i18n: row-ok the caller translated it
			if sub != "":
				draw_string(font, Vector2(0.0, ly + fs * 1.2), sub, HORIZONTAL_ALIGNMENT_LEFT, _label_w - 8.0, fs, UiTheme.TEXT_DIM)  # i18n: row-ok the caller translated it
		var a := x_of(int(r["start"]))
		var b := x_of(int(r["opens"]))
		draw_rect(Rect2(a, mid - bar_h * 0.5, maxf(b - a, 2.0), bar_h), UiTheme.NEUTRAL_BAR)
		# Said only when it fits the bar: a short build would cut it mid-word (the line under the lanes says it too).
		if String(r.get("bar_text", "")) != "" and font.get_string_size(String(r["bar_text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= b - a - 12.0:
			draw_string(font, Vector2(a + 8.0, mid + fs * 0.35), String(r["bar_text"]), HORIZONTAL_ALIGNMENT_LEFT, maxf(b - a - 12.0, 0.0), fs, UiTheme.TEXT)  # i18n: row-ok the caller translated it
		# The open stretch: dashed, to the axis's end -- it stands for good.
		var end := x_of((_last_year + 1) * 12 + 1)
		draw_dashed_line(Vector2(b, mid - bar_h * 0.5), Vector2(end, mid - bar_h * 0.5), UiTheme.TEXT_DIM, 1.0, DASH)
		draw_dashed_line(Vector2(b, mid + bar_h * 0.5), Vector2(end, mid + bar_h * 0.5), UiTheme.TEXT_DIM, 1.0, DASH)
		if _label_w > 0.0:  # a small chart has no room for the words: its card says them
			draw_string(font, Vector2(b + 6.0, mid + fs * 0.35), Strings.t("open, running cost"), HORIZONTAL_ALIGNMENT_LEFT,
				maxf(end - b - 8.0, 0.0), fs, UiTheme.TEXT_DIM)
		if int(r.get("due", 0)) > 0:
			_tag(ask_x(i), top + tag_h * 0.5, String(r.get("tag", "")), font, fs)
	var said := ends()
	if not said.is_empty():
		var y := head + _lane_h() * _rows.size() + fs * 1.1
		var a0 := x_of(int(_rows[0]["start"])) + 4.0  # clear of today's hairline, which sits on the start
		draw_string(font, Vector2(a0, y), said[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)  # i18n: row-ok chart data
		var w1 := font.get_string_size(said[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x1 := clampf(x_of(int(_rows[0]["opens"])) - w1 * 0.5, a0 + font.get_string_size(said[0], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0,
			size.x - w1)
		draw_string(font, Vector2(x1, y), said[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)  # i18n: row-ok chart data
	# Today, over every lane.
	var t := x_of(_now)
	draw_line(Vector2(t, head * 0.6 if _axis else 0.0), Vector2(t, size.y), UiTheme.accent(), 2.0)


## The ask's mark: an amber diamond on its date, then its tag in the theme's amber chip, the hourglass first.
func _tag(x: float, y: float, text: String, font: Font, fs: int) -> void:
	var d := fs * 0.4
	draw_colored_polygon(PackedVector2Array([Vector2(x, y - d), Vector2(x + d, y), Vector2(x, y + d), Vector2(x - d, y)]), UiTheme.WARN)
	if text == "":
		return
	var box := get_theme_stylebox("panel", UiTheme.CHIP_WARN)  # a variation's items, through the theme (Control.get_theme_stylebox)
	var icon_w := float(_glass.get_width()) if _glass != null else 0.0
	var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var h := fs * 1.5
	var rect := Rect2(x + d + 6.0, y - h * 0.5, box.get_margin(SIDE_LEFT) + icon_w + 4.0 + tw + box.get_margin(SIDE_RIGHT), h)
	draw_style_box(box, rect)
	var left := rect.position.x + box.get_margin(SIDE_LEFT)
	if _glass != null:
		draw_texture(_glass, Vector2(left, y - _glass.get_height() * 0.5))
	draw_string(font, Vector2(left + icon_w + 4.0, y + fs * 0.35), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		get_theme_color("font_color", UiTheme.CHIP_TEXT))  # i18n: row-ok the caller translated it


func _get_tooltip(at: Vector2) -> String:
	var i := int(floorf((at.y - _head()) / _lane_h()))
	return String(_rows[i]["label"]) if i >= 0 and i < _rows.size() else ""  # i18n: row-ok the caller translated it
