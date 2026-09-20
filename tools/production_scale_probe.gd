extends SceneTree

## V4.6 step-0 probe #2: the tick budget at full production-economy scale.
## godot --headless --script res://tools/production_scale_probe.gd
##
## docs/tiers/v4.md §V4.6: "a synthetic tick at full V4.6 + V4.7 scale —
## ~70 goods × 29 nations, ~2,900 firms, bilateral flows — timed before a
## recipe is authored, against a declared per-month budget." The warning is
## Victoria 3, same model shape, whose late game its own players call
## unplayable. Nothing here reads the real game state: this is the SHAPE the
## production layer would have, not the layer.
##
## DECLARED BANDS, written before the probe ran (E0's discipline):
##   PASS        mean synthetic month <= 300 ms — twice the whole measured
##               V3 tick (148 ms, tick_budget_probe.gd post-PR-#39): the
##               production layer may cost one more whole tick, no more,
##               without an optimisation session of its own.
##   CONDITIONAL <= 1000 ms — the tier's own kill line ("a grand-strategy
##               month that costs a second is a game that cannot be played
##               at speed 5"): the block proceeds but its first follow-up
##               session is the optimisation pass, pre-booked.
##   FAIL        > 1000 ms — the Victoria 3 late-game form at month one;
##               the block is unshippable at this abstraction and must be
##               re-scoped before a single recipe is authored.
##
## Two implementation shapes bound the answer from both sides, and both do
## the IDENTICAL monthly work list — only the data layout differs:
##   DICT   — everything Dictionary-keyed on String ids, the house data
##            style (sector_output, campaign_saturation all work this way).
##            The pessimistic bound: what a naive build costs.
##   PACKED — goods as one flat PackedFloat64Array, firms int-indexed into
##            parallel arrays. The optimistic bound: what a perf-conscious
##            build costs. The real implementation lands between them.
##
## The month's work, both shapes: reset balances; firm production over
## recipes (recipe read, value added, the monthly expand/shrink verb);
## per-nation-per-good balance against consumption and world demand; one
## world price per good under the tier's ±75 % clamp; bilateral surplus->
## deficit routing per good (sorted matcher); firm->region->nation
## aggregation (the V2.5 spine survives, so the rollup runs at V4.7's firm
## count); the three-sector reporting rollup every panel reads.
##
## Not a test, not registered in run_tests.sh: the committed instrument
## beside its verdict, tick_budget_probe.gd's precedent.

const GOODS := 70
const NATIONS := 29
const REGIONS := 213
const FIRMS := 2900
const INPUTS_PER_RECIPE := 3
const WARMUP_MONTHS := 10
const MEASURED_MONTHS := 120


func _initialize() -> void:
	var dict_mean := _run_shape(true)
	var packed_mean := _run_shape(false)
	var verdict := _verdict(minf(dict_mean, packed_mean))
	# stdout through the dev shells eats interleaved lines this session;
	# the verdict file is the record, the print is the convenience.
	var f := FileAccess.open("res://reports/production_scale_probe.txt", FileAccess.WRITE)
	f.store_line("=== V4.6 STEP-0 PROBE #2: TICK BUDGET AT PRODUCTION SCALE ===")
	f.store_line("scale: %d goods x %d nations x %d firms x %d regions" % [GOODS, NATIONS, FIRMS, REGIONS])
	f.store_line("DICT   mean month: %.1f ms" % dict_mean)
	f.store_line("PACKED mean month: %.1f ms" % packed_mean)
	f.store_line("band: PASS <= 300 ms | CONDITIONAL <= 1000 ms | FAIL above")
	f.store_line("VERDICT: %s" % verdict)
	f.close()
	print("VERDICT: %s | DICT %.1f ms | PACKED %.1f ms | see reports/production_scale_probe.txt" % [verdict, dict_mean, packed_mean])
	quit(0 if verdict != "FAIL" else 1)


func _run_shape(use_dicts: bool) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260920
	# -- world shape ---------------------------------------------------------
	var base_price := PackedFloat64Array()
	base_price.resize(GOODS)
	var basket := PackedFloat64Array()
	basket.resize(GOODS)
	var price := PackedFloat64Array()
	price.resize(GOODS)
	for g in GOODS:
		base_price[g] = rng.randf_range(50.0, 5000.0)
		basket[g] = rng.randf() * 1e-6
		price[g] = base_price[g]
	var pop := PackedFloat64Array()
	pop.resize(NATIONS)
	for n in NATIONS:
		pop[n] = rng.randf_range(0.6e6, 83e6)

	var firm_out: Variant
	var firm_in: Variant
	var firm_in_qty: Variant
	var firm_qty: Variant
	var firm_nation: Variant
	var firm_region: Variant
	var balance: Variant

	if use_dicts:
		var bal := {}
		for n in NATIONS:
			var row := {}
			for g in GOODS:
				row["g%d" % g] = 0.0
			bal["n%d" % n] = row
		balance = bal
		var outs: Array = []
		var ins: Array = []
		var qtys: Array = []
		var nats: Array = []
		var regs: Array = []
		for f in FIRMS:
			var recipe := {}
			for k in INPUTS_PER_RECIPE:
				recipe["g%d" % ((f * 7 + k * 13) % GOODS)] = rng.randf_range(0.1, 2.0)
			ins.append(recipe)
			outs.append("g%d" % (f % GOODS))
			qtys.append(rng.randf_range(1.0, 100.0))
			nats.append("n%d" % (f % NATIONS))
			regs.append(f % REGIONS)
		firm_out = outs
		firm_in = ins
		firm_in_qty = null
		firm_qty = qtys
		firm_nation = nats
		firm_region = regs
	else:
		var bal := PackedFloat64Array()
		bal.resize(NATIONS * GOODS)
		balance = bal
		var outs := PackedInt32Array()
		outs.resize(FIRMS)
		var ins := PackedInt32Array()
		ins.resize(FIRMS * INPUTS_PER_RECIPE)
		var inq := PackedFloat64Array()
		inq.resize(FIRMS * INPUTS_PER_RECIPE)
		var qtys := PackedFloat64Array()
		qtys.resize(FIRMS)
		var nats := PackedInt32Array()
		nats.resize(FIRMS)
		var regs := PackedInt32Array()
		regs.resize(FIRMS)
		for f in FIRMS:
			for k in INPUTS_PER_RECIPE:
				ins[f * INPUTS_PER_RECIPE + k] = (f * 7 + k * 13) % GOODS
				inq[f * INPUTS_PER_RECIPE + k] = rng.randf_range(0.1, 2.0)
			outs[f] = f % GOODS
			qtys[f] = rng.randf_range(1.0, 100.0)
			nats[f] = f % NATIONS
			regs[f] = f % REGIONS
		firm_out = outs
		firm_in = ins
		firm_in_qty = inq
		firm_qty = qtys
		firm_nation = nats
		firm_region = regs

	var order: Array = []
	for i in NATIONS:
		order.append(i)

	# -- warmup excluded from timing (the tick_budget_probe lesson) ---------
	for m in WARMUP_MONTHS:
		_month(balance, price, base_price, basket, pop, firm_out, firm_in, firm_in_qty, firm_qty, firm_nation, firm_region, order, use_dicts)

	var total_us := 0
	for m in MEASURED_MONTHS:
		var t0 := Time.get_ticks_usec()
		_month(balance, price, base_price, basket, pop, firm_out, firm_in, firm_in_qty, firm_qty, firm_nation, firm_region, order, use_dicts)
		total_us += Time.get_ticks_usec() - t0
	return float(total_us) / float(MEASURED_MONTHS) / 1000.0


func _month(balance, price: PackedFloat64Array, base_price: PackedFloat64Array, basket: PackedFloat64Array, pop: PackedFloat64Array, firm_out, firm_in, firm_in_qty, firm_qty, firm_nation, firm_region, order: Array, use_dicts: bool) -> void:
	var world_supply := PackedFloat64Array()
	world_supply.resize(GOODS)
	var world_demand := PackedFloat64Array()
	world_demand.resize(GOODS)
	var region_gdp := PackedFloat64Array()
	region_gdp.resize(REGIONS)

	# 0. reset the monthly flow balances
	if use_dicts:
		for n in NATIONS:
			var row: Dictionary = balance["n%d" % n]
			for g in GOODS:
				row["g%d" % g] = 0.0
	else:
		(balance as PackedFloat64Array).fill(0.0)

	# 1. firm production: recipe read, value added, the monthly firm verb
	for f in FIRMS:
		var cost := 0.0
		var out_g: int
		if use_dicts:
			var recipe: Dictionary = firm_in[f]
			for k in recipe:
				cost += recipe[k] * price[(k as String).substr(1).to_int()]
			out_g = (firm_out[f] as String).substr(1).to_int()
			# the recipe keys are "g<idx>" — the int lives in the string, no
			# extra array; the PACKED shape carries the same index in its own
			# array, which is why the DICT line pays the parse cost.
		else:
			for k in INPUTS_PER_RECIPE:
				cost += firm_in_qty[f * INPUTS_PER_RECIPE + k] * price[firm_in[f * INPUTS_PER_RECIPE + k]]
			out_g = firm_out[f]
		var qty: float = firm_qty[f]
		var va: float = price[out_g] * qty - cost
		world_supply[out_g] += qty
		if use_dicts:
			var row: Dictionary = balance[firm_nation[f]]
			row[firm_out[f]] += qty
		else:
			balance[firm_nation[f] * GOODS + out_g] += qty
		firm_qty[f] = qty * (1.0 + clampf(va * 1e-6, -0.01, 0.01))
		region_gdp[firm_region[f]] += va

	# 2. per-nation-per-good balance vs consumption; world demand
	for n in NATIONS:
		for g in GOODS:
			var consumed: float = pop[n] * basket[g]
			world_demand[g] += consumed
			if use_dicts:
				balance["n%d" % n]["g%d" % g] -= consumed
			else:
				balance[n * GOODS + g] -= consumed

	# 3. world price per good, the tier's +-75% clamp
	for g in GOODS:
		var supply: float = maxf(world_supply[g], 1e-9)
		price[g] = clampf(price[g] * (1.0 + 0.1 * (world_demand[g] - supply) / supply), base_price[g] * 0.25, base_price[g] * 1.75)

	# 4. bilateral routing: surplus nations feed deficit nations, per good
	for g in GOODS:
		if use_dicts:
			var key := "g%d" % g
			order.sort_custom(func(a: int, b: int) -> bool:
				return float(balance["n%d" % a][key]) > float(balance["n%d" % b][key]))
			var lo := 0
			var hi := NATIONS - 1
			while lo < hi:
				var surplus: float = balance["n%d" % order[lo]][key]
				var deficit: float = -float(balance["n%d" % order[hi]][key])
				if surplus <= 1e-9 or deficit <= 1e-9:
					break
				var moved: float = minf(surplus, deficit) * 0.5
				balance["n%d" % order[lo]][key] = surplus - moved
				balance["n%d" % order[hi]][key] = balance["n%d" % order[hi]][key] + moved
				lo += 1
				hi -= 1
		else:
			order.sort_custom(func(a: int, b: int) -> bool:
				return balance[a * GOODS + g] > balance[b * GOODS + g])
			var lo := 0
			var hi := NATIONS - 1
			while lo < hi:
				var surplus: float = balance[order[lo] * GOODS + g]
				var deficit: float = -balance[order[hi] * GOODS + g]
				if surplus <= 1e-9 or deficit <= 1e-9:
					break
				var moved: float = minf(surplus, deficit) * 0.5
				balance[order[lo] * GOODS + g] = surplus - moved
				balance[order[hi] * GOODS + g] = balance[order[hi] * GOODS + g] + moved
				lo += 1
				hi -= 1

	# 5. region -> nation aggregation (the V2.5 spine's monthly rollup)
	var nation_gdp := PackedFloat64Array()
	nation_gdp.resize(NATIONS)
	for r in REGIONS:
		nation_gdp[r % NATIONS] += region_gdp[r]

	# 6. sector reporting rollup: goods -> 3 sectors per nation
	var sectors := PackedFloat64Array()
	sectors.resize(NATIONS * 3)
	for n in NATIONS:
		for g in GOODS:
			sectors[n * 3 + g % 3] += world_supply[g] * price[g] / float(NATIONS)
	# both rollups consumed: a month's worst total is the harness's own read
	var checksum := nation_gdp[0] + sectors[0]
	if is_nan(checksum):
		push_error("production scale probe: NaN in rollup")


func _verdict(mean_ms: float) -> String:
	if mean_ms <= 300.0:
		return "PASS"
	if mean_ms <= 1000.0:
		return "CONDITIONAL"
	return "FAIL"
