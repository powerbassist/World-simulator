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
##   (e) PASS -- |corr(network_dev, mix_dev)| 0.3360 against a ceiling of 0.60: the
##       network term is not the mix term renamed. Accessibility spread at the
##       derived decay reads [0.498, 1.147] and the term's raw spread is
##       [-0.0865, +0.0134] points/yr per unit beta.
##   SWEEP -- clause (i) crosses at NETWORK_BETA 10.0 on the channel's own
##       differential fingerprint, exactly linear at 0.010 pp per unit beta;
##       clause (ii) never binds (out-drift 44x under SHARE_DRIFT_MAX, pop-drift
##       pinned by natural change at the rate V2.6c shipped). One-edged band --
##       see network_constants.gd's table and docs/network-model.md section 6.
##
## ONE DEVIATION FROM THE PLAN'S DRAFT, and it is the plan's own instruction: the
## draft read loader.region_features, but GeoLoader.load_geo() keeps only OUTER rings
## (GeoLoader.outer_ring -- the renderer and hit-test ignore holes). A
## reader over that shape reports 12 components and 10 isolates, adding AT13, BE1
## and DE3 to the singleton list -- the exact first-pass bug the plan records. The
## fix is in THIS file, not in src/: the probe parses data/geo/regions.geojson
## directly and joins on every ring of every polygon, holes included.

const DataLoader = preload("res://src/core/data_loader.gd")
const Network = preload("res://src/sim/network.gd")
const Regions = preload("res://src/sim/regions.gd")
const GameState = preload("res://src/core/game_state.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const RegionK = preload("res://src/sim/region_constants.gd")
const MigrationK = preload("res://src/sim/migration_constants.gd")
const NaturalChange = preload("res://src/sim/natural_change.gd")
const Economy = preload("res://src/sim/economy.gd")

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
	_table_decay()
	_table_e()
	_table_f()
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


## DECAY_KM's derivation, and the curve it comes from. The constant is a property of
## the graph, so the probe recomputes and prints it every run: mean shortest-path
## endowment-adjusted km over the continental component's ordered pairs whose HOP
## distance equals the component's mean eccentricity (9.65, measured at plan time;
## printed here again). A decay length set by the roster's own span reads the
## continent rather than a region's neighbours, and a value taken from the graph
## converges where a swept one would move.
func _table_decay() -> void:
	print("\n=== decay: hop-count-to-km curve, continental component ===")
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("data did not load: %s" % [loader.errors])
		return
	var adj: Dictionary = Network.adjacency(loader.region_graph)

	# The continental component: the largest one adjacency leaves.
	var seen: Dictionary = {}
	var best: Array = []
	for start in adj.keys():
		if seen.has(start):
			continue
		var start_id: String = start
		var stack: Array = [start_id]
		var component: Array = []
		seen[start_id] = true
		while not stack.is_empty():
			var current: String = stack.pop_back()
			component.append(current)
			for other in adj[current]:
				var nid: String = other[0]
				if not seen.has(nid):
					seen[nid] = true
					stack.append(nid)
		if component.size() > best.size():
			best = component

	# The CONTINENTAL component, which is what the plan-time eccentricity (9.65)
	# measured: adjacency's own component of 94 before the sea links close the
	# islands. Britain's eleven and the seven singletons are held out by id -- the
	# water is exactly what adjacency cannot express, and mixing the crossings in
	# would measure a roster the constant's derivation never spoke of.
	var continent: Dictionary = {}
	for cid in best:
		var cid_s := String(cid)
		if cid_s.begins_with("UK"):
			continue
		if cid_s in ["FRM", "ITG1", "ITG2", "ES53", "ES63", "ES64"]:
			continue
		continent[cid_s] = true

	# BFS per source over HOPS, carrying the endowment-adjusted km along the tree.
	var hop_km: Dictionary = {}
	var hop_count: Dictionary = {}
	var ecc_sum: float = 0.0
	for source in continent.keys():
		var source_id: String = source
		var dist: Dictionary = {source_id: [0, 0.0]}
		var queue: Array = [source_id]
		var farthest := 0
		while not queue.is_empty():
			var current: String = queue.pop_front()
			var entry: Array = dist[current]
			for other in adj[current]:
				var oid: String = other[0]
				if not continent.has(oid) or dist.has(oid):
					continue
				var step: Array = dist[current]
				dist[oid] = [step[0] + 1, float(step[1]) + float(other[1])]
				farthest = maxi(farthest, int(step[0]) + 1)
				queue.append(oid)
		ecc_sum += farthest
		for oid in dist.keys():
			var entry: Array = dist[oid]
			if entry[0] == 0:
				continue
			hop_km[entry[0]] = float(hop_km.get(entry[0], 0.0)) + float(entry[1])
			hop_count[entry[0]] = int(hop_count.get(entry[0], 0)) + 1

	var hops: Array = hop_count.keys()
	hops.sort()
	print("  continental component %d regions   mean eccentricity %.2f" % [continent.size(), ecc_sum / continent.size()])
	for h in hops:
		print("  hops %2d   pairs %5d   mean km %8.1f" % [h, hop_count[h], hop_km[h] / hop_count[h]])
	var target := 10
	if hop_count.has(target):
		print("  DECAY_KM at the eccentricity's own hop count (%d): %.1f" % [target, hop_km[target] / hop_count[target]])


## (e) COLLINEARITY, measured before anything is swept. The network deviation must
## not be the mix deviation wearing a second name: |corr(network_dev, mix_dev)|
## over the 112 regions, ceiling 0.60 fixed in the plan. V1.6c deleted its deficit
## term at a measured 0.9948; V1.6b accepted 0.2276 against 0.3185. The correlation
## is scale-free, so it is measured at whatever NETWORK_BETA happens to be -- the
## shipped 0.0 short-circuits the term, and this table computes the term's raw
## arithmetic (specialisation x ln accessibility, zero-meaned) itself.
func _table_e() -> void:
	print("\n=== (e) collinear: network deviation vs mix deviation ===")
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("data did not load: %s" % [loader.errors])
		return
	var xs: Array = []
	var ys: Array = []
	for nation_id in loader.regions.keys():
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		var access: Dictionary = Regions.accessibility_for(ns, list, loader.region_graph)
		var national: Dictionary = _national_mix(ns, list)
		var wsum := 0.0
		var netw := 0.0
		for region in list:
			var w: float = Regions.share_of(ns, region.id)
			wsum += w
			netw += w * _net_val(region, access, national)
		if wsum <= 0.0:
			continue
		var net_mean: float = netw / wsum
		for region in list:
			xs.append(Regions.trend_deviation_pct(ns, list, region.id, {}, {}))
			ys.append(_net_val(region, access, national) - net_mean)
	var n := xs.size()
	var sx := 0.0
	var sy := 0.0
	for i in n:
		sx += float(xs[i])
		sy += float(ys[i])
	var mx := sx / n
	var my := sy / n
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in n:
		var dx: float = float(xs[i]) - mx
		var dy: float = float(ys[i]) - my
		sxy += dx * dy
		sxx += dx * dx
		syy += dy * dy
	var rho := 0.0
	if sxx > 0.0 and syy > 0.0:
		rho = sxy / sqrt(sxx * syy)
	print("  regions %d   |corr| %.4f   (clause (e) ceiling 0.60)" % [n, absf(rho)])
	var ymin := INF
	var ymax := -INF
	var amin := INF
	var amax := -INF
	for nation_id in loader.regions.keys():
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		var access: Dictionary = Regions.accessibility_for(ns, list, loader.region_graph)
		for region in list:
			var a: float = float(access.get(region.id, 1.0))
			amin = minf(amin, a)
			amax = maxf(amax, a)
	var ys_all: Array = ys
	for y in ys_all:
		ymin = minf(ymin, float(y))
		ymax = maxf(ymax, float(y))
	print("  accessibility spread [%.3f, %.3f]   net-term spread [%.4f, %.4f] points/yr per unit beta" % [amin, amax, ymin, ymax])
	if absf(rho) <= 0.60:
		print("  VERDICT (e): PASS -- the network term is not the mix term renamed")
	else:
		print("  VERDICT (e): FAIL -- delete NETWORK_BETA and _network_pct, ship the graph")


## The specialisation-times-reach term at one region: the arithmetic
## Regions._network_pct() applies, restated here because a probe cannot set a
## const at runtime -- migration_probe.gd's own reason for emulating through
## share_delta().
func _net_val(region, access: Dictionary, national: Dictionary) -> float:
	return Network.specialisation(region.sector_mix, national) \
		* log(maxf(float(access.get(region.id, 1.0)), 0.0001))


## The nation's output-weighted mean production mix -- the same weighted mean
## Regions._national_production_mix() computes, from live shares.
func _national_mix(ns, region_list: Array) -> Dictionary:
	var out: Dictionary = {}
	var keys: Array = region_list[0].sector_mix.keys()
	for key in keys:
		out[key] = 0.0
	var wsum := 0.0
	for region in region_list:
		var w: float = Regions.share_of(ns, region.id)
		wsum += w
		for key in keys:
			out[key] = float(out[key]) + w * float(region.sector_mix.get(key, 0.0))
	if wsum > 0.0:
		for key in keys:
			out[key] = float(out[key]) / wsum
	return out


## (f) THE SWEEP. Each candidate runs the REAL model -- real economy month, real
## natural change, real migration share_delta -- and applies the candidate's
## network term as the exact multiplicative correction the real tick would have
## applied: monthly_factor(d_mix + d_net) / monthly_factor(d_mix) on the level the
## shipped tick just wrote. That is per-candidate emulation through the shipped
## arithmetic, not a rescale from one measured point (V2.6a's correction). Clause
## (ii)'s population half is emulated at the region level, where the ceiling
## lives: the city-level flow moves shares WITHIN a region and cannot reach the
## bound, and the pull reads the candidate's own unemployment deviation, so the
## Okun channel the network term opens is inside the number.
##
## Clauses, fixed before the run (network_constants.gd carries them verbatim):
##   (i)   largest mover's output share moves >= 0.1 pp over 60 months;
##   (ii)  worst output drift at 168 months <= region_constants.SHARE_DRIFT_MAX,
##         worst population drift at 168 months <= 0.0164.
func _table_f() -> void:
	print("\n=== (f) sweep: NETWORK_BETA against the two ceilings ===")
	print("  beta   move@60(pp)  diff@60(pp)  out-drift  pop-drift   verdicts")
	var loader = DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("data did not load: %s" % [loader.errors])
		return
	var ref: Dictionary = _reference_shares(loader)
	var grid: Array = [0.0, 2.0, 4.0, 5.0, 5.5, 6.0, 6.5, 7.0, 8.0, 10.0]
	for beta in grid:
		_sweep_row(loader, float(beta), ref)


## The inert channel's shares at month 60, per nation -- the reference the
## differential column measures the channel's OWN fingerprint against. Clause (i)
## written on the total move is confounded here: V2.5's mix divergence already
## moves the largest mover 0.093 pp, and the network term first DAMPS that mover
## before its own movers take over, so the total-move column dips below the inert
## row before it crosses. The differential column is the channel's readability,
## which is what the clause is about, and the inert row doubles as the emulation
## check: its pop-drift reads against V2.6c's real-harness 0.01599 at the same
## rate, so the emulator is trusted to about a ten-thousandth.
func _reference_shares(loader) -> Dictionary:
	var ref: Dictionary = {}
	for nation_id in loader.regions.keys():
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		if list.is_empty():
			continue
		for month in 60:
			_emulate_month(state, ns, list, loader, 0.0)
		var shares: Dictionary = {}
		for region in list:
			shares[region.id] = Regions.share_of(ns, region.id)
		ref[nation_id] = shares
	return ref


func _sweep_row(loader, beta: float, ref: Dictionary) -> void:
	var worst_out := 0.0
	var worst_pop := 0.0
	var best_move := 0.0
	var best_diff := 0.0
	for nation_id in loader.regions.keys():
		var state = GameState.new_game(loader, nation_id)
		var ns = state.nations[nation_id]
		var list: Array = loader.regions.get(nation_id, [])
		if list.is_empty():
			continue
		var move60 := 0.0
		var diff60 := 0.0
		var ref_shares: Dictionary = ref.get(nation_id, {})
		for month in 168:
			_emulate_month(state, ns, list, loader, beta)
			if month == 59:
				for region in list:
					move60 = maxf(move60, absf(Regions.share_of(ns, region.id) - float(region.gdp_share)))
					if ref_shares.has(region.id):
						diff60 = maxf(diff60, absf(Regions.share_of(ns, region.id) - float(ref_shares[region.id])))
		for region in list:
			worst_out = maxf(worst_out, absf(Regions.share_of(ns, region.id) - float(region.gdp_share)))
			worst_pop = maxf(worst_pop, absf(float(ns.region_pop_share[region.id]) - float(region.share)))
		best_move = maxf(best_move, move60)
		best_diff = maxf(best_diff, diff60)
	var ok_i := best_move * 100.0 >= 0.1 and best_diff * 100.0 >= 0.1
	var ok_ii := worst_out <= float(RegionK.SHARE_DRIFT_MAX) and worst_pop <= 0.0164
	print("  %4.2f   %8.3f     %8.3f    %8.4f   %8.4f   (i)%s (ii)%s" % [
		beta, best_move * 100.0, best_diff * 100.0, worst_out, worst_pop,
		"OK" if ok_i else "--", "OK" if ok_ii else "--",
	])


## One month of the candidate model: the real economy tick, then the candidate's
## network term applied as the exact multiplicative correction the shipped tick
## would have applied, then the region-level population flow with the candidate
## inside the pull. A probe cannot set a const at runtime, which is why this is
## an emulation and not a sweep over the shipped script -- migration_probe.gd's
## own reason, validated by the inert row against the real harness above.
func _emulate_month(state, ns, list: Array, loader, beta: float) -> void:
	Economy.tick_month(state)
	var access: Dictionary = Regions.accessibility_for(ns, list, loader.region_graph)
	var national: Dictionary = _national_mix(ns, list)
	var wsum := 0.0
	var netw := 0.0
	for region in list:
		var w: float = Regions.share_of(ns, region.id)
		wsum += w
		netw += w * _net_val(region, access, national)
	var net_mean: float = netw / wsum if wsum > 0.0 else 0.0
	var shares: Dictionary = {}
	var rates: Dictionary = {}
	var pulls: Dictionary = {}
	for region in list:
		var rid: String = region.id
		var d_mix: float = Regions.trend_deviation_pct(ns, list, rid, access, {})
		var d_net: float = beta * (_net_val(region, access, national) - net_mean)
		var f0: float = EK.monthly_factor(d_mix)
		if f0 > 0.0:
			ns.region_gdp_eur_bn[rid] = float(ns.region_gdp_eur_bn[rid]) \
				* EK.monthly_factor(d_mix + d_net) / f0
		var s: float = float(ns.region_pop_share[rid])
		shares[rid] = s
		var u: float = clampf(
			float(ns.unemployment_pct) * region.unemployment_rel
				- float(EK.OKUN) * (d_mix + d_net),
			float(EK.UNEMP_MIN_PCT), float(EK.UNEMP_MAX_PCT))
		var per_head: float = Regions.share_of(ns, rid) / maxf(s, 0.000001)
		rates[rid] = Regions.natural_change(region)
		pulls[rid] = per_head * (1.0 - u / 100.0)
	# The region-level flow, Migration.share_delta()'s own expression with the mean
	# in the same share weights, plus natural change -- the real _tick_nation()'s
	# composition with the candidate inside the pull. The city-level flow moves
	# shares WITHIN a region and cannot reach this ceiling, so it is not emulated.
	var sw := 0.0
	var pw := 0.0
	for region in list:
		var s2: float = float(shares[region.id])
		sw += s2
		pw += s2 * float(pulls[region.id])
	var mean_pull: float = pw / sw if sw > 0.0 else 0.0
	var deltas: Dictionary = NaturalChange.deltas(shares, rates)
	for region in list:
		var rid: String = region.id
		var s: float = float(ns.region_pop_share[rid])
		var ds: float = float(MigrationK.MIGRATION_RATE) * s \
			* (float(pulls[rid]) - mean_pull) / 12.0
		ns.region_pop_share[rid] = s + ds + float(deltas.get(rid, 0.0))
