extends SceneTree

## Headless test: godot --headless --script res://tests/test_dock_fit.gd
## Non-zero exit on any failure.
##
## The void pass's plate in the REAL game (#400 pass 2): test_workspace.gd holds the window
## manager's rule on fixtures; this holds it on the panels a player opens, whose own build is what
## broke it -- a floating window's height floor (Diplomacy 860) that kept the plate full height, a
## mid-term Agenda whose scroll was added to a floor that already held it (~300 px of blank), and
## a 440 px row measure in the 500 px Regions dock that put a sideways bar under the About rows.
## Swept in English at text 100 and in French at text 130, the two ends the frames are taken at.

const WindowManager = preload("res://src/ui/window_manager.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")

## What may sit between the last thing drawn and the plate's bottom: the panel's own bottom margin
## and a row's separation. The blank the review found was ~300 px.
const SLACK := 48.0

var _failures: Array[String] = []


func _initialize() -> void:
	await _sweep("en", 1.0)
	Strings.set_language("fr")
	await _sweep("fr", 1.3)
	Strings.set_language("en")
	UiTheme.set_text_scale(1.0)
	for failure in _failures:
		push_error("FAIL " + failure)
	print("test_dock_fit: %d failures" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)


func _sweep(language: String, text_scale: float) -> void:
	UiTheme.set_text_scale(text_scale)
	var main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	var windows = main._windows
	windows.size = Vector2(1920.0, 1080.0)
	var where := "%s at text %.0f" % [language, text_scale * 100.0]

	# Diplomacy with no nation picked: a few lines, so a short plate (the author's (d)).
	await _open(windows, "diplomacy")
	_check_hugs(windows, "diplomacy", where, true)

	# The Agenda mid-term with no programme: a line and one button.
	var ns = main._state.player()
	ns.programme = []
	ns.programme_chosen_term = -1
	ns.months_in_term = 7
	await _open(windows, "agenda")
	_check_hugs(windows, "agenda", where, true)

	# The Sectors overview hugs or fills, but never leaves a blank under its last row.
	await _open(windows, "companies")
	_check_hugs(windows, "companies", where, false)

	# Regions, the narrowest host a row has: About unfolded, then a city's card.
	var regions = main._region_panel
	regions._about_open = true
	regions.mark_dirty()
	await _open(windows, "region")
	_check_no_sideways_bar(windows, "region", where + ", About")
	_check_rows_share_a_width(windows.content("region"), where + ", Regions About")
	var region = main._loader.regions.get(ns.id, [])[0]
	var city = regions._largest_city(region.id)
	regions.open_city(String(city.id))
	await _frames(3)
	_check_no_sideways_bar(windows, "region", where + ", city card")

	# Polling's two ledgers: one caption column.
	await _open(windows, "society")
	_check_ledgers_share_a_caption_column(windows.content("society")._body, where + ", Society")

	# The Save/Load dialog (QA's real-window play, French 130: "Supprimer" cut at the dialog's edge).
	windows.close_all()
	await _check_save_load_buttons_fit(main, where)

	main.queue_free()
	await process_frame


func _open(windows, id: String) -> void:
	windows.close_all()
	windows.open(id, true)
	await _frames(4)


func _frames(count: int) -> void:
	for i in count:
		await process_frame


## The plate ends at its content: no vertical bar on a page that fits, and no more than SLACK
## between the last thing drawn and the plate's bottom. `short`: the content is known to be well
## under the dock, so the dock must not be full height.
func _check_hugs(windows, id: String, where: String, short: bool) -> void:
	var page = windows.frame(id)
	var scroll: ScrollContainer = page._scroll
	var dock: Rect2 = windows.dock().get_global_rect()
	var full: float = 1080.0 - WindowManager.DOCK_TOP - WindowManager.DOCK_BOTTOM
	if short and dock.size.y > full - 100.0:
		_fail("%s (%s): the dock is %.0f px of %.0f, the plate did not hug its content" % [id, where, dock.size.y, full])
	if dock.size.y < full - 0.5 and scroll.get_v_scroll_bar().visible:
		_fail("%s (%s): a hugging plate (%.0f px) scrolls its own content" % [id, where, dock.size.y])
	var bottom := scroll.get_global_rect().position.y
	for node in page._content.find_children("*", "Control", true, false):
		var control := node as Control
		if control.get_child_count() == 0 and control.is_visible_in_tree() and not control is ScrollBar:
			bottom = maxf(bottom, control.get_global_rect().end.y)
	var blank: float = scroll.get_global_rect().end.y - bottom
	if blank > SLACK:
		_fail("%s (%s): %.0f px of blank under the last line" % [id, where, blank])


## The row measure is never wider than its host: no sideways bar on the page or on a scroll in it.
func _check_no_sideways_bar(windows, id: String, where: String) -> void:
	var page = windows.frame(id)
	var scrolls: Array = [page._scroll]
	scrolls.append_array(page._content.find_children("*", "ScrollContainer", true, false))
	for scroll in scrolls:
		if (scroll as ScrollContainer).get_h_scroll_bar().visible:
			_fail("%s: a sideways scroll bar (content %.0f px in %.0f)" % [where,
				(scroll as ScrollContainer).get_child(0).get_combined_minimum_size().x, (scroll as ScrollContainer).size.x])
	var view: Rect2 = (page._scroll as Control).get_global_rect()
	var widest := 0.0
	for row in _rows(page._content):
		if (row as Control).is_visible_in_tree():
			widest = maxf(widest, (row as Control).get_global_rect().end.x - view.position.x)
	print("dock_fit: %s, rows reach %.0f px of a %.0f px page" % [where, widest, view.size.x])
	for row in _rows(page._content):
		if (row as Control).is_visible_in_tree() and (row as Control).get_global_rect().end.x > view.end.x + 0.5:
			_fail("%s: a row ends at x %.0f, past its page's %.0f" % [where, (row as Control).get_global_rect().end.x, view.end.x])


## T5: the caption-and-value rows of one stack share one width, so their values line up.
func _check_rows_share_a_width(content: Control, where: String) -> void:
	var by_stack := {}
	for row in _rows(content):
		if not (row as Control).is_visible_in_tree():
			continue
		var stack: Node = (row as Node).get_parent()
		if not by_stack.has(stack):
			by_stack[stack] = []
		by_stack[stack].append((row as Control).size.x)
	var checked := 0
	for stack in by_stack:
		var widths: Array = by_stack[stack]
		if widths.size() < 2:
			continue
		checked += 1
		if widths.max() - widths.min() > 0.5:
			_fail("%s: the rows of one stack are %s px wide, their values do not line up" % [where, widths])
	if checked == 0:
		_fail("%s: premise, no stack of two rows to compare" % where)


func _check_ledgers_share_a_caption_column(content: Control, where: String) -> void:
	var ends: Array = []
	for grid in content.find_children("*", "GridContainer", true, false):
		if (grid as Control).is_visible_in_tree() and not (grid as Node).is_queued_for_deletion() and (grid as Node).get_child_count() > 0:
			ends.append(((grid as Node).get_child(0) as Control).get_global_rect().end.x)
	if ends.size() < 2:
		_fail("%s: premise, %d ledgers" % [where, ends.size()])
	elif ends.max() - ends.min() > 0.5:
		_fail("%s: the ledgers' caption columns end at %s, their values do not line up" % [where, ends])


## Every button of the dialog, a saved game's Load and Delete included, inside the dialog and inside
## the list's view: a row past its scroll's edge is a button the player cannot see whole.
func _check_save_load_buttons_fit(main, where: String) -> void:
	var panel = main._save_load_panel
	panel.show()
	await _frames(2)
	# Enough saves for the list's own scroll bar, which takes its width from the rows.
	for i in 8:
		panel._slot_list.add_child(panel._build_slot_row("sauvegarde rapide du mandat %d" % i))
	await _frames(3)
	var box: Rect2 = (panel as Control).get_global_rect()
	var buttons: Array = (panel as Node).find_children("*", "Button", true, false)
	if buttons.size() < 4:
		_fail("Save/Load (%s): premise, %d buttons" % [where, buttons.size()])
	for button in buttons:
		var b := button as Button
		if not b.is_visible_in_tree():
			continue
		var rect := b.get_global_rect()
		var view := box
		var scroll := b.get_parent()
		while scroll != null and not scroll is ScrollContainer and scroll != panel:
			scroll = scroll.get_parent()
		if scroll is ScrollContainer:
			view = (scroll as Control).get_global_rect()
			var bar := (scroll as ScrollContainer).get_v_scroll_bar()
			if bar.visible:
				view.size.x -= bar.size.x
		if rect.end.x > view.end.x + 0.5 or rect.position.x < view.position.x - 0.5:
			_fail("Save/Load (%s): '%s' spans x %.0f-%.0f, outside its view's %.0f-%.0f" % [where, b.text,
				rect.position.x, rect.end.x, view.position.x, view.end.x])
	panel.close()


## A PanelKit.row: an HBox of a caption Label and a value Label.
func _rows(content: Control) -> Array:
	var out: Array = []
	for box in content.find_children("*", "HBoxContainer", true, false):
		if (box as Node).get_child_count() == 2 and (box as Node).get_child(0) is Label and (box as Node).get_child(1) is Label \
				and ((box as Node).get_child(0) as Label).theme_type_variation == UiTheme.CAPTION:
			out.append(box)
	return out


func _fail(message: String) -> void:
	_failures.append(message)
