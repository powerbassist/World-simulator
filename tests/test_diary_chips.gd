extends SceneTree

## V5.3 b, step 6 (docs/design/v5.3-ab.md section 5, "booking moves into the grid"), as the
## parent ruled with "N'importe quel jour libre" (2026-11-20, option a), on the month page (the
## author's pick A): a request is ARMED -- its card's See them beside the grid, or the inbox's
## Go -- and every free day of its window is tinted; a click on one books THAT day.
##   - no day is tinted before a request is armed; armed, a day of the window is;
##   - a real click on the day books that very date, not the first offered;
##   - a day of the window the diary holds is not tinted, its click picks it and says why,
##     and the driver refuses to book it (QA's T1 on #431);
##   - the inbox card's Go arms the request and turns the Diary to the first free day and,
##     frames later, past the grid's rebuilds, the keyboard stands on that day;
##   - the day pressed as the clock turns it books the first free day, never "passed";
##   - the Diary closed under a Go ends the booking, so the slowed clock is given back.
##
## The file keeps its name (the registry and its shard): the chips it once tested are gone.

const Audiences = preload("res://src/sim/audiences.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _request_id := ""
## A second waiting request: the Go and close cases, after the first is booked.
var _other := ""
var _date := {}
## The day pressed as the clock turns (frames 33-36).
var _held: Control


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
			_check_taken_day()
			_check_taken_not_rebooked()
		18:
			_go()
		28:
			_check_focus()
			# TAKE 1, nothing in hand: the focus and the pointer leave, the clock turns the
			# picked day into today, and the redraw re-picks the first free day.
			var focused := root.gui_get_focus_owner()
			if focused != null:
				focused.release_focus()
			var away := InputEventMouseMotion.new()
			away.position = Vector2(2, 2)
			root.push_input(away)
			_main._clock.advance_one_day()
		32:
			_check_unheld_turn_repicked()
			var grid = _main._calendar_panel._grid
			# Pass 1 on the delta: the keyboard alone on the day (where a Go leaves it) does not
			# freeze the day's redraw -- the ring follows the day.
			var kept := _picked_day()
			if kept != null:
				kept.grab_focus()
			_main._clock.advance_one_day()
			grid._process(0.0)
			if int(grid._drawn_day) != int(_main._state.day):
				_fail("the keyboard on the day froze the day's redraw (drawn %d, today %d)" % [grid._drawn_day, _main._state.day])
		33:
			# TAKE 1 and 2, mid-click: the day pressed (a frame after its rebuild, laid out),
			# the clock turns, then released.
			_held = _picked_day()
			_click_book(true)
		35:
			var grid = _main._calendar_panel._grid
			_main._clock.advance_one_day()
			grid._process(0.0)
			if _held == null or not is_instance_valid(_held) or not _held.is_inside_tree():
				_fail("the day's redraw freed the day held down")
		36:
			_click_book(false)
		38:
			_check_turned_day_booked()
			_main._windows.close("calendar")
		40:
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
	var cell := _cell(int(_date["day"]))
	if cell != null and bool(cell.tinted):
		_fail("a day is tinted before any request is armed")
	var see := _main._calendar_panel.find_child("See_%s" % _request_id, true, false) as Button
	if see == null:
		_fail("the request's card beside the grid has no See them")
		return
	see.pressed.emit()
	_main._calendar_panel._grid.show_month(int(_date["year"]), int(_date["month"]))


func _free(id: String) -> Array:
	var out := []
	for date in Audiences.offered_dates(_main._state, _main._state.player(), id):
		if bool(date["free"]):
			out.append(date)
	return out


func _cell(day: int) -> Control:
	return _main._calendar_panel._grid._days.get_node_or_null("Day_%d" % day) as Control


## The day the grid has picked, where a Go leaves the keyboard.
func _picked_day() -> Control:
	return _cell(int(_main._calendar_panel._grid._selected))


func _check_chips() -> void:
	if _main._calendar_panel.find_child("DiaryPeople", true, false) == null:
		_fail("the month page has no people column beside the grid")
	if _request_id == "":
		return
	var cell := _cell(int(_date["day"]))
	if cell == null or not bool(cell.tinted):
		_fail("a free day of the armed request's window is not tinted")
	_check_the_later_count()
	_check_go_takes_the_first_free_day()
	_check_a_call_counts_from_the_request()
	_main._calendar_panel._grid.show_month(int(_date["year"]), int(_date["month"]))


## The page-on button is the only sign left that a request has days further on.
func _check_the_later_count() -> void:
	var ns = _main._state.player()
	var grid = _main._calendar_panel._grid
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	var later := 0
	for row in Audiences.pending(ns):
		for date in Audiences.offered_dates(_main._state, ns, String(row["id"])):
			if int(date["year"]) * 12 + int(date["month"]) > now:
				later += 1
				break
	grid.show_month(int(_main._state.year), int(_main._state.month))
	if later == 0 or grid._later.text != "> %d" % later:
		_fail("the next-month button reads '%s', with %d requests offering later days" % [grid._later.text, later])
	grid.show_month(int(_date["year"]), int(_date["month"]))


## The first FREE day, whatever comes before it.
func _check_go_takes_the_first_free_day() -> void:
	var grid = _main._calendar_panel._grid
	var y := int(_date["year"])
	var m := int(_date["month"])
	_main._calendar_panel.booking.show_days([{"year": y, "month": m, "day": 3, "free": false}, {"year": y, "month": m, "day": 9, "free": true}], _main._state, _main._loader)
	if grid._selected != 9:
		_fail("Go took day %d, not the first free one" % grid._selected)
	grid.show_month(y, m)


## B6: a call counts only from the month the request came.
func _check_a_call_counts_from_the_request() -> void:
	var ns = _main._state.player()
	var row := Audiences.request(ns, _request_id)
	var pid := String(row["person_id"])
	var arrived := int(row["arrived_month"])
	ns.phone_calls[pid] = arrived - 1
	if AudienceDriver._called(_main, row) != 0:
		_fail("a call before the request came is said on its card")
	ns.phone_calls[pid] = arrived
	if AudienceDriver._called(_main, row) != arrived:
		_fail("a call in the month it came is not said")
	ns.phone_calls.erase(pid)


func _click(down: bool) -> void:
	var cell := _cell(int(_date["day"]))
	if cell == null:
		_fail("premise: the day to click is not on the grid")
		return
	Click.half(_main.get_viewport(), cell, down)


func _check_booked() -> void:
	var row := Audiences.request(_main._state.player(), _request_id)
	var booked: Dictionary = row.get("date", {})
	if String(row.get("status", "")) != "booked":
		_fail("the click did not book the request (%s)" % row.get("status", ""))
	elif int(booked.get("day", 0)) != int(_date["day"]) or int(booked.get("month", 0)) != int(_date["month"]):
		_fail("the click booked %s, not its own day %s" % [booked, _date])


## A day of the armed window the diary holds: no tint, its click picks it and says why, and
## nothing is booked (the cell's click, not a dead one: V5.1's lesson).
func _check_taken_day() -> void:
	var grid = _main._calendar_panel._grid
	var free := _free(_other)
	if free.is_empty():
		_fail("premise: the second request has no free day")
		return
	var day: Dictionary = free[0]
	var blocker := Calendar.make_entry(CalendarK.KIND_RESHUFFLE, int(day["year"]), int(day["month"]), int(day["day"]), "", "", "", "qa_taken", "")
	Calendar.book(_main._state, blocker)
	AudienceDriver._open_booking(_main, _other)
	grid.show_month(int(day["year"]), int(day["month"]))
	var cell := _cell(int(day["day"]))
	if cell == null or bool(cell.tinted):
		_fail("a day the diary holds is tinted as one that books")
	grid._on_day(int(day["day"]))
	if String(Audiences.request(_main._state.player(), _other).get("status", "")) != "pending":
		_fail("a click on a held day booked the request")
	if int(grid._selected) != int(day["day"]):
		_fail("a click on a held day did not pick it (%d)" % grid._selected)
	var why := ""
	for d in Audiences.offered_dates(_main._state, _main._state.player(), _other):
		if int(d["year"]) == int(day["year"]) and int(d["month"]) == int(day["month"]) and int(d["day"]) == int(day["day"]):
			why = String(d.get("reason", ""))
	var said := false
	for label in grid.day_list.find_children("*", "Label", true, false):
		said = said or (why != "" and String((label as Label).text).ends_with(tr(why)))
	if not said:
		_fail("the held day's list does not say why it cannot be booked")
	Calendar.cancel(_main._state, Calendar.verb_key(blocker))
	grid.arm({})


## QA's TAKE T1 on #431: only a day the clock turned is rebooked; a day the diary holds is
## refused, and the request stays waiting.
func _check_taken_not_rebooked() -> void:
	var free := _free(_other)
	if free.is_empty():
		_fail("premise: the second request has no free day")
		return
	var day: Dictionary = free[0]
	var blocker := Calendar.make_entry(CalendarK.KIND_RESHUFFLE, int(day["year"]), int(day["month"]), int(day["day"]), "", "", "", "qa_t1", "")
	Calendar.book(_main._state, blocker)
	_main._calendar_panel._grid.booked.emit(_other, day)
	if String(Audiences.request(_main._state.player(), _other).get("status", "")) != "pending":
		_fail("a booking on a day the diary holds booked another day (%s)" % Audiences.request(_main._state.player(), _other).get("status", ""))
	Calendar.cancel(_main._state, Calendar.verb_key(blocker))


func _go() -> void:
	var lane = AudienceDriver.lane_of(_main)
	var answers: Array = lane._answers_of.get(_other, [])
	if answers.is_empty() or String(answers[0]["label"]) != tr("Go"):
		_fail("the inbox card's first answer is not Go: %s" % [answers])
	# The Go from the keys: only that route hands the keyboard a day (the #427 ruling).
	var enter := InputEventKey.new()
	enter.keycode = KEY_ENTER
	enter.pressed = true
	_main._calendar_panel.people._input(enter)
	lane.book_requested.emit(_other)


func _check_focus() -> void:
	var owner := root.gui_get_focus_owner()
	var first: Dictionary = _free(_other)[0]
	if owner == null or String(owner.name) != "Day_%d" % int(first["day"]):
		_fail("Go left the focus on %s, not on the first free day" % (owner.name if owner != null else "nothing"))
	if String(_main._calendar_panel._grid.armed.get("id", "")) != _other:
		_fail("Go did not arm the request")
	var grid = _main._calendar_panel._grid
	var shown: Vector2i = grid._shown()
	if shown != Vector2i(int(first["year"]), int(first["month"])) or grid._selected != int(first["day"]):
		_fail("Go did not turn the Diary to the first free day %s (shown %s, day %d)" % [first, shown, grid._selected])


func _click_book(down: bool) -> void:
	if _held == null or not is_instance_valid(_held):
		_fail("premise: the second request's day went with the day's turn")
		return
	Click.half(_main.get_viewport(), _held, down)


## A pick shown to the player still books after the day turns: the first free day, never "passed".
func _check_turned_day_booked() -> void:
	var row := Audiences.request(_main._state.player(), _other)
	var date: Dictionary = row.get("date", {})
	if String(row.get("status", "")) != "booked":
		_fail("a day pressed as the clock turned it did not book (%s)" % row.get("status", ""))
	elif int(date.get("year", 0)) * 10000 + int(date.get("month", 0)) * 100 + int(date.get("day", 0)) \
			<= int(_main._state.year) * 10000 + int(_main._state.month) * 100 + int(_main._state.day):
		_fail("the turned day booked %s, today or before" % [date])


func _check_unheld_turn_repicked() -> void:
	var grid = _main._calendar_panel._grid
	if grid._selected <= int(_main._state.day) or String(grid.armed.get("id", "")) != _other:
		_fail("with nothing in hand, the turned day stayed picked (day %d, today %d) or the request is no longer armed" % [grid._selected, int(_main._state.day)])


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
