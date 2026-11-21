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
	_check_one_a_month_and_one_standing()
	_check_the_meeting_is_talk_and_unpriced()
	_check_a_missed_summons_costs_nothing()
	_check_a_cancelled_summons_costs_nothing()
	_check_a_resummons_after_a_cancel_is_its_own_row()
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
		if bool(r.get("ok", true)) or String(r.get("code", "")) != String(c[1]) or String(r.get("error", "")) == "":
			_fail("summoning %s read %s, not refused '%s' with words" % [c[2], r, c[1]])
		if String(Audiences.summon_refusal(state, ns, _loader, String(c[0])).get("code", "")) != String(c[1]):
			_fail("summon_refusal for %s does not say '%s'" % [c[2], c[1]])
	# An open request: answer that one instead.
	var asker := _own_quiet(state)
	var person = _loader.person_by_id[asker]
	var asked: Dictionary = Audiences.invite(state, ns, _loader, asker, String(person.wants[0]["object"]), String(person.wants[0]["stance"]))
	if not bool(asked.get("ok", false)):
		_fail("premise: the asker could not ask: %s" % [asked])
	elif String(Audiences.summon(state, ns, _loader, asker, day).get("code", "")) != K.SUMMON_ASKED:
		_fail("a person with an open request was not refused as having asked")
	# The cap: once per SUMMON_COOLDOWN_MONTHS while the summons stands (a cancel gives it back,
	# the parent's R-432-cancel ruling).
	var pid := _own_quiet(state, [asker])
	var first: Dictionary = Audiences.summon(state, ns, _loader, pid, day)
	if not bool(first.get("ok", false)):
		_fail("premise: the first summons was refused: %s" % [first])
		return
	for row in ns.audience_requests:  # a no-show, as tick_month closes one: the day back, the stamp kept
		if String(row["id"]) == String(first["request"]["id"]):
			Audiences._unbook(state, row)
			Audiences._close(row, K.STATUS_CANCELLED, _now(state))
	if String(Audiences.summon(state, ns, _loader, pid, _day(state, 22)).get("code", "")) != K.SUMMON_RECENT:
		_fail("a second summons inside the cooldown was not refused as recent")
	var recent: Dictionary = Audiences.summon_refusal(state, ns, _loader, pid)
	if String(recent.get("code", "")) != K.SUMMON_RECENT or int(recent.get("lifts", -1)) != _now(state) + K.SUMMON_COOLDOWN_MONTHS:
		_fail("summon_refusal does not say the cooldown and the month it lifts: %s" % [recent])
	ns.audience_summoned_month[pid] = _now(state) - K.SUMMON_COOLDOWN_MONTHS
	if not Audiences.summon_refusal(state, ns, _loader, pid).is_empty():
		_fail("the cooldown still holds %d months on: %s" % [K.SUMMON_COOLDOWN_MONTHS, Audiences.summon_refusal(state, ns, _loader, pid)])
	if K.SUMMON_COOLDOWN_MONTHS != K.REQUEST_COOLDOWN_MONTHS:
		_fail("the summons' cooldown is not the months a person waits between two asks")


## The author's "Une convocation par mois" and pass 2's TAKE 2: one summons a calendar month across
## everyone, one standing summons a person; the days a summons can take; none when the diary is full.
func _check_one_a_month_and_one_standing() -> void:
	var state = _game()
	var ns = state.player()
	var a := _own_quiet(state)
	var b := _own_quiet(state, [a])
	if not bool(Audiences.summon(state, ns, _loader, a, _day(state, 20)).get("ok", false)):
		_fail("premise: the month's first summons was refused")
		return
	if String(Audiences.summon_refusal(state, ns, _loader, b).get("code", "")) != K.SUMMON_MONTH_USED:
		_fail("a second summons in one month read %s, not month_used" % [Audiences.summon_refusal(state, ns, _loader, b)])
	if String(Audiences.summon(state, ns, _loader, b, _day(state, 22)).get("code", "")) != K.SUMMON_MONTH_USED:
		_fail("summon() let a second summons through in one month")
	if K.SUMMONS_PER_MONTH != 1:
		_fail("the monthly cap is not the author's one")
	# QA's T1/T2 on #432: the month is the booking's, not the meeting's -- a summons booked for a
	# day next month still uses this month, and a day beyond this month books at all.
	var fresh = _game()
	var fns = fresh.player()
	var c := _own_quiet(fresh)
	var d := _own_quiet(fresh, [c])
	var nxt := {"year": int(fresh.year) + (1 if int(fresh.month) == 12 else 0), "month": int(fresh.month) % 12 + 1, "day": 5}
	if not bool(Audiences.summon(fresh, fns, _loader, c, nxt).get("ok", false)):
		_fail("a summons for a day next month was refused")
	elif String(Audiences.summon_refusal(fresh, fns, _loader, d).get("code", "")) != K.SUMMON_MONTH_USED:
		_fail("a summons booked for next month left this month's one unused")
	# Nine months on, a's cap has lifted but a's summons -- booked far ahead -- still stands.
	for row in ns.audience_requests:
		if String(row["person_id"]) == a:
			row["date"] = {"year": int(state.year) + 1, "month": int(state.month), "day": 20}
	for m in range(K.SUMMON_COOLDOWN_MONTHS + 1):
		_advance(state)
	state.day = 10
	if String(Audiences.summon_refusal(state, ns, _loader, a).get("code", "")) != K.SUMMON_BOOKED:
		_fail("a person with a summons still standing read %s, not booked" % [Audiences.summon_refusal(state, ns, _loader, a)])
	if not Audiences.summon_refusal(state, ns, _loader, b).is_empty():
		_fail("a new month's first summons is refused: %s" % [Audiences.summon_refusal(state, ns, _loader, b)])
	# TAKE 3: the days, tomorrow to the diary's horizon; and none free when the diary is full.
	var days: Array[Dictionary] = Audiences.summon_days(state, b)
	if days.is_empty() or int(days[0]["day"]) != 11 or int(days[0]["month"]) != int(state.month):
		_fail("a summons' days do not start tomorrow: %s" % [days.slice(0, 1)])
	while state.appointments.size() < CalendarK.MAX_APPOINTMENTS:
		var n: int = state.appointments.size()
		state.appointments.append(Calendar.make_entry(CalendarK.KIND_RESHUFFLE, int(state.year) + 2, 1 + n % 12, 1 + n % 28, "", "", "", "full%d" % n, ""))
	if String(Audiences.summon_refusal(state, ns, _loader, b).get("code", "")) != K.SUMMON_NO_FREE_DAY:
		_fail("a full diary read %s, not no_free_day" % [Audiences.summon_refusal(state, ns, _loader, b)])


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
		if bool(r.get("ok", true)) or String(r.get("code", "")) != String(c[1]):
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
	# TAKE 4 and 5: no refusal risk, no offer, and nothing to answer or agree.
	if not Deal.refusal_risk(state, ns, _loader, session).is_empty() or not Deal.silence_worth(state, ns, _loader, session).is_empty() \
			or not (Deal.answers(state, ns, _loader, session)["offer"] as Dictionary).is_empty():
		_fail("a summons scene projects a refusal risk or an offer")
	if bool(Audiences.agree(ns, id, K.STATUS_PROMISED)) or bool(Audiences.answer(state, ns, id, K.STATUS_PROMISED).get("ok", true)):
		_fail("a summons took an agreement or an answer")
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


## QA's T3 on #432: AudienceLane.close_overtaken never closes a summons -- it reads a booked row
## only once overdue, and then only to ask whether the person's want is served, which no want
## named "summons" ever is; so no skip is needed there and none is kept.
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
	# R-432-cancel: a no-show keeps the stamp, the person's months still run.
	if String(Audiences.summon_refusal(state, ns, _loader, pid).get("code", "")) != K.SUMMON_RECENT:
		_fail("a missed summons gave back its stamp: %s" % [Audiences.summon_refusal(state, ns, _loader, pid)])
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
	# TAKE 5: a booked summons takes no phone answer (a settle with no ask, a promise with no word).
	if bool(Audiences.answer(state, ns, id, K.STATUS_PROMISED).get("ok", true)) or String(Audiences.request(ns, id)["status"]) != K.STATUS_BOOKED:
		_fail("a booked summons was answered as a request")
	var deleg: Dictionary = Audiences.delegate(state, ns, _loader, id)
	if bool(deleg.get("ok", true)) or String(deleg.get("error", "")) != K.SUMMON_NO_DELEGATE:
		_fail("a summons was delegated, or refused with another message: %s" % [deleg])
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
	# R-432-cancel: the player's cancel before the day gives back both stamps, the month's one
	# summons and the person's months: the same person can be summoned again this month.
	if not Audiences.summon_refusal(state, ns, _loader, pid).is_empty():
		_fail("a cancelled summons kept its stamp: %s" % [Audiences.summon_refusal(state, ns, _loader, pid)])
	# The phone and the roster have nothing to ask about either while a summons stands (next
	# month: one summons a month). QA's lead 13: the summons must succeed for this to read.
	_advance(state)
	state.day = 10
	var again := _own_quiet(state, [pid])
	var s: Dictionary = Audiences.summon(state, ns, _loader, again, _day(state, 21))
	if not bool(s.get("ok", false)):
		_fail("premise: the second summons was refused: %s" % [s])
	elif String(Phone.options(state, ns, _loader, again)["request_id"]) != "" or not AudienceLane.open_request(ns, again).is_empty():
		_fail("the phone or the lane's open request reads a summons as the person's request")


func _check_a_resummons_after_a_cancel_is_its_own_row() -> void:
	# Pass 2 TAKE 1: a summons cancelled then made again the same month, the same day even,
	# is a new row -- one id for both found the cancelled row, so the second never opened.
	var state = _game()
	var ns = state.player()
	var pid := _own_quiet(state)
	var first: Dictionary = Audiences.summon(state, ns, _loader, pid, _day(state, 20))
	if not bool(first.get("ok", false)):
		_fail("premise: the summons was refused: %s" % [first])
		return
	var old_id := String(first["request"]["id"])
	Audiences.decline(state, ns, _loader, old_id)
	var again: Dictionary = Audiences.summon(state, ns, _loader, pid, _day(state, 20))
	if not bool(again.get("ok", false)):
		_fail("a summons cancelled could not be made again: %s" % [again])
		return
	var id := String(again["request"]["id"])
	if id == old_id:
		_fail("a summons made again after a cancel kept the cancelled one's id '%s'" % id)
	if String(Audiences.request(ns, id)["status"]) != K.STATUS_BOOKED:
		_fail("the summons made again reads '%s', not booked" % Audiences.request(ns, id)["status"])
	if not bool(Audiences.decline(state, ns, _loader, id).get("ok", false)) or String(Audiences.request(ns, id)["status"]) != K.STATUS_CANCELLED:
		_fail("the summons made again could not be cancelled")
	var third: Dictionary = Audiences.summon(state, ns, _loader, pid, _day(state, 22))
	var third_id := String((third.get("request", {}) as Dictionary).get("id", ""))
	state.day = 22
	if Deal.open(state, ns, _loader, third_id).is_empty():
		_fail("a third summons the same month opened no meeting")


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
