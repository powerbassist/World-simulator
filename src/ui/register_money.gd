extends Control

## The register sheet's two money charts (V5.3 c' slice 1), one Control in one of two modes:
##   range  the price range as one grey bar, the estimate a tick on it, both ends and the
##          estimate printed (section 4: the contract price is drawn inside it at the vote);
##   cash   one bar a year from now, on one axis in bn: the capital while it builds (grey),
##          the running cost once it opens (the accent: the player's own programme), the
##          legend under it. The running cost never stops, so the years shown run past
##          the opening on purpose.
## The caller passes the sim's quote; the bars are its numbers spread over the calendar.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")

const BUILD := Color(0.290, 0.325, 0.353)  ## #4A535A: capital, a neutral the accent stands out from
const BAR_H := 10.0
const CASH_H := 72.0
const YEARS_AFTER := 3

var _mode := ""
var _lo := 0.0
var _mid := 0.0
var _hi := 0.0
## cash: [[year, capital_bn, running_bn]], and the legend's two words.
var _years: Array = []
var _legend: Array = []


func range_of(lo_bn: float, estimate_bn: float, hi_bn: float) -> void:
	_mode = "range"
	_lo = lo_bn
	_mid = estimate_bn
	_hi = hi_bn
	custom_minimum_size = Vector2(240.0, BAR_H + _fs() * 1.6 + 6.0)
	queue_redraw()


## `start_month` is months since year 0 (UnitPrice.now), the bill billed from the month after.
func cash_of(start_month: int, build_months: int, estimate_bn: float, running_bn_year: float, legend: Array) -> void:
	_mode = "cash"
	_legend = legend
	_years = []
	# UnitPrice.now() is year x 12 + a 1-BASED month; the loop below counts 0-based months.
	var s0 := start_month - 1
	var first := s0 / 12
	var open_at := s0 + build_months
	var last := open_at / 12 + YEARS_AFTER
	for year in range(first, last + 1):
		var capital := 0.0
		var running := 0.0
		for m in 12:
			var month := year * 12 + m
			if month > s0 and month <= open_at:
				capital += estimate_bn / float(build_months)
			elif month > open_at:
				running += running_bn_year / 12.0
		_years.append([year, capital, running])
	custom_minimum_size = Vector2(240.0, CASH_H + _fs() * 3.2)
	queue_redraw()


func years() -> Array:
	return _years


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


func _draw() -> void:
	if _mode == "range":
		_draw_range()
	elif _mode == "cash":
		_draw_cash()


func _draw_range() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	var pad := (_hi - _lo) * 0.15 + 1e-6
	var x := func(v: float) -> float: return (v - (_lo - pad)) / ((_hi + pad) - (_lo - pad)) * size.x
	draw_rect(Rect2(x.call(_lo), 3.0, x.call(_hi) - x.call(_lo), BAR_H), BUILD)
	draw_rect(Rect2(x.call(_mid) - 1.0, 0.0, 2.0, BAR_H + 6.0), UiTheme.TEXT)
	var y := BAR_H + 6.0 + fs
	draw_string(font, Vector2(x.call(_lo) - 30.0, y), Num.f(_lo, 2), HORIZONTAL_ALIGNMENT_CENTER, 60.0, fs, UiTheme.TEXT_DIM)
	draw_string(font, Vector2(x.call(_mid) - 30.0, y), Num.f(_mid, 2), HORIZONTAL_ALIGNMENT_CENTER, 60.0, fs, UiTheme.TEXT)
	draw_string(font, Vector2(x.call(_hi) - 30.0, y), Num.f(_hi, 2), HORIZONTAL_ALIGNMENT_CENTER, 60.0, fs, UiTheme.TEXT_DIM)


func _draw_cash() -> void:
	if _years.is_empty():
		return
	var font := get_theme_default_font()
	var fs := _fs()
	var top := 1e-9
	for y in _years:
		top = maxf(top, float(y[1]) + float(y[2]))
	var n := _years.size()
	var slot := size.x / float(n)
	var w := slot - 3.0
	var accent := UiTheme.accent()
	for i in n:
		var capital := float(_years[i][1])
		var running := float(_years[i][2])
		var x0 := slot * i
		var hc := capital / top * CASH_H
		var hr := running / top * CASH_H
		if hr > 0.0:
			draw_rect(Rect2(x0, CASH_H - hr, w, hr), accent)
		if hc > 0.0:
			draw_rect(Rect2(x0, CASH_H - hr - hc - (2.0 if hr > 0.0 else 0.0), w, hc), BUILD)
		# Two digits of the year: the bars are narrow, the century never changes here.
		draw_string(font, Vector2(x0, CASH_H + fs + 2.0), "%02d" % (int(_years[i][0]) % 100), HORIZONTAL_ALIGNMENT_CENTER, w, fs, UiTheme.TEXT_DIM)
	var ly := CASH_H + fs * 2.6 + 2.0
	var lx := 0.0
	for k in _legend.size():
		draw_rect(Rect2(lx, ly - fs * 0.75, 10.0, 10.0), BUILD if k == 0 else accent)
		draw_string(font, Vector2(lx + 15.0, ly), String(_legend[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT)  # i18n: row-ok the caller passes shown text
		lx += 15.0 + font.get_string_size(String(_legend[k]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16.0  # i18n: row-ok the caller passes shown text


func _get_tooltip(at: Vector2) -> String:
	if _mode != "cash" or _years.is_empty():
		return ""
	var i := clampi(int(at.x / (size.x / float(_years.size()))), 0, _years.size() - 1)
	return "%d  %s + %s" % [int(_years[i][0]), Num.f(float(_years[i][1]), 2), Num.f(float(_years[i][2]), 2)]  # i18n: row-ok chart data
