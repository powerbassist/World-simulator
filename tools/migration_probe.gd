extends SceneTree

## Migration probe: godot --headless --script res://tools/migration_probe.gd
##
## V2.6a's evidence generator. Not a test: tests/test_migration.gd asserts the
## invariants this probe is used to FIND. Kept in tools/ and excluded from
## run_tests.sh for that reason -- which also means a green suite says nothing about
## whether this file still parses, so run it before trusting the suite (V1.3e).
##
## TABLE (a) RUNS BEFORE ANY src/ CODE EXISTS, which is the point: the whole block
## rests on there being a signal to migrate on, and the honest order is to measure
## the signal before building the machine that reads it. docs/region-economy-model.md
## section 8 predicts Britain is flat on expected income; this is where that stops
## being a prediction.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Regions = preload("res://src/sim/regions.gd")
const Companies = preload("res://src/sim/companies.gd")
const Migration = preload("res://src/sim/migration.gd")
const MigrationK = preload("res://src/sim/migration_constants.gd")
const Economy = preload("res://src/sim/economy.gd")

const NATIONS := ["AUT", "BEL", "CHE", "DEU", "ESP", "FRA", "GBR", "ITA", "LUX", "NLD"]

## The three the band is read on: the three playable nations, and the three
## data/companies/ names employers in, so they are the only three where BOTH levels
## can carry a signal.
const BAND_NATIONS := ["FRA", "DEU", "GBR"]

const MONTHS := 168

## Clause (i)'s floor, fixed in src/sim/migration_constants.gd before this ran: one
## digit of src/ui/region_panel.gd's own "%.1f%%".
const READABLE_MIN := 0.001

## CLAUSE (ii)'S CEILING, AND IT IS NOT SHARE_DRIFT_MAX. The first version of this
## probe read MigrationK.SHARE_DRIFT_MAX here on a one-quantity-one-writer argument,
## and that was the defect rather than the discipline: the bound is evaluated on
## exactly the quantity worst_share_drift() returns, so the upper crossing RESTATED
## THE GUARD RAIL instead of measuring the model. This project names that failure
## repeatedly -- a band whose ceiling is the clamp measures the clamp.
##
## The replacement is MEASURED, from the same data family the register itself came
## from, and the clause it expresses is about the world rather than about the code:
## the model's regional population shares may not drift further over 168 months than
## REAL European regional population shares actually drift over a comparable span. A
## model whose people move faster than Europe's people move is wrong in a way no
## internal consistency check can see. V1.6a's precedent exactly -- the business
## cycle's amplitude was fitted to France's own measured growth volatility rather
## than to a band, because a band edge moves under widening or refinement while a fit
## converges.
##
## 0.0164, from tools/region_drift.py: Eurostat demo_r_pjangrp3 over the register's
## own NUTS codes, the widest roster-stable window per nation, share of the NATION at
## each end. The LARGEST per-region drift across the roster, not a mean -- the model
## must be able to reproduce Europe's most mobile real region without exceeding the
## ceiling, and a mean would forbid the interesting case. It is AT13 (Wien) in
## Austria, 2014-2025: 0.012871 share points over eleven years, 0.001170 a year,
## 0.016381 scaled to fourteen.
const DRIFT_CEILING := 0.0164

## THE NATIONS CLAUSE (i) IS READ ON, and the exclusion is the finding rather than a
## convenience. The clause's own sentence is "a movement the panel printing it cannot
## resolve is not a movement the player can see", so it is read per PLAYABLE nation --
## all three of these are playable -- and Britain is left out because the observable
## the clause names does not exist there: every British region carries an identical
## expected income by construction (V2.5's recorded proxy), so its region column is
## exactly 0.0000 at every candidate and its city column would need a rate of ~0.095,
## against a clause (ii) crossing at ~0.0124. There is no rate that satisfies both FOR
## BRITAIN, and the honest response is V1.6e's: record the structural bound with the
## number beside it rather than tune against an arithmetic impossibility -- the same
## treatment two of that session's three sectors got. The sweep prints Britain's
## columns anyway, so the exclusion is visible rather than silent.
const CLAUSE_I_NATIONS := ["FRA", "DEU"]

## Four grids, coarse to fine. V1.5b's diagnostic: an answer that moves under
## refinement is a statement about the grid rather than a result, so the refinement
## is part of the evidence rather than a step somebody did once and did not print.
## Each brackets both crossings with room on either side, so the passing interval can
## be checked INTERIOR rather than pinned at an endpoint by the range itself.
const SWEEPS := [
	[0.0020, 0.1000, 0.0020],
	[0.0040, 0.0300, 0.0005],
	[0.0050, 0.0200, 0.0002],
	[0.0060, 0.0180, 0.0001],
]


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("data did not load: %s" % [loader.errors])
		quit(1)
		return

	_table_a(loader)
	_table_b(loader)
	_table_c(loader)
	_table_d(loader)
	_table_e(loader)
	_table_e2(loader)
	_table_f(loader)
	quit(0)


## (a) THE STARTING SPREAD, from the content alone. Expected income is output per
## head times the probability of being employed -- Harris-Todaro, which is the
## textbook model of internal migration and carries NO free weight: it is a product
## of two ratios the register already publishes. The jobs column is the city-level
## signal, and it is zero for seven of ten nations because data/companies/ names
## employers in three.
func _table_a(loader) -> void:
	print("\n=== (a) starting pull spread: expected income, and named jobs ===")
	for nation_id in NATIONS:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		if list.is_empty():
			continue
		var rows: Array = []
		var jobs_total: float = 0.0
		for region in list:
			var per_head: float = Regions.gdp_per_head_index(ns, list, region.id, Migration.region_share(ns, region.id))
			var employed: float = 1.0 - Regions.unemployment_pct(ns, list, region.id) / 100.0
			rows.append([per_head * employed, region.region_name])
			for city in region.cities:
				jobs_total += Companies.headcount_in_city(ns, loader, city.id)
		rows.sort_custom(func(a, b): return a[0] < b[0])
		var low: float = rows[0][0]
		var high: float = rows[rows.size() - 1][0]
		print("  %s  best %-28s %.4f | worst %-28s %.4f | spread %.4f | named jobs %.0f" % [
			nation_id,
			rows[rows.size() - 1][1], high,
			rows[0][1], low,
			high - low,
			jobs_total,
		])


# --- The shipped tick, and the emulated one ------------------------------------

## THE SHIPPED MODEL, run for `months` and sampled. Everything except the sweep goes
## through Migration.tick_month() itself, so tables (b), (c), (d) and (f) measure the
## code that ships rather than this file's copy of it.
##
## The month is Economy, then Companies, then Migration -- tools/balance_probe.gd's
## own order, and the order tests/test_migration.gd asserts both harnesses keep,
## because the region pull reads settled output and the city pull settled headcount.
func _run_shipped(loader, nation_id: String, months: int) -> Dictionary:
	var state = GameState.new_game(loader, nation_id)
	var ns = state.nations[nation_id]
	var list: Array = loader.regions.get(nation_id, [])
	var start := _snapshot(ns, list)
	var out := _blank(nation_id, list)
	for i in months:
		Economy.tick_month(state)
		Companies.tick_month(state, loader)
		Migration.tick_month(state, loader)
		_accumulate(out, ns, list, start, i)
	out["drift"] = Migration.worst_share_drift(ns, list)
	return out


## THE CANDIDATE, EMULATED EXACTLY. A probe cannot change a `const` at runtime, and
## the naive workaround -- measure once at the shipped value and rescale -- makes the
## passing interval move when the shipped value moves, which is V1.6b's "the range was
## choosing the constant" wearing a second costume. So the sweep drives the candidate
## through Migration.share_delta(), which is public precisely so this is possible, in
## the shipped ORDER: cities first, regions second, both reading start-of-month state.
##
## The duplication is the price of the rule, and it is not left to trust: table (e2)
## replays this at the shipped rate against Migration.tick_month() itself and prints
## the largest disagreement, so a future edit to _tick_nation() that this copy does
## not follow shows up as a number rather than as a quiet wrong answer.
func _tick_migration(ns, list: Array, loader, rate: float) -> void:
	if list.is_empty():
		return

	for region in list:
		if region.cities.size() < 2:
			continue
		var city_pulls: Dictionary = {}
		var city_shares: Dictionary = {}
		var city_weighted: float = 0.0
		var city_total: float = 0.0
		for city in region.cities:
			var pull: float = Migration.city_pull(ns, loader, region, city.id)
			var share: float = Migration.city_share(ns, city.id)
			city_pulls[city.id] = pull
			city_shares[city.id] = share
			city_weighted += share * pull
			city_total += share
		if city_total <= 0.0:
			continue
		var city_mean: float = city_weighted / city_total
		for city in region.cities:
			var share: float = float(city_shares[city.id])
			ns.city_pop_share[city.id] = share + Migration.share_delta(share, float(city_pulls[city.id]), city_mean, rate)

	var pulls: Dictionary = {}
	var shares: Dictionary = {}
	var weighted: float = 0.0
	var total: float = 0.0
	for region in list:
		var pull: float = Migration.region_pull(ns, list, region.id)
		var share: float = Migration.region_share(ns, region.id)
		pulls[region.id] = pull
		shares[region.id] = share
		weighted += share * pull
		total += share
	if total <= 0.0:
		return
	var mean: float = weighted / total
	for region in list:
		var share: float = float(shares[region.id])
		ns.region_pop_share[region.id] = share + Migration.share_delta(share, float(pulls[region.id]), mean, rate)


# --- Bookkeeping shared by both -------------------------------------------------

## Month 0, in the ONE unit the band is written in: a place's share of its NATION.
## A region's is that directly; a city's is its region's share times its own share of
## that region, because city_pop_share is a share of the region and comparing it
## against a region's would be two quantities in one column. Britain moves only here,
## its regions being identical on expected income by construction.
func _snapshot(ns, list: Array) -> Dictionary:
	var out: Dictionary = {"region": {}, "city": {}, "city_own": {}, "region_sum": 0.0, "city_sums": {}}
	var region_sum: float = 0.0
	for region in list:
		var rs: float = Migration.region_share(ns, region.id)
		out["region"][region.id] = rs
		region_sum += rs
		var city_sum: float = 0.0
		for city in region.cities:
			out["city"][city.id] = rs * Migration.city_share(ns, city.id)
			out["city_own"][city.id] = Migration.city_share(ns, city.id)
			city_sum += Migration.city_share(ns, city.id)
		out["city_sums"][region.id] = city_sum
	out["region_sum"] = region_sum
	return out


func _blank(nation_id: String, list: Array) -> Dictionary:
	return {
		"id": nation_id,
		"regions": list.size(),
		"r60": 0.0, "c60": 0.0, "r168": 0.0, "c168": 0.0,
		"worst_region_sum_abs": 0.0, "worst_region_sum_rel": 0.0,
		"worst_city_sum_abs": 0.0, "worst_city_sum_rel": 0.0,
		"drift": 0.0, "cr168": 0.0,
		"r_name": "", "c_name": "", "cr_name": "",
	}


## The two band columns and the two partition columns, read every month -- the
## partition ones because a gap that opens and closes is still a gap, and a check
## sampled only at the end cannot see it.
func _accumulate(out: Dictionary, ns, list: Array, start: Dictionary, i: int) -> void:
	var region_sum: float = 0.0
	var r_worst: float = 0.0
	var c_worst: float = 0.0
	# The city's share of its OWN REGION, which is the quantity ns.city_pop_share
	# actually holds. Printed beside the share-of-nation column because the two differ
	# by a factor of the region's own share -- about twelve for a British region -- and
	# a Britain reported only in national units reads as a country where nothing moves
	# when what is true is that its regions do not.
	var cr_worst: float = 0.0
	var r_name: String = ""
	var c_name: String = ""
	var cr_name: String = ""
	for region in list:
		var rs: float = Migration.region_share(ns, region.id)
		region_sum += rs
		var rd: float = absf(rs - float(start["region"][region.id]))
		if rd > r_worst:
			r_worst = rd
			r_name = region.region_name
		var city_sum: float = 0.0
		for city in region.cities:
			city_sum += Migration.city_share(ns, city.id)
			var cd: float = absf(rs * Migration.city_share(ns, city.id) - float(start["city"][city.id]))
			if cd > c_worst:
				c_worst = cd
				c_name = city.city_name
			var crd: float = absf(Migration.city_share(ns, city.id) - float(start["city_own"][city.id]))
			if crd > cr_worst:
				cr_worst = crd
				cr_name = city.city_name
		var gap: float = absf(city_sum - float(start["city_sums"][region.id]))
		if gap > float(out["worst_city_sum_abs"]):
			out["worst_city_sum_abs"] = gap
		var base: float = float(start["city_sums"][region.id])
		if base > 0.0:
			out["worst_city_sum_rel"] = maxf(float(out["worst_city_sum_rel"]), gap / base)

	var national_gap: float = absf(region_sum - float(start["region_sum"]))
	out["worst_region_sum_abs"] = maxf(float(out["worst_region_sum_abs"]), national_gap)
	if float(start["region_sum"]) > 0.0:
		out["worst_region_sum_rel"] = maxf(float(out["worst_region_sum_rel"]), national_gap / float(start["region_sum"]))

	if i == 59:
		out["r60"] = r_worst
		out["c60"] = c_worst
	out["r168"] = r_worst
	out["c168"] = c_worst
	out["cr168"] = cr_worst
	out["r_name"] = r_name
	out["c_name"] = c_name
	out["cr_name"] = cr_name


# --- The tables -----------------------------------------------------------------

## (b) MOVEMENT AGAINST THE BAND, at the SHIPPED rate. Both clauses were fixed in
## src/sim/migration_constants.gd before this ran:
##   (i)  READABLE -- the largest mover's share of its nation moves at least 0.001
##        over 60 months, one digit of src/ui/region_panel.gd's own "%.1f%%".
##   (ii) BOUNDED  -- no region's share drifts more than DRIFT_CEILING over 168, the
##        largest drift a real European region measurably managed over a comparable
##        span. NOT SHARE_DRIFT_MAX: reading the guard rail here measures the guard
##        rail, which is the defect this ceiling replaces.
##
## The region and city columns are printed apart rather than folded together,
## because which level carries a nation's movement is the finding: Britain's regions
## are identical on expected income by construction (docs/region-economy-model.md
## section 8), so its whole signal is named employers and appears in the city column.
## Clause (ii) is read on the REGION column alone, which is what the bound's own
## sentence says; the city column is printed against the same figure so a city share
## of a nation running away cannot hide behind a clause that does not name it.
func _table_b(loader) -> void:
	print("\n=== (b) movement against the band, at MIGRATION_RATE %.4f ===" % MigrationK.MIGRATION_RATE)
	print("      the largest mover's change in its share of the NATION")
	print("  nation  region@60  region@168  city@60   city@168  | (i) >= %.4f @60   (ii) <= %.4f @168" % [READABLE_MIN, DRIFT_CEILING])
	for nation_id in BAND_NATIONS:
		var r := _run_shipped(loader, nation_id, MONTHS)
		var best60: float = maxf(float(r["r60"]), float(r["c60"]))
		var verdict_i := "PASS" if best60 >= READABLE_MIN else "fail"
		if not nation_id in CLAUSE_I_NATIONS:
			verdict_i = "BOUND" if best60 < READABLE_MIN else "PASS "
		print("  %s     %.4f     %.4f      %.4f    %.4f    | %s   %s     movers: %s / %s" % [
			nation_id, r["r60"], r["r168"], r["c60"], r["c168"],
			verdict_i,
			"PASS" if float(r["r168"]) <= DRIFT_CEILING else "fail",
			r["r_name"], r["c_name"],
		])


## (c) DOES THE PARTITION CLOSE? tools/regions_probe.gd's table (c) one quantity
## over, and the number tests/test_migration.gd's 1e-12 is a margin against. That
## tolerance had only ever been exercised at a rate of 0.02 inside a mutation check,
## so the realised drift at the SHIPPED rate is printed here rather than inherited:
## accumulated float error scales with the rate, and a margin nobody measured is an
## assumption wearing a number.
##
## THIS RUNS THE REAL Economy -> Companies -> Migration ORDER, through _run_shipped(),
## not tests/test_migration.gd's own frozen-pull loop that drives Migration.tick_month()
## alone -- the two numbers come from two different trajectories, and neither is
## evidence for the other's margin.
##
## Absolute AND relative, because the test's own comparison is absolute and a table
## printing only the relative figure would not be a margin against the assertion
## that exists.
func _table_c(loader) -> void:
	print("\n=== (c) does the partition close? worst gap over %d months ===" % MONTHS)
	print("  tests/test_migration.gd compares ABSOLUTE against 1e-12, so the absolute")
	print("  column is printed at eighteen decimals: at twelve, a drift of 5e-13 -- half")
	print("  the tolerance and a real finding -- rounds to 0.000000000000 and reads as a")
	print("  margin nobody has to think about.")
	print("  nation  national sum: abs / rel        each region's city sum: abs / rel")
	for nation_id in NATIONS:
		var list: Array = loader.regions.get(nation_id, [])
		if list.is_empty():
			continue
		var r := _run_shipped(loader, nation_id, MONTHS)
		var worst: float = maxf(float(r["worst_region_sum_abs"]), float(r["worst_city_sum_abs"]))
		print("  %s     %.18f / %.12f      %.18f / %.12f%s" % [
			nation_id,
			r["worst_region_sum_abs"], r["worst_region_sum_rel"],
			r["worst_city_sum_abs"], r["worst_city_sum_rel"],
			"   *** WITHIN 10x OF THE 1e-12 TEST TOLERANCE ***" if worst >= 0.0000000000001 else "",
		])


## (d) SHARE_DRIFT_MAX's SLACK. A bound and not a dial -- src/sim/region_constants.gd's
## position and src/sim/projects_constants.gd's -- so what prints is how far the worst
## region actually got. A bound that binds is one the model has outgrown; a bound with
## no slack at all was never measured. First caller of Migration.worst_share_drift().
func _table_d(loader) -> void:
	print("\n=== (d) SHARE_DRIFT_MAX %.3f -- what is left over, at month %d ===" % [MigrationK.SHARE_DRIFT_MAX, MONTHS])
	for nation_id in NATIONS:
		var list: Array = loader.regions.get(nation_id, [])
		if list.is_empty():
			continue
		var r := _run_shipped(loader, nation_id, MONTHS)
		var worst: float = float(r["drift"])
		print("  %s  worst drift %.4f, slack %.4f%s" % [
			nation_id, worst, MigrationK.SHARE_DRIFT_MAX - worst,
			"  *** BINDING ***" if worst >= MigrationK.SHARE_DRIFT_MAX else "",
		])


## (e) THE SWEEP. Four grids at four resolutions rather than one, because V1.5b's
## diagnostic is that an answer which moves under refinement was a statement about the
## grid: the interval and its midpoint are printed for each, so stability is visible
## rather than asserted. Each candidate is EMULATED (see _tick_migration) and never
## rescaled from the shipped value.
##
## The response is linear in the rate, so both clauses cross smoothly and neither edge
## selects -- docs/decision-log.md's V1.5d rule, the interior governs, and the midpoint
## of the passing interval ships.
func _table_e(loader) -> void:
	for grid in SWEEPS:
		_sweep(loader, float(grid[0]), float(grid[1]), float(grid[2]))


func _sweep(loader, low: float, high: float, step: float) -> void:
	print("\n=== (e) sweep over MIGRATION_RATE: %.4f to %.4f, step %.4f ===" % [low, high, step])
	print("  rate     FRA r@60   FRA c@60   DEU r@60   DEU c@60   GBR r@60   GBR c@60  | worst r@168 | (i) (ii)")

	var candidates: Array = []
	var steps: int = int(round((high - low) / step))
	for n in steps + 1:
		candidates.append(low + step * float(n))

	var results: Dictionary = {}
	for nation_id in BAND_NATIONS:
		results[nation_id] = _sweep_nation(loader, nation_id, candidates)

	var passing: Array = []
	for k in candidates.size():
		var candidate: float = float(candidates[k])
		var cells: Array = []
		var worst168: float = 0.0
		var ok_i := true
		for nation_id in BAND_NATIONS:
			var r: Dictionary = results[nation_id][k]
			cells.append(float(r["r60"]))
			cells.append(float(r["c60"]))
			worst168 = maxf(worst168, float(r["r168"]))
			if nation_id in CLAUSE_I_NATIONS and maxf(float(r["r60"]), float(r["c60"])) < READABLE_MIN:
				ok_i = false
		var ok_ii: bool = worst168 <= DRIFT_CEILING
		if ok_i and ok_ii:
			passing.append(candidate)
		print("  %.4f   %.5f   %.5f   %.5f   %.5f   %.5f   %.5f  | %.5f     | %s %s" % [
			candidate, cells[0], cells[1], cells[2], cells[3], cells[4], cells[5],
			worst168,
			"PASS" if ok_i else "fail",
			"PASS" if ok_ii else "fail",
		])

	if passing.is_empty():
		print("  NO CANDIDATE PASSES BOTH CLAUSES ON THIS GRID -- the kill switch has fired.")
		return
	var lo: float = float(passing[0])
	var hi: float = float(passing[passing.size() - 1])
	var interior: bool = lo > low + step * 0.5 and hi < high - step * 0.5
	print("  passing interval [%.4f, %.4f]   midpoint %.4f   %s" % [
		lo, hi, (lo + hi) / 2.0,
		"both edges INTERIOR to the swept range" if interior else "*** AN EDGE OF THE SWEPT RANGE PASSES -- WIDEN ***",
	])


## EVERY CANDIDATE IN ONE PASS OVER THE MONTHS, and the reason it is sound is a fact
## about the model rather than an optimisation somebody hoped was harmless: NOTHING
## in src/sim/ outside migration.gd reads region_pop_share or city_pop_share, so the
## economy's trajectory does not depend on the rate. That is the same fact the
## balance re-run's bit-identity prediction rests on. So the month is ticked once and
## each candidate's own pair of share registers is swapped onto the nation for the
## length of its own migration tick -- N lanes over one economy, rather than N
## economies. Running them apart gave identical figures on the grid this replaced.
func _sweep_nation(loader, nation_id: String, candidates: Array) -> Array:
	var state = GameState.new_game(loader, nation_id)
	var ns = state.nations[nation_id]
	var list: Array = loader.regions.get(nation_id, [])
	var start := _snapshot(ns, list)

	var lanes: Array = []
	var outs: Array = []
	for k in candidates.size():
		lanes.append([ns.region_pop_share.duplicate(true), ns.city_pop_share.duplicate(true)])
		outs.append(_blank(nation_id, list))

	for i in MONTHS:
		Economy.tick_month(state)
		Companies.tick_month(state, loader)
		for k in candidates.size():
			ns.region_pop_share = lanes[k][0]
			ns.city_pop_share = lanes[k][1]
			_tick_migration(ns, list, loader, float(candidates[k]))
			_accumulate(outs[k], ns, list, start, i)

	for k in candidates.size():
		ns.region_pop_share = lanes[k][0]
		outs[k]["drift"] = Migration.worst_share_drift(ns, list)
	return outs


## (e2) IS THE EMULATION THE SHIPPED MODEL? The sweep drives a copy of _tick_nation()
## and a copy is worth exactly what its last check says. This replays both at the
## SHIPPED rate over the full run and prints the largest disagreement in any share.
## At MIGRATION_RATE 0.0 both are inert and the check is vacuous, which is itself
## worth printing rather than reading as a pass.
func _table_e2(loader) -> void:
	print("\n=== (e2) the emulation against Migration.tick_month(), at %.4f ===" % MigrationK.MIGRATION_RATE)
	for nation_id in BAND_NATIONS:
		var shipped_state = GameState.new_game(loader, nation_id)
		var shipped_ns = shipped_state.nations[nation_id]
		var mirror_state = GameState.new_game(loader, nation_id)
		var mirror_ns = mirror_state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		for i in MONTHS:
			Economy.tick_month(shipped_state)
			Companies.tick_month(shipped_state, loader)
			Migration.tick_month(shipped_state, loader)
			Economy.tick_month(mirror_state)
			Companies.tick_month(mirror_state, loader)
			_tick_migration(mirror_ns, list, loader, MigrationK.MIGRATION_RATE)
		var worst: float = 0.0
		for region in list:
			worst = maxf(worst, absf(Migration.region_share(shipped_ns, region.id) - Migration.region_share(mirror_ns, region.id)))
			for city in region.cities:
				worst = maxf(worst, absf(Migration.city_share(shipped_ns, city.id) - Migration.city_share(mirror_ns, city.id)))
		print("  %s  largest disagreement in any share over %d months: %.15f%s" % [
			nation_id, MONTHS, worst,
			"   (vacuous: the shipped rate is 0.0)" if MigrationK.MIGRATION_RATE == 0.0 else "",
		])


## (f) REACHABILITY, per nation, at the shipped rate. Two of the ten are BOUNDS with
## numbers beside them rather than defects, and both were known before this ran:
## Britain's regions carry an identical expected income by construction (V2.5's
## recorded proxy, docs/region-economy-model.md section 8), so it moves only on named
## employers at the city level; and Luxembourg is ONE region holding ONE city, so
## `pull - mean` is exactly 0.0 at both levels and it cannot move at either however
## large the rate. Seven of the ten name no employer at all -- data/companies/ covers
## three -- so their city level is inert and their region level is the whole of their
## movement.
func _table_f(loader) -> void:
	print("\n=== (f) reachability: who moves, at MIGRATION_RATE %.4f ===" % MigrationK.MIGRATION_RATE)
	print("  nation  regions  cities  region@168  city@168  city-in-region@168   note")
	for nation_id in NATIONS:
		var list: Array = loader.regions.get(nation_id, [])
		if list.is_empty():
			continue
		var cities: int = 0
		for region in list:
			cities += region.cities.size()
		var employers: bool = not loader.companies.get(nation_id, []).is_empty()
		var r := _run_shipped(loader, nation_id, MONTHS)
		# Read off the CONTENT rather than off the measurement: a flat expected income
		# is a fact about the register and stays true at a rate of 0.0, where a note
		# keyed on "this nation did not move" would call every nation flat.
		var spread: float = _pull_spread(loader, nation_id, list)
		var note := ""
		if list.size() < 2 and cities < 2:
			note = "BOUND: one region holding one city -- cannot move at either level"
		elif spread < 0.000000001 and employers:
			note = "BOUND: expected income identical across its regions -- moves only on named employers"
		elif spread < 0.000000001:
			note = "BOUND: expected income identical AND no named employers -- cannot move at either level"
		elif not employers:
			note = "no named employers: the city level is inert, the region level is the whole signal"
		else:
			note = "moves at both levels"
		print("  %s     %2d      %3d     %.4f      %.4f    %.4f (%s)   %s" % [
			nation_id, list.size(), cities, r["r168"], r["c168"], r["cr168"], r["cr_name"], note,
		])


## The spread in expected income across a nation's regions at new game -- the signal
## the region level runs on, before anything has ticked. Zero means the level cannot
## discriminate at any rate.
func _pull_spread(loader, nation_id: String, list: Array) -> float:
	var state = GameState.new_game(loader, nation_id)
	var ns = state.nations[nation_id]
	var lo: float = 999.0
	var hi: float = -999.0
	for region in list:
		var p: float = Migration.region_pull(ns, list, region.id)
		lo = minf(lo, p)
		hi = maxf(hi, p)
	if hi < lo:
		return 0.0
	return hi - lo
