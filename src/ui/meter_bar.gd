extends Control

## A meter against its threshold (V5.3, gate 3: the author's pick of top bar A): a thin
## track, a fill to `value` of `top`, and a tick across it at `mark` -- the majority line,
## the level where unions organise. The dataviz method's meter: the fill in the text
## colour (it is a quantity, not a status), the tick in the text colour, the track in
## SLATE. The figure and its words sit beside it, so the meter is never the only reading.

const UiTheme = preload("res://src/ui/ui_theme.gd")

## Width at text 100 %; the height is the track's and the tick's.
const SIZE := Vector2(80.0, 10.0)
const TRACK := 4.0

var value := 0.0
var top := 1.0
var mark := 0.0
## The court's meter: a fill past the tick is bad news, so the fill takes BAD there (law_path.gd).
var bad_past_mark := false


func setup(v: float, t: float, m: float) -> void:
	value = v
	top = maxf(t, 1e-9)
	mark = m
	custom_minimum_size = Vector2(SIZE.x * UiTheme.text_scale(), SIZE.y)
	queue_redraw()


func _draw() -> void:
	var y := (size.y - TRACK) / 2.0
	draw_rect(Rect2(0.0, y, size.x, TRACK), UiTheme.SLATE)
	var fill := clampf(value / top, 0.0, 1.0) * size.x
	if fill > 0.0:
		draw_rect(Rect2(0.0, y, maxf(fill, 2.0), TRACK), UiTheme.BAD if bad_past_mark and value > mark else UiTheme.TEXT)
	var x := clampf(mark / top, 0.0, 1.0) * size.x
	draw_line(Vector2(x, 0.0), Vector2(x, size.y), UiTheme.TEXT, 1.5)
