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
## branch, which is AGENTS.md's first rule one level down.
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
## zero-mean three times over: sector mix, network, and sited-project payoffs (and
## since V5.3 a the player's regional terms). One region of deviation_by_region().
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
	return float(deviation_by_region(ns, region_list, access, sites).get(region_id, 0.0))


## V5.3 a: the player's regional terms, region id -> points a year: the OPEN rows of
## `ns.region_funds` (src/sim/region_funds.gd writes them), then the sector
## priorities of `ns.sector_priorities` in sector order (src/sim/sectors.gd writes
## them, #267). This file only reads the registers, as it reads the sited-project
## map. Each row's term was fixed when the player acted, so the strip's figure is the
## booked one. They enter deviation_by_region() as the sited term does, zero-mean
## over the nation's output shares, for the sited term's reason: a fund's national
## level is its SPENDING (a Budget line whose change moves demand), a priority's is
## none (it moves money between regions, never a line's total), and a term that also
## moved the national total would count the money twice or invent it.
static func _player_terms(ns) -> Dictionary:
	var out := {}
	for row in ns.region_funds:
		if String(row["status"]) == "open":
			var id := String(row["region_id"])
			out[id] = float(out.get(id, 0.0)) + float(row["pts"])
	if not ns.sector_priorities.is_empty():
		var sectors: Array = ns.sector_priorities.keys()
		sectors.sort()
		for sector in sectors:
			var row: Dictionary = ns.sector_priorities[sector]
			var id := String(row["region_id"])
			# The convergence factor (Sectors.tick_month(), the parent's TAKE on #267).
			out[id] = float(out.get(id, 0.0)) + float(row["pts"]) * float(row.get("factor", 1.0))
	return out


## THE ONE DEVIATION (V5.3 a, #267): every named region's growth deviation from its
## nation's, region id -> points a year. The tick grows each region by it,
## trend_deviation_pct() reads one region of it and unemployment_by_region() turns it
## into unemployment through Okun: three readers of one sum. There were three copies,
## whose sums ran in different orders, so a term added to one could be missed by
## another; tests/test_regions.gd pins the tick to the read. The sum is
## `mix + net + sited`, then `+ the player's terms` when any is open, in that order.
##
## EVERYTHING THAT DOES NOT VARY BY REGION IS COMPUTED ONCE, before any region's
## figure (V5.0c's lever: asked region by region it was cubic in the region count):
## the GDP-weighted mean trend, the national production mix, and each term's
## output-weighted mean over shares_of()'s one national total. Every read comes from
## one snapshot, which is also why the tick calls this before its loop rewrites the
## levels (the V2.8 review's finding: a mean rebuilt mid-loop drifts region by region
## and breaks the zero-mean sum).
##
## After the mix, each term is (own - the nation's output-weighted mean of it), so it
## cannot move the national total:
##   net    a region's POSITION, NETWORK_BETA x specialisation x ln(accessibility).
##          THE PRODUCT IS THE MODEL: `specialisation` says how much a region needs a
##          market it does not contain and `ln(accessibility)` how much market it can
##          reach; either alone is half an argument. A region making exactly what its
##          country makes reads 0.0 whatever its accessibility, and one at exactly the
##          mean accessibility reads 0.0 whatever it makes -- two structural zeros,
##          neither a clamp. The mix is `sector_mix`: the six-branch production mix was
##          REFUSED at clause (d) (rho 0.9170 against 0.90 -- one quantity written
##          twice), and the refusal is recorded beside the field it would have extended.
##   sited  what a FINISHED project is worth here (V2.7). The map arrives raw ({region
##          id -> points/year}, Projects.sited_map()); the subtraction happens HERE,
##          because zero-mean is a property of the readers it protects and not of the
##          content. A region hosting nothing reads exactly `-mean`, never 0.0: the
##          model, not a leak. V1.6f's national channel still carries the level through
##          project_potential_target_pct -- one act, priced once.
##   player the player's regional terms (_player_terms(): the open funds and the
##          sector priorities), only when one is set, so a nation with none computes
##          exactly the floats it computed before either existed.
static func deviation_by_region(ns, region_list: Array, access: Dictionary, sites: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if region_list.is_empty():
		return out
	var mean_trend: float = _mean_trend_pct(ns, region_list)
	var shares: Dictionary = shares_of(ns, region_list)
	var total: float = 0.0
	for other in region_list:
		total += float(shares[other.id])
	var net_on: bool = NK.NETWORK_BETA != 0.0 and total > 0.0
	var own_net: Dictionary = {}
	var mean_net: float = 0.0
	if net_on:
		var national: Dictionary = _national_production_mix(ns, region_list)
		var weighted: float = 0.0
		for other in region_list:
			var spec: float = Net.specialisation(other.sector_mix, national)
			var lg: float = log(maxf(float(access.get(other.id, 1.0)), 0.0001))
			own_net[other.id] = spec * lg
			weighted += float(shares[other.id]) * spec * lg
		mean_net = weighted / total
	var bought: Dictionary = _player_terms(ns)
	var mean_site: float = _weighted_mean(sites, shares, region_list, total)
	var mean_bought: float = _weighted_mean(bought, shares, region_list, total)
	for region in region_list:
		if region.id == K.RESIDUAL_KEY:
			continue
		var mix: float = trend_pct(region) - mean_trend
		var net: float = 0.0
		if net_on:
			net = NK.NETWORK_BETA * (float(own_net[region.id]) - mean_net)
		var sited: float = 0.0
		if not sites.is_empty() and total > 0.0:
			sited = float(sites.get(region.id, 0.0)) - mean_site
		var deviation: float = mix + net + sited
		if not bought.is_empty() and total > 0.0:
			deviation += float(bought.get(region.id, 0.0)) - mean_bought
		out[region.id] = deviation
	return out


## A raw region map's output-weighted mean over the nation's own total; 0.0 for an
## empty map or no output.
static func _weighted_mean(map: Dictionary, shares: Dictionary, region_list: Array, total: float) -> float:
	if map.is_empty() or total <= 0.0:
		return 0.0
	var weighted: float = 0.0
	for other in region_list:
		weighted += float(shares[other.id]) * float(map.get(other.id, 0.0))
	return weighted / total


## The accessibility index for one nation, from its live output shares -- the
## weights-building expression every caller of trend_deviation_pct() would otherwise
## repeat, and the one place that decides what a region weighs. network.gd never
## learns that a NationState exists (its own rule); this file never learns where the
## graph came from -- the caller passes it, `state.region_graph` today.
static func accessibility_for(ns, region_list: Array, graph: Dictionary) -> Dictionary:
	return Net.accessibility(graph, shares_of(ns, region_list))


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
	var shares: Dictionary = shares_of(ns, region_list)
	for region in region_list:
		var w: float = float(shares[region.id])
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
## trajectory rather than a one-off tilt. SHARE_DRIFT_MAX is NOT read here and never
## was: worst_share_drift() below is its only reader, and its own docstring gives the
## reason -- a bound that silently clamps is a bound nobody measures. This paragraph
## claimed the opposite until the V2.8 review, which is the wrong thing to believe
## when deciding whether a rate can be raised.
static func tick_month(ns, region_list: Array, growth: float, access: Dictionary, sites: Dictionary) -> float:
	if ns.region_gdp_eur_bn.is_empty():
		return ns.gdp_eur_bn * C.monthly_factor(growth)

	# EVERY DEVIATION IS TAKEN ONCE, BEFORE THE LOOP MUTATES ANY LEVEL, by the one
	# function every reader calls (deviation_by_region()). Until the V2.8 review the
	# means were rebuilt inside the loop from share_of(), which reads total(ns) over the
	# very dictionary this loop rewrites one entry at a time: at iteration k the first
	# k regions carried this month's levels and the rest last month's, every region
	# subtracted a DIFFERENT mean, the zero-mean sum stopped holding exactly, and the
	# result depended on region_list's order -- the property Siting.site(),
	# Network.adjacency(), Projects._advance() and Migration._tick_nation() all sort to
	# protect. This is also the projection's hot path: Budget.project() walks it for
	# 24 months, twice per budget-panel refresh.
	var deviations: Dictionary = deviation_by_region(ns, region_list, access, sites)

	var sum: float = 0.0

	for region in region_list:
		var current: float = float(ns.region_gdp_eur_bn.get(region.id, 0.0))
		var deviation: float = float(deviations.get(region.id, 0.0))
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


## share_of() for every region in the list, the national total summed ONCE --
## V5.0c: share_of() re-sums every region's GDP on each call, and the passes
## that ask it per region (accessibility, the deviation terms, the production
## mix) were quadratic in the region count for one division each. Same total,
## same division, so each entry is the float share_of() returns.
static func shares_of(ns, region_list: Array) -> Dictionary:
	var out: Dictionary = {}
	var national: float = total(ns)
	for region in region_list:
		out[region.id] = 0.0 if national <= 0.0 else float(ns.region_gdp_eur_bn.get(region.id, 0.0)) / national
	return out


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


## unemployment_pct() for every region of a nation in one pass -- V5.0c's tick
## lever, because Migration and Unrest ask it for every region of every nation. The
## deviations come from deviation_by_region() in one call, so each region's figure
## is the same float unemployment_pct() returns (tests/test_regions.gd pins the two
## equal).
static func unemployment_by_region(ns, region_list: Array, access: Dictionary, sites: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	if region_list.is_empty():
		return out
	var deviations: Dictionary = deviation_by_region(ns, region_list, access, sites)
	for region in region_list:
		if out.has(region.id):
			continue
		out[region.id] = clampf(
			ns.unemployment_pct * region.unemployment_rel - C.OKUN * float(deviations.get(region.id, 0.0)),
			C.UNEMP_MIN_PCT,
			C.UNEMP_MAX_PCT
		)
	return out


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


## A region's output, bn EUR a year. V5.3 a, for the development fund
## (src/sim/region_funds.gd), which sizes its term against it: an accessor named for
## the quantity, so the register keeps exactly one reader (tests/test_geography.gd).
static func output_eur_bn(ns, region_id: String) -> float:
	return float(ns.region_gdp_eur_bn.get(region_id, 0.0))


## The opened region's ONE problem (V5.3 a, docs/design/v5.3-ab.md 3.3): its worst
## figure against the nation, as {kind, value, nation, ratio}. Two candidates, each
## as a ratio where above 1 is worse than the nation: unemployment / the nation's,
## and the nation's output per head / the region's (1 / gdp_per_head_index). The
## larger one is the problem, ties to unemployment. A region better than the nation on
## both still names its worse figure, with a ratio under 1 -- the line says so rather
## than inventing a problem. Britain's regions carry the ONS's unemployment and
## output since V5.3 (docs/data-sources.md), so London's problem is its unemployment
## above the nation's and the North East's its output below it, as for any nation.
static func problem(ns, region_list: Array, region_id: String, access: Dictionary, sites: Dictionary, pop_share: float) -> Dictionary:
	return problem_of(ns, unemployment_pct(ns, region_list, region_id, access, sites),
		gdp_per_head_index(ns, region_list, region_id, pop_share))


## problem() with the two figures already read: a caller walking every region takes
## unemployment_by_region() once rather than the nation's sum per region.
static func problem_of(ns, u: float, index: float) -> Dictionary:
	var nation := float(ns.unemployment_pct)
	var u_ratio := u / nation if nation > 0.0 else 0.0
	var g_ratio := 1.0 / index if index > 0.0 else 0.0
	if u_ratio >= g_ratio:
		return {"kind": "unemployment", "value": u, "nation": nation, "ratio": u_ratio}
	return {"kind": "output_per_head", "value": index, "nation": 1.0, "ratio": g_ratio}


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
