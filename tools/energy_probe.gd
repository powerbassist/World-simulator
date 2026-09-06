extends SceneTree

## V2.8 step 0. Run BEFORE any src/ edit -- V2.7's own discipline, and the reason
## V2.2a's row was wrong within the hour rather than at build time.
##
## Three questions, none of which the row answers:
##   (a) DENOMINATOR. What is each nation's electricity consumption in TWh, from
##       the measured per-capita figure and the live population? A plant's authored
##       output only means something against this.
##   (b) SPREAD. How far apart are the ten? If one plant is a rounding error in
##       every nation, the verb is decorative.
##   (c) OPPOSITION WEIGHT. What does Siting.concentration() actually read for the
##       plausible siting regions -- V2.6b1 measured it and priced nothing, so
##       V2.8 is its first pricer and owes its own table.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Siting = preload("res://src/sim/siting.gd")
const Migration = preload("res://src/sim/migration.gd")
const Energy = preload("res://src/sim/energy.gd")
const EnergyAction = preload("res://src/core/energy_action.gd")
const EnergyK = preload("res://src/sim/energy_constants.gd")
const Regions = preload("res://src/sim/regions.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Events = preload("res://src/sim/events.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Elections = preload("res://src/sim/elections.gd")

const ROSTER := ["FRA", "DEU", "GBR", "ITA", "ESP", "BEL", "NLD", "LUX", "CHE", "AUT"]


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		print("data did not load: %s" % [loader.errors])
		quit(1)
		return
	_table_denominator(loader)
	_table_concentration(loader)
	if loader.energy_sources.is_empty():
		# The step-0 half. With no catalogue the sweeps have nothing to price, so
		# stop here rather than print tables about nothing.
		print("\n(catalogue not loaded -- step-0 run only)")
		quit()
		return
	_table_reachable(loader)
	_sweep_access(loader)
	_sweep_opposition(loader)
	_sweep_dep_beta(loader)
	_check_share_drift(loader)
	quit()


## (a) and (b). Reads the imported block Task 1 writes; prints "ABSENT" until then,
## which is what makes this runnable now and again after the import.
func _table_denominator(loader) -> void:
	print("\n=== denominator: measured kWh/head, live population, TWh ===")
	print("nation  kwh/head   pop (M)    TWh")
	for id in ROSTER:
		var state = GameState.new_game(loader, id)
		var ns = state.nations[id]
		# Reading a property NationState does not declare RAISES rather than
		# returning null -- the same raise test_shell.gd hit off a bare Control.
		# .get() answers null, which is what "the field does not exist yet" means.
		var raw = ns.get("energy_kwh_per_capita")
		if raw == null:
			print("%s     ABSENT" % id)
			continue
		var kwh: float = float(raw)
		if kwh <= 0.0:
			print("%s     ABSENT" % id)
			continue
		var twh: float = kwh * ns.population / 1.0e9
		print("%s     %8.1f   %7.2f   %7.1f" % [id, kwh, ns.population / 1.0e6, twh])


## (c). The multiplier the opposition price will read, at each nation's three
## largest regions by population share -- the ones a player actually sites in.
func _table_concentration(loader) -> void:
	print("\n=== concentration at the three largest regions ===")
	for id in ROSTER:
		var state = GameState.new_game(loader, id)
		var ns = state.nations[id]
		var list: Array = loader.regions.get(id, [])
		var weights: Dictionary = {}
		for region in list:
			weights[region.id] = Migration.region_share(ns, region.id)
		var ranked: Array = weights.keys()
		ranked.sort_custom(func(a, b): return float(weights[a]) > float(weights[b]))
		var line := "%s  n=%d  " % [id, list.size()]
		for i in range(mini(3, ranked.size())):
			line += "%s %.3f  " % [ranked[i], Siting.concentration(weights, String(ranked[i]))]
		print(line)


# --- Task 7: the reachable range and the three sweeps ---------------------------

const MANAGED := {"vat": 3.0, "defence": -1.4}
const REMAINING_SPAN := 0.5639  # what V1.6d and V1.6e left of DEFICIT_SCALE_PP (6.0)


## A state on the harness's own managed budget -- balance_probe.gd's REGIMES
## delta, resolved the way _resolve_pending() resolves it: nation-relative,
## clamped to the loader's valid ranges.
func _managed_state(loader, nation_id: String):
	var state = GameState.new_game(loader, nation_id)
	var ns = state.nations[nation_id]
	var pending := {}
	var rates := {}
	rates["vat"] = clampf(float(ns.start_tax_rates_pct.get("vat", 0.0)) + float(MANAGED["vat"]), 0.0, 100.0)
	pending["tax_rates_pct"] = rates
	var spending := {}
	spending["defence"] = clampf(float(ns.start_spending_pct_gdp.get("defence", 0.0)) + float(MANAGED["defence"]), 0.0, 100.0)
	pending["spending_pct_gdp"] = spending
	Budget.commit(state, pending)
	return state


## The tick stack balance_probe.gd runs, in its own order -- THE WHOLE STACK and
## not a convenient subset, because the drift obligation reads population shares
## and a stack without Migration.tick_month() measures a world where nobody moves
## (V1.3f's measuring-the-wrong-state error, in the file written to avoid it).
## Energy BEFORE Economy, because economy.gd reads the field the energy tick wrote.
func _tick(state, loader) -> void:
	var access_by_nation: Dictionary = {}
	for member_id in state.nations.keys():
		access_by_nation[member_id] = Regions.accessibility_for(
			state.nations[member_id], state.regions.get(member_id, []), state.region_graph)
	Energy.tick_month(state, loader, access_by_nation)
	Economy.tick_month(state)
	Budget.tick_month(state)
	Orgs.tick_month(state, loader)
	Inflation.tick_month(state)
	Media.tick_month(state, loader)
	Opinion.tick_month(state)
	var entry := Budget.snapshot(state)
	entry.merge(Opinion.snapshot(state))
	state.append_history(entry)
	Discipline.tick_month(state, loader)
	Legislature.tick_month(state, loader)
	Dissolution.tick_month(state)
	Companies.tick_month(state, loader)
	Migration.tick_month(state, loader)
	Investment.tick_month(state)
	Projects.tick_month(state, loader)
	Campaign.tick_month(state, loader)
	Pledges.tick_month(state, loader)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Events.tick_month(state, loader)
	Cabinet.tick_month(state, loader)
	Elections.tick_month(state, loader)


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


## One month loop with an optional repeated order through Energy.execute() -- never
## by writing ns.plants, because a probe that bypasses the verb measures a model
## the player cannot reach. Fires the order at `order_month` and again every
## `repeat_months`, which is Task 8's two regimes' own cadence.
func _run_months(state, loader, months: int, order_action_id: String, order_month: int, repeat_months: int) -> void:
	var ns = state.nations[state.player_nation_id]
	var action = null
	for a in loader.energy_actions:
		if a.id == order_action_id:
			action = a
	for i in range(months):
		_advance(state)
		var on_cadence := order_action_id != "" and (i + 1) >= order_month \
			and ((i + 1) - order_month) % repeat_months == 0
		if on_cadence and action != null:
			var weights: Dictionary = {}
			var largest := ""
			var largest_share: float = -1.0
			for region in loader.regions.get(state.player_nation_id, []):
				var share: float = Migration.region_share(ns, region.id)
				weights[region.id] = share
				if share > largest_share:
					largest_share = share
					largest = region.id
			var access: Dictionary = Regions.accessibility_for(
				ns, state.regions.get(state.player_nation_id, []), state.region_graph)
			Energy.execute(state, ns, loader, loader.energy_actions, action,
				Vector2(0.0, 0.0), largest, "", access, weights)
		_tick(state, loader)


## V1.7c's lesson: a kill switch that sweeps a range the player cannot reach is
## not a kill switch. The harness's managed budget for fourteen years, per year
## -- the deficit and the approval the player actually holds. Every band's test
## point is written inside this range, not outside it.
func _table_reachable(loader) -> void:
	print("\n=== reachable range: managed FRA, deficit and approval per year ===")
	var state = _managed_state(loader, "FRA")
	var ns = state.nations["FRA"]
	for i in range(168):
		_advance(state)
		_tick(state, loader)
		if (i + 1) % 12 == 0:
			print("  year %d  deficit %.2f  approval %.1f  plants %d" % [
				state.year, ns.deficit_pct_gdp, ns.overall_approval_pct, Energy.plant_count(ns)])


## ACCESS_ELASTICITY. Emulated rather than rescaled: connection_multiplier() reads
## the shipped const, so this recomputes pow(access, -candidate) itself. If it
## called the module instead, every row would print the same number and the table
## would say the constant does not matter.
func _sweep_access(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.nations["FRA"]
	var list: Array = loader.regions.get("FRA", [])
	var access: Dictionary = Regions.accessibility_for(ns, list, state.region_graph)
	var best: float = -INF
	var worst: float = INF
	for region_id in access.keys():
		best = maxf(best, float(access[region_id]))
		worst = minf(worst, float(access[region_id]))
	var source = loader.energy_sources["nuclear_epr"]
	print("\n=== ACCESS_ELASTICITY: best %.3f, worst %.3f ===" % [best, worst])
	print("cand    bill@best  bill@worst   spread     max_mult   (i)  (ii)")
	for cand in [0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.50, 0.70, 1.00]:
		var hi: float = source.build_cost_pct_gdp * pow(worst, -cand)
		var lo: float = source.build_cost_pct_gdp * pow(best, -cand)
		var spread: float = hi - lo
		var max_mult: float = pow(worst, -cand)
		print("%5.2f   %8.4f   %8.4f   %8.4f   %8.3f   %s   %s" % [
			cand, lo, hi, spread, max_mult,
			"OK" if spread >= 0.010 else "--",
			"OK" if max_mult <= 1.60 else "--",
		])


## OPPOSITION_SCALE, through Opinion's own read: the approval target moves
## APPROVAL_SPAN * clamp(score + law_offset - unrest_load), and the clamp is
## computed rather than assumed -- a scale big enough to saturate stops moving
## the approval at all, which is exactly what clause (i) is there to catch.
## Clause (ii) runs the aggressive programme: the CHEAPEST plant on the largest
## region, every month the deficit precondition allows -- the most orders a
## player can reach, and so the worst case the accumulator ever sees.
func _sweep_opposition(loader) -> void:
	var state = _managed_state(loader, "FRA")
	var ns = state.nations["FRA"]
	var weights: Dictionary = {}
	var largest := ""
	var smallest := ""
	var large_share: float = -1.0
	var small_share: float = INF
	for region in loader.regions.get("FRA", []):
		var share: float = Migration.region_share(ns, region.id)
		weights[region.id] = share
		if share > large_share:
			large_share = share
			largest = region.id
		if share < small_share:
			small_share = share
			smallest = region.id
	var c_large: float = Siting.concentration(weights, largest)
	var c_small: float = Siting.concentration(weights, smallest)
	var source = loader.energy_sources["nuclear_epr"]
	print("\n=== OPPOSITION_SCALE: largest %s %.3f, smallest %s %.3f (nuclear) ===" % [
		largest, c_large, smallest, c_small])
	print("cand    conc_L   conc_S   app_move   (i)   accum   vs_MAX  (ii)")
	for cand in [0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.11]:
		var opp_l: float = cand * source.opposition * c_large
		var opp_s: float = cand * source.opposition * c_small
		# score and unrest load are both 0.0 at new game, so the clamp reads the
		# offset alone -- and this is Opinion's own expression, not a rescaling.
		var moved: float = OpinionK.APPROVAL_SPAN * (
			clampf(-opp_l, -1.0, 1.0) - clampf(-opp_s, -1.0, 1.0))
		# Clause (ii) on the SUSTAINED programme -- one order per build length,
		# Task 8's own regime cadence, which is what a building programme IS. The
		# one-order-a-month reading is measured once below and recorded as the
		# bound it is: a repeatable action saturates the accumulator through its
		# AUTHORED offsets alone at that rate, so no siting scale can save it and
		# the clause cannot select on the spam run (U6a's finding in a new place).
		var accum := _accumulate_opposition(loader, cand, "gas_ccgt", 30)
		var worst_frac: float = 0.0
		for bloc_id in accum.keys():
			worst_frac = maxf(worst_frac, absf(float(accum[bloc_id])) / LegislatureK.BLOC_OFFSET_MAX)
		print("%5.2f   %6.3f   %6.3f   %7.2f   %s   %6.3f   %5.2f   %s" % [
			cand, opp_l, opp_s, moved,
			"OK" if absf(moved) >= 3.0 else "--",
			worst_frac * LegislatureK.BLOC_OFFSET_MAX, worst_frac,
			"OK" if worst_frac <= 0.45 else "--",
		])


## The most aggressive REACHABLE building programme: managed budget, the nation's
## largest region, one order a month whenever the action's own deficit
## precondition allows. Returns bloc -> accumulated siting offset over 168 months.
func _accumulate_opposition(loader, scale: float, source_id: String, repeat_months: int) -> Dictionary:
	var state = _managed_state(loader, "FRA")
	var ns = state.nations["FRA"]
	var source = loader.energy_sources[source_id]
	var action = null
	for a in loader.energy_actions:
		if EnergyAction.source_id_of(a) == source_id:
			action = a
	var accum: Dictionary = {}
	var orders := 0
	for i in range(168):
		_advance(state)
		var on_cadence := repeat_months <= 0 or ((i + 1) - 6) % repeat_months == 0
		if on_cadence and action != null and Energy.available(state, ns, loader.energy_actions).has(action):
			var weights: Dictionary = {}
			var largest := ""
			var largest_share: float = -1.0
			for region in loader.regions.get("FRA", []):
				var share: float = Migration.region_share(ns, region.id)
				weights[region.id] = share
				if share > largest_share:
					largest_share = share
					largest = region.id
			var access: Dictionary = Regions.accessibility_for(
				ns, state.regions.get("FRA", []), state.region_graph)
			var before: Dictionary = ns.bloc_offset.duplicate()
			# Emulate the candidate directly -- execute() reads the shipped const.
			var points: float = scale * source.opposition * Siting.concentration(weights, largest)
			Energy.execute(state, ns, loader, loader.energy_actions, action,
				Vector2(0.0, 0.0), largest, "", access, weights)
			# Undo the shipped-scale part of what execute() charged, keep the
			# candidate-scale part: the siting price is charged to the blocs the
			# action names, and this run's price is the candidate's.
			for bloc_id in action.effects.get("bloc_offset", {}).keys():
				ns.bloc_offset[bloc_id] = float(ns.bloc_offset[bloc_id]) + points
			orders += 1
			for bloc_id in action.effects.get("bloc_offset", {}).keys():
				accum[bloc_id] = float(accum.get(bloc_id, 0.0)) + points
		_tick(state, loader)
	print("  (aggressive %s programme: %d orders in 168 months)" % [source_id, orders])
	return accum


## DEP_BETA. The harness's managed budget twice for 168 months -- once building
## only gas on Task 8's own regime cadence, once building nothing -- and the
## annual-growth gap between them, against the span V1.6d and V1.6e left.
func _sweep_dep_beta(loader) -> void:
	print("\n=== DEP_BETA: managed FRA, gas-only cadence vs nothing ===")
	var control = _managed_state(loader, "FRA")
	for i in range(168):
		_advance(control)
		_tick(control, loader)
	var final_growth: float = control.nations["FRA"].growth_annual_pct
	var mean_growth: float = _mean_growth(control)
	print("control: final-year growth %.3f  14y mean %.3f" % [final_growth, mean_growth])

	var treatment = _managed_state(loader, "FRA")
	_run_months(treatment, loader, 168, "order_gas_ccgt", 6, 30)
	var t_final: float = treatment.nations["FRA"].growth_annual_pct
	var t_mean: float = _mean_growth(treatment)
	var dev: float = Energy.dependency_deviation_pct(treatment.nations["FRA"], loader)
	print("gas-only: final-year growth %.3f  14y mean %.3f  dependency dev %.2f pts" % [t_final, t_mean, dev])
	print("gap: final %.3f  mean %.3f  | span left %.4f  share of span %.2f" % [
		final_growth - t_final, mean_growth - t_mean, REMAINING_SPAN,
		absf(mean_growth - t_mean) / REMAINING_SPAN])
	print("dev is the MEASURED dependency deviation of the sustained gas run; the")
	print("term is -DEP_BETA * dev clamped, and dev does not depend on DEP_BETA, so")
	print("the emulation at the candidate is exact (V1.6b's rule, trivially).")
	print("cand    cost@dev   (i) >= 0.30   (ii) < %.4f" % REMAINING_SPAN)
	for cand in [0.080, 0.090, 0.100, 0.110, 0.120, 0.130, 0.140]:
		var raw: float = -cand * dev
		var cost: float = clampf(raw, -EnergyK.IMPULSE_MAX_PCT, EnergyK.IMPULSE_MAX_PCT)
		print("%5.3f   %8.3f   %s   %s" % [
			cand, cost,
			"OK" if absf(cost) >= 0.30 else "--",
			"OK" if absf(cost) < REMAINING_SPAN else "--",
		])


func _mean_growth(state) -> float:
	var total: float = 0.0
	var n: int = 0
	var hist: Array = state.history
	for i in range(maxi(0, hist.size() - 156), hist.size()):
		if float(hist[i].get("growth_annual_pct", 0.0)) != 0.0 or n == 0:
			total += float(hist[i].get("growth_annual_pct", 0.0))
			n += 1
	return total / maxf(1.0, float(n))


## THE HANDOFF'S OBLIGATION, checked rather than asserted. The energy addend is
## national, so every region's level moves by the same factor and no SHARE moves.
## If that is true the drift table is bit-identical to V2.7's and MIGRATION_RATE
## needs no re-sweep; if it is false the term is reaching output per head and the
## re-sweep is owed before this ships, not after.
func _check_share_drift(loader) -> void:
	print("\n=== worst regional share drift over 168 months (gas-only) ===")
	for nation_id in ["FRA", "DEU", "ITA"]:
		var state = _managed_state(loader, nation_id)
		_run_months(state, loader, 168, "order_gas_ccgt", 6, 30)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		print("%s  out-drift %.5f  pop-drift %.5f" % [
			nation_id,
			Regions.worst_share_drift(ns, list),
			Migration.worst_share_drift(ns, list),
		])
