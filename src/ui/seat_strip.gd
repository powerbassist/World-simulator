extends Control

## A margin as a length (G3 S5, Majority: B's two margins carried into A). The assembly's seats
## on one straight bar, the parties in the chamber's order and hues; the side the margin is about
## stays lit and the other side dims. A line marks the seats a vote needs and a dashed box the
## seats in question (the members who may break ranks, or the seats censure lacks). The figures
## are the tile's words around it: the strip carries no text, like every chart in the kit.

const UiTheme = preload("res://src/ui/ui_theme.gd")

const HEIGHT := 12.0
## The box stands this far over and under the bar, so it reads as a frame and not a segment.
const BOX_OUT := 4.0
## The dimmed side keeps its hue at this alpha: the parties are still told apart.
const DIM := 0.3
## Room over the strip for the number on its tick, px at text 100 %.
const LABEL_ROOM := 14.0

var _parts: Array = []  # [{value: int, color: Color, lit: bool}]
var _total := 1
var _line := 0
var _box := Vector2i.ZERO
## The seats the line marks, written over it ("289").
var line_label := "":
	set(value):
		line_label = value
		queue_redraw()


func setup(parts: Array, total: int, line_at: int, box_from: int, box_to: int) -> void:
	_parts = parts
	_total = maxi(total, 1)
	_line = line_at
	_box = Vector2i(mini(box_from, box_to), maxi(box_from, box_to))
	custom_minimum_size = Vector2(0.0, (HEIGHT + 2.0 * BOX_OUT + LABEL_ROOM) * UiTheme.text_scale())
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func line_at() -> int:
	return _line


func box() -> Vector2i:
	return _box


func _x(seats: float) -> float:
	return size.x * clampf(seats / float(_total), 0.0, 1.0)


func _draw() -> void:
	var out := BOX_OUT * UiTheme.text_scale()
	var top := LABEL_ROOM * UiTheme.text_scale()
	var bar := Rect2(0.0, top + out, size.x, size.y - top - 2.0 * out)
	var at := 0
	for part in _parts:
		var n := int(part["value"])
		if n <= 0:
			continue
		var color: Color = part["color"]
		if not bool(part.get("lit", true)):
			color.a = DIM
		# A 2 px surface gap between neighbours (dataviz's spacer), never on the bar's outer ends.
		var left := _x(at) + (1.0 if at > 0 else 0.0)
		var right := _x(at + n) - (1.0 if at + n < _total else 0.0)
		draw_rect(Rect2(left, bar.position.y, maxf(right - left, 1.0), bar.size.y), color)
		at += n
	if _box.y > _box.x:
		var r := Rect2(_x(_box.x), top, maxf(_x(_box.y) - _x(_box.x), 2.0), size.y - top)
		for edge in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.position.x, r.end.y), r.end],
				[r.position, Vector2(r.position.x, r.end.y)], [Vector2(r.end.x, r.position.y), r.end]]:
			draw_dashed_line(edge[0], edge[1], UiTheme.TEXT, 1.0, 3.0)
	var x := _x(_line)
	draw_line(Vector2(x, top), Vector2(x, size.y), UiTheme.TEXT, 2.0)
	if line_label != "":
		var font := get_theme_font("font", "Label")  # i18n: ok a theme type
		var px := roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())
		var width := font.get_string_size(line_label, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
		draw_string(font, Vector2(clampf(x - width / 2.0, 0.0, maxf(size.x - width, 0.0)), top - 3.0), line_label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, px, UiTheme.TEXT)
