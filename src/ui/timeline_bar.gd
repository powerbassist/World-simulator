extends Control

## One lane of the Sectors timeline (sectors_timeline.gd), or its month axis, or a legend
## swatch: the Diary's trip band (diary_band.gd) is its nearest relative, drawn the same way
## (a capsule on the sheet, no gradient). Month 0 is the first day of this month at x = 0;
## today sits at `today` (0..1 of the month). Everything left of today is past and drawn
## nothing: a bar runs from today, the sim keeps no start for a process.
##
## Styles: DUE, a bar to the answer's date and an amber diamond on it (the one mark that
## says "this waits on you"); BAR, a neutral bar to its end; WINDOW, an outline to the date
## a window closes, neutral because nothing is due; RUNNING, a neutral bar to the scale's
## edge with its words inside, a programme that runs until it is stopped. Chips (answer by,
## then, unanswered) sit after the bar's end, as children, so they read and wrap as chips.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const DateText = preload("res://src/ui/date_text.gd")

const DUE := "due"  # i18n: ok a style id
const BAR := "bar"  # i18n: ok a style id
const WINDOW := "window"  # i18n: ok a style id
const RUNNING := "running"  # i18n: ok a style id

## The lane's height and the bar's thickness, in px at text size 100.
const LANE_H := 34.0
const BAR_H := 18.0
const DIAMOND := 7.0
const CHIP_GAP := 8.0
const SWATCH := Vector2(28, 12)

var style := ""
var span := 6
var today := 0.0
var ends := -1
var due := -1
var inside := ""
var _axis := false
var _month := 1
var _year := 2026
var _chips: HBoxContainer
var _swatch := false
## Kept on the node, not made in _draw(): a box local to _draw() can be freed before the
## renderer reads it.
var _fill := StyleBoxFlat.new()
var _outline := StyleBoxFlat.new()


func setup(kind: String, months: int, now: float, end_month: int, due_month: int, words: String, chips: Array) -> void:
	style = kind
	span = maxi(months, 1)
	today = now
	ends = end_month
	due = due_month
	inside = words
	custom_minimum_size.y = roundf(LANE_H * UiTheme.text_scale())
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", 6)
	add_child(_chips)
	for c in chips:
		var chip := PanelKit.chip(_chips, String(c[0]), String(c[1]), String(c[2]))
		for label in chip.find_children("*", "Label", true, false):  # i18n: ok a class name
			(label as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
	resized.connect(_place_chips)
	_chips.minimum_size_changed.connect(_place_chips)
	queue_redraw()


## The month axis: the month names at their first day, today's line.
func axis(month: int, year: int, months: int, now: float) -> void:
	_axis = true
	_month = month
	_year = year
	span = maxi(months, 1)
	today = now
	custom_minimum_size.y = roundf(22.0 * UiTheme.text_scale())
	queue_redraw()


## A legend swatch: the style's mark alone.
func key(kind: String) -> void:
	style = kind
	_swatch = true
	custom_minimum_size = (SWATCH * UiTheme.text_scale()).round()
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	queue_redraw()


## The x of month offset `m` (its first day), in this lane.
func x_of(m: float) -> float:
	return clampf(m / float(span), 0.0, 1.0) * size.x


## Where the bar ends: its end, or the scale's edge for a programme.
func end_x() -> float:
	if style == RUNNING or ends < 0:
		return size.x
	return maxf(x_of(float(ends)), x_of(today) + 4.0)


## The chips after the bar's end, or, when they do not fit there, on a second line under it at
## the same x (clamped in): a chip laid over its own bar hid the diamond it dates.
func _place_chips() -> void:
	if _chips == null:
		return
	var w := _chips.get_combined_minimum_size()
	var x := (x_of(float(due)) if due >= 0 else end_x()) + CHIP_GAP * UiTheme.text_scale()
	var lane := roundf(LANE_H * UiTheme.text_scale())
	var two := w.x > 0.0 and x + w.x > size.x
	var want := lane * (2.0 if two else 1.0)
	if custom_minimum_size.y != want:
		custom_minimum_size.y = want
	_chips.position = Vector2(clampf(x, 0.0, maxf(size.x - w.x, 0.0)) if two else x, (lane if two else 0.0) + (lane - w.y) / 2.0)
	_chips.size = w
	queue_redraw()


func _draw() -> void:
	if _axis:
		_draw_axis()
		return
	if _swatch:
		# Room on the right for the diamond, which is drawn centred on the bar's end.
		var d := DIAMOND * UiTheme.text_scale()
		_draw_mark(Rect2(0, (size.y - d * 1.4) / 2.0, size.x - d, d * 1.4))
		return
	var h := roundf(BAR_H * UiTheme.text_scale())
	var y := (roundf(LANE_H * UiTheme.text_scale()) - h) / 2.0
	draw_line(Vector2(x_of(today), 0), Vector2(x_of(today), size.y), UiTheme.accent(), 2.0)
	var from := x_of(today)
	var to := end_x() if style != DUE else maxf(x_of(float(due)), from + 4.0)
	_draw_mark(Rect2(from, y, to - from, h))
	if inside != "" and style in [RUNNING, WINDOW, BAR]:
		var font := get_theme_default_font()
		var fs := roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())
		var room := to - from - 16.0
		if room > 24.0:
			draw_string(font, Vector2(from + 8.0, y + h / 2.0 + font.get_ascent(fs) / 2.0 - 2.0), inside,
				HORIZONTAL_ALIGNMENT_LEFT, room, fs, UiTheme.TEXT)


func _draw_mark(r: Rect2) -> void:
	var radius := r.size.y / 2.0
	if style == WINDOW:
		_outline.draw_center = false
		_outline.set_border_width_all(1)
		_outline.border_color = UiTheme.TEXT_DIM
		_outline.set_corner_radius_all(int(radius))
		draw_style_box(_outline, r)
		return
	_fill.bg_color = UiTheme.NEUTRAL_BAR
	_fill.set_corner_radius_all(int(radius))
	draw_style_box(_fill, r)
	if style == DUE:
		var c := Vector2(r.end.x, r.position.y + radius)
		var d := DIAMOND * UiTheme.text_scale()
		draw_colored_polygon(PackedVector2Array([c + Vector2(0, -d), c + Vector2(d, 0), c + Vector2(0, d), c + Vector2(-d, 0)]), UiTheme.WARN)


func _draw_axis() -> void:
	var font := get_theme_default_font()
	var fs := roundi(UiTheme.SIZE_MICRO * UiTheme.text_scale())
	for m in span:
		var t := _year * 12 + _month + m
		var month := (t - 1) % 12 + 1
		var year := floori((t - 1) / 12.0)
		var words := DateText.month(month) if month != 1 or m == 0 else DateText.month_year(month, year)
		var x := x_of(float(m))
		if m > 0:
			draw_line(Vector2(x, size.y - 4.0), Vector2(x, size.y), UiTheme.EDGE, 1.0)
		draw_string(font, Vector2(x + 4.0, size.y - 6.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			UiTheme.accent() if m == 0 else UiTheme.TEXT_DIM)
	draw_line(Vector2(x_of(today), 0), Vector2(x_of(today), size.y), UiTheme.accent(), 2.0)
