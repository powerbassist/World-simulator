extends RefCounted

## V5.3 PR 3 (c), the author's call 3 (2026-11-14): a plant closure's weight on its
## region. Regions.unemployment_by_region read no firm job, so a closure moved only the
## national rate (a few thousand jobs over thirty million: a hundredth of a point,
## spread over every region by its unemployment_rel). A landed closure now books its
## jobs over its region's labour force onto that region, the people-weighted mean
## taken back from every region (the nation's rate stays Economy's, which already
## counts the jobs through firm_jobs_offset_pct), into ns.region_closure_pts; Regions
## adds it and fades it (economy_constants.CLOSURE_ABSORB_MONTHS, a mean life). move() is the
## strip's read, through the game's own unemployment_by_region, before and after.

const Region = preload("res://src/core/region.gd")
const Regions = preload("res://src/sim/regions.gd")
const Demography = preload("res://src/sim/demography.gd")


## A closure of `jobs` in `city_id` lands: its lift onto the register.
static func book(ns, region_list: Array, city_id: String, jobs: float) -> void:
	var pts := pts_of(ns, region_list, city_id, jobs)
	for id in pts:
		ns.region_closure_pts[id] = float(ns.region_closure_pts.get(id, 0.0)) + float(pts[id])


## {region_id: points} a closure of `jobs` in `city_id` adds: the jobs over the region's
## labour force (the nation's, by the region's people), less its people-weighted mean
## over the regions, so the weighted sum is 0. {} for a city in no region.
static func pts_of(ns, region_list: Array, city_id: String, jobs: float) -> Dictionary:
	var region = Region.region_of_city(region_list, city_id)
	if region == null:
		return {}
	var share := float(ns.region_pop_share.get(region.id, 0.0))
	var total := 0.0
	for other in region_list:
		total += float(ns.region_pop_share.get(other.id, 0.0))
	var force: float = Demography.labour_force(ns) * share
	if force <= 0.0 or total <= 0.0:
		return {}
	var lift := 100.0 * jobs / force
	var out := {}
	for other in region_list:
		out[other.id] = -lift * share / total
	out[region.id] = lift * (1.0 - share / total)
	return out


## The strip's read for the closure `row` (Closures' record: city_id, jobs): {ok,
## region_id, before_pct, after_pct, jobs}, the region's unemployment now and the moment
## the plant shuts, through Regions.unemployment_by_region on the register booked on a
## copy; {ok: false} for a city in no region. Later months move both with the nation's.
static func move(state, ns, row: Dictionary) -> Dictionary:
	var list: Array = state.regions.get(ns.id, [])
	var region = Region.region_of_city(list, String(row.get("city_id", "")))
	if region == null:
		return {"ok": false}
	var access := Regions.accessibility_for(ns, list, state.region_graph)
	var sites: Dictionary = state.project_sited_pct.get(ns.id, {})
	var before := Regions.unemployment_by_region(ns, list, access, sites)
	var held: Dictionary = ns.region_closure_pts
	ns.region_closure_pts = held.duplicate()
	book(ns, list, String(row["city_id"]), float(row["jobs"]))
	var after := Regions.unemployment_by_region(ns, list, access, sites)
	ns.region_closure_pts = held
	return {"ok": true, "region_id": String(region.id), "before_pct": float(before[region.id]),
		"after_pct": float(after[region.id]), "jobs": float(row["jobs"])}
