extends Control

## A programme's units as squares (picture C's overrun answers): one square a unit voted, filled
## while it is kept, an outline once an answer cuts it. The count is said in words beside it, so
## the squares are never the only reading. They wrap to the width they are given (pass 2 T3 on #448: a
## 40-unit programme laid on one line pushed three answers past the workspace).

const UiTheme = preload("res://src/ui/ui_theme.gd")

const SIDE := 10.0
const GAP := 4.0
## A line is never narrower than this many squares, so a narrow tile still reads as a row.
const MIN_PER_LINE := 10

var kept := 0
var voted := 0


func setup(kept_units: int, voted_units: int) -> void:
	kept = kept_units
	voted = voted_units
	custom_minimum_size.x = mini(voted, MIN_PER_LINE) * (SIDE + GAP)
	_fit()


## Squares a line at the width laid out.
func per_line() -> int:
	return maxi(1, floori((maxf(size.x, custom_minimum_size.x) + GAP) / (SIDE + GAP)))


func lines() -> int:
	return ceili(float(voted) / float(per_line())) if voted > 0 else 1


func _fit() -> void:
	custom_minimum_size.y = lines() * (SIDE + GAP) - GAP + 2.0
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()


func _draw() -> void:
	for i in voted:
		var r := Rect2((i % per_line()) * (SIDE + GAP), 1.0 + (i / per_line()) * (SIDE + GAP), SIDE, SIDE)
		if i < kept:
			draw_rect(r, UiTheme.TEXT)
		else:
			draw_rect(r, UiTheme.TEXT_DIM, false, 1.0)
