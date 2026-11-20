extends RefCounted

## V5.3 c' (docs/design/v5.3-c-register.md): the construction register's reads over
## the catalogue, the start stock and the player's programmes (`ns.unit_programmes`).
##
##   catalogue(loader) / row(loader, id)  the unit types, then the five projects as
##                                        `potential` rows (UnitsLoader builds them);
##   offered(loader, nation, type)        a type is offered where the nation's stock
##                                        file names it, nowhere else: one general rule;
##   capacity_delta(ns, loader, type, r)  d, the capacity the player added (built units
##                                        x the type's capacity) less what was closed;
##   factor(ns, loader, type, r)          f = max(1 + d / C, RATIO_FLOOR) ^ elasticity,
##                                        Sectors.regional_quantity's form;
##   netted_factor(...)                   f over its people x level x priority mean;
##   national_figure(ns, loader, type)    the type's `national` x the sector's own path;
##   shown_figure(...)                    national figure x level x priority term x
##                                        netted factor;
##   fill_by_need / fill_by_population    the sheet's two ways to place N units.
##
## EACH TYPE ANSWERS ITS OWN FIGURE (section 1, amended 2026-11-17): a lycée's pupils
## per teacher in upper-secondary schools, not the sector's primary figure, so its
## national value and its regional levels come from one table, in its stock file. It
## rides the sector's path: the money on the line moves it as Sectors.ratio moves the
## sector, and nothing else does (no second channel).
##
## EVERY RULE READS CAPACITY (section 3): pupils enrolled, beds. The count of
## establishments is for the screen. Only a DONE row moves a region: capacity still
## building is capacity nobody has, and capacity still being closed is still open.
##
## THE NATION'S FIGURE HAS ONE WRITER: the netting weights are exactly what the screen
## multiplies, people x level x priority term, the level normalised on the same live
## people x priority term, and the floor applied to f BEFORE the mean, so the shown
## figure's people-weighted mean is the type's national figure exactly, a closure to
## the floor included. With no programme every f is exactly 1.0.
##
## Rule 1: no nation id anywhere; a nation that differs has a stock file saying so.
## Rule 2: no UI. pow() (here and through Sectors): main thread only.

const UK = preload("res://src/sim/units_constants.gd")
const Sectors = preload("res://src/sim/sectors.gd")
const DK = preload("res://src/sim/domains_constants.gd")


static func catalogue(loader) -> Array:
	var ids: Array = loader.unit_types.keys()
	ids.sort()
	var out: Array = []
	for id in ids:
		out.append(loader.unit_types[id])
	out.append_array(loader.unit_potential)
	return out


static func row(loader, id: String) -> Dictionary:
	if loader.unit_types.has(id):
		return loader.unit_types[id]
	for p in loader.unit_potential:
		if String(p["id"]) == id:
			return p
	return {}


static func offered(loader, nation_id: String, type_id: String) -> bool:
	return (loader.unit_stock.get(nation_id, {}) as Dictionary).has(type_id)


## C, the region's capacity of the type at the start (its stock row), 0 with none.
static func start_capacity(loader, nation_id: String, type_id: String, region_id: String) -> float:
	return float(_stock_row(loader, nation_id, type_id, region_id).get("capacity", 0.0))


## The establishments the stock counts there: shown, never computed with.
static func start_units(loader, nation_id: String, type_id: String, region_id: String) -> int:
	return int(_stock_row(loader, nation_id, type_id, region_id).get("units", 0))


## The capacity one new unit of the type adds in the nation (the catalogue's, by nation).
static func unit_capacity(loader, nation_id: String, type_id: String) -> float:
	return float((loader.unit_types[type_id]["capacity"] as Dictionary).get(nation_id, 0.0))


## The region's level: its sourced figure over the national one, normalised on the live
## people x the priority term, so their people-weighted mean is exactly 1. 1.0 for a
## type the nation has no level for.
static func level(ns, loader, type_id: String, region_id: String) -> float:
	return float((_basis(ns, loader, type_id, {})["level"] as Dictionary).get(region_id, 1.0))


## d: the capacity the player's DONE rows built (+ units x the type's capacity) and
## closed (- capacity, a closure is entered in capacity) in the region.
static func capacity_delta(ns, loader, type_id: String, region_id: String) -> float:
	var d := 0.0
	for p in ns.unit_programmes:
		if String(p.get("type", "")) != type_id or String(p.get("state", "")) != UK.STATE_DONE:
			continue
		for r in p.get("rows", []):
			if String(r.get("region", "")) == region_id:
				d += row_capacity(ns, loader, p, r)
	return d


## One region row's capacity, signed: + units x capacity for a build, - capacity closed.
static func row_capacity(ns, loader, programme: Dictionary, r: Dictionary) -> float:
	if String(programme.get("op", "")) == UK.OP_DEMOLISH:
		return -float(r.get("capacity", 0.0))
	return float(r.get("units", 0)) * unit_capacity(loader, ns.id, String(programme["type"]))


static func factor(ns, loader, type_id: String, region_id: String) -> float:
	return _factor(ns, loader, type_id, region_id, 0)


static func netted_factor(ns, loader, type_id: String, region_id: String) -> float:
	var b := _basis(ns, loader, type_id, {})
	return float((b["factor"] as Dictionary).get(region_id, 1.0)) / float(b["mean_factor"])


## The type's national figure: its `national` start x the sector's own path.
static func national_figure(ns, loader, type_id: String) -> float:
	var t: Dictionary = loader.unit_types[type_id]
	return float((loader.unit_national.get(ns.id, {}) as Dictionary).get(type_id, 0.0)) \
		* Sectors.path_factor(ns, loader, String(t["line"]), String(t["sector"]))


static func shown_figure(ns, loader, type_id: String, region_id: String) -> float:
	return _shown(ns, loader, type_id, region_id, {})


## The register sheet's "after" (section 9, row 1): every region's shown figure with
## `placed` ({region: units}) counted as if built, from ONE basis, so the netting the
## other regions give back is the rule's own. {} for an id that is not a capacity type.
static func preview(ns, loader, type_id: String, placed: Dictionary) -> Dictionary:
	var out := {}
	if not loader.unit_types.has(type_id):
		return out
	var b := _basis(ns, loader, type_id, placed)
	var n := national_figure(ns, loader, type_id)
	for id in b["level"]:
		out[id] = n * float(b["term"][id]) * float(b["level"][id]) * float(b["factor"][id]) / float(b["mean_factor"])
	return out


## Section 3, "by population": N units split by region_pop_share over the regions
## that hold the type, largest remainder first (ties to the regions' file order).
static func fill_by_population(ns, loader, type_id: String, n: int) -> Array:
	var open := _buildable(ns, loader, type_id) if n > 0 else []
	var total := 0.0
	for id in open:
		total += float(ns.region_pop_share.get(id, 0.0))
	var placed := {}
	var rest: Array = []
	var left := n
	for i in open.size():
		var id: String = open[i]
		# No people counted at all (T13 on #410): an equal split, never fewer than N.
		var share := float(ns.region_pop_share.get(id, 0.0)) / total if total > 0.0 else 1.0 / open.size()
		var exact := float(n) * share
		placed[id] = int(floorf(exact))
		left -= int(placed[id])
		rest.append([exact - floorf(exact), i, id])
	# sort_custom is not stable (T12): ties go to the regions' file order.
	rest.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for i in mini(left, rest.size()):
		placed[rest[i][2]] = int(placed[rest[i][2]]) + 1
	return _rows(open, placed)


## Section 3, "by need": one unit at a time into the region whose shown figure is
## furthest behind the nation's, counting the units already placed, until N.
static func fill_by_need(ns, loader, type_id: String, n: int) -> Array:
	var open := _buildable(ns, loader, type_id) if n > 0 else []
	if open.is_empty():
		return []
	var behind := 1.0 if String(loader.unit_types[type_id]["figure"]["better"]) == "lower" else -1.0
	var placed := {}
	# Every candidate of a step reads the same placed units: one set of factors a step over
	# one base for the whole fill, not a whole basis a candidate (a 200-unit fill froze the
	# register 1-2 s; QA TAKE on #420). The same arithmetic as preview(), in the same order.
	var base := _base(ns, loader, type_id)
	var national := national_figure(ns, loader, type_id)
	for i in n:
		var worst := ""
		var top := -INF
		var b := _with_factors(base, ns, loader, type_id, placed)
		for id in open:
			var f := behind * (national * float(b["term"][id]) * float(b["level"][id]) * float(b["factor"][id]) / float(b["mean_factor"]))
			if f > top:
				top = f
				worst = id
		placed[worst] = int(placed.get(worst, 0)) + 1
	return _rows(open, placed)


# --- internals ---------------------------------------------------------------

## f, floored before any mean is taken; exactly 1.0 with nothing built or closed.
static func _factor(ns, loader, type_id: String, region_id: String, extra_units: int) -> float:
	var c := start_capacity(loader, ns.id, type_id, region_id)
	if c <= 0.0:
		return 1.0
	var d := capacity_delta(ns, loader, type_id, region_id) + float(extra_units) * unit_capacity(loader, ns.id, type_id)
	if d == 0.0:
		return 1.0
	return pow(maxf(1.0 + d / c, DK.RATIO_FLOOR), float(loader.unit_types[type_id]["figure_elasticity"]))


## ONE BASIS (the parent's rule, T2 on #410): w = people x priority term x level, the
## level normalised on the same live people x priority term, so
##   N x sum(w x f / mean_f) / sum(people) = N x sum(w) / sum(people) = N,
## the type's national figure, with a priority set, after migration, with units built,
## at the floor too (the floor is in f, before the mean). `placed` counts units not yet
## built (the sheet's by-need fill).
static func _basis(ns, loader, type_id: String, placed: Dictionary) -> Dictionary:
	if not loader.unit_types.has(type_id):
		return {"level": {}, "factor": {}, "term": {}, "mean_factor": 1.0}
	return _with_factors(_base(ns, loader, type_id), ns, loader, type_id, placed)


## The basis's part that no placed unit moves: each region's term, level and weight w.
static func _base(ns, loader, type_id: String) -> Dictionary:
	var out := {"level": {}, "term": {}, "w": {}}
	var t: Dictionary = loader.unit_types[type_id]
	var rel: Dictionary = (loader.unit_levels.get(ns.id, {}) as Dictionary).get(type_id, {})
	var q := Sectors.quantity(ns, loader, String(t["line"]), String(t["sector"]))
	var people := 0.0
	var tilted := 0.0
	for r in loader.regions.get(ns.id, []):
		var p := float(ns.region_pop_share.get(r.id, 0.0))
		var term := Sectors.regional_quantity(ns, loader, String(t["line"]), String(t["sector"]), r.id) / q if q != 0.0 else 1.0
		out["term"][r.id] = term
		people += p
		tilted += p * term * float(rel.get(r.id, 1.0))
	var norm := tilted / people if people > 0.0 and tilted > 0.0 else 1.0
	for r in loader.regions.get(ns.id, []):
		var level := float(rel.get(r.id, 1.0)) / norm if not rel.is_empty() else 1.0
		out["level"][r.id] = level
		out["w"][r.id] = float(ns.region_pop_share.get(r.id, 0.0)) * float(out["term"][r.id]) * level
	return out


## The base with each region's factor f for `placed`, and the weighted mean of f.
static func _with_factors(base: Dictionary, ns, loader, type_id: String, placed: Dictionary) -> Dictionary:
	var out := {"level": base["level"], "factor": {}, "term": base["term"], "mean_factor": 1.0}
	var weighted := 0.0
	var weights := 0.0
	for r in loader.regions.get(ns.id, []):
		var f := _factor(ns, loader, type_id, r.id, int(placed.get(r.id, 0)))
		var w := float(base["w"][r.id])
		out["factor"][r.id] = f
		weighted += w * f
		weights += w
	if weights > 0.0 and weighted > 0.0:
		out["mean_factor"] = weighted / weights
	return out


## 0.0 for an id that is not a capacity type (a project's potential row).
static func _shown(ns, loader, type_id: String, region_id: String, placed: Dictionary) -> float:
	if not loader.unit_types.has(type_id):
		return 0.0
	var b := _basis(ns, loader, type_id, placed)
	return national_figure(ns, loader, type_id) * float((b["term"] as Dictionary).get(region_id, 1.0)) \
		* float((b["level"] as Dictionary).get(region_id, 1.0)) \
		* float((b["factor"] as Dictionary).get(region_id, 1.0)) / float(b["mean_factor"])


static func _stock_row(loader, nation_id: String, type_id: String, region_id: String) -> Dictionary:
	var by_region: Dictionary = (loader.unit_stock.get(nation_id, {}) as Dictionary).get(type_id, {})
	return by_region.get(region_id, {})


static func _buildable(ns, loader, type_id: String) -> Array:
	var out: Array = []
	if not offered(loader, ns.id, type_id):
		return out
	for r in loader.regions.get(ns.id, []):
		if start_capacity(loader, ns.id, type_id, r.id) > 0.0:
			out.append(String(r.id))
	return out


static func _rows(order: Array, placed: Dictionary) -> Array:
	var out: Array = []
	for id in order:
		if int(placed.get(id, 0)) > 0:
			out.append({"region": id, "units": int(placed[id])})
	return out
