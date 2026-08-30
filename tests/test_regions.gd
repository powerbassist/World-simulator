extends SceneTree

## Headless test: godot --headless --script res://tests/test_regions.gd
## Non-zero exit on any failure.
##
## V2.5, the economy from below. Model: docs/region-economy-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Regions = preload("res://src/sim/regions.gd")
const RegionK = preload("res://src/sim/region_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_schema()
	_check_partition_closes()
	_check_deviation_is_zero_mean()
	_check_unemployment_decomposes()
	_check_sectors_still_reconcile()
	_finish()


func _check_schema() -> void:
	for nation_id in _loader.regions.keys():
		for region in _loader.regions[nation_id]:
			if region.gdp_share <= 0.0 or region.gdp_share > 1.0:
				_fail("%s region '%s' gdp_share %f is not in (0, 1]" % [nation_id, region.id, region.gdp_share])
			if region.unemployment_rel <= 0.0:
				_fail("%s region '%s' unemployment_rel %f is not positive" % [nation_id, region.id, region.unemployment_rel])
			var total: float = 0.0
			for key in ["agriculture", "industry", "services"]:
				if not region.sector_mix.has(key):
					_fail("%s region '%s' sector_mix has no '%s'" % [nation_id, region.id, key])
					continue
				total += float(region.sector_mix[key])
			if absf(total - 1.0) > 0.000000001:
				_fail("%s region '%s' sector_mix sums to %f, not 1.0" % [nation_id, region.id, total])


func _fail(message: String) -> void:
	_failures.append(message)


## THE INVARIANT THE WHOLE SESSION RESTS ON. National GDP is the sum of the regions,
## so this is the model rather than a check on it -- and it is asserted over a real
## fourteen-year run, not at new game, because float drift is what a one-month check
## cannot see.
func _check_partition_closes() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]
	for i in 168:
		Economy.tick_month(state)
		var total: float = Regions.total(ns)
		if absf(total - ns.gdp_eur_bn) > 0.000000001 * maxf(1.0, ns.gdp_eur_bn):
			_fail("month %d: regions sum to %f against a national %f" % [i, total, ns.gdp_eur_bn])
			return


## The deviation is zero-mean BY CONSTRUCTION, which is what lets the aggregate stay
## on the national trajectory. Trade.sector_shift()'s sum-to-zero rule one level up.
func _check_deviation_is_zero_mean() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]
	var list: Array = _loader.regions.get("FRA", [])
	for i in 24:
		Economy.tick_month(state)
	var weighted: float = 0.0
	for region in list:
		weighted += Regions.share_of(ns, region.id) * Regions.trend_deviation_pct(ns, list, region.id)
	if absf(weighted) > 0.000001:
		_fail("GDP-weighted mean deviation is %f, not zero" % weighted)


## A decomposition, not a second opinion -- asserted in the two halves the model
## actually makes, because the plan's single figure was a REAL RED and the reason is
## understanding rather than arithmetic. The import normalises `unemployment_rel` so
## the POPULATION-weighted mean of `national x rel` is exactly the national rate; the
## Okun term is zero-mean in GDP shares, so its population-weighted mean is a small
## RESIDUAL -- two weightings of one country -- and measuring it against one 0.001
## tolerance made the exact half and the residual half fail together. Measured
## residual: 0.0037 points at new game, three orders under the +/-3.0 poll floor.
func _check_unemployment_decomposes() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]
	var list: Array = _loader.regions.get("FRA", [])
	var weight: float = 0.0
	var ratio: float = 0.0
	for region in list:
		weight += region.share
		ratio += region.share * ns.unemployment_pct * region.unemployment_rel
	if weight <= 0.0:
		_fail("no named French regions")
		return
	# The exact half: the tolerance is the import's own six-decimal rounding.
	if absf(ratio / weight - ns.unemployment_pct) > 0.000001:
		_fail("regional mean unemployment %f against a national %f" % [ratio / weight, ns.unemployment_pct])
	# The residual half: a bound on the two-weighting gap, not a second tolerance on
	# the exact claim above.
	var okun: float = 0.0
	for region in list:
		okun += region.share * float(EK.OKUN) * Regions.trend_deviation_pct(ns, list, region.id)
	if absf(okun / weight) > 0.01:
		_fail("the Okun term's population-weighted mean is %f -- past the measured two-weighting residual" % (okun / weight))
	# And the read is its own formula: national rate x rel, minus the deviation, in the
	# national clamp.
	for region in list:
		var expect: float = clampf(
			ns.unemployment_pct * region.unemployment_rel - float(EK.OKUN) * Regions.trend_deviation_pct(ns, list, region.id),
			float(EK.UNEMP_MIN_PCT),
			float(EK.UNEMP_MAX_PCT)
		)
		if absf(Regions.unemployment_pct(ns, list, region.id) - expect) > 0.0000001:
			_fail("region '%s' reads %f against its own formula's %f" % [region.id, Regions.unemployment_pct(ns, list, region.id), expect])


## The invariant that CHANGED, pinned at the precision it now holds at. Before V2.5
## `ns.gdp_eur_bn` was `_sum(ns.sector_output)` and the two agreed exactly; GDP is the
## region sum now, so the sectors agree to float noise instead. Asserted rather than
## dropped, because trend_pct() divides by gdp_eur_bn and a sector split that drifted
## would move the trend without anything saying so.
func _check_sectors_still_reconcile() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]
	for i in 168:
		Economy.tick_month(state)
	var sectors: float = 0.0
	for value in ns.sector_output.values():
		sectors += float(value)
	if absf(sectors - ns.gdp_eur_bn) > 0.000000001 * ns.gdp_eur_bn:
		_fail("sectors sum to %f against a national %f" % [sectors, ns.gdp_eur_bn])


func _finish() -> void:
	for message in _failures:
		printerr("FAIL: " + message)
	if _failures.is_empty():
		print("test_regions: all checks passed")
		quit(0)
	else:
		printerr("test_regions: %d failure(s)" % _failures.size())
		quit(1)
