extends RefCounted

## The game's one Theme -- U3. Before this, three separate places built a
## StyleBoxFlat by hand with the same colour typed in three times (main.gd's
## _add_centered(), menu.gd's _add_overlay(), top_bar.gd's _ready()) and two
## panels reached for add_theme_font_size_override() to get a big number.
##
## A Theme assigned to a Control propagates to every descendant, so one
## assignment on each scene root covers the docked tabs, the four modal panels
## and the top bar together. That propagation is the whole reason this is a
## Theme and not a module of helper functions.
##
## Built in code rather than authored as a .tres, for the same reason the panels
## are (docs/engine-decision.md, CLAUDE.md style): a .tres is a blob that diffs
## badly and can only be edited through the editor, whereas the palette below is
## greppable and a colour change is a one-line diff.
##
## SIZES here are the type scale, not layout. Per-panel separations and margins
## stay as add_theme_constant_override() at their call sites -- they are that
## panel's layout, and hoisting them here would make every spacing tweak a
## remote edit in a file shared by fifteen panels.

const BG := Color(0.11, 0.12, 0.13)
const BG_RAISED := Color(0.16, 0.17, 0.19)
const TEXT := Color(0.88, 0.89, 0.90)
const TEXT_DIM := Color(0.58, 0.60, 0.63)
const GOOD := Color(0.42, 0.78, 0.50)
const BAD := Color(0.89, 0.44, 0.42)
const ACCENT := Color(0.45, 0.62, 0.88)

const SIZE_BASE := 14
const SIZE_SMALL := 12
const SIZE_FIGURE := 20
const SIZE_LEAD := 20

## Label type variations. Assign with `label.theme_type_variation = "Lead"`.
const LEAD := "Lead"              ## the one sentence a screen is about
const HEADING := "Heading"        ## small dim section label above a group
const FIGURE := "Figure"          ## a large number
const FIGURE_LABEL := "FigureLabel"  ## the caption above a large number
const CAPTION := "Caption"        ## dim secondary text
const GOOD_TEXT := "GoodText"     ## a delta that is good news
const BAD_TEXT := "BadText"       ## a delta that is bad news

## Container and button variations.
const TOP_BAR_PANEL := "TopBarPanel"
const RAIL_BUTTON := "RailButton"


static func apply(root: Control) -> void:
	root.theme = build()


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = SIZE_BASE

	theme.set_color("font_color", "Label", TEXT)
	theme.set_color("font_color", "Button", TEXT)
	theme.set_color("font_color", "CheckBox", TEXT)
	theme.set_color("font_color", "OptionButton", TEXT)

	_panels(theme)
	_labels(theme)
	_rail_button(theme)
	_progress(theme)
	return theme


static func _panels(theme: Theme) -> void:
	var panel := StyleBoxFlat.new()
	panel.bg_color = BG
	panel.set_corner_radius_all(4)
	# A one-pixel edge, because a modal and the tab behind it are the same colour
	# and without it the player cannot see where the modal starts.
	panel.set_border_width_all(1)
	panel.border_color = BG_RAISED
	theme.set_stylebox("panel", "PanelContainer", panel)

	# The top bar is flush against the window edge, so it gets square corners and
	# its own padding. menu.gd's overlays need nothing of their own -- the base
	# PanelContainer style above is exactly what its hand-built one produced.
	var bar := StyleBoxFlat.new()
	bar.bg_color = BG
	bar.set_corner_radius_all(0)
	bar.content_margin_left = 16
	bar.content_margin_right = 16
	bar.content_margin_top = 8
	bar.content_margin_bottom = 8
	theme.set_type_variation(TOP_BAR_PANEL, "PanelContainer")
	theme.set_stylebox("panel", TOP_BAR_PANEL, bar)


static func _labels(theme: Theme) -> void:
	for variation in [LEAD, HEADING, FIGURE, FIGURE_LABEL, CAPTION, GOOD_TEXT, BAD_TEXT]:
		theme.set_type_variation(variation, "Label")

	theme.set_font_size("font_size", LEAD, SIZE_LEAD)
	theme.set_color("font_color", LEAD, TEXT)

	theme.set_font_size("font_size", HEADING, SIZE_SMALL)
	theme.set_color("font_color", HEADING, ACCENT)

	theme.set_font_size("font_size", FIGURE, SIZE_FIGURE)
	theme.set_color("font_color", FIGURE, TEXT)

	theme.set_font_size("font_size", FIGURE_LABEL, SIZE_SMALL)
	theme.set_color("font_color", FIGURE_LABEL, TEXT_DIM)

	theme.set_font_size("font_size", CAPTION, SIZE_SMALL)
	theme.set_color("font_color", CAPTION, TEXT_DIM)

	theme.set_color("font_color", GOOD_TEXT, GOOD)
	theme.set_color("font_color", BAD_TEXT, BAD)


## The rail is a column of full-width buttons that should read as a list, not as
## seven raised widgets. Flat except when selected, where the accent bar is the
## only thing saying which tab is open.
static func _rail_button(theme: Theme) -> void:
	theme.set_type_variation(RAIL_BUTTON, "Button")

	theme.set_stylebox("normal", RAIL_BUTTON, _rail_box(Color(BG_RAISED, 0.0)))
	theme.set_stylebox("hover", RAIL_BUTTON, _rail_box(BG_RAISED))
	theme.set_stylebox("pressed", RAIL_BUTTON, _rail_box(BG_RAISED, ACCENT))
	theme.set_stylebox("focus", RAIL_BUTTON, _rail_box(Color(BG_RAISED, 0.0), ACCENT))
	theme.set_color("font_color", RAIL_BUTTON, TEXT_DIM)
	theme.set_color("font_hover_color", RAIL_BUTTON, TEXT)
	theme.set_color("font_pressed_color", RAIL_BUTTON, TEXT)
	theme.set_color("font_focus_color", RAIL_BUTTON, TEXT)


## Used for share-of-a-whole bars (Economy's sector split). The engine default
## draws fill and track in near-identical greys, which on a 12px bar is no bar
## at all.
static func _progress(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = BG_RAISED
	track.set_corner_radius_all(2)
	theme.set_stylebox("background", "ProgressBar", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(2)
	theme.set_stylebox("fill", "ProgressBar", fill)


static func _rail_box(bg: Color, marker := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.content_margin_left = 12
	box.content_margin_right = 8
	box.content_margin_top = 7
	box.content_margin_bottom = 7
	if marker.a > 0.0:
		box.border_width_left = 3
		box.border_color = marker
	return box
