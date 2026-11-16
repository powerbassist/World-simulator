extends Control

## One lane of the Presidency page's term (term_reads.gd says what): the plot slice of a
## row whose gutter and door are the page's own Controls, so a lane lines up with its
## words by sitting in the same HBox. Every lane shares one geometry: the past year on
## the left, a seam at today (the accent: "you are here"), the term to the vote on the
## right, each half on its own linear scale (the author's "Coupure en deux").
##
## Drawn in ChartKit's grammar (chart_line.gd): hairline grid, 2px lines, text in the
## text tokens, the single series in the first categorical slot, never a number on every
## point. The gutter prints every value the lane draws (the kit's table rule).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const DateText = preload("res://src/ui/date_text.gd")

enum Kind { HEAD, APPROVAL, GOAL, NOTE }

## The past half's share of the plot: a year of polls against up to five years ahead.
const SEAM := 0.4
const PAD := 6.0
const DOT_R := 4.0
## Heights at text size 100 %.
const HEIGHTS := {Kind.HEAD: 18.0, Kind.APPROVAL: 96.0, Kind.GOAL: 40.0, Kind.NOTE: 32.0}
## The narrowest approval range drawn, in points (panel_charts.gd's POLL_SPAN: a tighter
## scale draws the poll noise as a story).
const POLL_SPAN := 20.0
## The past half's left margin, px at text size 100 %: the approval ticks sit in it, clear of the line.
const LEFT := 24.0

var kind := Kind.NOTE
var _past := 0            # how many months the past half holds (PAST_MONTHS once a year is in)
var _ahead := 1           # months to the vote
var _data := {}
var _range := Vector2(0.0, 1.0)


## `past_months` is the number of history snapshots (the last is today), `ahead` the months
## to the vote; `data` per kind: HEAD {months: [[y, m], ...], today: [y, m]}, APPROVAL
## {values}, GOAL a term_reads lane, NOTE {text}.
func setup(lane_kind: Kind, past_months: int, ahead: int, data := {}) -> void:
	kind = lane_kind
	_past = past_months
	_ahead = maxi(ahead, 1)
	_data = data
	match kind:
		Kind.APPROVAL:
			_range = _span(data.get("values", PackedFloat64Array()), POLL_SPAN)
		Kind.GOAL:
			var values: PackedFloat64Array = data.get("values", PackedFloat64Array())
			var with_goal := values.duplicate()
			with_goal.append(float(data.get("goal", 0.0)))
			_range = _span(with_goal, 0.5)
	custom_minimum_size = Vector2(0.0, float(HEIGHTS[kind]) * UiTheme.text_scale())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


static func _span(values: PackedFloat64Array, min_span: float) -> Vector2:
	if values.is_empty():
		return Vector2(0.0, 100.0)
	var lo := INF
	var hi := -INF
	for v in values:
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return ChartStyle.nice_range(lo, hi, false, min_span)


func seam_x() -> float:
	return size.x * SEAM


## The x of the past snapshot `i` (0 the oldest of a full year, PAST_MONTHS - 1 today).
func past_x(i: int) -> float:
	var left := LEFT * UiTheme.text_scale()
	return left + (seam_x() - left) * float(i) / 11.0


## The x of `m` months after today.
func future_x(m: int) -> float:
	return seam_x() + (size.x - seam_x() - PAD) * clampf(float(m) / float(_ahead), 0.0, 1.0)


func _y(v: float, top: float, bottom: float) -> float:
	return bottom - (bottom - top) * (v - _range.x) / maxf(_range.y - _range.x, 1e-9)


func _fs() -> int:
	return roundi(UiTheme.SIZE_MICRO * UiTheme.text_scale())


## The values laid on the past half, newest at the seam: a short history sits at its right end.
func _past_points(values: PackedFloat64Array, top: float, bottom: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := values.size()
	for i in n:
		out.append(Vector2(past_x(12 - n + i), _y(values[i], top, bottom)))
	return out


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	match kind:
		Kind.HEAD:
			_draw_head(font, fs)
		Kind.APPROVAL:
			_draw_approval(font, fs)
		Kind.GOAL:
			_draw_goal(font, fs)
		Kind.NOTE:
			draw_string(font, Vector2(seam_x() + PAD * 2.0, size.y * 0.5 + fs * 0.35), String(_data.get("text", "")),
				HORIZONTAL_ALIGNMENT_LEFT, size.x - seam_x() - PAD * 3.0, fs, UiTheme.TEXT_DIM)
	if kind != Kind.HEAD:
		draw_line(Vector2(seam_x(), 0.0), Vector2(seam_x(), size.y), UiTheme.accent(), 1.5)


## Every third month in the past half, each January ahead, "today" at the seam, the vote at the end.
func _draw_head(font: Font, fs: int) -> void:
	var months: Array = _data.get("months", [])
	var base := font.get_ascent(fs)
	for i in months.size():
		if (months.size() - 1 - i) % 3 != 0 or i == months.size() - 1:
			continue
		var ym: Array = months[i]
		draw_string(font, Vector2(past_x(12 - months.size() + i), base),
			DateText.month_year(int(ym[1]), int(ym[0])).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	draw_string(font, Vector2(seam_x() + 4.0, base), tr("TODAY"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.accent())
	var today: Array = _data.get("today", [2000, 1])
	var first_jan := 13 - int(today[1])
	var m := first_jan
	while m < _ahead:
		var x := future_x(m)
		if x > seam_x() + 60.0 and x < size.x - 70.0:
			draw_string(font, Vector2(x, base), str(int(today[0]) + (m + int(today[1]) - 1) / 12),
				HORIZONTAL_ALIGNMENT_CENTER, -1, fs, UiTheme.TEXT_DIM)
		m += 12
	var vote := tr("VOTE")
	var w := font.get_string_size(vote, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	draw_string(font, Vector2(size.x - w - PAD, base), vote, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)


func _draw_approval(font: Font, fs: int) -> void:
	var top := DOT_R + 2.0
	var bottom := size.y - DOT_R - 2.0
	var values: PackedFloat64Array = _data.get("values", PackedFloat64Array())
	_draw_vote(size.y * 0.5)
	# No line, no grid: an empty scale with invented ticks reads as data (chart_line.gd's rule);
	# the gutter says the line fills in.
	if values.size() < 2:
		return
	for t in ChartStyle.ticks(_range):
		var y := _y(t, top, bottom)
		draw_line(Vector2(0.0, y), Vector2(size.x - PAD, y), UiTheme.EDGE, 1.0)
		draw_string(font, Vector2(2.0, y - 2.0), ChartStyle.tick_text(t, _range), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	var color: Color = ChartStyle.SERIES[0]
	draw_polyline(_past_points(values, top, bottom), color, 2.0, true)
	var end := Vector2(seam_x(), _y(values[-1], top, bottom))
	draw_circle(end, DOT_R + 2.0, UiTheme.HULL)
	draw_circle(end, DOT_R, color)


## The vote at the far end: a diamond, the term's last mark.
func _draw_vote(y: float) -> void:
	var x := size.x - PAD - 6.0
	draw_colored_polygon(PackedVector2Array([Vector2(x, y - 6.0), Vector2(x + 6.0, y), Vector2(x, y + 6.0), Vector2(x - 6.0, y)]), UiTheme.TEXT)


func _draw_goal(font: Font, fs: int) -> void:
	var top := 6.0
	var bottom := size.y - 6.0
	var goal_y := _y(float(_data.get("goal", 0.0)), top, bottom)
	draw_dashed_line(Vector2(0.0, goal_y), Vector2(seam_x(), goal_y), UiTheme.TEXT_DIM, 1.0, 4.0)
	var values: PackedFloat64Array = _data.get("values", PackedFloat64Array())
	if values.size() >= 2:
		draw_polyline(_past_points(values, top, bottom), UiTheme.TEXT, 2.0, true)
	var chosen := int(_data.get("chosen", -1))
	if chosen >= 0:
		var cx := past_x(12 - _past + chosen)
		draw_line(Vector2(cx, 2.0), Vector2(cx, size.y - 2.0), UiTheme.TEXT_DIM, 1.0)
	var mid := size.y * 0.5
	var due := int(_data.get("due", -1))
	if due < 0:
		return
	var dx := future_x(due)
	draw_line(Vector2(seam_x(), mid), Vector2(dx, mid), UiTheme.EDGE, 4.0)
	draw_line(Vector2(dx, mid - 8.0), Vector2(dx, mid + 8.0), UiTheme.TEXT, 2.0)
	var words := String(_data.get("due_text", ""))
	var w := font.get_string_size(words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var tx := dx - w - PAD if dx - w - PAD > seam_x() + PAD else dx + PAD
	draw_string(font, Vector2(tx, mid - 7.0), words, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
