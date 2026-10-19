extends RefCounted

## Monthly economy update: sector output, GDP, potential, growth, unemployment,
## population. Runs for every nation; only the player's carries budget impulses.
##
## No engine access, no node references, no signals, no randomness. Everything
## here is a pure function of the state passed in — which is what lets the budget
## projection run the real model forward on a copy and get the real answer.
##
## The model, and the justification for every constant, is docs/economy-model.md.

const C = preload("res://src/sim/economy_constants.gd")
const Trade = preload("res://src/sim/trade.gd")
const TradeK = preload("res://src/sim/trade_constants.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Investment = preload("res://src/sim/investment.gd")
const Regions = preload("res://src/sim/regions.gd")


static func tick_month(state) -> void:
	# Snapshotted once, from last month's figures, so the result does not depend on
	# the order nations are ticked in. Same reason the single GDP-weighted
	# aggregate this replaced was computed once, and more load-bearing now: the
	# table is ninety directed entries reading every nation's GDP.
	#
	# V5.0c: only the rows the impulse below reads -- the has_budget nations'.
	# Trade.weight_table() built all forty-one and the loop read four; each row
	# is the same Trade.weights() on the same snapshot, so the four are the same
	# floats.
	var table := {}
	for ns in state.nations.values():
		if ns.has_budget:
			table[ns.id] = Trade.weights(state, ns.id)

	# The impulse is resolved for every nation BEFORE any nation ticks, not inside
	# the loop below. Snapshotting the weight table alone is not enough: the
	# impulse also reads each partner's growth_annual_pct, and _tick_nation()
	# overwrites that. Computed in the loop, the player would read this month's
	# growth for every partner sorted before it and last month's for every partner
	# after -- for France, five of nine one way and four the other.
	#
	# Invisible today, because every partner sits at its own baseline forever and
	# both answers are zero. It would have surfaced at V1.3c, as a mystery, in the
	# session that first perturbs a partner. tools/trade_probe.gd's synthetic
	# recession is what caught it.
	# Coercion damage is resolved in the same pre-pass and for the same reason: it
	# reads the target's own weight row, which reads every nation's GDP.
	#
	# Unlike the trade impulse above, this one runs for ALL TEN nations -- it is a
	# different channel, not a lifting of the has_budget guard below. That guard is
	# about whether a nation feels its partners' business cycle; this is about
	# whether a nation feels something done to it on purpose, and the whole point
	# of V1.3c is that the nine can. docs/trade-model.md's deferral of the coupled
	# common mode is untouched: the player's own trend still never feeds back to a
	# partner, so the path stays one hop with no loop.
	var damage := {}
	for ns in state.nations.values():
		# The BEFORE-measures vector, not `table`: damage is done by the trade a
		# measure destroys, not by what survives it. See Coercion.impulse().
		# V5.0c: Coercion.impulse() is exactly 0.0 before it reads the row when no
		# measure targets the nation, so the row is built only when one does.
		if Coercion.against(state, ns.id).is_empty():
			damage[ns.id] = 0.0
		else:
			damage[ns.id] = Coercion.impulse(state, ns, Trade.weights_before_measures(state, ns.id))

	var impulses := {}
	for ns in state.nations.values():
		# Player-only, unchanged from S4. Not a stability concern -- the coupled
		# ten-nation system's common mode is provably stable, and the eigenvalues
		# are in docs/trade-model.md so V1.3c can lift this knowingly. It is that
		# turning it on replaces the 28-month output-gap half-life the whole
		# game's pacing is argued from, which is a model rewrite rather than a
		# wiring change.
		if ns.has_budget:
			impulses[ns.id] = Trade.external_impulse(state, ns, table.get(ns.id, {}))

	for ns in state.nations.values():
		if impulses.has(ns.id):
			ns.external_impulse_pct = float(impulses[ns.id])
		ns.coercion_impulse_pct = float(damage.get(ns.id, 0.0))
		# V1.6a. Written HERE, from a pure read, and src/sim/cycle.gd has no
		# tick_month() to call from anywhere else. That is the session's structural
		# call rather than a convenience: docs/decision-log.md's V1.5d entry records
		# that neither balance harness ever called Media.tick_month(), so both ran the
		# pre-session model and their agreement was about nothing. Every harness in
		# this project already calls Economy.tick_month(), so a system reached from
		# inside it cannot be forgotten by one and remembered by another.
		#
		# Inside the tick loop rather than in a pre-pass above, unlike the trade
		# impulse and the coercion damage: those two read every OTHER nation's
		# figures, so they must be snapshotted before any nation moves. This reads
		# nothing but the clock and the nation's own authored volatility, so tick
		# order cannot reach it.
		ns.cycle_impulse_pct = Cycle.impulse_pct(ns, state.year, state.month)
		_tick_nation(state, ns)


static func _tick_nation(state, ns) -> void:
	_update_potential_shift(state, ns)

	var trend := trend_pct(ns)
	ns.trend_annual_pct = trend

	ns.potential_gdp_eur_bn *= C.monthly_factor(trend)

	var gap := 0.0
	if ns.potential_gdp_eur_bn > 0.0:
		gap = 100.0 * (ns.gdp_eur_bn - ns.potential_gdp_eur_bn) / ns.potential_gdp_eur_bn

	# Six terms since V1.5c. coercion_impulse_pct is sustained rather than decayed
	# -- a measure in force is a standing condition, not a shock -- and carries its
	# own clamp in coercion_constants.gd, because docs/economy-model.md's
	# divergence argument is per-quantity and a new quantity owes it a bound.
	#
	# firm_impulse_pct is sustained for the same reason and carries its own clamp in
	# companies_constants.gd for the same one: a subsidy in force is a standing
	# condition. It reads EXACTLY 0.0 in every month of every game in which no
	# subsidy has ever been paid, which is what lets the whole firm register go live
	# with the balance harness bit-identical across all fourteen existing regimes.
	#
	# unrest_impulse_pct is the first addend on the DECAYING side of that distinction
	# since demand_impulse_pct itself, and it is there because a strike is a shock and
	# not a standing condition -- the same sentence the two above are excluded by, read
	# the other way. Its clamp is unrest_constants.UNREST_IMPULSE_MAX_PCT and the DECAY
	# is applied by Unrest.tick_month() rather than beside demand_impulse_pct below, so
	# the field keeps one writer. It reads exactly 0.0 in every month of every game in
	# which no union has ever acted.
	# cycle_impulse_pct is the seventh addend, V1.6a, and it is on the SUSTAINED side
	# of the distinction above rather than the decaying one: a recession is a
	# condition the economy is in, not a shock it absorbed. It is the only term here
	# that is non-zero without the player or any AI having done anything, which is
	# what docs/tiers/v1.md section 6 means by *arriving whether or not deserved*.
	#
	# It needs no clamp of its own, and that is the one exception to the rule the
	# three comments above state. Coercion, companies and unrest each carry a tuned
	# maximum because each is an unbounded product of live quantities; this is a sum
	# of three sines normalised to unit standard deviation, so it is bounded by
	# construction at cycle_constants.max_impulse_pct() -- a number derived from the
	# term count rather than chosen, and therefore one nobody can set wrong.
	#
	# It moves GDP and never potential_gdp_eur_bn. A business cycle is by definition
	# output around potential, so a term that moved both would be describing
	# something else -- and potential_shift_pct is already the only feedback into
	# trend, which is the whole of docs/economy-model.md's divergence argument.
	# inflation_impulse_pct is the eighth addend, V1.6b, and it is on the SUSTAINED
	# side with the cycle: high prices are a condition the economy is in. It is written
	# by Inflation.tick_month(), which runs AFTER this function, so the figure read here
	# is last month's -- unrest_impulse_pct's existing pattern, and what keeps the
	# feedback loop this term closes from being an intra-month circular dependency.
	#
	# It is the only addend here that is a function of another addend's consequences,
	# so it is the only one that could feed itself. It cannot, and the reason is
	# arithmetic rather than a clamp: the term is one-sided above the anchor, and above
	# the anchor the loop is NEGATIVE feedback -- a negative impulse raises
	# unemployment, which lowers inflation, which shrinks the impulse. The gain is
	# INFLATION_UNEMP_BETA * OKUN / UNEMP_REVERT * INFLATION_OUTPUT_BETA, an order of
	# magnitude below 1.0 at the shipped values. See Inflation.output_cost_pct() for
	# why the lower branch is not modelled and inflation_constants.gd for the bound.
	#
	# Like the cycle it moves GDP and never potential_gdp_eur_bn.
	#
	# V2.8. THE TENTH ADDEND. READ, not computed here: Energy.tick_month() has
	# already written it this month, so economy.gd needs no loader and gains no
	# preload -- the strictest form of V1.6a's answer to V1.5d's forgotten tick,
	# because a harness that skips the energy tick then reads a STALE field
	# rather than silently computing a fresh zero, and a stale field shows up in
	# the re-run where a fresh zero does not. Reads EXACTLY 0.0 for a nation that
	# has built nothing.
	var growth: float = (
		trend + C.GAP_CLOSE * (-gap)
		+ ns.demand_impulse_pct + ns.external_impulse_pct + ns.coercion_impulse_pct
		+ ns.firm_impulse_pct + ns.unrest_impulse_pct + ns.cycle_impulse_pct
		+ ns.inflation_impulse_pct
		+ ns.energy_impulse_pct
	)
	growth = clampf(growth, C.GROWTH_MIN_PCT, C.GROWTH_MAX_PCT)
	ns.growth_annual_pct = growth

	# V2.5. THE MONTH'S GDP TARGET IS THE REGION SUM, not `gdp * monthly_factor(growth)`
	# -- national GDP is defined as the sum of the regions now, and the three sectors
	# reconcile to that number rather than to one they never saw. The swap is one
	# definition: from the MVP to V2.4 the sectors were the authority.
	#
	# A nation with an empty register falls back to the old expression inside
	# Regions.tick_month(), which is what keeps every test fixture loadable -- an
	# absent data/regions/ file is a load ERROR for the ten, and a fixture is not one
	# of the ten.
	# V2.7. The index is a pure read over the graph and the shares as they stand at
	# the top of the tick, and the argument is REQUIRED -- a defaulted one would let
	# a caller forget it and silently run the pre-V2.7 model (V1.5d's own failure).
	var access: Dictionary = Regions.accessibility_for(ns, state.regions.get(ns.id, []), state.region_graph)
	var sites: Dictionary = state.project_sited_pct.get(ns.id, {})
	var target_gdp: float = Regions.tick_month(ns, state.regions.get(ns.id, []), growth, access, sites)
	_apply_growth_to_sectors(state, ns, target_gdp)
	_update_unemployment(ns, trend, growth)

	# V1.5b: per-nation and measured, where this was one flat constant for all ten.
	# Compound rather than linear, because a population does compound -- unlike the
	# age SHARES demography.gd drifts, which cannot.
	ns.population *= C.monthly_factor(ns.pop_growth_pct)

	ns.demand_impulse_pct = clampf(
		ns.demand_impulse_pct * C.IMPULSE_DECAY, -C.IMPULSE_MAX_PCT, C.IMPULSE_MAX_PCT
	)


## Share-weighted sector trend, plus the budget's long-run shift. Ten nations get
## ten different trends out of one constant table, with no per-nation branch.
##
## V1.6e adds the SECOND term ever to reach this function from outside
## potential_shift_pct, and adding it HERE is half of what makes the sector lever a
## lever. _apply_growth_to_sectors() below reconciles the three sectors against the
## month's GDP target exactly, so a per-sector rate added only down there moves the
## MIX and nothing else -- the residual takes the level effect straight back out
## inside the same tick. Added here as well, share-weighted, the two paths agree
## and the level effect survives.
##
## That is also the whole difference between this term and Trade.sector_shift(),
## which is required to sum to zero at load precisely because an agreement must
## move composition and not the nation's own trend. An investment shift must NOT
## sum to zero; if it did, nothing would have been bought.
static func trend_pct(ns) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var trend := 0.0
	for key in C.SECTOR_TREND.keys():
		var share: float = float(ns.sector_output.get(key, 0.0)) / ns.gdp_eur_bn
		trend += share * float(C.SECTOR_TREND[key])
	return trend + ns.potential_shift_pct + Investment.national_trend_shift_pct(ns)


## Trend part by each sector's own rate, cyclical part by cyclical beta. Doing it
## in one step with beta alone would push industry's share *up* over a decade,
## the opposite of the secular trend. The cyclical part is a residual against the
## GDP target, so sector output sums to GDP exactly with no reconciliation.
##
## V2.5: the third parameter is now the TARGET, not the growth rate -- the region
## sum `Regions.tick_month()` returned. Before V2.5 this function computed its own
## target from `gdp * monthly_factor(growth)`; national GDP is the sum of the
## regions now, so the target arrives from there and the sectors reconcile to a
## number they never saw.
static func _apply_growth_to_sectors(state, ns, target_gdp: float) -> void:
	# An agreement's winners and losers, in points of trend per sector. The three
	# shifts sum to zero — checked at load — so this moves the SPLIT between
	# sectors and never the nation's own trend. Inside this loop rather than as a
	# pass after it: the cyclical residual below reconciles sectors to the GDP
	# target exactly, and a shift applied outside would break that identity.
	var trade_shift := Trade.sector_shift(state, ns.id)

	# V1.6e, beside the trade shift because it lands in the same slot, and REQUIRED
	# TO BE READ AT trend_pct() AS WELL -- see that function for why. Reads exactly
	# 0.0 for every sector until an investment programme has run, so `after_trend` is
	# unchanged to the last bit in every game in which nobody has invested.
	var investment_shift := Investment.sector_trend_shift(ns)

	# Trend part: each sector at its own rate, plus the uniform potential shift.
	# Summed, this is exactly the nation's trend, so the two paths agree.
	var after_trend := 0.0
	for key in C.SECTOR_TREND.keys():
		var rate: float = (
			float(C.SECTOR_TREND[key]) + ns.potential_shift_pct
			+ float(trade_shift.get(key, 0.0))
			+ float(investment_shift.get(key, 0.0))
		)
		ns.sector_output[key] = float(ns.sector_output[key]) * C.monthly_factor(rate)
		after_trend += float(ns.sector_output[key])
	if after_trend <= 0.0:
		ns.gdp_eur_bn = target_gdp
		return

	# Cyclical part: the residual needed to reach the month's GDP target, split
	# by cyclical beta.
	var cyclical := target_gdp - after_trend

	var weights := {}
	var weight_sum := 0.0
	for key in C.SECTOR_TREND.keys():
		var share: float = float(ns.sector_output[key]) / after_trend
		var w: float = share * float(C.SECTOR_CYCLE_BETA[key])
		weights[key] = w
		weight_sum += w
	if weight_sum <= 0.0:
		ns.gdp_eur_bn = target_gdp
		return

	var total := 0.0
	for key in C.SECTOR_TREND.keys():
		var v: float = float(ns.sector_output[key]) + cyclical * float(weights[key]) / weight_sum
		v = maxf(v, C.SECTOR_MIN_EUR_BN)
		ns.sector_output[key] = v
		total += v

	# GDP IS THE REGION SUM, not the sector sum, and that is the definitional swap
	# V2.5 makes. The sectors still reconcile to it exactly -- the cyclical residual
	# is distributed by weights that sum to 1.0 -- so `total` and `target_gdp` differ
	# only by float noise, and taking the target keeps the region partition closing to
	# the last bit rather than to a tolerance. The sector sum's own agreement with GDP
	# is now a 1e-9 relative claim rather than an exact one, and
	# tests/test_regions.gd asserts it at that precision and says why here.
	ns.gdp_eur_bn = target_gdp


static func _update_unemployment(ns, trend: float, growth: float) -> void:
	ns.structural_unemployment_pct = clampf(
		ns.start_unemployment_pct
			+ C.STRUCT_INCOME_BETA * (
				float(ns.tax_rates_pct.get("income", 0.0))
				- float(ns.start_tax_rates_pct.get("income", 0.0))
			)
			+ ns.law_structural_offset_pct
			# V1.4a, beside the law offset because it is the same shape: a signed
			# adjustment to where unemployment is heading, not a claim about this
			# month's cycle. It is REALLOCATION and nothing else -- two firms of equal
			# share employ different numbers of people, so moving share between them
			# changes total jobs, and a firm hiring because the whole economy grew
			# would be a second answer to the Okun term below. Exactly 0.0 while every
			# firm sits at its authored share. See src/sim/companies.gd.
			+ ns.firm_jobs_offset_pct,
		C.STRUCT_MIN_PCT,
		C.STRUCT_MAX_PCT
	)

	var du: float = (
		-C.OKUN * (growth - trend)
		+ C.UNEMP_REVERT * (ns.structural_unemployment_pct - ns.unemployment_pct)
	) / 12.0

	ns.unemployment_pct = clampf(ns.unemployment_pct + du, C.UNEMP_MIN_PCT, C.UNEMP_MAX_PCT)


## First-order lag toward the shift implied by current infrastructure, education
## and corporate tax. Clamped hard, because this term feeds back into trend growth.
##
## IT WAS THE ONLY SUCH TERM UNTIL V1.6e, and that clause is amended here rather
## than left to quietly become false. Investment.sector_trend_shift() now reaches
## trend as well, through trend_pct() above, and it carries its own per-quantity
## bound (investment_constants.SECTOR_TREND_MAX_PCT) exactly as
## docs/economy-model.md's divergence argument requires of a new quantity. The two
## are not one channel measured twice: this one reads a player-set SPENDING LINE and
## produces a UNIFORM shift, that one reads a register written by a verb and
## produces a PER-SECTOR one.
static func _update_potential_shift(state, ns) -> void:
	var d_infra: float = (
		float(ns.spending_pct_gdp.get("infrastructure", 0.0))
		- float(ns.start_spending_pct_gdp.get("infrastructure", 0.0))
	)
	var d_edu: float = (
		float(ns.spending_pct_gdp.get("education", 0.0))
		- float(ns.start_spending_pct_gdp.get("education", 0.0))
	)
	var d_corp: float = (
		float(ns.tax_rates_pct.get("corporate", 0.0))
		- float(ns.start_tax_rates_pct.get("corporate", 0.0))
	)

	# The fourth writer, added at V1.3b. Trade openness is a trend effect, not a
	# demand one, so this is the right channel — and sharing SHIFT_MAX_PCT with
	# infrastructure is the point rather than a compromise: openness and public
	# investment compete for the same ±1.0 budget. The index is exactly 1.0 with no
	# agreement signed, so this term is exactly zero for every regime in the balance
	# harness, and it is bounded by MAX_AGREEMENT_WEIGHT_MULTIPLIER at load, before
	# the clamp below ever sees it. See docs/trade-model.md.
	var d_open: float = Trade.openness_index(state, ns.id) - 1.0

	var target: float = (
		C.INFRA_BETA * d_infra + C.EDU_BETA * d_edu - C.CORP_TAX_BETA * d_corp
		+ TradeK.TRADE_OPENNESS_BETA * d_open
		+ ns.law_potential_target_pct
		# The SIXTH writer, added at V1.6f, and beside law_potential_target_pct rather
		# than anywhere else because it is that field's shape exactly: a one-time act
		# producing a permanent addend, bounded on its own accumulator by
		# projects_constants.PROJECT_POTENTIAL_MAX_PCT the way a law is bounded by
		# legislature_constants.POTENTIAL_TARGET_MAX_PCT.
		#
		# THIS IS WHY V1.6f ADDS NO THIRD QUANTITY REACHING TREND. V1.6e's shift had to
		# carry its own bound because it reaches trend_pct() directly; this reaches the
		# TARGET of the lag below, which SHIFT_MAX_PCT already bounds, so the comment on
		# that constant stays true as V1.6e amended it. Reads exactly 0.0 until a
		# project has been COMPLETED -- not merely started -- which is what keeps the
		# balance harness bit-identical with this whole layer live.
		+ ns.project_potential_target_pct
	)

	ns.potential_shift_pct += (target - ns.potential_shift_pct) * C.SHIFT_ADJUST / 12.0
	ns.potential_shift_pct = clampf(ns.potential_shift_pct, -C.SHIFT_MAX_PCT, C.SHIFT_MAX_PCT)


## `neighbour_weighted_growth()` lived here from S4 to V1.3a: one GDP-weighted
## average of the nine nations the player does not govern, the same number for
## every viewer. V1.3b replaced it with src/sim/trade.gd's directed weight table,
## which is per-viewer and reads relations and agreements as well as size. Retired
## rather than kept alongside — two answers to "how much does B matter to A" is the
## divergence the pair key was made symmetric to avoid.


static func output_gap_pct(ns) -> float:
	if ns.potential_gdp_eur_bn <= 0.0:
		return 0.0
	return 100.0 * (ns.gdp_eur_bn - ns.potential_gdp_eur_bn) / ns.potential_gdp_eur_bn
