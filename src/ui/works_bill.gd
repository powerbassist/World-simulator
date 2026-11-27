extends Control

## The works' bill by year (G3 S4 PR 2c, works-a-calendar.png), on the lanes' own axis
## (WorksLane.x_at): what is signed, a neutral step that drops the month each work opens, and
## "with the picked work" as a white dashed step over it. % of GDP a year, the unit the sim
## bills in (Projects.bill_pct_gdp). One neutral data colour; the accent marks nothing here.
## Its y ticks sit left of the plot, in the words column's right end (TICKS_EM wide), and a
## value's label sits above its own line, clear of every drop and gridline (Design's T3 on #450).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const WorksRows = preload("res://src/ui/works_rows.gd")
const WorksLane = preload("res://src/ui/works_lane.gd")

const DASH := 4.0
## The room the y ticks take left of the plot, in ems of the caption size: "0.40" and its gap.
const TICKS_EM := 3.0

var _rows: Array = []
var _first := 0
var _last := 1
## Today: the picked offer would be paid from now, never over the months already past.
var _now := 0
var _with := ""
var _with_name := ""
var _top := 0.1


func setup(rows: Array, first: int, last: int, now: int, with_id: String, with_name: String) -> void:
	_rows = rows
	_now = now
	_first = first
	_last = maxi(last, first + 12)
	_with = with_id
	_with_name = with_name
	_top = 0.1
	for m in range(_first, _last + 1):
		_top = maxf(_top, _at(m, _with))
	_top = ceilf(_top * 10.0) / 10.0  # a round top: 0.4 for 0.33
	custom_minimum_size.y = _fs() * 9.0
	queue_redraw()


func x_of(month: int) -> float:
	return WorksLane.x_at(month, _first, _last, size.x)


func global_x(month: int) -> float:
	return global_position.x + x_of(month)


## The foot's years, thinned as the lanes' head row is (WorksLane.years_across).
func year_labels() -> Array:
	return WorksLane.years_across(_first, _last, size.x, get_theme_default_font(), _fs())


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


func _y(value: float) -> float:
	var fs := _fs()
	return size.y - fs * 1.6 - value / _top * (size.y - fs * 3.2)


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	var signed := _steps("")
	var with := _steps(_with) if _with != "" else PackedVector2Array()
	var labels := _labels(font, fs, [signed, with])
	for value in [0.0, _top * 0.5, _top]:
		_gridline(_y(value), labels)
		var tick := Num.f(value, 2)
		var w := font.get_string_size(tick, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2(-6.0 - w, _y(value) + fs * 0.35), tick, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)  # i18n: row-ok a figure
	for label in year_labels():
		draw_string(font, Vector2(label[1].position.x, size.y - 2.0), str(label[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)  # i18n: row-ok chart data
	if signed.size() > 1:
		var area := PackedVector2Array(signed)
		area.append(Vector2(signed[signed.size() - 1].x, _y(0.0)))
		area.append(Vector2(signed[0].x, _y(0.0)))
		draw_colored_polygon(area, Color(UiTheme.NEUTRAL_BAR, 0.5))
		draw_polyline(signed, UiTheme.NEUTRAL_BAR, 2.0)
	for i in with.size() - 1:
		draw_dashed_line(with[i], with[i + 1], UiTheme.TEXT, 1.5, DASH)
	for label in labels:
		draw_string(font, Vector2(label[0].position.x, label[0].end.y - font.get_descent(fs)), label[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, label[2])


## Each value's label and its box: 4 px above its own line, from today, moved right past any
## drop of either line that would cross it. [[Rect2, words, colour], ...]
func _labels(font: Font, fs: int, lines: Array) -> Array:
	var drops: Array[float] = []
	for line in lines:
		for i in range(1, line.size()):
			if is_equal_approx(line[i].x, line[i - 1].x):
				drops.append(line[i].x)
	drops.sort()
	var out := []
	var now0 := WorksRows.bill_at(_rows, _now)
	var said := [[now0, tr("%s signed") % Num.f(now0, 2), UiTheme.TEXT_DIM]]
	if _with != "":
		said.append([_at(_now, _with), tr("%s with it") % Num.f(_at(_now, _with), 2), UiTheme.TEXT])
	for s in said:
		var w := font.get_string_size(s[1], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := x_of(_now) + 8.0
		for d in drops:
			if d >= x - 2.0 and d <= x + w + 2.0:
				x = d + 6.0
		out.append([Rect2(x, _y(s[0]) - 4.0 - font.get_height(fs), w, font.get_height(fs)), s[1], s[2]])
	return out


## A gridline across the plot, broken where a label sits on it.
func _gridline(y: float, labels: Array) -> void:
	var x := 0.0
	var cuts: Array = []
	for label in labels:
		var box: Rect2 = label[0]
		if y >= box.position.y - 2.0 and y <= box.end.y + 2.0:
			cuts.append(Vector2(box.position.x - 4.0, box.end.x + 4.0))
	cuts.sort_custom(func(a, b): return a.x < b.x)
	for cut in cuts:
		if cut.x > x:
			draw_line(Vector2(x, y), Vector2(cut.x, y), UiTheme.EDGE, 1.0)
		x = maxf(x, cut.y)
	if x < size.x:
		draw_line(Vector2(x, y), Vector2(size.x, y), UiTheme.EDGE, 1.0)


## The step line of the bill from the axis's first month to its last, a corner at each change.
func _steps(with_id: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var was := -1.0
	for m in range(_first, _last + 1):
		var v := _at(m, with_id)
		if v != was:
			if was >= 0.0:
				out.append(Vector2(x_of(m), _y(was)))
			out.append(Vector2(x_of(m), _y(v)))
			was = v
	out.append(Vector2(x_of(_last), _y(was)))
	return out


## The bill in `month`, the offer `with_id` added only from today on.
func _at(month: int, with_id: String) -> float:
	return WorksRows.bill_at(_rows, month, with_id if month >= _now else "")


func _get_tooltip(at: Vector2) -> String:
	var m := _first + roundi(at.x / maxf(size.x, 1.0) * float(_last - _first))
	var when := DateText.mon_year((m - 1) % 12 + 1, (m - 1) / 12)
	if _with == "":
		return tr("%s: %s %% of GDP a year") % [when, Num.f(WorksRows.bill_at(_rows, m), 2)]
	return tr("%s: %s %% of GDP a year; %s with %s") % [when, Num.f(WorksRows.bill_at(_rows, m), 2), Num.f(_at(m, _with), 2), _with_name]
