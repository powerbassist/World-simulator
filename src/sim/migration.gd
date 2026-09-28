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
## V2.6c MADE THIS THE REGISTER'S ONE HOME FOR THREE FLOWS. Natural change --
## births minus deaths as a measured per-region rate -- composes at the bottom of
## _tick_nation() through src/sim/natural_change.gd, the same telescoping invariant
## with the pull replaced by the differential against the live-share-weighted mean.
## Migration stays the SINGLE WRITER: the leaf computes, this file applies, and the
## conservation checks below hold over the COMBINED flow because every flow
## telescopes in the weights it reads. Model: docs/natural-change-model.md.
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
const NaturalChange = preload("res://src/sim/natural_change.gd")


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
static func region_pull(ns, region_list: Array, region_id: String, access: Dictionary, sites: Dictionary) -> float:
	var share: float = region_share(ns, region_id)
	if share <= 0.0:
		return 0.0
	var per_head: float = Regions.share_of(ns, region_id) / share
	var employed: float = 1.0 - Regions.unemployment_pct(ns, region_list, region_id, access, sites) / 100.0
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
## V4.7a: the jobs figure arrives pre-bucketed -- one pass over the nation's
## firms per month (_jobs_by_city below), not a scan of the whole roster per
## city. At the 2,729-firm register the scan was ~102k firm visits a month; the
## bucket is bit-identical because each city's firms accumulate in roster order
## either way.
static func city_pull(ns, region, city_id: String, jobs_by_city: Dictionary) -> float:
	var heads: float = city_population(ns, region.id, city_id)
	if heads <= 0.0:
		return 0.0
	return float(jobs_by_city.get(city_id, 0.0)) / heads


## Named jobs per city, one pass over the nation's whole firm roster -- the
## migration month's only walk of the register, where it used to be one walk
## per city. Summation order per city is the roster order, matching
## Companies.headcount_in_city exactly, so the flow's inputs are unchanged to
## the bit and the re-run prediction owes nothing.
static func _jobs_by_city(ns, loader) -> Dictionary:
	var out := {}
	for company in Companies.firms_of(loader, ns.id):
		out[company.city] = float(out.get(company.city, 0.0)) + Companies.headcount(ns, company)
	return out


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
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var region_list: Array = state.regions.get(id, [])
		# V2.7. One index per nation-month, from the shares as they stand at the top
		# of this tick -- the same required-argument rule regions.gd states at the
		# function it feeds.
		var access: Dictionary = Regions.accessibility_for(state.nations[id], region_list, state.region_graph)
		_tick_nation(state.nations[id], region_list, loader, access, state.project_sited_pct.get(id, {}))


## One entry's monthly change in share. Extracted so the DIRECTION of the flow is
## testable at all: at the time this was written MIGRATION_RATE was 0.0, unmeasured,
## so an assertion driven only through tick_month() would have passed whatever sign
## the model had -- a flow that moved people TOWARD the poorer, higher-unemployment
## place would have satisfied every invariant this module asserts, because
## conservation and direction are orthogonal failures. MIGRATION_RATE is measured and
## nonzero now (migration_constants.gd), but the reason for the extraction still
## holds: tests/test_migration.gd's _check_share_delta_direction() calls this
## function directly, at a rate it supplies itself, rather than trusting whatever the
## shipped rate happens to be to expose a sign error. This is also the one expression
## both levels share, so having it in one place is what stops them drifting apart.
static func share_delta(share: float, pull: float, mean: float, rate: float) -> float:
	return rate * share * (pull - mean) / 12.0


## The one expression, applied twice with different denominators -- which is what
## keeps this one machine rather than two. `ds_i = RATE * s_i * (pull_i - mean) / 12`
## with the mean taken in the SAME share weights, so the sum telescopes to exactly
## zero however extreme the spread. Every delta is computed against the shares as
## they stood at the start of the month and applied afterwards, so the result does
## not depend on the order the register is walked in -- Companies._tick_shares()'s
## discipline and Economy.tick_month()'s pre-pass, and it exists here for their
## reason. The share is cached beside the pull for the same reason the pull is: a
## later term that read a neighbour's share instead of only its own -- a distance
## weight, a contiguity term -- would make the result walk-order-dependent despite
## this comment, unless every read in the loop comes from one frozen snapshot.
##
## V2.6c ADDED THE THIRD FLOW and with it this file's final shape: MIGRATION and
## NATURAL CHANGE are two answers to one question -- who gains share of the nation
## this month -- and one register with three flows is one machine with three
## denominators, not three machines. Natural change composes at the bottom of
## _tick_nation() and is NOT gated by MIGRATION_RATE: zeroing the rate isolates
## migration, and the natural flow must keep running through that isolation for it
## to stay an isolation of migration alone.
static func _tick_nation(ns, region_list: Array, loader, access: Dictionary, sites: Dictionary) -> void:
	if region_list.is_empty():
		return

	# Defensive, not descriptive: MIGRATION_RATE is measured and nonzero in the
	# shipped tree (migration_constants.gd), so this guard is unreachable today. It
	# stays because a session that ever sets the rate back to 0.0 -- to isolate a
	# regression, say -- should skip the pull and share bookkeeping below entirely
	# rather than run it to compute deltas that share_delta() would multiply by zero
	# anyway, and a guard that is only added when it is first needed is a guard
	# nobody tested. It moved here from tick_month() when natural change landed:
	# the natural flow below answers to the register's rates, not to this constant,
	# and a guard around the whole nation would have made the isolation silent
	# about the one flow it does not isolate.
	if K.MIGRATION_RATE != 0.0:
		_tick_migration(ns, region_list, loader, access, sites, _jobs_by_city(ns, loader))

	# V2.6c. Natural change, the third flow on this register -- births and deaths
	# as a measured per-region rate against the live-share-weighted mean. It runs
	# LAST and reads its own frozen snapshot at that point, so the ordering between
	# the flows is fixed but carries no information: unlike cities-then-regions
	# above, nothing here reads what another flow wrote this month. The anchor is
	# the LIVE share weights, and that is the lesson's other side recorded where the
	# next session will look: V2.6b2 took campaign reach OFF population weighting
	# because reach is delivered where the PLAYER goes -- births happen where the
	# people are, the V2.6b1 output-price side of the line.
	#
	# migration.gd stays the SINGLE WRITER: the deltas come back from the leaf and
	# the write happens here, so the one-writer-per-register property this file
	# asserts in tests/test_migration.gd survives the composition.
	var rates: Dictionary = {}
	var nat_shares: Dictionary = {}
	for region in region_list:
		rates[region.id] = Regions.natural_change(region)
		nat_shares[region.id] = region_share(ns, region.id)
	var nat_deltas: Dictionary = NaturalChange.deltas(nat_shares, rates)
	for region in region_list:
		ns.region_pop_share[region.id] += float(nat_deltas.get(region.id, 0.0))


## The two pull-driven levels exactly as V2.6a shipped them, under the guard the
## composition moved. Cities first, so both levels see start-of-month state; the
## comments below are the original ordering argument, kept whole because the
## natural flow after them is what makes "both levels read start-of-month state"
## mean "start of the MIGRATION step" rather than start of the month.
static func _tick_migration(ns, region_list: Array, loader, access: Dictionary, sites: Dictionary, jobs_by_city: Dictionary) -> void:
	# Level one (run FIRST): the named cities of each region. city_pull() reads its
	# OWN region's live share through city_population(), while region_pull() reads no
	# city's share at all -- so cities-then-regions is the order in which both levels
	# see start-of-month state. Swapping this back would make the city pull divide by
	# the region's POST-flow share, which is a smaller number for a region people are
	# leaving and a larger one for a region people are arriving in -- a same-month
	# look-ahead the region loop below does not get.
	for region in region_list:
		if region.cities.size() < 2:
			# One city cannot differ from its own mean. Skipped rather than computed,
			# because `pull - mean` is exactly 0.0 there and doing the arithmetic
			# anyway would spend float precision on a guaranteed no-op.
			continue
		var city_pulls: Dictionary = {}
		var city_shares: Dictionary = {}
		var city_weighted: float = 0.0
		var city_total: float = 0.0
		for city in region.cities:
			var pull: float = city_pull(ns, region, city.id, jobs_by_city)
			var share: float = city_share(ns, city.id)
			city_pulls[city.id] = pull
			city_shares[city.id] = share
			city_weighted += share * pull
			city_total += share
		if city_total <= 0.0:
			continue
		var city_mean: float = city_weighted / city_total
		for city in region.cities:
			var share: float = float(city_shares[city.id])
			ns.city_pop_share[city.id] = share + share_delta(share, float(city_pulls[city.id]), city_mean, K.MIGRATION_RATE)

	# Level two: between the named regions of the nation.
	var pulls: Dictionary = {}
	var shares: Dictionary = {}
	var weighted: float = 0.0
	var total: float = 0.0
	for region in region_list:
		var pull: float = region_pull(ns, region_list, region.id, access, sites)
		var share: float = region_share(ns, region.id)
		pulls[region.id] = pull
		shares[region.id] = share
		weighted += share * pull
		total += share
	if total > 0.0:
		var mean: float = weighted / total
		for region in region_list:
			var share: float = float(shares[region.id])
			ns.region_pop_share[region.id] = share + share_delta(share, float(pulls[region.id]), mean, K.MIGRATION_RATE)


## Has any region drifted past the bound? Read by tools/migration_probe.gd's table
## (d) -- SHARE_DRIFT_MAX's slack -- and by its sweep bookkeeping in table (e).
## tests/test_migration.gd does NOT call it: that file asserts the partition and the
## direction, not the guard rail's slack, so this stays a probe-only reader. Nothing
## in the tick calls it either, because a bound that silently clamps is a bound
## nobody measures -- src/sim/regions.gd's own sentence.
static func worst_share_drift(ns, region_list: Array) -> float:
	var worst: float = 0.0
	for region in region_list:
		worst = maxf(worst, absf(region_share(ns, region.id) - float(region.share)))
	return worst
