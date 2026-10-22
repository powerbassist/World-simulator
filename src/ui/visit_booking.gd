extends RefCounted

## A meeting verb pressed on the Diplomacy window, booked the way the Diary books
## it -- V5.1-d1b2, G13 of the play gate. The author's call on the two ways to
## visit ("Deux façons différentes"): one rule for the player, "comme dans la vraie
## vie" -- a state visit takes its travel days. So the Diplomacy row no longer runs
## the verb on the spot; it books it through the Diary's own command
## (Calendar.book), priced and placed exactly as calendar_panel.gd prices and
## places a booking, on the earliest day the scheduler accepts. The AI's instant
## verb is untouched: this is the player's door only, and it writes nothing the
## Diary would not.

const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")

## How far ahead the earliest open day is looked for: two months covers the
## longest journey and a diary already holding a trip.
const SEARCH_DAYS := 62


## Book `action` with `target_id` on the earliest day the scheduler accepts after
## today. The booked entry, or {} when no day in SEARCH_DAYS is open.
static func book_earliest(state, loader, action, target_id: String) -> Dictionary:
	var nation = loader.nations.get(target_id)
	var person := String(nation.leader_person_id) if nation != null else ""
	var travel: int = Diplomacy.travel_days(loader, state.player_nation_id, target_id)
	var y := int(state.year)
	var m := int(state.month)
	var d := int(state.day)
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
			Calendar.book(state, entry)
			return entry
	return {}


## The player's booking of `action` with `target_id` still in the diary, or {}.
static func booked(state, action, target_id: String) -> Dictionary:
	for entry in Calendar.booked(state):
		if String(entry.get("action_id", "")) == String(action.id) and String(entry.get("target_id", "")) == target_id:
			return entry
	return {}
