extends RefCounted

## The theme's scroll bars, and the clear gap between a scrolled panel's text and its vertical bar. Split out of
## ui_theme.gd (at its size ceiling); the colours are the theme's, passed in so this file never preloads it.

const BAR_WIDTH_PX := 10.0
## The clear gap between a scrolled panel's text and its vertical scroll bar. ScrollContainer's own
## scrollbar_v_separation does nothing in 4.7.2 (measured: an override of 20 left the
## content as wide as before), so the gap is part of the bar: its track is wider by this much and every part of
## the bar is drawn inside it, which moves the content over by the same amount in every panel at once.
const SCROLL_GAP_PX := 8.0


## Every floating panel sits inside a ScrollContainer, so nothing is unreachable --
## and the scrollbar that says so was once the engine default, a light grey slab,
## which is most of why five screenshot passes photographed a panel at the top of a
## body nobody could tell was scrolling.
##
## The grabber is EDGE -- the hairline colour, the quietest thing in the palette
## that is still visible -- and it brightens on hover like every other control. It
## does NOT take the accent: the accent says where you are, not that you can scroll.
static func apply(theme: Theme, ink: Color, edge: Color, dim: Color) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		# The content margins are the BAR'S WIDTH and not decoration: a StyleBoxFlat
		# with none has a minimum size of zero, so a first version of this theming
		# gave the scrollbar a colour and a width of 0px and it vanished everywhere.
		var track := StyleBoxFlat.new()
		track.bg_color = Color(ink.r, ink.g, ink.b, 0.6)
		track.set_corner_radius_all(2)
		track.content_margin_left = BAR_WIDTH_PX / 2.0
		track.content_margin_right = BAR_WIDTH_PX / 2.0
		theme.set_stylebox("scroll", type, _gapped(track, type == "VScrollBar"))

		theme.set_stylebox("grabber", type, _gapped(_grabber_box(edge), type == "VScrollBar"))
		theme.set_stylebox("grabber_highlight", type, _gapped(_grabber_box(edge.lightened(0.25)), type == "VScrollBar"))
		theme.set_stylebox("grabber_pressed", type, _gapped(_grabber_box(dim), type == "VScrollBar"))



## A vertical bar part with SCROLL_GAP_PX of nothing on the content's side (its left): the bar is that much wider and
## the box is drawn back inside the width it had. A horizontal bar is left as it was: the author's complaint is the
## vertical one, and a horizontal bar's thickness does not follow its stylebox's margins here (measured: 7 px).
static func _gapped(box: StyleBoxFlat, vertical: bool) -> StyleBoxFlat:
	if vertical:
		box.content_margin_left += SCROLL_GAP_PX
		box.expand_margin_left = -SCROLL_GAP_PX
	return box


static func _grabber_box(bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(2)
	box.content_margin_left = BAR_WIDTH_PX / 2.0
	box.content_margin_right = BAR_WIDTH_PX / 2.0
	return box
