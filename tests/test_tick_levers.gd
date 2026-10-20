extends SceneTree

## Headless test: godot --headless --script res://tests/test_tick_levers.gd
## Non-zero exit on any failure.
##
## V5.0c's month-tick levers are each a claim that a faster path returns the SAME
## FLOAT as the slow one. The 51-regime balance table (cmp-identical) is the
## whole-game proof; this file pins each claim on its own, so a later edit that
## breaks one fails here, by name, rather than as an unexplained balance diff:
##
##   1. Regions.unemployment_by_region() equals unemployment_pct() region by
##      region, for every nation, with sites and access live.
##   2. Org.shared_bonus() memoised equals it computed, and Diplomacy closes the
##      memo on its way out (an open memo would serve stale membership to the
##      Orgs step).
##   3. Trade's skipped lookups are skipped only while the registers are EMPTY:
##      with an agreement and a measure on a pair, the vector still prices both.
##   4. Cycle's seed memo returns the FNV value the loop computes, and
##      unit_pair(a, b) draws the float unit("a|b") draws (V5.0c2).
##   5. Commodities' shared routes give the same production as each nation
##      choosing its own, and an equal price vector compares equal by value
##      (the reuse guard reads `!=`).
##   6. The invariants the two Diplomacy memos REST on, source-scanned: nothing
##      Diplomacy runs loads orgs.gd or writes membership (Org's memo), and
##      execute() closes the turn memo before its first relation write.
##   7. Commodities._rows() (V5.0c2) is the per-good `_capacity_of()` and
##      `_want()` arithmetic it replaced, recomputed here the old way, for every
##      nation and good, at a price vector that moves the elasticity term.
##   8. Companies' three price walks over Walk.priced() (V5.0c2) equal the
##      full-roster walks, recomputed here the old way: with no burden, with a
##      burden (the filter must then return everything), and with a body firm
##      at share 0.0 (its term is -h, not zero, so it must stay in).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Regions = preload("res://src/sim/regions.gd")
const Org = preload("res://src/core/org.gd")
const Trade = preload("res://src/sim/trade.gd")
const RK = preload("res://src/core/relations.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Commodities = preload("res://src/sim/commodities.gd")
const Natural = preload("res://src/sim/commodities_natural.gd")
const CK = preload("res://src/sim/commodity_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const CoK = preload("res://src/sim/companies_constants.gd")
const Demography = preload("res://src/sim/demography.gd")
const Walk = preload("res://src/sim/companies_walk.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return
	var state = GameState.new_game(loader, "FRA")
	for _i in range(3):
		WorldMonth.tick_month(state, loader)
	_check_unemployment_batch(state)
	_check_shared_bonus_memo(state, loader)
	_check_trade_registers(state)
	_check_seed_memo()
	_check_shared_routes(state, loader)
	_check_rows(state, loader)
	_check_price_walks(state, loader)
	_check_turn_flavours(state)
	_check_memo_invariants()
	_finish()


func _check_unemployment_batch(state) -> void:
	var checked := 0
	for id in state.nations:
		var ns = state.nations[id]
		var region_list: Array = state.regions.get(id, [])
		if region_list.is_empty():
			continue
		var access: Dictionary = Regions.accessibility_for(ns, region_list, state.region_graph)
		# Sited and unsited both: the batch hoists the sited mean, so a nation with
		# no sites and one with a synthetic site are two different paths.
		var site_cases: Array = [state.project_sited_pct.get(id, {}), {String(region_list[0].id): 0.25}]
		for sites in site_cases:
			var batch: Dictionary = Regions.unemployment_by_region(ns, region_list, access, sites)
			for region in region_list:
				var one: float = Regions.unemployment_pct(ns, region_list, region.id, access, sites)
				if not batch.has(region.id) or float(batch[region.id]) != one:
					_fail("%s/%s: batched unemployment %s, per-region %s" % [id, region.id, batch.get(region.id), one])
				checked += 1
	if checked < 200:
		_fail("only %d regions compared -- the batch check is not reaching the roster" % checked)


func _check_shared_bonus_memo(state, loader) -> void:
	var ids: Array = state.nations.keys()
	var plain := {}
	for a in ids:
		for b in ids:
			plain[a + ">" + b] = Org.shared_bonus(state, a, b, "trade_bonus")
	Org.memo_open(state)
	for pass_i in range(2):  # the second pass is all hits
		for a in ids:
			for b in ids:
				if Org.shared_bonus(state, a, b, "trade_bonus") != float(plain[a + ">" + b]):
					_fail("memoised shared_bonus(%s, %s) differs on pass %d" % [a, b, pass_i])
	Org.memo_close()
	# A different state never reads another's memo: prime it with a pair that
	# DOES share a priced org, then ask a copy whose membership was emptied.
	var primed: float = Org.shared_bonus(state, "FRA", "DEU", "trade_bonus")
	if primed <= 0.0:
		_fail("FRA-DEU shares no priced org -- the cross-state check would be vacuous")
	var other = state.duplicate_state()
	Org.memo_open(state)
	Org.shared_bonus(state, "FRA", "DEU", "trade_bonus")
	other.nations["FRA"].orgs = []
	if Org.shared_bonus(other, "FRA", "DEU", "trade_bonus") != 0.0:
		_fail("a second state read the first state's memo")
	Org.memo_close()
	# Diplomacy leaves neither memo open behind it.
	WorldMonth.tick_month(state, loader)
	if Org._memo_state != null:
		_fail("the shared_bonus memo is still open after the month")
	if Trade._turn_state != null:
		_fail("the trade turn memo is still open after the month")


func _check_trade_registers(state) -> void:
	var probe = state.duplicate_state()
	var ids: Array = probe.nations.keys()
	var a: String = "FRA"
	var b: String = "DEU"
	var before: Dictionary = Trade.weights(probe, a)
	probe.agreements[RK.key(a, b)] = {"weight_multiplier": 1.5}
	var with_agreement: Dictionary = Trade.weights(probe, a)
	if not float(with_agreement[b]) > float(before[b]):
		_fail("an agreement on %s-%s did not raise the weight (%s -> %s)" % [a, b, before[b], with_agreement[b]])
	probe.measures[RK.directed_key(b, a)] = {"severity": 1.0, "since_year": probe.year, "since_month": probe.month}
	var with_measure: Dictionary = Trade.weights(probe, a)
	if not float(with_measure[b]) < float(with_agreement[b]):
		_fail("a measure on %s-%s did not cut the weight (%s -> %s)" % [a, b, with_agreement[b], with_measure[b]])
	if ids.size() < 3:
		_fail("roster too small to exercise the trade registers")


func _check_seed_memo() -> void:
	for key in ["FRA|evt_strike", "industry|x|invest", "statute|pmb|DEU", "", "ÄÖ|€"]:
		var h: int = 2166136261
		for i in key.length():
			h = (h ^ key.unicode_at(i)) & 0xFFFFFFFF
			h = (h * 16777619) & 0xFFFFFFFF
		for pass_i in range(2):  # a miss, then a hit
			if Cycle._key_seed(key) != h:
				_fail("seed of '%s' on pass %d is %d, FNV says %d" % [key, pass_i, Cycle._key_seed(key), h])
	for pair in [["FRA", "evt_strike"], ["DEU", "evt_strike"], ["FRA", "evt_flood"], ["", ""], ["ÄÖ", "€"]]:
		for index in [0, 1, 7, 359]:
			for pass_i in range(2):  # a miss, then a hit
				var want: float = Cycle.unit("%s|%s" % pair, index)
				if Cycle.unit_pair(pair[0], pair[1], index) != want:
					_fail("unit_pair(%s, %d) on pass %d differs from unit('a|b')" % [pair, index, pass_i])


func _check_shared_routes(state, loader) -> void:
	var tables: Dictionary = Commodities._loader_tables(loader)
	var price: Dictionary = state.nations["FRA"].commodity_state["price"]
	if price.is_empty():
		_fail("no price vector to test the shared routes against")
		return
	if not (price.duplicate() == price) or price.duplicate() != price:
		_fail("an equal price vector does not compare equal -- the route reuse would never fire")
	var chosen := {}
	for good_id in tables["order"]:
		chosen[good_id] = Commodities._cheapest_route(tables, good_id, price)
	for id in ["FRA", "DEU", "POL"]:
		if not state.nations.has(id):
			continue
		var capacity: Dictionary = state.nations[id].commodity_state.get("capacity", {})
		var out_a := {}
		var gross_a := {}
		var out_b := {}
		var gross_b := {}
		Commodities._produce(tables, capacity, price, out_a, gross_a)
		Commodities._produce(tables, capacity, price, out_b, gross_b, chosen)
		if var_to_str(out_a) != var_to_str(out_b) or var_to_str(gross_a) != var_to_str(gross_b):
			_fail("%s: production with the shared routes differs from its own" % id)


func _check_rows(state, loader) -> void:
	var probe = state.duplicate_state()
	var goods: Array = Commodities._goods(loader)
	for nation_id in probe.nations.keys():
		var price: Dictionary = probe.nations[nation_id].commodity_state["price"]
		for i in goods.size():
			if i % 3 == 0:
				price[goods[i]] = float(price[goods[i]]) * 1.37
	var tables: Dictionary = Commodities._loader_tables(loader)
	var structure: Dictionary = tables["structure"]
	var endowed: Dictionary = tables["endowed"]
	if endowed.is_empty():
		_fail("no endowment tables -- the natural branch of _rows() would go unchecked")
		return
	var natural: Dictionary = endowed["goods"]
	var ids: Array = probe.nations.keys()
	ids.sort()
	var wss: Dictionary = Natural.authored_sector_share(loader, ids)
	var per_capita := 2345.6
	var checked := 0
	for nation_id in ids:
		var ns = probe.nations[nation_id]
		var rows: Array = Commodities._rows(ns, tables, wss, per_capita)
		if rows[0].keys() != goods or rows[1].keys() != goods:
			_fail("%s: _rows() keys are not the goods in _goods() order" % nation_id)
		for good_id in goods:
			var good: Dictionary = loader.commodity_goods[good_id]
			var id := String(good.id)
			var cap: float
			if natural.has(id):
				cap = float(endowed["capacity"].get(String(ns.id), {}).get(id, 0.0))
			else:
				cap = Commodities._bucket(ns, good, structure) / float(good.base_price)
			var sector := String(Commodities.CATEGORY_SECTOR.get(String(good.category), "industry"))
			var p := float(ns.commodity_state["price"].get(id, float(good.base_price)))
			var base := float(good.base_price)
			var value: float = per_capita * ns.population \
				* float(wss.get(sector, 0.0)) * float(structure.get(id, 0.0))
			var quantity := value / maxf(base, 1e-9)
			var want: float = quantity * pow(base / maxf(p, 1e-9), CK.DEMAND_ELASTICITY)
			if float(rows[0][good_id]) != cap:
				_fail("%s %s: capacity %.17g, the old way %.17g" % [nation_id, good_id, float(rows[0][good_id]), cap])
			if float(rows[1][good_id]) != want:
				_fail("%s %s: demand %.17g, the old way %.17g" % [nation_id, good_id, float(rows[1][good_id]), want])
			checked += 1
	if checked < 1000:
		_fail("only %d rows checked" % checked)


func _check_price_walks(state, loader) -> void:
	var probe = state.duplicate_state()
	var fra = probe.nations["FRA"]
	var major = Companies.majors_of(loader, "FRA")[0]
	var body = Companies.body_of(loader, "FRA")[0]
	var entry: Dictionary = fra.companies[major.id]
	entry["share"] = float(entry["share"]) * 1.1
	entry["subsidy"] = 0.5
	entry["state_share"] = 0.3
	if not fra.regulation_burden.is_empty():
		_fail("FRA starts with a regulation burden -- the plain case would go unchecked")
	_compare_walks(probe, loader, "plain")
	var authored_share: float = body.share
	body.share = 0.0
	_compare_walks(probe, loader, "zero-share body firm")
	body.share = authored_share
	fra.regulation_burden = {"industry": 0.25}
	_compare_walks(probe, loader, "burdened")
	if Walk.priced(fra, Companies.firms_of(loader, "FRA")).size() != Companies.firms_of(loader, "FRA").size():
		_fail("a burdened nation's walk left a firm out")


func _compare_walks(probe, loader, label: String) -> void:
	var moved := 0
	for nation_id in probe.nations.keys():
		var ns = probe.nations[nation_id]
		var old := _old_walks(ns, loader)
		var now := [Companies.firm_impulse_pct(ns, loader), Companies.firm_jobs_offset_pct(ns, loader),
			Companies.dividend_revenue_pct_gdp(ns, loader)]
		for k in 3:
			if float(now[k]) != float(old[k]):
				_fail("%s, %s walk %d: %.17g, the full roster says %.17g" % [label, nation_id, k, float(now[k]), float(old[k])])
			if float(old[k]) != 0.0:
				moved += 1
	if moved < 3:
		_fail("%s: only %d walks are non-zero -- the comparison is near vacuous" % [label, moved])


## The three walks as they stood before V5.0c2: every firm of the roster.
func _old_walks(ns, loader) -> Array:
	var impulse := 0.0
	if ns.gdp_eur_bn > 0.0:
		var subsidised := 0.0
		var burdened := 0.0
		for company in Companies.firms_of(loader, ns.id):
			var intensity := Companies.subsidy_of(ns, company.id)
			var burden := Companies.regulation_burden_of(ns, company.sector)
			if intensity == 0.0 and burden == 0.0:
				continue
			var gdp_share: float = Companies.output_eur_bn(ns, company) / ns.gdp_eur_bn
			subsidised += intensity * gdp_share / CoK.GDP_SHARE_REFERENCE
			burdened += burden * gdp_share / CoK.GDP_SHARE_REFERENCE
		impulse = clampf(CoK.SUBSIDY_GROWTH_BETA * subsidised - CoK.REGULATION_GROWTH_BETA * burdened,
			-CoK.FIRM_IMPULSE_MAX_PCT, CoK.FIRM_IMPULSE_MAX_PCT)
	var jobs := 0.0
	var labour_force: float = Demography.labour_force(ns)
	if labour_force > 0.0:
		var net_jobs := 0.0
		for company in Companies.firms_of(loader, ns.id):
			net_jobs += Companies.headcount(ns, company) - company.headcount
		if net_jobs != 0.0:
			jobs = clampf(-100.0 * net_jobs / labour_force, -CoK.FIRM_JOBS_MAX_PCT, CoK.FIRM_JOBS_MAX_PCT)
	var dividend := 0.0
	if ns.gdp_eur_bn > 0.0:
		var paid := 0.0
		for company in Companies.firms_of(loader, ns.id):
			var held := Companies.state_share_of(ns, company.id)
			if held <= 0.0:
				continue
			paid += held * Companies.output_eur_bn(ns, company) * CoK.DIVIDEND_YIELD
		if paid != 0.0:
			dividend = minf(100.0 * paid / ns.gdp_eur_bn, CoK.DIVIDEND_MAX_PCT_GDP)
	return [impulse, jobs, dividend]


## Under an open turn memo, with a measure in force, "with" and "before"
## measures are different vectors -- the memo must keep them apart.
func _check_turn_flavours(state) -> void:
	var probe = state.duplicate_state()
	probe.measures[RK.directed_key("DEU", "FRA")] = {"severity": 1.0, "since_year": probe.year, "since_month": probe.month}
	var with_plain: Dictionary = Trade.weights(probe, "FRA")
	var before_plain: Dictionary = Trade.weights_before_measures(probe, "FRA")
	Trade.turn_open(probe)
	var before_memo: Dictionary = Trade.weights_before_measures(probe, "FRA")
	var with_memo: Dictionary = Trade.weights(probe, "FRA")
	var with_again: Dictionary = Trade.weights(probe, "FRA")
	Trade.turn_close()
	if var_to_str(with_memo) != var_to_str(with_plain) or var_to_str(with_again) != var_to_str(with_plain):
		_fail("the turn memo served a different 'with measures' vector")
	if var_to_str(before_memo) != var_to_str(before_plain):
		_fail("the turn memo served a different 'before measures' vector")
	if float(with_memo["DEU"]) == float(before_memo["DEU"]):
		_fail("with a measure in force the two flavours must differ -- the memo shared one entry")


## Scanned over comment-stripped code, so a docstring cannot trip or satisfy it.
## The file list is what Diplomacy's tick reaches; a writer of membership or of
## the effects snapshot in any of them would serve stale bonuses under the memo.
func _check_memo_invariants() -> void:
	for path in ["res://src/sim/diplomacy.gd", "res://src/sim/foreign_policy.gd", "res://src/sim/defence.gd",
			"res://src/sim/diplomacy_verbs.gd", "res://src/sim/coercion.gd", "res://src/core/relations.gd",
			"res://src/sim/trade.gd", "res://src/core/org.gd"]:
		var code := _code_only(FileAccess.get_file_as_string(path))
		for forbidden in ["orgs.gd\")", ".orgs = ", ".orgs.append(", ".orgs.push_back(", ".orgs.erase(",
				".orgs.remove_at(", ".orgs.clear(", ".orgs.sort(", "org_effects = ", "org_effects[org"]:
			if code.contains(forbidden):
				_fail("%s contains '%s': Diplomacy's tick would write membership under Org's memo" % [path, forbidden])
	# Every kind of write execute() makes comes after the turn memo's close.
	var dip := _code_only(FileAccess.get_file_as_string("res://src/sim/diplomacy.gd"))
	var start := dip.find("static func execute(")
	var close_at := dip.find("Trade.turn_close()", start)
	if start < 0 or close_at < 0:
		_fail("execute() no longer closes the turn memo")
		return
	for write in ["RK.adjust(", "ns.bloc_offset[", "state.agreements[", "state.agreements.erase(",
			"state.measures[", "state.measures.erase(", "Defence.", "ns.diplo_cooldown_months[", "state.met_months["]:
		var at := dip.find(write, start)
		if at >= 0 and at < close_at:
			_fail("execute() writes '%s' before it closes the turn memo" % write)


func _code_only(src: String) -> String:
	var out: PackedStringArray = []
	for line in src.split("\n"):
		var cut := line.find("#")
		out.append(line if cut < 0 else line.substr(0, cut))
	return "\n".join(out)


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_tick_levers: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
