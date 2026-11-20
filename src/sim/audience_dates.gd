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
		var reason := Calendar.refusal_reason(state, entry(row, date))
		date["free"] = reason.is_empty()
		date["reason"] = reason
		out.append(date)
		d += 1
	return out


## Why `date` cannot be booked for `row`: {} when it can, else {reason, error} -- the
## reason one of K.BOOK_PASSED / BOOK_DEADLINE / BOOK_TAKEN, the error the words.
static func refusal(state, row: Dictionary, date: Dictionary) -> Dictionary:
	var today := _today(state)
	var y := int(date.get("year", 0))
	var m := int(date.get("month", 0))
	var d := int(date.get("day", 0))
	# Once only a drawn day could be booked; any day now, so an impossible one is refused here.
	if m < 1 or m > 12 or d < 1 or d > Calendar.days_in_month(y, m):
		return {"reason": K.BOOK_NO_DAY, "error": "not a day of the calendar"}
	if Calendar.ordinal(y, m, d) <= Calendar.ordinal(int(today["year"]), int(today["month"]), int(today["day"])):
		return {"reason": K.BOOK_PASSED, "error": "that day has passed"}
	if y * 12 + m > last_month(row):
		return {"reason": K.BOOK_DEADLINE, "error": "after the last day they can see you"}
	var taken := Calendar.refusal_reason(state, entry(row, date))
	return {} if taken.is_empty() else {"reason": K.BOOK_TAKEN, "error": taken}


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


## Calendar's today: a stale day past this month's end reads as its last day.
static func _today(state) -> Dictionary:
	var y := int(state.year)
	var m := int(state.month)
	return {"year": y, "month": m, "day": mini(int(state.day), Calendar.days_in_month(y, m))}
