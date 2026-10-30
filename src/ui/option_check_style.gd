extends RefCounted

## UiTheme.OPTION_CHECK's look -- V5.2 close R4. An option ON a verb (the
## audience's "as a lie") is not a verb: no plate and no edge, so it never reads as
## a button beside the lever's own (the author at the gate: the Lie box read as a
## stray, "je pense que c'est graphique"). Caption size, dim until hovered; ticked,
## its words turn WARN -- a lie is attention, not failure -- and its box goes
## solid: a shape apart from the hollow one, so the state is never told by colour
## alone. Its own file because ui_theme.gd sits at the size ratchet; the tokens are
## handed in, so this file preloads nothing back.


## `boxes`: ui_theme's button boxes [flat, hovered, focus ring]; `font_px` the
## caption size already scaled; `dim`, `text`, `warn` the theme's tones.
static func apply(theme: Theme, variation: String, boxes: Array, font_px: int, dim: Color, text: Color, warn: Color) -> void:
	theme.set_type_variation(variation, "CheckBox")  # i18n: ok
	for box: StyleBoxFlat in boxes:
		box.content_margin_left = 4
		box.content_margin_right = 4
	for state in ["normal", "pressed", "disabled"]:
		theme.set_stylebox(state, variation, boxes[0])
	for state in ["hover", "hover_pressed"]:
		theme.set_stylebox(state, variation, boxes[1])
	theme.set_stylebox("focus", variation, boxes[2])
	theme.set_font_size("font_size", variation, font_px)
	theme.set_color("font_color", variation, dim)
	theme.set_color("font_hover_color", variation, text)
	theme.set_color("font_focus_color", variation, dim)
	theme.set_color("font_pressed_color", variation, warn)
	theme.set_color("font_hover_pressed_color", variation, warn)
	theme.set_color("font_disabled_color", variation, Color(dim, 0.45))
	var px := font_px - 2
	theme.set_icon("unchecked", variation, _box(px, dim, false))
	theme.set_icon("checked", variation, _box(px, warn, true))
	theme.set_icon("unchecked_disabled", variation, _box(px, Color(dim, 0.45), false))
	theme.set_icon("checked_disabled", variation, _box(px, Color(warn, 0.45), true))
	theme.set_constant("h_separation", variation, 6)
	# The drawn box centres on the line, not on the cap height: measured 2px high.
	theme.set_constant("check_v_offset", variation, 2)


## The box, drawn rather than shipped (no SVG to import on a fresh clone): a
## hollow square, or a solid one when ticked.
static func _box(px: int, colour: Color, solid: bool) -> ImageTexture:
	var image := Image.create(px, px, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var edge := maxi(1, px / 8)
	for y in px:
		for x in px:
			if solid or x < edge or y < edge or x >= px - edge or y >= px - edge:
				image.set_pixel(x, y, colour)
	return ImageTexture.create_from_image(image)
