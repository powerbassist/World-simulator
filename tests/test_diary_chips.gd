extends SceneTree

## V5.3 b, step 6 (docs/design/v5.3-ab.md section 5, "booking moves into the grid"), as the
## parent ruled with "N'importe quel jour libre" (2026-11-20, option a): every day a request can
## be booked on is tinted and wears NO chip (a chip on every day of the window was a wall of
## faces); a click on the day lists its "Book here", which books THAT day. The faces return
## with the Diary's redraw (the author's pick A, Interface's card).
##   - a day of the window is tinted, with no chip on the grid;
##   - a real click on the day's Book here books that very date, not the first offered;
##   - DiaryDay's chip, set by hand: a refused day's is disabled with the sim's reason, and a
##     click on it picks the day rather than dying (a dead click, V5.1's lesson);
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
			_click_refused(true)
		14:
			_click_refused(false)
		16:
			_check_refused_clicked()
		18:
			_go()
		28:
			_check_focus()
			# #431 pass 2 TAKE 1: the clock turns the picked day into today under the player's
			# hand (the keyboard stands on Book here, so the grid's daily redraw waits).
			_main._clock.advance_one_day()
		30:
			_click_book(true)
		32:
			_click_book(false)
		34:
			_check_turned_day_booked()
			_main._windows.close("calendar")
		36:
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


func _book_here(id: String) -> Button:
	return _main._calendar_panel._grid.day_list.find_child("BookHere_%s" % id, true, false) as Button


func _chip(id: String, day: int) -> Button:
	var cell := _cell(day)
	return cell.find_child("Chip_%s" % id, true, false) as Button if cell != null else null


func _check_chips() -> void:
	if _main._calendar_panel.find_child("DiaryRequests", true, false) != null:
		_fail("the request column beside the grid is still there")
	if _request_id == "":
		return
	var cell := _cell(int(_date["day"]))
	if cell == null or not bool(cell.tinted):
		_fail("a day the request can be booked on is not tinted")
	if _chip(_request_id, int(_date["day"])) != null:
		_fail("a chip is back on the grid: every day of the window would wear one")
	_check_the_later_count()
	_check_go_takes_the_first_free_day()
	_check_a_call_counts_from_the_request()
	_main._calendar_panel._grid.pick(int(_date["year"]), int(_date["month"]), int(_date["day"]))


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
	var book := _book_here(_request_id)
	if book == null:
		_fail("premise: the picked day lists no Book here before its click")
		return
	Click.half(_main.get_viewport(), book, down)


func _check_booked() -> void:
	var row := Audiences.request(_main._state.player(), _request_id)
	var booked: Dictionary = row.get("date", {})
	if String(row.get("status", "")) != "booked":
		_fail("the click did not book the request (%s)" % row.get("status", ""))
	elif int(booked.get("day", 0)) != int(_date["day"]) or int(booked.get("month", 0)) != int(_date["month"]):
		_fail("the click booked %s, not its own day %s" % [booked, _date])


## A refused day, set on a cell by hand: the chip shows, disabled, and passes the click on.
func _check_refused() -> void:
	var grid = _main._calendar_panel._grid
	var cell := _cell(1)
	var row := {"id": "req|1", "person": "Someone", "wants": "wants a thing", "by": "MAR 2027"}
	var date := {"year": 2026, "month": 2, "day": 1, "free": false, "reason": "This day is taken."}
	cell.show_chips([{"id": "req|1", "person_id": "", "person": "Someone", "date": date}], {"req|1": row}, grid.booked)
	var chip := _chip("req|1", 1)
	if chip == null or not chip.disabled or not chip.tooltip_text.contains(tr("This day is taken.")):
		_fail("a refused day's chip is not disabled with the sim's reason")
	elif chip.mouse_filter != Control.MOUSE_FILTER_PASS:
		_fail("a disabled chip swallows the click on its day")


func _click_refused(down: bool) -> void:
	var chip := _chip("req|1", 1)
	if chip != null:
		Click.half(_main.get_viewport(), chip, down)


## The real click, through the chip and its box to the cell: the day is picked and listed.
func _check_refused_clicked() -> void:
	if _main._calendar_panel._grid._selected != 1:
		_fail("a click on a refused chip did not pick its day (%d)" % _main._calendar_panel._grid._selected)


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


func _click_book(down: bool) -> void:
	var book := _book_here(_other)
	if book == null:
		_fail("premise: Book here for the second request went with the day's turn")
		return
	Click.half(_main.get_viewport(), book, down)


## A pick shown to the player still books after the day turns: the first free day, never "passed".
func _check_turned_day_booked() -> void:
	var row := Audiences.request(_main._state.player(), _other)
	var date: Dictionary = row.get("date", {})
	if String(row.get("status", "")) != "booked":
		_fail("Book here pressed after the day turned did not book (%s)" % row.get("status", ""))
	elif int(date.get("year", 0)) * 10000 + int(date.get("month", 0)) * 100 + int(date.get("day", 0)) \
			<= int(_main._state.year) * 10000 + int(_main._state.month) * 100 + int(_main._state.day):
		_fail("the turned day booked %s, today or before" % [date])


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
