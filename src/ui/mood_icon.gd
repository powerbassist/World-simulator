extends Control

## V5.1-0c. The president's mood as a small icon beside the approval figure.
##
## The portrait card used to swap the president's FACE with approval, and the
## author asked why the portrait "sometimes changes" -- nothing told them it was a
## mood read. The face is one fixed portrait now; this carries the mood instead,
## and its tooltip says so. Drawn rather than loaded: four expressions are four
## arcs, the colours are the theme's own, and an icon file would be a fifth
## committed asset for a glyph a `_draw` states exactly.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Strings = preload("res://src/ui/strings.gd")

const SIZE := Vector2(22, 22)

## Portrait.Emotion value; -1 until the card first reads approval.
var emotion: int = -1:
	set(value):
		if value == emotion:
			return
		emotion = value
		tooltip_text = _tooltip_for(value)
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = SIZE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


static func _tooltip_for(value: int) -> String:
	var mood := Strings.t("Steady")
	match value:
		Portrait.Emotion.PLEASED: mood = Strings.t("Pleased")
		Portrait.Emotion.WORRIED: mood = Strings.t("Worried")
		Portrait.Emotion.WEARY: mood = Strings.t("Weary")
	return Strings.t("%s -- the president's mood follows approval.") % mood


## How far the mouth bends: positive smiles, negative frowns.
static func _bend_for(value: int) -> float:
	match value:
		Portrait.Emotion.PLEASED: return 1.0
		Portrait.Emotion.WORRIED: return -0.5
		Portrait.Emotion.WEARY: return -1.0
	return 0.0


static func _colour_for(value: int) -> Color:
	match value:
		Portrait.Emotion.PLEASED: return UiTheme.GOOD
		Portrait.Emotion.WORRIED: return UiTheme.WARN
		Portrait.Emotion.WEARY: return UiTheme.BAD
	return UiTheme.TEXT_DIM


func _draw() -> void:
	var colour := _colour_for(emotion)
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.5 - 1.5
	draw_arc(centre, radius, 0.0, TAU, 32, colour, 1.5, true)
	draw_circle(centre + Vector2(-radius * 0.35, -radius * 0.25), 1.3, colour)
	draw_circle(centre + Vector2(radius * 0.35, -radius * 0.25), 1.3, colour)
	var bend := _bend_for(emotion)
	var mouth_y := centre.y + radius * 0.4
	if bend == 0.0:
		draw_line(Vector2(centre.x - radius * 0.4, mouth_y), Vector2(centre.x + radius * 0.4, mouth_y), colour, 1.5, true)
		return
	# A shallow arc across the mouth's width; y grows downward, so a smile's middle
	# sits lower than its ends and a frown's higher. The sign of `bend` picks which,
	# its size the depth.
	var width := radius * 0.8
	var points := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		points.append(Vector2(centre.x - width * 0.5 + width * t, mouth_y + sin(t * PI) * radius * 0.35 * bend))
	draw_polyline(points, colour, 1.5, true)
