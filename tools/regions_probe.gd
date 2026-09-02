extends SceneTree

## Regions probe: godot --headless --script res://tools/regions_probe.gd
##
## V2.5's evidence generator. Not a test: tests/test_regions.gd asserts the
## invariants this probe is used to FIND. Kept in tools/ and excluded from
## run_tests.sh for that reason -- which also means a green suite says nothing about
## whether this file still parses, so run it before trusting the suite (V1.3e).
##
## Three jobs and no constant sweep, because src/sim/region_constants.gd ships no
## tuned constant: a region's trend IS its own mix. The absence is a result, so table
## (d) prints what the bound has left over rather than what a dial was set to.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Regions = preload("res://src/sim/regions.gd")
const RegionK = preload("res://src/sim/region_constants.gd")
const Migration = preload("res://src/sim/migration.gd")

const MONTHS := 168
const NATIONS := ["FRA", "DEU", "GBR"]


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
	quit(0)


## (a) THE STARTING SPREAD, from the content alone. Nothing has ticked; this is what
## the import produced and what every later table moves away from.
func _table_a(loader) -> void:
	print("\n=== (a) starting spread: output per head against the national average ===")
	for nation_id in NATIONS:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		var rows: Array = []
		for region in list:
			rows.append([Regions.gdp_per_head_index(ns, list, region.id, Migration.region_share(ns, region.id)), region.region_name])
		rows.sort_custom(func(a, b): return a[0] < b[0])
		if rows.is_empty():
			continue
		print("  %s  richest %-30s x%.3f | poorest %-30s x%.3f | ratio %.3f" % [
			nation_id,
			rows[rows.size() - 1][1], rows[rows.size() - 1][0],
			rows[0][1], rows[0][0],
			rows[rows.size() - 1][0] / maxf(rows[0][0], 0.000001),
		])


## (b) THE DIVERGENCE OVER A TERM AND OVER THE RUN, and the kill switch's own column.
## The band was fixed before this ran: over fourteen years the richest-to-poorest
## output-per-head ratio must move by at least 0.010 -- one digit of the Region
## panel's own %.3f, so a spread the readout cannot print is a spread that is not
## there -- and by at most 0.500, which is where one region is running away with the
## country.
func _table_b(loader) -> void:
	print("\n=== (b) divergence: the ratio at month 0, 60 and %d ===" % MONTHS)
	for nation_id in NATIONS:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		var at_0: float = _ratio(ns, list)
		var at_60: float = 0.0
		for i in MONTHS:
			Economy.tick_month(state)
			if i == 59:
				at_60 = _ratio(ns, list)
		var at_end: float = _ratio(ns, list)
		var moved: float = absf(at_end - at_0)
		var verdict := "READABLE"
		if moved < 0.010:
			verdict = "BELOW THE PANEL'S OWN PRECISION"
		elif moved > 0.500:
			verdict = "RUNAWAY"
		print("  %s  %.3f -> %.3f -> %.3f   moved %.3f   %s" % [
			nation_id, at_0, at_60, at_end, moved, verdict,
		])


## (c) THE AGGREGATE, and the session's central claim. National GDP is the sum of the
## regions, so this prints the worst relative gap over the run. Anything above 1e-9
## is a defect rather than a tolerance.
func _table_c(loader) -> void:
	print("\n=== (c) does the partition close? ===")
	for nation_id in NATIONS:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var worst: float = 0.0
		for i in MONTHS:
			Economy.tick_month(state)
			if ns.gdp_eur_bn > 0.0:
				worst = maxf(worst, absf(Regions.total(ns) - ns.gdp_eur_bn) / ns.gdp_eur_bn)
		# GDScript's % operator has no %e, so the gap prints at twelve decimals --
		# a 1e-9 claim needs the zeros visible to be a claim.
		print("  %s  worst relative gap over %d months: %.12f" % [nation_id, MONTHS, worst])


## (d) THE BOUND'S SLACK. region_constants.SHARE_DRIFT_MAX is a bound and not a dial,
## so what this prints is how far the worst region actually got. A bound that binds is
## one the model has outgrown; a bound with no slack at all was never measured.
func _table_d(loader) -> void:
	print("\n=== (d) SHARE_DRIFT_MAX %.3f -- what is left over ===" % RegionK.SHARE_DRIFT_MAX)
	for nation_id in NATIONS:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		for i in MONTHS:
			Economy.tick_month(state)
		var worst: float = Regions.worst_share_drift(ns, list)
		print("  %s  worst drift %.4f, slack %.4f%s" % [
			nation_id, worst, RegionK.SHARE_DRIFT_MAX - worst,
			"  *** BINDING ***" if worst >= RegionK.SHARE_DRIFT_MAX else "",
		])


func _ratio(ns, list: Array) -> float:
	var lo: float = 999.0
	var hi: float = 0.0
	for region in list:
		var v: float = Regions.gdp_per_head_index(ns, list, region.id, Migration.region_share(ns, region.id))
		if v <= 0.0:
			continue
		lo = minf(lo, v)
		hi = maxf(hi, v)
	if lo >= 999.0:
		return 0.0
	return hi / lo
