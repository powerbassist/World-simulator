extends RefCounted

## The shared BUREAU controls the register's order form needed and no panel had (the bureau
## audit, sections 3 and 7; the parent's ruling for #420). Its own file beside
## option_check_style.gd so ui_theme.gd keeps one line per piece; the tokens are handed in,
## so this file preloads nothing back.
##   Primary  the one action a screen exists for: the button's plate, outlined in the accent
##            (identity, "you are here"), never a filled slab (the gate's oversized buttons);
##   Small    a verb at the caption size with a tight plate, beside a line it acts on;
##   Segment  one choice among a few, side by side; the picked one outlined in the accent;
##   Chip     a bordered caption-size plate, a glyph beside its words: Chip is neutral, the
##            three status tones are the theme's fixed GOOD / WARN / BAD on the border only,
##            so the words stay in the text tone and the glyph carries the state.


## `box` is ui_theme's _button_box (bg, border) -> StyleBoxFlat; `t` the tokens
## {slate, hull, edge, text, dim, good, warn, bad, accent}; `small_px` the caption size scaled.
static func apply(theme: Theme, names: Dictionary, box: Callable, t: Dictionary, small_px: int) -> void:
	var primary := String(names["primary"])
	theme.set_type_variation(primary, "Button")  # i18n: ok
	theme.set_stylebox("normal", primary, box.call(t["slate"], t["accent"]))
	theme.set_stylebox("hover", primary, box.call((t["slate"] as Color).lightened(0.10), t["accent"]))
	theme.set_stylebox("pressed", primary, box.call((t["slate"] as Color).lightened(0.16), t["accent"]))
	theme.set_stylebox("focus", primary, _ringed(box.call(Color(0, 0, 0, 0), t["accent"])))
	# No border when disabled: the EDGE border is what reads "pressable" (ui_theme._buttons).
	theme.set_stylebox("disabled", primary, box.call(t["hull"]))

	var small := String(names["small"])
	theme.set_type_variation(small, "Button")  # i18n: ok
	var states := {"normal": [t["slate"], t["edge"]], "hover": [(t["slate"] as Color).lightened(0.10), t["accent"]],
		"pressed": [(t["slate"] as Color).lightened(0.16), t["accent"]], "focus": [Color(0, 0, 0, 0), t["accent"]],
		"disabled": [t["hull"], Color(0, 0, 0, 0)]}
	for state in states:
		theme.set_stylebox(state, small, _tight(box.call(states[state][0], states[state][1])))
	theme.set_font_size("font_size", small, small_px)

	# A segment reads as a choice, not a verb: flat until picked, its pick outlined.
	var segment := String(names["segment"])
	theme.set_type_variation(segment, "Button")  # i18n: ok
	theme.set_stylebox("normal", segment, box.call(t["hull"], t["edge"]))
	theme.set_stylebox("hover", segment, box.call(t["slate"], t["edge"]))
	theme.set_stylebox("pressed", segment, box.call(t["slate"], t["accent"]))
	theme.set_stylebox("hover_pressed", segment, box.call(t["slate"], t["accent"]))
	theme.set_stylebox("focus", segment, box.call(Color(0, 0, 0, 0), t["accent"]))
	theme.set_color("font_color", segment, t["dim"])
	theme.set_color("font_pressed_color", segment, t["text"])
	theme.set_color("font_hover_pressed_color", segment, t["text"])

	for pair in [[names["chip"], t["edge"]], [names["chip_good"], t["good"]], [names["chip_warn"], t["warn"]], [names["chip_bad"], t["bad"]]]:
		theme.set_type_variation(String(pair[0]), "PanelContainer")  # i18n: ok
		var plate: StyleBoxFlat = box.call(Color(0, 0, 0, 0), pair[1])
		plate.content_margin_left = 7
		plate.content_margin_right = 7
		plate.content_margin_top = 1
		plate.content_margin_bottom = 1
		plate.set_corner_radius_all(3)
		theme.set_stylebox("panel", String(pair[0]), plate)


static func _tight(b: StyleBoxFlat) -> StyleBoxFlat:
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 2
	b.content_margin_bottom = 2
	return b


## Primary's focus ring is two pixels, so the screen's one action shows where the keyboard is.
static func _ringed(b: StyleBoxFlat) -> StyleBoxFlat:
	b.set_border_width_all(2)
	return b
