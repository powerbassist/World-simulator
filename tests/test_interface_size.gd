extends SceneTree

## Headless test: godot --headless --script res://tests/test_interface_size.gd
## Non-zero exit on any failure.
##
## V5.3, the author's "je veux jouer en 2k": the Interface size setting. The project
## stretches a 1920x1080 canvas (canvas_items, expand), so a 2560x1440 screen used to
## show the 1080p layout x1.33 -- bigger, not more room. Auto (the default) sets the
## root window's content_scale_factor to undo that stretch, clamped to [0.75, 1.0]:
## UI pixels keep their 1080p physical size and the logical canvas grows. The manual
## steps are the factor itself. Pinned here: the rule (a pure function, so no display
## is needed), the file key and its default for an old settings.cfg, the row, the
## listener that keeps Auto following the window, and the Regions tab's map frame,
## which used to bake in the 1080 height.

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const InterfaceSize = preload("res://src/ui/interface_size.gd")
const RegionsShell = preload("res://src/ui/regions_shell.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const MapRegions = preload("res://src/ui/map_regions.gd")

var _failures: Array[String] = []
var _panel: PanelContainer
var _frame := 0
## The developer's settings file as this run found it, put back at the end (a hand
## run without isolation shares the real user dir).
var _original := ""
var _had_file := false


func _init() -> void:
	_had_file = FileAccess.file_exists(SettingsPanel.CONFIG_PATH)
	if _had_file:
		_original = FileAccess.get_file_as_string(SettingsPanel.CONFIG_PATH)
	DirAccess.remove_absolute(SettingsPanel.CONFIG_PATH)
	_check_rule()
	_check_old_config()
	_check_regions_frame()
	_panel = SettingsPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_check_row()
		_check_listener()
		_restore()
		_finish()
		quit(1 if not _failures.is_empty() else 0)
	return false


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _expect(label: String, actual: float, expected: float) -> void:
	if not is_equal_approx(actual, expected):
		_fail("%s: expected %s, got %s" % [label, expected, actual])


## Auto undoes the canvas_items/expand stretch, min(w/1920, h/1080), clamped.
## The stretch form rather than 1080/height: a 1920x1200 or a drag-resized 1600x1200
## window is stretched by its WIDTH, and 1080/height would shrink its UI below 1080p.
func _check_rule() -> void:
	var auto := InterfaceSize.AUTO_INDEX
	_expect("Auto at 1920x1080 (today, unchanged)", InterfaceSize.factor(auto, Vector2i(1920, 1080)), 1.0)
	_expect("Auto at 2560x1440 (1080p pixel size)", InterfaceSize.factor(auto, Vector2i(2560, 1440)), 0.75)
	_expect("Auto at 3440x1440 (ultrawide)", InterfaceSize.factor(auto, Vector2i(3440, 1440)), 0.75)
	_expect("Auto at 3840x2160 (clamped at 0.75)", InterfaceSize.factor(auto, Vector2i(3840, 2160)), 0.75)
	_expect("Auto at 1280x720 (never above 1.0)", InterfaceSize.factor(auto, Vector2i(1280, 720)), 1.0)
	_expect("Auto at 1920x1200 (stretched by width)", InterfaceSize.factor(auto, Vector2i(1920, 1200)), 1.0)
	_expect("Auto at 1920x1920 (headless)", InterfaceSize.factor(auto, Vector2i(1920, 1920)), 1.0)
	_expect("Auto at 2240x1260", InterfaceSize.factor(auto, Vector2i(2240, 1260)), 1080.0 / 1260.0)
	_expect("Auto with no size yet", InterfaceSize.factor(auto, Vector2i.ZERO), 1.0)
	# The manual steps are the factor, whatever the window.
	var steps := {1: 1.0, 2: 0.9, 3: 0.8, 4: 0.75}
	for index in steps.keys():
		for size in [Vector2i(1920, 1080), Vector2i(2560, 1440)]:
			_expect("step %d at %s" % [index, size], InterfaceSize.factor(index, size), steps[index])
	# Out of range reads as Auto, not as a crash or a 0 factor.
	_expect("index 99 reads as Auto", InterfaceSize.factor(99, Vector2i(2560, 1440)), 0.75)
	_expect("index -1 reads as Auto", InterfaceSize.factor(-1, Vector2i(2560, 1440)), 0.75)
	# Never above 1.0: the retired content_scale_factor crushed the map above 100 %.
	for scale in InterfaceSize.SIZES:
		if scale > 1.0:
			_fail("an interface size above 100 %% is offered (%s): it crushes the map" % scale)


## A settings.cfg written before this row has no key: it reads Auto. The retired
## ui_scale_index (85-130 %) is not read as this row.
func _check_old_config() -> void:
	if InterfaceSize.CONFIG_PATH != SettingsPanel.CONFIG_PATH:
		_fail("interface_size.gd reads %s, the Settings screen writes %s" % [InterfaceSize.CONFIG_PATH, SettingsPanel.CONFIG_PATH])
	var cfg := ConfigFile.new()
	cfg.set_value("display", "ui_scale_index", 4)
	cfg.set_value("display", "text_scale_index", 2)
	cfg.save(SettingsPanel.CONFIG_PATH)
	if InterfaceSize.index() != InterfaceSize.AUTO_INDEX:
		_fail("an old settings.cfg (no interface_size_index) should read Auto, got %d" % InterfaceSize.index())
	if InterfaceSize.DEFAULT_INDEX != InterfaceSize.AUTO_INDEX:
		_fail("the default interface size should be Auto")
	DirAccess.remove_absolute(SettingsPanel.CONFIG_PATH)


## The Regions tab frames the nation between its narrow dock and the inbox strip.
## At the 1920x1080 canvas the rect is the one it always was; on a bigger canvas it
## follows the canvas instead of stopping at 1080.
func _check_regions_frame() -> void:
	var w = WindowManager
	var old := Rect2(w.DOCK_LEFT + float(w.DOCK_WIDTHS["region"]), w.DOCK_TOP,
		w.DOCK_WIDTH - float(w.DOCK_WIDTHS["region"]), 1080.0 - w.DOCK_TOP - w.DOCK_BOTTOM)
	var at_1080: Rect2 = RegionsShell.fit_rect_for(Vector2(1920, 1080))
	if not at_1080.is_equal_approx(old):
		_fail("the Regions frame moved at 1920x1080: %s, was %s" % [at_1080, old])
	var at_1440: Rect2 = RegionsShell.fit_rect_for(Vector2(2560, 1440))
	if not is_equal_approx(at_1440.end.y, 1440.0 - w.DOCK_BOTTOM):
		_fail("the Regions frame stops at %s on a 1440-tall canvas" % at_1440.end.y)
	if not is_equal_approx(2560.0 - at_1440.end.x, 1920.0 - old.end.x):
		_fail("the Regions frame should keep the inbox strip at the right edge: ends at %s" % at_1440.end.x)
	if not is_equal_approx(at_1440.position.x, old.position.x):
		_fail("the Regions frame should start at the narrow dock's edge, starts at %s" % at_1440.position.x)


## The row exists beside Text size, saves its key, and applies the factor at once.
func _check_row() -> void:
	var button: OptionButton = _panel._interface_button
	if button == null:
		_fail("no Interface size row")
		return
	if button.item_count != InterfaceSize.SIZES.size():
		_fail("Interface size offers %d items, expected %d" % [button.item_count, InterfaceSize.SIZES.size()])
	if button.selected != InterfaceSize.AUTO_INDEX:
		_fail("with no settings file the row should show Auto, shows %d" % button.selected)
	button.select(4)
	_panel._save_and_apply()
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	if int(cfg.get_value("display", "interface_size_index", -1)) != 4:
		_fail("the Interface size row did not save interface_size_index")
	_expect("75 % applied to the window", root.content_scale_factor, 0.75)
	# A second panel reads the file, as the next launch will.
	var reloaded = SettingsPanel.new()
	root.add_child(reloaded)
	if reloaded._interface_button.selected != 4:
		_fail("Interface size did not survive a reload: %d" % reloaded._interface_button.selected)
	reloaded.queue_free()
	button.select(InterfaceSize.AUTO_INDEX)
	_panel._save_and_apply()
	_expect("Auto applied back", root.content_scale_factor,
		InterfaceSize.factor(InterfaceSize.AUTO_INDEX, root.size))


## Auto follows the window: F11, a maximize or a drag changes the size, and the root
## window's size_changed re-applies the rule. Installed once, however many scenes
## apply the setting.
func _check_listener() -> void:
	InterfaceSize.apply(root)
	InterfaceSize.apply(root)
	var count := 0
	for connection in root.size_changed.get_connections():
		if String(connection["callable"].get_method()) == "refit":
			count += 1
	if count != 1:
		_fail("Auto should follow the window through one size_changed connection, found %d" % count)
	# The handler itself, at whatever size headless reports: it lands on the rule.
	root.content_scale_factor = 0.5
	InterfaceSize.refit(root)
	_expect("the refit lands on the rule", root.content_scale_factor,
		InterfaceSize.factor(InterfaceSize.AUTO_INDEX, root.size))
	# A manual step survives the window moving: a maximize must not snap 80 % back to Auto.
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value("display", "interface_size_index", 3)
	cfg.save(SettingsPanel.CONFIG_PATH)
	InterfaceSize.refit(root)
	_expect("80 % kept through a size change", root.content_scale_factor, 0.8)
	_check_region_fit_source()
	_check_click_through_scale()


## The overlay asks the live canvas when it frames, not the rect set when the tab was
## built: the factor can change after that (a Settings change, a window moved to
## another screen).
func _check_region_fit_source() -> void:
	var overlay = MapRegions.new()
	root.add_child(overlay)
	overlay.fit_rect = Rect2(0, 0, 1, 1)
	overlay.fit_rect_source = RegionsShell.fit_rect_for
	overlay.fit()
	var expected: Rect2 = RegionsShell.fit_rect_for(overlay.get_viewport_rect().size)
	if not overlay.fit_rect.is_equal_approx(expected):
		_fail("fit() kept a stale frame %s; the canvas asks for %s" % [overlay.fit_rect, expected])
	overlay.queue_free()


## A click in window pixels still lands on the control under it at 75 %: the engine
## maps it through the stretch transform, which carries the factor. A control placed
## past the 1080p canvas (x 2000) is reachable only because the canvas grew.
func _check_click_through_scale() -> void:
	root.content_scale_factor = 0.75
	var button := Button.new()
	button.position = Vector2(2000, 300)
	button.size = Vector2(120, 40)
	var fired := [0]
	button.pressed.connect(func(): fired[0] += 1)
	root.add_child(button)
	var at: Vector2 = root.get_final_transform() * button.get_global_rect().get_center()
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = down
		click.position = at
		click.global_position = at
		root.push_input(click)
	if fired[0] != 1:
		_fail("a click at window px %s did not reach the button at canvas %s under factor 0.75" % [at, button.position])
	button.queue_free()


func _restore() -> void:
	if _had_file:
		var file := FileAccess.open(SettingsPanel.CONFIG_PATH, FileAccess.WRITE)
		file.store_string(_original)
		file.close()
	else:
		DirAccess.remove_absolute(SettingsPanel.CONFIG_PATH)
	root.content_scale_factor = 1.0


func _finish() -> void:
	if _failures.is_empty():
		print("test_interface_size: OK")
	else:
		print("test_interface_size: %d failure(s)" % _failures.size())
