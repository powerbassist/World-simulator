extends RefCounted

## Monthly budget update: revenue, spending, deficit, accumulated debt. Plus the
## two commands the UI sends — commit() and project().
##
## project() runs the *same* Economy.tick_month + Budget.tick_month pair that the
## real game runs, on a deep copy of the state. That is what makes the projected
## path identical to what subsequently happens, rather than merely close: there
## is only one model, and both callers use it.
##
## The model, and the justification for every constant, is docs/economy-model.md.

const C = preload("res://src/sim/economy_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Trade = preload("res://src/sim/trade.gd")
const Coercion = preload("res://src/sim/coercion.gd")
const Bloc = preload("res://src/sim/bloc.gd")


static func tick_month(state) -> void:
	var ns = state.player()
	if ns == null:
		return
	recompute(state, ns)
	ns.debt_eur_bn += ns.deficit_pct_gdp / 100.0 * ns.gdp_eur_bn / 12.0


## Revenue, spending, debt service and deficit from the nation's current rates,
## allocations, debt and GDP. Pure bookkeeping — no state advances here.
##
## `state` is V1.3c's, for the tariff line below, and it is passed rather than the
## line being cached on NationState by the economy pre-pass: the budget panel is
## the surface that promises "this is what will happen", and a tariff imposed this
## month whose revenue only appeared next month would be a lie on exactly that
## surface. Three call sites, all of which already had the state in hand.
static func recompute(state, ns) -> void:
	ns.revenue_pct_gdp = revenue_lines(ns.tax_rates_pct, ns.start_tax_rates_pct)
	ns.revenue_pct_gdp["other"] = ns.other_revenue_pct_gdp + ns.law_other_revenue_pct_gdp
	ns.revenue_pct_gdp["tariffs"] = _tariff_revenue(state, ns)

	var revenue := 0.0
	for v in ns.revenue_pct_gdp.values():
		revenue += float(v)
	ns.total_revenue_pct_gdp = revenue

	ns.debt_service_pct_gdp = 0.0
	if ns.gdp_eur_bn > 0.0:
		ns.debt_service_pct_gdp = C.DEBT_REAL_RATE_PCT * ns.debt_eur_bn / ns.gdp_eur_bn

	# V1.3d's line. SIGNED and on the spending side, not a sixth SPENDING_KEYS
	# entry: docs/tiers/v1.md section 6 keys the five player-set spending lines 1:1
	# to cabinet portfolios, so a sixth line would be a sixth minister -- and the
	# player does not set this one with a slider. Same call docs/coercion-model.md
	# made for the tariff revenue line, in the other direction.
	#
	# Read straight off NationState rather than recomputed here, because unlike the
	# tariff line this one must NOT respond within the month: Bloc.tick_month() runs
	# after this and charges next month's penalties, which is what stops a rule on
	# the deficit from feeding a fine that widens the deficit. See src/sim/bloc.gd.
	ns.total_spending_pct_gdp = (
		ns.player_spending_pct_gdp()
		+ ns.other_spending_pct_gdp
		+ ns.debt_service_pct_gdp
		+ ns.bloc_transfer_pct_gdp
	)
	ns.deficit_pct_gdp = ns.total_spending_pct_gdp - ns.total_revenue_pct_gdp


## Yield of each modelled tax as a percent of GDP. With the rate in percent and
## the base as a share of GDP, the product is already a percent of GDP.
##
## `ref_rates` is the reference the erosion curve centres on -- always the
## nation's own starting rates, `ns.start_tax_rates_pct`, the same "delta
## against the nation's own start" shape every other satisfaction term in this
## model already uses. Passed explicitly rather than read off a shared
## constant since V1.2a made starting rates per-nation: a table shared by all
## ten would put every nation but one off its own reference.
static func revenue_lines(rates: Dictionary, ref_rates: Dictionary) -> Dictionary:
	var out := {}
	for key in C.TAX_KEYS:
		var rate := float(rates.get(key, 0.0))
		out[key] = float(C.TAX_BASE_SHARE[key]) * rate * _erosion(key, rate, ref_rates)
	return out


## Tariff revenue as a percent of GDP — a revenue line of its own, not a fourth
## entry in TAX_KEYS.
##
## TAX_KEYS stays at three. docs/tiers/v1.md section 6's five-tax target does not
## include tariffs, and a tariff is not the shape the other three are: there is no
## slider, no base share, no erosion curve, and the rate is per-partner rather than
## national. Folding it into `other` instead was the alternative and is worse — a
## revenue source the player cannot see on the panel is the decorative-axis failure
## docs/scenario-model.md records, with a different label.
##
## Short-circuits before building a weight row when nothing is imposed, which is
## every nation in every balance-harness regime. Exactly 0.0 then, by construction
## rather than by rounding, which is half of what keeps the re-run bit-identical.
static func _tariff_revenue(state, ns) -> float:
	if state == null or Coercion.imposed_by(state, ns.id).is_empty():
		return 0.0
	return Coercion.tariff_revenue_pct_gdp(state, ns.id, Trade.weights(state, ns.id))


static func modelled_revenue_total(rates: Dictionary, ref_rates: Dictionary) -> float:
	var total := 0.0
	for v in revenue_lines(rates, ref_rates).values():
		total += float(v)
	return total


## Diminishing returns. Steeper where the base is more mobile — corporate profits
## move, consumption does not. Clamped so a rate of zero or of 100 still produces
## a finite, correctly signed number.
static func _erosion(key: String, rate_pct: float, ref_rates: Dictionary) -> float:
	var ref := float(ref_rates.get(key, 0.0))
	if ref <= 0.0:
		return 1.0
	var raw: float = 1.0 - float(C.TAX_EROSION[key]) * (rate_pct - ref) / ref
	return clampf(raw, C.EROSION_MIN, C.EROSION_MAX)


## Apply a pending budget. `pending` is {"tax_rates_pct": {...},
## "spending_pct_gdp": {...}}; either key may be omitted to leave it unchanged.
##
## The demand impulse is raised here and nowhere else: a budget *change* is a
## shock, a budget left alone is not. The revenue delta is computed by running
## revenue_lines() at the old and new rates, so the erosion curve is respected
## automatically and the two can never drift apart.
static func commit(state, pending: Dictionary) -> void:
	var ns = state.player()
	if ns == null:
		return

	var new_rates: Dictionary = ns.tax_rates_pct.duplicate(true)
	if pending.has("tax_rates_pct"):
		for key in C.TAX_KEYS:
			if pending["tax_rates_pct"].has(key):
				new_rates[key] = float(pending["tax_rates_pct"][key])

	var new_spending: Dictionary = ns.spending_pct_gdp.duplicate(true)
	if pending.has("spending_pct_gdp"):
		for key in C.SPENDING_KEYS:
			if pending["spending_pct_gdp"].has(key):
				new_spending[key] = float(pending["spending_pct_gdp"][key])

	var old_revenue := revenue_lines(ns.tax_rates_pct, ns.start_tax_rates_pct)
	var new_revenue := revenue_lines(new_rates, ns.start_tax_rates_pct)

	var old_spend: float = ns.player_spending_pct_gdp()
	var new_spend := 0.0
	for key in C.SPENDING_KEYS:
		new_spend += float(new_spending.get(key, 0.0))

	var level_effect: float = (new_spend - old_spend) * C.MULT_SPENDING
	for key in C.TAX_KEYS:
		level_effect -= (float(new_revenue[key]) - float(old_revenue[key])) * float(C.MULT_TAX[key])

	ns.demand_impulse_pct = clampf(
		ns.demand_impulse_pct + level_effect / C.impulse_level_factor(),
		-C.IMPULSE_MAX_PCT,
		C.IMPULSE_MAX_PCT
	)

	ns.tax_rates_pct = new_rates
	ns.spending_pct_gdp = new_spending
	recompute(state, ns)


## What the books look like the instant `pending` is committed, before any time
## passes. The budget screen's "now vs proposed" column.
static func preview(state, pending: Dictionary) -> Dictionary:
	var sim = state.duplicate_state()
	commit(sim, pending)
	return snapshot(sim)


## Run `months` of the real simulation on a copy, with `pending` applied first.
## Returns one snapshot per month. Pass an empty Dictionary to project the
## current budget unchanged, which is what the UI compares against.
##
## `loader` is required rather than defaulted, and V1.3b is why. Until then this
## ran Economy + Budget and nothing else, because nothing else could reach a figure
## the projection reports. Relations now do: they set the trade weight, the trade
## weight sets the external impulse, and Diplomacy.tick_month() is what drifts them
## back toward resting. Without this call the projection holds relations frozen
## while the real game drifts them, and the two disagree -- measured at about 2e-9
## relative from a displaced state, small but real, and this panel is the one
## surface in the game that promises "this is what will happen".
##
## A defaulted null would have made that divergence opt-in and silent at every call
## site that forgot. tests/test_budget.gd runs the check from a diplomatically
## displaced state precisely because the undisplaced one cannot see it.
static func project(state, pending: Dictionary, months: int, loader) -> Array[Dictionary]:
	var sim = state.duplicate_state()
	commit(sim, pending)

	var out: Array[Dictionary] = []
	for _i in range(months):
		Economy.tick_month(sim)
		tick_month(sim)
		# In the same position main.gd runs it -- after Budget, before the snapshot
		# -- and required for exactly the reason Diplomacy is. The council advances,
		# a defied rule keeps charging, and a projection that held the bloc frozen
		# would under-report the deficit of a player in breach. V1.3b's repair, made
		# once rather than rediscovered.
		Bloc.tick_month(sim, loader)
		Diplomacy.tick_month(sim, loader)
		out.append(snapshot(sim))
	return out


## The player nation's figures, flat and plain. Deliberately dateless — the date
## is stamped on by GameState.append_history(), so a projection and a real month
## produce byte-identical dictionaries and the equality test means something.
static func snapshot(state) -> Dictionary:
	var ns = state.player()
	if ns == null:
		return {}
	return {
		"gdp_eur_bn": ns.gdp_eur_bn,
		"potential_gdp_eur_bn": ns.potential_gdp_eur_bn,
		"output_gap_pct": Economy.output_gap_pct(ns),
		"trend_annual_pct": ns.trend_annual_pct,
		"growth_annual_pct": ns.growth_annual_pct,
		"unemployment_pct": ns.unemployment_pct,
		"structural_unemployment_pct": ns.structural_unemployment_pct,
		"population": ns.population,
		"debt_eur_bn": ns.debt_eur_bn,
		"debt_to_gdp_pct": ns.debt_to_gdp_pct(),
		"total_revenue_pct_gdp": ns.total_revenue_pct_gdp,
		"tariff_revenue_pct_gdp": float(ns.revenue_pct_gdp.get("tariffs", 0.0)),
		"total_spending_pct_gdp": ns.total_spending_pct_gdp,
		"debt_service_pct_gdp": ns.debt_service_pct_gdp,
		"bloc_transfer_pct_gdp": ns.bloc_transfer_pct_gdp,
		"bloc_burden": ns.bloc_burden,
		"deficit_pct_gdp": ns.deficit_pct_gdp,
		"demand_impulse_pct": ns.demand_impulse_pct,
		"potential_shift_pct": ns.potential_shift_pct,
		"sectors": ns.sector_output.duplicate(true),
	}
