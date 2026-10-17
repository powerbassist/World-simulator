extends Control

## A nation's flag, drawn from `data/nations/*.json`'s `flag` block -- U5a.
##
## Vector rather than an image, for the reason the panels are built in code: ten
## sprite files would be ten binaries to license, resize and keep in step with a
## roster that grows every V1.2-class session, and a flag at this size is four
## rectangles. `assets/` stays fonts-only.
##
## The layout is dispatched on the data's own string, never on the nation id --
## docs/engine-decision.md Rule 1, the same shape formation_method and the six
## fields after it already use. An eleventh nation with a flag this file cannot
## draw adds a layout here and a string there; it never adds a branch on `id`.
##
## Charges are deliberately not modelled -- no Spanish arms, no Swiss proportions
## and a simplified Union Flag. At the size this is drawn (roughly 28x18) a
## charge is three grey pixels, and the thing the player is reading is "which
## country", which the colours already answer.

var _bands: Array[Color] = []
var _layout := ""


func setup(bands: Array[Color], layout: String) -> void:
	_bands = bands
	_layout = layout
	queue_redraw()


func _draw() -> void:
	if _bands.is_empty():
		return

	match _layout:
		"vertical":
			_draw_bands(true)
		"horizontal":
			_draw_bands(false)
		"cross":
			_draw_cross()
		"union":
			_draw_union()
		_:
			# An unknown layout still shows the nation's colours rather than
			# nothing -- the load-time check in nation.gd is what actually
			# rejects a bad string, so reaching here means the data changed
			# under a running game.
			_draw_bands(false)

	# One dark hairline, so a flag whose outer band is white does not bleed into
	# the plate it sits on.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.55), false, 1.0)


func _draw_bands(vertical: bool) -> void:
	var count := _bands.size()
	for i in range(count):
		# Computed from the edges rather than as i * band_width, so rounding
		# cannot leave a one-pixel gap of background between two bands.
		var from := floorf(size.x * i / count) if vertical else floorf(size.y * i / count)
		var to := floorf(size.x * (i + 1) / count) if vertical else floorf(size.y * (i + 1) / count)
		var rect := Rect2(Vector2(from, 0), Vector2(to - from, size.y)) if vertical \
			else Rect2(Vector2(0, from), Vector2(size.x, to - from))
		draw_rect(rect, _bands[i])


## Field first, cross second -- the band order the data declares. A THIRD band
## (V4.11: Norway, Iceland) makes the second a fimbriation: drawn as a wider
## cross under the third, the way those two flags edge their cross in white.
func _draw_cross() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _bands[0])
	if _bands.size() < 2:
		return
	var arm := minf(size.x, size.y) * 0.2
	if _bands.size() >= 3:
		_draw_cross_arms(arm * 1.6, _bands[1])
		_draw_cross_arms(arm * 0.8, _bands[2])
	else:
		_draw_cross_arms(arm, _bands[1])


func _draw_cross_arms(arm: float, colour: Color) -> void:
	draw_rect(Rect2(Vector2((size.x - arm) / 2.0, size.y * 0.2), Vector2(arm, size.y * 0.6)), colour)
	draw_rect(Rect2(Vector2(size.x * 0.2, (size.y - arm) / 2.0), Vector2(size.x * 0.6, arm)), colour)


## Field, then the saltire and cross colours in band order. Simplified: the
## white fimbriation is drawn as a wider line under each coloured one rather
## than as the offset counterchange the real flag has.
func _draw_union() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), _bands[0])
	if _bands.size() < 3:
		return
	var white: Color = _bands[1]
	var red: Color = _bands[2]

	var tl := Vector2.ZERO
	var tr := Vector2(size.x, 0)
	var bl := Vector2(0, size.y)
	var br := size

	draw_line(tl, br, white, size.y * 0.28)
	draw_line(tr, bl, white, size.y * 0.28)
	draw_line(tl, br, red, size.y * 0.12)
	draw_line(tr, bl, red, size.y * 0.12)

	var mid_y := size.y / 2.0
	var mid_x := size.x / 2.0
	draw_line(Vector2(0, mid_y), Vector2(size.x, mid_y), white, size.y * 0.36)
	draw_line(Vector2(mid_x, 0), Vector2(mid_x, size.y), white, size.y * 0.36)
	draw_line(Vector2(0, mid_y), Vector2(size.x, mid_y), red, size.y * 0.20)
	draw_line(Vector2(mid_x, 0), Vector2(mid_x, size.y), red, size.y * 0.20)
