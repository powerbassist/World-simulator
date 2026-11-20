extends RefCounted

## A request's Go from the inbox -- V5.3 b, step 6: the grid turns to the first day it offers
## that the Diary can take (else its first) and picks it, so the day list carries "Book here",
## and the keyboard stands on that button through the grid's rebuilds. What is left of the
## request column once its cards went onto the grid (diary_chip.gd).

const Grid = preload("res://src/ui/diary_grid.gd")
const Audiences = preload("res://src/sim/audiences.gd")

## The request the keyboard was sent to book, "" for none. audience_driver clears it.
var request := ""
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


func focus(request_id: String) -> void:
	request = request_id
	_focus_on(request_id)


## A rebuild freed the focused control: the pending booking takes it again. Focus the player
## moved elsewhere stays.
func _refocus() -> void:
	if request == "" or not _grid.is_visible_in_tree():
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


func _focus_on(request_id: String) -> void:
	for b in _grid.day_list.find_children("BookHere_%s" % request_id, "Button", true, false):  # i18n: ok a node name and a class, found by tests
		if not (b as Button).disabled and not b.is_queued_for_deletion():
			(b as Button).grab_focus()
			return
