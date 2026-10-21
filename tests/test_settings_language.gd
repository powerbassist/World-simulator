extends SceneTree

## Headless test: godot --headless --script res://tests/test_settings_language.gd
## Non-zero exit on any failure.
##
## V5.1b. The language is a setting like the others: a row in the Settings screen,
## a [display] language key in user://settings.cfg, applied by apply_saved() before
## any scene is built (the first scene to come up -- menu or game -- calls it), and
## reversible. A code the file holds that the game does not offer must not blank
## the interface: it is ignored. The panel is driven a frame at a time because a
## Control outside the tree is half-dead (AGENTS.md gotchas).

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _panel: PanelContainer
var _frame := 0


func _init() -> void:
	DirAccess.remove_absolute(SettingsPanel.CONFIG_PATH)
	_check_apply_saved()
	_panel = SettingsPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_check_row()
		Strings.set_language("en")
		DirAccess.remove_absolute(SettingsPanel.CONFIG_PATH)
		_finish()
		quit(1 if not _failures.is_empty() else 0)
	return false


func _check_apply_saved() -> void:
	if SettingsPanel.saved_language() != "en":
		_fail("with no settings file the language should be en, got %s" % SettingsPanel.saved_language())
	_write_language("fr")
	SettingsPanel.apply_saved(root)
	if Strings.language() != "fr":
		_fail("apply_saved should apply the saved language fr, got %s" % Strings.language())
	_write_language("klingon")
	Strings.set_language("en")
	SettingsPanel.apply_saved(root)
	if Strings.language() != "en":
		_fail("a language the game does not offer should be ignored, got %s" % Strings.language())
	DirAccess.remove_absolute(SettingsPanel.CONFIG_PATH)


func _check_row() -> void:
	var button: OptionButton = _panel._language_button
	if button == null:
		_fail("the Settings screen has no language row")
		return
	var codes: Array[String] = []
	for entry in Strings.languages():
		codes.append(String(entry["code"]))
	if button.item_count != codes.size():
		_fail("the row should offer %d languages, has %d" % [codes.size(), button.item_count])
	if button.selected != 0:
		_fail("a fresh install should show English selected")
	var fr_index := codes.find("fr")
	button.select(fr_index)
	button.item_selected.emit(fr_index)
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	if String(cfg.get_value("display", "language", "")) != "fr":
		_fail("choosing French should save [display] language = fr")
	if Strings.language() != "fr":
		_fail("choosing French should apply it")
	# The panel is rebuilt in the new language, and the row still shows the choice.
	if not _has_text(_panel, tr("Language")):
		_fail("the panel should have been rebuilt with its own labels in French")
	if _panel._language_button.selected != fr_index:
		_fail("the rebuilt row should still show the chosen language")
	var back: OptionButton = _panel._language_button
	back.select(0)
	back.item_selected.emit(0)
	if Strings.language() != "en" or _has_text(_panel, "Langue"):
		_fail("choosing English should restore the English labels")


func _has_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for child in node.get_children():
		if _has_text(child, text):
			return true
	return false


func _write_language(code: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SettingsPanel.CONFIG_PATH)
	cfg.set_value("display", "language", code)
	cfg.save(SettingsPanel.CONFIG_PATH)


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_settings_language: all checks passed")
	else:
		for f in _failures:
			printerr(f)
