extends SceneTree

## V5.3-0 (b2), parent pass 2 on #221 (TAKE 3): a request's card dropped on one of
## its days books THAT day, through the cell's own drop hooks:
##   - a request arrives and its Days turns the Diary to its offered days;
##   - the first free offered cell takes the request's payload and refuses a
##     payload it does not offer; the drop books the request on that very day;
##   - an offered day the Diary refuses takes no drop;
##   - the Diary closed under a booking ends it (TAKE 7): nothing is focused;
##   - QA's TAKE on #221: Days by a REAL Enter leaves the keyboard on the request's
##     "Book here" frames later, after the Diary's rebuilds.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const DiaryDay = preload("res://src/ui/diary_day.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _request_id := ""
## A second waiting request, for the close case.
var _other := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main._clock.paused = true
		_arrive()
	elif _frame == 4:
		_enter(true)
	elif _frame == 6:
		_enter(false)
	elif _frame == 14:
		_check_focus()
	elif _frame == 16:
		_drop()
	elif _frame == 18:
		_close()
	elif _frame == 20:
		_finish()
		return true
	return false


func _arrive() -> void:
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	for person in _main._loader.people.get(String(ns.id), []):
		if person.wants.is_empty() or String(person.id) == String(ns.head_of_state_person_id):
			continue
		var arrived := []
		Audiences._arrive(ns, person, person.wants[0], now, arrived)
		if arrived.is_empty():
			continue
		AudienceDriver.after_month(_main, {"audience_requests": {"arrived": arrived, "lapsed": []}})
		var id := String(arrived[0]["id"])
		if _request_id == "":
			for date in Audiences.offered_dates(_main._state, ns, id):
				if bool(date["free"]):
					_request_id = id
					break
		elif _other == "":
			_other = id
		if _request_id != "" and _other != "":
			break
	if _request_id == "":
		_fail("premise: no arrived request offers a free day")
		return
	_main._windows.open("calendar")


## Days focused, then Enter pressed (and released frames later) through the viewport.
func _enter(down: bool) -> void:
	if down:
		var card: Node = _main._calendar_panel.requests.find_child("Request_%s" % _request_id, true, false)
		var days := card.find_child("Days", true, false) as Button if card != null else null
		if days == null:
			_fail("premise: the request has no Days")
			return
		days.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_ENTER
	key.pressed = down
	root.push_input(key)


func _check_focus() -> void:
	var owner := root.gui_get_focus_owner()
	if owner == null or String(owner.name) != "BookHere_%s" % _request_id:
		_fail("Days by Enter left the focus on %s, not on Book here" % (owner.name if owner != null else "nothing"))


func _drop() -> void:
	if _request_id == "":
		return
	var cell: Control = null
	for c in _main._calendar_panel._grid._days.get_children():
		var offered: Dictionary = c.get("offers") if c.get("offers") != null else {}
		if offered.has(_request_id) and bool(offered[_request_id].get("free", true)):
			cell = c
			break
	if cell == null:
		_fail("Days did not turn the grid to a page with the request's free day")
		return
	var date: Dictionary = cell.offers[_request_id]
	if not cell._can_drop_data(Vector2.ZERO, {"request": _request_id}):
		_fail("a free offered day refused its own request's card")
	if cell._can_drop_data(Vector2.ZERO, {"request": "nobody|0"}):
		_fail("a day took a card it does not offer")
	cell._drop_data(Vector2.ZERO, {"request": _request_id})
	var row := Audiences.request(_main._state.player(), _request_id)
	var booked: Dictionary = row.get("date", {})
	if String(row.get("status", "")) != "booked":
		_fail("the drop did not book the request (%s)" % row.get("status", ""))
	elif int(booked.get("day", 0)) != int(date["day"]) or int(booked.get("month", 0)) != int(date["month"]):
		_fail("the drop booked %s, not the day it fell on %s" % [booked, date])

	var refused := DiaryDay.new()
	refused.offers["req|1"] = {"year": 2026, "month": 2, "day": 3, "free": false, "reason": "already booked"}
	if refused._can_drop_data(Vector2.ZERO, {"request": "req|1"}):
		_fail("an offered day the Diary refuses took the card")
	refused.free()


## The request's Days again opens its booking; the Diary closes under it.
func _close() -> void:
	var column = _main._calendar_panel.requests
	column.focus_requested.emit(_other)
	if column.request_id() != _other:
		_fail("premise: Days did not focus the request")
	_main._windows.close("calendar")
	if column.request_id() != "":
		_fail("the Diary closed under a booking left %s focused" % column.request_id())


func _finish() -> void:
	if _failures.is_empty():
		print("test_diary_drop: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
