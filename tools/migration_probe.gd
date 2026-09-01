extends SceneTree

## Migration probe: godot --headless --script res://tools/migration_probe.gd
##
## V2.6a's evidence generator. Not a test: tests/test_migration.gd asserts the
## invariants this probe is used to FIND. Kept in tools/ and excluded from
## run_tests.sh for that reason -- which also means a green suite says nothing about
## whether this file still parses, so run it before trusting the suite (V1.3e).
##
## TABLE (a) RUNS BEFORE ANY src/ CODE EXISTS, which is the point: the whole block
## rests on there being a signal to migrate on, and the honest order is to measure
## the signal before building the machine that reads it. docs/region-economy-model.md
## section 8 predicts Britain is flat on expected income; this is where that stops
## being a prediction.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Regions = preload("res://src/sim/regions.gd")
const Companies = preload("res://src/sim/companies.gd")
const Migration = preload("res://src/sim/migration.gd")

const NATIONS := ["AUT", "BEL", "CHE", "DEU", "ESP", "FRA", "GBR", "ITA", "LUX", "NLD"]


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("data did not load: %s" % [loader.errors])
		quit(1)
		return

	_table_a(loader)
	quit(0)


## (a) THE STARTING SPREAD, from the content alone. Expected income is output per
## head times the probability of being employed -- Harris-Todaro, which is the
## textbook model of internal migration and carries NO free weight: it is a product
## of two ratios the register already publishes. The jobs column is the city-level
## signal, and it is zero for seven of ten nations because data/companies/ names
## employers in three.
func _table_a(loader) -> void:
	print("\n=== (a) starting pull spread: expected income, and named jobs ===")
	for nation_id in NATIONS:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		if list.is_empty():
			continue
		var rows: Array = []
		var jobs_total: float = 0.0
		for region in list:
			var per_head: float = Regions.gdp_per_head_index(ns, list, region.id, Migration.region_share(ns, region.id))
			var employed: float = 1.0 - Regions.unemployment_pct(ns, list, region.id) / 100.0
			rows.append([per_head * employed, region.region_name])
			for city in region.cities:
				jobs_total += Companies.headcount_in_city(ns, loader, city.id)
		rows.sort_custom(func(a, b): return a[0] < b[0])
		var low: float = rows[0][0]
		var high: float = rows[rows.size() - 1][0]
		print("  %s  best %-28s %.4f | worst %-28s %.4f | spread %.4f | named jobs %.0f" % [
			nation_id,
			rows[rows.size() - 1][1], high,
			rows[0][1], low,
			high - low,
			jobs_total,
		])
