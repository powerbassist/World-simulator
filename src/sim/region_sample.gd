extends RefCounted

## V5.3 e PR B (docs/design/finance-bill.md section 13, call 7 (a)): the writer of the
## regions screen's monthly sample, `ns.region_history`, {region_id: {unemployment,
## gdp_per_head, migration}}, twelve months each (src/sim/series.gd). Written only:
## nothing in the sim reads it back; src/sim/region_read.gd is its reader.
##
## Migration._tick_migration() calls record() once a month with the reads that step
## already takes: the regions' unemployment, their population shares at the start of
## the step, and the share each gained or lost to migration, stored in persons
## (natural change is not migration and is not in it). The spec placed the first two
## at "the Regions step"; there is no such step (Regions.tick_month runs inside
## Economy), and the Migration step holds both figures already, so all three are
## written at one point and every region's three series hold the same months. With
## MIGRATION_RATE at 0.0 (an isolation run) the step skips its pull and writes none.
##
## A leaf over regions.gd and series.gd: migration.gd preloads it, and unrest.gd's
## closure through migration.gd must not reach economy.gd (tests/test_unrest.gd).

const Series = preload("res://src/sim/series.gd")
const Regions = preload("res://src/sim/regions.gd")

const KEYS := ["unemployment", "gdp_per_head", "migration"]


## One month. `unemployment` and `shares` are region id -> % and region id -> the
## population share at the step's start; `deltas` the share each region's migration
## moved.
static func record(ns, region_list: Array, unemployment: Dictionary, shares: Dictionary, deltas: Dictionary) -> void:
	for region in region_list:
		if not ns.region_history.has(region.id):
			ns.region_history[region.id] = {"unemployment": [], "gdp_per_head": [], "migration": []}
		var row: Dictionary = ns.region_history[region.id]
		Series.push(row["unemployment"], float(unemployment[region.id]))
		Series.push(row["gdp_per_head"], Regions.gdp_per_head_index(ns, region_list, region.id, float(shares[region.id])))
		Series.push(row["migration"], float(deltas.get(region.id, 0.0)) * float(ns.population))
