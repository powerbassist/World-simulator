extends SceneTree

## Headless test: godot --headless --script res://tests/test_ui_theme.gd
## Non-zero exit on any failure.
##
## U3's theme test. Checks the done-when line "panel styling comes from one
## theme, not from per-panel overrides" directly and in both directions: the
## theme carries the styles, and the three places that used to build a
## StyleBoxFlat by hand no longer override anything.
##
## Both scenes are instantiated, because a Theme propagates down a tree and not
## across a scene change -- menu.tscn carries its own assignment and a test that
## only looked at main.tscn would not notice if that one were dropped.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const AccentRule = preload("res://src/ui/accent_rule.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

var _failures: Array[String] = []
var _main
var _menu
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)
	_menu = load("res://src/ui/menu.tscn").instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let both scenes' _ready() run

	_check_player_accent_wired()
	_check_theme_contents()
	_check_scenes_carry_it()
	_check_no_panel_overrides()
	_check_glass_off()
	_check_text_scale()
	_check_type_steps()
	_finish()
	return false


## V5.1-d2, G11 (the play gate's "text proportions odd"; author: "Oui, dans d"):
## the scale ran 11/12/15/18/20/30 -- two steps a reader cannot tell apart (11/12,
## 18/20) and two that jump (12 to 15, 20 to 30). Each step now differs from the
## last by a ratio a reader sees and none leaps; the body stays at 15.
func _check_type_steps() -> void:
	var steps := [UiTheme.SIZE_MICRO, UiTheme.SIZE_SMALL, UiTheme.SIZE_BASE, UiTheme.SIZE_LEAD,
		UiTheme.SIZE_FIGURE, UiTheme.SIZE_HERO]
	if UiTheme.SIZE_BASE != 15:
		_fail("the body moved off 15: %d" % UiTheme.SIZE_BASE)
	for i in range(1, steps.size()):
		var ratio := float(steps[i]) / float(steps[i - 1])
		if ratio < 1.13 or ratio > 1.3:
			_fail("the type step %d -> %d is %.2f, outside 1.13-1.30" % [steps[i - 1], steps[i], ratio])


## V5.1-c2.4. The text-size option scales the whole type scale -- every size the
## theme sets, at once -- and nothing else: a plate's margins are layout, and a
## larger text must not quietly re-lay the shell.
func _check_text_scale() -> void:
	UiTheme.set_text_scale(1.15)
	var big: Theme = UiTheme.build()
	UiTheme.set_text_scale(1.0)
	var base: Theme = UiTheme.build()
	if big.default_font_size != roundi(base.default_font_size * 1.15):
		_fail("at 115 %% the body is %d px, not %d" % [big.default_font_size, roundi(base.default_font_size * 1.15)])
	for type in [UiTheme.MICRO, UiTheme.HEADING, UiTheme.FIGURE, UiTheme.HERO, UiTheme.CAPTION, UiTheme.LEAD]:
		var want := roundi(base.get_font_size("font_size", type) * 1.15)
		if big.get_font_size("font_size", type) != want:
			_fail("at 115 %% '%s' is %d px, not %d" % [type, big.get_font_size("font_size", type), want])
	var plate_big: StyleBox = big.get_stylebox("panel", UiTheme.PLATE)
	var plate_base: StyleBox = base.get_stylebox("panel", UiTheme.PLATE)
	if plate_big.get_minimum_size() != plate_base.get_minimum_size():
		_fail("the text size moved a plate's margins: %s at 115 %%, %s at 100 %%" % [plate_big.get_minimum_size(), plate_base.get_minimum_size()])


func _check_theme_contents() -> void:
	var theme := UiTheme.build()

	if not theme.has_stylebox("panel", "PanelContainer"):
		_fail("theme has no PanelContainer panel stylebox")
	else:
		var box := theme.get_stylebox("panel", "PanelContainer")
		# The whole reason the old overrides existed: the engine default is
		# translucent, so a modal panel reads through a screen full of figures.
		if box is StyleBoxFlat and box.bg_color.a < 1.0:
			_fail("the PanelContainer style is translucent (alpha %.2f)" % box.bg_color.a)

	for variation in [UiTheme.TOP_BAR_PANEL, UiTheme.PLATE, UiTheme.TITLE_BAR, UiTheme.PANE, UiTheme.TILE_PANEL, UiTheme.POPOVER_PANEL]:
		if not theme.has_stylebox("panel", variation):
			_fail("theme has no %s variation stylebox" % variation)
		if theme.get_type_variation_base(variation) != &"PanelContainer":
			_fail("'%s' is not registered as a PanelContainer variation" % variation)

	var label_variations := [
		UiTheme.LEAD, UiTheme.HEADING, UiTheme.MICRO, UiTheme.FIGURE, UiTheme.HERO,
		UiTheme.FIGURE_LABEL, UiTheme.CAPTION, UiTheme.GOOD_TEXT, UiTheme.BAD_TEXT,
	]
	for variation in label_variations:
		if theme.get_type_variation_base(variation) != &"Label":
			_fail("'%s' is not registered as a Label variation" % variation)

	var button_variations := [
		UiTheme.CLUSTER_BUTTON, UiTheme.SUBROW_BUTTON, UiTheme.REQUESTS_BUTTON,
	]
	for variation in button_variations:
		if theme.get_type_variation_base(variation) != &"Button":
			_fail("'%s' is not registered as a Button variation" % variation)

	# Good and bad have to be distinguishable, or every signed delta in the game
	# reads the same.
	if theme.get_color("font_color", UiTheme.GOOD_TEXT) == theme.get_color("font_color", UiTheme.BAD_TEXT):
		_fail("the good and bad text colours are identical")

	# A ghost is a quiet action: no fill until the pointer is on it (else it is a button).
	if (theme.get_stylebox("normal", UiTheme.GHOST) as StyleBoxFlat).bg_color.a > 0.0 or (theme.get_stylebox("hover", UiTheme.GHOST) as StyleBoxFlat).bg_color.a <= 0.0:
		_fail("the ghost is filled at rest or empty on hover")

	# The status tones are read as text on a tile (a delta, a date): G3 lifted BAD for it.
	for tone in [UiTheme.GOOD, UiTheme.BAD, UiTheme.WARN]:
		if AccentRule.contrast(tone, UiTheme.TILE) < AccentRule.MIN_CONTRAST:
			_fail("the tone %s is %.2f:1 on a tile, under AA" % [tone.to_html(false), AccentRule.contrast(tone, UiTheme.TILE)])

	# A disabled button must not look live (the menu's Continue read enabled with no
	# saves, playtest 2026-09-05). G3's live look is the fill, so disabled has none.
	for type in ["Button", "OptionButton", UiTheme.PRIMARY]:
		var disabled_box := theme.get_stylebox("disabled", type) as StyleBoxFlat
		if disabled_box != null and disabled_box.bg_color.a > 0.0:
			_fail("the disabled %s keeps a fill, so it reads live" % type)

	_check_grammar(theme)
	_check_pressed_text_contrast(theme)
	_check_fonts(theme)


## main.gd re-applies the theme once the played nation is known (and again on a
## load): the scene boots with the fallback, so a wiring that is missing leaves
## every nation looking like the menu, and nothing else would say so.
func _check_player_accent_wired() -> void:
	var player_id: String = _main._state.player_nation_id
	var expected := UiTheme.accent_for(_main._loader.nations[player_id].flag_bands)
	var folded := _main.theme.get_stylebox("panel", UiTheme.PLATE_FOLDED) as StyleBoxFlat
	if folded.border_color != expected:
		_fail("main's theme carries %s, not %s -- the played nation's accent" % [folded.border_color.to_html(false), expected.to_html(false)])
	if expected == UiTheme.ACCENT_FALLBACK:
		_fail("France resolves to the fallback accent; the wiring check proves nothing")

	# The accent is a static: a game's nation must not outlive it. The menu scene
	# was built AFTER main in _init(), so if it resets the slot, a player who plays
	# France and returns to the menu sees the fallback, not France's blue.
	if UiTheme.accent() != UiTheme.ACCENT_FALLBACK:
		_fail("the menu left the previous game's accent in force (%s)" % UiTheme.accent().to_html(false))
	if _menu.theme.get_stylebox("panel", UiTheme.PLATE_FOLDED).border_color != UiTheme.ACCENT_FALLBACK:
		_fail("the menu's own theme does not carry the fallback accent")


## G3's grammar, replacing BUREAU's hairline on four sides (the author picked "Sheets on
## glass", 2026-11-21). A SHEET is opaque, borderless and R_SHEET, and never wears the
## accent; a PANE of the chrome is the tint with a light rim and R_PANE; with Glass off the
## pane is PANE_SOLID. The test is the mirror of BUREAU's: where that one failed a plate
## missing an edge, this fails a sheet that draws one.
func _check_grammar(theme: Theme) -> void:
	var plate := theme.get_stylebox("panel", UiTheme.PLATE) as StyleBoxFlat
	if plate == null:
		_fail("the sheet style is not a StyleBoxFlat")
		return
	for side in ["top", "bottom", "left", "right"]:
		if plate.get("border_width_" + side) > 0:
			_fail("the sheet draws a border on its %s edge; G3 separates by surface, not by line" % side)
	if plate.bg_color.a < 1.0:
		_fail("the sheet is translucent (alpha %.2f): text on a sheet must not depend on the map" % plate.bg_color.a)
	if plate.bg_color != UiTheme.SHEET or plate.corner_radius_top_left != UiTheme.R_SHEET:
		_fail("the sheet is not SHEET at R_SHEET")
	if plate.shadow_size <= 0:
		_fail("the sheet has no shadow to lift it off the map")

	var pane := theme.get_stylebox("panel", UiTheme.PANE) as StyleBoxFlat
	if pane == null or pane.border_color != UiTheme.PANE_RIM or pane.border_width_left < 1 or pane.corner_radius_top_left != UiTheme.R_PANE:
		_fail("the pane lost its rim or its R_PANE corners")
	elif pane.bg_color != (UiTheme.PANE_TINT if UiTheme.glass() else UiTheme.PANE_SOLID):
		_fail("the pane's ground is %s, not the tint Glass asks for" % pane.bg_color)
	var popover := theme.get_stylebox("panel", UiTheme.POPOVER_PANEL) as StyleBoxFlat
	if popover == null or popover.bg_color.a < 1.0:
		_fail("a popover is not opaque: it would need a second copy of the screen")

	# Headings (every section label, window title and card title) are neutral: the
	# accent is reserved for "you are here", not "this is a heading".
	if theme.get_color("font_color", UiTheme.HEADING) == UiTheme.accent():
		_fail("headings wear the accent, which is reserved for where-you-are marks")

	# The folded sheet and a cluster's open marker are the accent's two jobs in the
	# chrome. An accent that is not the one in force means a nation's colour never
	# reached the theme.
	var folded := theme.get_stylebox("panel", UiTheme.PLATE_FOLDED) as StyleBoxFlat
	if folded == null or folded.border_width_bottom < 2 or folded.border_color != UiTheme.accent():
		_fail("the folded plate is not outlined in the accent with a 2px bottom edge")
	var open := theme.get_stylebox("pressed", UiTheme.CLUSTER_BUTTON) as StyleBoxFlat
	if open == null or open.border_width_bottom < 2 or open.border_color != UiTheme.accent():
		_fail("the open cluster does not carry the accent bar")

	# Without a nation (the menu), the accent is the named fallback, not a flag.
	var host := Control.new()
	UiTheme.apply(host)
	if UiTheme.accent() != UiTheme.ACCENT_FALLBACK:
		_fail("the accent in force with no nation chosen is not the fallback")

	# A given accent reaches a freshly built theme: set one, rebuild, read.
	UiTheme.apply(host, Color("#E3A63A"))
	var tinted := host.theme.get_stylebox("panel", UiTheme.PLATE_FOLDED) as StyleBoxFlat
	if tinted.border_color != Color("#E3A63A"):
		_fail("apply(root, accent) did not carry the accent into the theme")
	UiTheme.apply(host)
	host.free()


## G3 (Glass off): every pane is PANE_SOLID and nothing reads the screen -- the frost under
## a pane hides, which is the only node that samples it. Mutation: a frost that ignores
## glass() stays visible and fails here; a pane built from the tint fails the colour.
func _check_glass_off() -> void:
	var holder := Control.new()
	root.add_child(holder)
	UiTheme.apply(holder)
	var pane := PanelKit.pane(PanelContainer.new())
	holder.add_child(pane)
	var frost := pane.get_child(0) as CanvasItem
	if frost == null or not frost.visible:
		_fail("with Glass on, a pane has no visible frost under it")
	UiTheme.set_glass(false)
	UiTheme.rebuild(holder)
	var solid := pane.get_theme_stylebox("panel") as StyleBoxFlat
	if solid.bg_color != UiTheme.PANE_SOLID:
		_fail("with Glass off the pane is %s, not PANE_SOLID" % solid.bg_color)
	if frost != null and frost.visible:
		_fail("with Glass off the frost still draws, so the screen is still read")
	UiTheme.set_glass(true)
	UiTheme.apply(holder)
	holder.queue_free()


## No text on a control is a status tone or the accent (the accent drops to 3.8:1 on a
## hovered control): every live state of a button holds AA with its label, and the screen's
## one action, filled with the accent, holds it with its own label.
func _check_pressed_text_contrast(theme: Theme) -> void:
	var states := {"normal": "font_color", "hover": "font_hover_color", "pressed": "font_pressed_color"}
	for type in ["Button", "OptionButton", UiTheme.CLUSTER_BUTTON, UiTheme.SUBROW_BUTTON, UiTheme.PRIMARY, UiTheme.SMALL, UiTheme.SEGMENT, UiTheme.GHOST]:
		for state in states:
			var box := theme.get_stylebox(state, type) as StyleBoxFlat
			if box == null:
				_fail("%s has no %s stylebox" % [type, state])
				continue
			# A transparent state sits on the sheet: judge it there.
			var ground := box.bg_color if box.bg_color.a > 0.0 else UiTheme.SHEET
			# A variation that does not set a colour takes its base type's, as a control does.
			var text := theme.get_color(states[state], type if theme.has_color(states[state], type) else theme.get_type_variation_base(type))
			var ratio := AccentRule.contrast(text, ground)
			if ratio < AccentRule.MIN_CONTRAST:
				_fail("%s %s text %s on %s is %.2f:1, under AA" % [type, state, text.to_html(false), ground.to_html(false), ratio])


## The fonts are the one part of the theme that fails *silently*: a missing
## .ttf makes _font() return null, the theme sets nothing, and the game renders
## in the engine's built-in sans looking merely plain rather than broken. This
## is the "new UI behaviour that can fail silently needs a test" rule in
## AGENTS.md, and it is why the check is on the loaded Font object rather than
## on the file existing. Archivo's axes and the figures' tabular feature fail
## the same way (a string key where a tag is wanted is accepted and does
## nothing), so they are checked as values too.
func _check_fonts(theme: Theme) -> void:
	if theme.default_font == null:
		_fail("no default font -- assets/fonts is missing or failed to load")
		return

	var figures := theme.get_font("font", UiTheme.FIGURE)
	if not figures is FontVariation:
		_fail("figures have no Archivo cut, so ticking numbers will jitter")
		return
	var base := (figures as FontVariation).base_font as FontFile
	if base == null or not base.get_font_name().begins_with("Archivo"):
		_fail("the figure face is not Archivo")
		return
	# The variable file, not a static instance of it: two axes, wght and wdth.
	if base.get_supported_variation_list().size() < 2:
		_fail("the loaded Archivo has no variation axes -- the static file, not the variable one")

	var ts := TextServerManager.get_primary_interface()
	var tnum := ts.name_to_tag("tnum")
	if not (figures as FontVariation).opentype_features.has(tnum):
		_fail("figures do not carry the tabular-figures feature")
	# And it is the VALUE that matters: tabular digits are all one width.
	var one := figures.get_string_size("1111", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var zero := figures.get_string_size("0000", HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	if not is_equal_approx(one, zero):
		_fail("tabular figures differ in width (1111 is %.0f, 0000 is %.0f)" % [one, zero])

	if theme.get_font("font", UiTheme.HEADING) == null:
		_fail("headings have no tracked font")


func _check_scenes_carry_it() -> void:
	if _main.theme == null:
		_fail("main.tscn's root has no theme")
	if _menu.theme == null:
		_fail("menu.tscn's root has no theme")

	# Propagation is the point: a docked tab never touches the theme itself.
	var overview = _main._overview_panel
	if overview != null and overview.get_theme_stylebox("panel") == null:
		_fail("a docked panel resolves no panel stylebox, so the theme is not reaching it")


## The three sites U3 removed, plus the panels they styled. An override here is
## a regression to per-panel styling even if the screen still looks right.
func _check_no_panel_overrides() -> void:
	var named := {
		"top bar": _main._top_bar,
		"election panel": _main._election_panel,
		"save/load panel": _main._save_load_panel,
		"settings panel": _main._settings_panel,
		"pause menu": _main._pause_menu,
		"menu load panel": _menu._load_panel,
		"menu settings panel": _menu._settings_panel,
		"menu credits panel": _menu._credits_panel,
	}
	for name in named:
		var panel = named[name]
		if panel == null:
			_fail("%s was not built" % name)
			continue
		if panel.has_theme_stylebox_override("panel"):
			_fail("%s still carries a per-panel 'panel' stylebox override" % name)


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_ui_theme: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
