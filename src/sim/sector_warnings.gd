extends RefCounted

## V5.3 a + b, band B7's sector source (docs/design/v5.3-ab.md 3.1 and section 7, the
## parent's option (c)): a sector's figure drifts on its own, so a held line slips into
## its bad band and the warning arrives unprovoked. Sectors.quantity() reads the drift;
## this file is the drift's month and what is read off it:
##
##   tick_month(state, loader)      the player's month: the drift's clock, the trend's
##                                  sample, the crossings. In WorldMonth's Sectors step;
##   warning(ns, loader, line, id)  "" or why the figure is in its bad band, for the
##                                  tile's mark (no UI draws it yet), read live, so it
##                                  follows a verb at once and never disagrees with it;
##   arrivals(ns, loader, now)      the sectors whose figure crossed INTO the band this
##                                  month, once per crossing: the decision arrival;
##   trend(ns, id)                  the figure, a sample a month, oldest first;
##   restore_pct_gdp(...)           the points of GDP on the line that bring the figure
##                                  back to its start, for the warning's Budget answer;
##   raise_effects(...)             that answer as effects for the game's own applier.
##
## The band is against the figure the player reads at the start (DK.WARNING_BAND), not
## against the money: a sector that answers its money weakly (digital, 0.2) has a figure
## that barely moves, so it warns rarely, and the warning never contradicts the number
## beside it. The answer verbs are the ones that exist: Sectors.move_share() into the
## sector, or the line through the Budget.
##
## THE PLAYER ONLY, as the priorities are: no other nation has a tile to read.
##
## `ns.sector_drift`, all of it absent until the first month and absent_ok in a save:
##   base_gdp_per_head  GDP per head when the drift began, what Sectors.drift_ratio()
##                      measures the money against. Taken in the first month, not at
##                      new game: an older save has none, and starts drifting from its
##                      load, which is a smaller lie than a base it never had;
##   need_months        months of need; a sector's need is (1 + its yearly rate) ^
##                      (months / 12). A count, not the factor, so a rate re-sourced in
##                      data/domains/ reads as a new game would;
##   warnings           sector id -> {entered, left}, left -1 while inside its band;
##   history            sector id -> the figure, a sample a month, oldest first.

const DK = preload("res://src/sim/domains_constants.gd")
const Sectors = preload("res://src/sim/sectors.gd")

const REASON_CUT := "Its money has been cut below where it started."  # i18n: msgid
const REASON_INCOME := "Its money per head has fallen with the economy."  # i18n: msgid
const REASON_NEED := "Its money has not kept up with the need."  # i18n: msgid


static func tick_month(state, loader) -> void:
	var ns = state.player()
	if ns == null or loader.domains.is_empty():
		return
	var drift: Dictionary = ns.sector_drift
	if not drift.has("base_gdp_per_head"):
		drift["base_gdp_per_head"] = float(ns.gdp_eur_bn) / float(ns.population)
	drift["need_months"] = int(drift.get("need_months", 0)) + 1
	var warnings: Dictionary = drift.get_or_add("warnings", {})
	var history: Dictionary = drift.get_or_add("history", {})
	var now := int(state.year) * 12 + int(state.month)
	for line in loader.domains:
		for s in Sectors.sectors_of(loader, String(line)):
			var id := String(s["id"])
			_sample(history, id, Sectors.quantity(ns, loader, String(line), id))
			_watch(warnings, id, Sectors.shortfall(ns, loader, String(line), id) >= DK.WARNING_BAND, now)


## Why the figure is in its bad band, the largest of the three causes, "" when it is
## not: the player's levers, the money per head, the need. Each is a factor of ratio(),
## so the smallest factor did the most. The reasons are msgids: the caller translates.
static func warning(ns, loader, line: String, sector_id: String) -> String:
	if Sectors.shortfall(ns, loader, line, sector_id) < DK.WARNING_BAND:
		return ""
	var income := Sectors.income_ratio(ns)
	var need := 1.0
	for s in Sectors.sectors_of(loader, line):
		if String(s["id"]) == sector_id:
			need = Sectors.need_ratio(ns, s)
	var levers := Sectors.ratio(ns, loader, line, sector_id) * need / income
	if levers <= income and levers <= 1.0 / need:
		return REASON_CUT
	return REASON_INCOME if income <= 1.0 / need else REASON_NEED


## The sectors whose figure crossed into the band at `now`: [{line, id}].
static func arrivals(ns, loader, now: int) -> Array:
	var out := []
	var warnings: Dictionary = ns.sector_drift.get("warnings", {})
	for line in loader.domains:
		for s in Sectors.sectors_of(loader, String(line)):
			var row: Dictionary = warnings.get(String(s["id"]), {})
			if not row.is_empty() and int(row["entered"]) == now:
				out.append({"line": String(line), "id": String(s["id"])})
	return out


## A copy of the sector's figures, a sample a month, oldest first, ten years at most.
static func trend(ns, sector_id: String) -> Array:
	return (ns.sector_drift.get("history", {}).get(sector_id, []) as Array).duplicate()


## The points of GDP to add to the line so the figure reads its start again, 0 for a
## figure at or above it. The share is held, so the line's other sectors gain too.
static func restore_pct_gdp(ns, loader, line: String, sector_id: String) -> float:
	var target := float(ns.start_spending_pct_gdp.get(line, 0.0)) / Sectors.held_ratio(ns, loader, line, sector_id)
	return maxf(target - float(ns.spending_pct_gdp.get(line, 0.0)), 0.0)


## restore_pct_gdp() as an effect the game's own applier books (Legislature.apply_effects).
static func raise_effects(ns, loader, line: String, sector_id: String) -> Dictionary:
	return {"spending_pct_gdp": {line: restore_pct_gdp(ns, loader, line, sector_id)}}


static func _sample(history: Dictionary, sector_id: String, figure: float) -> void:
	var samples: Array = history.get_or_add(sector_id, [])
	samples.append(figure)
	if samples.size() > DK.TREND_MONTHS:
		samples.remove_at(0)


## One arrival per crossing. A row is {entered, left}, left -1 while inside: a figure
## that left may arrive again only WARNING_REARM_MONTHS after it left.
static func _watch(warnings: Dictionary, sector_id: String, in_band: bool, now: int) -> void:
	var row: Dictionary = warnings.get(sector_id, {})
	var inside := not row.is_empty() and int(row["left"]) < 0
	if in_band and not inside and (row.is_empty() or now >= int(row["left"]) + DK.WARNING_REARM_MONTHS):
		warnings[sector_id] = {"entered": now, "left": -1}
	elif inside and not in_band:
		row["left"] = now
