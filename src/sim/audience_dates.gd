extends RefCounted

## The days an audience can be booked on, and the diary entry an audience is.
## Split out of audiences.gd at pre-gate B, when the month-3 guarantee met that
## file's 300-line cap; Audiences keeps offered_dates() and delegates, so no caller
## moved. A leaf over Calendar and Cycle.

const K = preload("res://src/sim/audience_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")


## Every day `row` can be booked on, in date order, each with whether the diary can
## place it: any day from tomorrow to the last day of last_month() (the author's calls of
## 2026-11-20, "N'importe quel jour libre" and "Fin du mois limite"; the two days once drawn
## from the request's id are gone). Tomorrow, not today: a day booked today would fire at the
## next day's tick, after a month close that reads it as a no-show.
static func offered(state, ns, row: Dictionary) -> Array[Dictionary]:
	return _walk(state, row, false)


## The first day of the window the diary can place, or {}: a card that needs one free day
## stops there rather than reading the whole window (#431 pass 2, TAKE 3).
static func first_free(state, row: Dictionary) -> Dictionary:
	var found := _walk(state, row, true)
	return {} if found.is_empty() else found[0]


## The window's days in order, each with `free` and the words of why not (refusal(), the one
## rule book() reads, so a day the list calls free is a day that books -- TAKE 4); with
## `first_only`, just the first free one.
static func _walk(state, row: Dictionary, first_only: bool) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if row.is_empty():
		return out
	var today := _today(state)
	var y := int(today["year"])
	var m := int(today["month"])
	var d := int(today["day"]) + 1
	var last := last_month(row)
	while y * 12 + m <= last:
		if d > Calendar.days_in_month(y, m):
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
			continue
		var date := {"year": y, "month": m, "day": d}
		var why := refusal(state, row, date)
		date["free"] = why.is_empty()
		date["reason"] = String(why.get("reason", ""))
		if first_only and not bool(date["free"]):
			d += 1
			continue
		out.append(date)
		if first_only:
			return out
		d += 1
	return out


## Why `date` cannot be booked for `row`: {} when it can, else {code, reason, error} -- the
## code one of K.BOOK_*, the reason and the error the words (TAKE 8: codes under `code`, words
## under `reason`, as offered() and answers() carry them).
static func refusal(state, row: Dictionary, date: Dictionary) -> Dictionary:
	var today := _today(state)
	var y := int(date.get("year", 0))
	var m := int(date.get("month", 0))
	var d := int(date.get("day", 0))
	# Once only a drawn day could be booked; any day now, so an impossible one is refused here.
	if m < 1 or m > 12 or d < 1 or d > Calendar.days_in_month(y, m):
		return _no(K.BOOK_NO_DAY, "not a day of the calendar")
	if Calendar.ordinal(y, m, d) <= Calendar.ordinal(int(today["year"]), int(today["month"]), int(today["day"])):
		return _no(K.BOOK_PASSED, "that day has passed")
	if y * 12 + m > last_month(row):
		return _no(K.BOOK_DEADLINE, "after the last day they can see you")
	var taken := Calendar.refusal_reason(state, entry(row, date))
	return {} if taken.is_empty() else _no(K.BOOK_TAKEN, taken)


## The last month a day can be booked in (absolute): the deadline month ("Fin du mois limite").
## A chief's ends a month earlier, at the answer-by month: the plant lands as its deadline
## month opens, and a day in it would be an audience about a plant already gone.
static func last_month(row: Dictionary) -> int:
	return int(row["deadline_month"]) - (1 if String(row["object"]).begins_with(K.FIRM_PREFIX) else 0)


## The diary entry an audience on `date` is: Calendar's kind "audience", the
## request id in action_id (Interface's Diary reads it there).
static func entry(row: Dictionary, date: Dictionary) -> Dictionary:
	return Calendar.make_entry(CalendarK.KIND_AUDIENCE, int(date["year"]), int(date["month"]), int(date["day"]),
		String(row["id"]), String(row["person_id"]), "", "", "", String(row["person_id"]), 0)


static func _no(code: String, words: String) -> Dictionary:
	return {"code": code, "reason": words, "error": words}


## Calendar's today: a stale day past this month's end reads as its last day.
static func _today(state) -> Dictionary:
	var y := int(state.year)
	var m := int(state.month)
	return {"year": y, "month": m, "day": mini(int(state.day), Calendar.days_in_month(y, m))}
