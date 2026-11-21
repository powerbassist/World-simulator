extends RefCounted

## A request's Go from the inbox -- V5.3 b, step 6: the grid turns to the first day it offers
## that the Diary can take (else its first) and picks it, and the keyboard stands on that day
## through the grid's rebuilds; Enter there books it, as a click does (the month page).

const Grid = preload("res://src/ui/diary_grid.gd")
const Audiences = preload("res://src/sim/audiences.gd")

## The request the keyboard was sent to book, "" for none. audience_driver clears it.
var request := ""
## The request came by the keys (a Go, a keyboard See them): only then does a day take the
## focus, where Space books it -- never after a mouse route (pass 2 TAKE 8).
var keys := true
var _grid: Grid


func attach(grid: Grid) -> void:
	_grid = grid
	grid.listed.connect(_refocus)


func show_days(dates: Array, state, loader) -> void:
	if dates.is_empty():
		return
	# A Diary never drawn has no state yet; its next refresh brings the items and keeps
	# the page (show_items).
	if _grid._state == null:
		_grid.show_items(state, loader, [])
	var first: Dictionary = dates[0]
	for date in dates:
		if bool(date.get("free", false)):
			first = date
			break
	_grid.pick(int(first["year"]), int(first["month"]), int(first["day"]))


func focus(request_id: String, by_keys := true) -> void:
	request = request_id
	keys = by_keys
	_focus_on(request_id)


## The picked day takes the keyboard (a summons' See them from the keys: it has no request id).
func focus_day() -> void:
	var cell := _grid._days.get_node_or_null("Day_%d" % _grid._selected) as Control
	if _grid._selected > 0 and cell != null and not cell.is_queued_for_deletion():
		cell.grab_focus()
		_settle(cell)


## A rebuild freed the focused control: the pending booking takes it again. Focus the player
## moved elsewhere stays.
func _refocus() -> void:
	if request == "" or not keys or not _grid.is_visible_in_tree():
		return
	# #431 pass 2 TAKE 1: the daily redraw ran (nothing was in hand) and the picked day is now
	# today or gone; the first free day takes the pick, its re-render brings us back here.
	var st = _grid._state
	if st != null and _grid._selected > 0 and _grid._shown() == Vector2i(int(st.year), int(st.month)) \
			and _grid._selected <= int(st.day):
		var first: Dictionary = Audiences.first_free_day(st, st.player(), request)
		if not first.is_empty():
			_grid.pick(int(first["year"]), int(first["month"]), int(first["day"]))
			return
	var viewport := _grid.get_viewport()
	var owner: Control = viewport.gui_get_focus_owner() if viewport != null else null
	if owner == null or owner.is_queued_for_deletion() or not owner.is_inside_tree():
		_focus_on(request)


## The picked day of the armed request's window takes the keyboard, where Enter books it.
func _focus_on(request_id: String) -> void:
	if not keys or String(_grid.armed.get("id", "")) != request_id:
		return
	focus_day()


## The page's scroll followed the focus while the month page was still laying out (the
## counters, the armed line), and kept an offset that hid the page's top. A frame later, from
## the top, it scrolls only as far as the day needs.
func _settle(cell: Control) -> void:
	await _grid.get_tree().process_frame
	if not is_instance_valid(cell) or not cell.is_inside_tree():
		return
	var node := cell.get_parent()
	while node != null and not (node is ScrollContainer and node != _grid._list_scroll):
		node = node.get_parent()
	if node != null:
		(node as ScrollContainer).scroll_vertical = 0
		(node as ScrollContainer).ensure_control_visible(cell)
