extends RefCounted

## People move -- V2.6a. Model: docs/migration-model.md.
##
## TWO PARTITIONS BECOME LIVE, and that is the whole of the session. V2.2a authored a
## region's share of its nation's population and a city's share of its region as
## CONTENT; this file seeds them onto NationState and moves them every month, so the
## expression src/ui/city_panel.gd and src/ui/map_cities.gd have both used since
## V2.2b -- population x region share x city share -- starts telling a different story
## each year without either of them changing a line of arithmetic.
##
## BOTH SUMS ARE INVARIANT BY SUBTRACTION, not by a check somebody has to remember to
## run. The flow is `ds_i = RATE * s_i * (pull_i - mean) / 12` with the mean taken in
## the same share weights, so `sum ds_i` telescopes to exactly zero --
## Trade.sector_shift()'s sum-to-zero rule and Regions.trend_deviation_pct()'s
## zero-mean rule, third instance and the first at two levels at once.
##
## THE TWO RESIDUALS ARE FROZEN, and for two different reasons worth keeping apart.
## The NATIONAL residual is extra-regio and the overseas regions the map's bounding
## box has dropped since S8 -- a person cannot migrate to somewhere the game does not
## draw, so the named regions redistribute among themselves. The REGIONAL residual is
## rural and the towns under the cut, and it carries the region's own mean, which is
## the assignment that adds no information -- src/sim/regions.gd's treatment of its
## own residual exactly. The consequence is worth naming because a later session will
## want it: there is NO NET URBANISATION here, and a session that wants some has to
## author a rural pull rather than inherit one nobody measured.
##
## NOT A LEAF, and the departure is deliberate. src/sim/regions.gd takes its register
## as an Array and holds no loader; this file needs Companies.headcount_in_city(),
## whose answer is per firm and firms are content, so it takes the loader the way
## Campaign.tick_month(state, loader) and Companies.tick_month(state, loader) already
## do. What it does NOT do is name a register field: every regional quantity it reads
## comes back through a Regions function, so tests/test_geography.gd's assertion that
## the register has exactly one reader stays green -- asserted on purpose in
## tests/test_migration.gd rather than left to luck.

const K = preload("res://src/sim/migration_constants.gd")
const Regions = preload("res://src/sim/regions.gd")


## Seed both levels from the authored shares. Called once from GameState.new_game(),
## beside Regions.init_nation() and for its reason: each seeds a live stock.
##
## The authored share is where a place STARTED. Re-deriving these on load would erase
## the movement the player watched happen, which is service_quality's reason at V1.5a
## and the region GDP stock's at V2.5 -- see tests/test_save_load.gd.
static func init_nation(ns, region_list: Array) -> void:
	ns.region_pop_share.clear()
	ns.city_pop_share.clear()
	for region in region_list:
		ns.region_pop_share[region.id] = float(region.share)
		for city in region.cities:
			ns.city_pop_share[city.id] = float(city.share)


## A region's live share of its nation's population. Not the authored `share`: that
## is where it started, and the difference between the two is what this session
## exists to make visible -- Regions.share_of()'s own sentence one quantity over.
static func region_share(ns, region_id: String) -> float:
	return float(ns.region_pop_share.get(region_id, 0.0))


## A city's live share of ITS REGION's population.
static func city_share(ns, city_id: String) -> float:
	return float(ns.city_pop_share.get(city_id, 0.0))


## The one place the two shares are multiplied by the national head count. Every
## caller reads it here rather than writing the product out, which is V2.2b's
## PanelKit.pop_text() lesson applied to the quantity rather than to its formatting:
## three callers writing one expression is three roundings of one figure waiting to
## disagree.
static func city_population(ns, region_id: String, city_id: String) -> float:
	return float(ns.population) * region_share(ns, region_id) * city_share(ns, city_id)
