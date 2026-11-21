extends RefCounted

## The summons: the president asks to see a person of his nation who has asked nothing (the
## author's "Oui, petite carte à part" and "Toute personne du pays", 2026-11-20; Design's
## audiences read, section 3). A leaf over the lane's row, the diary and the registers' doors.
##
## A SUMMONS IS NOT AN ASK. Its row sits in ns.audience_requests so the diary, the day's scene
## and the hold run as for any booked audience (rapport + RECEIVED_RAPPORT, KNOW_AUDIENCE
## learned), but it takes no place under MAX_PENDING (AudienceLane), stamps no ask
## (audience_asked_month), and the person may still ask on their own. The meeting is talk only:
## every lever and deal verb answers SUMMON_NO_ASK. Missed or cancelled, it closes CANCELLED
## with no price -- it was the president's own appointment.
##
## THE CAP: one summons per person in SUMMON_COOLDOWN_MONTHS (the months a person waits between
## two asks), stamped in ns.audience_summoned_month at the booking. The player's cancel before the
## day gives the stamp back (the parent's R-432-cancel ruling: no meeting was held, so no rapport to
## farm); a no-show keeps it.

const K = preload("res://src/sim/audience_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Dates = preload("res://src/sim/audience_dates.gd")
const President = preload("res://src/sim/president.gd")
const Staff = preload("res://src/sim/staff.gd")
const Lane = preload("res://src/sim/audience_lane.gd")


## Why `person_id` cannot be summoned now, whatever the day: {} when they can, else {code,
## reason, error} (codes under `code`, words under `reason`, as a request's booking). Any person
## of the played nation, minus the president, staff, and anyone with an open request (the
## player answers that one); a foreign head is not his to summon. `summoned` carries `lifts`,
## the absolute month the person's cap lifts.
static func refusal(state, ns, loader, person_id: String) -> Dictionary:
	if loader.person_by_id.get(person_id) == null or not person_id.begins_with("%s_" % ns.id) \
			or person_id == President.leader_id(ns) or Staff.is_staff(loader, person_id):
		return _no(K.SUMMON_NOT_OWN, "not someone of your nation you can summon")
	if not Lane.open_request(ns, person_id).is_empty():
		return _no(K.SUMMON_ASKED, "they have asked to see you: answer their request")
	for row in ns.audience_requests:
		if String(row.get("person_id", "")) == person_id and K.is_summons(row) and K.OPEN.has(String(row.get("status", ""))):
			return _no(K.SUMMON_BOOKED, "you have already summoned them")
	var now := _now(state)
	var at := int(ns.audience_summoned_month.get(person_id, -1))
	if at >= 0 and now - at < K.SUMMON_COOLDOWN_MONTHS:
		return _no(K.SUMMON_RECENT, "you summoned them too recently").merged({"lifts": at + K.SUMMON_COOLDOWN_MONTHS})
	var this_month := 0
	for pid in ns.audience_summoned_month:
		this_month += 1 if int(ns.audience_summoned_month[pid]) == now else 0
	if this_month >= K.SUMMONS_PER_MONTH:
		return _no(K.SUMMON_MONTH_USED, "you have summoned someone this month already")
	if Dates.first_free(state, _window(person_id, now)).is_empty():
		return _no(K.SUMMON_NO_FREE_DAY, "no day in your diary is free")
	return {}


## The days a summons of `person_id` can take, as a request's offered days: every day from
## tomorrow to the diary's horizon, each with `free` and the words of why not (TAKE 3).
static func days(state, person_id: String) -> Array[Dictionary]:
	return Dates.offered(state, null, _window(person_id, _now(state)))


## Summon `person_id` on `date`. {ok, code, reason, error, request}; a refusal writes nothing.
static func summon(state, ns, loader, person_id: String, date: Dictionary) -> Dictionary:
	var refused := refusal(state, ns, loader, person_id)
	if not refused.is_empty():
		return refused.merged({"ok": false, "request": {}})
	var now := _now(state)
	var row := _window(person_id, now)
	row["id"] = _unique_id(ns, String(row["id"]))  # before the book: the day keys on it
	var bad := Dates.refusal(state, row, date)
	if String(bad.get("code", "")) == K.BOOK_DEADLINE:
		bad = _no(K.SUMMON_TOO_FAR, "further ahead than the diary reaches")
	if not bad.is_empty():
		return bad.merged({"ok": false, "request": {}})
	var day := {"year": int(date["year"]), "month": int(date["month"]), "day": int(date["day"])}
	var booked: Dictionary = Calendar.book(state, Dates.entry(row, day))
	if not bool(booked.get("ok", false)):
		return _no(K.BOOK_TAKEN, String(booked.get("error", ""))).merged({"ok": false, "request": {}})
	row["status"] = K.STATUS_BOOKED
	row["date"] = day
	# No acted_month: the briefing counts that stamp as a request answered, and nobody asked.
	ns.audience_requests.append(row)
	ns.audience_summoned_month[person_id] = now
	return {"ok": true, "code": "", "reason": "", "error": "", "request": row.duplicate(true)}


## A summons' row before it is booked: its window runs to the diary's horizon.
static func _window(person_id: String, now: int) -> Dictionary:
	return {
		"id": "%s|%s|%d" % [person_id, K.SUMMON_OBJECT, now],
		"person_id": person_id,
		"object": K.SUMMON_OBJECT,
		"stance": "",
		"arrived_month": now,
		"deadline_month": now + CalendarK.BOOKING_HORIZON_MONTHS,
		"status": K.STATUS_PENDING,
		"date": {},
		"resolved_month": -1,
		"offer": {},
		# Not an arrival: it ends no quiet month and the quiet call's stamp reads it as plain.
		"differs": false,
	}


## A summons cancelled and made again the same month must not share the cancelled row's id:
## every lookup by id would find the cancelled one first (pass 2 TAKE 1).
static func _unique_id(ns, base: String) -> String:
	var taken := {}
	for row in ns.audience_requests:
		taken[String(row.get("id", ""))] = true
	var id := base
	var n := 1
	while taken.has(id):
		n += 1
		id = "%s#%d" % [base, n]
	return id


static func _no(code: String, words: String) -> Dictionary:
	return {"code": code, "reason": words, "error": words}


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
