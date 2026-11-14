extends RefCounted

## V5.3 e PR B (docs/design/finance-bill.md section 13): the regions screen's reads
## over `ns.region_history` (written by src/sim/region_sample.gd) and the unrest site.
## A series starts empty and the reads say how many months it holds.

const RegionSample = preload("res://src/sim/region_sample.gd")
const Regions = preload("res://src/sim/regions.gd")
const Unrest = preload("res://src/sim/unrest.gd")

const KEYS := RegionSample.KEYS


## Months the sample holds, 0 to Series.MONTHS. Every region is written in the same
## month, so any region's length is the sample's.
static func months_held(ns) -> int:
	for region_id in ns.region_history:
		return (ns.region_history[region_id]["unemployment"] as Array).size()
	return 0


## The unrest site with its price: Unrest.site_report()'s keys, plus `impulse_pct`
## (unrest's pull on demand, % a year) and `opinion_load` (its weight on approval),
## then `migration`, the site region's net migration in persons a month (a copy of
## its series), and `months`, how many months that series holds.
static func unrest_site(state, ns) -> Dictionary:
	var list: Array = state.regions.get(ns.id, [])
	var out: Dictionary = Unrest.site_report(ns, list, Regions.accessibility_for(ns, list, state.region_graph),
		state.project_sited_pct.get(ns.id, {}))
	out["impulse_pct"] = float(ns.unrest_impulse_pct)
	out["opinion_load"] = float(ns.unrest_opinion_load)
	var row: Dictionary = ns.region_history.get(String(out["region_id"]), {})
	var migration: Array = (row.get("migration", []) as Array).duplicate()
	out["migration"] = migration
	out["months"] = migration.size()
	return out
