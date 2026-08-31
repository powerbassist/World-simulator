extends SceneTree

## Headless test: godot --headless --script res://tests/test_migration.gd
## Non-zero exit on any failure.
##
## V2.6a, people move. Model: docs/migration-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Migration = preload("res://src/sim/migration.gd")
const MigrationK = preload("res://src/sim/migration_constants.gd")
const Regions = preload("res://src/sim/regions.gd")
const Companies = preload("res://src/sim/companies.gd")

const NATIONS := ["AUT", "BEL", "CHE", "DEU", "ESP", "FRA", "GBR", "ITA", "LUX", "NLD"]

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_seed_matches_the_content()
	_check_pull_is_expected_income()
	_finish()


## THE SEED IS THE CONTENT, EXACTLY. The authored share is where a region STARTED,
## and the whole session is the difference between that and where it ends -- so if
## the seed disagreed with the file on the first frame the divergence would be
## measured against the wrong thing.
func _check_seed_matches_the_content() -> void:
	for nation_id in NATIONS:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = _loader.regions.get(nation_id, [])
		for region in list:
			if absf(Migration.region_share(ns, region.id) - region.share) > 0.000000000001:
				_fail("%s region '%s' seeded at %f against an authored %f" % [
					nation_id, region.id, Migration.region_share(ns, region.id), region.share,
				])
			for city in region.cities:
				if absf(Migration.city_share(ns, city.id) - city.share) > 0.000000000001:
					_fail("%s city '%s' seeded at %f against an authored %f" % [
						nation_id, city.id, Migration.city_share(ns, city.id), city.share,
					])


## THE PULL IS A PRODUCT OF TWO RATIOS AND CARRIES NO AUTHORED WEIGHT, so it can be
## recomputed here from the register's own published quantities and compared. If this
## ever needs a coefficient to agree, a coefficient has been added to migration.gd and
## the model's central claim is no longer true.
##
## Britain is asserted FLAT rather than excluded: docs/region-economy-model.md section
## 8 records that its gdp_share IS its population share and its unemployment_rel is
## exactly 1.0, so every British region's expected income is identical by
## construction. That is a bound with a number beside it, and the day somebody
## authors the twelve ITL1 figures this assertion turns red and says so.
func _check_pull_is_expected_income() -> void:
	for nation_id in NATIONS:
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = _loader.regions.get(nation_id, [])
		for region in list:
			var per_head: float = Regions.share_of(ns, region.id) / maxf(Migration.region_share(ns, region.id), 0.000001)
			var employed: float = 1.0 - Regions.unemployment_pct(ns, list, region.id) / 100.0
			var expected: float = per_head * employed
			var actual: float = Migration.region_pull(ns, list, region.id)
			if absf(actual - expected) > 0.000000001:
				_fail("%s region '%s' pull %f against an expected income of %f" % [
					nation_id, region.id, actual, expected,
				])

	var gbr = GameState.new_game(_loader, "GBR")
	var gbr_ns = gbr.nations["GBR"]
	var gbr_list: Array = _loader.regions.get("GBR", [])
	var first: float = Migration.region_pull(gbr_ns, gbr_list, gbr_list[0].id)
	for region in gbr_list:
		if absf(Migration.region_pull(gbr_ns, gbr_list, region.id) - first) > 0.000000001:
			_fail("a British region's expected income differs from another's -- section 8's proxy says every one of them is identical, so either the proxy moved or this test is measuring the wrong thing")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_migration: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr("FAIL: %s" % message)
	quit(1)
