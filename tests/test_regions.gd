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


## A decomposition, not a second opinion: the population-weighted mean of the regional
## rates over the named regions is the national rate.
func _check_unemployment_decomposes() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.nations["FRA"]
	var list: Array = _loader.regions.get("FRA", [])
	var weight: float = 0.0
	var acc: float = 0.0
	for region in list:
		weight += region.share
		acc += region.share * Regions.unemployment_pct(ns, list, region.id)
	if weight <= 0.0:
		_fail("no named French regions")
		return
	if absf(acc / weight - ns.unemployment_pct) > 0.001:
		_fail("regional mean unemployment %f against a national %f" % [acc / weight, ns.unemployment_pct])


func _finish() -> void:
	for message in _failures:
		printerr("FAIL: " + message)
	if _failures.is_empty():
		print("test_regions: all checks passed")
		quit(0)
	else:
		printerr("test_regions: %d failure(s)" % _failures.size())
		quit(1)
