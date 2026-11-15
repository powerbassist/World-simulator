extends RefCounted

## The theme's scroll bars, and the clear gap between a scrolled panel's text and its vertical bar. Split out of
## ui_theme.gd (at its size ceiling); the colours are the theme's, passed in so this file never preloads it.

const BAR_WIDTH_PX := 10.0
## The clear gap between a scrolled panel's content and its vertical scroll bar. Godot 4.7 spaces the VERTICAL bar
## with ScrollContainer's `scrollbar_h_separation` ("The space between the ScrollContainer's vertical scroll bar and
## its content, in pixels. No space will be added when the content's minimum size is larger than the
## ScrollContainer's size."): the name's axis is the separation's, not the bar's, and `scrollbar_v_separation` is
## the horizontal bar's. One theme constant, so every one of the ScrollContainers gets it and the bar's own boxes
## (and so its input area) stay as they were.
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
	theme.set_constant("scrollbar_h_separation", "ScrollContainer", int(SCROLL_GAP_PX))
	for type in ["VScrollBar", "HScrollBar"]:
		# The content margins are the BAR'S WIDTH and not decoration: a StyleBoxFlat
		# with none has a minimum size of zero, so a first version of this theming
		# gave the scrollbar a colour and a width of 0px and it vanished everywhere.
		var track := StyleBoxFlat.new()
		track.bg_color = Color(ink.r, ink.g, ink.b, 0.6)
		track.set_corner_radius_all(2)
		track.content_margin_left = BAR_WIDTH_PX / 2.0
		track.content_margin_right = BAR_WIDTH_PX / 2.0
		theme.set_stylebox("scroll", type, track)

		theme.set_stylebox("grabber", type, _grabber_box(edge))
		theme.set_stylebox("grabber_highlight", type, _grabber_box(edge.lightened(0.25)))
		theme.set_stylebox("grabber_pressed", type, _grabber_box(dim))


static func _grabber_box(bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(2)
	box.content_margin_left = BAR_WIDTH_PX / 2.0
	box.content_margin_right = BAR_WIDTH_PX / 2.0
	return box
