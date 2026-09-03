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
