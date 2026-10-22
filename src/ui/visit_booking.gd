extends RefCounted

## A meeting verb pressed on the Diplomacy window, booked the way the Diary books
## it -- V5.1-d1b2, G13 of the play gate. The author's call on the two ways to
## visit ("Deux façons différentes"): one rule for the player, "comme dans la vraie
## vie" -- a state visit takes its travel days. And then, on the first build: "je ne
## comprends pas pourquoi quand on clique sur visite d'état, on ne peut pas choisir
## la date dans l'agenda". So the Diplomacy row does not book on its own: it opens
## the Diary's booking form (calendar_panel.gd) on that visit -- partner, act and
## travel filled in, the earliest open day offered -- and the player picks the day
## and books it there, through the Diary's own command (Calendar.book). The AI's
## instant verb is untouched: this is the player's door only.
##
## Also the form's live note, for every kind it books: the days away for a journey,
## and why a day cannot be booked, so an invalid day reads as one before the press.

const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Cooldowns = preload("res://src/sim/diplomacy_cooldowns.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")

## How far ahead the earliest open day is looked for: two months covers the
## longest journey and a diary already holding a trip.
const SEARCH_DAYS := 62


## The earliest day after today the scheduler would accept `action` with
## `target_id` on, as the entry the Diary would book; {} when none in SEARCH_DAYS.
static func earliest_entry(state, loader, action, target_id: String) -> Dictionary:
	var nation = loader.nations.get(target_id)
	var person := String(nation.leader_person_id) if nation != null else ""
	var travel: int = Diplomacy.travel_days(loader, state.player_nation_id, target_id)
	var y := int(state.year)
	var m := int(state.month)
	var d := int(state.day)
	# A host that received this verb too recently refuses every day before its free
	# one, which may be months out: the search starts there (#76, the parent's call).
	var free := host_free_day(state, action, target_id)
	if not free.is_empty():
		y = int(free["year"])
		m = int(free["month"])
		d = 0
	for _i in range(SEARCH_DAYS):
		d += 1
		if d > Calendar.days_in_month(y, m):
			d = 1
			m += 1
			if m > 12:
				m = 1
				y += 1
		var entry := Calendar.make_entry(CalendarK.KIND_DIPLOMATIC, y, m, d, String(action.id), target_id, "", "", "", person, travel)
		if Calendar.can_book(state, entry):
			return entry
	return {}


## The first day `target_id` may receive `action` again, {year, month, day}, or {}
## while nothing holds it -- Calendar.refusal_reason's day: the host register (#74)
## counts down in the month tick, so N months left is free from the 1st of month N.
static func host_free_day(state, action, target_id: String) -> Dictionary:
	var left := int(Cooldowns.hosted(state, target_id).get(String(action.id), 0))
	if left <= 0:
		return {}
	var at: int = int(state.year) * 12 + int(state.month) - 1 + left
	return {"year": at / 12, "month": at % 12 + 1, "day": 1}


## Whether the host register is all that holds `action` back from `target_id`
## (#76, the parent's call "choisir la date dans l'agenda"): a meeting verb with no
## precondition of its own (the one in the data; one with preconditions would need a
## sim query that reads them), off the player's own cooldown, proposing no agreement
## or pact a partner could refuse, that the Diary can book on a later day. Both the
## Diplomacy row and the Diary's act list read it, so they offer the same verbs.
static func held_only_by_host(state, loader, action, target_id: String) -> bool:
	if not action.opens_meeting or not action.preconditions.is_empty():
		return false
	if action.effects.has("agreement") or action.effects.has("pact"):
		return false
	var ns = state.player()
	if ns == null or ns.diplo_cooldown_months.has(Diplomacy.cooldown_key(action.id, target_id)):
		return false
	if host_free_day(state, action, target_id).is_empty():
		return false
	return not earliest_entry(state, loader, action, target_id).is_empty()


## The meeting and other verbs the player can book with `target_id`: what
## Diplomacy.available() offers today, and a meeting the host refuses only until
## its free day. Catalogue order.
static func bookable_acts(state, loader, target_id: String) -> Array:
	var offered: Array = Diplomacy.available(state, loader.diplomatic_actions, state.player_nation_id, target_id)
	var out: Array = []
	for action in loader.diplomatic_actions:
		if offered.has(action) or held_only_by_host(state, loader, action, target_id):
			out.append(action)
	return out


## The player's booking of `action` with `target_id` still in the diary, or {}.
static func booked(state, action, target_id: String) -> Dictionary:
	for entry in Calendar.booked(state):
		if String(entry.get("action_id", "")) == String(action.id) and String(entry.get("target_id", "")) == target_id:
			return entry
	return {}


## A booked journey's days away, appended to its diary row: "  (away 03–07 MAR)",
## or "" for a verb that does not travel. Moved from calendar_panel.gd at V5.1-d1b2.
static func away_text(entry: Dictionary) -> String:
	if int(entry.get("travel_days", 0)) <= 0:
		return ""
	var depart: Dictionary = Calendar.departure(entry)
	var home: Dictionary = Calendar.arrival_home(entry)
	# One month prints once -- "MAR–MAR" is always a duplicate, and the playtest
	# read it as broken text. Two months keep the span form.
	var dm := DateText.month(int(depart["month"]))
	var hm := DateText.month(int(home["month"]))
	if dm == hm:
		return Strings.t("  (away %02d–%02d %s)") % [int(depart["day"]), int(home["day"]), dm]
	return Strings.t("  (away %02d–%02d, %s–%s)") % [int(depart["day"]), int(home["day"]), dm, hm]


## The form's note for `entry`: "travel", the days away (empty for a verb that does
## not travel), and "refusal", why that day cannot be booked (empty when it can).
static func form_note(state, entry: Dictionary) -> Dictionary:
	var note := {"travel": "", "refusal": ""}
	if state == null or entry.is_empty():
		return note
	var travel := int(entry.get("travel_days", 0))
	if travel > 0:
		var depart: Dictionary = Calendar.departure(entry)
		var home: Dictionary = Calendar.arrival_home(entry)
		note["travel"] = Strings.t("Away %d %s – %d %s (%d days' travel each way).") % [
			int(depart["day"]), DateText.month(int(depart["month"])),
			int(home["day"]), DateText.month(int(home["month"])),
			travel,
		]
	if not Calendar.can_book(state, entry):
		note["refusal"] = Strings.t("This day cannot be booked: %s.") % Calendar.refusal_reason(state, entry)
	return note
