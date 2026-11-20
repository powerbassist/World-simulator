extends Control

## A programme's units as squares (picture C's overrun answers): one square a unit voted, filled
## while it is kept, an outline once an answer cuts it. The count is said in words beside it, so
## the squares are never the only reading.

const UiTheme = preload("res://src/ui/ui_theme.gd")

const SIDE := 10.0
const GAP := 4.0

var kept := 0
var voted := 0


func setup(kept_units: int, voted_units: int) -> void:
	kept = kept_units
	voted = voted_units
	custom_minimum_size = Vector2(voted * (SIDE + GAP), SIDE + 2.0)
	queue_redraw()


func _draw() -> void:
	for i in voted:
		var r := Rect2(i * (SIDE + GAP), 1.0, SIDE, SIDE)
		if i < kept:
			draw_rect(r, UiTheme.TEXT)
		else:
			draw_rect(r, UiTheme.TEXT_DIM, false, 1.0)
