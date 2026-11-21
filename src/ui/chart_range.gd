extends Control

## A range with its estimate -- ChartKit.range_bar (V5.3 c', the bureau audit's item 5): one
## neutral bar from the low end to the high end, the estimate a TEXT-tone tick across it,
## the three values printed under their marks. The register's price (section 4: the contract
## price is drawn inside the range at the vote) first; any figure known as a range later.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")

const BAR := UiTheme.NEUTRAL_BAR
const BAR_H := 10.0
const LABEL_W := 60.0

var _lo := 0.0
var _mid := 0.0
var _hi := 0.0
var _places := 2
## opts "track": [min, max] draws the range on that fixed axis, the track a hairline under it
## (a chance on 0 to 100, Design's T8 on #441); empty, the axis is the range's own.
var _track: Array = []


func setup(lo: float, estimate: float, hi: float, opts := {}) -> void:
	_lo = lo
	_mid = estimate
	_hi = hi
	_places = int(opts.get("places", 2))
	_track = opts.get("track", [])
	custom_minimum_size = Vector2(240.0, BAR_H + 6.0 + _fs() * 1.6)
	queue_redraw()


func _fs() -> int:
	return roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())


## The axis runs 15 % of the range past each end, so both printed ends fit under their marks;
## a fixed track runs from its min to its max, inset by half a label.
func _x(v: float) -> float:
	if _track.size() == 2:
		var inset := LABEL_W * 0.5
		return inset + (v - float(_track[0])) / maxf(float(_track[1]) - float(_track[0]), 1e-9) * maxf(size.x - 2.0 * inset, 1.0)
	var pad := (_hi - _lo) * 0.15 + 1e-9
	return (v - (_lo - pad)) / ((_hi + pad) - (_lo - pad)) * size.x


func bar_rect() -> Rect2:
	return Rect2(_x(_lo), 3.0, _x(_hi) - _x(_lo), BAR_H)


func tick_x() -> float:
	return _x(_mid)


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := _fs()
	if _track.size() == 2:
		draw_line(Vector2(_x(float(_track[0])), 3.0 + BAR_H * 0.5), Vector2(_x(float(_track[1])), 3.0 + BAR_H * 0.5), UiTheme.EDGE, 1.0)
	draw_rect(bar_rect(), BAR)
	draw_rect(Rect2(tick_x() - 1.0, 0.0, 2.0, BAR_H + 6.0), UiTheme.TEXT)
	var y := BAR_H + 6.0 + fs
	for pair in [[_lo, UiTheme.TEXT_DIM], [_mid, UiTheme.TEXT], [_hi, UiTheme.TEXT_DIM]]:
		draw_string(font, Vector2(_x(float(pair[0])) - LABEL_W * 0.5, y), Num.f(float(pair[0]), _places),
			HORIZONTAL_ALIGNMENT_CENTER, LABEL_W, fs, pair[1])


func _get_tooltip(_at: Vector2) -> String:
	return "%s – %s – %s" % [Num.f(_lo, _places), Num.f(_mid, _places), Num.f(_hi, _places)]  # i18n: row-ok chart data
