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
## two asks), stamped in ns.audience_summoned_month at the booking; a cancelled one keeps its
## stamp, so a cancel and a re-book cannot farm the hold's rapport.

const K = preload("res://src/sim/audience_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Dates = preload("res://src/sim/audience_dates.gd")
const President = preload("res://src/sim/president.gd")
const Staff = preload("res://src/sim/staff.gd")


static func is_summons(row: Dictionary) -> bool:
	return String(row.get("object", "")) == K.SUMMON_OBJECT


## Why `person_id` cannot be summoned now, whatever the day: {} when they can, else {reason,
## error}. Any person of the played nation, minus the president, staff, and anyone with an
## open request (the player answers that one); a foreign head is not his to summon.
static func refusal(state, ns, loader, person_id: String) -> Dictionary:
	if loader.person_by_id.get(person_id) == null or not person_id.begins_with("%s_" % ns.id) \
			or person_id == President.leader_id(ns) or Staff.is_staff(loader, person_id):
		return {"reason": K.SUMMON_NOT_OWN, "error": "not someone of your nation you can summon"}
	var at := int(ns.audience_summoned_month.get(person_id, -1))
	if at >= 0 and _now(state) - at < K.SUMMON_COOLDOWN_MONTHS:
		return {"reason": K.SUMMON_RECENT, "error": "you summoned them too recently"}
	for row in ns.audience_requests:
		if String(row.get("person_id", "")) == person_id and K.OPEN.has(String(row.get("status", ""))) and not is_summons(row):
			return {"reason": K.SUMMON_ASKED, "error": "they have asked to see you: answer their request"}
	return {}


## Summon `person_id` on `date`: any free day from tomorrow to the diary's horizon. {ok, error,
## reason, request}; a refusal writes nothing.
static func summon(state, ns, loader, person_id: String, date: Dictionary) -> Dictionary:
	var refused := refusal(state, ns, loader, person_id)
	if not refused.is_empty():
		return refused.merged({"ok": false, "request": {}})
	var now := _now(state)
	var row := {
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
	var bad := Dates.refusal(state, row, date)
	if String(bad.get("reason", "")) == K.BOOK_DEADLINE:
		bad = {"reason": K.SUMMON_TOO_FAR, "error": "further ahead than the diary reaches"}
	if not bad.is_empty():
		return bad.merged({"ok": false, "request": {}})
	var day := {"year": int(date["year"]), "month": int(date["month"]), "day": int(date["day"])}
	var booked: Dictionary = Calendar.book(state, Dates.entry(row, day))
	if not bool(booked.get("ok", false)):
		return {"ok": false, "reason": K.BOOK_TAKEN, "error": String(booked.get("error", "")), "request": {}}
	row["status"] = K.STATUS_BOOKED
	row["date"] = day
	# No acted_month: the briefing counts that stamp as a request answered, and nobody asked.
	ns.audience_requests.append(row)
	ns.audience_summoned_month[person_id] = now
	return {"ok": true, "error": "", "reason": "", "request": row.duplicate(true)}


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
