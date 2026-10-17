extends SceneTree

## Endowment probe: godot --headless --script res://tools/endowment_probe.gd
##
## V4.11b2's committed instrument for docs/commodities-model.md section 8's four
## bands, run on main.gd's _on_month_elapsed order (tick_budget_probe.gd's mirror,
## with the systems that mirror still leaves out -- Commodities, Programme,
## Characters -- put back in their slots). A probe that ticked Commodities alone
## would measure a world whose sector output never moves, and band (iv) is a
## statement about ten years of a moving one (AGENTS.md: green is not measured).
##
##   (i)   month 1: every NATURAL good's price within +-2 % of base. Scoped to
##         natural goods at b2: the manufactures drift (clothing 1.04-1.14 by
##         month 12) as they did before V4.11 -- printed, not banded here.
##   (ii)  month 12: the EU-27's net import share of lithium ore, rare earths,
##         crude oil and nickel ore >= 0.70. Share of what EU industry HOLDS
##         (endowment + net trade), the requirement routing fills -- not of
##         population demand, which the b1 scratch probe divided by and read 1.12.
##   (iii) a 6-month 50 % cut in the world pool's supply of one good, from rest at
##         month 12, moves its price >= 1.25x base (the commodity_price_high line).
##   (iv)  month 120: no good pinned at the +-PRICE_BAND clamp.
##
## It also times Commodities.tick_month (mean and worst, warmup excluded) -- the
## tick probe the b2 brief names. The same file runs on a pre-V4.11b tree: with no
## endowments it prints the timing row and skips the bands.
##
## Not a test, excluded from run_tests.sh. tests/test_endowments.gd pins the
## mechanisms; this prints the numbers a human reads.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Regions = preload("res://src/sim/regions.gd")
const Energy = preload("res://src/sim/energy.gd")
const Economy = preload("res://src/sim/economy.gd")
const Commodities = preload("res://src/sim/commodities.gd")
const CK = preload("res://src/sim/commodity_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Programme = preload("res://src/sim/programme.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Statute = preload("res://src/sim/statute.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")
const Migration = preload("res://src/sim/migration.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Events = preload("res://src/sim/events.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Characters = preload("res://src/sim/characters.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const Elections = preload("res://src/sim/elections.gd")

const START_YEAR := 2026
const PLAYER := "FRA"
const LONG_MONTHS := 120
const REST_MONTHS := 12
const CUT_MONTHS := 6
const CUT_FACTOR := 0.5

const BAND_I_TOL := 0.02
const BAND_II_MIN := 0.70
const BAND_III_MIN := 1.25
const IMPORTED := ["lithium_ore", "rare_earths", "crude_oil", "nickel_ore"]
## Band (iii) is stated for ONE good; the probe cuts each of these in its own run
## and prints all of them, so the reader sees which goods the pool can move.
const DOSE_GOOD := "lithium_ore"
const DOSE_FACTORS := [0.95, 0.9, 0.8]
const CUT_GOODS := ["lithium_ore", "rare_earths", "nickel_ore", "crude_oil", "copper_ore", "uranium_ore"]

var _commodity_us: Array[int] = []
## Crossings of the commodity_price_high line over the long run: the one events
## channel V4.11b is predicted to move (a new stamp value is one crossing).
var _crossings := {"player": 0, "world": 0}
var _last_stamp := {}
## Each good's peak price over the long run and the run month it was reached, so a
## crossing above names its good (the stamp itself carries no good id).
var _peak := {}


func _initialize() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return
	var endowed: bool = loader.get("commodity_endowments") is Dictionary and not (loader.get("commodity_endowments") as Dictionary).is_empty()
	var verdicts: Array[String] = []

	# --- the long run: bands (i), (ii), (iv) and the timing row ---
	var state = _fresh(loader)
	for i in range(LONG_MONTHS):
		_tick(state, loader, i)
		if not endowed:
			continue
		if i == 0:
			verdicts.append(_band_i(state, loader))
		if i + 1 == REST_MONTHS:
			verdicts.append(_band_ii(state, loader))
	if endowed:
		verdicts.append(_band_iv(state, loader))
	_print_timing()
	if not endowed:
		print("no endowments on this tree: bands skipped")
		quit(0)
		return

	# --- band (iii): one run per good, cut from rest ---
	var best := 0.0
	for good_id in CUT_GOODS:
		var run := _cut_run(loader, good_id, CUT_FACTOR)
		best = maxf(best, float(run[0]))
		print("BAND_III cut %.0f%% %-12s price at month %d = %.3f of base; first >= %.2f in cut month %d" % [
			100.0 * (1.0 - CUT_FACTOR), good_id, REST_MONTHS + CUT_MONTHS, float(run[0]), BAND_III_MIN, int(run[1])])
	# The dose: a 50 % cut of a pool that supplies nearly all of Europe's ore is a
	# world shortage near half, and any lasting gap walks the price to the clamp. A
	# small cut shows the surface is graded, not a switch.
	for factor in DOSE_FACTORS:
		var run := _cut_run(loader, DOSE_GOOD, factor)
		print("BAND_III dose %.0f%% %-12s price at month %d = %.3f of base; first >= %.2f in cut month %d" % [
			100.0 * (1.0 - factor), DOSE_GOOD, REST_MONTHS + CUT_MONTHS, float(run[0]), BAND_III_MIN, int(run[1])])
	verdicts.append("(iii) best cut %.3f vs %.2f: %s" % [best, BAND_III_MIN, "PASS" if best >= BAND_III_MIN else "BOUND"])

	print("--- verdicts ---")
	for v in verdicts:
		print(v)
	quit(0)


func _fresh(loader):
	var state = GameState.new_game(loader, PLAYER)
	state.year = START_YEAR
	state.month = 1
	return state


func _price_ratio(state, loader, good_id: String) -> float:
	var price: Dictionary = state.nations[PLAYER].commodity_state["price"]
	return float(price[good_id]) / float(loader.commodity_goods[good_id].base_price)


func _band_i(state, loader) -> String:
	var worst_natural := 0.0
	var worst_good := ""
	var worst_made := 0.0
	for good_id in loader.commodity_goods.keys():
		var dev := absf(_price_ratio(state, loader, good_id) - 1.0)
		var category := String(loader.commodity_goods[good_id].category)
		if category == "raw" or category == "agri":
			if dev > worst_natural:
				worst_natural = dev
				worst_good = good_id
		else:
			worst_made = maxf(worst_made, dev)
	print("BAND_I month 1: worst natural |p/base-1| = %.4f (%s); worst manufacture %.4f (not banded)" % [worst_natural, worst_good, worst_made])
	return "(i) worst natural %.4f vs %.2f: %s" % [worst_natural, BAND_I_TOL, "PASS" if worst_natural <= BAND_I_TOL else "BOUND"]


## Net imports over holdings, summed over the EU's live membership (the org
## register, not a list in this file).
func _band_ii(state, loader) -> String:
	var worst := 1.0
	for good_id in IMPORTED:
		var net := 0.0
		var held := 0.0
		for nation_id in state.nations.keys():
			var ns = state.nations[nation_id]
			if not ns.orgs.has("eu"):
				continue
			var cs: Dictionary = ns.commodity_state
			net += float(cs["trade"][good_id])
			held += float(cs["capacity"][good_id]) + float(cs["trade"][good_id])
		var share := net / held if held > 0.0 else 0.0
		worst = minf(worst, share)
		print("BAND_II month %d: EU net import share %-12s %.3f" % [REST_MONTHS, good_id, share])
	return "(ii) worst EU import share %.3f vs %.2f: %s" % [worst, BAND_II_MIN, "PASS" if worst >= BAND_II_MIN else "BOUND"]


func _band_iv(state, loader) -> String:
	var pinned: Array = []
	var ids: Array = loader.commodity_goods.keys()
	ids.sort()
	for good_id in ids:
		var r := _price_ratio(state, loader, good_id)
		if absf(r - 1.0) >= CK.PRICE_BAND - 1e-3:
			pinned.append(good_id)
		if absf(r - 1.0) > 0.05:
			print("BAND_IV month %d: %-18s %.3f" % [LONG_MONTHS, good_id, r])
	return "(iv) pinned at the clamp after %d months: %s: %s" % [LONG_MONTHS, str(pinned), "PASS" if pinned.is_empty() else "BOUND"]


## The pool's supply is `pool_capacity` in the memoised endowment table; the cut
## scales that one entry for CUT_MONTHS and restores it, so the run measures the
## pool's supply and nothing else. Reaching into the memo is a probe's licence.
## Returns [price ratio at the cut's end, first cut month at or above the band line
## (-1 for never)].
func _cut_run(loader, good_id: String, factor: float) -> Array:
	var state = _fresh(loader)
	for i in range(REST_MONTHS):
		_tick(state, loader, i, false)
	var pool: Dictionary = Commodities._loader_tables(loader)["endowed"]["pool_capacity"]
	var before := float(pool[good_id])
	pool[good_id] = before * factor
	var first := -1
	for i in range(CUT_MONTHS):
		_tick(state, loader, REST_MONTHS + i, false)
		if first < 0 and _price_ratio(state, loader, good_id) >= BAND_III_MIN:
			first = i + 1
	var ratio := _price_ratio(state, loader, good_id)
	pool[good_id] = before
	return [ratio, first]


func _tick(state, loader, i: int, timed: bool = true) -> void:
	if i > 0:
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
	# --- main.gd _on_month_elapsed, in order ---
	var access_by_nation: Dictionary = {}
	for nation_id in state.nations.keys():
		access_by_nation[nation_id] = Regions.accessibility_for(
			state.nations[nation_id], state.regions.get(nation_id, []), state.region_graph)
	Energy.tick_month(state, loader, access_by_nation)
	Economy.tick_month(state)
	var t0 := Time.get_ticks_usec()
	Commodities.tick_month(state, loader)
	# Month 0 pays the memo build; the row is the steady month.
	if timed and i > 0:
		_commodity_us.append(Time.get_ticks_usec() - t0)
	if timed:
		for nation_id in state.nations.keys():
			var stamp := int(state.nations[nation_id].commodity_high_month)
			if stamp >= 0 and stamp != int(_last_stamp.get(nation_id, -1)):
				_crossings["world"] += 1
				if nation_id == PLAYER:
					_crossings["player"] += 1
			_last_stamp[nation_id] = stamp
		for good_id in loader.commodity_goods.keys():
			var r := _price_ratio(state, loader, good_id)
			if r > float(_peak.get(good_id, [0.0, 0])[0]):
				_peak[good_id] = [r, i + 1]
	Budget.tick_month(state)
	Orgs.tick_month(state, loader)
	Inflation.tick_month(state)
	Media.tick_month(state, loader)
	Programme.tick_month(state, loader)
	Opinion.tick_month(state)
	var entry: Dictionary = Budget.snapshot(state)
	entry.merge(Opinion.snapshot(state))
	state.append_history(entry)
	Calendar.tick_month(state)
	Discipline.tick_month(state, loader)
	Legislature.tick_month(state, loader)
	Statute.tick_month(state, loader)
	Dissolution.tick_month(state)
	Diplomacy.tick_month(state, loader)
	Defence.tick_month(state)
	Companies.tick_month(state, loader)
	Industry.tick_month(state, loader)
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
	Characters.tick_month(state, loader, {
		"grievance": float(state.player().unrest_pct),
		"press_freedom": float(state.player().press_freedom),
		"judicial_independence": Judiciary.independence_deviation(state.player()),
	})
	Elections.tick_month(state, loader)


func _print_timing() -> void:
	if _commodity_us.is_empty():
		return
	var total := 0
	var worst := 0
	for us in _commodity_us:
		total += us
		worst = maxi(worst, us)
	print("TICK Commodities.tick_month over %d months: mean %.0f us, worst %d us" % [
		_commodity_us.size(), float(total) / float(_commodity_us.size()), worst])
	print("HOOK commodity_price_high crossings over %d months: player %d, all nations %d" % [
		LONG_MONTHS, int(_crossings["player"]), int(_crossings["world"])])
	var ids: Array = _peak.keys()
	ids.sort()
	for good_id in ids:
		if float(_peak[good_id][0]) >= 1.10:
			print("PEAK %-18s %.3f of base at run month %d" % [good_id, float(_peak[good_id][0]), int(_peak[good_id][1])])
