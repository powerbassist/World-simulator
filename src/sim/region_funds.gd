extends RefCounted

## V5.3 a (docs/design/v5.3-ab.md 3.3 (a), band A7): the regional development fund,
## a chosen share of one region's output a year for 1 to 5 years, the bill in euros and fixed
## at the opening (the author, 2026-11-09: 1 bn was 0.12 % of London, 2.2 % of DE5). One open fund per region; the rule's
## ranges and bloc offsets are data (data/region-actions/fund.json), the response is
## region_fund_constants.FUND_BETA.
##
##   the money   a Budget line of its own, `ns.region_fund_bill_pct_gdp`, written
##               by tick_month() for the Budget to read a month behind (the other
##               computed lines' lag: `deficit_pct_gdp` is a precondition field);
##   the effect  a term in the region's growth deviation, FUND_BETA x sqrt(the fund
##               as a percentage of the region's output), fixed at the start and read by
##               src/sim/regions.gd from the open rows -- zero-mean over the nation's
##               output, so it moves growth between regions, never the nation's,
##               and the region's unemployment falls by Okun's share of it;
##   the demand  the national level: a fund is spending, so the bill's change moves
##               `demand_impulse_pct` through the channel every spending change takes
##               (Budget.commit()'s MULT_SPENDING over impulse_level_factor()), up when
##               it starts billing and down when it stops, so its level effect over
##               the fund's life sums to zero -- a transfer to the region paid by the
##               deficit, with the stimulus any spending of its size would give;
##   the blocs   the rule's offsets per level x the level x the region's share of the
##               population, at the start (blocs are national, a fund is not);
##               stopping early gives back FUND_STOP_SHARE of what each pleased
##               bloc gained.
##
## The register `ns.region_funds` is saved whole (absent_ok: no save before V5.3 a
## could hold a fund). A row's `unemployment_at_start` is the region's figure the month it
## opened, for its row to say what changed; a fund opened before that key has none, reads
## no comparison and earns no bump (the figure was never recorded, so nothing can be
## shown wrongly: tests/test_region_fund.gd pins the row without it). sqrt() runs only in start() and estimate(), the player's verb
## and its strip, on the main thread; no tick step computes the term.

const Regions = preload("res://src/sim/regions.gd")
const RK = preload("res://src/sim/region_constants.gd")
const FK = preload("res://src/sim/region_fund_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")

const OPEN := FK.STATUS_OPEN


## Open a fund. {ok, id} or {ok: false, reason}; a refusal writes nothing.
static func start(state, ns, loader, region_id: String, share_pct: float, years: int) -> Dictionary:
	var why := refusal(state, ns, loader, region_id, share_pct, years)
	if why != "":
		return {"ok": false, "reason": why}
	var row := _row(state, ns, loader, region_id, share_pct, years)
	row["unemployment_at_start"] = unemployment_here(state, ns, region_id)
	_blocs(ns, row["bloc_offset"], 1.0)
	ns.region_funds.append(row)
	return {"ok": true, "id": String(row["id"])}


## The strip's figures for a fund not yet opened: {ok, pts, eur_bn_per_year,
## total_eur_bn, months, unemployment_now, unemployment_after, bloc_offset}, or
## {ok: false, reason}. `unemployment_after` is the region's figure with the fund
## open, read through the same Regions function the game reads, so it is the booked
## figure (the term is immediate; later months move it with the national rate).
static func estimate(state, ns, loader, region_id: String, share_pct: float, years: int) -> Dictionary:
	var why := refusal(state, ns, loader, region_id, share_pct, years)
	if why != "":
		return {"ok": false, "reason": why}
	var row := _row(state, ns, loader, region_id, share_pct, years)
	var eur_bn := float(row["eur_bn_per_year"])
	var list: Array = state.regions.get(ns.id, [])
	var access := Regions.accessibility_for(ns, list, state.region_graph)
	var sites: Dictionary = state.project_sited_pct.get(ns.id, {})
	var now := Regions.unemployment_pct(ns, list, region_id, access, sites)
	# The row is appended for one synchronous read and removed at once: the read is
	# the game's own arithmetic, with nothing between the two writes.
	ns.region_funds.append(row)
	var after := Regions.unemployment_pct(ns, list, region_id, access, sites)
	ns.region_funds.pop_back()
	return {"ok": true, "pts": float(row["pts"]), "eur_bn_per_year": eur_bn, "total_eur_bn": eur_bn * float(years),
		"months": years * 12, "unemployment_now": now, "unemployment_after": after,
		"bloc_offset": (row["bloc_offset"] as Dictionary).duplicate()}


## The region's unemployment now, through the function the game reads.
static func unemployment_here(state, ns, region_id: String) -> float:
	var list: Array = state.regions.get(ns.id, [])
	return Regions.unemployment_pct(ns, list, region_id, Regions.accessibility_for(ns, list, state.region_graph),
		state.project_sited_pct.get(ns.id, {}))


## The rule's ranges and the cap, {share_pct: [lowest, highest], years: [shortest,
## longest], max_open}, for
## the panel's inputs and its refusal line (the msgids below carry no figures, so
## they stay translatable; the panel prints the range from here).
static func limits(loader) -> Dictionary:
	var rule: Dictionary = loader.region_fund_rule
	if rule.is_empty():
		return {}
	return {"share_pct": (rule["share_pct"] as Array).duplicate(), "years": (rule["years"] as Array).duplicate(),
		"max_open": FK.FUND_MAX_OPEN}


## Why a fund cannot open, "" when it can. English msgids, the panel's line.
static func refusal(state, ns, loader, region_id: String, share_pct: float, years: int) -> String:
	var rule: Dictionary = loader.region_fund_rule
	if rule.is_empty():
		return "No regional fund rule is loaded."
	var named := false
	for region in state.regions.get(ns.id, []):
		if region.id == region_id and region_id != RK.RESIDUAL_KEY:
			named = true
	if not named:
		return "That is not one of this nation's regions."
	if share_pct < float(rule["share_pct"][0]) or share_pct > float(rule["share_pct"][1]):
		return "A fund runs between its lowest and highest shares of the region's output."
	if years < int(rule["years"][0]) or years > int(rule["years"][1]):
		return "A fund runs for between its shortest and longest number of years."
	if Regions.output_eur_bn(ns, region_id) <= 0.0:
		return "This region has no recorded output to fund."
	var open := 0
	for row in ns.region_funds:
		if String(row["status"]) != OPEN:
			continue
		if String(row["region_id"]) == region_id:
			return "This region already has a development fund."
		open += 1
	if open >= FK.FUND_MAX_OPEN:
		return "The most development funds that can run at once are already running."
	return ""


## Stop a fund early. {ok} or {ok: false, reason}.
static func stop(state, ns, fund_id: String) -> Dictionary:
	for row in ns.region_funds:
		if String(row["id"]) == fund_id and String(row["status"]) == OPEN:
			var back := {}
			for bloc in row["bloc_offset"]:
				if float(row["bloc_offset"][bloc]) > 0.0:
					back[bloc] = -FK.FUND_STOP_SHARE * float(row["bloc_offset"][bloc])
			_blocs(ns, back, 1.0)
			_close(state, row, "stopped")
			return {"ok": true}
	return {"ok": false, "reason": "This fund is no longer running."}


## The open funds, oldest first, as copies for a panel to read.
static func open_funds(ns) -> Array:
	var out: Array = []
	for row in ns.region_funds:
		if String(row["status"]) == OPEN:
			out.append((row as Dictionary).duplicate(true))
	return out


## A month of every open fund: its bill (the Budget reads it next month) and the
## bill's change into demand (Economy reads it next month), then a month off its run;
## a fund at its end closes "done". WorldMonth runs this after Projects, the other
## bill that stops, for the same lag.
static func tick_month(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		if ns.region_funds.is_empty():
			continue
		var bill := 0.0
		for row in ns.region_funds:
			if String(row["status"]) != OPEN:
				continue
			if float(ns.gdp_eur_bn) > 0.0:
				bill += 100.0 * float(row["eur_bn_per_year"]) / float(ns.gdp_eur_bn)
			row["months_left"] = int(row["months_left"]) - 1
			if int(row["months_left"]) <= 0:
				_close(state, row, "done")
		# Budget.commit()'s spending term on the bill's change (its arithmetic, the
		# same constants and the same clamp): the start, the end and GDP's drift in
		# between telescope, so a fund leaves no lasting impulse -- unless a step
		# lands while the impulse sits at IMPULSE_MAX_PCT, where the clamp clips it,
		# as it clips a commit's.
		ns.demand_impulse_pct = clampf(
			ns.demand_impulse_pct
				+ (bill - float(ns.region_fund_bill_pct_gdp)) * C.MULT_SPENDING / C.impulse_level_factor(),
			-C.IMPULSE_MAX_PCT, C.IMPULSE_MAX_PCT)
		ns.region_fund_bill_pct_gdp = bill


static func _row(state, ns, loader, region_id: String, share_pct: float, years: int) -> Dictionary:
	var now := _now(state)
	var eur_bn := share_pct / 100.0 * Regions.output_eur_bn(ns, region_id)
	var pop := float(ns.region_pop_share.get(region_id, 0.0))
	var offsets := {}
	var per_pct: Dictionary = loader.region_fund_rule["bloc_offset_per_pct"]
	for bloc in per_pct:
		offsets[bloc] = float(per_pct[bloc]) * share_pct * pop
	return {
		"id": "%s|%d|%d" % [region_id, now, ns.region_funds.size()], "region_id": region_id,
		"eur_bn_per_year": eur_bn, "years": years, "started": now, "months_left": years * 12,
		"pts": FK.FUND_BETA * sqrt(share_pct),
		"bloc_offset": offsets, "status": OPEN, "closed": -1,
	}


static func _close(state, row: Dictionary, status: String) -> void:
	row["status"] = status
	row["closed"] = _now(state)


## Clamped, as every writer of the register is (Companies.execute's comment).
static func _blocs(ns, offsets: Dictionary, share: float) -> void:
	for bloc in offsets:
		ns.bloc_offset[bloc] = clampf(float(ns.bloc_offset.get(bloc, 0.0)) + share * float(offsets[bloc]),
			LK.BLOC_OFFSET_MIN, LK.BLOC_OFFSET_MAX)


static func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)
