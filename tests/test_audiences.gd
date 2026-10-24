extends SceneTree

## Headless test: godot --headless --script res://tests/test_audiences.gd
## Non-zero exit on any failure.
##
## V5.2b, the requests (src/sim/audiences.gd; docs/audiences-model.md). What
## this file holds:
##
##   - SOMEONE ASKS, ON AN IDLE TERM (B1's first cut, the pre-mortem's cause 1):
##     a new France game run through WorldMonth with no input has a request in
##     the lane by month 3.
##   - THE THREE ANSWERS AND THE LAPSE PRICE ONCE, AND THE SAME: a lapse costs
##     exactly what a decline costs (B3), delegation a share of it, a no-show a
##     decline; nothing prices twice.
##   - THE DIARY IS THE SCARCITY (B2): a booking takes an offered day the diary
##     can place; when none can be placed, the card still offers delegation and
##     decline.
##   - DETERMINISM (I1), the cooldown, the cap, and the president never asking
##     themself.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const K = preload("res://src/sim/audience_constants.gd")
const President = preload("res://src/sim/president.gd")
const Characters = preload("res://src/sim/characters.gd")
const Programme = preload("res://src/sim/programme.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")

const PLAYER := "FRA"
const METERS := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_idle_term_first_request()
	_check_determinism()
	_check_cooldown_cap_and_the_president()
	_check_cooldown_silences_a_recent_asker()
	_check_a_full_lane_takes_no_one()
	_check_programme_choice_invites_its_people()
	_check_lapse_costs_what_a_decline_costs()
	_check_delegation_costs_a_share()
	_check_booking_takes_an_offered_day()
	_check_an_unplaceable_request_still_offers_the_rest()
	_check_a_booked_request_can_still_be_declined()
	_check_a_decline_at_the_ceiling_still_costs()
	_check_a_no_show_is_a_decline()
	_check_rows_round_trip_with_int_months()

	_finish()


## B1's first cut through the game's own month: requests are counted where the
## inbox reads them, the register itself.
func _check_idle_term_first_request() -> void:
	var state = _game()
	var arrived := 0
	for m in range(3):
		var report: Dictionary = WorldMonth.tick_month(state, _loader)
		arrived += (report.get("audience_requests", {}).get("arrived", []) as Array).size()
		_advance(state)
	if arrived == 0 or Audiences.pending(state.player()).is_empty():
		_fail("an idle France term had no request in the lane by month 3 (%d arrived)" % arrived)


func _check_determinism() -> void:
	var a = _game()
	var b = _game()
	_run(a, 24)
	_run(b, 24)
	if var_to_str(a.player().audience_requests) != var_to_str(b.player().audience_requests):
		_fail("two identical states produced different requests")
	if a.player().audience_requests.is_empty():
		_fail("24 idle months produced no request at all -- the determinism check compared nothing")


func _check_cooldown_cap_and_the_president() -> void:
	var state = _game()
	var ns = state.player()
	var leader := President.leader_id(ns)
	for m in range(36):
		Audiences.tick_month(state, _loader, METERS)
		var open := 0
		for row in ns.audience_requests:
			if [K.STATUS_PENDING, K.STATUS_BOOKED].has(String(row["status"])):
				open += 1
		if open > K.MAX_PENDING:
			_fail("month %d: %d requests open, the cap is %d" % [m, open, K.MAX_PENDING])
		_advance(state)
	var last := {}
	for row in ns.audience_requests:
		var pid := String(row["person_id"])
		if pid == leader:
			_fail("the president asked themself for an audience")
		var at := int(row["arrived_month"])
		if last.has(pid) and at - int(last[pid]) < K.REQUEST_COOLDOWN_MONTHS:
			_fail("%s asked at %d and again at %d, inside the %d-month cooldown" % [pid, last[pid], at, K.REQUEST_COOLDOWN_MONTHS])
		last[pid] = at


## The cooldown, forced: everyone asked last month, so for the rest of the
## cooldown nobody asks -- and the month it ends, the hazard is free again.
func _check_cooldown_silences_a_recent_asker() -> void:
	var state = _game()
	var ns = state.player()
	for person in _loader.people[PLAYER]:
		ns.audience_asked_month[String(person.id)] = _now(state) - 1
	for m in range(K.REQUEST_COOLDOWN_MONTHS - 1):
		var report: Dictionary = Audiences.tick_month(state, _loader, METERS)
		if not (report["arrived"] as Array).is_empty():
			_fail("month %d of the cooldown: %s asked anyway" % [m, report["arrived"][0]["person_id"]])
			return
		_advance(state)


## The lane's cap, forced: four open requests and nobody else is let in.
func _check_a_full_lane_takes_no_one() -> void:
	var state = _game()
	var ns = state.player()
	for i in range(K.MAX_PENDING):
		ns.audience_requests.append({"id": "fixture|%d" % i, "person_id": "FRA_fixture_%d" % i,
			"object": "meter:grievance", "stance": "demand", "arrived_month": _now(state),
			"deadline_month": _now(state) + 12, "status": K.STATUS_PENDING, "date": {}, "resolved_month": -1})
	for m in range(6):
		var report: Dictionary = Audiences.tick_month(state, _loader, METERS)
		if not (report["arrived"] as Array).is_empty():
			_fail("a full lane took %s in month %d" % [report["arrived"][0]["person_id"], m])
			return
		_advance(state)


## A programme choice invites the people whose wants name its entry, the month
## it goes live, outside the hazard -- the spec's second trigger.
func _check_programme_choice_invites_its_people() -> void:
	var state = _game()
	var ns = state.player()
	var entry_id := ""
	var askers: Array[String] = []
	for entry in Programme.available(state, ns, _loader):
		askers.clear()
		for person in _loader.people[PLAYER]:
			if person.id == President.leader_id(ns):
				continue
			for want in person.wants:
				if String(want["object"]) == "programme:%s" % entry["id"]:
					askers.append(String(person.id))
		if not askers.is_empty():
			entry_id = String(entry["id"])
			break
	if entry_id == "":
		_fail("no offerable programme entry has a person whose want names it -- the fixture lost its case")
		return
	Programme.choose(state, ns, entry_id, _loader)
	Programme.tick_month(state, _loader)
	Audiences.tick_month(state, _loader, METERS)
	var asked := false
	for row in ns.audience_requests:
		if askers.has(String(row["person_id"])) and String(row["object"]) == "programme:%s" % entry_id:
			asked = true
	if not asked:
		_fail("choosing %s invited none of %s" % [entry_id, askers])


func _check_lapse_costs_what_a_decline_costs() -> void:
	var lapsed = _game_with_request()
	var declined = _game_with_request()
	if lapsed.is_empty() or declined.is_empty():
		return
	var pid := String(lapsed["row"]["person_id"])
	var before := _person_registers(lapsed["state"].player(), pid)
	var price: Dictionary = Audiences.decline_price(declined["state"].player(), _loader, String(declined["row"]["id"]))
	var result: Dictionary = Audiences.decline(declined["state"], declined["state"].player(), _loader, String(declined["row"]["id"]))
	if not bool(result.get("ok", false)):
		_fail("decline refused: %s" % [result])
		return
	# Let the other one lapse: tick past its deadline, answering nothing.
	var st = lapsed["state"]
	while _now(st) <= int(lapsed["row"]["deadline_month"]):
		_advance(st)
		Audiences.tick_month(st, _loader, METERS)
	var row: Dictionary = Audiences.request(st.player(), String(lapsed["row"]["id"]))
	if String(row.get("status", "")) != K.STATUS_LAPSED:
		_fail("an unanswered request past its window reads '%s', not lapsed" % row.get("status", ""))
	var after_lapse := _person_registers(st.player(), pid)
	var after_decline := _person_registers(declined["state"].player(), pid)
	for key in ["grudge", "loyalty", "rapport"]:
		var lapse_cost := float(after_lapse[key]) - float(before[key])
		var decline_cost := float(after_decline[key]) - float(before[key])
		if not is_equal_approx(lapse_cost, decline_cost):
			_fail("%s: a lapse cost %.4f and a decline %.4f -- the author's call makes them equal" % [key, lapse_cost, decline_cost])
		if not is_equal_approx(decline_cost, float(price[key])):
			_fail("%s: decline_price promised %.4f and the decline wrote %.4f" % [key, float(price[key]), decline_cost])
	if is_equal_approx(float(after_decline["grudge"]), float(before["grudge"])):
		_fail("a decline wrote no grudge -- refusing cost nothing (B3)")
	# Once: more months change nothing more for this request.
	var settled := _person_registers(st.player(), pid)
	Audiences.tick_month(st, _loader, METERS)
	if _person_registers(st.player(), pid)["rapport"] != settled["rapport"]:
		_fail("a lapsed request priced again a month later")
	if bool(Audiences.decline(declined["state"], declined["state"].player(), _loader, String(declined["row"]["id"])).get("ok", true)):
		_fail("a request declined twice was accepted twice")


func _check_delegation_costs_a_share() -> void:
	var case = _game_with_request()
	if case.is_empty():
		return
	var ns = case["state"].player()
	var pid := String(case["row"]["person_id"])
	var before := _person_registers(ns, pid)
	var full: Dictionary = Audiences.decline_price(ns, _loader, String(case["row"]["id"]))
	var result: Dictionary = Audiences.delegate(case["state"], ns, _loader, String(case["row"]["id"]))
	if not bool(result.get("ok", false)):
		_fail("delegate refused: %s" % [result])
		return
	var grudge := float(_person_registers(ns, pid)["grudge"]) - float(before["grudge"])
	if not is_equal_approx(grudge, float(full["grudge"]) * K.DELEGATE_GRUDGE_SHARE):
		_fail("delegation wrote grudge %.4f, wanted %.4f" % [grudge, float(full["grudge"]) * K.DELEGATE_GRUDGE_SHARE])
	if String(Audiences.request(ns, String(case["row"]["id"]))["status"]) != K.STATUS_DELEGATED:
		_fail("a delegated request does not read delegated")


func _check_booking_takes_an_offered_day() -> void:
	var case = _game_with_request()
	if case.is_empty():
		return
	var state = case["state"]
	var ns = state.player()
	var id := String(case["row"]["id"])
	var dates: Array[Dictionary] = Audiences.offered_dates(state, ns, id)
	if dates.size() != K.OFFERED_DATES:
		_fail("a request offered %d dates, not %d" % [dates.size(), K.OFFERED_DATES])
		return
	var free := {}
	for d in dates:
		if bool(d["free"]):
			free = d
			break
	if free.is_empty():
		_fail("an empty diary could place none of %s" % [dates])
		return
	for day in range(28, 0, -1):
		var offered := false
		for d in dates:
			if int(d["year"]) == int(free["year"]) and int(d["month"]) == int(free["month"]) and int(d["day"]) == day:
				offered = true
		if not offered:
			var other := {"year": int(free["year"]), "month": int(free["month"]), "day": day}
			if bool(Audiences.book(state, ns, _loader, id, other).get("ok", true)):
				_fail("a booking on a day the person did not offer was accepted")
			break
	var result: Dictionary = Audiences.book(state, ns, _loader, id, free)
	if not bool(result.get("ok", false)):
		_fail("booking a free offered day was refused: %s" % [result])
		return
	var entries := 0
	for e in state.appointments:
		if String(e["kind"]) == CalendarK.KIND_AUDIENCE and String(e["action_id"]) == id:
			entries += 1
	if entries != 1 or String(Audiences.request(ns, id)["status"]) != K.STATUS_BOOKED:
		_fail("a booking left %d diary entries and status '%s'" % [entries, Audiences.request(ns, id)["status"]])
	if bool(Audiences.book(state, ns, _loader, id, free).get("ok", true)):
		_fail("a booked request was booked a second time")


## B2's 100 % row: every offered day taken, and the card still answers.
func _check_an_unplaceable_request_still_offers_the_rest() -> void:
	var case = _game_with_request()
	if case.is_empty():
		return
	var state = case["state"]
	var ns = state.player()
	var id := String(case["row"]["id"])
	for d in Audiences.offered_dates(state, ns, id):
		# A reshuffle booked on the day takes it: one thing at a time.
		var blocker := Calendar.make_entry(CalendarK.KIND_RESHUFFLE, int(d["year"]), int(d["month"]), int(d["day"]),
			"", "", "", "p%d" % int(d["day"]), "")
		Calendar.book(state, blocker)
	var answers: Dictionary = Audiences.answers(state, ns, _loader, id)
	if bool(answers["book"]["ok"]) or String(answers["book"]["reason"]) == "":
		_fail("with every offered day taken, book still read %s" % [answers["book"]])
	if not bool(answers["delegate"]["ok"]) or not bool(answers["decline"]["ok"]):
		_fail("an unplaceable request did not offer delegation and decline: %s" % [answers])


## A booked audience can still be declined from the card, and the day goes back.
func _check_a_booked_request_can_still_be_declined() -> void:
	var case = _game_with_request()
	if case.is_empty():
		return
	var state = case["state"]
	var ns = state.player()
	var id := String(case["row"]["id"])
	for d in Audiences.offered_dates(state, ns, id):
		if bool(d["free"]) and bool(Audiences.book(state, ns, _loader, id, d)["ok"]):
			break
	var answers: Dictionary = Audiences.answers(state, ns, _loader, id)
	if bool(answers["book"]["ok"]) or not bool(answers["decline"]["ok"]) or not bool(answers["delegate"]["ok"]):
		_fail("a booked request's card read %s -- decline and delegate stay open, book does not" % [answers])
	Audiences.decline(state, ns, _loader, id)
	for e in state.appointments:
		if String(e["action_id"]) == id and String(e["status"]) == CalendarK.STATUS_BOOKED:
			_fail("a declined audience kept its day in the diary")


## B3's 100 % row at the edge: a person already at the refusal ceiling takes no
## more grudge, and the decline still writes a change the card can name.
func _check_a_decline_at_the_ceiling_still_costs() -> void:
	var case = _game_with_request()
	if case.is_empty():
		return
	var ns = case["state"].player()
	var pid := String(case["row"]["person_id"])
	ns.person_grudges[pid] = 0.95
	var before := _person_registers(ns, pid)
	Audiences.decline(case["state"], ns, _loader, String(case["row"]["id"]))
	var after := _person_registers(ns, pid)
	if after["grudge"] != before["grudge"]:
		_fail("a refusal lifted a grudge already past the ceiling: %.3f -> %.3f" % [before["grudge"], after["grudge"]])
	if after["rapport"] == before["rapport"] and after["loyalty"] == before["loyalty"]:
		_fail("a decline at the ceiling wrote no change at all -- B3's 100 % row")


func _check_a_no_show_is_a_decline() -> void:
	var case = _game_with_request()
	if case.is_empty():
		return
	var state = case["state"]
	var ns = state.player()
	var id := String(case["row"]["id"])
	var pid := String(case["row"]["person_id"])
	var price: Dictionary = Audiences.decline_price(ns, _loader, id)
	var date := {}
	for d in Audiences.offered_dates(state, ns, id):
		if bool(d["free"]):
			date = d
			break
	if date.is_empty() or not bool(Audiences.book(state, ns, _loader, id, date).get("ok", false)):
		_fail("the no-show fixture could not book")
		return
	var before := _person_registers(ns, pid)
	# Never held: run months until the one after the date.
	while _now(state) <= int(date["year"]) * 12 + int(date["month"]):
		_advance(state)
		Audiences.tick_month(state, _loader, METERS)
	if String(Audiences.request(ns, id)["status"]) != K.STATUS_LAPSED:
		_fail("an audience never held reads '%s', not lapsed" % Audiences.request(ns, id)["status"])
	var grudge := float(_person_registers(ns, pid)["grudge"]) - float(before["grudge"])
	if grudge < float(price["grudge"]) - 0.0001:
		_fail("a no-show cost grudge %.4f, less than the decline's %.4f" % [grudge, float(price["grudge"])])


func _check_rows_round_trip_with_int_months() -> void:
	var case = _game_with_request()
	if case.is_empty():
		return
	var ns = case["state"].player()
	var loaded = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	var row: Dictionary = Audiences.request(loaded, String(case["row"]["id"]))
	for key in ["arrived_month", "deadline_month", "resolved_month"]:
		if typeof(row.get(key)) != TYPE_INT:
			_fail("%s came back from JSON as %s, not an int" % [key, type_string(typeof(row.get(key)))])
	if Audiences.pending(loaded).size() != Audiences.pending(ns).size():
		_fail("the lane changed size across a save")


# --- fixtures ----------------------------------------------------------------

## A new France game with its clock set, the way the game's own clock starts.
func _game():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 1
	state.day = 1
	return state


## A game ticked (Audiences alone) until its first request arrives:
## {state, row}, or {} with a failure if none comes in two years.
func _game_with_request() -> Dictionary:
	var state = _game()
	for m in range(24):
		Audiences.tick_month(state, _loader, METERS)
		var lane: Array[Dictionary] = Audiences.pending(state.player())
		if not lane.is_empty():
			_advance(state)
			return {"state": state, "row": lane[0]}
		_advance(state)
	_fail("no request arrived in 24 months")
	return {}


func _run(state, months: int) -> void:
	for m in range(months):
		Audiences.tick_month(state, _loader, METERS)
		_advance(state)


func _person_registers(ns, pid: String) -> Dictionary:
	return {
		"grudge": float(ns.person_grudges.get(pid, 0.0)),
		"loyalty": float(ns.person_loyalty.get(pid, 0.0)),
		"rapport": President.rapport(ns, pid),
	}


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	state.day = 1


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_audiences: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
