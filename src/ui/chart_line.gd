extends Control

## A line over time (chart_kit.gd's `line()`): a hairline grid at round ticks, the
## first and last month under the plot, one 2px line per series with a dot and its
## value at the end -- never a number on every point. The hover names the nearest
## month and every series' value there.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const DateText = preload("res://src/ui/date_text.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")

const DOT_R := 4.0
const RING := 2.0
const PAD := 6.0

var _series: Array = []
var _months: Array = []
var _unit := ""
var _zero := false
var _range := Vector2(0.0, 1.0)
var _spark := false


func setup(series: Array, months: Array, opts := {}) -> void:
	_series = series
	_months = months
	_unit = String(opts.get("unit", ""))
	_zero = bool(opts.get("zero", false))
	_spark = bool(opts.get("spark", false))
	if opts.has("fixed"):
		_range = opts["fixed"]
	else:
		var lo := INF
		var hi := -INF
		for s in series:
			for v in (s["values"] as PackedFloat64Array):
				lo = minf(lo, v)
				hi = maxf(hi, v)
		if lo > hi:
			lo = 0.0
			hi = 1.0
		_range = ChartStyle.nice_range(lo, hi, _zero, float(opts.get("min_span", 1.0)))
	# No line, no plot: an empty grid with an invented scale reads as data. The
	# builder's caption says the chart fills in.
	custom_minimum_size = Vector2(0.0, ChartStyle.HEIGHT * UiTheme.text_scale() if has_line() else 0.0)
	if _spark:
		custom_minimum_size = Vector2(ChartStyle.SPARK.x, ChartStyle.SPARK.y * UiTheme.text_scale())
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()


## Evenly spaced along x, the range mapped onto the plot with y growing upward.
static func points(values: PackedFloat64Array, plot: Rect2, range: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := values.size()
	var span := maxf(range.y - range.x, 1e-9)
	for i in n:
		var x := plot.position.x + (plot.size.x * (float(i) / float(n - 1)) if n > 1 else 0.0)
		var y := plot.position.y + plot.size.y * (1.0 - (values[i] - range.x) / span)
		out.append(Vector2(x, y))
	return out


func has_line() -> bool:
	for s in _series:
		if (s["values"] as PackedFloat64Array).size() >= 2:
			return true
	return false


## Where the zero line sits, or -1 when the range does not cross zero.
func zero_y() -> float:
	if _range.x > 0.0 or _range.y < 0.0:
		return -1.0
	var plot := plot_rect()
	return plot.position.y + plot.size.y * (1.0 - (0.0 - _range.x) / maxf(_range.y - _range.x, 1e-9))


func _font_size() -> int:
	return roundi(UiTheme.SIZE_MICRO * UiTheme.text_scale())


## The plot inside the tick labels (left), the month band (below) and the end
## value (right), measured off the text rather than guessed.
func plot_rect() -> Rect2:
	if _spark:
		return Rect2(DOT_R, DOT_R, maxf(size.x - DOT_R * 2.0, 1.0), maxf(size.y - DOT_R * 2.0, 1.0))
	var font := get_theme_default_font()
	var fs := _font_size()
	var left := 0.0
	for t in ChartStyle.ticks(_range):
		left = maxf(left, font.get_string_size(ChartStyle.tick_text(t, _range), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var right := 0.0
	for s in _series:
		var values: PackedFloat64Array = s["values"]
		if values.size() >= 2:
			right = maxf(right, font.get_string_size(ChartStyle.figure(values[-1]) + _unit, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	var band := font.get_height(fs) + PAD
	return Rect2(left + PAD, DOT_R + RING, maxf(size.x - left - right - PAD * 3.0, 1.0),
		maxf(size.y - band - DOT_R - RING, 1.0))


func _draw() -> void:
	if not has_line():
		return
	if _spark:
		_draw_spark()
		return
	var font := get_theme_default_font()
	var fs := _font_size()
	var plot := plot_rect()
	var span := maxf(_range.y - _range.x, 1e-9)
	for t in ChartStyle.ticks(_range):
		var y := plot.position.y + plot.size.y * (1.0 - (t - _range.x) / span)
		var grid := UiTheme.TEXT_DIM if (_zero and absf(t) < 1e-9) else UiTheme.EDGE
		draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), grid, 1.0)
		draw_string(font, Vector2(0.0, y + fs * 0.35), ChartStyle.tick_text(t, _range), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	if _months.size() >= 1:
		var base := plot.end.y + font.get_ascent(fs) + PAD * 0.5
		draw_string(font, Vector2(plot.position.x, base), _month_text(0), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
		if _months.size() >= 2:
			var last := _month_text(_months.size() - 1)
			var w := font.get_string_size(last, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(plot.end.x - w, base), last, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	for i in _series.size():
		var values: PackedFloat64Array = _series[i]["values"]
		if values.size() < 2:
			continue
		var color: Color = ChartStyle.SERIES[mini(i, ChartStyle.SERIES.size() - 1)]
		var pts := points(values, plot, _range)
		draw_polyline(pts, color, 2.0, true)
		var end := pts[-1]
		draw_circle(end, DOT_R + RING, UiTheme.HULL)
		draw_circle(end, DOT_R, color)
		draw_string(font, Vector2(end.x + PAD, end.y + fs * 0.35), ChartStyle.figure(values[-1]) + _unit,
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)


## The trend beside a figure: the line in the de-emphasis grey, only the current
## month in the series colour -- no grid, no labels; the figure beside it is the value.
func _draw_spark() -> void:
	var values: PackedFloat64Array = _series[0]["values"]
	var pts := points(values, plot_rect(), _range)
	draw_polyline(pts, UiTheme.TEXT_DIM, 2.0, true)
	draw_circle(pts[-1], DOT_R - 1.0, ChartStyle.SERIES[0])


func _month_text(i: int) -> String:
	var ym: Array = _months[i]
	return DateText.month_year(int(ym[1]), int(ym[0]))


## The nearest month under the pointer, and each series' value there.
func _get_tooltip(at: Vector2) -> String:
	if not has_line() or _months.is_empty():
		return ""
	var plot := plot_rect()
	var n := _months.size()
	var i := clampi(roundi((at.x - plot.position.x) / plot.size.x * float(n - 1)), 0, n - 1)
	var lines := PackedStringArray([_month_text(i)])
	for s in _series:
		var values: PackedFloat64Array = s["values"]
		if i < values.size():
			lines.append("%s  %s%s" % [String(s["label"]), ChartStyle.figure(values[i]), _unit])  # i18n: row-ok chart data, the caller passes shown text
	return "\n".join(lines)
