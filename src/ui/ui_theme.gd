extends RefCounted

const ScrollBars = preload("res://src/ui/scroll_bars.gd")
const OptionCheckStyle = preload("res://src/ui/option_check_style.gd")
const ControlStyle = preload("res://src/ui/control_style.gd")
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
## ---
##
## G3, "Sheets on glass" (the author's pick, 2026-11-21, after "je veux un design
## moderne"; the spec is Design's g3-spec.md, AGENTS.md "UI conventions" carries its
## rules). The map fills the screen; the chrome is three floating glass PANES (a dark
## tint over the blurred map, a light rim); the workspace's content sits on opaque
## SHEETS, one job each, separated by space and a change of surface rather than by
## lines. Slice S0 is this file and PanelKit: every screen takes the colours, corners
## and button states at once; the shell's layout is S1's.
##
## The BUREAU names (INK, HULL, SLATE, EDGE) stay as aliases of the G3 surface they
## became, because fifty callers draw with them; a slice that re-lays a screen moves
## it to the G3 name.

# -- Palette ------------------------------------------------------------------

const INK := Color(0.059, 0.071, 0.078)        ## #0F1214 the deepest ground: a well, a track
const SHEET := Color("#11151A")                ## the body of a sheet
const TILE := Color("#1A2026")                 ## a day, a figure tile, a quiet group in a sheet
const TILE_HOVER := Color("#262D34")           ## a tile under the pointer; the accent's judging surface
const CONTROL := Color("#252C33")              ## a button, a chip, an appointment
const CONTROL_HOVER := Color("#323A42")        ## a control under the pointer; the open tab
const CONTROL_PRESSED := Color("#1C2228")      ## a control held down
const LINE := Color("#242B31")                 ## the divider between table rows, and nothing else
const LINE_STRONG := Color("#343C44")          ## an empty track, a disabled outline
const POPOVER := Color("#1C2228")              ## a tooltip, a menu
const TEXT := Color("#F3F5F7")                 ## body text
const TEXT_DIM := Color("#A3ACB3")             ## captions on a sheet
const TEXT_DIM_CHROME := Color("#B6BEC5")      ## captions on a glass pane
## A disabled label, an out-of-month date: large or secondary text only (4.6:1 on a tile).
const TEXT_OFF := Color("#7F8890")
const GOOD := Color(0.247, 0.702, 0.498)       ## #3FB37F
## G3: lifted from #E5534B, which was 4.4:1 on a tile; this is 5.5.
const BAD := Color("#F26A62")
const WARN := Color(0.890, 0.651, 0.227)       ## #E3A63A something waits on you, with a date
const WARN_GROUND := Color(WARN, 0.17)         ## the ground of a deadline tag
## A glass pane: this tint over the blurred map, which is first darkened by the gain.
const PANE_TINT := Color(0.051, 0.067, 0.082, 0.64)  ## #0D1115 at 64 %
const PANE_BACKDROP_GAIN := 0.6
const PANE_RIM := Color(1, 1, 1, 0.13)
const PANE_SOLID := Color(0.051, 0.067, 0.082, 0.92) ## a pane with Glass off
## BUREAU's names, as the G3 surface each became (see the header).
const HULL := SHEET
const SLATE := CONTROL
const EDGE := LINE_STRONG

# -- Shape and depth (G3). Radii and shadows are the look; spacing stays layout. --

const R_PANE := 22
const R_SHEET := 16
const R_TILE := 12
const R_SMALL := 10
const R_POPOVER := 14
const GAP_PANE := 12   ## between panes, between sheets, from the screen's edge
const PAD_PANE := 12   ## inside a pane, left and right
## Shadows: the pictures' CSS blur radii, retuned in a real window (StyleBoxFlat falls off sooner).
const ELEV_SHEET := [Color(0, 0, 0, 0.40), Vector2(0, 6), 14]   # colour, offset, size
const ELEV_PANE := [Color(0, 0, 0, 0.40), Vector2(0, 10), 24]
const ELEV_POPOVER := [Color(0, 0, 0, 0.45), Vector2(0, 8), 18]

## The map's own mark for what is NOT the player's: another nation's city, project
## or plant. The accent is the played nation's identity, so it goes on that nation's
## marks alone; everything else is this one neutral tone.
const MAP_NEUTRAL := Color(0.827, 0.851, 0.878)  ## #D3D9E0

## What the accent is when there is no nation to take it from (the menu), and when
## no band of the flag passes accent_rule.gd's floors. A cool azure, deliberately
## not a flag colour of its own.
## #4A535A: a neutral fill a chart's accent and ticks stand out from (ChartKit.range_bar, the bars a year).
const NEUTRAL_BAR := Color(0.290, 0.325, 0.353)
const ACCENT_FALLBACK := Color(0.361, 0.616, 0.922)  ## #5C9DEB


# -- Type scale ---------------------------------------------------------------

## One family, Archivo (variable, SIL OFL), cut by axis rather than by file: the
## width axis runs 62-125 and 88 is the condensed cut the tables need -- French
## runs about a fifth longer than English -- while headings may open it up. The
## base size stays at U5a's 15. V5.1-d2 (G11) retuned the steps round it: 11/12
## and 18/20 read as one size, 12 to 15 and 20 to 30 as leaps; each step is now
## about a fifth over the last (tests/test_ui_theme.gd holds the ratios).
const SIZE_MICRO := 11   ## tracked uppercase cluster and section labels
const SIZE_SMALL := 13
const SIZE_BASE := 15
const SIZE_LEAD := 18
const SIZE_FIGURE := 22
## G3: a screen's title and a person's name on their sheet. Off the step ladder the
## test holds (18 -> 20 is a tenth): it is a title cut, not a reading size.
const SIZE_TITLE := 20
const SIZE_MAP := 10     ## the map's place names, drawn in map_face() -- see WIDTH_MAP
const SIZE_HERO := 27    ## the portrait card's approval figure, and only that

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
## V5.3-0 R15: a newspaper's masthead, the one cut this heavy.
const WEIGHT_BLACK := 900

# -- Label variations. Assign with `label.theme_type_variation = UiTheme.LEAD` --

const LEAD := "Lead"                 ## the one sentence a screen is about  # i18n: ok
const HEADING := "Heading"           ## small dim section label above a group  # i18n: ok
const MICRO := "Micro"               ## tracked uppercase, smaller than Heading  # i18n: ok
const FIGURE := "Figure"             ## a large number  # i18n: ok
const TITLE := "Title"               ## a screen's title, a person's name on their sheet (G3)  # i18n: ok
const MASTHEAD := "Masthead"  ## a paper's name on a front page (V5.3-0 R15)  # i18n: ok
const HEADLINE := "Headline"  ## a front page's headline at display size (R15)  # i18n: ok
const HERO := "Hero"                 ## the portrait card's approval, and only it  # i18n: ok
const FIGURE_LABEL := "FigureLabel"  ## the caption above a large number
const CAPTION := "Caption"           ## dim secondary text  # i18n: ok
const GOOD_TEXT := "GoodText"        ## a delta that is good news
const BAD_TEXT := "BadText"          ## a delta that is bad news
const WARN_TEXT := "WarnText"        ## something waits on the player (V5.1-d1b3: why the clock holds)
const BAD_SMALL := "BadSmall"        ## bad news at the caption size (V5.2-0b: a law's blocking glyph)
const GOOD_SMALL := "GoodSmall"      ## good news at the caption size (V5.2 close R5: a result's tag)
## V5.1-c. The same tones for a RichTextLabel (term_text.gd), which reads
## default_color and normal_font_size where a Label reads font_color and font_size.
const RICH_CAPTION := "RichCaption"
const RICH_GOOD := "RichGood"
const RICH_BAD := "RichBad"
const FIGURE_ALERT := "FigureAlert"  ## a strip figure in a bad state (V4.8a)

# -- Container and button variations -------------------------------------------

const PLATE := "Plate"                    ## a SHEET (G3): opaque, borderless, one job  # i18n: ok
const PANE := "Pane"                      ## a glass pane of the chrome (PanelKit.pane)  # i18n: ok
const TILE_PANEL := "TilePanel"           ## a tile inside a sheet
const POPOVER_PANEL := "PopoverPanel"     ## a tooltip or a menu: opaque, never blurred
const GHOST := "Ghost"                    ## a quiet link-like action: no fill until hovered  # i18n: ok
const PLATE_FOLDED := "PlateFolded"       ## a plate whose primary action is below the fold
const CLUSTER_BUTTON := "ClusterButton"   ## the four bottom-bar clusters
const SUBROW_BUTTON := "SubrowButton"     ## an entry in an open cluster's sub-row
## G3 S1: a toggle that is ON wears the accent fill. Its own variation (PanelKit.toggle), because
## "pressed" is also a plain button held down, which must not flash the fill (#436 RECORD).
const PICKED := "Picked"                  # i18n: ok
const SIDEBAR_ROW := "SidebarRow"         ## a domain's row in the sidebar pane (G3 spec section 2)
const REQUESTS_BUTTON := "RequestsButton" ## the title bar's "requests waiting" mark (V5.2 pre-gate)
const CHIEF_MARK := "ChiefMark"           ## the chief's mark beside it (G1): a raised plate, no tone of its own
## V5.3 c' (the bureau audit's items 1, 2, 5; control_style.gd says why each looks as it does).
const PRIMARY := "Primary"                ## the one action a screen exists for  # i18n: ok
const SMALL := "Small"                    ## a verb at the caption size  # i18n: ok
const SEGMENT := "Segment"                ## one choice among a few, side by side  # i18n: ok
const CHIP := "Chip"                      ## a bordered caption plate, neutral  # i18n: ok
const CHIP_GOOD := "ChipGood"             ## a chip in the good-news tone
const CHIP_WARN := "ChipWarn"             ## a chip in the attention tone
const CHIP_BAD := "ChipBad"               ## a chip in the bad-news tone
const CHIP_TEXT := "ChipText"             ## a chip's words: caption size, the text tone
const COUNT_PILL := "CountPill"           ## a count that waits on you: a solid amber pill, a dark figure
const OPTION_CHECK := "OptionCheck"       ## an option on a verb, not a verb (V5.2 close R4: the audience's Lie)

## The accent in force: the played nation's, set by apply() and read by everything
## that draws "you are here" -- the theme below, the map's own marks. Static
## because a Theme is built once per scene root and the map is not a theme.
static var _accent: Color = ACCENT_FALLBACK
## V5.1-c2.4, the text-size option: every size of the type scale times this, and
## nothing else -- margins and separations are layout, and the shell's slots are
## sized at 100 %. Set from settings.cfg before the first theme is built.
static var _text_scale := 1.0
static var _archivo: FontFile
static var _map_face: Font
static var _map_figure_face: Font


## The accent a flag resolves to -- accent_rule.gd's floors over the flag's bands,
## judged against the three state tones (alert, good, attention) and the LIGHTEST
## surface it is read on as text, TILE_HOVER (a hovered tile); judged on the sheet
## (HULL) it would pass colours that fail where they are actually used.
static func accent_for(bands: Array) -> Color:
	return AccentRule.pick(bands, TILE_HOVER, [BAD, GOOD, WARN], ACCENT_FALLBACK)


static func accent() -> Color:
	return _accent


## G3: the accent as a FILL -- the same rule's second result (accent_rule.fill): darkened
## until white holds AA on it, or left as it is when its hue cannot (a yellow), in which
## case its label is dark. For today's date, the armed verb, a picked chip, a screen's one
## main action; no other button is filled.
static func accent_fill() -> Color:
	return AccentRule.fill(_accent)


## The label colour on accent_fill(): white, or the solid pane's dark when white fails.
static func on_accent_fill() -> Color:
	return AccentRule.label_on(accent_fill(), Color(PANE_SOLID, 1.0))


## G3's "Glass" setting (settings_panel.gd): on, the chrome's panes blur the map
## (frost.gd); off, they are PANE_SOLID and nothing reads the screen. Set before the first
## theme is built, like the text size. There is no renderer check: the one renderer the game
## ships on, gl_compatibility, gives the blur's screen mipmaps (measured at S0, frost.gd), and
## a player whose machine draws it badly turns the setting off (#436 RECORD 10).
static var _glass := true


static func set_glass(on: bool) -> void:
	_glass = on


static func glass() -> bool:
	return _glass


## The face the map draws place names in -- see WIDTH_MAP. One cached object: the
## map asks for it every frame.
static func map_face() -> Font:
	if _map_face == null:
		_map_face = _face(WEIGHT_BODY, 0, false, WIDTH_MAP)
	return _map_face if _map_face != null else ThemeDB.fallback_font


## Screen 6: the figure printed on a region of the map (map_regions.gd) -- bold, tabular, the
## body width, because a place name's narrow face read "95%" for "9.5 %" on a real screen
## (QA's T1 on #384). One cached object, asked every frame.
static func map_figure_face() -> Font:
	if _map_figure_face == null:
		_map_figure_face = _face(WEIGHT_BOLD, 0, true)
	return _map_figure_face if _map_figure_face != null else ThemeDB.fallback_font


## The theme for a played nation: its flag's accent, by the rule.
static func apply_for(root: Control, nation) -> void:
	apply(root, accent_for(nation.flag_bands))


static func apply(root: Control, accent_color := ACCENT_FALLBACK) -> void:
	_accent = accent_color
	root.theme = build()


## The theme again, with the accent already chosen and the text size now set:
## the settings row's live change, on whichever scene is up.
static func rebuild(root: Control) -> void:
	root.theme = build()


static func set_text_scale(scale: float) -> void:
	_text_scale = scale


static func text_scale() -> float:
	return _text_scale


## A size of the type scale at the chosen text size.
static func _px(size: int) -> int:
	return roundi(size * _text_scale)


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = _px(SIZE_BASE)

	var body := _face(WEIGHT_BODY)
	if body != null:
		theme.default_font = body

	for type in ["Label", "Button", "CheckBox", "OptionButton", "LineEdit", "SpinBox"]:  # i18n: ok
		theme.set_color("font_color", type, TEXT)

	_panels(theme)
	_labels(theme)
	_rich(theme)
	_buttons(theme)
	_progress(theme)
	ScrollBars.apply(theme, INK, EDGE, TEXT_DIM)
	_sliders(theme)
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
	# The default every PanelContainer gets, including the ones nested inside a panel's
	# own layout: a TILE, opaque and borderless -- a quiet group set off from the sheet
	# it sits on by its surface, not by a line (G3).
	theme.set_stylebox("panel", "PanelContainer", _flat(TILE, R_TILE))

	# A SHEET: what every workspace plate and HUD card is. Opaque (a panel of figures you
	# can see a coastline through is unreadable, U3's lesson), no border, a soft shadow;
	# the accent never, because it is reserved for what marks where you are. The margins
	# stay BUREAU's in S0 -- PAD_SHEET comes with S1's widths, so no screen re-lays here.
	var sheet := _flat(SHEET, R_SHEET, ELEV_SHEET)
	sheet.content_margin_left = 10
	sheet.content_margin_right = 10
	sheet.content_margin_top = 8
	sheet.content_margin_bottom = 8
	_variation(theme, PLATE, sheet)

	# The sheet with a 2px accent bottom edge -- V2.1a's one added mark, kept by G3. It
	# says "the thing you came to this panel to press is below the fold", a claim a
	# scrollbar structurally cannot make (that failure cost five screenshot passes: all
	# eight diplomatic verbs lost at V1.3e and again at V1.3g, three sector rows reading
	# "No state programme" over a live bill at V1.6e). The accent keeps one meaning under
	# this: it marks what you are being sent to.
	var folded := sheet.duplicate()
	folded.border_width_bottom = 2
	folded.border_color = _accent
	_variation(theme, PLATE_FOLDED, folded)

	_variation(theme, TILE_PANEL, _flat(TILE, R_TILE))

	# A tooltip or a menu: opaque, so it never reads the screen and never needs a second
	# copy of it; the pane's rim so it lifts off a sheet. The engine's own tooltips too.
	var popover := _flat(POPOVER, R_POPOVER, ELEV_POPOVER)
	popover.set_border_width_all(1)
	popover.border_color = PANE_RIM
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		popover.set_content_margin(side, 13)
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		popover.set_content_margin(side, 10)
	_variation(theme, POPOVER_PANEL, popover)
	theme.set_stylebox("panel", "TooltipPanel", popover)  # i18n: ok
	theme.set_color("font_color", "TooltipLabel", TEXT)  # i18n: ok

	# A glass PANE of the chrome: the tint over the blurred map (frost.gd draws the blur
	# under it), a 1px light rim, R_PANE. With Glass off the tint is PANE_SOLID and the
	# frost is not drawn, so nothing reads the screen. The shadow is the SOLID pane's only:
	# a StyleBoxFlat draws its shadow under its whole body, so under glass it darkened the
	# blur inside the pane to about 0.36 instead of the 0.6 gain (#436 RECORD 4); the rim
	# and the blur lift a glass pane off the map without one.
	var pane := _flat(PANE_TINT if _glass else PANE_SOLID, R_PANE, [] if _glass else ELEV_PANE)
	pane.set_border_width_all(1)
	pane.border_color = PANE_RIM
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		pane.set_content_margin(side, PAD_PANE)
	# 3 above and below, as the flush strip had: the top strip's tiles fill its 84 px slot at
	# text 115 (test_top_bar_tiles); a pane whose content wants air adds its own margin inside.
	for side in [SIDE_TOP, SIDE_BOTTOM]:
		pane.set_content_margin(side, 3)
	_variation(theme, PANE, pane)


static func _variation(theme: Theme, name: String, box: StyleBox) -> void:
	theme.set_type_variation(name, "PanelContainer")
	theme.set_stylebox("panel", name, box)


## A borderless rounded surface, with a shadow when `elev` ([colour, offset, size]) is given.
static func _flat(bg: Color, radius: int, elev := []) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	if not elev.is_empty():
		box.shadow_color = elev[0]
		box.shadow_offset = elev[1]
		box.shadow_size = elev[2]
	return box


static func _labels(theme: Theme) -> void:
	for variation in [LEAD, TITLE, HEADING, MICRO, FIGURE, FIGURE_ALERT, HERO, FIGURE_LABEL, CAPTION, GOOD_TEXT, BAD_TEXT, WARN_TEXT, BAD_SMALL, GOOD_SMALL, MASTHEAD, HEADLINE, CHIP_TEXT]:
		theme.set_type_variation(variation, "Label")  # i18n: ok

	var bold := _face(WEIGHT_BOLD)
	var figures := _face(WEIGHT_BOLD, 0, true)
	var tracked := _face(WEIGHT_MEDIUM, 1)

	_label(theme, LEAD, SIZE_LEAD, TEXT, bold)
	_label(theme, TITLE, SIZE_TITLE, TEXT, bold)

	# Heading and Micro are the same idea at two weights of emphasis: a tracked
	# uppercase label naming a group. Micro is for chrome the player reads once
	# and then recognises by position (cluster names), Heading for sections
	# inside a panel they read every time.
	theme.set_font_size("font_size", HEADING, _px(SIZE_SMALL))
	theme.set_color("font_color", HEADING, TEXT)  # neutral: the accent is where-you-are, not a heading
	if tracked != null:
		theme.set_font("font", HEADING, tracked)

	_label(theme, MICRO, SIZE_MICRO, TEXT_DIM, tracked)

	# Figures carry the tabular-figures feature so a ticking number stops
	# shifting its own column every month -- unemployment going 7.33 -> 7.4 used
	# to move the decimal. (Archivo's default digits are proportional.)
	_label(theme, FIGURE, SIZE_FIGURE, TEXT, figures)

	# V4.8a. The strip's alert tone: the figure's own face and size, BAD's colour,
	# so a reading in trouble changes colour and nothing else -- a figure that
	# changed size when it went bad would shove its neighbours along the strip.
	_label(theme, FIGURE_ALERT, SIZE_FIGURE, BAD, figures)

	_label(theme, HERO, SIZE_HERO, TEXT, figures)

	_label(theme, FIGURE_LABEL, SIZE_SMALL, TEXT_DIM)

	_label(theme, CAPTION, SIZE_SMALL, TEXT_DIM)

	theme.set_color("font_color", GOOD_TEXT, GOOD)
	theme.set_color("font_color", BAD_TEXT, BAD)
	_label(theme, WARN_TEXT, SIZE_SMALL, WARN)
	_label(theme, BAD_SMALL, SIZE_SMALL, BAD)
	_label(theme, GOOD_SMALL, SIZE_SMALL, GOOD)
	_label(theme, CHIP_TEXT, SIZE_SMALL, TEXT)
	# G3 S1: a count waiting on the player (the sidebar's) is a SOLID amber pill, its figure bold
	# in the sheet's colour, 8.5:1 (the author's pick, "Ambre pleine", 2026-11-21: on amber at
	# 17 % the white figure left no amber in the pill at all, QA's RECORD on #436). The pill is
	# not a control, so the figure's colour is its own.
	theme.set_type_variation(COUNT_PILL, "Label")  # i18n: ok
	_label(theme, COUNT_PILL, SIZE_SMALL, SHEET, _face(WEIGHT_BOLD))
	var pill := _flat(WARN, 99)
	for side in [SIDE_LEFT, SIDE_RIGHT]:
		pill.set_content_margin(side, 6)
	theme.set_stylebox("normal", COUNT_PILL, pill)

	# V5.3-0 R15 (the closing gate: "les unes ne sont pas assez graphiques"): a
	# front page prints its paper's name in the black cut, tracked, and its
	# headline at the figure size in bold -- display type on the one surface that
	# is a newspaper, not a panel.
	var black := _face(WEIGHT_BLACK, 1)
	_label(theme, MASTHEAD, SIZE_LEAD, TEXT, black)
	_label(theme, HEADLINE, SIZE_FIGURE, TEXT, bold)


## One label variation: its size, its colour and, when the face loaded, its font.
static func _label(theme: Theme, variation: String, size: int, colour: Color, font: Font = null) -> void:
	theme.set_font_size("font_size", variation, _px(size))
	theme.set_color("font_color", variation, colour)
	if font != null:
		theme.set_font("font", variation, font)


static func _rich(theme: Theme) -> void:
	theme.set_color("default_color", "RichTextLabel", TEXT)  # i18n: ok
	# V5.1-d1c (G12, the author never saw a term): the dashes under a term, and a
	# name's underline, at the text's full opacity -- the engine draws them at half.
	theme.set_constant("underline_alpha", "RichTextLabel", 100)  # i18n: ok
	for variation in [RICH_CAPTION, RICH_GOOD, RICH_BAD]:
		theme.set_type_variation(variation, "RichTextLabel")  # i18n: ok
	theme.set_font_size("normal_font_size", RICH_CAPTION, _px(SIZE_SMALL))
	theme.set_color("default_color", RICH_CAPTION, TEXT_DIM)
	theme.set_color("default_color", RICH_GOOD, GOOD)
	theme.set_color("default_color", RICH_BAD, BAD)


static func _buttons(theme: Theme) -> void:
	# G3's button: a CONTROL surface, R_TILE, no border; the label TEXT at the bold cut on
	# every live state, because a status tone or the accent is never text on a control
	# (the accent as text drops to 3.8:1 on a hovered control). Disabled has no fill and
	# a LINE_STRONG outline: the fill is what reads "pressable" now, so an outline with
	# nothing in it is the inert look (the menu's disabled Continue, playtest 2026-09-05).
	var label := _face(WEIGHT_BOLD)
	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, _button_box(CONTROL))
		theme.set_stylebox("hover", type, _button_box(CONTROL_HOVER))
		# "pressed" is a button held down here: CONTROL_PRESSED, with the scale (Motion). A
		# toggle that is ON wears PICKED below (#436 RECORD: the fill flashed under every click).
		theme.set_stylebox("pressed", type, _button_box(CONTROL_PRESSED))
		theme.set_stylebox("hover_pressed", type, _button_box(CONTROL_PRESSED))
		theme.set_stylebox("focus", type, _ring())
		theme.set_stylebox("disabled", type, _button_box(Color(0, 0, 0, 0), LINE_STRONG))
		for state in ["font_hover_color", "font_focus_color"]:
			theme.set_color(state, type, TEXT)
		for state in ["font_pressed_color", "font_hover_pressed_color"]:
			theme.set_color(state, type, TEXT)
		theme.set_color("font_disabled_color", type, TEXT_OFF)
		if label != null:
			theme.set_font("font", type, label)

	# PICKED, a toggle that is ON -- a picked chip, the clock's running speed, the map layer
	# shown: the accent FILL, kept under the pointer (#436 pass 2: an ON toggle lost its mark on
	# hover, and a picked chip at CONTROL_PRESSED was 1.14:1 from an unpicked one -- invisible).
	theme.set_type_variation(PICKED, "Button")  # i18n: ok
	theme.set_stylebox("normal", PICKED, _button_box(CONTROL))
	theme.set_stylebox("hover", PICKED, _button_box(CONTROL_HOVER))
	theme.set_stylebox("pressed", PICKED, _button_box(accent_fill()))
	theme.set_stylebox("hover_pressed", PICKED, _button_box(accent_fill().darkened(0.06)))
	for state in ["font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, PICKED, on_accent_fill())

	# A cluster is an icon with a name under it, not a slab. Flat until it is the open
	# one, where the accent fills the bar under it -- "one accent says where you are".
	theme.set_type_variation(CLUSTER_BUTTON, "Button")  # i18n: ok
	theme.set_stylebox("normal", CLUSTER_BUTTON, _cluster_box(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", CLUSTER_BUTTON, _cluster_box(CONTROL))
	theme.set_stylebox("pressed", CLUSTER_BUTTON, _cluster_box(CONTROL, _accent))
	theme.set_stylebox("hover_pressed", CLUSTER_BUTTON, _cluster_box(CONTROL_HOVER, _accent))
	theme.set_stylebox("focus", CLUSTER_BUTTON, _ring())
	theme.set_color("font_color", CLUSTER_BUTTON, TEXT_DIM_CHROME)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		theme.set_color(state, CLUSTER_BUTTON, TEXT)

	theme.set_type_variation(SUBROW_BUTTON, "Button")  # i18n: ok
	theme.set_stylebox("normal", SUBROW_BUTTON, _button_box(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", SUBROW_BUTTON, _button_box(CONTROL))
	theme.set_stylebox("pressed", SUBROW_BUTTON, _button_box(CONTROL, _accent))
	theme.set_stylebox("hover_pressed", SUBROW_BUTTON, _button_box(CONTROL_HOVER, _accent))
	theme.set_stylebox("focus", SUBROW_BUTTON, _ring())
	theme.set_color("font_color", SUBROW_BUTTON, TEXT_DIM)
	theme.set_color("font_hover_color", SUBROW_BUTTON, TEXT)
	theme.set_color("font_pressed_color", SUBROW_BUTTON, TEXT)
	theme.set_color("font_hover_pressed_color", SUBROW_BUTTON, TEXT)
	# A refused answer on a card (a spent call, a Book with every day taken): the outline of
	# every disabled control and the text off, so it is not told from a live one by the hover
	# alone (QA's pre-gate B RECORD 8; pass 2: TEXT_OFF alone was 1.55:1 from TEXT_DIM).
	theme.set_stylebox("disabled", SUBROW_BUTTON, _button_box(Color(0, 0, 0, 0), LINE_STRONG))
	theme.set_color("font_disabled_color", SUBROW_BUTTON, TEXT_OFF)

	# A domain's row in the sidebar pane (G3 S1): no ground at rest, its name TEXT_DIM_CHROME on
	# the glass; the name brightens under the pointer; the open one sits on CONTROL with the
	# accent bar beside it (sidebar.gd draws the bar, outside the row, on the pane's padding).
	theme.set_type_variation(SIDEBAR_ROW, "Button")  # i18n: ok
	theme.set_stylebox("normal", SIDEBAR_ROW, _button_box(Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", SIDEBAR_ROW, _button_box(Color(0, 0, 0, 0)))
	theme.set_stylebox("pressed", SIDEBAR_ROW, _button_box(CONTROL))
	theme.set_stylebox("hover_pressed", SIDEBAR_ROW, _button_box(CONTROL_HOVER))
	theme.set_stylebox("focus", SIDEBAR_ROW, _ring())
	theme.set_color("font_color", SIDEBAR_ROW, TEXT_DIM_CHROME)
	for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		theme.set_color(state, SIDEBAR_ROW, TEXT)

	# The requests mark: something waits on the player, the one place WARN outlines a
	# control (the author: "clearly visible"). The words stay TEXT; the outline is the tone.
	theme.set_type_variation(REQUESTS_BUTTON, "Button")  # i18n: ok
	theme.set_stylebox("normal", REQUESTS_BUTTON, _button_box(CONTROL, WARN))
	theme.set_stylebox("hover", REQUESTS_BUTTON, _button_box(CONTROL_HOVER, WARN))
	theme.set_stylebox("pressed", REQUESTS_BUTTON, _button_box(CONTROL_PRESSED, WARN))
	theme.set_stylebox("focus", REQUESTS_BUTTON, _ring())

	# G1: the chief's mark is neither identity nor status -- a control's surface; its chip
	# carries the tone when a line is due now.
	theme.set_type_variation(CHIEF_MARK, "Button")  # i18n: ok
	theme.set_stylebox("normal", CHIEF_MARK, _button_box(CONTROL))
	theme.set_stylebox("hover", CHIEF_MARK, _button_box(CONTROL_HOVER))
	theme.set_stylebox("pressed", CHIEF_MARK, _button_box(CONTROL_PRESSED))
	theme.set_stylebox("focus", CHIEF_MARK, _ring())

	# V5.2 close R4: an option ON a verb, not a verb (option_check_style.gd says why).
	OptionCheckStyle.apply(theme, OPTION_CHECK, [_button_box(Color(0, 0, 0, 0)), _button_box(CONTROL),
		_ring()], _px(SIZE_SMALL), TEXT_DIM, TEXT, WARN)
	ControlStyle.apply(theme, {"primary": PRIMARY, "small": SMALL, "segment": SEGMENT, "chip": CHIP,
		"chip_good": CHIP_GOOD, "chip_warn": CHIP_WARN, "chip_bad": CHIP_BAD, "ghost": GHOST}, _button_box,
		{"control": CONTROL, "hover": CONTROL_HOVER, "pressed": CONTROL_PRESSED, "line": LINE_STRONG,
		"text": TEXT, "dim": TEXT_DIM, "off": TEXT_OFF, "good": GOOD, "warn": WARN, "bad": BAD,
		"fill": accent_fill(), "on_fill": on_accent_fill(), "ring": _ring()},
		_px(SIZE_SMALL), _face(WEIGHT_MEDIUM))


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


## Every slider (the budget's, the tax's, a fund's): G3's track is 4px of LINE_STRONG,
## round, and the part behind the grabber the accent FILL. The content margins are the
## bar's thickness, as for the scrollbars.
static func _sliders(theme: Theme) -> void:
	for part in [["slider", LINE_STRONG], ["grabber_area", accent_fill()], ["grabber_area_highlight", accent_fill()]]:
		var bar := StyleBoxFlat.new()
		bar.bg_color = part[1]
		bar.set_corner_radius_all(2)
		bar.content_margin_top = 2
		bar.content_margin_bottom = 2
		theme.set_stylebox(part[0], "HSlider", bar)


static func _button_box(bg: Color, border := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(R_TILE)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 5
	box.content_margin_bottom = 5
	if border.a > 0.0:
		box.set_border_width_all(1)
		box.border_color = border
	return box


## G3's one focus ring, everywhere: 2px of the accent, 2px outside the control, its
## radius plus 2. The only place the accent is an outline.
static func _ring() -> StyleBoxFlat:
	var ring := StyleBoxFlat.new()
	ring.draw_center = false
	ring.set_border_width_all(2)
	ring.border_color = _accent
	ring.set_corner_radius_all(R_TILE + 2)
	ring.set_expand_margin_all(2)
	return ring


## A cluster's selected state is a bar of the accent along the *bottom*, on the
## screen edge the control is anchored to (U2's rail button put its bar on the left
## for the same reason).
static func _cluster_box(bg: Color, marker := Color(0, 0, 0, 0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(R_TILE)
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 6
	box.content_margin_bottom = 6
	if marker.a > 0.0:
		box.border_width_bottom = 2
		box.border_color = marker
	return box
