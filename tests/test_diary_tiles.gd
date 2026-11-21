extends SceneTree

## Headless test: godot --headless --script res://tests/test_diary_tiles.gd
## Non-zero exit on any failure.
##
## G3 S2, the Diary on Sheets on glass (g3-spec.md sections 2 and 5): the month as tiles.
##   - the weeks are whole: the days before the 1st and after the last are drawn, out of
##     month, dated, and take neither a click nor the keyboard;
##   - a visit's trip is one capsule per week row: round where the trip starts and ends,
##     square with a chevron where a week ends and the trip goes on; its legs are named
##     ("to <host>" on the way out, "back" on the way home) and the meeting day is a pill;
##     the pointer on any day of it lights every day of it, and only those;
##   - an armed person's free day carries a bookable place named for them ("See <name>");
##     a day of their window the diary holds says it is taken, with the reason;
##   - a booking just made is fresh: its appointment wears the check, and the accent has
##     drained (motion off headless: the final state at once);
##   - the people column's armed verb is the screen's main action (the accent fill), and
##     the file's four verbs share one button class, re-read on every redraw (RECORD H10).

const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _grid
var _request := ""
var _offered := {}


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_stage()
			AudienceDriver.refresh(_main)
			_main._windows.open("calendar")
		6:
			_grid = _main._calendar_panel.find_child("DiaryGrid", true, false)
			if _grid == null or _request == "":
				_fail("premise: no grid or no staged request")
				_finish()
				return true
			_check_whole_weeks()
			_check_trip()
			_check_places()
		8:
			_check_fresh()
			_finish()
			return true
	return false


func _stage() -> void:
	var state = _main._state
	var ns = state.player()
	var people: Array = _main._loader.people[String(ns.id)]
	for person in people.slice(4):
		var r := Audiences.invite(state, ns, _main._loader, String(person.id), "office:premiership", "wants")
		if bool(r.get("ok", false)):
			_request = String(r["request"]["id"])
			break
	var now := int(state.year) * 12 + int(state.month)
	for d in Audiences.offered_dates(state, ns, _request):
		if bool(d["free"]) and int(d["year"]) * 12 + int(d["month"]) > now:
			_offered = d
			break


func _check_whole_weeks() -> void:
	var at := _month(3)
	_grid.show_month(int(at["year"]), int(at["month"]))
	var cells: Array = _grid._days.get_children()
	if cells.size() % 7 != 0:
		_fail("the month's last week is not whole: %d tiles" % cells.size())
	var first := -1
	for i in cells.size():
		if String(cells[i].name) == "Day_1":
			first = i
	if first < 0:
		_fail("no Day_1 tile")
		return
	var prev_len := Calendar.days_in_month(int(at["year"]) - (1 if int(at["month"]) == 1 else 0), 12 if int(at["month"]) == 1 else int(at["month"]) - 1)
	for i in first:
		var c = cells[i]
		if not bool(c.get("outside")):
			_fail("the tile before the 1st at %d is not out of month" % i)
		elif int(c.day) != prev_len - first + 1 + i:
			_fail("the tile before the 1st at %d reads day %d, not %d" % [i, int(c.day), prev_len - first + 1 + i])
		if (c as Control).focus_mode != Control.FOCUS_NONE:
			_fail("an out-of-month tile takes the keyboard")
	var last = cells[cells.size() - 1]
	if cells.size() > first + Calendar.days_in_month(int(at["year"]), int(at["month"])) and (not bool(last.get("outside")) or int(last.day) > 7):
		_fail("the tile after the last day is not next month's start")


## A state visit on the 14th with two days' journey: days 12-16, out on 12-13, home on 15-16.
func _check_trip() -> void:
	var state = _main._state
	var at := _month(4)
	var visit := Calendar.make_entry(K.KIND_DIPLOMATIC, int(at["year"]), int(at["month"]), 14, "state_visit", "DEU", "", "", "", "", 2)
	state.appointments.append(visit)
	_main._calendar_panel._refresh()
	_grid.show_month(int(at["year"]), int(at["month"]))
	var host := String(_main._loader.nations["DEU"].nation_name)
	for d in range(12, 17):
		var c = _cell(d)
		var col: int = _grid._days.get_children().find(c) % 7
		var left := "cap" if d == 12 else ("chevron" if col == 0 else "join")
		var right := "cap" if d == 16 else ("chevron" if col == 6 else "join")
		if String(c.band_left) != left or String(c.band_right) != right:
			_fail("day %d's capsule ends read %s/%s, not %s/%s" % [d, c.band_left, c.band_right, left, right])
	if String(_cell(12).band_leg) != tr("to %s") % host:
		_fail("the way out reads '%s', not 'to %s'" % [_cell(12).band_leg, host])
	if String(_cell(15).band_leg) != tr("back"):
		_fail("the way home reads '%s', not 'back'" % _cell(15).band_leg)
	for d in [13, 14, 16]:
		if String(_cell(d).band_leg) != "":
			_fail("day %d names a leg: '%s'" % [d, _cell(d).band_leg])
	if not bool(_cell(14).band_meeting) or bool(_cell(13).band_meeting):
		_fail("the meeting pill is not on the meeting day alone")
	# The pointer on one day of the trip lights the whole trip, and nothing else.
	_cell(13).mouse_entered.emit()
	for d in range(12, 17):
		if not bool(_cell(d).band_hot):
			_fail("hovering the trip left day %d unlit" % d)
	if bool(_cell(11).band_hot) or bool(_cell(17).band_hot):
		_fail("hovering the trip lit a day off it")
	_cell(13).mouse_exited.emit()
	if bool(_cell(14).band_hot):
		_fail("the trip stayed lit after the pointer left")
	state.appointments.erase(visit)
	_main._calendar_panel._refresh()


func _check_places() -> void:
	var state = _main._state
	var ns = state.player()
	# A day of the window the diary holds: taken, with the reason.
	var held := {}
	for d in Audiences.offered_dates(state, ns, _request):
		if bool(d["free"]) and int(d["year"]) * 12 + int(d["month"]) == int(_offered["year"]) * 12 + int(_offered["month"]) and int(d["day"]) != int(_offered["day"]):
			held = d
			break
	var blocker = null
	if not held.is_empty():
		blocker = Calendar.make_entry(K.KIND_RESHUFFLE, int(held["year"]), int(held["month"]), int(held["day"]), "", "", "", "interior", "")
		state.appointments.append(blocker)
		_main._calendar_panel._refresh()
	var see := _main._calendar_panel.find_child("See_%s" % _request, true, false) as Button
	if see == null:
		_fail("the request has no See them")
		return
	if String(see.theme_type_variation) == UiTheme.PRIMARY:
		_fail("See them wears the main action's fill before it is armed")
	see.pressed.emit()
	_grid.show_month(int(_offered["year"]), int(_offered["month"]))
	var name: String = _main._loader.person_name(String(Audiences.request(ns, _request)["person_id"]))
	var surname := name.get_slice(" ", name.get_slice_count(" ") - 1)
	var cell = _cell(int(_offered["day"]))
	if cell == null or String(cell.offer) != tr("See %s") % surname:
		_fail("the free day's bookable place reads '%s', not 'See %s'" % [cell.offer if cell != null else "", surname])
	if blocker != null:
		var taken = _cell(int(held["day"]))
		if taken == null or String(taken.taken) == "":
			_fail("a day of the window the diary holds does not say it is taken")
		elif String(taken.offer) != "":
			_fail("a taken day still offers a place")
		state.appointments.erase(blocker)
	var armed := _main._calendar_panel.find_child("See_%s" % _request, true, false) as Button
	if armed == null or String(armed.theme_type_variation) != UiTheme.PRIMARY:
		_fail("the armed See them is not the screen's main action")
	_check_verb_class()
	# Book it as the click does.
	_grid._on_day(int(_offered["day"]))


## RECORD H10: the file's four verbs share one class, re-read on a redraw with other labels.
func _check_verb_class() -> void:
	var verbs: Array = []
	for key in ["See", "Call", "Delegate", "Decline"]:
		var b := _main._calendar_panel.find_child("%s_%s" % [key, _request], true, false) as Button
		if b == null:
			_fail("the file has no %s verb" % key)
			return
		verbs.append(b)
	var w: float = (verbs[0] as Button).custom_minimum_size.x
	for b in verbs:
		if not is_equal_approx((b as Button).custom_minimum_size.x, w):
			_fail("the file's verbs do not share one width: %s" % [verbs.map(func(v: Button) -> float: return v.custom_minimum_size.x)])
			return
	var widths: Array = PanelKit.BTN_W.values().map(func(x: int) -> float: return roundf(x * UiTheme.text_scale()))
	if not w in widths:
		_fail("the file's verbs are %.0f px, not a button class" % w)


func _check_fresh() -> void:
	var row := Audiences.request(_main._state.player(), _request)
	if String(row.get("status", "")) != "booked":
		_fail("premise: the booking did not land: %s" % row.get("status", ""))
		return
	_grid.show_month(int(_offered["year"]), int(_offered["month"]))
	var cell = _cell(int(_offered["day"]))
	if cell == null or not bool(cell.fresh):
		_fail("the appointment just booked is not fresh")
	elif not is_equal_approx(float(cell.drain), 1.0):
		_fail("motion off, the fresh appointment has not drained: %.2f" % float(cell.drain))
	if cell != null and String(cell.offer) != "":
		_fail("the booked day still offers a place")


func _cell(day: int):
	return _grid.find_child("Day_%d" % day, true, false)


func _month(offset: int) -> Dictionary:
	var total: int = int(_main._state.year) * 12 + int(_main._state.month) - 1 + offset
	return {"year": total / 12, "month": total % 12 + 1}


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_diary_tiles: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
