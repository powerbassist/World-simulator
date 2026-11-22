extends Control

## The works' bill by year (G3 S4 PR 2c, works-a-calendar.png), on the lanes' own axis
## (WorksLane.x_at): what is signed, a neutral step that drops the month each work opens, and
## "with the picked work" as a white dashed step over it. % of GDP a year, the unit the sim
## bills in (Projects.bill_pct_gdp). One neutral data colour; the accent marks nothing here.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const WorksRows = preload("res://src/ui/works_rows.gd")
const WorksLane = preload("res://src/ui/works_lane.gd")

const DASH := 4.0

var _rows: Array = []
var _first := 0
var _last := 1
var _with := ""
var _with_name := ""
var _top := 0.1


func setup(rows: Array, first: int, last: int, with_id: String, with_name: String) -> void:
	_rows = rows
	_first = first
	_last = maxi(last, first + 12)
	_with = with_id
	_with_name = with_name
	_top = 0.1
	for m in range(_first, _last + 1):
		_top = maxf(_top, WorksRows.bill_at(_rows, m, _with))
	_top = ceilf(_top * 10.0) / 10.0  # a round top: 0.4 for 0.33
	custom_minimum_size.y = _fs() * 9.0
	queue_redraw()


func x_of(month: int) -> float:
	return WorksLane.x_at(month, _first, _last, size.x)


func global_x(month: int) -> float:
	return global_position.x + x_of(month)


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


func _y(value: float) -> float:
	var fs := _fs()
	return size.y - fs * 1.6 - value / _top * (size.y - fs * 3.2)


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	for value in [0.0, _top * 0.5, _top]:
		draw_line(Vector2(0.0, _y(value)), Vector2(size.x, _y(value)), UiTheme.EDGE, 1.0)
		draw_string(font, Vector2(2.0, _y(value) - 3.0), Num.f(value, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)  # i18n: row-ok a figure
	for year in range((_first - 1) / 12, (_last - 1) / 12 + 1):
		var x := x_of(year * 12 + 1)
		if year * 12 + 1 >= _first:
			draw_string(font, Vector2(x - fs, size.y - 2.0), str(year), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)  # i18n: row-ok chart data
	var signed := _steps("")
	if signed.size() > 1:
		var area := PackedVector2Array(signed)
		area.append(Vector2(signed[signed.size() - 1].x, _y(0.0)))
		area.append(Vector2(signed[0].x, _y(0.0)))
		draw_colored_polygon(area, Color(UiTheme.NEUTRAL_BAR, 0.5))
		draw_polyline(signed, UiTheme.NEUTRAL_BAR, 2.0)
	if _with != "":
		var with := _steps(_with)
		for i in with.size() - 1:
			draw_dashed_line(with[i], with[i + 1], UiTheme.TEXT, 1.5, DASH)
	var now0 := WorksRows.bill_at(_rows, _first)
	draw_string(font, Vector2(x_of(_first) + 40.0, _y(now0) - 4.0), tr("%s signed") % Num.f(now0, 2), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
	if _with != "":
		var with0 := WorksRows.bill_at(_rows, _first, _with)
		draw_string(font, Vector2(x_of(_first) + 40.0, _y(with0) - 4.0), tr("%s with %s") % [Num.f(with0, 2), _with_name], HORIZONTAL_ALIGNMENT_LEFT,
			size.x - 48.0, fs, UiTheme.TEXT)


## The step line of the bill from the axis's first month to its last, a corner at each change.
func _steps(with_id: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var was := -1.0
	for m in range(_first, _last + 1):
		var v := WorksRows.bill_at(_rows, m, with_id)
		if v != was:
			if was >= 0.0:
				out.append(Vector2(x_of(m), _y(was)))
			out.append(Vector2(x_of(m), _y(v)))
			was = v
	out.append(Vector2(x_of(_last), _y(was)))
	return out


func _get_tooltip(at: Vector2) -> String:
	var m := _first + roundi(at.x / maxf(size.x, 1.0) * float(_last - _first))
	var when := DateText.mon_year((m - 1) % 12 + 1, (m - 1) / 12)
	if _with == "":
		return tr("%s: %s %% of GDP a year") % [when, Num.f(WorksRows.bill_at(_rows, m), 2)]
	return tr("%s: %s %% of GDP a year; %s with %s") % [when, Num.f(WorksRows.bill_at(_rows, m), 2), Num.f(WorksRows.bill_at(_rows, m, _with), 2), _with_name]
