extends SceneTree

## V2.7. The graph, the index and the two properties every later reader rests on.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Network = preload("res://src/sim/network.gd")
const Regions = preload("res://src/sim/regions.gd")

var _failures: Array[String] = []


func _init() -> void:
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load: %s" % [loader.errors])
		_report()
		return
	_check_leaf()
	_check_adjacency(loader)
	_check_mean_one(loader)
	_check_specialisation()
	_report()


## A LEAF, asserted from the source rather than promised in a comment --
## tests/test_regions.gd's idiom, and the property every "takes plain Dictionaries"
## claim in this file rests on.
func _check_leaf() -> void:
	var text := FileAccess.get_file_as_string("res://src/sim/network.gd")
	for forbidden in [
		"src/sim/regions.gd", "src/sim/economy.gd", "src/sim/migration.gd",
		"src/core/data_loader.gd", "src/core/region.gd", "src/sim/projects.gd",
	]:
		if text.contains("preload(\"res://%s\")" % forbidden):
			_fail("src/sim/network.gd preloads %s -- it is a leaf and takes the graph as data" % forbidden)


func _check_adjacency(loader) -> void:
	var adj: Dictionary = Network.adjacency(loader.region_graph)
	if adj.size() != 213:
		_fail("adjacency covers %d regions, expected 213" % adj.size())
	# Symmetric: an undirected edge stated once must be readable from both ends, or
	# a Dijkstra from Marseille and one from Ajaccio disagree about the crossing.
	for region_id in adj.keys():
		for entry in adj[region_id]:
			var back: Array = adj.get(entry[0], [])
			var found := false
			for other in back:
				if String(other[0]) == region_id:
					found = true
			if not found:
				_fail("edge %s-%s is not symmetric" % [region_id, entry[0]])
				return


## THE PROPERTY EVERY PRICE BUILT ON THIS RESTS ON, checked at 1e-12 --
## Siting.normalised()'s bar. A multiplier whose weighted mean is not one is a silent
## retune of whatever constant multiplies it, and here that constant is the growth
## rate of a whole nation.
func _check_mean_one(loader) -> void:
	for nation_id in ["FRA", "DEU", "ITA"]:
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		var weights: Dictionary = {}
		for region in list:
			weights[region.id] = Regions.share_of(ns, region.id)
		var index: Dictionary = Network.accessibility(loader.region_graph, weights)
		var weighted: float = 0.0
		var total: float = 0.0
		for region_id in weights.keys():
			weighted += float(weights[region_id]) * float(index.get(region_id, 0.0))
			total += float(weights[region_id])
		if absf(weighted / total - 1.0) > 0.000000000001:
			_fail("%s accessibility weighted mean is %.15f, not 1.0" % [nation_id, weighted / total])


func _check_specialisation() -> void:
	var identical: float = Network.specialisation({"a": 0.5, "b": 0.5}, {"a": 0.5, "b": 0.5})
	if absf(identical) > 0.000001:
		_fail("a region with the national mix reads specialisation %f, not 0.0" % identical)
	var disjoint: float = Network.specialisation({"a": 1.0, "b": 0.0}, {"a": 0.0, "b": 1.0})
	if absf(disjoint - 1.0) > 0.000001:
		_fail("a fully disjoint mix reads specialisation %f, not 1.0" % disjoint)


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	for message in _failures:
		printerr("FAIL: %s" % message)
	if _failures.is_empty():
		print("test_network: all checks passed")
	quit(1 if not _failures.is_empty() else 0)
