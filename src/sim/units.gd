extends RefCounted

## V5.3 c' (docs/design/v5.3-c-register.md): the construction register. Slice A is
## the reads over the catalogue, the start stock and the player's programmes
## (`ns.unit_programmes`); later slices add the price, the bill's rows, the overrun
## ask, the envelope and the arrival.
##
##   catalogue(loader) / row(loader, id)  the unit types, then the five projects as
##                                        `potential` rows (UnitsLoader builds them);
##   offered(loader, nation, type)        a type is offered where the nation's stock
##                                        file names it, nowhere else: one general rule;
##   gain(ns, loader, type, region)       g = figure_elasticity x n x capacity / C;
##   netted_gain(...)                     g less its people x level weighted mean;
##   shown_figure(...)                    the nation's figure x the priority term x
##                                        the region's level x (1 + the netted gain);
##   fill_by_need / fill_by_population    the sheet's two ways to place N units.
##
## THE NATION'S FIGURE HAS ONE WRITER (section 3): a unit lifts its own region and
## the others give a little back, netted with the people x level weights the loader
## normalised against, so the regions' people-weighted mean stays exactly the
## nation's figure. The nation's figure itself moves only through the units' running
## cost on the line (a later slice), by the lever's own path (Sectors.ratio).
##
## ONLY A DONE ROW MOVES A REGION: a unit still building is capacity nobody has, and a
## unit still being demolished is capacity still open. With no programme every gain
## is exactly 0.0 and the shown figure is the priority read x the level, exactly.
##
## Rule 1: no nation id anywhere; a nation that differs has a stock file saying so.
## Rule 2: no UI. pow() (through Sectors.regional_quantity): main thread only.

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
	var by_region: Dictionary = (loader.unit_stock.get(nation_id, {}) as Dictionary).get(type_id, {})
	return float((by_region.get(region_id, {}) as Dictionary).get("capacity", 0.0))


## The region's level for the type's figure: its sourced figure over the mean of the
## nation's named regions weighted by the live people x the priority term (T2, T3 on
## #410), so the people-weighted mean of level x priority term is exactly 1. 1.0 for a
## type the nation has no level for.
static func level(ns, loader, type_id: String, region_id: String) -> float:
	var b := _basis(ns, loader, type_id, {})
	return float((b["level"] as Dictionary).get(region_id, 1.0))


## n, the units the player's DONE rows built (+) and closed (-) in the region.
static func net_units(ns, type_id: String, region_id: String) -> int:
	var n := 0
	for p in ns.unit_programmes:
		if String(p.get("type", "")) != type_id or String(p.get("state", "")) != UK.STATE_DONE:
			continue
		var sign := -1 if String(p.get("op", "")) == UK.OP_DEMOLISH else 1
		for r in p.get("rows", []):
			if String(r.get("region", "")) == region_id:
				n += sign * int(r.get("units", 0))
	return n


static func gain(ns, loader, type_id: String, region_id: String) -> float:
	return _gain(ns, loader, type_id, region_id, 0)


static func netted_gain(ns, loader, type_id: String, region_id: String) -> float:
	return _netted(ns, loader, type_id, region_id, {})


static func shown_figure(ns, loader, type_id: String, region_id: String) -> float:
	return _shown(ns, loader, type_id, region_id, {})


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
	var t: Dictionary = loader.unit_types[type_id]
	var behind := 1.0 if _better(loader, t) == "lower" else -1.0
	var placed := {}
	for i in n:
		var worst := ""
		var top := -INF
		for id in open:
			var f := behind * _shown(ns, loader, type_id, id, placed)
			if f > top:
				top = f
				worst = id
		placed[worst] = int(placed.get(worst, 0)) + 1
	return _rows(open, placed)


# --- internals ---------------------------------------------------------------

static func _gain(ns, loader, type_id: String, region_id: String, extra: int) -> float:
	var c := start_capacity(loader, ns.id, type_id, region_id)
	if c <= 0.0:
		return 0.0
	var n := net_units(ns, type_id, region_id) + extra
	if n == 0:
		return 0.0
	var t: Dictionary = loader.unit_types[type_id]
	return float(t["figure_elasticity"]) * float(n) * float(t["capacity"]) / c


static func _netted(ns, loader, type_id: String, region_id: String, placed: Dictionary) -> float:
	if not loader.unit_types.has(type_id):
		return 0.0
	var b := _basis(ns, loader, type_id, placed)
	return float((b["gain"] as Dictionary).get(region_id, 0.0)) - float(b["mean_gain"])


## ONE BASIS (the parent's rule, T2 on #410): the weights are exactly what the screen
## multiplies, w = people x priority term x level, the level normalised on the same
## live people x priority term. So the shown figure's people-weighted mean is
##   q x sum(w x (1 + g - mean_g)) / sum(people) = q x sum(w) / sum(people) = q,
## the nation's figure, with a priority set, after migration, with units built. The
## one case it gives way is the floor on (1 + netted) in _shown(): a region whose
## figure would cross zero is held above it, and the mean no longer balances.
## `placed` counts units not yet built (the sheet's by-need fill).
static func _basis(ns, loader, type_id: String, placed: Dictionary) -> Dictionary:
	var out := {"level": {}, "gain": {}, "mean_gain": 0.0}
	if not loader.unit_types.has(type_id):
		return out
	var t: Dictionary = loader.unit_types[type_id]
	var raw: Dictionary = (loader.unit_levels.get(ns.id, {}) as Dictionary).get(String(t["figure"]), {})
	var q := Sectors.quantity(ns, loader, String(t["line"]), String(t["sector"]))
	var people := 0.0
	var tilted := 0.0
	var term := {}
	for r in loader.regions.get(ns.id, []):
		var p := float(ns.region_pop_share.get(r.id, 0.0))
		term[r.id] = Sectors.regional_quantity(ns, loader, String(t["line"]), String(t["sector"]), r.id) / q if q != 0.0 else 1.0
		people += p
		tilted += p * float(term[r.id]) * float(raw.get(r.id, 1.0))
	var norm := tilted / people if people > 0.0 and tilted > 0.0 else 1.0
	var weighted := 0.0
	var weights := 0.0
	for r in loader.regions.get(ns.id, []):
		var level := float(raw.get(r.id, 1.0)) / norm if not raw.is_empty() else 1.0
		var g := _gain(ns, loader, type_id, r.id, int(placed.get(r.id, 0)))
		var w := float(ns.region_pop_share.get(r.id, 0.0)) * float(term[r.id]) * level
		out["level"][r.id] = level
		out["gain"][r.id] = g
		weighted += w * g
		weights += w
	out["mean_gain"] = weighted / weights if weights > 0.0 else 0.0
	return out


## The gain is linear in the units, so enough of them in one region would take the
## figure to zero or past it: (1 + netted) is floored at the multiplier floor
## Sectors already uses (DK.RATIO_FLOOR), never reached by a step the size of a band.
## 0.0 for an id that is not a capacity type (a project's potential row).
static func _shown(ns, loader, type_id: String, region_id: String, placed: Dictionary) -> float:
	if not loader.unit_types.has(type_id):
		return 0.0
	var t: Dictionary = loader.unit_types[type_id]
	var b := _basis(ns, loader, type_id, placed)
	return Sectors.regional_quantity(ns, loader, String(t["line"]), String(t["sector"]), region_id) \
		* float((b["level"] as Dictionary).get(region_id, 1.0)) \
		* maxf(1.0 + float((b["gain"] as Dictionary).get(region_id, 0.0)) - float(b["mean_gain"]), DK.RATIO_FLOOR)


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


static func _better(loader, t: Dictionary) -> String:
	for s in Sectors.sectors_of(loader, String(t["line"])):
		if String(s["id"]) == String(t["sector"]):
			return String(s["quantity"]["better"])
	return "higher"
