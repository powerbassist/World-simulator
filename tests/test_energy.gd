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
	_check_place_prices(loader)
	_check_partition_after_build(loader)
	_check_small_nation(loader)
	_check_emissions_inert_at_start(loader)
	_check_emissions_displace_downward(loader)
	_check_emissions_fossil_raises(loader)
	_check_source_emission_fixture()
	_check_precondition_fields(loader)
	_check_harnesses_tick()
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


## THE TWO PRICES OF THE PLACE, checked here where there is no map anywhere: both are
## read from the REGION, so this test can hand execute() a region id directly and the
## click in Task 11 prices identically. That is also what keeps the verb testable
## headless at all -- the geometry happens in the caller, never in energy.gd.
func _check_place_prices(loader) -> void:
	var access: Dictionary = {"FR10": 1.40, "FR83": 0.55, "FRMEAN": 1.0}
	# A region at exactly the mean pays exactly 1.0. A STRUCTURAL zero, not a clamp,
	# and asserted exactly because "reads as one" and "reads one" differ under a re-run.
	if Energy.connection_multiplier(access, "FRMEAN") != 1.0:
		_fail("a region at the mean accessibility must pay exactly 1.0")
	# And the better-connected region must never pay MORE than the worse-connected
	# one, whatever the elasticity. The sign, checked rather than assumed -- V1.6d
	# shipped a bracket factor that was backwards and a test caught it, not a reading.
	if Energy.connection_multiplier(access, "FR10") > Energy.connection_multiplier(access, "FR83"):
		_fail("the better-connected region costs more to build in -- the sign is backwards")


## THE PARTITION SURVIVES A BUILD, which is the claim mix() makes and the one a
## reconciliation term would break silently.
func _check_partition_after_build(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.nations["FRA"]
	ns.plants["p1"] = {"source_id": "nuclear_epr", "region_id": "FR10", "months_left": 0, "done": true}
	var sum: float = 0.0
	for share in Energy.mix(ns, loader).values():
		sum += float(share)
	if absf(sum - 1.0) > 1.0e-12:
		_fail("mix sums to %.15f with one reactor built" % sum)
	# And the dependency must have MOVED, or the whole channel is decoration.
	if Energy.dependency_deviation_pct(ns, loader) == 0.0:
		_fail("one reactor moved the dependency by exactly nothing")


## LUXEMBOURG IS THE TRANSFORMING CASE and it falls out of the arithmetic rather
## than out of a branch: one reactor is 13 TWh against a national consumption near
## 8, so nuclear takes more than half the mix. Recorded as a property because it is
## the thing that makes the same authored plant a different decision in a small
## country -- the reason capacity is a physical unit and not a share.
func _check_small_nation(loader) -> void:
	var state = GameState.new_game(loader, "LUX")
	var ns = state.nations["LUX"]
	ns.plants["p1"] = {"source_id": "nuclear_epr", "region_id": "LU00", "months_left": 0, "done": true}
	if float(Energy.mix(ns, loader)["nuclear"]) < 0.50:
		_fail("one reactor is under half of Luxembourg's mix -- check the denominator")


## --- V3.5: emissions are a third derived read of the same partition -------------

## THE SAME EXACT-ZERO PROPERTY the re-run prediction rests on, one quantity over:
## with no plants the mix IS the start mix term by term, so every delta is exactly
## 0.0 and the deviation is EXACTLY 0.0 -- not 1e-9. V1.4a's bar, at the same five
## nations _check_inert_at_start() walks.
func _check_emissions_inert_at_start(loader) -> void:
	for nation_id in ["FRA", "DEU", "CHE", "LUX", "GBR"]:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var d: float = Energy.emissions_deviation_tonnes(ns, loader)
		if d != 0.0:
			_fail("%s emissions deviation is %.17f with no plants, expected exactly 0.0" % [nation_id, d])


## A DONE RENEWABLE ADDS CLEAN TWH: mix()'s fossil share falls, so the deviation
## goes NEGATIVE even though total generation rose. That is the displacement
## physics and the reason the read is share-based, not stock-based.
func _check_emissions_displace_downward(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.nations["FRA"]
	ns.plants["p1"] = {"source_id": "wind_onshore", "region_id": "FR1",
		"lon": 2.0, "lat": 48.0, "months_left": 0, "done": true, "connection": 1.0}
	if Energy.emissions_deviation_tonnes(ns, loader) >= 0.0:
		_fail("a done wind farm did not push the emissions deviation negative -- the read is not share-based")


## And a done gas station pushes it POSITIVE, or the sign of the whole channel is
## decoration. The fossil share rises on the same arithmetic, signed the other way.
func _check_emissions_fossil_raises(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.nations["FRA"]
	ns.plants["p1"] = {"source_id": "gas_ccgt", "region_id": "FR1",
		"lon": 2.0, "lat": 48.0, "months_left": 0, "done": true, "connection": 1.0}
	if Energy.emissions_deviation_tonnes(ns, loader) <= 0.0:
		_fail("a done gas station did not push the emissions deviation positive")


## THE TASK-2 REVIEW'S CARRY-OVER: the loader's emission refusal shipped untested.
## from_dict() parses a missing emission_t_per_twh to the -1.0 sentinel and
## _validate_energy_sources() refuses it -- the negative case is RUN here rather
## than assumed, because 0.0 tonnes per TWh on a gas station is a confident lie
## the emissions read would print for years. test_political_systems.gd's precedent
## for reaching a loader validator directly.
func _check_source_emission_fixture() -> void:
	var loader = DataLoader.new()
	loader._load_energy_sources("res://tests/fixtures/energy_sources_bad_emission.json")
	loader._validate_energy_sources()
	for e in loader.errors:
		if e.find("emission_t_per_twh") != -1:
			return
	_fail("a source without emission_t_per_twh loaded without an error naming it: %s" % [loader.errors])


## THE WHITELIST AND THE READER ARE THE SAME LIST IN TWO PLACES, and V1.5c shipped
## a session that added to only one of them. This walks the constant and fails on
## any key _read_field() answers with its fall-through zero.
func _check_precondition_fields(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var ns = state.nations["FRA"]
	ns.deficit_pct_gdp = 3.0
	ns.overall_approval_pct = 40.0
	ns.import_dependency_pct = 47.0
	ns.plants["p1"] = {"source_id": "gas_ccgt", "region_id": "FR10", "months_left": 1, "done": false}
	var text := FileAccess.get_file_as_string("res://src/sim/energy.gd")
	for field in EnergyK.PRECONDITION_FIELDS.keys():
		if not text.contains("\"%s\":" % field):
			_fail("_read_field() does not answer for PRECONDITION_FIELDS key '%s'" % field)


## BOTH HARNESSES MUST CALL Energy.tick_month(), and this is a test rather than a
## habit because V1.5d shipped with NEITHER calling Media.tick_month() -- so both
## ran the pre-session model and their agreement about a bit-identical re-run was
## about nothing. A bit-identical re-run is the reassuring outcome, which is
## exactly why the check has to exist before the re-run is run.
func _check_harnesses_tick() -> void:
	for path in ["res://tools/balance_probe.gd", "res://tests/test_balance.gd"]:
		var text := FileAccess.get_file_as_string(path)
		if not text.contains("Energy.tick_month"):
			_fail("%s does not call Energy.tick_month -- it runs the pre-V2.8 model" % path)


func _report() -> void:
	if _failures.is_empty():
		print("test_energy: all checks passed")
		quit()
		return
	for f in _failures:
		print("FAIL: %s" % f)
	quit(1)
