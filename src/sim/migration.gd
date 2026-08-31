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
const Companies = preload("res://src/sim/companies.gd")


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


# --- The pull -----------------------------------------------------------------

## What a region is worth to somebody deciding whether to live in it: output per
## head times the probability of being employed.
##
## THAT IS HARRIS-TODARO, the textbook model of internal migration, and it is chosen
## because it carries NO FREE WEIGHT -- a product of two ratios the register already
## publishes, where a weighted sum of "jobs, unemployment and service quality" would
## have needed three coefficients nothing could measure. A wage nobody can get is
## worth nothing and a job at half the wage is worth half, which is the whole content
## of the multiplication.
##
## Output per head divides by the LIVE population share rather than the authored one,
## which is what closes the loop: a region people leave has fewer heads to divide its
## output between, so its pull rises and the outflow slows. NEGATIVE FEEDBACK BY
## CONSTRUCTION, which is why migration_constants.SHARE_DRIFT_MAX is a bound with
## measured slack rather than the thing setting the number.
static func region_pull(ns, region_list: Array, region_id: String) -> float:
	var share: float = region_share(ns, region_id)
	if share <= 0.0:
		return 0.0
	var per_head: float = Regions.share_of(ns, region_id) / share
	var employed: float = 1.0 - Regions.unemployment_pct(ns, region_list, region_id) / 100.0
	return per_head * employed


## What one city is worth against the others in ITS OWN region: named jobs per head.
##
## A DIFFERENT SIGNAL AT A DIFFERENT LEVEL, and each is the one its level can see.
## Every city in a region shares that region's output per head and its unemployment
## rate -- the register publishes neither below the region -- so expected income
## cannot separate Lille from a smaller city in the same region and named employers
## can. That is V2.2a's own measured finding read as a mechanism: one city holds a
## third to a half of a nation's named payroll (Lille 33.1 %, Duesseldorf 34.3 %,
## Manchester 44.0 %), and ROADMAP.md's V2.2a paragraph says in terms that this is
## "what makes V2.6's migration a decision rather than a diffusion".
##
## Zero for seven of the ten nations, because data/companies/ names employers in
## three -- so for those seven nothing moves at this level and the region level moves
## them instead. A true zero rather than an absent figure, which is the same
## distinction src/ui/region_panel.gd's payroll column already draws.
static func city_pull(ns, loader, region, city_id: String) -> float:
	var heads: float = city_population(ns, region.id, city_id)
	if heads <= 0.0:
		return 0.0
	return Companies.headcount_in_city(ns, loader, city_id) / heads


# --- The flow -----------------------------------------------------------------

## The named regions' share of the nation, which the flow may not move. The
## remainder is extra-regio and the overseas regions the bounding box drops -- a
## person cannot migrate to somewhere the game does not draw.
static func named_region_total(ns, region_list: Array) -> float:
	var total: float = 0.0
	for region in region_list:
		total += region_share(ns, region.id)
	return total


## One month, for all ten nations. Runs AFTER Companies.tick_month() in
## src/ui/main.gd's order, because the city pull reads live headcount and a month in
## which a subsidy moved a firm's hiring should move people in the same month rather
## than the next one.
static func tick_month(state, loader) -> void:
	if K.MIGRATION_RATE == 0.0:
		return
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		_tick_nation(state.nations[id], state.regions.get(id, []), loader)


## The one expression, applied twice with different denominators -- which is what
## keeps this one machine rather than two. `ds_i = RATE * s_i * (pull_i - mean) / 12`
## with the mean taken in the SAME share weights, so the sum telescopes to exactly
## zero however extreme the spread. Every delta is computed against the shares as
## they stood at the start of the month and applied afterwards, so the result does
## not depend on the order the register is walked in -- Companies._tick_shares()'s
## discipline and Economy.tick_month()'s pre-pass, and it exists here for their
## reason.
static func _tick_nation(ns, region_list: Array, loader) -> void:
	if region_list.is_empty():
		return

	# Level one: between the named regions of the nation.
	var pulls: Dictionary = {}
	var weighted: float = 0.0
	var total: float = 0.0
	for region in region_list:
		var pull: float = region_pull(ns, region_list, region.id)
		var share: float = region_share(ns, region.id)
		pulls[region.id] = pull
		weighted += share * pull
		total += share
	if total > 0.0:
		var mean: float = weighted / total
		for region in region_list:
			var share: float = region_share(ns, region.id)
			ns.region_pop_share[region.id] = share + K.MIGRATION_RATE * share * (float(pulls[region.id]) - mean) / 12.0

	# Level two: between the named cities of each region. The rural residual carries
	# the region's own mean, so it contributes nothing to the average and the named
	# cities' sum is invariant too -- src/sim/regions.gd's treatment of its residual,
	# and the reason this session produces no net urbanisation.
	for region in region_list:
		if region.cities.size() < 2:
			# One city cannot differ from its own mean. Skipped rather than computed,
			# because `pull - mean` is exactly 0.0 there and doing the arithmetic
			# anyway would spend float precision on a guaranteed no-op.
			continue
		var city_pulls: Dictionary = {}
		var city_weighted: float = 0.0
		var city_total: float = 0.0
		for city in region.cities:
			var pull: float = city_pull(ns, loader, region, city.id)
			var share: float = city_share(ns, city.id)
			city_pulls[city.id] = pull
			city_weighted += share * pull
			city_total += share
		if city_total <= 0.0:
			continue
		var city_mean: float = city_weighted / city_total
		for city in region.cities:
			var share: float = city_share(ns, city.id)
			ns.city_pop_share[city.id] = share + K.MIGRATION_RATE * share * (float(city_pulls[city.id]) - city_mean) / 12.0


## Has any region drifted past the bound? Read by tools/migration_probe.gd and by
## tests/test_migration.gd; nothing in the tick calls it, because a bound that
## silently clamps is a bound nobody measures -- src/sim/regions.gd's own sentence.
static func worst_share_drift(ns, region_list: Array) -> float:
	var worst: float = 0.0
	for region in region_list:
		worst = maxf(worst, absf(region_share(ns, region.id) - float(region.share)))
	return worst
