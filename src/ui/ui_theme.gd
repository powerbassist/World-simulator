extends RefCounted

## The game's one Theme -- U3, retuned at U5a. Before U3, three separate places
## built a StyleBoxFlat by hand with the same colour typed in three times and two
## panels reached for add_theme_font_size_override() to get a big number.
##
## A Theme assigned to a Control propagates to every descendant, so one
## assignment on each scene root covers the HUD furniture, every floating window
## and the top strip together. That propagation is the whole reason this is a
## Theme and not a module of helper functions.
##
## Built in code rather than authored as a .tres, for the same reason the panels
## are (docs/engine-decision.md, AGENTS.md style): a .tres is a blob that diffs
## badly and can only be edited through the editor, whereas the palette below is
## greppable and a colour change is a one-line diff.
##
## SIZES here are the type scale, not layout. Per-panel separations and margins
## stay as add_theme_constant_override() at their call sites -- they are that
## panel's layout, and hoisting them here would make every spacing tweak a
## remote edit in a file shared by twenty panels.
##
## ---
##
## U5a's direction, because a palette with no stated intent gets edited into mud:
## a map table in a situation room at night, with sheets of glass laid over it,
## lit from above. Every HUD plate is a translucent navy sheet with a single
## brass hairline along its *top* edge and a soft shadow below it. That one rule
## is the whole visual signature; nothing else gets a glow or a gradient.
##
## The accent is brass rather than the cyan every game HUD reaches for. Brass is
## the state's own material -- seal, instrument bezel, ministerial fitting -- and
## cyan would have made this look like a spaceship rather than a palace.

# -- Palette ------------------------------------------------------------------

const INK := Color(0.039, 0.063, 0.125)        ## #0A1020 behind everything
const HULL := Color(0.063, 0.106, 0.188)       ## #101B30 plate body
const SLATE := Color(0.106, 0.173, 0.290)      ## #1B2C4A raised row, hover
const EDGE := Color(0.169, 0.263, 0.408)       ## #2B4368 hairline
const TEXT := Color(0.867, 0.894, 0.941)       ## #DDE4F0 body text
const TEXT_DIM := Color(0.486, 0.553, 0.675)   ## #7C8DAC captions
const ACCENT := Color(0.788, 0.635, 0.153)     ## #C9A227 brass -- the one accent
const GOOD := Color(0.310, 0.706, 0.467)       ## #4FB477
const BAD := Color(0.878, 0.353, 0.353)        ## #E05A5A

## The plate's fill is drawn under a translucent alpha so the map reads through
## the HUD furniture. Modal window *bodies* stay opaque -- a panel of figures you
## can see a coastline through is unreadable, which is the failure U3's theme
## test already guards in the other direction.
const PLATE_ALPHA := 0.94

## A scrollbar's width, which in Godot is its stylebox's own minimum size. Ten is
## the engine default's order and narrow enough to read as chrome.
const BAR_WIDTH_PX := 10.0

# -- Type scale ---------------------------------------------------------------

## Barlow Condensed is narrower than the engine's built-in sans, so the base size
## is one step up from U3's 14 to hold the same reading weight.
const SIZE_MICRO := 11   ## tracked uppercase cluster and section labels
const SIZE_SMALL := 12
const SIZE_BASE := 15
const SIZE_LEAD := 18
const SIZE_FIGURE := 20
const SIZE_HERO := 30    ## the portrait card's approval figure, and only that

const FONT_CHROME := "res://assets/fonts/BarlowCondensed-Regular.ttf"
const FONT_CHROME_MEDIUM := "res://assets/fonts/BarlowCondensed-Medium.ttf"
const FONT_CHROME_BOLD := "res://assets/fonts/BarlowCondensed-SemiBold.ttf"
const FONT_FIGURE := "res://assets/fonts/IBMPlexMono-SemiBold.ttf"

# -- Label variations. Assign with `label.theme_type_variation = UiTheme.LEAD` --

const LEAD := "Lead"                 ## the one sentence a screen is about
const HEADING := "Heading"           ## small dim section label above a group
const MICRO := "Micro"               ## tracked uppercase, smaller than Heading
const FIGURE := "Figure"             ## a large number
const HERO := "Hero"                 ## the portrait card's approval, and only it
const FIGURE_LABEL := "FigureLabel"  ## the caption above a large number
const CAPTION := "Caption"           ## dim secondary text
const GOOD_TEXT := "GoodText"        ## a delta that is good news
const BAD_TEXT := "BadText"          ## a delta that is bad news
const FIGURE_ALERT := "FigureAlert"  ## a strip figure in a bad state (V4.8a)

# -- Container and button variations -------------------------------------------

const TOP_BAR_PANEL := "TopBarPanel"      ## the thin strip flush to the top edge
const PLATE := "Plate"                    ## HUD furniture: glass over the map
const PLATE_FOLDED := "PlateFolded"       ## a plate whose primary action is below the fold
const TITLE_BAR := "TitleBar"             ## a floating window's grab handle
const CLUSTER_BUTTON := "ClusterButton"   ## the four bottom-bar clusters
const SUBROW_BUTTON := "SubrowButton"     ## an entry in an open cluster's sub-row


static func apply(root: Control) -> void:
	root.theme = build()


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = SIZE_BASE

	var chrome := _font(FONT_CHROME)
	if chrome != null:
		theme.default_font = chrome

	for type in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "SpinBox"]:
		theme.set_color("font_color", type, TEXT)

	_panels(theme)
	_labels(theme)
	_buttons(theme)
	_progress(theme)
	_scrollbars(theme)
	return theme


## Two load paths on purpose. Once the editor has imported the .ttf, load()
## returns the imported FontFile and honours its import settings. Before that --
## a fresh clone running tools/run_tests.sh headless, which is how this repo is
## verified -- there is no .import file and load() fails outright, so the bytes
## are read straight off disk. Same object either way.
##
## Returning null is a real outcome, not a bug: the theme then sets no font and
## everything falls back to the engine's built-in sans. A missing font should
## make the game look plainer, never fail to start.
static func _font(path: String) -> FontFile:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is FontFile:
			return res
	var file := FontFile.new()
	if file.load_dynamic_font(path) != OK:
		return null
	return file


## Godot has no letter-spacing on Label, so the tracked uppercase micro labels
## are a FontVariation over the medium weight rather than a theme constant.
static func _tracked(path: String, spacing: int) -> Font:
	var base := _font(path)
	if base == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base
	variation.set_spacing(TextServer.SPACING_GLYPH, spacing)
	return variation


static func _panels(theme: Theme) -> void:
	# The default every PanelContainer gets, including the ones nested inside a
	# panel's own layout. Deliberately quiet: opaque, one hairline, no brass. If
	# this carried the plate's brass edge, every nested container in twenty
	# panels would draw one and the signature would read as noise.
	var panel := StyleBoxFlat.new()
	panel.bg_color = HULL
	panel.set_corner_radius_all(3)
	panel.set_border_width_all(1)
	panel.border_color = EDGE
	theme.set_stylebox("panel", "PanelContainer", panel)

	# The signature, and the only place it is defined. Applied by hand to the HUD
	# furniture and to every floating window's outer frame -- see hud.gd and
	# window_frame.gd. Light falls from above onto a sheet of glass: one brass
	# line along the top edge, a soft shadow below, and the map showing through.
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(HULL.r, HULL.g, HULL.b, PLATE_ALPHA)
	plate.set_corner_radius_all(3)
	plate.border_width_top = 1
	plate.border_color = ACCENT
	plate.shadow_color = Color(0.0, 0.0, 0.0, 0.45)
	plate.shadow_size = 8
	plate.shadow_offset = Vector2(0, 3)
	plate.content_margin_left = 10
	plate.content_margin_right = 10
	plate.content_margin_top = 8
	plate.content_margin_bottom = 8
	theme.set_type_variation(PLATE, "PanelContainer")
	theme.set_stylebox("panel", PLATE, plate)

	# The plate again, with the SAME hairline drawn along its bottom edge -- V2.1a,
	# and the only new mark this project has added to U5a's signature.
	#
	# It says one thing and not two. "There is more content below" is the
	# scrollbar's job and the scrollbar is styled just below; what this says is
	# **the thing you came to this panel to press is below the fold**, which is a
	# claim a scrollbar structurally cannot make. That failure has cost five
	# screenshot passes -- all eight diplomatic verbs lost at V1.3e and again at
	# V1.3g, three sector rows reading "No state programme" over a live 0.654 %
	# bill at V1.6e -- and none of them was a scrolling problem. The player could
	# always scroll. They had no reason to think there was anything to scroll to.
	#
	# Brass keeps one meaning under this: the state's own material marks what
	# matters. It is not a second word for the scrollbar.
	var folded := plate.duplicate()
	folded.border_width_bottom = 1
	theme.set_type_variation(PLATE_FOLDED, "PanelContainer")
	theme.set_stylebox("panel", PLATE_FOLDED, folded)

	# A window's grab handle. Lighter than the body it sits on, so the draggable
	# strip is visibly a different thing from the panel's own content.
	var title := StyleBoxFlat.new()
	title.bg_color = SLATE
	title.corner_radius_top_left = 3
	title.corner_radius_top_right = 3
	title.content_margin_left = 12
	title.content_margin_right = 6
	title.content_margin_top = 5
	title.content_margin_bottom = 5
	theme.set_type_variation(TITLE_BAR, "PanelContainer")
	theme.set_stylebox("panel", TITLE_BAR, title)

	# The top strip is flush against the window edge, so it gets square corners
	# and no border at all -- an edge drawn against the screen edge is a seam.
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(INK.r, INK.g, INK.b, PLATE_ALPHA)
	bar.set_corner_radius_all(0)
	bar.content_margin_left = 16
	bar.content_margin_right = 16
	bar.content_margin_top = 6
	bar.content_margin_bottom = 6
	theme.set_type_variation(TOP_BAR_PANEL, "PanelContainer")
	theme.set_stylebox("panel", TOP_BAR_PANEL, bar)


static func _labels(theme: Theme) -> void:
	for variation in [LEAD, HEADING, MICRO, FIGURE, FIGURE_ALERT, HERO, FIGURE_LABEL, CAPTION, GOOD_TEXT, BAD_TEXT]:
		theme.set_type_variation(variation, "Label")

	var bold := _font(FONT_CHROME_BOLD)
	var figures := _font(FONT_FIGURE)
	var tracked := _tracked(FONT_CHROME_MEDIUM, 1)

	theme.set_font_size("font_size", LEAD, SIZE_LEAD)
	theme.set_color("font_color", LEAD, TEXT)
	if bold != null:
		theme.set_font("font", LEAD, bold)

	# Heading and Micro are the same idea at two weights of emphasis: a tracked
	# uppercase label naming a group. Micro is for chrome the player reads once
	# and then recognises by position (cluster names), Heading for sections
	# inside a panel they read every time.
	theme.set_font_size("font_size", HEADING, SIZE_SMALL)
	theme.set_color("font_color", HEADING, ACCENT)
	if tracked != null:
		theme.set_font("font", HEADING, tracked)

	theme.set_font_size("font_size", MICRO, SIZE_MICRO)
	theme.set_color("font_color", MICRO, TEXT_DIM)
	if tracked != null:
		theme.set_font("font", MICRO, tracked)

	# Figures are monospaced so a ticking number stops shifting its own column
	# every month -- unemployment going 7.33 -> 7.4 used to move the decimal.
	theme.set_font_size("font_size", FIGURE, SIZE_FIGURE)
	theme.set_color("font_color", FIGURE, TEXT)
	if figures != null:
		theme.set_font("font", FIGURE, figures)

	# V4.8a. The strip's alert tone: the figure's own face and size, BAD's colour,
	# so a reading in trouble changes colour and nothing else -- a figure that
	# changed size when it went bad would shove its neighbours along the strip.
	theme.set_font_size("font_size", FIGURE_ALERT, SIZE_FIGURE)
	theme.set_color("font_color", FIGURE_ALERT, BAD)
	if figures != null:
		theme.set_font("font", FIGURE_ALERT, figures)

	theme.set_font_size("font_size", HERO, SIZE_HERO)
	theme.set_color("font_color", HERO, TEXT)
	if figures != null:
		theme.set_font("font", HERO, figures)

	theme.set_font_size("font_size", FIGURE_LABEL, SIZE_SMALL)
	theme.set_color("font_color", FIGURE_LABEL, TEXT_DIM)

	theme.set_font_size("font_size", CAPTION, SIZE_SMALL)
	theme.set_color("font_color", CAPTION, TEXT_DIM)

	theme.set_color("font_color", GOOD_TEXT, GOOD)
	theme.set_color("font_color", BAD_TEXT, BAD)


static func _buttons(theme: Theme) -> void:
	# U3 left buttons on the engine default, which was survivable against a grey
	# background and is not against navy -- the default draws a light grey slab.
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, _button_box(SLATE, EDGE))
		theme.set_stylebox("hover", type, _button_box(SLATE.lightened(0.10), ACCENT))
		theme.set_stylebox("pressed", type, _button_box(SLATE.lightened(0.16), ACCENT))
		theme.set_stylebox("focus", type, _button_box(Color(0, 0, 0, 0), ACCENT))
		# No border on disabled: live buttons carry EDGE, so the border is what
		# reads "pressable" at a glance; HULL fill alone is the inert look
		# (font_disabled_color already dims the text). The menu's disabled
		# Continue read enabled until clicked (playtest 2026-09-05).
		theme.set_stylebox("disabled", type, _button_box(HULL))
		theme.set_color("font_hover_color", type, TEXT)
		theme.set_color("font_pressed_color", type, ACCENT)
		theme.set_color("font_disabled_color", type, TEXT_DIM)

	# A cluster is an icon with a name under it, not a slab. Flat until it is the
	# open one, where brass fills the bar under it -- the same "one accent says
	# where you are" rule the rail button used, moved to the bottom of the screen.
	theme.set_type_variation(CLUSTER_BUTTON, "Button")
	theme.set_stylebox("normal", CLUSTER_BUTTON, _cluster_box(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", CLUSTER_BUTTON, _cluster_box(SLATE))
	theme.set_stylebox("pressed", CLUSTER_BUTTON, _cluster_box(SLATE, ACCENT))
	theme.set_stylebox("focus", CLUSTER_BUTTON, _cluster_box(Color(0, 0, 0, 0), ACCENT))
	theme.set_color("font_color", CLUSTER_BUTTON, TEXT_DIM)
	theme.set_color("font_hover_color", CLUSTER_BUTTON, TEXT)
	theme.set_color("font_pressed_color", CLUSTER_BUTTON, ACCENT)
	theme.set_color("font_focus_color", CLUSTER_BUTTON, TEXT)

	theme.set_type_variation(SUBROW_BUTTON, "Button")
	theme.set_stylebox("normal", SUBROW_BUTTON, _button_box(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", SUBROW_BUTTON, _button_box(SLATE))
	theme.set_stylebox("pressed", SUBROW_BUTTON, _button_box(SLATE, ACCENT))
	theme.set_stylebox("focus", SUBROW_BUTTON, _button_box(Color(0, 0, 0, 0), ACCENT))
	theme.set_color("font_color", SUBROW_BUTTON, TEXT_DIM)
	theme.set_color("font_hover_color", SUBROW_BUTTON, TEXT)
	theme.set_color("font_pressed_color", SUBROW_BUTTON, ACCENT)


## Used for share-of-a-whole bars (Economy's sector split). The engine default
## draws fill and track in near-identical greys, which on a 12px bar is no bar
## at all.
static func _progress(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = INK
	track.set_corner_radius_all(2)
	theme.set_stylebox("background", "ProgressBar", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT
	fill.set_corner_radius_all(2)
	theme.set_stylebox("fill", "ProgressBar", fill)


## Every floating panel has sat inside a ScrollContainer since U5a, so nothing has
## been unreachable since then -- and the scrollbar that says so has been on the
## engine default the whole time, which is a light grey slab against #0A1020. The
## one indicator this interface already had for "there is more below" was
## effectively invisible, which is most of why five screenshot passes found a
## panel photographed at the top of a body nobody could tell was scrolling.
##
## Themed rather than replaced. The grabber is EDGE -- the hairline colour, the
## quietest thing in the palette that is still visible -- and it brightens on
## hover the way every other control here does. It does NOT go brass: brass is
## reserved, and V2.2 has already spent the next of it on cities.
static func _scrollbars(theme: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		# The content margins are the BAR'S WIDTH and not decoration, which is the
		# whole of a bug the screenshot pass found: a StyleBoxFlat with no content
		# margins has a minimum size of zero, so the first version of this theming
		# gave the scrollbar a colour and a width of 0px and it vanished from every
		# panel at once. It had been on the engine default -- a light grey slab,
		# nearly invisible on navy but at least present -- since U5a.
		var track := StyleBoxFlat.new()
		track.bg_color = Color(INK.r, INK.g, INK.b, 0.6)
		track.set_corner_radius_all(2)
		track.content_margin_left = BAR_WIDTH_PX / 2.0
		track.content_margin_right = BAR_WIDTH_PX / 2.0
		theme.set_stylebox("scroll", type, track)

		theme.set_stylebox("grabber", type, _grabber_box(EDGE))
		theme.set_stylebox("grabber_highlight", type, _grabber_box(EDGE.lightened(0.25)))
		theme.set_stylebox("grabber_pressed", type, _grabber_box(TEXT_DIM))


static func _grabber_box(bg: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(2)
	box.content_margin_left = BAR_WIDTH_PX / 2.0
	box.content_margin_right = BAR_WIDTH_PX / 2.0
	return box


static func _button_box(bg: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(2)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	if border.a > 0.0:
		box.set_border_width_all(1)
		box.border_color = border
	return box


## A cluster's selected state is a brass bar along the *bottom*, mirroring the
## plate's top hairline: the bottom bar's light comes from the screen edge it
## sits on rather than from above. This replaces U2's rail button, whose accent
## bar ran down the left for the same reason -- the marker sits on the edge the
## control is anchored to.
static func _cluster_box(bg: Color, marker := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(2)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	if marker.a > 0.0:
		box.border_width_bottom = 2
		box.border_color = marker
	return box
