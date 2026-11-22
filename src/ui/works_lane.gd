extends Control

## Public works' lanes (G3 S4 PR 2c, works-a-calendar.png): one axis of years shared by the
## head row, every work's lane and the works' bill (works_bill.gd draws on the same x_at). A
## work being built is a solid bar from today to its opening; an offer is a dashed bar "if
## started now" (the accent when it is the picked one, as a bookable place on the Diary); a dot
## marks the opening, then a wedge says its growth arrives over about five years -- a sign, not
## the trend's curve (the sim adds the payoff to a target the economy converges on). Today is
## the accent's hairline; the end of the term a dashed line across every lane. A mark line never
## strikes text (Design's T1 and T2 on #450): the term's label sits beside its line, and in a
## lane the lines start under the lane's words.
##
## Rows are works_rows.gd's. Months are absolute (year x 12 + month).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const DateText = preload("res://src/ui/date_text.gd")
const WorksRows = preload("res://src/ui/works_rows.gd")

## "About five years" (the panel's own sentence, economy_constants.SHIFT_ADJUST's lag): the wedge's length.
const ARRIVES_MONTHS := 60
const DASH := 4.0

var _row := {}
var _first := 0
var _last := 1
var _now := 0
var _term := -1
var _picked := false
var _legend := false


## The head row: the years, today and the term's end under them.
func axis(first: int, last: int, now: int, term: int) -> void:
	_place(first, last, now, term)
	custom_minimum_size.y = _fs() * 3.0


## The legend under the lanes: what a solid bar, a dashed bar and a wedge mean.
func legend() -> void:
	_legend = true
	custom_minimum_size.y = _fs() * 1.6
	queue_redraw()


## One work's lane.
func lane(row: Dictionary, first: int, last: int, now: int, term: int, picked: bool) -> void:
	_row = row
	_picked = picked
	_place(first, last, now, term)
	custom_minimum_size.y = _fs() * 3.4
	tooltip_text = _said()


func _place(first: int, last: int, now: int, term: int) -> void:
	_first = first
	_last = maxi(last, first + 12)
	_now = now
	_term = term
	queue_redraw()


func term_month() -> int:
	return _term


func _term_words() -> String:
	return tr("your term ends · %s") % DateText.month_long_year((_term - 1) % 12 + 1, (_term - 1) / 12)


## The axis row's "your term ends" label: ending 6 px left of its line when there is room after
## "today", else starting 6 px right of it. Empty off the axis row or with no term ahead.
func term_label_rect() -> Rect2:
	if _term <= 0 or not _row.is_empty() or _legend:
		return Rect2()
	var font := get_theme_default_font()
	var fs := _fs()
	var w := font.get_string_size(_term_words(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var xt := x_of(_term)
	var x := xt - 6.0 - w
	if x < _today_end(font, fs):
		x = xt + 6.0 if xt + 6.0 + w <= size.x else x
	return Rect2(x, fs * 2.4 - font.get_ascent(fs), w, font.get_height(fs))


## Where the term's and the years' lines start: under the term's label on the axis row, under
## the lane's words in a lane.
func line_top() -> float:
	var font := get_theme_default_font()
	var fs := _fs()
	if _row.is_empty():
		var label := term_label_rect()
		return label.end.y if label.size.x > 0.0 else fs * 1.4
	return fs * 1.1 + font.get_descent(fs) + 2.0


func _today_end(font: Font, fs: int) -> float:
	return x_of(_now) + 2.0 + font.get_string_size(tr("today"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 8.0


## The x of an absolute month on an axis `width` wide that runs from `first` to `last`.
static func x_at(month: int, first: int, last: int, width: float) -> float:
	return clampf(float(month - first) / float(maxi(last - first, 1)), 0.0, 1.0) * width


func x_of(month: int) -> float:
	return x_at(month, _first, _last, size.x)


## For the tests: lanes and the bill share one axis on screen.
func global_x(month: int) -> float:
	return global_position.x + x_of(month)


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


## What the lane says over its bar (and its tooltip).
func _said() -> String:
	var opens := int(_row.get("opens", -1))
	match String(_row.get("state", "")):
		WorksRows.BUILDING:
			return tr("opens %s · then about five years to arrive") % _mon(opens)
		WorksRows.OFFER:
			# Only the picked lane says it: the lead says it for that work, and five lanes saying
			# it was the page's longest repeat (Design's T2 on #450).
			if _picked and _term > 0 and opens > _term:
				return tr_n("if started now: opens %s · %d month after your term ends", "if started now: opens %s · %d months after your term ends",
					opens - _term) % [_mon(opens), opens - _term]
			return tr("if started now: opens %s") % _mon(opens)
		_:
			return tr("open · its growth is still arriving")


func _mon(month: int) -> String:
	return DateText.mon_year((month - 1) % 12 + 1, (month - 1) / 12)


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	if _legend:
		_draw_legend(font, fs)
		return
	var top := line_top()
	# The years: a hairline at each January (and its number on the head row).
	for year in range((_first - 1) / 12, (_last - 1) / 12 + 1):
		var x := x_of(year * 12 + 1)
		if x <= 0.0 and year * 12 + 1 < _first:
			continue
		draw_line(Vector2(x, fs * 1.4 if _row.is_empty() else top), Vector2(x, size.y), UiTheme.EDGE, 1.0)
		if _row.is_empty():
			draw_string(font, Vector2(x - fs, fs), str(year), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)  # i18n: row-ok chart data
	var xn := x_of(_now)
	if _term > 0:
		var xt := x_of(_term)
		draw_dashed_line(Vector2(xt, top), Vector2(xt, size.y), UiTheme.TEXT_DIM, 1.0, DASH)
		if _row.is_empty():
			draw_string(font, Vector2(term_label_rect().position.x, fs * 2.4), _term_words(), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)
	if _row.is_empty():
		draw_string(font, Vector2(xn + 2.0, fs * 2.4), tr("today"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.accent())
	else:
		_lane(font, fs, xn)
	draw_line(Vector2(xn, fs * 1.4 if _row.is_empty() else 0.0), Vector2(xn, size.y), UiTheme.accent(), 2.0)


func _lane(font: Font, fs: int, xn: float) -> void:
	var kind := String(_row["state"])
	var mid := fs * 2.4
	var h := fs * 0.6
	if kind == WorksRows.DONE:
		draw_string(font, Vector2(xn + 8.0, fs * 1.1), _said(), HORIZONTAL_ALIGNMENT_LEFT, size.x - xn - 8.0, fs, UiTheme.TEXT_DIM)
		return
	var xo := x_of(int(_row["opens"]))
	draw_string(font, Vector2(xn + 8.0, fs * 1.1), _said(), HORIZONTAL_ALIGNMENT_LEFT, size.x - xn - 8.0, fs, UiTheme.TEXT)
	# Its growth arriving after the opening: a wedge from nothing to the bar's height.
	var xe := x_of(int(_row["opens"]) + ARRIVES_MONTHS)
	draw_colored_polygon(PackedVector2Array([Vector2(xo, mid + h * 0.5), Vector2(xe, mid - h * 0.5), Vector2(xe, mid + h * 0.5)]),
		Color(UiTheme.NEUTRAL_BAR, 0.6))
	var bar := Rect2(xn, mid - h * 0.5, maxf(xo - xn, 2.0), h)
	if kind == WorksRows.BUILDING:
		draw_rect(bar, UiTheme.NEUTRAL_BAR)
	else:
		var tone := UiTheme.accent() if _picked else UiTheme.TEXT_DIM
		for edge in [[bar.position, Vector2(bar.end.x, bar.position.y)], [Vector2(bar.position.x, bar.end.y), bar.end]]:
			draw_dashed_line(edge[0], edge[1], tone, 1.5, DASH)
	draw_circle(Vector2(xo, mid), fs * 0.3, UiTheme.TEXT)


## Three keys in a row, each a mark as the lanes draw it, then its words.
func _draw_legend(font: Font, fs: int) -> void:
	var x := 0.0
	var mid := fs * 0.8
	var h := fs * 0.6
	for key in [[WorksRows.BUILDING, tr("being built")], [WorksRows.OFFER, tr("on offer, if started now")], ["", tr("its growth arriving")]]:
		var mark := Rect2(x, mid - h * 0.5, fs * 1.6, h)
		match String(key[0]):
			WorksRows.BUILDING:
				draw_rect(mark, UiTheme.NEUTRAL_BAR)
			WorksRows.OFFER:
				for edge in [[mark.position, Vector2(mark.end.x, mark.position.y)], [Vector2(mark.position.x, mark.end.y), mark.end]]:
					draw_dashed_line(edge[0], edge[1], UiTheme.TEXT_DIM, 1.5, DASH)
			_:
				draw_colored_polygon(PackedVector2Array([Vector2(mark.position.x, mark.end.y), Vector2(mark.end.x, mark.position.y), mark.end]),
					Color(UiTheme.NEUTRAL_BAR, 0.6))
		x = mark.end.x + 6.0
		draw_string(font, Vector2(x, mid + fs * 0.35), String(key[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_DIM)
		x += font.get_string_size(String(key[1]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0
