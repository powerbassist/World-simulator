extends RefCounted

## The month page's wiring (picture A): the people column (diary_people.gd) and the grid's
## armed person (diary_grid.gd) joined to the sim's commands. A leaf of audience_driver.gd,
## which hands in its own booking, answer and refresh, so a request answered here goes the
## way a card's answer goes. Reads the sim, writes nothing itself: the summons is
## Audiences.summon, its cancel Audiences.decline (which gives the cap back).

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceK = preload("res://src/sim/audience_constants.gd")
const AudienceTalks = preload("res://src/ui/audience_talks.gd")
const PhoneDriver = preload("res://src/ui/phone_driver.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")
const Calendar = preload("res://src/sim/calendar.gd")


## `open_booking(id, keys)` arms a request and turns the grid to its first free day, `answer(id,
## result)` lands a command's result, `refresh()` redraws everything off the registers,
## `seen(id)` gives back the speed the request's arrival took (a verb here is the request seen,
## as the inbox card's are: pass 2 TAKE 3).
static func wire(main, game: Dictionary, open_booking: Callable, answer: Callable, refresh: Callable, seen: Callable) -> void:
	var panel = main._calendar_panel
	var grid = panel._grid
	var people = panel.people
	# See them again on the armed request lets it go: the toggle is the way out.
	people.see_requested.connect(func(id: String) -> void:
		if String(grid.armed.get("id", "")) == id and not bool(grid.armed.get("summons", false)):
			game["booking_for"] = ""
			grid.arm({})
			seen.call(id)
		else:
			open_booking.call(id, people.by_keys))
	people.delegate_requested.connect(func(id: String) -> void:
		answer.call(id, Audiences.delegate(main._state, main._state.player(), main._loader, id))
		seen.call(id))
	people.decline_requested.connect(func(id: String) -> void:
		answer.call(id, Audiences.decline(main._state, main._state.player(), main._loader, id))
		seen.call(id))
	people.cancel_requested.connect(func(id: String) -> void:
		answer.call(id, Audiences.decline(main._state, main._state.player(), main._loader, id)))
	people.call_requested.connect(func(pid: String) -> void:
		PhoneDriver.open_call(main, pid, AudienceTalks.gossip_people(main, pid)))
	people.summon_requested.connect(func(pid: String) -> void:
		game["booking_for"] = ""
		grid.arm({"id": "", "person_id": pid, "person": main._loader.person_name(pid), "summons": true})
		panel.booking.show_days(Audiences.summon_days(main._state, pid), main._state, main._loader)
		refresh.call()
		if people.by_keys:
			panel.booking.focus_day())
	grid.summoned.connect(func(pid: String, date: Dictionary) -> void:
		var ns = main._state.player()
		var result := Audiences.summon(main._state, ns, main._loader, pid, date)
		# The clock turned the picked day into today under the hand (#431 pass 2 TAKE 1, as a
		# booking): the first free day is what the player chose.
		if String(result.get("code", "")) == AudienceK.BOOK_PASSED:
			for d in Audiences.summon_days(main._state, pid):
				if bool(d["free"]):
					result = Audiences.summon(main._state, ns, main._loader, pid, d)
					break
		if bool(result.get("ok", false)):
			answer.call(String((result["request"] as Dictionary).get("id", "")), result)
		else:
			main._hud.inbox.push(Strings.t("The summons"), Strings.t(String(result.get("error", ""))))  # i18n: row-ok the sim's refusal
			refresh.call())
	grid.armed_changed.connect(func() -> void: refresh.call())


## The column off the registers: the waiting requests in `rows` (row_of's), each with the
## last day it can be seen; the people a summons reaches; the summons booked and not held.
static func show(main, rows: Array) -> void:
	var state = main._state
	var ns = state.player()
	var loader = main._loader
	# Calendar.today: the month turns before the day at the close, and a stale 31 is no date.
	var today := _unix(int(state.year), int(state.month), Calendar.today(state))
	for row in rows:
		var dates: Array = Audiences.offered_dates(state, ns, String(row["id"]))
		row["until"] = ""
		if not dates.is_empty():
			var last: Dictionary = dates[dates.size() - 1]
			row["until"] = Strings.t("any free day until %s") % DateText.day_month_year(int(last["day"]), int(last["month"]), int(last["year"]))
		# The token's ring: the share of the window left, from the month it came to the last day.
		var request := Audiences.request(ns, String(row["id"]))
		var by := Audiences.answer_by(request)
		var by_y := floori((by - 1) / 12.0)
		var end := _unix(by_y, by - by_y * 12, Calendar.days_in_month(by_y, by - by_y * 12))
		var came := int(request["arrived_month"])
		var start := _unix(floori((came - 1) / 12.0), came - floori((came - 1) / 12.0) * 12, 1)
		row["left"] = maxi(0, (end - today) / 86400)
		row["frac"] = clampf(float(end - today) / maxf(1.0, float(end - start)), 0.0, 1.0)
	var reach: Array = []
	for person in loader.people.get(String(ns.id), []):
		var pid := String(person.id)
		var why: Dictionary = Audiences.summon_refusal(state, ns, loader, pid)
		# Not his to summon, or someone already waiting on an answer (the card above answers).
		if [AudienceK.SUMMON_NOT_OWN, AudienceK.SUMMON_ASKED].has(String(why.get("code", ""))):
			continue
		var words := Strings.t(String(why.get("reason", ""))) if not why.is_empty() else ""  # i18n: row-ok the sim's refusal, its English the msgid
		if why.has("lifts"):
			var lifts := int(why["lifts"])
			var ly := floori((lifts - 1) / 12.0)
			words = Strings.t("%s: again from %s") % [words, DateText.month_year(lifts - ly * 12, ly)]
		reach.append({"person_id": pid, "person": loader.person_name(pid), "why": words})
	reach.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a["person"]) < String(b["person"]))
	var summoned: Array = []
	for row in ns.audience_requests:
		if AudienceK.is_summons(row) and String(row.get("status", "")) == AudienceK.STATUS_BOOKED:
			var d: Dictionary = row["date"]
			summoned.append({"id": String(row["id"]), "person": loader.person_name(String(row["person_id"])),
				"when": DateText.day_month_year(int(d["day"]), int(d["month"]), int(d["year"]))})
	var now := int(state.year) * 12 + int(state.month)
	var free: bool = ns.audience_summoned_month.values().filter(func(m) -> bool: return int(m) == now).size() < AudienceK.SUMMONS_PER_MONTH
	main._calendar_panel.people.show_rows(rows, reach, summoned, free, main._calendar_panel._grid.armed)


static func _unix(y: int, m: int, d: int) -> int:
	return int(Time.get_unix_time_from_datetime_dict({"year": y, "month": m, "day": d, "hour": 0, "minute": 0, "second": 0}))
