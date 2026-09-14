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
	_check_memo_holds_the_roster(loader)
	_check_warm(loader)
	_check_split_matches_reference(loader)
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


## The memo must hold ONE ENTRY PER NATION for a full EU-27 sweep. MEMO_MAX was
## sized to the ten-nation roster ("a linear scan ... is nothing" beside the
## sweep it saves) and 16 slots cannot serve 29: a monthly sweep evicts its own
## head, so every accessibility call in every pass was a miss paying the full
## recompute plus a graph deep-copy -- four sweeps a month across main.gd's
## Energy pre-pass, Economy, Migration and map_flows. This test fails on the old
## constant and pins the invariant the fix exists for, so the next roster growth
## re-opens MEMO_MAX on purpose.
func _check_memo_holds_the_roster(loader) -> void:
	var graph: Dictionary = loader.region_graph
	var endowment: Dictionary = graph.get("endowment", {})
	var ids: Array = endowment.keys()
	if ids.size() < 29:
		_fail("only %d regions in the graph; the roster-sweep test needs 29" % ids.size())
		return
	Network._memo.clear()
	var first_weights: Dictionary = {}
	var first_index: Dictionary = {}
	for i in range(29):
		var weights: Dictionary = {}
		for j in range(i + 7):
			weights[String(ids[j])] = 1.0 / float(j + 1)
		var index: Dictionary = Network.accessibility(graph, weights)
		if i == 0:
			first_weights = weights
			first_index = index
	if Network._memo.size() != 29:
		_fail("memo holds %d entries after a 29-nation sweep, expected 29 (MEMO_MAX %d)" % [
			Network._memo.size(), Network.MEMO_MAX])
	# A re-call with equal weights must come back from the memo, not the sweep:
	# the hit path returns the stored object, so identity is the observable.
	var again = Network.accessibility(graph, first_weights.duplicate())
	if again != first_index:
		_fail("re-call with equal weights returned a different index")


## warm() must populate the distance table, and main.gd must call it at boot:
## the ~2 s one-time build is boot cost when paid eagerly and a freeze on the
## player's first month boundary when paid lazily. The source scan is the
## wiring half of the pin -- the same idiom test_regions.gd uses for callers
## that must not quietly disappear.
func _check_warm(loader) -> void:
	var graph: Dictionary = loader.region_graph
	Network._matrix_rows.clear()
	Network._matrix_graph = {}
	Network.warm(graph)
	if Network._matrix_rows.size() != graph.get("endowment", {}).size():
		_fail("warm() built %d distance rows, expected %d" % [
			Network._matrix_rows.size(), graph.get("endowment", {}).size()])
	var text := FileAccess.get_file_as_string("res://src/ui/main.gd")
	if not text.contains("Net.warm("):
		_fail("src/ui/main.gd no longer warms the network table at boot")


## The foreign-endowment split regroups the interleaved market-potential sum,
## so its values are the same numbers to the last bits only if the algebra is
## right. This holds the split to 1e-9 RELATIVE against a reference copy of the
## old interleaved form, over every nation's real weights at a new game --
## the same bar Siting.normalised() is held to, and loose enough that the
## regrouping's own last-bit reordering cannot trip it.
func _check_split_matches_reference(loader) -> void:
	var state = GameState.new_game(loader, "FRA")
	var graph: Dictionary = loader.region_graph
	for nation_id in state.nations.keys():
		var ns = state.nations[nation_id]
		var region_list: Array = state.regions.get(nation_id, [])
		var weights: Dictionary = {}
		for region in region_list:
			weights[region.id] = Regions.share_of(ns, region.id)
		var split: Dictionary = Network.accessibility(graph, weights)
		var reference: Dictionary = _reference_accessibility(graph, weights)
		for region_id in split.keys():
			var a: float = float(split[region_id])
			var b: float = float(reference.get(region_id, 0.0))
			if absf(a - b) > 1e-9 * maxf(1.0, absf(b)):
				_fail("split accessibility %s/%s reads %.17f, reference %.17f" % [
					nation_id, region_id, a, b])
				return


## The pre-split form, kept verbatim as the reference the split must agree with.
func _reference_accessibility(graph: Dictionary, weights: Dictionary) -> Dictionary:
	var NetK = preload("res://src/sim/network_constants.gd")
	var rows: Dictionary = {}
	for region_id in graph.get("endowment", {}).keys():
		rows[String(region_id)] = Network.distances_from(graph, String(region_id))
	var raw: Dictionary = {}
	var ids: Array = weights.keys()
	ids.sort()
	var endowment: Dictionary = graph.get("endowment", {})
	for region_id in ids:
		var dist: Dictionary = rows.get(String(region_id), {})
		var potential: float = 0.0
		for other in endowment.keys():
			if String(other) == String(region_id):
				continue
			var d = dist.get(other)
			if d == null:
				continue
			var mass: float = float(weights.get(other, 0.0))
			if mass <= 0.0:
				mass = float(endowment.get(other, 0.0))
			potential += mass * exp(-float(d) / maxf(NetK.DECAY_KM, 1.0))
		raw[region_id] = potential
	var weighted: float = 0.0
	var total: float = 0.0
	for region_id in ids:
		weighted += float(weights[region_id]) * float(raw[region_id])
		total += float(weights[region_id])
	var out: Dictionary = {}
	var mean: float = weighted / total
	for region_id in ids:
		out[region_id] = float(raw[region_id]) / mean
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	for message in _failures:
		printerr("FAIL: %s" % message)
	if _failures.is_empty():
		print("test_network: all checks passed")
	quit(1 if not _failures.is_empty() else 0)
