extends RefCounted

## V5.3 b, band B5 (docs/design/v5.3-ab.md 4.3): the president goes on air about an open bill.
## It moves the country's opinion of that bill, per bloc, and the deputies whose voters moved
## feel it in the division (DivisionTerms.sway_share reads the register, so every caller and
## the forecast do).
##
## The register, ns.measure_opinion, one field: {"measures": {law id: {"months_left", "shifts":
## {bloc: points away from neutral}}}, "given": [the month of each address in the window]}.
## {} when nothing is live, and on every game that has given none.
##
## THE DIARY IS THE PRICE, AND IT HAS NO HALF-DAY. The spec says a half-day. The diary's unit is
## the day and its rule is one thing at a time, and half a day would need a second kind of day
## for one verb. So an address takes today, or is refused with the diary's own reason. It is
## given at once and its row is left booked, which is what holds the day; nothing is left for
## the day's driver to do but mark it.

const K = preload("res://src/sim/address_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Media = preload("res://src/sim/media.gd")
const Referendum = preload("res://src/sim/referendum.gd")


## The shift an address would bring, per bloc. `worth` discounts what persuades and not what
## hardens (address_constants.HARDEN_SHARE). A bloc's lean is the read a referendum takes of
## the same position, so the country has one opinion of where a bill stands.
static func shifts(ns, outlets: Array, law, worth_now: float) -> Dictionary:
	var standing := clampf(float(ns.overall_approval_pct) / OpinionK.APPROVAL_NEUTRAL, K.STANDING_MIN, K.STANDING_MAX)
	var persuades: float = K.PERSUASION_FLAT * standing * worth_now
	var out := {}
	for bloc in OpinionK.BLOC_KEYS:
		var yes := Referendum.bloc_yes(ns, bloc, law.position)
		var heard := _heard(ns, outlets, bloc)
		if yes < 0.5 - K.LEAN_BAND:
			out[bloc] = -K.HARDEN_SHARE * K.SHIFT_TOWARD * heard
		elif yes > 0.5 + K.LEAN_BAND:
			out[bloc] = K.SHIFT_TOWARD * persuades * heard
		else:
			out[bloc] = K.SHIFT_NEUTRAL * persuades * heard
	return out


## How far a bloc's own outlets carry it.
static func _heard(ns, outlets: Array, bloc: String) -> float:
	var carried := 0.0
	for outlet in outlets:
		if outlet.audience == bloc:
			carried += float(outlet.reach) * Media.outlet_alignment(outlet, ns)
	return clampf(1.0 + K.OUTLET_BETA * carried, K.OUTLET_MIN, K.OUTLET_MAX)


## What the next address persuades, against the first's, at month `now` (year * 12 + month).
static func worth(ns, now: int) -> float:
	var earlier := 0
	for month in (ns.measure_opinion.get("given", []) as Array):
		if now - int(month) < K.REPEAT_WINDOW_MONTHS:
			earlier += 1
	return pow(K.REPEAT_WORTH, earlier)


## The player command: {"ok", "error"}, and on ok what it did, "shifts" and "worth". Refused,
## it leaves no mark. The law is the open bill at its reference: a grade is a number the
## opinion of it does not read, and a tabled bill stays open until its division.
static func give(state, loader, law_id: String) -> Dictionary:
	var ns = state.player()
	var law = Legislature.open_law(state, ns, loader, law_id)
	if law == null:
		return {"ok": false, "error": "no such bill is open"}
	var today := mini(int(state.day), Calendar.days_in_month(int(state.year), int(state.month)))
	var booked: Dictionary = Calendar.book(state, Calendar.make_entry(CalendarK.KIND_ADDRESS, int(state.year), int(state.month), today, "", "", law_id))
	if not bool(booked["ok"]):
		return booked
	var now: int = int(state.year) * 12 + int(state.month)
	var worth_now := worth(ns, now)
	var moved := shifts(ns, loader.outlets.get(ns.id, []), law, worth_now)
	_write(ns, law_id, moved, now)
	var price := {}
	for bloc in moved:
		if float(moved[bloc]) < 0.0:
			price[bloc] = -K.APPROVAL_PRICE
	if not price.is_empty():
		Legislature.apply_effects(state, ns, {"bloc_offset": price}, loader)
	return {"ok": true, "error": "", "shifts": moved, "worth": worth_now}


static func _write(ns, law_id: String, moved: Dictionary, now: int) -> void:
	var row: Dictionary = (ns.measure_opinion.get_or_add("measures", {}) as Dictionary).get_or_add(law_id, {"shifts": {}})
	for bloc in moved:
		row["shifts"][bloc] = float(row["shifts"].get(bloc, 0.0)) + float(moved[bloc])
	row["months_left"] = K.FADE_MONTHS
	(ns.measure_opinion.get_or_add("given", []) as Array).append(now)


## What the strip reads before the player acts, for `law` at the grade it is tabled at: the
## shift, what this address is worth, and the division before and after. Pure, on a copy.
static func estimate(state, ns, loader, law) -> Dictionary:
	var now: int = int(state.year) * 12 + int(state.month)
	var worth_now := worth(ns, now)
	var moved := shifts(ns, loader.outlets.get(ns.id, []), law, worth_now)
	var parties: Array = loader.parties.get(ns.id, [])
	var after = ns.duplicate_state()
	_write(after, String(law.id), moved, now)
	return {"shifts": moved, "worth": worth_now,
		"before": Legislature.resolve_vote(ns, parties, law), "after": Legislature.resolve_vote(after, parties, law)}


## The month's close: every shift a third nearer nothing, the window's old addresses forgotten,
## and the month's rows marked, here for a game with no day's driver. An address is dated the
## day it is given, so none is ahead of the close.
static func tick_month(state) -> void:
	var ns = state.player()
	if ns == null or ns.measure_opinion.is_empty():
		return
	var now: int = int(state.year) * 12 + int(state.month)
	var measures: Dictionary = ns.measure_opinion.get("measures", {})
	for law_id in measures.keys():
		var row: Dictionary = measures[law_id]
		var left := int(row["months_left"])
		for bloc in row["shifts"]:
			row["shifts"][bloc] = float(row["shifts"][bloc]) * float(left - 1) / float(left)
		row["months_left"] = left - 1
		if left <= 1:
			measures.erase(law_id)
	var given: Array = (ns.measure_opinion.get("given", []) as Array).filter(func(month) -> bool:
		return now - int(month) < K.REPEAT_WINDOW_MONTHS)
	ns.measure_opinion["given"] = given
	if measures.is_empty() and given.is_empty():
		ns.measure_opinion = {}
	for entry in state.appointments.duplicate():
		if String(entry["kind"]) == CalendarK.KIND_ADDRESS and String(entry["status"]) == CalendarK.STATUS_BOOKED:
			Calendar.resolve(state, Calendar.verb_key(entry), true)
