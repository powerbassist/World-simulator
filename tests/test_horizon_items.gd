extends SceneTree

## Headless test: godot --headless --script res://tests/test_horizon_items.gd
## Non-zero exit on any failure.
##
## The horizon's read (src/ui/horizon_items.gd, V5.3 bar C): the DATED things the
## ribbon draws. What can fail silently is the arithmetic of "when": a request's last
## answerable month is its deadline_month MINUS ONE (audience_driver and the diary say
## so; the sim lapses it as the deadline month begins), a desk decision's is now +
## months_left - 1 (Events counts months_left down at each month tick and lapses at 0),
## and a due outside the three-month window or already past is not drawn. An off-by-one
## here prints a lapse a month late, which no walk of the screen would notice.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Items = preload("res://src/ui/horizon_items.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const AudienceK = preload("res://src/sim/audience_constants.gd")
const Trends = preload("res://src/ui/trends.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return
	var state = GameState.new_game(loader, "FRA")
	state.day = 10
	_check_requests(state, loader)
	_check_the_desk(state, loader)
	_check_bookings(state, loader)
	_check_the_vote(state, loader)
	_finish()


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _request(ns, person_id: String, deadline: int, status := AudienceK.STATUS_PENDING) -> void:
	ns.audience_requests.append({"id": "%s|%d" % [person_id, deadline], "person_id": person_id, "object": "programme:x",
		"stance": "oppose", "arrived_month": deadline - 2, "deadline_month": deadline, "status": status, "date": {},
		"resolved_month": -1, "offer": {}})


func _check_requests(state, loader) -> void:
	var ns = state.player()
	ns.audience_requests.clear()
	var now := _now(state)
	_request(ns, "FRA_lachapelle", now + 2)
	var dues: Array = Items.read(state, loader)["dues"]
	if dues.size() != 1 or int(dues[0]["abs_month"]) != now + 1:
		_fail("a request with deadline_month now+2 is last answerable in now+1 (the month BEFORE its deadline); read %s" % [dues])
		return
	if String(dues[0]["person_id"]) != "FRA_lachapelle" or String(dues[0]["who"]) != loader.person_name("FRA_lachapelle"):
		_fail("a lone request's chip does not carry its person: %s" % [dues[0]])
	if not Items.due_text(dues[0]).contains("[p=FRA_lachapelle]"):
		_fail("a lone request's words do not link its person: %s" % Items.due_text(dues[0]))
	# Two in one month are one group: a count, no name, no link.
	_request(ns, "FRA_vasseur", now + 2)
	dues = Items.read(state, loader)["dues"]
	if dues.size() != 1 or int(dues[0]["count"]) != 2 or String(dues[0]["person_id"]) != "":
		_fail("two requests lapsing in one month are not one counted group: %s" % [dues])
	if Items.due_text(dues[0]).contains("[p="):
		_fail("a group of two links one person's name: %s" % Items.due_text(dues[0]))
	# Outside the window (three months: this, next, the one after) and already past: not drawn.
	ns.audience_requests.clear()
	_request(ns, "FRA_lachapelle", now + Items.MONTHS + 1)  # last answerable now+3: one past the window
	_request(ns, "FRA_vasseur", now)  # last answerable now-1: past
	_request(ns, "FRA_turcy", now + 2, AudienceK.STATUS_BOOKED)  # booked, not pending: nothing lapses
	if not (Items.read(state, loader)["dues"] as Array).is_empty():
		_fail("a due outside the window, a past one or a booked request was drawn: %s" % [Items.read(state, loader)["dues"]])
	ns.audience_requests.clear()


func _check_the_desk(state, loader) -> void:
	var ns = state.player()
	var now := _now(state)
	var ev = loader.events[0]
	ns.event_queue.clear()
	ns.event_queue.append({"event_id": String(ev.id), "months_left": 1, "severity": 1})
	var dues: Array = Items.read(state, loader)["dues"]
	if dues.size() != 1 or int(dues[0]["abs_month"]) != now:
		_fail("a decision with 1 month left must be answered THIS month (it decides itself at the next tick); read %s" % [dues])
	ns.event_queue.clear()
	ns.event_queue.append({"event_id": String(ev.id), "months_left": Items.MONTHS, "severity": 1})
	dues = Items.read(state, loader)["dues"]
	if dues.size() != 1 or int(dues[0]["abs_month"]) != now + Items.MONTHS - 1:
		_fail("months_left = MONTHS lands in the window's last month; read %s" % [dues])
	ns.event_queue.clear()
	ns.event_queue.append({"event_id": String(ev.id), "months_left": Items.MONTHS + 1, "severity": 1})
	if not (Items.read(state, loader)["dues"] as Array).is_empty():
		_fail("a decision that lapses beyond the window was drawn")
	ns.event_queue.clear()


func _check_bookings(state, loader) -> void:
	state.appointments.clear()
	var year := int(state.year)
	var month := int(state.month)
	var visit := Calendar.make_entry(CalendarK.KIND_DIPLOMATIC, year, month, 16, "state_visit", "DEU", "", "", "", "DEU_vogler", 2)
	var yesterday := Calendar.make_entry(CalendarK.KIND_ADDRESS, year, month, 5)
	var far := Calendar.make_entry(CalendarK.KIND_ADDRESS, year + 1, month, 5)
	for e in [visit, yesterday, far]:
		state.appointments.append(e)
	var rows: Array = Items.read(state, loader)["bookings"]
	if rows.size() != 1:
		_fail("only the booking inside [today, today + 3 months) is read; got %d rows" % rows.size())
		return
	if int(rows[0]["day"]) != 16 or int(rows[0]["travel_days"]) != 2:
		_fail("the booking lost its meeting day or its travel days: %s" % [rows[0]])
	if String(rows[0]["act"]) == CalendarK.KIND_DIPLOMATIC or String(rows[0]["act"]).is_empty():
		_fail("a booking is named by its raw kind or not at all: '%s'" % rows[0]["act"])
	# An audience booking links its person; any other booking links nobody.
	state.appointments.clear()
	state.appointments.append(Calendar.make_entry(CalendarK.KIND_AUDIENCE, year, month, 20, "", "", "", "", "", "FRA_vasseur", 0))
	rows = Items.read(state, loader)["bookings"]
	if rows.size() != 1 or String(rows[0]["person_id"]) != "FRA_vasseur" or not Items.booking_text(rows[0]).contains("[p=FRA_vasseur]"):
		_fail("an audience booking does not link its person: %s" % [rows])
	state.appointments.clear()


func _check_the_vote(state, loader) -> void:
	var vote: Dictionary = Items.read(state, loader)["vote"]
	if int(vote["months"]) != Trends.months_to_vote(state, state.player()):
		_fail("the horizon's vote count (%d) and the strip's (%d) differ -- two clocks for one vote" % [
			int(vote["months"]), Trends.months_to_vote(state, state.player())])
	if Items.vote_text(vote) != "%02d/%d" % [int(vote["month"]), int(vote["year"])]:
		_fail("the vote's date is not MM/YYYY: %s" % Items.vote_text(vote))


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_horizon_items: all checks passed")
		quit(0)
		return
	for failure in _failures:
		printerr("FAIL: " + failure)
	quit(1)
