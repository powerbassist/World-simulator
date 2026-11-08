extends SceneTree

## V5.3 b, step 6 (docs/design/v5.3-ab.md section 5, "booking moves into the grid"): a waiting
## request is a chip on each of its offered days, a click on a chip books THAT day, and the
## request column beside the grid is gone.
##   - each free offered day shows a chip with the asker's face and the last day to answer;
##   - a real click on a chip books that very date, not the first offered;
##   - a day the Diary refuses shows its chip disabled, with the sim's reason, and a click on
##     it picks the day rather than dying (a dead click, V5.1's lesson);
##   - the inbox card's Go turns the Diary to the first free day and, frames later, past the
##     grid's rebuilds, the keyboard stands on that day's Book here;
##   - the Diary closed under a Go ends the booking, so the slowed clock is given back.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _request_id := ""
## A second waiting request: the Go and close cases, after the first is booked.
var _other := ""
var _date := {}


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._clock.paused = true
			_arrive()
		5:
			_check_chips()
		6:
			_click(true)
		8:
			_click(false)
		10:
			_check_booked()
		11:
			_check_refused()
		12:
			_go()
		22:
			_check_focus()
			_main._windows.close("calendar")
		24:
			_check_closed()
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
		var free := _free(id)
		# The LAST free day of a request with two: a booking of the first would not tell
		# "that day" from "the first offered".
		if _request_id == "" and free.size() >= 2:
			_request_id = id
			_date = free[free.size() - 1]
		elif id != _request_id and _other == "" and not free.is_empty():
			_other = id
		if _request_id != "" and _other != "":
			break
	if _request_id == "" or _other == "":
		_fail("premise: too few requests with free offered days arrived")
		return
	_main._windows.open("calendar")
	_main._calendar_panel._process(0.0)
	_main._calendar_panel._grid.show_month(int(_date["year"]), int(_date["month"]))


func _free(id: String) -> Array:
	var out := []
	for date in Audiences.offered_dates(_main._state, _main._state.player(), id):
		if bool(date["free"]):
			out.append(date)
	return out


func _cell(day: int) -> Control:
	return _main._calendar_panel._grid._days.get_node_or_null("Day_%d" % day) as Control


func _chip(id: String, day: int) -> Button:
	var cell := _cell(day)
	return cell.find_child("Chip_%s" % id, true, false) as Button if cell != null else null


func _check_chips() -> void:
	if _main._calendar_panel.find_child("DiaryRequests", true, false) != null:
		_fail("the request column beside the grid is still there")
	if _request_id == "":
		return
	var chip := _chip(_request_id, int(_date["day"]))
	if chip == null:
		_fail("no chip on the offered day")
		return
	if not chip.is_visible_in_tree() or chip.disabled:
		_fail("a free day's chip is hidden or disabled")
	if chip.find_child("Face", true, false) == null:
		_fail("the chip wears no face")
	var by: Label = chip.find_child("By", true, false)
	var row := Audiences.request(_main._state.player(), _request_id)
	var last := preload("res://src/ui/lever_words.gd").when(int(row["deadline_month"]) - 1)
	if by == null or not by.text.contains(last):
		_fail("the chip's deadline reads '%s', not '%s'" % [by.text if by != null else "nothing", last])
	var who: String = _main._loader.person_name(String(row["person_id"]))
	if not chip.tooltip_text.contains(who):
		_fail("the chip's hover does not name who asks: '%s'" % chip.tooltip_text)
	if chip.focus_mode != Control.FOCUS_ALL:
		_fail("a keyboard cannot reach the chip")


func _click(down: bool) -> void:
	var chip := _chip(_request_id, int(_date["day"]))
	if chip == null:
		_fail("premise: the chip went before its click")
		return
	Click.half(_main.get_viewport(), chip, down)


func _check_booked() -> void:
	var row := Audiences.request(_main._state.player(), _request_id)
	var booked: Dictionary = row.get("date", {})
	if String(row.get("status", "")) != "booked":
		_fail("the click did not book the request (%s)" % row.get("status", ""))
	elif int(booked.get("day", 0)) != int(_date["day"]) or int(booked.get("month", 0)) != int(_date["month"]):
		_fail("the click booked %s, not its own day %s" % [booked, _date])
	if _chip(_request_id, int(_date["day"])) != null:
		_fail("a booked request keeps its chip")


## A refused day, set on a cell by hand: the chip shows, disabled, and passes the click on.
func _check_refused() -> void:
	var grid = _main._calendar_panel._grid
	var cell := _cell(1)
	var row := {"id": "req|1", "person": "Someone", "wants": "wants a thing", "by": "MAR 2027"}
	var date := {"year": 2026, "month": 2, "day": 1, "free": false, "reason": "This day is taken."}
	cell.show_chips([{"id": "req|1", "person": "Someone", "date": date}], {"req|1": row}, grid.booked)
	var chip := _chip("req|1", 1)
	if chip == null or not chip.disabled or not chip.tooltip_text.contains(tr("This day is taken.")):
		_fail("a refused day's chip is not disabled with the sim's reason")
	elif chip.mouse_filter != Control.MOUSE_FILTER_PASS:
		_fail("a disabled chip swallows the click on its day")


func _go() -> void:
	var lane = AudienceDriver.lane_of(_main)
	var answers: Array = lane._answers_of.get(_other, [])
	if answers.is_empty() or String(answers[0]["label"]) != tr("Go"):
		_fail("the inbox card's first answer is not Go: %s" % [answers])
	lane.book_requested.emit(_other)


func _check_focus() -> void:
	var owner := root.gui_get_focus_owner()
	if owner == null or String(owner.name) != "BookHere_%s" % _other:
		_fail("Go left the focus on %s, not on Book here" % (owner.name if owner != null else "nothing"))
	var first: Dictionary = _free(_other)[0]
	var grid = _main._calendar_panel._grid
	var shown: Vector2i = grid._shown()
	if shown != Vector2i(int(first["year"]), int(first["month"])) or grid._selected != int(first["day"]):
		_fail("Go did not turn the Diary to the first free day %s (shown %s, day %d)" % [first, shown, grid._selected])


func _check_closed() -> void:
	var game: Dictionary = AudienceDriver._games[_main.get_instance_id()]
	if String(game["booking_for"]) != "":
		_fail("the Diary closed under a Go left %s being booked" % game["booking_for"])


func _finish() -> void:
	if _failures.is_empty():
		print("test_diary_chips: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(message: String) -> void:
	_failures.append(message)
