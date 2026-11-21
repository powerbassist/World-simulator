extends RefCounted

## The shared controls beyond a plain Button (the bureau audit, sections 3 and 7; restyled for
## G3, "Sheets on glass", 2026-11-21). Its own file beside option_check_style.gd so ui_theme.gd
## keeps one line per piece; the tokens are handed in, so this file preloads nothing back.
##   Primary  the one action a screen exists for, and the armed verb: the accent FILL with
##            its label (white, or dark where white fails), a soft glow of the fill under it.
##            No other button is filled;
##   Small    a verb at the caption size with a tight plate, beside a line it acts on;
##   Ghost    a quiet action ("Back to the map", "Menu"): no fill until hovered, a dim label.
##            Two looks for a click, a button and a ghost, never bare text;
##   Segment  one choice among a few, side by side on a tile ground (PanelKit.segmented):
##            the open one is a raised control, the others a dim label;
##   Chip     a pill: neutral on a control's surface, or a status tone as its GROUND at 17 %,
##            the words in the text tone and the glyph in the tone, so a state is never colour
##            alone.


## `box` is ui_theme's _button_box (bg, border) -> StyleBoxFlat; `t` the tokens
## {control, hover, pressed, line, text, dim, off, good, warn, bad, fill, on_fill, ring};
## `small_px` the caption size scaled; `medium` the 500 cut (null when the font did not load).
static func apply(theme: Theme, names: Dictionary, box: Callable, t: Dictionary, small_px: int, medium: Font) -> void:
	var fill := t["fill"] as Color
	var primary := String(names["primary"])
	theme.set_type_variation(primary, "Button")  # i18n: ok
	theme.set_stylebox("normal", primary, _glow(box.call(fill)))
	# Darker under the pointer and darker again when held: a white label's contrast rises,
	# never falls (a dark label on a yellow fill starts near 10:1 and keeps AA).
	theme.set_stylebox("hover", primary, _glow(box.call(fill.darkened(0.06))))
	theme.set_stylebox("pressed", primary, _glow(box.call(fill.darkened(0.12))))
	# Held ON under the pointer (the armed "See them" is a Primary toggle): the fill still, never
	# the base Button's graphite (#439 pass 2 T2).
	theme.set_stylebox("hover_pressed", primary, _glow(box.call(fill.darkened(0.12))))
	theme.set_stylebox("focus", primary, t["ring"])
	theme.set_stylebox("disabled", primary, box.call(Color(0, 0, 0, 0), t["line"]))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, primary, t["on_fill"])

	var small := String(names["small"])
	theme.set_type_variation(small, "Button")  # i18n: ok
	var states := {"normal": [t["control"], Color(0, 0, 0, 0)], "hover": [t["hover"], Color(0, 0, 0, 0)],
		"pressed": [t["pressed"], Color(0, 0, 0, 0)], "hover_pressed": [t["pressed"], Color(0, 0, 0, 0)],
		"disabled": [Color(0, 0, 0, 0), t["line"]]}
	for state in states:
		theme.set_stylebox(state, small, _tight(box.call(states[state][0], states[state][1])))
	# Held down, as a Button: CONTROL_PRESSED, never the fill (#436 RECORD, the press flash). No
	# small verb is a toggle; one that becomes one takes PICKED.
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, small, t["text"])
	theme.set_stylebox("focus", small, t["ring"])
	theme.set_font_size("font_size", small, small_px)

	var ghost := String(names["ghost"])
	theme.set_type_variation(ghost, "Button")  # i18n: ok
	theme.set_stylebox("normal", ghost, box.call(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", ghost, box.call(t["control"]))
	theme.set_stylebox("pressed", ghost, box.call(t["pressed"]))
	theme.set_stylebox("focus", ghost, t["ring"])
	theme.set_stylebox("disabled", ghost, box.call(Color(0, 0, 0, 0), t["line"]))  # inert: the outline, as every disabled control
	theme.set_color("font_color", ghost, t["dim"])
	if medium != null:
		theme.set_font("font", ghost, medium)

	# A segment reads as a choice, not a verb: a dim label on the tile ground until it is
	# the open one, a raised control.
	var segment := String(names["segment"])
	theme.set_type_variation(segment, "Button")  # i18n: ok
	theme.set_stylebox("normal", segment, _segment(box.call(Color(0, 0, 0, 0))))
	theme.set_stylebox("hover", segment, _segment(box.call(Color(0, 0, 0, 0))))
	theme.set_stylebox("pressed", segment, _segment(box.call(t["hover"])))
	theme.set_stylebox("hover_pressed", segment, _segment(box.call(t["hover"])))
	theme.set_stylebox("focus", segment, t["ring"])
	theme.set_color("font_color", segment, t["dim"])
	if medium != null:
		theme.set_font("font", segment, medium)

	for pair in [[names["chip"], t["control"]], [names["chip_good"], Color(t["good"], 0.17)],
			[names["chip_warn"], Color(t["warn"], 0.17)], [names["chip_bad"], Color(t["bad"], 0.17)]]:
		theme.set_type_variation(String(pair[0]), "PanelContainer")  # i18n: ok
		var plate: StyleBoxFlat = box.call(pair[1])
		plate.content_margin_left = 10
		plate.content_margin_right = 10
		plate.content_margin_top = 3
		plate.content_margin_bottom = 3
		plate.set_corner_radius_all(99)  # a pill: half its height, whatever the text size
		theme.set_stylebox("panel", String(pair[0]), plate)


static func _tight(b: StyleBoxFlat) -> StyleBoxFlat:
	b.content_margin_left = 8
	b.content_margin_right = 8
	b.content_margin_top = 2
	b.content_margin_bottom = 2
	return b


## A segment's own radius, 9, inside the tile ground's 12 and its 3px padding.
static func _segment(b: StyleBoxFlat) -> StyleBoxFlat:
	b.set_corner_radius_all(9)
	return b


## ACCENT_GLOW: the fill at 35 % under the armed button, and under nothing else.
static func _glow(b: StyleBoxFlat) -> StyleBoxFlat:
	b.shadow_color = Color(b.bg_color, 0.35)
	b.shadow_size = 8
	b.shadow_offset = Vector2(0, 3)
	return b
