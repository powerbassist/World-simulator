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

	_check_theme_contents()
	_check_scenes_carry_it()
	_check_no_panel_overrides()
	_finish()
	return false


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

	if not theme.has_stylebox("panel", UiTheme.TOP_BAR_PANEL):
		_fail("theme has no %s variation stylebox" % UiTheme.TOP_BAR_PANEL)

	var label_variations := [
		UiTheme.LEAD, UiTheme.HEADING, UiTheme.FIGURE,
		UiTheme.FIGURE_LABEL, UiTheme.CAPTION, UiTheme.GOOD_TEXT, UiTheme.BAD_TEXT,
	]
	for variation in label_variations:
		if theme.get_type_variation_base(variation) != &"Label":
			_fail("'%s' is not registered as a Label variation" % variation)

	if theme.get_type_variation_base(UiTheme.RAIL_BUTTON) != &"Button":
		_fail("'%s' is not registered as a Button variation" % UiTheme.RAIL_BUTTON)

	# Good and bad have to be distinguishable, or every signed delta in the game
	# reads the same.
	if theme.get_color("font_color", UiTheme.GOOD_TEXT) == theme.get_color("font_color", UiTheme.BAD_TEXT):
		_fail("the good and bad text colours are identical")


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
