extends SceneTree

## Headless test: godot --headless --script res://tests/test_gap_bars.gd
## Non-zero exit on any failure.
##
## Design's T16 on #441: a page that lays out its own sheets (WindowManager.OWN_SHEETS) keeps them on
## the header sheet's edges whether or not it scrolls. A scroll that holds sheets -- one with no sheet
## (PLATE) between it and its page -- takes no width for its bar: the bar stands in the 12 px gap at
## the scroll's right, at most 8 wide, and moving it moves the page. A scroll inside a sheet keeps its
## own bar (it moves no sheet's edge). Silent when wrong: the page still scrolls, one sheet edge is off.
##
## The test world is quiet and nothing overflows, so each target scroll is made to overflow with a
## tall floor on its content, one at a time, and restored.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const GapBars = preload("res://src/ui/gap_bars.gd")

const WIDE := 8.0

var _failures: Array[String] = []
var _main
var _frame := 0
var _ids: Array = []
var _id := ""
var _targets: Array = []
var _index := 0
var _kept_floor := 0.0
var _checked := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		root.size = Vector2i(1920, 1080)
		_check_any_panel_is_a_sheet()
		_ids = WindowManager.OWN_SHEETS.duplicate()
		_next_page()
		return false
	if _frame < 5 or _frame % 3 != 0:
		return false
	if _id == "":
		_check_none_left_on_the_map()
		_finish()
		return false
	if _index > 0:
		_check_target(_targets[_index - 1])
	if _index < _targets.size():
		_overflow(_targets[_index])
		_index += 1
		return false
	_next_page()
	return false


## #445 pass 2 T1: a sheet is any panel that draws (the bill sheet, finance_sheet.gd, is a default
## PanelContainer, not a PLATE), so a scroll inside one keeps its own bar; only a BARE panel is no sheet.
func _check_any_panel_is_a_sheet() -> void:
	var page := Control.new()
	root.add_child(page)
	var drawn := PanelContainer.new()
	page.add_child(drawn)
	var inside := ScrollContainer.new()
	drawn.add_child(inside)
	var bare := PanelContainer.new()
	bare.theme_type_variation = UiTheme.BARE
	page.add_child(bare)
	var through := ScrollContainer.new()
	bare.add_child(through)
	var bars = GapBars.new()
	root.add_child(bars)
	bars.adopt(page)
	if inside.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_SHOW_NEVER or GapBars.bar_for(bars, inside) != null:
		_fail("a scroll inside a default-styled panel (the bill sheet) lost its own bar to a gap bar")
	if GapBars.bar_for(bars, through) == null:
		_fail("a scroll under a BARE panel was not given its gap bar")
	page.queue_free()
	bars.queue_free()


func _next_page() -> void:
	if _ids.is_empty():
		_main._windows.close_all()
		_id = ""
		return
	_id = String(_ids.pop_front())
	_main._windows.open(_id)
	_targets = []
	_index = 0
	# One frame for the page to build before its scrolls are read.
	await process_frame
	_targets = _sheet_scrolls(_main._windows.frame(_id))
	if _targets.is_empty():
		_fail("premise: %s has no scroll that holds sheets" % _id)


## The scrolls whose bar would take width from sheets: visible, scrolling vertically, no sheet above.
func _sheet_scrolls(page: Control) -> Array:
	var out := []
	for node in page.find_children("*", "ScrollContainer", true, false):
		var scroll := node as ScrollContainer
		if not scroll.is_visible_in_tree() or scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED:
			continue
		var in_sheet := false
		var up: Node = scroll.get_parent()
		while up != null and up != page:
			if up is PanelContainer and (up as Control).theme_type_variation != UiTheme.BARE:
				in_sheet = true
			up = up.get_parent()
		if not in_sheet:
			out.append(scroll)
	return out


func _overflow(scroll: ScrollContainer) -> void:
	var content := scroll.get_child(0) as Control
	_kept_floor = content.custom_minimum_size.y
	content.custom_minimum_size.y = scroll.size.y + 2000.0


func _check_target(scroll: ScrollContainer) -> void:
	var content := scroll.get_child(0) as Control
	var where := "%s, %s" % [_id, scroll.name]
	var inner := scroll.get_v_scroll_bar()
	if inner.max_value - inner.page < 100.0:
		_fail("premise (%s): the floor did not make the scroll overflow" % where)
	_checked += 1
	if inner.visible:
		_fail("%s: the scroll's own bar shows, taking %.0f px from its sheets" % [where, scroll.size.x - content.size.x])
	if content.size.x < scroll.size.x - 0.5:
		_fail("%s: the content is %.0f wide in a %.0f px scroll (the bar's room is still taken)" % [where, content.size.x, scroll.size.x])
	var bar := GapBars.bar_for(_main._windows, scroll)
	if bar == null or not bar.is_visible_in_tree():
		_fail("%s: no bar in the gap while the page scrolls" % where)
	else:
		var r := bar.get_global_rect()
		var s := scroll.get_global_rect()
		var gap := float(UiTheme.GAP_PANE)
		if r.size.x > WIDE + 0.01 or r.position.x < s.end.x - 0.01 or r.end.x > s.end.x + gap + 0.01:
			_fail("%s: the bar spans x %.0f-%.0f, not inside the %.0f px gap at %.0f (at most %.0f wide)" % [where, r.position.x, r.end.x, gap, s.end.x, WIDE])
		if absf(r.position.y - s.position.y) > 0.5 or absf(r.size.y - s.size.y) > 0.5:
			_fail("%s: the bar runs y %.0f-%.0f, its scroll %.0f-%.0f" % [where, r.position.y, r.end.y, s.position.y, s.end.y])
		bar.value = 120.0
		if scroll.scroll_vertical != 120:
			_fail("%s: moving the gap bar to 120 left the page at %d" % [where, scroll.scroll_vertical])
		scroll.scroll_vertical = 0
	content.custom_minimum_size.y = _kept_floor


## Back to the map: no bar is left standing in the empty gap.
func _check_none_left_on_the_map() -> void:
	if _checked == 0:
		_fail("premise: no scroll was checked")
	for node in _main._windows.find_children("*", "VScrollBar", true, false):
		if (node as Control).has_meta(GapBars.META) and (node as Control).is_visible_in_tree():
			_fail("a gap bar still shows with every tab closed")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_gap_bars: all checks passed (%d scrolls)" % _checked)
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
