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


static func tick_month(state) -> void:
	# Computed once, from last month's figures, so the result does not depend on
	# the order nations are ticked in.
	var neighbour_growth := neighbour_weighted_growth(state)

	for ns in state.nations.values():
		if ns.has_budget:
			ns.external_impulse_pct = C.TRADE_BETA * (neighbour_growth - ns.trade_baseline_pct)
		_tick_nation(ns)


static func _tick_nation(ns) -> void:
	_update_potential_shift(ns)

	var trend := trend_pct(ns)
	ns.trend_annual_pct = trend

	ns.potential_gdp_eur_bn *= C.monthly_factor(trend)

	var gap := 0.0
	if ns.potential_gdp_eur_bn > 0.0:
		gap = 100.0 * (ns.gdp_eur_bn - ns.potential_gdp_eur_bn) / ns.potential_gdp_eur_bn

	var growth: float = trend + C.GAP_CLOSE * (-gap) + ns.demand_impulse_pct + ns.external_impulse_pct
	growth = clampf(growth, C.GROWTH_MIN_PCT, C.GROWTH_MAX_PCT)
	ns.growth_annual_pct = growth

	_apply_growth_to_sectors(ns, growth)
	_update_unemployment(ns, trend, growth)

	ns.population *= C.monthly_factor(C.POP_GROWTH_PCT)

	ns.demand_impulse_pct = clampf(
		ns.demand_impulse_pct * C.IMPULSE_DECAY, -C.IMPULSE_MAX_PCT, C.IMPULSE_MAX_PCT
	)


## Share-weighted sector trend, plus the budget's long-run shift. Ten nations get
## ten different trends out of one constant table, with no per-nation branch.
static func trend_pct(ns) -> float:
	if ns.gdp_eur_bn <= 0.0:
		return 0.0
	var trend := 0.0
	for key in C.SECTOR_TREND.keys():
		var share: float = float(ns.sector_output.get(key, 0.0)) / ns.gdp_eur_bn
		trend += share * float(C.SECTOR_TREND[key])
	return trend + ns.potential_shift_pct


## Trend part by each sector's own rate, cyclical part by cyclical beta. Doing it
## in one step with beta alone would push industry's share *up* over a decade,
## the opposite of the secular trend. The cyclical part is a residual against the
## GDP target, so sector output sums to GDP exactly with no reconciliation.
static func _apply_growth_to_sectors(ns, growth: float) -> void:
	var target_gdp: float = ns.gdp_eur_bn * C.monthly_factor(growth)

	# Trend part: each sector at its own rate, plus the uniform potential shift.
	# Summed, this is exactly the nation's trend, so the two paths agree.
	var after_trend := 0.0
	for key in C.SECTOR_TREND.keys():
		var rate: float = float(C.SECTOR_TREND[key]) + ns.potential_shift_pct
		ns.sector_output[key] = float(ns.sector_output[key]) * C.monthly_factor(rate)
		after_trend += float(ns.sector_output[key])
	if after_trend <= 0.0:
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
		ns.gdp_eur_bn = after_trend
		return

	var total := 0.0
	for key in C.SECTOR_TREND.keys():
		var v: float = float(ns.sector_output[key]) + cyclical * float(weights[key]) / weight_sum
		v = maxf(v, C.SECTOR_MIN_EUR_BN)
		ns.sector_output[key] = v
		total += v

	ns.gdp_eur_bn = total


static func _update_unemployment(ns, trend: float, growth: float) -> void:
	ns.structural_unemployment_pct = clampf(
		ns.start_unemployment_pct
			+ C.STRUCT_INCOME_BETA * (
				float(ns.tax_rates_pct.get("income", 0.0))
				- float(ns.start_tax_rates_pct.get("income", 0.0))
			),
		C.STRUCT_MIN_PCT,
		C.STRUCT_MAX_PCT
	)

	var du: float = (
		-C.OKUN * (growth - trend)
		+ C.UNEMP_REVERT * (ns.structural_unemployment_pct - ns.unemployment_pct)
	) / 12.0

	ns.unemployment_pct = clampf(ns.unemployment_pct + du, C.UNEMP_MIN_PCT, C.UNEMP_MAX_PCT)


## First-order lag toward the shift implied by current infrastructure, education
## and corporate tax. Clamped hard: this is the only term that feeds back into
## trend growth, so it is the only one that could compound.
static func _update_potential_shift(ns) -> void:
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

	var target: float = C.INFRA_BETA * d_infra + C.EDU_BETA * d_edu - C.CORP_TAX_BETA * d_corp

	ns.potential_shift_pct += (target - ns.potential_shift_pct) * C.SHIFT_ADJUST / 12.0
	ns.potential_shift_pct = clampf(ns.potential_shift_pct, -C.SHIFT_MAX_PCT, C.SHIFT_MAX_PCT)


## GDP-weighted growth of every nation the player does not govern. Real and
## computed — their trends differ because their sector mixes differ — but quiet,
## because nothing in the MVP perturbs a neighbour. See docs/economy-model.md.
static func neighbour_weighted_growth(state) -> float:
	var weighted := 0.0
	var total_gdp := 0.0
	for ns in state.nations.values():
		if ns.id == state.player_nation_id:
			continue
		weighted += ns.growth_annual_pct * ns.gdp_eur_bn
		total_gdp += ns.gdp_eur_bn
	if total_gdp <= 0.0:
		return 0.0
	return weighted / total_gdp


static func output_gap_pct(ns) -> float:
	if ns.potential_gdp_eur_bn <= 0.0:
		return 0.0
	return 100.0 * (ns.gdp_eur_bn - ns.potential_gdp_eur_bn) / ns.potential_gdp_eur_bn
