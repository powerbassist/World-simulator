extends RefCounted

## V5.3 b, band B3 (docs/design/v5.3-ab.md 4.2): a poll on any measure, the country's support
## per bloc, at a margin the player pays for. V4.2's poll on a named bill (Statute.buy_poll)
## widened, keeping its rule: bought once per measure per tier, fixed, never a reroll, and the
## price lands on the debt stock, a one-off that moves no deficit. Its two kinds stay until the
## briefing and the law panel move to these.
##
## THE KEY names the measure: a law id, an ownership bill, a draft id, a live process's id, or
## a tax change, `tax:<key>:up`. What is polled is where the measure stands: its position,
## read once at the purchase, so a poll outlives a process that closes before it arrives.
##
## THE FIELDWORK IS ON THE DAY IT ARRIVES, and the range is then fixed. Otherwise the dearest
## poll would be the stalest. So a range brackets the truth of the day it was printed.
##
## The register is the key "polls" in ns.measure_opinion, the country's opinion of a measure:
## {key: {tier: {"month", "cost", "due_day", "position", and once printed "ranges": {bloc:
## [low, high]}}}}. absent_ok like the rest of that field: a save with none bought none.

const K = preload("res://src/sim/poll_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Bills = preload("res://src/sim/bills.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Processes = preload("res://src/sim/processes.gd")
const Referendum = preload("res://src/sim/referendum.gd")


## Where a measure stands, {} for a key that names nothing a poll can read. A process verb
## with no `bill` block in content has no position yet: a data row, not a rule here.
static func position_of(ns, loader, key: String) -> Dictionary:
	if key.begins_with(K.TAX_PREFIX):
		var parts := key.split(":")
		if parts.size() == 3 and ns.tax_rates_pct.has(parts[1]) and K.TAX_POSITION.has(parts[2]):
			return K.TAX_POSITION[parts[2]]
		return {}
	var law = Bills.by_id(loader, key)
	if law != null:
		return law.position
	if ns.draft_bills.has(key):
		return ns.draft_bills[key].get("position", {})
	for row in ns.processes:
		if String(row["id"]) == key and String(row["status"]) == Processes.OPEN:
			return _process_position(loader, String(row["action_id"]))
	return {}


static func _process_position(loader, action_id: String) -> Dictionary:
	for action in loader.company_actions:
		if String(action.id) == action_id:
			return action.bill.get("position", {})
	return {}


## A measure's true support per bloc, 0 to 100, now: {} for a key that names nothing. The
## read a referendum takes of the same position, plus an address's shift on this measure.
static func support(ns, loader, key: String) -> Dictionary:
	var position := position_of(ns, loader, key)
	return {} if position.is_empty() else _support_at(ns, key, position)


static func _support_at(ns, key: String, position: Dictionary) -> Dictionary:
	var shifts: Dictionary = ((ns.measure_opinion.get("measures", {}) as Dictionary).get(key, {}) as Dictionary).get("shifts", {})
	var out := {}
	for bloc in OpinionK.BLOC_KEYS:
		out[bloc] = clampf(100.0 * Referendum.bloc_yes(ns, bloc, position) + float(shifts.get(bloc, 0.0)), 0.0, 100.0)
	return out


## The player command, buy_poll's shape: on a refusal, no mark and no charge.
static func commission(state, loader, key: String, tier: String) -> Dictionary:
	var ns = state.player()
	if not K.TIERS.has(tier):
		return _refused("There is no such poll.")
	var position := position_of(ns, loader, key)
	if position.is_empty():
		return _refused("A poll is commissioned on a measure the country can read.")
	var polls: Dictionary = (ns.measure_opinion.get("polls", {}) as Dictionary).get(key, {})
	if polls.has(tier):
		return _refused("That poll was commissioned already: the figures it bought are fixed.")
	var cost := float(K.TIERS[tier]["cost_eur_bn"])
	var today := mini(int(state.day), Calendar.days_in_month(int(state.year), int(state.month)))
	var row := {
		"month": int(state.year) * 12 + int(state.month),
		"cost": cost,
		"due_day": Calendar.day_number(int(state.year), int(state.month), today) + 7 * int(K.TIERS[tier]["weeks"]),
		"position": position.duplicate(),
	}
	((ns.measure_opinion.get_or_add("polls", {}) as Dictionary).get_or_add(key, {}) as Dictionary)[tier] = row
	ns.debt_eur_bn += cost
	return {"ok": true, "refused": false, "refusal": "", "key": key, "tier": tier, "cost_eur_bn": cost, "due_day": int(row["due_day"])}


static func _refused(why: String) -> Dictionary:
	return {"ok": false, "refused": true, "refusal": why, "cost_eur_bn": 0.0}


## Every poll due by `day` of the state's month is read and printed: the rows that arrived,
## {"key", "tier", "ranges"}. The month's close calls it with its last day; a day's driver may
## call it sooner.
static func deliver_due(state, day: int) -> Array:
	var ns = state.player()
	var out := []
	if ns == null or not ns.measure_opinion.has("polls"):
		return out
	var today := Calendar.day_number(int(state.year), int(state.month), day)
	var polls: Dictionary = ns.measure_opinion["polls"]
	for key in polls:
		for tier in polls[key]:
			var row: Dictionary = polls[key][tier]
			if not row.has("ranges") and today >= int(row["due_day"]):
				row["ranges"] = _print(ns, String(key), String(tier), row)
				out.append({"key": String(key), "tier": String(tier), "ranges": row["ranges"]})
	return out


static func _print(ns, key: String, tier: String, row: Dictionary) -> Dictionary:
	var truth := _support_at(ns, key, row["position"])
	var ranges := {}
	for bloc in truth:
		var draw := Cycle.unit(Cycle.salted("poll|%s|%s|%s" % [key, tier, bloc], int(ns.draw_seed)), int(row["month"]))
		ranges[bloc] = printed_range(float(truth[bloc]), float(K.TIERS[tier]["margin"]), draw)
	return ranges


## [low, high] around the truth. The centre stands off it by at most NOISE_SHARE of the margin,
## so the truth is inside by construction. At an edge the range slides inside 0 to 100 rather
## than being cut, so a dearer poll is narrower everywhere. Rounded outward, to what is printed.
static func printed_range(truth: float, margin: float, draw: float) -> Array:
	var centre := truth + (2.0 * draw - 1.0) * K.NOISE_SHARE * margin
	var low := centre - margin
	var high := centre + margin
	if low < 0.0:
		high -= low
		low = 0.0
	elif high > 100.0:
		low -= high - 100.0
		high = 100.0
	return [floorf(low * 10.0) / 10.0, ceilf(high * 10.0) / 10.0]


## The printed ranges of one poll, {} until it arrives.
static func result(ns, key: String, tier: String) -> Dictionary:
	var row: Dictionary = ((ns.measure_opinion.get("polls", {}) as Dictionary).get(key, {}) as Dictionary).get(tier, {})
	return row.get("ranges", {})
