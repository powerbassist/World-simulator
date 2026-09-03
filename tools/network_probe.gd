extends SceneTree

## Network probe: godot --headless --script res://tools/network_probe.gd
##
## V2.7's evidence generator, and the STEP-0 GATE runs before any src/ edit --
## docs/tiers/v2.md section 7 leaves the graph's shape "deliberately not decided",
## so this file is what decides it. Not a test: tests/test_network.gd asserts the
## invariants this probe is used to FIND. Excluded from run_tests.sh, which means a
## green suite says nothing about whether it still parses (V1.3e).
##
## Five clauses, all fixed in the plan BEFORE the first run:
##   (a) shape       -- enclaves connected, Berlin routes to Hamburg over adjacency
##   (b) water       -- components off the mainland <= 12, or the graph is continental
##   (c) endowment   -- a tran_r_net branch covering all 112 codes at one year
##   (d) production  -- six-branch vs three-branch Spearman <= 0.90
##   (e) collinear   -- |corr(network_dev, mix_dev)| <= 0.60
##
## GATE VERDICTS, recorded after the runs they measured:
##   (a) PASS -- 112 regions, 243 edges; AT13 -> [AT12], BE1 -> [BE2], DE3 -> [DE4];
##       DE3 reaches DE6 in three hops and ITC4 in five, through a third country;
##       FR1 -> UKI is UNREACHABLE over land. Routed geometry buys nothing here.
##   (b) PASS -- nine components: the continental 94, Britain's 11, and seven
##       singletons (UKN FRM ITG1 ITG2 ES53 ES63 ES64). SEA LINKS REQUIRED: 8 <= 12.
##
## ONE DEVIATION FROM THE PLAN'S DRAFT, and it is the plan's own instruction: the
## draft read loader.region_features, but _load_geo() keeps only OUTER rings
## (data_loader.gd's _outer_ring -- the renderer and hit-test ignore holes). A
## reader over that shape reports 12 components and 10 isolates, adding AT13, BE1
## and DE3 to the singleton list -- the exact first-pass bug the plan records. The
## fix is in THIS file, not in src/: the probe parses data/geo/regions.geojson
## directly and joins on every ring of every polygon, holes included.

const NATIONS := ["FRA", "DEU", "GBR"]


func _init() -> void:
	var adj: Dictionary = _adjacency()
	_table_a(adj)
	_table_b(adj)
	quit(0)


## Shared-vertex adjacency over EVERY RING of every polygon. Reading only the outer
## ring reports 12 components and 10 isolated regions, because an enclave's adjacency
## lives in its host's HOLE ring -- AT13 Wien, BE1 Bruxelles and DE3 Berlin all
## disappear. The holes are in the committed file (283 rings, 18 of them holes);
## the bug is in the reader.
func _adjacency() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://data/geo/regions.geojson")
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not (parsed as Dictionary).has("features"):
		printerr("data/geo/regions.geojson did not parse")
		quit(1)
		return {}
	var rings_by_id: Dictionary = {}
	for feature in (parsed as Dictionary)["features"]:
		var props: Dictionary = (feature as Dictionary).get("properties", {})
		var geometry: Dictionary = (feature as Dictionary).get("geometry", {})
		var id: String = String(props["id"])
		var rings: Array = []
		if String(geometry.get("type", "")) == "MultiPolygon":
			for polygon in geometry.get("coordinates", []):
				for ring in polygon:
					rings.append(ring)
		rings_by_id[id] = rings
	var by_vertex: Dictionary = {}
	for region_id in rings_by_id.keys():
		for ring in rings_by_id[region_id]:
			for point in ring:
				var key: String = "%.4f,%.4f" % [point[0], point[1]]
				if not by_vertex.has(key):
					by_vertex[key] = []
				var owners: Array = by_vertex[key]
				if not owners.has(region_id):
					owners.append(region_id)
	var adj: Dictionary = {}
	for region_id in rings_by_id.keys():
		adj[region_id] = []
	for key in by_vertex.keys():
		var owners: Array = by_vertex[key]
		if owners.size() < 2:
			continue
		for a in owners:
			for b in owners:
				if a == b:
					continue
				if not (adj[a] as Array).has(b):
					(adj[a] as Array).append(b)
	return adj


## (a) SHAPE. The clause the tier note left open, answered by counting.
func _table_a(adj: Dictionary) -> void:
	print("\n=== (a) shape: adjacency over the committed geometry ===")
	var edges: int = 0
	for region_id in adj.keys():
		edges += (adj[region_id] as Array).size()
	print("  regions %d  edges %d" % [adj.size(), edges / 2])
	for enclave in ["AT13", "BE1", "DE3"]:
		print("  enclave %-5s neighbours %s" % [enclave, adj.get(enclave, [])])
	print("  DE3 -> DE6 : %s" % [_path(adj, "DE3", "DE6")])
	print("  DE3 -> ITC4: %s" % [_path(adj, "DE3", "ITC4")])
	print("  FR1 -> UKI : %s" % [_path(adj, "FR1", "UKI")])
	print("  FR1 -> ES30: %s" % [_path(adj, "FR1", "ES30")])


## (b) WATER. Components, and the count of sea links connectivity demands.
func _table_b(adj: Dictionary) -> void:
	print("\n=== (b) water: components off the mainland ===")
	var seen: Dictionary = {}
	var components: Array = []
	var ids: Array = adj.keys()
	ids.sort()
	for start in ids:
		if seen.has(start):
			continue
		var stack: Array = [start]
		var component: Array = []
		seen[start] = true
		while not stack.is_empty():
			var current: String = String(stack.pop_back())
			component.append(current)
			for other in adj[current]:
				if not seen.has(other):
					seen[other] = true
					stack.append(other)
		component.sort()
		components.append(component)
	components.sort_custom(func(a, b): return a.size() > b.size())
	for component in components:
		print("  size %3d  %s" % [component.size(), component if component.size() <= 6 else component.slice(0, 6)])
	print("  SEA LINKS REQUIRED: %d  (clause (b) ceiling is 12)" % [components.size() - 1])


func _path(adj: Dictionary, from_id: String, to_id: String) -> Array:
	if not adj.has(from_id) or not adj.has(to_id):
		return ["MISSING ID"]
	var queue: Array = [[from_id]]
	var seen: Dictionary = {from_id: true}
	while not queue.is_empty():
		var route: Array = queue.pop_front()
		if String(route[route.size() - 1]) == to_id:
			return route
		var neighbours: Array = (adj[route[route.size() - 1]] as Array).duplicate()
		neighbours.sort()
		for other in neighbours:
			if not seen.has(other):
				seen[other] = true
				queue.append(route + [other])
	return ["UNREACHABLE"]
