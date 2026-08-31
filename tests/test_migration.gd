extends SceneTree

## Headless test: godot --headless --script res://tests/test_migration.gd
## Non-zero exit on any failure.
##
## V2.6a, people move. Model: docs/migration-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Migration = preload("res://src/sim/migration.gd")
const MigrationK = preload("res://src/sim/migration_constants.gd")

const NATIONS := ["AUT", "BEL", "CHE", "DEU", "ESP", "FRA", "GBR", "ITA", "LUX", "NLD"]

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_seed_matches_the_content()
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
