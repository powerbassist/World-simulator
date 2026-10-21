extends SceneTree

## Headless test: godot --headless --script res://tests/test_i18n_fit.gd
## Non-zero exit on any failure.
##
## V5.1b. French runs about a third longer than English, and a window sized to its
## content grows with it until the screen is the limit: past that the right-hand
## figures are cut off (V5.1a's briefing bug, found by eye). This opens every
## registered window and requires its content's minimum width to fit the band a
## window may occupy -- once in English and once under the engine's own
## pseudolocalization at +35%, which stands in for a language before its
## translations exist (accents, bracketed, every msgid reached through tr()).
## Real French fit is checked in each translation PR with the windowed frame
## (tools/screenshot.gd -- --lang fr).
##
## A window whose English already does not fit is a pre-existing failure and is
## reported as such rather than blamed on the language.

const WindowManager = preload("res://src/ui/window_manager.gd")

## 1920x1080 is the layout base (stretch canvas_items); this is the width
## window_manager._place() gives a window.
const BAND := 1920.0 - WindowManager.LEFT_RESERVE - WindowManager.SIDE_MARGIN
const EXPANSION := 0.35

var _failures: Array[String] = []
var _widths := {}  # id -> {"en": px, "pseudo": px}


func _initialize() -> void:
	await _sweep("en")
	ProjectSettings.set_setting("internationalization/pseudolocalization/expansion_ratio", EXPANSION)
	TranslationServer.pseudolocalization_enabled = true
	TranslationServer.reload_pseudolocalization()
	await _sweep("pseudo")
	TranslationServer.pseudolocalization_enabled = false
	_report()
	quit(1 if not _failures.is_empty() else 0)


func _sweep(language: String) -> void:
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var windows = main._windows
	var ids: Array = windows.panel_ids()
	if ids.size() < 20:
		_fail("only %d windows registered under %s" % [ids.size(), language])
	for id in ids:
		windows.open(id, true)
		# The panel refreshes on the frame after it is marked dirty.
		await process_frame
		await process_frame
		var frame = windows.frame(id)
		var need: float = frame._content.get_combined_minimum_size().x
		if not _widths.has(id):
			_widths[id] = {}
		_widths[id][language] = need
		if need > BAND:
			var baseline: float = _widths[id].get("en", 0.0)
			if language == "en" or baseline <= BAND:
				_fail("window '%s' needs %.0f px under %s, more than the %.0f px a window may take" % [id, need, language, BAND])
		windows.close(id, true)
	main.queue_free()
	await process_frame


func _report() -> void:
	var ids := _widths.keys()
	ids.sort()
	for id in ids:
		print("i18n_fit: %-14s en %4.0f px   pseudo %4.0f px" % [id, _widths[id].get("en", 0.0), _widths[id].get("pseudo", 0.0)])
	if _failures.is_empty():
		print("test_i18n_fit: all checks passed")
	else:
		for f in _failures:
			printerr(f)


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)
