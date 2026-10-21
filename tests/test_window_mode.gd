extends SceneTree

## Headless test: godot --headless --script res://tests/test_window_mode.gd
## Non-zero exit on any failure.
##
## V5.1-0c. The author's "window size change dont work": the game booted
## fullscreen with no key out, and a windowed drag snapped back on every return to
## the menu. The pure rules (WindowMode.plan), the root window they configure and
## the F11 key are pinned here; the OS window itself is not reachable headless, so
## the windowed frames in the PR carry the visual half.

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

	SettingsPanel.toggle_fullscreen(root)
	var after := ConfigFile.new()
	after.load(SettingsPanel.CONFIG_PATH)
	if bool(after.get_value("display", "fullscreen", SettingsPanel.DEFAULT_FULLSCREEN)) == was:
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
