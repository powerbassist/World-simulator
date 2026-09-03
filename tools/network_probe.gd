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
##   (d) FAIL -- Spearman rho 0.9170 against a pre-committed ceiling of 0.90: the
##       six-branch specialisation ranks the roster almost exactly as the
##       three-branch one, so production_mix is REFUSED as one quantity written
##       twice (src/core/region.gd carries the refusal beside sector_mix) and the
##       network term reads sector_mix.
##
## ONE DEVIATION FROM THE PLAN'S DRAFT, and it is the plan's own instruction: the
## draft read loader.region_features, but _load_geo() keeps only OUTER rings
## (data_loader.gd's _outer_ring -- the renderer and hit-test ignore holes). A
## reader over that shape reports 12 components and 10 isolates, adding AT13, BE1
## and DE3 to the singleton list -- the exact first-pass bug the plan records. The
## fix is in THIS file, not in src/: the probe parses data/geo/regions.geojson
## directly and joins on every ring of every polygon, holes included.

const DataLoader = preload("res://src/core/data_loader.gd")
const Network = preload("res://src/sim/network.gd")

const NATIONS := ["FRA", "DEU", "GBR"]

## tools/import_data.py's own collapse, restated so the six-branch ranking and the
## three-branch one measure the same 112 regions from the same source file.
const NACE_TO_SECTOR := {
	"A": "agriculture", "B-E": "industry", "F": "industry",
	"G-J": "services", "K-N": "services", "O-U": "services",
}
const PRODUCTION_BRANCHES := ["A", "B-E", "F", "G-J", "K-N", "O-U"]
const VINTAGE_SIBLING := {"NL31": "NL35", "NL33": "NL36"}


func _init() -> void:
	var adj: Dictionary = _adjacency()
	_table_a(adj)
	_table_b(adj)
	_table_d()
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


## (d) PRODUCTION. Does the six-branch mix rank regions differently from the three?
##
## THE CLAUSE IS FIXED BEFORE THE MEASUREMENT: Spearman rank correlation over all 112
## regions must be <= 0.90. Above that the finer mix is one quantity written twice --
## V1.6b's output gap, V1.6c's deficit gap -- and `production_mix` is refused with the
## number recorded rather than shipped because the row asked for it.
##
## The six branches are not in the register yet, so this table decodes
## sources/eurostat/nama_10r_3gva_2022.json itself -- the same decode
## tools/import_data.py's load_jsonstat() does, duplicated because the probe is the
## one place an independent reading is the point. Specialisation is
## Network.specialisation()'s half-L1, each region against its nation's own
## output(gdp_share)-weighted mean mix, under each keying; regions the source does
## not answer (Britain's proxy, Switzerland's TOTAL-only file, NL31/NL33 through
## their 2024 siblings) read exactly as the importer will write them.
func _table_d() -> void:
	print("\n=== (d) production: six-branch vs three-branch specialisation ===")
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("data did not load: %s" % [loader.errors])
		return
	var branches: Dictionary = _gva_branches()

	var ids: Array = []
	var six: Dictionary = {}
	var three: Dictionary = {}
	for nation_id in loader.regions.keys():
		var list: Array = loader.regions[nation_id]
		# Each nation's own output-weighted mean mix, under both keyings.
		var nat_three: Dictionary = {"agriculture": 0.0, "industry": 0.0, "services": 0.0}
		var nat_six: Dictionary = {}
		for b in PRODUCTION_BRANCHES:
			nat_six[b] = 0.0
		var w_total: float = 0.0
		for region in list:
			var w: float = float(region.gdp_share)
			w_total += w
			for key in nat_three.keys():
				nat_three[key] += w * float(region.sector_mix.get(key, 0.0))
			var own_six: Dictionary = _six_mix(branches, region.id)
			for b in PRODUCTION_BRANCHES:
				nat_six[b] += w * float(own_six[b])
		if w_total <= 0.0:
			continue
		for key in nat_three.keys():
			nat_three[key] /= w_total
		for b in PRODUCTION_BRANCHES:
			nat_six[b] /= w_total
		for region in list:
			ids.append(region.id)
			six[region.id] = Network.specialisation(_six_mix(branches, region.id), nat_six)
			three[region.id] = Network.specialisation(region.sector_mix, nat_three)

	var rank_six: Dictionary = _ranks(ids, six)
	var rank_three: Dictionary = _ranks(ids, three)
	var n: int = ids.size()
	var sum_d2: float = 0.0
	var movers: Array = []
	for id in ids:
		var d: float = float(rank_six[id]) - float(rank_three[id])
		sum_d2 += d * d
		movers.append([id, int(d)])
	movers.sort_custom(func(a, b): return absi(a[1]) > absi(b[1]))
	var rho: float = 1.0 - 6.0 * sum_d2 / (float(n) * (float(n) * float(n) - 1.0))
	print("  regions ranked: %d   Spearman rho: %.4f   (clause (d) ceiling 0.90)" % [n, rho])
	print("  five largest rank movers (six-branch rank minus three-branch rank):")
	for i in 5:
		print("    %-5s %+d" % [movers[i][0], movers[i][1]])
	if rho <= 0.90:
		print("  VERDICT (d): PASS -- the finer mix ranks the roster differently")
	else:
		print("  VERDICT (d): FAIL -- one quantity written twice, production_mix refused")


## {(nace branch, geo code): GVA in million EUR}, from the committed source file.
func _gva_branches() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://sources/eurostat/nama_10r_3gva_2022.json")
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		printerr("nama_10r_3gva_2022.json did not parse")
		return {}
	var data: Dictionary = parsed
	var dims: Array = data["id"]
	var sizes: Array = []
	var inverse: Array = []
	for dim in dims:
		var idx: Dictionary = data["dimension"][dim]["category"]["index"]
		sizes.append(idx.size())
		var inv: Dictionary = {}
		for key in idx.keys():
			inv[int(idx[key])] = key
		inverse.append(inv)
	var strides: Array = []
	strides.resize(sizes.size())
	strides[sizes.size() - 1] = 1
	for i in range(sizes.size() - 2, -1, -1):
		strides[i] = int(strides[i + 1]) * int(sizes[i + 1])
	var wanted := [dims.find("nace_r2"), dims.find("geo")]
	var out: Dictionary = {}
	var values: Dictionary = data["value"]
	for key in values.keys():
		var rem := int(key)
		var coord: Array = []
		for s in strides:
			coord.append(rem / int(s))
			rem = rem % int(s)
		out[[inverse[wanted[0]][coord[wanted[0]]], inverse[wanted[1]][coord[wanted[1]]]]] = values[key]
	return out


## A region's six-branch mix, normalised to exactly 1.0 the way normalised_mix()
## floors its three: five branches floored at 4 decimals, the sixth the remainder.
## A code the source does not answer takes its nation's mix through the caller's
## national mean -- which here reads as all-equal, the same no-signal the importer's
## fallback writes.
func _six_mix(branches: Dictionary, code: String) -> Dictionary:
	var looked: String = code
	if VINTAGE_SIBLING.has(code):
		looked = VINTAGE_SIBLING[code]
	var raw: Dictionary = {}
	var total: float = 0.0
	for b in PRODUCTION_BRANCHES:
		var v: float = float(branches.get([b, looked], 0.0))
		raw[b] = v
		total += v
	var out: Dictionary = {}
	if total <= 0.0:
		for b in PRODUCTION_BRANCHES:
			out[b] = 1.0 / PRODUCTION_BRANCHES.size()
		return out
	var acc: float = 0.0
	for i in PRODUCTION_BRANCHES.size() - 1:
		var b: String = PRODUCTION_BRANCHES[i]
		out[b] = floor(raw[b] / total * 10000.0) / 10000.0
		acc += out[b]
	out[PRODUCTION_BRANCHES[PRODUCTION_BRANCHES.size() - 1]] = snappedf(1.0 - acc, 6)
	return out


## Descending by value, ties broken by id -- a total order, so the rank correlation
## is reproducible even where 19 regions read exactly 0.0 specialisation.
func _ranks(ids: Array, values: Dictionary) -> Dictionary:
	var order: Array = ids.duplicate()
	order.sort_custom(func(a, b):
		if not is_equal_approx(float(values[a]), float(values[b])):
			return float(values[a]) > float(values[b])
		return String(a) < String(b))
	var out: Dictionary = {}
	for i in order.size():
		out[order[i]] = i + 1
	return out
