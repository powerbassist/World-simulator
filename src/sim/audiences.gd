extends RefCounted

## Audience requests -- V5.2b. People of the played nation ask to see the
## president; the president books, delegates or declines, and a request left
## unanswered past its window is a decline (the author's answer 3, 2026-10-21).
## The model is docs/audiences-model.md; the design, docs/design/v5.2-spec.md
## "An audience request (V5.2b)"; the bands, docs/design/bands-v5.2.md B1-B3.
##
## THE REQUEST IS THE LANE. `ns.audience_requests` is the REQUESTS lane the
## inbox shows, row for row, and MAX_PENDING caps it here -- so a request is
## counted where the player meets it (B1), and nothing between the sim and the
## card can drop one (the pre-mortem's cause 2). A request never holds the clock
## (decision-surfaces, the author's answer 2).
##
## ITS OWN TRIGGER (the pre-mortem's cause 1). The want ladder's edge trigger
## fires nothing in an idle term by design, so a request does not ride it: a
## person with a want the government does not serve asks on a seeded monthly
## hazard, and a programme entry that goes live invites the people whose wants
## name it. A grudge does not silence anyone -- the declined go on asking.
##
## THE PRICE IS THE EXISTING REGISTERS'. A decline writes a grudge and loyalty
## through Characters.price_refusal() (characters.gd stays their one writer) and
## a rapport loss through President (a's one writer); no third number. A lapse
## and a no-show cost exactly a decline; delegation a share of it.
##
## A leaf over its writers: constants, Characters and President (the registers'
## doors), Calendar (the diary is the scarcity) and Cycle (the seeded draw).
## Determinism: every draw is Cycle.unit_pair over an id, a salt and a month.

const K = preload("res://src/sim/audience_constants.gd")
const Characters = preload("res://src/sim/characters.gd")
const President = preload("res://src/sim/president.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")


## One month of the played nation's lane: what is overdue lapses (priced), who
## asks arrives, and old resolved rows are pruned. {arrived, lapsed}, the rows as
## the card reads them. `meters` is the dict Characters.tick_month takes.
static func tick_month(state, loader, meters: Dictionary) -> Dictionary:
	var out := {"arrived": [], "lapsed": []}
	var ns = state.player()
	if ns == null:
		return out
	var now := _now(state)
	for row in ns.audience_requests:
		if _overdue(row, now):
			_unbook(state, row)
			_price(state, ns, loader, row, 1.0, K.DECLINE_RAPPORT)
			_close(row, K.STATUS_LAPSED, now)
			out["lapsed"].append(_view(row))
	_arrivals(state, ns, loader, meters, now, out["arrived"])
	_prune(ns, now)
	return out


# --- Reads --------------------------------------------------------------------------

## The REQUESTS lane: every request waiting for an answer, oldest first.
static func pending(ns) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for row in ns.audience_requests:
		if String(row.get("status", "")) == K.STATUS_PENDING:
			out.append(_view(row))
	return out


static func waiting_count(ns) -> int:
	return pending(ns).size()


static func request(ns, request_id: String) -> Dictionary:
	var row := _row(ns, request_id)
	return {} if row.is_empty() else _view(row)


## The days the person offers, in date order, each with whether the diary can
## place it. Drawn from the request's id, so the card is the same every time it
## is opened; a day that has passed reads not free, with Calendar's reason.
static func offered_dates(state, ns, request_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var row := _row(ns, request_id)
	if row.is_empty():
		return out
	var spans := []
	var total := 0
	for m in range(int(row["arrived_month"]) + 1, int(row["deadline_month"]) + 1):
		var ym := _ym(m)
		var days := Calendar.days_in_month(int(ym["year"]), int(ym["month"]))
		spans.append([ym, days])
		total += days
	var picks: Array[int] = []
	var k := 0
	while picks.size() < K.OFFERED_DATES and k < K.OFFERED_DATES * 8:
		var pick := int(Cycle.unit_pair(request_id, K.SALT_DATE, k) * float(total))
		if not picks.has(pick):
			picks.append(pick)
		k += 1
	picks.sort()
	for pick in picks:
		var left := pick
		for span in spans:
			if left < int(span[1]):
				var date := {"year": int(span[0]["year"]), "month": int(span[0]["month"]), "day": left + 1}
				var reason := Calendar.refusal_reason(state, _entry(row, date))
				date["free"] = reason.is_empty()
				date["reason"] = reason
				out.append(date)
				break
			left -= int(span[1])
	return out


## The card's three answers. Booking needs an offered day the diary can place;
## delegation and decline are always open on a waiting request (B2's 100 %).
static func answers(state, ns, loader, request_id: String) -> Dictionary:
	var row := _row(ns, request_id)
	if row.is_empty() or String(row["status"]) != K.STATUS_PENDING:
		var closed := {"ok": false, "reason": "this request is no longer waiting"}
		return {"book": closed, "delegate": closed, "decline": closed}
	var book := {"ok": false, "reason": "none of the days offered is free"}
	for date in offered_dates(state, ns, request_id):
		if bool(date["free"]):
			book = {"ok": true, "reason": ""}
			break
	return {"book": book, "delegate": {"ok": true, "reason": ""}, "decline": {"ok": true, "reason": ""}}


## What a decline -- or the lapse, or a no-show -- writes on the person's card,
## before any clamp: the card names it (B3).
static func decline_price(ns, loader, request_id: String) -> Dictionary:
	var row := _row(ns, request_id)
	var person = loader.person_by_id.get(String(row.get("person_id", "")))
	var intake: float = Characters.grudge_intake(person) if person != null else 1.0
	return {"grudge": K.DECLINE_GRUDGE * intake, "loyalty": K.DECLINE_LOYALTY, "rapport": K.DECLINE_RAPPORT}


# --- Commands -------------------------------------------------------------------------

## Book one of the offered days. The diary refuses a day already taken (one
## thing at a time), and that refusal is the scarcity.
static func book(state, ns, loader, request_id: String, date: Dictionary) -> Dictionary:
	var row := _row(ns, request_id)
	if row.is_empty() or String(row["status"]) != K.STATUS_PENDING:
		return {"ok": false, "error": "this request is no longer waiting"}
	var offered := false
	for d in offered_dates(state, ns, request_id):
		if int(d["year"]) == int(date.get("year", 0)) and int(d["month"]) == int(date.get("month", 0)) \
				and int(d["day"]) == int(date.get("day", 0)):
			offered = true
	if not offered:
		return {"ok": false, "error": "not a day the person offered"}
	var day := {"year": int(date["year"]), "month": int(date["month"]), "day": int(date["day"])}
	var result: Dictionary = Calendar.book(state, _entry(row, day))
	if bool(result.get("ok", false)):
		row["status"] = K.STATUS_BOOKED
		row["date"] = day
	return result


static func delegate(state, ns, loader, request_id: String) -> Dictionary:
	var row := _row(ns, request_id)
	if row.is_empty() or not K.OPEN.has(String(row["status"])):
		return {"ok": false, "error": "this request is no longer waiting"}
	_unbook(state, row)
	var person = loader.person_by_id.get(String(row["person_id"]))
	var snub := 0.0
	if person != null and (person.traits.has("vain") or String(row["object"]).begins_with("office:")):
		snub = K.DELEGATE_SNUB_RAPPORT
	var price := _price(state, ns, loader, row, K.DELEGATE_GRUDGE_SHARE, snub)
	_close(row, K.STATUS_DELEGATED, _now(state))
	return {"ok": true, "error": "", "price": price}


static func decline(state, ns, loader, request_id: String) -> Dictionary:
	var row := _row(ns, request_id)
	if row.is_empty() or not K.OPEN.has(String(row["status"])):
		return {"ok": false, "error": "this request is no longer waiting"}
	_unbook(state, row)
	var price := _price(state, ns, loader, row, 1.0, K.DECLINE_RAPPORT)
	_close(row, K.STATUS_DECLINED, _now(state))
	return {"ok": true, "error": "", "price": price}


## The booked day has come and the scene opens (Levers.open calls this): the
## president learns the person a little whatever is said.
static func hold(state, ns, loader, request_id: String) -> Dictionary:
	var row := _row(ns, request_id)
	if row.is_empty() or String(row["status"]) != K.STATUS_BOOKED:
		return {"ok": false, "error": "this audience is not booked"}
	row["status"] = K.STATUS_HELD
	President.learn(state, ns, loader, String(row["person_id"]), K.KNOW_AUDIENCE)
	return {"ok": true, "error": ""}


## How a held audience ended: settled, promised, or declined (priced as one).
static func settle(state, ns, loader, request_id: String, outcome: String) -> Dictionary:
	var row := _row(ns, request_id)
	if row.is_empty() or String(row["status"]) != K.STATUS_HELD:
		return {"ok": false, "error": "this audience is not being held"}
	if not [K.STATUS_SETTLED, K.STATUS_PROMISED, K.STATUS_DECLINED].has(outcome):
		return {"ok": false, "error": "not an outcome"}
	var price := {}
	if outcome == K.STATUS_DECLINED:
		price = _price(state, ns, loader, row, 1.0, K.DECLINE_RAPPORT)
	_close(row, outcome, _now(state))
	return {"ok": true, "error": "", "price": price}


# --- The month's halves -----------------------------------------------------------------

## Pending past its window lapses; an audience booked or held in an earlier
## month and never closed is a no-show -- each costs a decline, once.
static func _overdue(row: Dictionary, now: int) -> bool:
	match String(row.get("status", "")):
		K.STATUS_PENDING:
			return now >= int(row["deadline_month"])
		K.STATUS_BOOKED, K.STATUS_HELD:
			var date: Dictionary = row.get("date", {})
			return int(date.get("year", 0)) * 12 + int(date.get("month", 0)) < now
	return false


## Invitations first -- an entry gone live this month calls the people whose
## wants name it, outside the hazard -- then the seeded monthly ask. The lane's
## cap and each person's cooldown bound both.
static func _arrivals(state, ns, loader, meters: Dictionary, now: int, arrived: Array) -> void:
	var people: Array = loader.people.get(state.player_nation_id, [])
	var leader := President.leader_id(ns)
	var open := 0
	for row in ns.audience_requests:
		if K.OPEN.has(String(row.get("status", ""))):
			open += 1
	var live := {}
	for entry in ns.programme:
		if int(entry.get("chosen_term", -1)) == int(ns.terms_served) and int(entry.get("months_live", 0)) == 1 \
				and String(entry.get("status", "")) == "active":
			live["programme:%s" % String(entry["entry_id"])] = true
	for person in people:
		if open >= K.MAX_PENDING:
			return
		if not _may_ask(ns, person, leader, now):
			continue
		for want in person.wants:
			if live.has(String(want["object"])):
				_arrive(ns, person, want, now, arrived)
				open += 1
				break
	var leaders := {}
	for party in loader.parties.get(state.player_nation_id, []):
		leaders[party.id] = party.leader_person_id
	for person in people:
		if open >= K.MAX_PENDING:
			return
		if not _may_ask(ns, person, leader, now):
			continue
		var want := _unserved(ns, person, meters, leaders)
		if want.is_empty():
			continue
		var hazard := K.REQUEST_HAZARD * (0.5 + float(ns.person_standing.get(person.id, 0.0)))
		if Cycle.unit_pair(person.id, K.SALT_REQUEST, now) < hazard:
			_arrive(ns, person, want, now, arrived)
			open += 1


static func _may_ask(ns, person, leader: String, now: int) -> bool:
	if person.id == leader:
		return false
	if ns.audience_asked_month.has(person.id) \
			and now - int(ns.audience_asked_month[person.id]) < K.REQUEST_COOLDOWN_MONTHS:
		return false
	for row in ns.audience_requests:
		if String(row.get("person_id", "")) == person.id and K.OPEN.has(String(row.get("status", ""))):
			return false
	return true


## The first want the government does not serve, read through the same door the
## edge trigger uses, or {}.
static func _unserved(ns, person, meters: Dictionary, leaders: Dictionary) -> Dictionary:
	for want in person.wants:
		if not Characters.want_served(ns, person, want, meters, leaders):
			return want
	return {}


static func _arrive(ns, person, want: Dictionary, now: int, arrived: Array) -> void:
	var row := {
		"id": "%s|%d" % [person.id, now],
		"person_id": String(person.id),
		"object": String(want["object"]),
		"stance": String(want["stance"]),
		"arrived_month": now,
		"deadline_month": now + K.REQUEST_WINDOW_MONTHS,
		"status": K.STATUS_PENDING,
		"date": {},
		"resolved_month": -1,
	}
	ns.audience_requests.append(row)
	ns.audience_asked_month[String(person.id)] = now
	arrived.append(_view(row))


static func _prune(ns, now: int) -> void:
	var kept: Array[Dictionary] = []
	for row in ns.audience_requests:
		var resolved := int(row.get("resolved_month", -1))
		if resolved >= 0 and now - resolved > K.RESOLVED_KEPT_MONTHS:
			continue
		kept.append(row)
	ns.audience_requests = kept


# --- Helpers ------------------------------------------------------------------------------

## A refusal's price at `share` of a decline's grudge, plus `rapport`.
static func _price(state, ns, loader, row: Dictionary, share: float, rapport: float) -> Dictionary:
	var pid := String(row["person_id"])
	var person = loader.person_by_id.get(pid)
	if person == null:
		push_error("audiences: request '%s' names no person" % String(row["id"]))
		return {"grudge": 0.0, "loyalty": 0.0, "rapport": 0.0}
	var applied: Dictionary = Characters.price_refusal(ns, person, K.DECLINE_GRUDGE * share, K.DECLINE_LOYALTY * share)
	var before := President.rapport(ns, pid)
	President.adjust_rapport(state, ns, loader, pid, rapport)
	applied["rapport"] = President.rapport(ns, pid) - before
	return applied


static func _close(row: Dictionary, status: String, now: int) -> void:
	row["status"] = status
	row["resolved_month"] = now


## A booked request answered another way gives its day back to the diary.
static func _unbook(state, row: Dictionary) -> void:
	if String(row["status"]) == K.STATUS_BOOKED:
		Calendar.cancel(state, Calendar.verb_key(_entry(row, row["date"])))


static func _entry(row: Dictionary, date: Dictionary) -> Dictionary:
	return Calendar.make_entry(CalendarK.KIND_AUDIENCE, int(date["year"]), int(date["month"]), int(date["day"]),
		String(row["id"]), String(row["person_id"]), "", "", "", String(row["person_id"]), 0)


static func _row(ns, request_id: String) -> Dictionary:
	for row in ns.audience_requests:
		if String(row.get("id", "")) == request_id:
			return row
	return {}


## A copy for readers, every month cast to int: rows come back from a JSON save
## with every number a float (the pledges precedent -- cast on every read).
static func _view(row: Dictionary) -> Dictionary:
	var date: Dictionary = row.get("date", {})
	return {
		"id": String(row.get("id", "")),
		"person_id": String(row.get("person_id", "")),
		"object": String(row.get("object", "")),
		"stance": String(row.get("stance", "")),
		"arrived_month": int(row.get("arrived_month", 0)),
		"deadline_month": int(row.get("deadline_month", 0)),
		"status": String(row.get("status", "")),
		"date": {} if date.is_empty() else {
			"year": int(date.get("year", 0)), "month": int(date.get("month", 0)), "day": int(date.get("day", 0))},
		"resolved_month": int(row.get("resolved_month", -1)),
	}


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


static func _ym(absolute: int) -> Dictionary:
	var year := floori((absolute - 1) / 12.0)
	return {"year": year, "month": absolute - year * 12}
