extends RefCounted

## The nation, from below -- V2.5. Model: docs/region-economy-model.md.
##
## NATIONAL GDP IS THE SUM OF THE REGIONS, and that is a definition rather than a
## reconciliation. From the MVP to V2.4 `ns.gdp_eur_bn` was the sum of the three
## sectors; it is the sum of the regions now, and Economy._apply_growth_to_sectors()
## reconciles the sectors to that number instead of computing a target of its own.
## There is no rescale-the-regions-to-match pass anywhere, which is what
## docs/tiers/v2.md section 5 means by "the partition is the model, not a correction
## on top of one".
##
## THE ALTERNATIVE THAT WAS REFUSED, recorded because a later session will reach for
## it: keep the sector sum as the authority and normalise regional weights into it.
## Exact by construction and bit-identical for free -- and top-down wearing the
## partition's clothes, one step from the ninth-addend version section 5's own
## warning box already declined.
##
## A LEAF. This file preloads economy_constants.gd and region_constants.gd and
## nothing else; it never reaches Economy, Trade, Demography or the loader's other
## registers, and tests/test_regions.gd reads the source to say so. The register it
## reads is passed in as an Array, U6a's Calendar.due() shape: the caller holds the
## loader, this holds the arithmetic.

const C = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/region_constants.gd")
# V2.7. Downstream of nothing: network.gd preloads only its own constants, so this
# is a chain and not a cycle -- and the leaf test that polices this file still
# holds, because what it forbids is the systems that would make regions.gd reach
# SIDEWAYS (economy, trade, demography, the loader). The graph itself travels in
# as a Dictionary from the caller; only the decay length lives behind NK.
const NK = preload("res://src/sim/network_constants.gd")
const Net = preload("res://src/sim/network.gd")


## Seed the level from the authored shares. Called once from GameState.new_game(),
## beside Demography, Society, Unrest and Defence's inits and for their reason: each
## of those seeds a live STOCK, and this seeds one too.
##
## The residual takes `gdp - sum` rather than `1.0 - sum` times GDP, so the entries
## add up to the national figure EXACTLY at month zero whatever the authored shares
## round to. That is the register's own rule -- a residual which is the remainder
## cannot drift from what it is the remainder of -- applied to a level.
static func init_nation(ns, region_list: Array) -> void:
	ns.region_gdp_eur_bn.clear()
	if region_list.is_empty():
		return
	var named: float = 0.0
	for region in region_list:
		var value: float = ns.gdp_eur_bn * region.gdp_share
		ns.region_gdp_eur_bn[region.id] = value
		named += value
	ns.region_gdp_eur_bn[K.RESIDUAL_KEY] = ns.gdp_eur_bn - named


## The region's own trend, by the same expression Economy.trend_pct() applies to a
## nation: share-weighted SECTOR_TREND over its authored mix. Ten nations get a
## hundred and twelve different trends out of one constant table and no per-region
## branch, which is CLAUDE.md's first rule one level down.
static func trend_pct(region) -> float:
	var trend: float = 0.0
	for key in C.SECTOR_TREND.keys():
		trend += float(region.sector_mix.get(key, 0.0)) * float(C.SECTOR_TREND[key])
	return trend


## The GDP-weighted mean regional trend, INCLUDING the residual at the national mix.
## The residual is output the register does not name and it grows with the country by
## definition, so giving it the mean is the only assignment that adds no information.
## Do NOT name a local `total` here -- it shadows total() below and the call fails to
## resolve. GDScript reports that as a type error on an unrelated line.
static func _mean_trend_pct(ns, region_list: Array) -> float:
	var weighted: float = 0.0
	var named: float = 0.0
	for region in region_list:
		var value: float = float(ns.region_gdp_eur_bn.get(region.id, 0.0))
		weighted += value * trend_pct(region)
		named += value
	if named <= 0.0:
		return 0.0
	# The residual carries the named mean, so it contributes nothing to the average
	# and the sum below is the named regions' own weighted mean.
	return weighted / named


## A region's growth deviation from its nation's, in points per year. ZERO-MEAN OVER
## THE NAMED REGIONS BY CONSTRUCTION, which is the whole of why the aggregate stays
## on the national trajectory -- Trade.sector_shift()'s sum-to-zero rule, one level
## up and enforced by subtraction rather than by a load-time check. Since V2.7 it is
## zero-mean three times over: sector mix, network, and sited-project payoffs.
##
## THE FOURTH AND FIFTH ARGUMENTS ARE REQUIRED AND NOT DEFAULTED. A defaulted empty
## Dictionary would read as "no network" / "nothing built" and every harness that
## forgot to pass one would silently run the pre-V2.7 model and agree with itself
## about a re-run that measured nothing -- which is precisely what V1.5d shipped
## when neither harness called Media.tick_month(). tests/test_network.gd reads both
## harnesses and fails if either omits them.
static func trend_deviation_pct(ns, region_list: Array, region_id: String, access: Dictionary, sites: Dictionary) -> float:
	if region_id == K.RESIDUAL_KEY:
		return 0.0
	for region in region_list:
		if region.id == region_id:
			var mix: float = trend_pct(region) - _mean_trend_pct(ns, region_list)
			return mix + _network_pct(ns, region_list, region, access) + _sited_pct(ns, region_list, region_id, sites)
	return 0.0


## What a FINISHED project is worth here, in points of growth per year, measured
## against the nation's own output-weighted mean of the same payoffs so the
## national total is untouched: the site gains `p - mean` and every other region
## loses its weighted share of the mean. V2.7's third term. The map arrives raw
## ({region id -> points/year}, Projects.sited_pct()); the subtraction happens
## HERE, because zero-mean is a property of the readers it protects and not of the
## content -- a project's authored payoff is what it is.
##
## A region hosting nothing reads exactly `-mean`, never 0.0: that is the model,
## not a leak. The nation's total is unchanged, which is the invariant that
## matters, and V1.6f's national channel still carries the level through
## project_potential_target_pct -- one act, priced once.
static func _sited_pct(ns, region_list: Array, region_id: String, sites: Dictionary) -> float:
	if sites.is_empty():
		return 0.0
	var own: float = float(sites.get(region_id, 0.0))
	var weighted: float = 0.0
	var total: float = 0.0
	for other in region_list:
		var w: float = share_of(ns, other.id)
		weighted += w * float(sites.get(other.id, 0.0))
		total += w
	if total <= 0.0:
		return 0.0
	return own - weighted / total


## The accessibility index for one nation, from its live output shares -- the
## weights-building expression every caller of trend_deviation_pct() would otherwise
## repeat, and the one place that decides what a region weighs. network.gd never
## learns that a NationState exists (its own rule); this file never learns where the
## graph came from -- the caller passes it, `state.region_graph` today.
static func accessibility_for(ns, region_list: Array, graph: Dictionary) -> Dictionary:
	var weights: Dictionary = {}
	for region in region_list:
		weights[region.id] = share_of(ns, region.id)
	return Net.accessibility(graph, weights)


## What a region's POSITION is worth, in points of growth per year, measured against
## the nation's own output-weighted mean so it cannot move the national total.
##
## THE PRODUCT IS THE MODEL. `specialisation` says how much a region needs a market
## it does not contain and `ln(accessibility)` says how much market it can reach;
## either alone is half an argument. A region making exactly what its country makes
## reads exactly 0.0 whatever its accessibility, and a region at exactly the mean
## accessibility reads exactly 0.0 whatever it makes -- two structural zeros, neither
## of them a clamp. The mix here is `sector_mix`: the six-branch production mix was
## REFUSED at clause (d) (rho 0.9170 against 0.90 -- one quantity written twice),
## and the refusal is recorded beside the field it would have extended.
static func _network_pct(ns, region_list: Array, region, access: Dictionary) -> float:
	if NK.NETWORK_BETA == 0.0:
		return 0.0
	var national: Dictionary = _national_production_mix(ns, region_list)
	var own: float = Net.specialisation(region.sector_mix, national) \
		* log(maxf(float(access.get(region.id, 1.0)), 0.0001))
	var weighted: float = 0.0
	var total: float = 0.0
	for other in region_list:
		var w: float = share_of(ns, other.id)
		weighted += w * Net.specialisation(other.sector_mix, national) \
			* log(maxf(float(access.get(other.id, 1.0)), 0.0001))
		total += w
	if total <= 0.0:
		return 0.0
	return NK.NETWORK_BETA * (own - weighted / total)


## The nation's own output-weighted mean production mix -- the national mix a
## region's specialisation is measured against, not the authored national sector
## shares, because the comparison has to be like for like: live regions against the
## live whole of them.
static func _national_production_mix(ns, region_list: Array) -> Dictionary:
	var keys: Array = []
	if not region_list.is_empty():
		keys = region_list[0].sector_mix.keys()
	var out: Dictionary = {}
	for key in keys:
		out[key] = 0.0
	var weighted: float = 0.0
	for region in region_list:
		var w: float = share_of(ns, region.id)
		weighted += w
		for key in keys:
			out[key] += w * float(region.sector_mix.get(key, 0.0))
	if weighted <= 0.0:
		return out
	for key in keys:
		out[key] = out[key] / weighted
	return out


## Grow every region and return the month's national GDP -- which IS the sum.
## Economy._tick_nation() takes the return value as its target.
##
## The deviation is applied to the region's own growth rate rather than to its level,
## so a region that grows faster compounds, which is what makes divergence a
## trajectory rather than a one-off tilt. SHARE_DRIFT_MAX is checked here rather than
## clamped on the rate, because the quantity the bound is about is the SHARE.
static func tick_month(ns, region_list: Array, growth: float, access: Dictionary, sites: Dictionary) -> float:
	if ns.region_gdp_eur_bn.is_empty():
		return ns.gdp_eur_bn * C.monthly_factor(growth)

	# THE MEAN IS TAKEN ONCE, BEFORE THE LOOP MUTATES ANY LEVEL -- not through
	# trend_deviation_pct(), which recomputes it against live state and would
	# therefore drift as this loop writes region after region. The deviation
	# EXPRESSION below is still the one expression: mix term, network term, sited
	# term -- identical to the public function's, and at NETWORK_BETA 0.0 with
	# nothing built it is bit-equal to the pre-V2.7 arithmetic because both added
	# terms return exactly 0.0.
	var mean: float = _mean_trend_pct(ns, region_list)
	var sum: float = 0.0

	for region in region_list:
		var current: float = float(ns.region_gdp_eur_bn.get(region.id, 0.0))
		var deviation: float = (trend_pct(region) - mean) \
			+ _network_pct(ns, region_list, region, access) \
			+ _sited_pct(ns, region_list, region.id, sites)
		var value: float = current * C.monthly_factor(growth + deviation)
		ns.region_gdp_eur_bn[region.id] = value
		sum += value

	# The residual grows at exactly the national rate: it is output nobody located,
	# and inventing a mix for it would be a number no dataset measured.
	var residual: float = float(ns.region_gdp_eur_bn.get(K.RESIDUAL_KEY, 0.0)) * C.monthly_factor(growth)
	ns.region_gdp_eur_bn[K.RESIDUAL_KEY] = residual
	return sum + residual


static func total(ns) -> float:
	var sum: float = 0.0
	for value in ns.region_gdp_eur_bn.values():
		sum += float(value)
	return sum


## A region's live share of national output. Not the authored `gdp_share`: that is
## where it started, and the difference between the two is what this session exists
## to make visible.
static func share_of(ns, region_id: String) -> float:
	# Named `national`, not `total`: a local called `total` shadows total() above.
	var national: float = total(ns)
	if national <= 0.0:
		return 0.0
	return float(ns.region_gdp_eur_bn.get(region_id, 0.0)) / national


## A PURE READ, AND THE REASON SAVE_VERSION BUMPS ON ONE FIELD RATHER THAN TWO.
## src/sim/credit.gd's stateless shape: nothing here accumulates, nothing is written
## on NationState, and Economy._update_unemployment() keeps its single writer. A
## regional stock would be a second answer to the Okun term the macro model already
## owns -- companies.gd's own argument at V1.4a.
##
## `unemployment_rel` is normalised at import so the population-weighted mean over
## the named regions is exactly 1.0, and the deviation term is GDP-weighted zero-mean,
## so this DECOMPOSES the national figure rather than disagreeing with it.
static func unemployment_pct(ns, region_list: Array, region_id: String, access: Dictionary, sites: Dictionary) -> float:
	for region in region_list:
		if region.id == region_id:
			return clampf(
				ns.unemployment_pct * region.unemployment_rel - C.OKUN * trend_deviation_pct(ns, region_list, region_id, access, sites),
				C.UNEMP_MIN_PCT,
				C.UNEMP_MAX_PCT
			)
	return ns.unemployment_pct


## Output per head against the national average: 1.0 is exactly average, and nothing
## authored the spread. The quantity the Region panel leads with, and the one that
## makes two partitions of one nation worth carrying rather than one.
##
## THE POPULATION SHARE IS PASSED IN RATHER THAN READ, and that is what keeps this
## file a leaf after V2.6a made the share live. Reading ns.region_pop_share here
## would give regions.gd a second register to know about and would put
## tests/test_geography.gd's one-reader assertion under pressure for no gain: the
## caller already holds the share, because the caller is the thing that moved it.
static func gdp_per_head_index(ns, region_list: Array, region_id: String, pop_share: float) -> float:
	for region in region_list:
		if region.id == region_id:
			if pop_share <= 0.0:
				return 0.0
			return share_of(ns, region_id) / pop_share
	return 0.0


## A region's authored natural-change rate, per cent per year, signed. V2.6c. A
## pass-through rather than a raw read for the same reason unemployment_rel travels
## behind unemployment_pct(): tests/test_geography.gd's one-reader scan names this
## field, and the only file allowed to spell it is this one -- which is also why the
## accessor is named for the QUANTITY rather than restating the field, share_of()'s
## naming rule. The mean over live shares is NOT taken here -- the flow that moves
## people owns its snapshot, and regions.gd reaching the population register would
## be a second register to know about (gdp_per_head_index's own comment, the rule
## this pass-through exists to keep).
static func natural_change(region) -> float:
	return region.natural_change_pct


## Has any region drifted past the bound? Read by tools/regions_probe.gd and by
## tests/test_regions.gd; nothing in the tick calls it, because a bound that silently
## clamps is a bound nobody measures.
static func worst_share_drift(ns, region_list: Array) -> float:
	var worst: float = 0.0
	for region in region_list:
		worst = maxf(worst, absf(share_of(ns, region.id) - region.gdp_share))
	return worst
