extends RefCounted

## Where a region SITS -- V2.7. Model: docs/network-model.md.
##
## A LEAF, and it takes the graph as a plain Dictionary the way src/sim/siting.gd
## takes weights and signals: the caller holds the loader, this holds the arithmetic
## (U6a's Calendar.due() shape). It preloads network_constants.gd and nothing else,
## and tests/test_network.gd reads the source to say so.
##
## THE GRAPH IS ADJACENCY AND THE ROW LEFT THAT OPEN. docs/tiers/v2.md section 7
## says the choice between per-region adjacency and true routed geometry "is the
## decomposition session's first question", and the answer came from counting rather
## than from taste: adjacency over the committed polygons routes Berlin to Hamburg
## through Brandenburg and Niedersachsen and Berlin to Milan through Switzerland, so
## the transit case the note reserved for routed geometry is a PATH rather than a
## border. What adjacency cannot express is water, and that is eight authored links
## rather than a second geometry. Routed geometry is also a licence question this
## repo has already answered: docs/data-sources.md rejects OpenStreetMap on ODbL's
## share-alike and no permissively-licensed European road linework replaces it.
##
## NOTHING HERE ACCUMULATES. No tick_month(), nothing written on NationState, nothing
## in the save -- src/sim/credit.gd's stateless shape, and the reason SAVE_VERSION
## stays at 30. The index moves because the OUTPUT SHARES move, and those were
## serialised at V2.5.

const K = preload("res://src/sim/network_constants.gd")

## Two caches, both correctness-neutral and both load-bearing for the harness: the
## graph is CONTENT, so the 213x213 endowment-adjusted distance table is a property
## of the committed file and never changes during a run -- computing it fresh per
## call would put a full Dijkstra sweep inside every month of every nation. The
## index memo catches the other repetition: migration and unrest read the same
## nation's shares within one month, and the shares move only when the economy
## ticks. Both caches key the graph by VALUE (GDScript's == on Dictionaries):
## the graph is CONTENT, so every reference in the process -- the loader's, the
## state's, and Budget.project()'s duplicated simulation state -- holds equal
## dictionaries, and value keying is what lets a copy hit the cache instead of
## paying a full Dijkstra rebuild. The comparison is cheap next to what it
## guards (measured ~90 us against a ~1.4 ms recompute); what actually priced
## the old shape was the bound below and the deep copy per miss, both gone.
## The weights ARE rebuilt live every call, so they are compared by VALUE too:
## a caller passing a different nation's weights can never read another's
## index. Stored by reference, because content is never mutated -- data_loader
## reads it once and nothing in src/ writes through it.
static var _matrix_graph: Dictionary = {}
static var _matrix_rows: Dictionary = {}
## ONE ENTRY PER DISTINCT WEIGHTS VECTOR, not one slot. A single slot could never
## hit the case the paragraph above describes: accessibility() is called once per
## nation per system, so between Migration's call for FRA and Unrest's call for FRA
## the other nations' calls had each evicted it, and the full market potential
## sweep ran four times a month instead of once. MEMO_MAX was 16, sized when "the
## roster is ten"; at 29 nations a single sweep evicted its own head, so no call
## in a 29-nation pass could ever hit. 32 is the roster plus headroom, and
## tests/test_network.gd pins that the memo holds a full roster sweep, so the next
## roster growth re-opens this constant on purpose.
const MEMO_MAX := 32
static var _memo: Array = []


## region id -> [[neighbour_id, km], ...], both directions, sorted by neighbour id.
##
## Sorted because a Dictionary's insertion order must never reach a result --
## Siting.site()'s tie rule, and here it is what makes a Dijkstra reproducible when
## two routes tie to the float.
static func adjacency(graph: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var endowment: Dictionary = graph.get("endowment", {})
	for region_id in endowment.keys():
		out[region_id] = []
	for edge in graph.get("edges", []):
		var a: String = String(edge[0])
		var b: String = String(edge[1])
		var km: float = float(edge[2])
		if not out.has(a) or not out.has(b):
			continue
		# THE ENDOWMENT SHORTENS THE EDGE RATHER THAN WEIGHTING THE REGION, and that
		# is where a transport network belongs: a motorway is a property of the
		# crossing, not of either end. The mean of the two endowments, so a
		# well-served region cannot make its poorly-served neighbour's side cheap.
		var served: float = 0.5 * (float(endowment.get(a, 1.0)) + float(endowment.get(b, 1.0)))
		var cost: float = km / maxf(served, 0.05)
		(out[a] as Array).append([b, cost])
		(out[b] as Array).append([a, cost])
	for region_id in out.keys():
		(out[region_id] as Array).sort_custom(func(x, y): return String(x[0]) < String(y[0]))
	return out


## Shortest endowment-adjusted distance from one region to every region it can reach.
## Dijkstra with a linear scan for the frontier: 112 nodes and 251 edges, so a heap
## would be a data structure carrying no information (Region.region_of_city()'s own
## argument about an index).
static func distances_from(graph: Dictionary, from_id: String) -> Dictionary:
	var adj: Dictionary = adjacency(graph)
	if not adj.has(from_id):
		return {}
	var dist: Dictionary = {from_id: 0.0}
	var settled: Dictionary = {}
	while true:
		var best: String = ""
		var best_d: float = INF
		var ids: Array = dist.keys()
		ids.sort()
		for region_id in ids:
			if settled.has(region_id):
				continue
			if float(dist[region_id]) < best_d:
				best_d = float(dist[region_id])
				best = String(region_id)
		if best == "":
			break
		settled[best] = true
		for entry in adj[best]:
			var other: String = String(entry[0])
			var through: float = best_d + float(entry[1])
			if not dist.has(other) or through < float(dist[other]):
				dist[other] = through
	return dist


## Market potential: how much of the roster's output a region can reach, discounted
## by how far away it is, normalised so the `weights`-weighted mean is EXACTLY 1.0.
##
## THE ANCHOR IS A THIRD KIND AND WAS MEASURED RATHER THAN INHERITED. V2.6b1
## normalises unrest's signal in POPULATION weights because a demonstration happens
## where the people are; V2.6b2 took campaign reach OFF that anchor because reach is
## delivered where the PLAYER goes. Accessibility is neither -- it follows the
## infrastructure. What decides it is the aggregate: this index rides on a region's
## OUTPUT growth, and V2.5's spine closes because every regional deviation is
## zero-mean in OUTPUT weights, so an index normalised in any other weighting moves
## the national total and re-opens the definitional swap. The anchor is the
## weighting in which the sum closes, and nothing else was available.
##
## `weights` is region id -> share of national output, passed in rather than read,
## so this file never learns that a NationState exists -- Regions.gdp_per_head_index()'s
## own rule one module over.
static func accessibility(graph: Dictionary, weights: Dictionary) -> Dictionary:
	for entry in _memo:
		if entry["weights"] == weights and entry["graph"] == graph:
			return entry["index"]
	var raw: Dictionary = {}
	var ids: Array = weights.keys()
	ids.sort()
	var endowment: Dictionary = graph.get("endowment", {})
	var rows: Dictionary = _distance_rows(graph)
	# THE SPLIT. The market potential of region i is a foreign part -- every
	# region OUTSIDE the asking nation, priced at the static endowment -- plus an
	# own-nation part priced at live output shares. The foreign part does not
	# depend on which nation is asking, so it is built ONCE per graph and
	# corrected per call: for each own region j, the foreign part already
	# counted e_j at the static endowment, so the live share w_j contributes
	# (w_j - e_j) * exp(-d/decay). The zero-share branch mirrors the per-pair
	# rule below it: a weight of 0 falls back to the endowment, which the
	# foreign part already carries, so the correction is 0. The arithmetic is
	# the old interleaved loop regrouped, so last-bit drift against it is
	# possible; tests/test_network.gd holds the split to 1e-9 against a
	# reference copy of the interleaved form, and the balance re-run gates the
	# shipping at a handful of print-boundary digits.
	var foreign: Dictionary = _foreign_part(graph)
	for region_id in ids:
		var dist: Dictionary = rows.get(String(region_id), {})
		var potential: float = float(foreign.get(String(region_id), 0.0))
		for other in weights.keys():
			if String(other) == String(region_id):
				continue
			var d = dist.get(other)
			if d == null:
				continue
			# The weight is the OTHER region's own output share where the register
			# knows it, and the endowment otherwise: a French region's market
			# includes German output, and this file holds no second nation's shares.
			var mass: float = float(weights.get(other, 0.0))
			if mass <= 0.0:
				continue
			potential += (mass - float(endowment.get(other, 0.0))) * exp(-float(d) / maxf(K.DECAY_KM, 1.0))
		raw[region_id] = potential
	var weighted: float = 0.0
	var total: float = 0.0
	for region_id in ids:
		weighted += float(weights[region_id]) * float(raw[region_id])
		total += float(weights[region_id])
	if total <= 0.0 or weighted <= 0.0:
		var flat: Dictionary = {}
		for region_id in ids:
			flat[region_id] = 1.0
		return flat
	var mean: float = weighted / total
	var out: Dictionary = {}
	for region_id in ids:
		out[region_id] = float(raw[region_id]) / mean
	# The graph is stored by REFERENCE (content, never mutated -- see the cache
	# comment above); the weights and the index by value, because weights are the
	# one input a caller recomputes and the index is what those callers read.
	_memo.append({
		"graph": graph,
		"weights": weights.duplicate(true),
		"index": out.duplicate(true),
	})
	while _memo.size() > MEMO_MAX:
		_memo.pop_front()
	return out


## The 112 shortest-path rows, built once per distinct graph and reused. See the
## cache comment above the constants for why this is a cache and not a computation
## the caller schedules.
static func _distance_rows(graph: Dictionary) -> Dictionary:
	if graph == _matrix_graph and not _matrix_rows.is_empty():
		return _matrix_rows
	var rows: Dictionary = {}
	for region_id in graph.get("endowment", {}).keys():
		rows[String(region_id)] = distances_from(graph, String(region_id))
	_matrix_graph = graph
	_matrix_rows = rows
	return rows


## region id -> sum over EVERY OTHER region k of endowment_k * exp(-d/decay),
## with the per-pair reachability rule of the caller applied. Nation-independent:
## the asking nation's own live shares enter as the (w - e) correction in
## accessibility(), never here. Built once per graph, keyed by the same identity
## test as the distance table -- see the cache comment above the constants.
static var _foreign_graph: Dictionary = {}
static var _foreign_rows: Dictionary = {}

static func _foreign_part(graph: Dictionary) -> Dictionary:
	if graph == _foreign_graph and not _foreign_rows.is_empty():
		return _foreign_rows
	var endowment: Dictionary = graph.get("endowment", {})
	var rows: Dictionary = _distance_rows(graph)
	var out: Dictionary = {}
	for region_id in endowment.keys():
		var dist: Dictionary = rows.get(String(region_id), {})
		var sum: float = 0.0
		for other in endowment.keys():
			if String(other) == String(region_id):
				continue
			var d = dist.get(other)
			if d == null:
				continue
			sum += float(endowment.get(other, 0.0)) * exp(-float(d) / maxf(K.DECAY_KM, 1.0))
		out[String(region_id)] = sum
	_foreign_graph = graph
	_foreign_rows = out
	return out


## Warms the per-graph caches. The 213x213 distance table costs ~2 s to build
## ONCE per process, and built lazily that cost landed on the player's first
## month boundary as a visible freeze -- the only slow call in 240 simmed
## months (measured, tools/_spike_probe.gd's verdict). Paid at boot instead,
## right after the state exists, where the loading moment already is.
static func warm(graph: Dictionary) -> void:
	_distance_rows(graph)
	_foreign_part(graph)


## Half the L1 distance between a region's production mix and its nation's: 0.0 for a
## region that makes exactly what the country makes, 1.0 for one that shares nothing
## with it. Bounded in [0, 1] BY CONSTRUCTION -- two partitions each summing to 1.0
## have an L1 distance of at most 2 -- so this file ships no clamp, which is
## V1.7a's log-odds argument in a third place.
static func specialisation(mix: Dictionary, national_mix: Dictionary) -> float:
	var keys: Array = national_mix.keys()
	keys.sort()
	var l1: float = 0.0
	for key in keys:
		l1 += absf(float(mix.get(key, 0.0)) - float(national_mix[key]))
	return clampf(0.5 * l1, 0.0, 1.0)
