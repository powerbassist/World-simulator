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


## The region's figure over the nation's, people-weighted mean 1; 1.0 with no row.
static func level(loader, nation_id: String, figure: String, region_id: String) -> float:
	var by_figure: Dictionary = (loader.unit_levels.get(nation_id, {}) as Dictionary).get(figure, {})
	return float(by_figure.get(region_id, 1.0))


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
	var open := _buildable(ns, loader, type_id)
	var total := 0.0
	for id in open:
		total += float(ns.region_pop_share.get(id, 0.0))
	var placed := {}
	var rest: Array = []
	var left := n
	for id in open:
		var exact := float(n) * float(ns.region_pop_share.get(id, 0.0)) / total if total > 0.0 else 0.0
		placed[id] = int(floorf(exact))
		left -= int(placed[id])
		rest.append([exact - floorf(exact), id])
	rest.sort_custom(func(a, b): return a[0] > b[0])
	for i in mini(left, rest.size()):
		placed[rest[i][1]] = int(placed[rest[i][1]]) + 1
	return _rows(open, placed)


## Section 3, "by need": one unit at a time into the region whose shown figure is
## furthest behind the nation's, counting the units already placed, until N.
static func fill_by_need(ns, loader, type_id: String, n: int) -> Array:
	var open := _buildable(ns, loader, type_id)
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


## The region's gain less the people x level weighted mean of every named region's,
## `placed` counting units not yet built (the sheet's by-need fill).
static func _netted(ns, loader, type_id: String, region_id: String, placed: Dictionary) -> float:
	if not loader.unit_types.has(type_id):
		return 0.0
	var figure := String(loader.unit_types[type_id]["figure"])
	var weighted := 0.0
	var weights := 0.0
	var own := 0.0
	for r in loader.regions.get(ns.id, []):
		var g := _gain(ns, loader, type_id, r.id, int(placed.get(r.id, 0)))
		var w := float(ns.region_pop_share.get(r.id, 0.0)) * level(loader, ns.id, figure, r.id)
		weighted += w * g
		weights += w
		if r.id == region_id:
			own = g
	return own - weighted / weights if weights > 0.0 else own


static func _shown(ns, loader, type_id: String, region_id: String, placed: Dictionary) -> float:
	var t: Dictionary = loader.unit_types[type_id]
	var line := String(t["line"])
	var sector := String(t["sector"])
	return Sectors.regional_quantity(ns, loader, line, sector, region_id) \
		* level(loader, ns.id, String(t["figure"]), region_id) \
		* (1.0 + _netted(ns, loader, type_id, region_id, placed))


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
