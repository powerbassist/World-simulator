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
## graph is CONTENT, so the 112x112 endowment-adjusted distance table is a property
## of the committed file and never changes during a run -- computing it fresh per
## call would put a full Dijkstra sweep inside every month of every nation. The
## index memo catches the other repetition: migration and unrest read the same
## nation's shares within one month, and the shares move only when the economy
## ticks. Deep equality (GDScript's == on Dictionaries) is the validity test, so a
## caller passing a different nation's weights can never read another's index.
static var _matrix_graph: Dictionary = {}
static var _matrix_rows: Dictionary = {}
static var _memo_graph: Dictionary = {}
static var _memo_weights: Dictionary = {}
static var _memo_index: Dictionary = {}


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
	if weights == _memo_weights and graph == _memo_graph and not _memo_index.is_empty():
		return _memo_index
	var raw: Dictionary = {}
	var ids: Array = weights.keys()
	ids.sort()
	var endowment: Dictionary = graph.get("endowment", {})
	var rows: Dictionary = _distance_rows(graph)
	for region_id in ids:
		var dist: Dictionary = rows.get(String(region_id), {})
		var potential: float = 0.0
		for other in endowment.keys():
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
				mass = float(endowment.get(other, 0.0))
			potential += mass * exp(-float(d) / maxf(K.DECAY_KM, 1.0))
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
	_memo_graph = graph
	_memo_weights = weights.duplicate()
	_memo_index = out
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
	_matrix_graph = graph.duplicate(true)
	_matrix_rows = rows
	return rows


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
