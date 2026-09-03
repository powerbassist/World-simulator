extends SceneTree

## V2.8. The partition, the two structural zeros, and the refusal that keeps the
## grid national.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Energy = preload("res://src/sim/energy.gd")
const EnergyK = preload("res://src/sim/energy_constants.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load: %s" % [loader.errors])
		_report()
		return
	_check_leaf()
	_check_partition(loader)
	_check_inert_at_start(loader)
	_report()


## THE REFUSAL THAT IS THE MODEL. A power station serves a grid and the grid is
## national, so energy adds NO fourth zero-mean term to
## Regions.trend_deviation_pct(). If a later session wants a regional energy
## channel it turns this red and comes and says why -- which is the whole reason
## the refusal is a check rather than a paragraph.
func _check_leaf() -> void:
	var text := FileAccess.get_file_as_string("res://src/sim/energy.gd")
	for forbidden in [
		"src/sim/regions.gd", "src/sim/network.gd", "src/sim/economy.gd",
		"src/sim/migration.gd", "src/core/data_loader.gd",
	]:
		if text.contains("preload(\"res://%s\")" % forbidden):
			_fail("src/sim/energy.gd preloads %s -- it takes access and weights as data" % forbidden)


## The mix is a partition and sums to exactly 1.0, with and without plants.
func _check_partition(loader) -> void:
	for nation_id in ["FRA", "DEU", "CHE", "LUX"]:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var sum: float = 0.0
		for share in Energy.mix(ns, loader).values():
			sum += float(share)
		if absf(sum - 1.0) > 1.0e-12:
			_fail("%s mix sums to %.15f with no plants" % [nation_id, sum])


## THE PROPERTY THE RE-RUN PREDICTION RESTS ON, and it is exact rather than
## approximate: with zero plants the mix IS the measured content and the dependency
## deviation is EXACTLY 0.0, so every balance regime is bit-identical. Asserted at
## 0.0 and not at 1e-9 -- V1.4a's bar, because "reads as zero" and "reads zero" are
## different claims and only one of them survives a re-run.
func _check_inert_at_start(loader) -> void:
	for nation_id in ["FRA", "DEU", "CHE", "LUX", "GBR"]:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		if Energy.dependency_deviation_pct(ns, loader) != 0.0:
			_fail("%s dependency deviation is %.17f with no plants, expected exactly 0.0"
				% [nation_id, Energy.dependency_deviation_pct(ns, loader)])
		var live: Dictionary = Energy.mix(ns, loader)
		for branch in ns.start_energy_mix.keys():
			if live[branch] != ns.start_energy_mix[branch]:
				_fail("%s mix[%s] moved with no plants" % [nation_id, branch])


func _fail(msg: String) -> void:
	_failures.append(msg)


func _report() -> void:
	if _failures.is_empty():
		print("test_energy: all checks passed")
		quit()
		return
	for f in _failures:
		print("FAIL: %s" % f)
	quit(1)
