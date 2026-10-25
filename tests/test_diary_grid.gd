extends SceneTree

## Headless test: godot --headless --script res://tests/test_diary_grid.gd
## Non-zero exit on any failure.
##
## V5.2 b+ R8 (docs/design/v5.2-bplus-spec.md, "the Diary as a full agenda grid"):
##   - every register entry and fixed date within the horizon has a mark on its
##     day (100 %), and so do a commitment's due date and a waiting request's last
##     day to answer;
##   - a day a waiting request offers is tinted, and its day list books it ("Book
##     here", a real press and release frames apart);
##   - today is marked; paging stops at both ends of the horizon.

const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AK = preload("res://src/sim/audience_constants.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _grid
var _request := ""
var _offered := {}
var _target: Control


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_stage()
			_main._windows.open("calendar")
		6:
			_grid = _main._calendar_panel.find_child("DiaryGrid", true, false)
			if _grid == null or not _grid.is_visible_in_tree():
				_fail("the Diary has no month grid on screen")
				_finish()
				return true
			_check_marks()
			_check_today()
			_check_paging()
			_check_month_turn()
			_check_travel_days()
			_grid.show_month(int(_offered["year"]), int(_offered["month"]))
		8:
			var cell := _cell(int(_offered["day"]))
			if cell == null or not bool(cell.tinted):
				_fail("the day a waiting request offers is not tinted")
				_finish()
				return true
			_target = cell
			_press(true)
		9:
			# QA's TAKE 1 on #153: a hand jitters -- a pixel of motion between the
			# press and the release must not drop the click.
			_move(1.0)
		11:
			_press(false)
		14:
			_target = _grid.day_list.find_child("BookHere", true, false) as Control
			if _target == null or not _target.is_visible_in_tree():
				_fail("the offered day's list has no Book here")
				_finish()
				return true
			_press(true)
		17:
			_press(false)
		20:
			var row := Audiences.request(_main._state.player(), _request)
			if String(row.get("status", "")) != AK.STATUS_BOOKED:
				_fail("Book here did not book the audience: %s" % String(row.get("status", "")))
			# QA's TAKE 2 on #153: days pass with the Diary open; today's ring follows.
			_grid.show_month(int(_main._state.year), int(_main._state.month))
			for i in 5:
				_main._clock.advance_one_day()
		22:
			var today := _cell(int(_main._state.day))
			if today == null or not bool(today.today):
				_fail("five days on with the Diary open, today's ring is not on day %d" % int(_main._state.day))
			var stale := _cell(int(_main._state.day) - 5)
			if stale != null and bool(stale.today):
				_fail("the ring stayed on the day the grid last drew")
			_finish()
			return true
	return false


## A booking two months out, a promise due in three, and a waiting request.
func _stage() -> void:
	var state = _main._state
	var ns = state.player()
	var at := _month(2)
	state.appointments.append(Calendar.make_entry(K.KIND_RESHUFFLE, int(at["year"]), int(at["month"]), 14, "", "", "", "interior", ""))
	var people: Array = _main._loader.people[String(ns.id)]
	var pid := String(people[3].id)
	var now := int(state.year) * 12 + int(state.month)
	ns.commitments.append({"kind": "promise", "person_id": pid, "object": "office:premiership", "made_month": now, "due_month": now + 3})
	for person in people.slice(4):
		var r := Audiences.invite(state, ns, _main._loader, String(person.id), "office:premiership", "wants")
		if bool(r.get("ok", false)):
			_request = String(r["request"]["id"])
			break
	if _request == "":
		_fail("premise: no request could be staged")
		return
	for d in Audiences.offered_dates(state, ns, _request):
		if bool(d["free"]):
			_offered = d
			break
	if _offered.is_empty():
		_fail("premise: the staged request offers no free day")


## Every dated thing in the horizon, with the day it lands on: the register and
## the fixed dates (Calendar.upcoming), each commitment on the first day of its
## month (judged as the month begins), each waiting request on the last day of
## the month before its deadline (it lapses as the deadline month begins).
func _check_marks() -> void:
	var state = _main._state
	var ns = state.player()
	var want := {}
	for row in Calendar.upcoming(state, K.BOOKING_HORIZON_MONTHS):
		_count(want, int(row["year"]), int(row["month"]), int(row.get("day", 1)))
	for row in ns.commitments:
		var m := int(row["due_month"])
		_count(want, floori((m - 1) / 12.0), m - floori((m - 1) / 12.0) * 12, 1)
	for row in Audiences.pending(ns):
		var last := int(row["deadline_month"]) - 1
		var y := floori((last - 1) / 12.0)
		var mo := last - y * 12
		_count(want, y, mo, Calendar.days_in_month(y, mo))
	var horizon := int(state.year) * 12 + int(state.month) + K.BOOKING_HORIZON_MONTHS
	var seen := 0
	for key in want:
		var parts: PackedStringArray = String(key).split("-")
		var y := int(parts[0])
		var mo := int(parts[1])
		if y * 12 + mo > horizon:
			continue
		_grid.show_month(y, mo)
		var cell := _cell(int(parts[2]))
		var marks: int = cell.marks.size() if cell != null else 0
		if marks < int(want[key]):
			_fail("%s carries %d marks, %d entries fall on it" % [key, marks, want[key]])
		seen += 1
	if seen < 3:
		_fail("premise: only %d dated days staged in the horizon" % seen)


func _check_today() -> void:
	var state = _main._state
	_grid.show_month(int(state.year), int(state.month))
	var cell := _cell(int(state.day))
	if cell == null or not bool(cell.today):
		_fail("today's cell is not marked")


func _check_paging() -> void:
	for i in K.BOOKING_HORIZON_MONTHS + 4:
		_grid.page_by(1)
	if _grid.page() != K.BOOKING_HORIZON_MONTHS:
		_fail("paging forward passed the horizon: page %d" % _grid.page())
	for i in K.BOOKING_HORIZON_MONTHS + 4:
		_grid.page_by(-1)
	if _grid.page() != 0:
		_fail("paging back passed this month: page %d" % _grid.page())


## The page is a month, not an offset from today: when the month turns, the
## picked month and day stay (review pass 1 on #153).
func _check_month_turn() -> void:
	var state = _main._state
	var at := _month(2)
	_grid.show_month(int(at["year"]), int(at["month"]))
	_grid._pick(14)
	state.month += 1
	_main._calendar_panel._refresh()
	if _grid.page() != 1 or _grid._selected != 14:
		_fail("the month turned and the grid moved: page %d (expected 1), day %d" % [_grid.page(), _grid._selected])
	state.month -= 1
	_main._calendar_panel._refresh()


## A visit's journey days are taken (the diary refuses them): each carries a mark
## (review pass 1 on #153).
func _check_travel_days() -> void:
	var state = _main._state
	var at := _month(4)
	var visit := Calendar.make_entry(K.KIND_DIPLOMATIC, int(at["year"]), int(at["month"]), 14, "state_visit", "DEU", "", "", "", "", 2)
	state.appointments.append(visit)
	_main._calendar_panel._refresh()
	_grid.show_month(int(at["year"]), int(at["month"]))
	for d in [12, 13, 15, 16]:
		var cell := _cell(d)
		if cell == null or cell.marks.is_empty():
			_fail("the visit's travel day %d carries no mark" % d)
	state.appointments.erase(visit)
	_main._calendar_panel._refresh()


func _count(want: Dictionary, y: int, mo: int, d: int) -> void:
	var key := "%d-%d-%d" % [y, mo, d]
	want[key] = int(want.get(key, 0)) + 1


func _cell(day: int) -> Control:
	return _grid.find_child("Day_%d" % day, true, false) as Control


func _month(offset: int) -> Dictionary:
	var total: int = int(_main._state.year) * 12 + int(_main._state.month) - 1 + offset
	return {"year": total / 12, "month": total % 12 + 1}


func _move(dx: float) -> void:
	var at: Vector2 = _target.get_global_rect().get_center() + Vector2(dx, 0)
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_main.get_viewport().push_input(motion, true)


func _press(down: bool) -> void:
	var at: Vector2 = _target.get_global_rect().get_center()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = down
	click.position = at
	click.global_position = at
	_main.get_viewport().push_input(click, true)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_diary_grid: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
