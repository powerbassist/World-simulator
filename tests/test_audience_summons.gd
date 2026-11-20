extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_summons.gd
## Non-zero exit on any failure.
##
## The summons (the author's "Oui, petite carte à part" and "Toute personne du pays",
## 2026-11-20; Design's audiences read, section 3): the president may ask to see any person
## of his nation who has asked nothing. src/sim/audience_summons.gd. What this file holds:
##   - a summons books a day and is no ask: the lane's cap and the person's own cooldown
##     are untouched, and the person may still ask;
##   - who cannot be summoned, and why, as data: the president, staff, a foreign head,
##     anyone with an open request, anyone summoned in the last SUMMON_COOLDOWN_MONTHS;
##     and the day's own reasons (no day, passed, too far, taken);
##   - the meeting: received (rapport + RECEIVED_RAPPORT, a little learned), talk only --
##     every lever and every deal verb refused, a topic talked -- and it ends settled,
##     unpriced;
##   - a missed one and a cancelled one cost nothing and give the day back;
##   - the stamp survives a save.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const AudienceLane = preload("res://src/sim/audience_lane.gd")
const K = preload("res://src/sim/audience_constants.gd")
const President = preload("res://src/sim/president.gd")
const Levers = preload("res://src/sim/levers.gd")
const Deal = preload("res://src/sim/deal.gd")
const Phone = preload("res://src/sim/phone.gd")
const Staff = preload("res://src/sim/staff.gd")
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
	_check_a_summons_books_a_day_and_is_no_ask()
	_check_who_cannot_be_summoned()
	_check_the_days_reasons()
	_check_the_meeting_is_talk_and_unpriced()
	_check_a_missed_summons_costs_nothing()
	_check_a_cancelled_summons_costs_nothing()
	_check_the_stamp_survives_a_save()
	_finish()


func _check_a_summons_books_a_day_and_is_no_ask() -> void:
	var state = _game()
	var ns = state.player()
	var pid := _own_quiet(state)
	var open_before := AudienceLane.open_count(ns, true)
	var r: Dictionary = Audiences.summon(state, ns, _loader, pid, _day(state, 20))
	if not bool(r.get("ok", false)):
		_fail("a summons of a quiet person of the nation was refused: %s" % [r])
		return
	var row := Audiences.request(ns, String(r["request"]["id"]))
	if String(row.get("status", "")) != K.STATUS_BOOKED or String(row.get("object", "")) != K.SUMMON_OBJECT:
		_fail("a summons reads %s, not a booked summons" % [row])
	var entries := 0
	for e in state.appointments:
		if String(e["kind"]) == CalendarK.KIND_AUDIENCE and String(e["action_id"]) == String(row["id"]):
			entries += 1
	if entries != 1:
		_fail("a summons left %d diary entries, not 1" % entries)
	if AudienceLane.open_count(ns, true) != open_before:
		_fail("a summons took a place in the lane (%d -> %d)" % [open_before, AudienceLane.open_count(ns, true)])
	if ns.audience_asked_month.has(pid):
		_fail("a summons stamped the person as having asked")
	if int(ns.audience_summoned_month.get(pid, -1)) != _now(state):
		_fail("a summons did not stamp its month: %s" % [ns.audience_summoned_month])
	# Pass 1 on #432: the briefing counts acted_month as a request answered; a summons answers none.
	for raw in ns.audience_requests:
		if String(raw["id"]) == String(row["id"]) and raw.has("acted_month"):
			_fail("a summons carries acted_month, which the briefing counts as an answered request")
	# The card's answers: no delegation, and a cancel priced at nothing.
	var answers: Dictionary = Audiences.answers(state, ns, _loader, String(row["id"]))
	if bool(answers["delegate"]["ok"]) or not bool(answers["decline"]["ok"]):
		_fail("a summons' card reads %s: delegate open or cancel closed" % [answers])
	if not Audiences.decline_price(ns, _loader, String(row["id"])).is_empty():
		_fail("a summons' cancel is priced: %s" % [Audiences.decline_price(ns, _loader, String(row["id"]))])
	# The person may still ask on their own.
	var person = _loader.person_by_id[pid]
	if person.wants.is_empty():
		return
	var asked: Dictionary = Audiences.invite(state, ns, _loader, pid, String(person.wants[0]["object"]), String(person.wants[0]["stance"]))
	if not bool(asked.get("ok", false)):
		_fail("a summoned person could not ask on their own: %s" % [asked])


func _check_who_cannot_be_summoned() -> void:
	var state = _game()
	var ns = state.player()
	var day := _day(state, 20)
	var cases := [
		[President.leader_id(ns), K.SUMMON_NOT_OWN, "the president"],
		[_staff(), K.SUMMON_NOT_OWN, "staff"],
		[_foreign_head(state), K.SUMMON_NOT_OWN, "a foreign head"],
		["FRA_nobody_at_all", K.SUMMON_NOT_OWN, "an unknown id"],
	]
	for c in cases:
		if String(c[0]) == "":
			_fail("premise: no %s to read" % c[2])
			continue
		var r: Dictionary = Audiences.summon(state, ns, _loader, String(c[0]), day)
		if bool(r.get("ok", true)) or String(r.get("reason", "")) != String(c[1]) or String(r.get("error", "")) == "":
			_fail("summoning %s read %s, not refused '%s' with words" % [c[2], r, c[1]])
		if String(Audiences.summon_refusal(state, ns, _loader, String(c[0])).get("reason", "")) != String(c[1]):
			_fail("summon_refusal for %s does not say '%s'" % [c[2], c[1]])
	# An open request: answer that one instead.
	var asker := _own_quiet(state)
	var person = _loader.person_by_id[asker]
	var asked: Dictionary = Audiences.invite(state, ns, _loader, asker, String(person.wants[0]["object"]), String(person.wants[0]["stance"]))
	if not bool(asked.get("ok", false)):
		_fail("premise: the asker could not ask: %s" % [asked])
	elif String(Audiences.summon(state, ns, _loader, asker, day).get("reason", "")) != K.SUMMON_ASKED:
		_fail("a person with an open request was not refused as having asked")
	# The cap: once per SUMMON_COOLDOWN_MONTHS, cancelled or not.
	var pid := _own_quiet(state, [asker])
	var first: Dictionary = Audiences.summon(state, ns, _loader, pid, day)
	if not bool(first.get("ok", false)):
		_fail("premise: the first summons was refused: %s" % [first])
		return
	Audiences.decline(state, ns, _loader, String(first["request"]["id"]))
	if String(Audiences.summon(state, ns, _loader, pid, _day(state, 22)).get("reason", "")) != K.SUMMON_RECENT:
		_fail("a second summons inside the cooldown was not refused as recent")
	if String(Audiences.summon_refusal(state, ns, _loader, pid).get("reason", "")) != K.SUMMON_RECENT:
		_fail("summon_refusal does not say the cooldown")
	ns.audience_summoned_month[pid] = _now(state) - K.SUMMON_COOLDOWN_MONTHS
	if not Audiences.summon_refusal(state, ns, _loader, pid).is_empty():
		_fail("the cooldown still holds %d months on" % K.SUMMON_COOLDOWN_MONTHS)
	if K.SUMMON_COOLDOWN_MONTHS != K.REQUEST_COOLDOWN_MONTHS:
		_fail("the summons' cooldown is not the months a person waits between two asks")


func _check_the_days_reasons() -> void:
	var state = _game()
	var ns = state.player()
	var pid := _own_quiet(state)
	var taken := Calendar.make_entry(CalendarK.KIND_RESHUFFLE, int(state.year), int(state.month), 25, "", "", "", "p25", "")
	Calendar.book(state, taken)
	var far := {"year": int(state.year) + 2, "month": int(state.month), "day": 1}
	for c in [[_day(state, 10), K.BOOK_PASSED, "today"], [_day(state, 25), K.BOOK_TAKEN, "a taken day"],
			[{"year": int(state.year), "month": 2, "day": 30}, K.BOOK_NO_DAY, "30 February"], [far, K.SUMMON_TOO_FAR, "two years on"]]:
		var r: Dictionary = Audiences.summon(state, ns, _loader, pid, c[0])
		if bool(r.get("ok", true)) or String(r.get("reason", "")) != String(c[1]):
			_fail("summoning on %s (%s) read %s, not '%s'" % [c[0], c[2], r, c[1]])
	if ns.audience_summoned_month.has(pid):
		_fail("a refused summons stamped the cooldown")


func _check_the_meeting_is_talk_and_unpriced() -> void:
	var state = _game()
	var ns = state.player()
	var pid := _own_quiet(state)
	var r: Dictionary = Audiences.summon(state, ns, _loader, pid, _day(state, 20))
	if not bool(r.get("ok", false)):
		_fail("premise: the summons was refused: %s" % [r])
		return
	var id := String(r["request"]["id"])
	var grudge := float(ns.person_grudges.get(pid, 0.0))
	var rapport := President.rapport(ns, pid)
	var known := President.knowledge(ns, pid)
	state.day = 20
	var session: Dictionary = Deal.open(state, ns, _loader, id)
	if session.is_empty():
		_fail("the summoned day opened no meeting")
		return
	if not is_equal_approx(President.rapport(ns, pid) - rapport, K.RECEIVED_RAPPORT) and President.rapport(ns, pid) < 1.0:
		_fail("being received moved rapport %.3f, not %.2f" % [President.rapport(ns, pid) - rapport, K.RECEIVED_RAPPORT])
	if President.knowledge(ns, pid) <= known:
		_fail("a summons taught nothing")
	for lever in ["argue", "bargain", "flatter"]:
		var a: Dictionary = Levers.attempt(state, ns, _loader, session, lever)
		if bool(a.get("ok", true)) or String(a.get("error", "")) != K.SUMMON_NO_ASK:
			_fail("the lever %s in a summons read %s, not refused for having no ask" % [lever, a])
	for row in Levers.offered(state, ns, _loader, session):
		if bool(row["offered"]):
			_fail("a summons offers the lever %s" % row["lever"])
	for verb in [Deal.grant(state, ns, _loader, session), Deal.take(state, ns, _loader, session)]:
		if bool(verb.get("ok", true)):
			_fail("a deal verb answered a summons: %s" % [verb])
	# A refusal read on a copy (RefusalRisk settles one as declined) prices nothing either.
	var copy = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var refused: Dictionary = Audiences.settle(copy, copy.player(), _loader, id, K.STATUS_DECLINED)
	if not (refused.get("price", {}) as Dictionary).is_empty() or String(Audiences.request(copy.player(), id)["status"]) != K.STATUS_SETTLED:
		_fail("a summons settled as declined read %s, not settled unpriced" % [refused])
	# Nor can it end as a promise: nothing was asked to promise (GLM gap 4).
	var copy2 = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	Audiences.settle(copy2, copy2.player(), _loader, id, K.STATUS_PROMISED)
	if String(Audiences.request(copy2.player(), id)["status"]) != K.STATUS_SETTLED:
		_fail("a summons settled as a promise reads '%s'" % Audiences.request(copy2.player(), id)["status"])
	# Held and never closed (the scene left open), the month's tick ends it settled, unpriced (GLM gap 3).
	var copy3 = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	var g3 := float(copy3.player().person_grudges.get(pid, 0.0))
	_advance(copy3)
	Audiences.tick_month(copy3, _loader, METERS)
	if String(Audiences.request(copy3.player(), id)["status"]) != K.STATUS_SETTLED or float(copy3.player().person_grudges.get(pid, 0.0)) > g3:
		_fail("a held summons never closed read '%s' at the month's end" % Audiences.request(copy3.player(), id)["status"])
	var talked: Dictionary = Levers.talk(state, ns, _loader, session, "family")
	if not bool(talked.get("ok", false)):
		_fail("a topic could not be talked in a summons: %s" % [talked])
	var closed: Dictionary = Levers.close(state, ns, _loader, session)
	if String(closed.get("outcome", "")) != K.STATUS_SETTLED or not (closed.get("price", {}) as Dictionary).is_empty():
		_fail("a summons closed as %s" % [closed])
	if float(ns.person_grudges.get(pid, 0.0)) > grudge:
		_fail("a summons wrote a grudge")
	if String(Audiences.request(ns, id)["status"]) != K.STATUS_SETTLED:
		_fail("a closed summons reads '%s'" % Audiences.request(ns, id)["status"])


func _check_a_missed_summons_costs_nothing() -> void:
	var state = _game()
	var ns = state.player()
	var pid := _own_quiet(state)
	var r: Dictionary = Audiences.summon(state, ns, _loader, pid, _day(state, 20))
	if not bool(r.get("ok", false)):
		_fail("premise: the summons was refused: %s" % [r])
		return
	var id := String(r["request"]["id"])
	var before := [float(ns.person_grudges.get(pid, 0.0)), President.rapport(ns, pid)]
	for m in range(2):
		_advance(state)
		var report: Dictionary = Audiences.tick_month(state, _loader, METERS)
		for lapsed in report["lapsed"]:
			if String(lapsed["id"]) == id:
				_fail("a missed summons was reported as a lapsed request")
	if String(Audiences.request(ns, id)["status"]) != K.STATUS_CANCELLED:
		_fail("a missed summons reads '%s', not cancelled" % Audiences.request(ns, id)["status"])
	if [float(ns.person_grudges.get(pid, 0.0)), President.rapport(ns, pid)] != before:
		_fail("a missed summons cost something: %s -> %s" % [before, [ns.person_grudges.get(pid, 0.0), President.rapport(ns, pid)]])


func _check_a_cancelled_summons_costs_nothing() -> void:
	var state = _game()
	var ns = state.player()
	var pid := _own_quiet(state)
	var r: Dictionary = Audiences.summon(state, ns, _loader, pid, _day(state, 20))
	if not bool(r.get("ok", false)):
		_fail("premise: the summons was refused: %s" % [r])
		return
	var id := String(r["request"]["id"])
	var before := [float(ns.person_grudges.get(pid, 0.0)), President.rapport(ns, pid)]
	if bool(Audiences.delegate(state, ns, _loader, id).get("ok", true)):
		_fail("a summons was delegated")
	var c: Dictionary = Audiences.decline(state, ns, _loader, id)
	if not bool(c.get("ok", false)) or not (c.get("price", {}) as Dictionary).is_empty():
		_fail("cancelling a summons read %s, not free" % [c])
	if [float(ns.person_grudges.get(pid, 0.0)), President.rapport(ns, pid)] != before:
		_fail("a cancelled summons cost something")
	for e in state.appointments:
		if String(e["action_id"]) == id and String(e["status"]) == CalendarK.STATUS_BOOKED:
			_fail("a cancelled summons kept its day")
	if String(Audiences.request(ns, id)["status"]) != K.STATUS_CANCELLED:
		_fail("a cancelled summons reads '%s'" % Audiences.request(ns, id)["status"])
	# The phone has nothing to ask about either while a summons stands.
	var again := _own_quiet(state, [pid])
	var s: Dictionary = Audiences.summon(state, ns, _loader, again, _day(state, 21))
	if bool(s.get("ok", false)) and String(Phone.options(state, ns, _loader, again)["request_id"]) != "":
		_fail("the phone reads a summons as the person's request")


func _check_the_stamp_survives_a_save() -> void:
	var state = _game()
	var ns = state.player()
	var pid := _own_quiet(state)
	Audiences.summon(state, ns, _loader, pid, _day(state, 20))
	var copy = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if copy == null or int(copy.player().audience_summoned_month.get(pid, -1)) != _now(state):
		_fail("the summons' stamp did not survive a save")
	var d: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	(d["nations"][PLAYER] as Dictionary).erase("audience_summoned_month")
	var old = GameState.from_dict(d)
	if old == null or not old.player().audience_summoned_month.is_empty():
		_fail("an older save without the stamp did not read as nobody summoned")


# --- Fixtures -------------------------------------------------------------------------------

func _game():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 3
	state.day = 10
	return state


## A person of the nation with a want, no open request, neither the president nor staff.
func _own_quiet(state, skip: Array = []) -> String:
	var ns = state.player()
	var leader := President.leader_id(ns)
	for person in _loader.people.get(PLAYER, []):
		var pid := String(person.id)
		if pid == leader or Staff.is_staff(_loader, pid) or person.wants.is_empty() or skip.has(pid):
			continue
		if not Audiences.summon_refusal(state, ns, _loader, pid).is_empty():
			continue
		return pid
	_fail("premise: no quiet person of the nation")
	return ""


func _staff() -> String:
	for person in _loader.people.get(PLAYER, []):
		if Staff.is_staff(_loader, String(person.id)):
			return String(person.id)
	return ""


func _foreign_head(state) -> String:
	return String(state.nations["DEU"].head_of_state_person_id)


func _day(state, day: int) -> Dictionary:
	return {"year": int(state.year), "month": int(state.month), "day": day}


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
		print("test_audience_summons: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
