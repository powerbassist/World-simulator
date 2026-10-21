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
const Strings = preload("res://src/ui/strings.gd")

## 1920x1080 is the layout base (stretch canvas_items); this is the width
## window_manager._place() gives a window.
const BAND := 1920.0 - WindowManager.LEFT_RESERVE - WindowManager.SIDE_MARGIN
const EXPANSION := 0.35
## The HUD's lower row (legend + portrait, the command bar with its drawer, the clock)
## and the top bar sit in the 1920 px layout less the HUD's 14 px edge margins.
const HUD_BAND := 1920.0 - 2.0 * 14.0

var _failures: Array[String] = []
var _widths := {}  # id -> {"en": px, "pseudo": px}


func _initialize() -> void:
	await _sweep("en")
	Strings.set_language("fr")
	await _sweep("fr")
	Strings.set_language("en")
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
	await _check_hud(main, language)
	await _check_briefing(main, language)
	main.queue_free()
	await process_frame


## The HUD pieces that share the screen's width, in every state of the command bar:
## the lower row needs the sum of its pieces and the drawer of the open cluster is the
## widest of them, so each cluster is opened in turn. Also after a live language
## switch -- the pieces already built keep their language, the drawer is rebuilt in
## the new one, and the row must still fit.
func _check_hud(main, language: String) -> void:
	var hud = main._hud
	var bar = hud.action_bar
	var lower: Control = bar.get_parent()
	for cluster in bar._entries.keys():
		bar.show_cluster(cluster)
		await process_frame
		_hud_width("lower row with '%s' open" % cluster, lower.get_combined_minimum_size().x, language)
	bar.close_subrow()
	_hud_width("top bar", hud.top_bar.get_combined_minimum_size().x, language, 1920.0)
	_hud_width("map legend", hud.map_legend.get_combined_minimum_size().x, language)
	# The switch: English pieces, French drawer; then the reverse.
	if language == "en":
		for other in ["fr", "en"]:
			Strings.set_language(other)
			for cluster in bar._entries.keys():
				bar.close_subrow()
				bar.show_cluster(cluster)
				await process_frame
				_hud_width("lower row with '%s' open after a switch to %s" % [cluster, other], lower.get_combined_minimum_size().x, "en>" + other)


## The bill briefing is a popup with a fixed width over a scroll view (V5.1a's
## clipped-figures bug): its content's minimum width must not exceed its view.
func _check_briefing(main, language: String) -> void:
	var laws: Array = main._loader.laws
	if laws.is_empty():
		_fail("no authored law to brief on")
		return
	var briefing = main._briefing
	briefing.open_for_law(laws[0], main._state, main._loader)
	briefing.show()
	briefing.size = briefing.custom_minimum_size
	await process_frame
	var scrolls: Array[ScrollContainer] = []
	_collect_scrolls(briefing, scrolls)
	if scrolls.is_empty():
		_fail("the briefing has no ScrollContainer under %s" % language)
	for scroll in scrolls:
		var need: float = scroll.get_child(0).get_combined_minimum_size().x
		print("i18n_fit: briefing %-6s needs %4.0f px of %4.0f" % [language, need, scroll.size.x])
		if need > scroll.size.x + 0.5:
			_fail("the briefing under %s needs %.0f px but its view is %.0f: right-hand figures are clipped" % [language, need, scroll.size.x])
	briefing.hide()


func _collect_scrolls(node: Node, out: Array[ScrollContainer]) -> void:
	if node is ScrollContainer:
		out.append(node)
	for child in node.get_children():
		_collect_scrolls(child, out)


func _hud_width(what: String, need: float, language: String, band := HUD_BAND) -> void:
	print("i18n_fit: HUD %-6s %-44s %4.0f px" % [language, what, need])
	if need > band:
		_fail("HUD under %s: %s needs %.0f px, more than the %.0f px of the screen" % [language, what, need, band])


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
