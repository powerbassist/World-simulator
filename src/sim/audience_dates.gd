extends RefCounted

## The days a person offers for an audience, and the diary entry an audience is.
## Split out of audiences.gd at pre-gate B, when the month-3 guarantee met that
## file's 300-line cap; Audiences keeps offered_dates() and delegates, so no caller
## moved. A leaf over Calendar and Cycle.

const K = preload("res://src/sim/audience_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")


## The days the person offers for `row`, in date order, each with whether the
## diary can place it. Drawn from the request's id, so the card is the same every
## time it is opened; a day that has passed reads not free, with Calendar's reason.
static func offered(state, ns, row: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
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
		var pick := int(Cycle.unit_pair(String(row["id"]), Cycle.salted(K.SALT_DATE, ns.draw_seed), k) * float(total))
		if not picks.has(pick):
			picks.append(pick)
		k += 1
	picks.sort()
	for pick in picks:
		var left := pick
		for span in spans:
			if left < int(span[1]):
				var date := {"year": int(span[0]["year"]), "month": int(span[0]["month"]), "day": left + 1}
				var reason := Calendar.refusal_reason(state, entry(row, date))
				date["free"] = reason.is_empty()
				date["reason"] = reason
				out.append(date)
				break
			left -= int(span[1])
	return out


## The diary entry an audience on `date` is: Calendar's kind "audience", the
## request id in action_id (Interface's Diary reads it there).
static func entry(row: Dictionary, date: Dictionary) -> Dictionary:
	return Calendar.make_entry(CalendarK.KIND_AUDIENCE, int(date["year"]), int(date["month"]), int(date["day"]),
		String(row["id"]), String(row["person_id"]), "", "", "", String(row["person_id"]), 0)


static func _ym(absolute: int) -> Dictionary:
	var year := floori((absolute - 1) / 12.0)
	return {"year": year, "month": absolute - year * 12}
