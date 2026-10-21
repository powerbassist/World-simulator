extends RefCounted

const AccentRule = preload("res://src/ui/accent_rule.gd")

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
## V5.1a's direction (BUREAU, picked by the author 2026-10-21): a head of state's
## desk, not a situation room. Graphite panels, near-opaque, one 1px hairline all
## round; no glow, no gradient. The single accent is the PLAYED NATION'S OWN flag
## colour, chosen by a rule over the flag's bands (accent_rule.gd) and carried only
## by what says "you are here" -- the active tab or marker, a focus ring, a fill.
## The brass top-edge hairline of U5a is gone, and so is the rule against drawing
## a plate's other three edges: those edges are the grammar now.
##
## Colour names are kept from U5a (fifty callers) and mean what they say here:
## INK the ground, HULL a panel, SLATE a raised row or hover, EDGE the hairline.

# -- Palette ------------------------------------------------------------------

const INK := Color(0.059, 0.071, 0.078)        ## #0F1214 behind everything
const HULL := Color(0.090, 0.106, 0.118)       ## #171B1E panel body
const SLATE := Color(0.153, 0.176, 0.196)      ## #272D32 raised row, hover
const EDGE := Color(0.196, 0.224, 0.251)       ## #323940 hairline
const TEXT := Color(0.929, 0.941, 0.949)       ## #EDF0F2 body text
const TEXT_DIM := Color(0.557, 0.596, 0.624)   ## #8E989F captions
const GOOD := Color(0.247, 0.702, 0.498)       ## #3FB37F
const BAD := Color(0.898, 0.325, 0.294)        ## #E5534B
const WARN := Color(0.890, 0.651, 0.227)       ## #E3A63A attention, not failure

## What the accent is when there is no nation to take it from (the menu), and when
## no band of the flag passes accent_rule.gd's floors. A cool azure, deliberately
## not a flag colour of its own.
const ACCENT_FALLBACK := Color(0.361, 0.616, 0.922)  ## #5C9DEB

## Panels are graphite and nearly opaque: the map may show through a HUD plate
## only faintly. A panel of figures you can see a coastline through is unreadable
## (U3's lesson), which is why a window body stays fully opaque.
const PLATE_ALPHA := 0.97

## A scrollbar's width, which in Godot is its stylebox's own minimum size.
const BAR_WIDTH_PX := 10.0

# -- Type scale ---------------------------------------------------------------

## One family, Archivo (variable, SIL OFL), cut by axis rather than by file: the
## width axis runs 62-125 and 88 is the condensed cut the tables need -- French
## runs about a fifth longer than English -- while headings may open it up. The
## base size stays at U5a's 15.
const SIZE_MICRO := 11   ## tracked uppercase cluster and section labels
const SIZE_SMALL := 12
const SIZE_BASE := 15
const SIZE_LEAD := 18
const SIZE_FIGURE := 20
const SIZE_MAP := 10     ## the map's place names, drawn in map_face() -- see WIDTH_MAP
const SIZE_HERO := 30    ## the portrait card's approval figure, and only that

const FONT_ARCHIVO := "res://assets/fonts/Archivo-Variable.ttf"
const WIDTH_CONDENSED := 88
## The map's own labels sit in a few pixels of ocean or a small state, and the
## collision packer drops a name that does not fit: Archivo at 88 is wider than
## the Barlow Condensed these labels were tuned on (a 6-letter caps name is 26px
## in Barlow, 36 in Archivo 88, 27 at the axis floor of 62), so they take the floor.
const WIDTH_MAP := 62
const WEIGHT_BODY := 400
const WEIGHT_MEDIUM := 500
const WEIGHT_BOLD := 650

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
const PLATE := "Plate"                    ## HUD furniture over the map
const PLATE_FOLDED := "PlateFolded"       ## a plate whose primary action is below the fold
const TITLE_BAR := "TitleBar"             ## a floating window's grab handle
const CLUSTER_BUTTON := "ClusterButton"   ## the four bottom-bar clusters
const SUBROW_BUTTON := "SubrowButton"     ## an entry in an open cluster's sub-row

## The accent in force: the played nation's, set by apply() and read by everything
## that draws "you are here" -- the theme below, the map's own marks. Static
## because a Theme is built once per scene root and the map is not a theme.
static var _accent: Color = ACCENT_FALLBACK
static var _archivo: FontFile
static var _map_face: Font


## The accent a flag resolves to -- accent_rule.gd's floors over the flag's bands,
## judged against the panel the accent is drawn on and the two semantic tones.
static func accent_for(bands: Array) -> Color:
	return AccentRule.pick(bands, HULL, [BAD, GOOD], ACCENT_FALLBACK)


static func accent() -> Color:
	return _accent


## The face the map draws place names in -- see WIDTH_MAP. One cached object: the
## map asks for it every frame.
static func map_face() -> Font:
	if _map_face == null:
		_map_face = _face(WEIGHT_BODY, 0, false, WIDTH_MAP)
	return _map_face if _map_face != null else ThemeDB.fallback_font


## The theme for a played nation: its flag's accent, by the rule.
static func apply_for(root: Control, nation) -> void:
	apply(root, accent_for(nation.flag_bands))


static func apply(root: Control, accent_color := ACCENT_FALLBACK) -> void:
	_accent = accent_color
	root.theme = build()


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = SIZE_BASE

	var body := _face(WEIGHT_BODY)
	if body != null:
		theme.default_font = body

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
## (V5.1-0d: the .ttf.import files are committed, so a fresh clone DOES take the
## load() path once tools/suite_runner.py's cold --import has run -- which is why
## the runner now checks that import finished: a cut-off one left the fonts as
## 0-byte .tmp files and every UI test printed the engine's load errors.)
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


## Archivo at a weight, condensed, optionally tracked and with tabular figures.
## Godot has no letter-spacing on Label, so tracking is a FontVariation's glyph
## spacing; the axes and the `tnum` feature are keyed by OpenType TAG (an int),
## not by name -- a string key is accepted and silently does nothing.
static func _face(weight: int, spacing := 0, tabular := false, width := WIDTH_CONDENSED) -> Font:
	if _archivo == null:
		_archivo = _font(FONT_ARCHIVO)
	if _archivo == null:
		return null
	var ts := TextServerManager.get_primary_interface()
	var face := FontVariation.new()
	face.base_font = _archivo
	face.variation_opentype = {ts.name_to_tag("wght"): weight, ts.name_to_tag("wdth"): width}
	if tabular:
		face.opentype_features = {ts.name_to_tag("tnum"): 1}
	if spacing != 0:
		face.set_spacing(TextServer.SPACING_GLYPH, spacing)
	return face


static func _panels(theme: Theme) -> void:
	# The default every PanelContainer gets, including the ones nested inside a
	# panel's own layout. Opaque, one hairline: the grammar of the whole screen.
	var panel := StyleBoxFlat.new()
	panel.bg_color = HULL
	panel.set_corner_radius_all(4)
	panel.set_border_width_all(1)
	panel.border_color = EDGE
	theme.set_stylebox("panel", "PanelContainer", panel)

	# HUD furniture over the map and every floating window's outer frame -- see
	# hud.gd and window_frame.gd. The same panel, a touch translucent and with
	# room inside; it carries no accent, because the accent is reserved for what
	# marks where you are.
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(HULL.r, HULL.g, HULL.b, PLATE_ALPHA)
	plate.set_corner_radius_all(4)
	plate.set_border_width_all(1)
	plate.border_color = EDGE
	plate.content_margin_left = 10
	plate.content_margin_right = 10
	plate.content_margin_top = 8
	plate.content_margin_bottom = 8
	theme.set_type_variation(PLATE, "PanelContainer")
	theme.set_stylebox("panel", PLATE, plate)

	# The plate outlined in the accent, 2px along its bottom -- V2.1a's one added mark.
	# It says "the thing you came to this panel to press is below the fold", a
	# claim a scrollbar structurally cannot make (that failure cost five
	# screenshot passes: all eight diplomatic verbs lost at V1.3e and again at
	# V1.3g, three sector rows reading "No state programme" over a live bill at
	# V1.6e -- the player could always scroll, and had no reason to think there
	# was anything to scroll to). The accent keeps one meaning under this: it
	# marks what you are being sent to.
	var folded := plate.duplicate()
	folded.border_width_bottom = 2
	folded.border_color = _accent
	theme.set_type_variation(PLATE_FOLDED, "PanelContainer")
	theme.set_stylebox("panel", PLATE_FOLDED, folded)

	# A window's grab handle. Lighter than the body it sits on.
	var title := StyleBoxFlat.new()
	title.bg_color = SLATE
	title.corner_radius_top_left = 4
	title.corner_radius_top_right = 4
	title.content_margin_left = 12
	title.content_margin_right = 6
	title.content_margin_top = 5
	title.content_margin_bottom = 5
	theme.set_type_variation(TITLE_BAR, "PanelContainer")
	theme.set_stylebox("panel", TITLE_BAR, title)

	# The top strip is flush against the window edge: square corners, and only a
	# hairline underneath -- an edge drawn against the screen edge is a seam.
	var bar := StyleBoxFlat.new()
	bar.bg_color = Color(INK.r, INK.g, INK.b, PLATE_ALPHA)
	bar.set_corner_radius_all(0)
	bar.border_width_bottom = 1
	bar.border_color = EDGE
	bar.content_margin_left = 16
	bar.content_margin_right = 16
	# 3, down from 6 at V4.8a: the figures stack caption over value now, and the
	# strip must stay inside window_frame.gd's 44px TOP_MARGIN (it drew 50 at 6).
	bar.content_margin_top = 3
	bar.content_margin_bottom = 3
	theme.set_type_variation(TOP_BAR_PANEL, "PanelContainer")
	theme.set_stylebox("panel", TOP_BAR_PANEL, bar)


static func _labels(theme: Theme) -> void:
	for variation in [LEAD, HEADING, MICRO, FIGURE, FIGURE_ALERT, HERO, FIGURE_LABEL, CAPTION, GOOD_TEXT, BAD_TEXT]:
		theme.set_type_variation(variation, "Label")

	var bold := _face(WEIGHT_BOLD)
	var figures := _face(WEIGHT_BOLD, 0, true)
	var tracked := _face(WEIGHT_MEDIUM, 1)

	theme.set_font_size("font_size", LEAD, SIZE_LEAD)
	theme.set_color("font_color", LEAD, TEXT)
	if bold != null:
		theme.set_font("font", LEAD, bold)

	# Heading and Micro are the same idea at two weights of emphasis: a tracked
	# uppercase label naming a group. Micro is for chrome the player reads once
	# and then recognises by position (cluster names), Heading for sections
	# inside a panel they read every time.
	theme.set_font_size("font_size", HEADING, SIZE_SMALL)
	theme.set_color("font_color", HEADING, _accent)
	if tracked != null:
		theme.set_font("font", HEADING, tracked)

	theme.set_font_size("font_size", MICRO, SIZE_MICRO)
	theme.set_color("font_color", MICRO, TEXT_DIM)
	if tracked != null:
		theme.set_font("font", MICRO, tracked)

	# Figures carry the tabular-figures feature so a ticking number stops
	# shifting its own column every month -- unemployment going 7.33 -> 7.4 used
	# to move the decimal. (Archivo's default digits are proportional.)
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
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, _button_box(SLATE, EDGE))
		theme.set_stylebox("hover", type, _button_box(SLATE.lightened(0.10), _accent))
		theme.set_stylebox("pressed", type, _button_box(SLATE.lightened(0.16), _accent))
		theme.set_stylebox("focus", type, _button_box(Color(0, 0, 0, 0), _accent))
		# No border on disabled: live buttons carry EDGE, so the border is what
		# reads "pressable" at a glance; HULL fill alone is the inert look
		# (font_disabled_color already dims the text). The menu's disabled
		# Continue read enabled until clicked (playtest 2026-09-05).
		theme.set_stylebox("disabled", type, _button_box(HULL))
		theme.set_color("font_hover_color", type, TEXT)
		theme.set_color("font_pressed_color", type, _accent)
		theme.set_color("font_disabled_color", type, TEXT_DIM)

	# A cluster is an icon with a name under it, not a slab. Flat until it is the
	# open one, where the accent fills the bar under it -- "one accent says where
	# you are", the rule the rail button used, at the bottom of the screen.
	theme.set_type_variation(CLUSTER_BUTTON, "Button")
	theme.set_stylebox("normal", CLUSTER_BUTTON, _cluster_box(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", CLUSTER_BUTTON, _cluster_box(SLATE))
	theme.set_stylebox("pressed", CLUSTER_BUTTON, _cluster_box(SLATE, _accent))
	theme.set_stylebox("focus", CLUSTER_BUTTON, _cluster_box(Color(0, 0, 0, 0), _accent))
	theme.set_color("font_color", CLUSTER_BUTTON, TEXT_DIM)
	theme.set_color("font_hover_color", CLUSTER_BUTTON, TEXT)
	theme.set_color("font_pressed_color", CLUSTER_BUTTON, _accent)
	theme.set_color("font_focus_color", CLUSTER_BUTTON, TEXT)

	theme.set_type_variation(SUBROW_BUTTON, "Button")
	theme.set_stylebox("normal", SUBROW_BUTTON, _button_box(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", SUBROW_BUTTON, _button_box(SLATE))
	theme.set_stylebox("pressed", SUBROW_BUTTON, _button_box(SLATE, _accent))
	theme.set_stylebox("focus", SUBROW_BUTTON, _button_box(Color(0, 0, 0, 0), _accent))
	theme.set_color("font_color", SUBROW_BUTTON, TEXT_DIM)
	theme.set_color("font_hover_color", SUBROW_BUTTON, TEXT)
	theme.set_color("font_pressed_color", SUBROW_BUTTON, _accent)


## Used for share-of-a-whole bars (Economy's sector split). The engine default
## draws fill and track in near-identical greys, which on a 12px bar is no bar
## at all.
static func _progress(theme: Theme) -> void:
	var track := StyleBoxFlat.new()
	track.bg_color = INK
	track.set_corner_radius_all(2)
	theme.set_stylebox("background", "ProgressBar", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = _accent
	fill.set_corner_radius_all(2)
	theme.set_stylebox("fill", "ProgressBar", fill)


## Every floating panel sits inside a ScrollContainer, so nothing is unreachable --
## and the scrollbar that says so was once the engine default, a light grey slab,
## which is most of why five screenshot passes photographed a panel at the top of a
## body nobody could tell was scrolling.
##
## The grabber is EDGE -- the hairline colour, the quietest thing in the palette
## that is still visible -- and it brightens on hover like every other control. It
## does NOT take the accent: the accent says where you are, not that you can scroll.
static func _scrollbars(theme: Theme) -> void:
	for type in ["VScrollBar", "HScrollBar"]:
		# The content margins are the BAR'S WIDTH and not decoration: a StyleBoxFlat
		# with none has a minimum size of zero, so a first version of this theming
		# gave the scrollbar a colour and a width of 0px and it vanished everywhere.
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
	box.set_corner_radius_all(4)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	if border.a > 0.0:
		box.set_border_width_all(1)
		box.border_color = border
	return box


## A cluster's selected state is a bar of the accent along the *bottom*, on the
## screen edge the control is anchored to (U2's rail button put its bar on the left
## for the same reason).
static func _cluster_box(bg: Color, marker := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(4)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	if marker.a > 0.0:
		box.border_width_bottom = 2
		box.border_color = marker
	return box
