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
## up and enforced by subtraction rather than by a load-time check.
static func trend_deviation_pct(ns, region_list: Array, region_id: String) -> float:
	if region_id == K.RESIDUAL_KEY:
		return 0.0
	for region in region_list:
		if region.id == region_id:
			return trend_pct(region) - _mean_trend_pct(ns, region_list)
	return 0.0


## Grow every region and return the month's national GDP -- which IS the sum.
## Economy._tick_nation() takes the return value as its target.
##
## The deviation is applied to the region's own growth rate rather than to its level,
## so a region that grows faster compounds, which is what makes divergence a
## trajectory rather than a one-off tilt. SHARE_DRIFT_MAX is checked here rather than
## clamped on the rate, because the quantity the bound is about is the SHARE.
static func tick_month(ns, region_list: Array, growth: float) -> float:
	if ns.region_gdp_eur_bn.is_empty():
		return ns.gdp_eur_bn * C.monthly_factor(growth)

	var mean: float = _mean_trend_pct(ns, region_list)
	var sum: float = 0.0

	for region in region_list:
		var current: float = float(ns.region_gdp_eur_bn.get(region.id, 0.0))
		var deviation: float = trend_pct(region) - mean
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
static func unemployment_pct(ns, region_list: Array, region_id: String) -> float:
	for region in region_list:
		if region.id == region_id:
			var deviation: float = trend_pct(region) - _mean_trend_pct(ns, region_list)
			return clampf(
				ns.unemployment_pct * region.unemployment_rel - C.OKUN * deviation,
				C.UNEMP_MIN_PCT,
				C.UNEMP_MAX_PCT
			)
	return ns.unemployment_pct


## Output per head against the national average: 1.0 is exactly average, and nothing
## authored the spread. The quantity the Region panel leads with, and the one that
## makes two partitions of one nation worth carrying rather than one.
static func gdp_per_head_index(ns, region_list: Array, region_id: String) -> float:
	for region in region_list:
		if region.id == region_id:
			if region.share <= 0.0:
				return 0.0
			return share_of(ns, region_id) / region.share
	return 0.0


## Has any region drifted past the bound? Read by tools/regions_probe.gd and by
## tests/test_regions.gd; nothing in the tick calls it, because a bound that silently
## clamps is a bound nobody measures.
static func worst_share_drift(ns, region_list: Array) -> float:
	var worst: float = 0.0
	for region in region_list:
		worst = maxf(worst, absf(share_of(ns, region.id) - region.gdp_share))
	return worst
