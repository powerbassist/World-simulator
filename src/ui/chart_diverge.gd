extends Control

## One bar around a zero line (chart_kit.gd's `diverging()`): a signed value per row, drawn right
## of the line when it is above zero and left when below, the length proportional to the row's
## share of the chart's span. The Bills sheet draws what a law does to each bloc with it; the
## same piece is meant for Diplomacy's relations and a sector's moves.
##
## The two directions take the vote's own tones, GOOD above zero and BAD below (G3 S5, Design's
## T5: a chart never wears the accent's hue, and the blue it had was the hue France skips, beside
## the filled press). Colour is never the only signal: the caller prints the signed value beside
## every bar, and a zero draws no bar at all, only the line.

const UiTheme = preload("res://src/ui/ui_theme.gd")

const BAR := 10.0

var value := 0.0
## The largest magnitude the chart draws at full half-width, shared by every row of one chart.
var span := 1.0


func setup(v: float, chart_span: float) -> void:
	value = v
	span = maxf(chart_span, 1e-9)
	custom_minimum_size = Vector2(0.0, BAR + 6.0)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	queue_redraw()


## The bar's rectangle across `width`: from the middle, toward the sign, never past the edge.
static func bar_rect(v: float, chart_span: float, width: float) -> Rect2:
	var mid := width * 0.5
	var length := mid * clampf(absf(v) / maxf(chart_span, 1e-9), 0.0, 1.0)
	return Rect2(mid if v >= 0.0 else mid - length, 3.0, length, BAR)


## The bar's colour: the vote's own tones (a test reads it).
static func colour_of(v: float) -> Color:
	return UiTheme.GOOD if v > 0.0 else UiTheme.BAD


func _draw() -> void:
	var r := bar_rect(value, span, size.x)
	if r.size.x > 0.0:
		draw_rect(r, colour_of(value))
	draw_line(Vector2(size.x * 0.5, 0.0), Vector2(size.x * 0.5, size.y), UiTheme.EDGE, 1.0)
