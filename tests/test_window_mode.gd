extends SceneTree

## Headless test: godot --headless --script res://tests/test_window_mode.gd
## Non-zero exit on any failure.
##
## V5.1-0c. The author's "window size change dont work": the game booted
## fullscreen with no key out, and a windowed drag snapped back on every return to
## the menu. The pure rules (WindowMode.plan), the root window they configure and
## the F11 key are pinned here; the OS window itself is not reachable headless, so
## the windowed frames in the PR carry the visual half.

## suite-exclusive: backs up and restores user://settings.cfg -- the key and Settings checks write the display keys

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const WindowMode = preload("res://src/ui/window_mode.gd")

var _failures: Array[String] = []
var _calls := 0
var _frame := 0


func _process(_delta: float) -> bool:
	# One frame in: the root window is inside the tree, as it is when the menu's
	# _ready() calls apply_saved(), so the key node has a viewport to handle on.
	_frame += 1
	if _frame < 2:
		return false
	_check_plan()
	_check_root_window_is_resizable_with_a_floor()
	_check_key_toggles_and_persists()
	_check_f11_flips_the_window_not_the_file()
	_check_settings_rows_do_not_fight_the_window()
	_finish()
	return false


func _check_plan() -> void:
	# The first apply of a process takes the preset: nothing has been dragged yet.
	var first := WindowMode.plan(false, false)
	if not bool(first["set_size"]):
		_fail("the first windowed apply of a process does not set the preset size")
	WindowMode.note_applied()

	# Windowed -> windowed (a return through the menu): the dragged size stays.
	if bool(WindowMode.plan(false, false)["set_size"]):
		_fail("a windowed window is resized back to the preset on re-apply -- a drag cannot survive the menu")
	# Out of fullscreen the window has the display's size, so the preset is wanted.
	if not bool(WindowMode.plan(false, true)["set_size"]):
		_fail("leaving fullscreen does not restore the preset size")
	# A size chosen on the Settings screen is an explicit request.
	if not bool(WindowMode.plan(false, false, true)["set_size"]):
		_fail("a resolution picked on the Settings screen is ignored while windowed")
	# Fullscreen has no size of its own to set.
	if bool(WindowMode.plan(true, false, true)["set_size"]):
		_fail("fullscreen asks for a window size")

	for fullscreen in [true, false]:
		var plan := WindowMode.plan(fullscreen, false)
		if not bool(plan["resizable"]):
			_fail("fullscreen=%s plan is not resizable" % fullscreen)
		var floor_size: Vector2i = plan["min_size"]
		if floor_size.x < 640 or floor_size.y < 360 or floor_size.x > 1280 or floor_size.y > 720:
			_fail("the window floor %s is outside what the layout survives and what a preset allows" % floor_size)


func _check_root_window_is_resizable_with_a_floor() -> void:
	root.unresizable = true  # the state a bad config could have left
	root.min_size = Vector2i.ZERO
	SettingsPanel.apply_saved(root)
	if root.unresizable:
		_fail("apply_saved left the root window unresizable")
	if root.min_size != WindowMode.MIN_SIZE:
		_fail("apply_saved left min_size %s, want %s" % [root.min_size, WindowMode.MIN_SIZE])
	if root.get_node_or_null(WindowMode.NODE_NAME) == null:
		_fail("apply_saved installed no F11 key node on the root window")
	SettingsPanel.apply_saved(root)
	var keys := 0
	for child in root.get_children():
		if child.name == WindowMode.NODE_NAME:
			keys += 1
	if keys != 1:
		_fail("%d F11 key nodes after two apply_saved calls, want one" % keys)


func _check_key_toggles_and_persists() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	var had := cfg.has_section_key("display", "fullscreen")
	var was := bool(cfg.get_value("display", "fullscreen", SettingsPanel.DEFAULT_FULLSCREEN))

	var node = root.get_node(WindowMode.NODE_NAME)
	node._on_toggle = func(_w): _calls += 1  # observe the key alone first
	node._unhandled_input(_key(KEY_F11, true, false))
	if _calls != 1:
		_fail("F11 pressed called the toggle %d times, want 1" % _calls)
	node._unhandled_input(_key(KEY_F11, false, false))
	node._unhandled_input(_key(KEY_F11, true, true))
	node._unhandled_input(_key(KEY_F10, true, false))
	if _calls != 1:
		_fail("a release, an echo or another key toggled the window (%d calls)" % _calls)

	var was_fullscreen := root.mode == Window.MODE_FULLSCREEN
	SettingsPanel.toggle_fullscreen(root)
	var after := ConfigFile.new()
	after.load(SettingsPanel.CONFIG_PATH)
	# F11 flips what the window is (review pass 2), and writes the result.
	if bool(after.get_value("display", "fullscreen", SettingsPanel.DEFAULT_FULLSCREEN)) == was_fullscreen:
		_fail("toggle_fullscreen did not persist the flip -- the Settings row would disagree with the screen")
	if root.unresizable or root.min_size != WindowMode.MIN_SIZE:
		_fail("toggling fullscreen left the window unresizable or without its floor")

	# Put the user's file back as it was.
	var restore := ConfigFile.new()
	restore.load(SettingsPanel.CONFIG_PATH)
	if had:
		restore.set_value("display", "fullscreen", was)
	else:
		restore.erase_section_key("display", "fullscreen")
	restore.save(SettingsPanel.CONFIG_PATH)


## Review pass 2. F11 negated the FILE's value; when the file and the window
## disagree (a file edited by hand, a mode changed another way) the first press
## changed nothing visible. It flips what the window is.
func _check_f11_flips_the_window_not_the_file() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	var had := cfg.has_section_key("display", "fullscreen")
	var was: Variant = cfg.get_value("display", "fullscreen") if had else null
	cfg.set_value("display", "fullscreen", false)  # the file says windowed...
	cfg.save(SettingsPanel.CONFIG_PATH)
	# A child Window: the headless root has no OS window to take a mode.
	var window := Window.new()
	root.add_child(window)
	window.mode = Window.MODE_FULLSCREEN             # ...the window is fullscreen
	if window.mode != Window.MODE_FULLSCREEN:
		_fail("the fixture cannot put a window in fullscreen headless -- the next check proves nothing")
	SettingsPanel.toggle_fullscreen(window)
	if window.mode == Window.MODE_FULLSCREEN:
		_fail("F11 on a fullscreen window left it fullscreen because the file said windowed")
	window.queue_free()
	var after := ConfigFile.new()
	after.load(SettingsPanel.CONFIG_PATH)
	if bool(after.get_value("display", "fullscreen", true)):
		_fail("F11 wrote fullscreen=true after leaving fullscreen")
	var restore := ConfigFile.new()
	restore.load(SettingsPanel.CONFIG_PATH)
	if had:
		restore.set_value("display", "fullscreen", was)
	else:
		restore.erase_section_key("display", "fullscreen")
	restore.save(SettingsPanel.CONFIG_PATH)


## Review pass 1. Two ways the Settings screen could undo the player's window:
## every row's change re-applied the preset size (toggling Sound snapped a dragged
## window back), and the panel read the file only when built, so after F11 its
## Window row was stale and the next change put the old mode back.
func _check_settings_rows_do_not_fight_the_window() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	var had_fs := cfg.has_section_key("display", "fullscreen")
	var was_fs: Variant = cfg.get_value("display", "fullscreen") if had_fs else null
	var had_res := cfg.has_section_key("display", "resolution_index")
	var was_res: Variant = cfg.get_value("display", "resolution_index") if had_res else null
	cfg.set_value("display", "fullscreen", false)
	cfg.set_value("display", "resolution_index", 2)
	cfg.save(SettingsPanel.CONFIG_PATH)

	var panel := SettingsPanel.new()
	root.add_child(panel)
	var dragged := Vector2i(1500, 820)
	root.size = dragged
	if root.size != dragged:
		_fail("the fixture cannot set the root window's size headless -- the next checks prove nothing")

	panel._sound_button.select(0)
	panel._save_and_apply()
	if root.size != dragged:
		_fail("changing Sound reset a dragged window from %s to %s" % [dragged, root.size])
	panel._resolution_button.select(0)
	panel._save_and_apply()
	if root.size != SettingsPanel.RESOLUTIONS[0]:
		_fail("picking a resolution left the window at %s, want %s" % [root.size, SettingsPanel.RESOLUTIONS[0]])

	# F11 behind the panel's back, then the panel is shown again.
	panel.hide()
	var f11 := ConfigFile.new()
	f11.load(SettingsPanel.CONFIG_PATH)
	f11.set_value("display", "fullscreen", true)
	f11.save(SettingsPanel.CONFIG_PATH)
	panel.show()
	if panel._fullscreen_button.selected != 1:
		_fail("the Settings Window row still reads Windowed after F11 went fullscreen -- the next change would revert it")
	panel.queue_free()

	var restore := ConfigFile.new()
	restore.load(SettingsPanel.CONFIG_PATH)
	for pair in [["fullscreen", had_fs, was_fs], ["resolution_index", had_res, was_res]]:
		if bool(pair[1]):
			restore.set_value("display", String(pair[0]), pair[2])
		else:
			restore.erase_section_key("display", String(pair[0]))
	restore.save(SettingsPanel.CONFIG_PATH)


func _key(keycode: Key, pressed: bool, echo: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = pressed
	event.echo = echo
	return event


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_window_mode: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
