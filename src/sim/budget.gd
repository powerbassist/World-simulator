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
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Events = preload("res://src/sim/events.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Credit = preload("res://src/sim/credit.gd")
const Tax = preload("res://src/sim/tax.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const Regions = preload("res://src/sim/regions.gd")
const Migration = preload("res://src/sim/migration.gd")
const Energy = preload("res://src/sim/energy.gd")


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
	ns.revenue_pct_gdp = revenue_lines(
		ns.tax_rates_pct, ns.start_tax_rates_pct, Tax.progressivity_base_factor(ns)
	)
	ns.revenue_pct_gdp["other"] = ns.other_revenue_pct_gdp + ns.law_other_revenue_pct_gdp
	ns.revenue_pct_gdp["tariffs"] = _tariff_revenue(state, ns)
	# V1.4c's line, and the second computed REVENUE line after the tariff one above.
	# Read straight off NationState rather than recomputed here, unlike the tariff
	# line and exactly like the subsidy bill below: Companies.tick_month() runs after
	# this, so a firm nationalised this month pays its first dividend next month --
	# the one-month lag the bloc transfer, the deployment bill and the subsidy bill
	# all take, and for the same reason, since `deficit_pct_gdp` is a company action's
	# own precondition field.
	#
	# The PURCHASE is not here and is not a revenue or a spending line at all. A
	# capital transaction is a balance-sheet swap: Companies.execute() writes
	# `debt_eur_bn` directly, so the price reaches this function next month as
	# `debt_service_pct_gdp` and never as a one-off nothing on this budget has a shape
	# for.
	ns.revenue_pct_gdp["dividends"] = ns.dividend_revenue_pct_gdp

	var revenue := 0.0
	for v in ns.revenue_pct_gdp.values():
		revenue += float(v)
	ns.total_revenue_pct_gdp = revenue

	# V1.6c. The rate is Credit.yield_pct(ns) where it was a flat
	# C.DEBT_REAL_RATE_PCT from the MVP until now, and that constant is still the
	# ANCHOR: the yield is it plus a spread whose every input is measured against the
	# nation's own start, so this line is bit-identical at new game and every balance
	# figure ever quoted against a flat 2.0 keeps its meaning. See src/sim/credit.gd.
	#
	# ABOVE ns.deficit_pct_gdp's assignment at the bottom of this function, and that
	# ordering is load-bearing rather than incidental. The spread reads the deficit, and
	# debt service is INSIDE the deficit, so a yield reading the figure this function is
	# about to write would feed itself -- the positive feedback docs/economy-model.md
	# forbids. Reading it here means it is last month's, which is the same one-month lag
	# the bloc transfer, the deployment bill and the subsidy bill all take a few lines
	# below, and for the same reason. The loop is broken by a lag that already existed.
	ns.debt_service_pct_gdp = 0.0
	if ns.gdp_eur_bn > 0.0:
		ns.debt_service_pct_gdp = Credit.yield_pct(ns) * ns.debt_eur_bn / ns.gdp_eur_bn

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
		# V1.3g's line, and on the spending side for exactly the reasons above it:
		# not a sixth SPENDING_KEYS entry, because that would key a sixth cabinet
		# portfolio and the player sets this one with no slider at all. Read straight
		# off NationState and NOT recomputed here, because Defence.tick_month() runs
		# after this and an obligation that arrived this month must bill next month --
		# the same one-month lag the bloc transfer takes, and for the same reason: a
		# bill that widened the deficit inside the month would feed the deficit
		# precondition that decides which verbs are available.
		+ ns.deployment_bill_pct_gdp
		# V1.4a's line, and the third to take this route rather than the fourth: the
		# argument above is now the settled one for any bill the player does not set
		# with a slider. Companies.tick_month() runs after this, so a subsidy signed
		# this month bills next month -- the lag the bloc transfer and the deployment
		# bill both take, and for the same reason, since `deficit_pct_gdp` is a
		# company action's own precondition field.
		+ ns.subsidy_bill_pct_gdp
		# V1.6e's line, and the fourth to take this route. The same argument a fourth
		# time: not a sixth SPENDING_KEYS entry, because that list is keyed 1:1 to
		# cabinet portfolios and the player sets this one with a verb rather than a
		# slider. Read straight off NationState and NOT recomputed here, because
		# Investment.tick_month() runs after this and a programme committed this month
		# must bill next month -- `deficit_pct_gdp` is one of that verb's own
		# precondition fields.
		+ ns.investment_bill_pct_gdp
		# V1.6f's line, and the fifth to take this route. The same argument a fifth
		# time, and the one difference is worth stating: this bill STOPS. Every other
		# line above it is a standing rate the player can lower; a project's cost runs
		# for exactly as long as the work does and ends the month it completes, which
		# is the whole of what makes it a commitment rather than a policy.
		# Projects.tick_month() runs after this in main.gd's order, so a project begun
		# this month bills next month -- `deficit_pct_gdp` is one of that verb's own
		# precondition fields.
		+ ns.project_bill_pct_gdp
		# V1.7a's line, and the sixth to take this route. The same argument a sixth time,
		# and the one difference is the deadline: V1.6f's bill stops when the work does,
		# which is a length the player chose, and this one stops at the vote, which is a
		# date the constitution chose. Campaign.tick_month() runs after this in main.gd's
		# order, so an effort begun this month bills next month -- `deficit_pct_gdp` is one
		# of that verb's own precondition fields.
		+ ns.campaign_bill_pct_gdp
		# V2.8. THE EIGHTH COMPUTED SPENDING LINE, and it is the second one that
		# can STOP -- a project ends when it is built and a campaign when the vote
		# comes, where a station's run cost lasts until the player closes it. That
		# is why data/energy-actions/ ships a decommission: a monthly charge with no
		# off switch is V1.3g's permanent monotone charge, and the off switch here
		# is a verb rather than a clock. Billed a month behind the order, as every
		# other computed line is, because deficit_pct_gdp is this verb's own
		# precondition field and a same-month bill closes a loop.
		+ ns.energy_bill_pct_gdp
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
## `progressivity_factor` is V1.6d's, and it is passed rather than read off a
## NationState for the reason `ref_rates` is: this function is called twice inside
## commit(), once at the OLD schedule and once at the PENDING one, and a version that
## reached for live state could not express the difference. Defaulted to 1.0 -- the
## no-brackets model every caller before V1.6d ran -- so the two call sites that
## genuinely have no schedule to hand (modelled_revenue_total() at new-game
## calibration, where the deviation is zero by construction) read the same numbers
## they always did.
static func revenue_lines(
	rates: Dictionary, ref_rates: Dictionary, progressivity_factor: float = 1.0
) -> Dictionary:
	var out := {}
	for key in C.TAX_KEYS:
		var rate := float(rates.get(key, 0.0))
		var yield_pct: float = float(C.TAX_BASE_SHARE[key]) * rate * _erosion(key, rate, ref_rates)
		# V1.6d. A factor on the INCOME LINE ONLY, and the first draft put it inside
		# _erosion() instead -- which was wrong in a way that measured as zero rather
		# than as a wrong number, so only tests/test_tax.gd's own check caught it. The
		# erosion coefficient multiplies `(rate - ref)`, and a player who steepens the
		# brackets WITHOUT touching the headline rate leaves that difference at exactly
		# zero, so a coefficient there is multiplied by nothing and the whole price
		# vanishes precisely for the budget the lever exists to express.
		#
		# It belongs on the base rather than on the curve on the merits too: a steeper
		# schedule does not change how fast the base responds to a rate change, it
		# SHRINKS THE BASE -- top incomes are the mobile part, and progressivity is what
		# points the rate at them. Still one coefficient inside the one income line, so
		# section 6's "without a fourth revenue channel" holds exactly as before.
		if key == "income":
			yield_pct *= progressivity_factor
		out[key] = yield_pct
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


## No progressivity argument, and the omission is correct rather than an oversight:
## its one caller is GameState's new-game calibration, where the live schedule IS the
## starting schedule and the deviation is exactly zero. Passing 1.0 explicitly would
## claim this function works at any schedule, which it does not.
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
	# V1.6d, AND IT IS A BUG FIX RATHER THAN AN ADDITION. This branch returned a flat
	# 1.0 -- no diminishing returns at all, revenue linear in the rate forever -- which
	# is correct for a tax nobody has and wrong the moment a player invents one. It was
	# unreachable while every nation authored all three of income, corporate and VAT
	# above zero, and V1.6d's content makes it reachable on the first frame:
	# Switzerland taxes no private capital gain, Belgium and Luxembourg broadly neither,
	# and eight of the ten start with no wealth tax at all. Left alone, the player's
	# best move would have been to invent a tax from nothing and take it to the ceiling.
	#
	# The curve is taken against an absolute reference instead of a relative one, which
	# is the only thing available when the relative one is zero. Same shape, same
	# clamps, and it meets the old branch continuously nowhere -- a nation starting at
	# zero and one starting at its EROSION_ZERO_REF_PCT are different nations, not the
	# same nation approached from two directions. That table is PER KEY, and it has to
	# be: an invented capital-gains tax is normally levied around twenty-five points
	# and an invented wealth tax below one.
	var effective_ref := ref if ref > 0.0 else float(C.EROSION_ZERO_REF_PCT[key])
	var raw: float = 1.0 - float(C.TAX_EROSION[key]) * (rate_pct - effective_ref) / effective_ref
	return clampf(raw, C.EROSION_MIN, C.EROSION_MAX)


## Apply a pending budget. `pending` is {"tax_rates_pct": {...},
## "spending_pct_gdp": {...}, "tax_progressivity": float}; any key may be omitted to
## leave it unchanged.
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

	# V1.6d. A THIRD KEY ON `pending`, beside the two dictionaries, and a scalar rather
	# than a fourth entry in tax_rates_pct -- because it is not a rate. Optional like
	# the other two, so every existing caller that sends two keys keeps the schedule it
	# had.
	var new_progressivity: float = float(pending.get(
		"tax_progressivity", ns.tax_progressivity
	))

	# Both read at their OWN schedule, which is what makes a bracket change on its own
	# raise the demand impulse below. This is the whole of progressivity's revenue
	# price: the same headline rate collects less at a steeper schedule, so the delta
	# falls out of the erosion curve rather than out of a term of its own. See
	# tax_constants.PROGRESSIVITY_BASE_BETA.
	var old_factor: float = Tax.progressivity_base_factor(ns)
	var new_factor: float = Tax.base_factor_at(
		new_progressivity, float(ns.start_tax_progressivity)
	)
	var old_revenue := revenue_lines(ns.tax_rates_pct, ns.start_tax_rates_pct, old_factor)
	var new_revenue := revenue_lines(new_rates, ns.start_tax_rates_pct, new_factor)

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
	ns.tax_progressivity = clampf(
		new_progressivity, TaxK.PROGRESSIVITY_MIN, TaxK.PROGRESSIVITY_MAX
	)
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
		# V1.6a, AND IT IS A BUG FIX RATHER THAN AN ADDITION. This loop has never
		# advanced the clock on its copy: it ran twelve ticks at one date, and until now
		# nothing it called computed anything from the date -- bloc.gd, defence.gd and
		# cabinet.gd read state.year only to STAMP a record, and calendar.gd, which
		# genuinely reads it, is not run here. The cycle is the first thing in the
		# projection that is a function of the month, so a frozen clock made every
		# projected month repeat the current month's impulse. tests/test_cycle.gd caught
		# it on the first run: month 1 projected -0.903 and delivered -0.690.
		#
		# This is docs/decision-log.md's V1.5d finding one layer down -- a harness that
		# silently does not do the thing it appears to do -- and it was invisible for
		# eleven sessions because no reader existed to notice.
		sim.month += 1
		if sim.month > 12:
			sim.month = 1
			sim.year += 1
		# V2.8. The accessibility index per nation, built here because energy.gd never
		# learns that a graph exists. Same index Regions already computes, so the
		# Dijkstra rows are served from network.gd's own per-graph cache and this
		# costs a lookup. Immediately BEFORE Economy, because economy.gd READS
		# ns.energy_impulse_pct rather than computing it -- an energy tick placed
		# after the economy would price this month's mix against last month's
		# growth, a one-month lag in a channel with no reason to have one.
		var access_by_nation: Dictionary = {}
		for nation_id in sim.nations.keys():
			access_by_nation[nation_id] = Regions.accessibility_for(
				sim.nations[nation_id], sim.regions.get(nation_id, []), sim.region_graph)
		Energy.tick_month(sim, loader, access_by_nation)
		Economy.tick_month(sim)
		tick_month(sim)
		# In the same position main.gd runs it -- after Budget, before the snapshot
		# -- and required for exactly the reason Diplomacy is. The council advances,
		# a defied rule keeps charging, and a projection that held the bloc frozen
		# would under-report the deficit of a player in breach. V1.3b's repair, made
		# once rather than rediscovered.
		Bloc.tick_month(sim, loader)
		Diplomacy.tick_month(sim, loader)
		# In main.gd's slot again, and required for the same reason Bloc and Diplomacy
		# are: a projection that held defence frozen would report the bill of a player
		# already under an alliance obligation as never having existed, and would miss
		# an obligation arriving inside the projected window entirely. V1.3b's repair,
		# made a third time rather than rediscovered a third time.
		Defence.tick_month(sim)
		# In main.gd's slot a fourth time, and required for the same reason the three
		# above it are: a projection that held the firm register frozen would report a
		# standing subsidy as costing nothing and would hold the share shift still, so
		# the one surface in the game that promises "this is what will happen" would be
		# wrong about the thing the player just paid for.
		Companies.tick_month(sim, loader)
		# In main.gd's slot -- between Companies and Investment -- and absent
		# altogether until the V2.8 review, which is the one system here that had
		# neither a paragraph justifying its presence nor Media's paragraph
		# justifying its absence. It is not inert: this is the only writer of
		# region_pop_share/city_pop_share, and since V2.6c it carries the natural
		# change flow too. Those shares are read inside this very loop, by
		# Unrest._tick_nation() through site_report() -> Siting.site() and
		# Regions.gdp_per_head_index(), which prices act_impulse() -> the sixth
		# addend of economy.gd's growth sum -> GDP, revenue and deficit_pct_gdp.
		# Held frozen, a projection could site a strike in the wrong region
		# entirely -- Germany's demonstration turns on a +0.4 % margin -- so the
		# one surface that promises "this is what will happen" disagreed with what
		# happened. V1.3b's repair, made an eighth time.
		Migration.tick_month(sim, loader)
		# In main.gd's slot, and required for the reason the five above it are: a
		# projection that held the investment register frozen would report a
		# programme committed this month as costing nothing AND would hold the
		# capital stock still, so the one surface in the game that promises "this
		# is what will happen" would be silent about both halves of what the player
		# just signed. V1.3b's repair, made a seventh time rather than rediscovered
		# a seventh time.
		Investment.tick_month(sim)
		# In main.gd's slot, and required for the reason the six above it are: a
		# projection that held the project register frozen would report a build begun
		# this month as costing nothing, and -- worse than any of them -- would never
		# COMPLETE one inside the projected window, so the one surface that promises
		# "this is what will happen" would be silent about the only moment this lever
		# has. V1.3b's repair, made an eighth time rather than rediscovered an eighth
		# time.
		Projects.tick_month(sim, loader)
		# In main.gd's slot, and required for the reason the seven above it are -- with a
		# sharper case than any of them. A projection that held the campaign register
		# frozen would report a run-up as costing nothing AND would never CLOSE the window
		# inside the projected months, so a president looking at a twenty-four-month
		# forecast in the month before an election would see a campaign bill they will
		# stop paying in four weeks charged for two years.
		Campaign.tick_month(sim, loader)
		# In main.gd's slot a fifth time, and required for the same reason the four
		# above it are: a projection that held the quality stock frozen would report a
		# spending cut as costing nothing beyond its own delta, when the whole point of
		# the stock is that the consequence arrives over the following three years.
		# V1.3b's repair, made a fifth time rather than rediscovered a fifth time.
		# V1.5b, immediately before Society: the quality stock divides by this layer's
		# dependency factor, so demography must have settled before quality reads it.
		Demography.tick_month(sim)
		Society.tick_month(sim)
		# In main.gd's slot a sixth time, and required for the same reason the five above
		# it are -- but this one is the sharpest case yet, because the others report a
		# standing cost the player has already chosen and this one reports an act nobody
		# has chosen at all. A projection that held unrest frozen would show a country
		# heading into a general strike as growing normally for twelve months, which is
		# the one surface in the game that promises "this is what will happen" being
		# silent about the thing that is about to happen. V1.3b's repair, made a sixth
		# time rather than rediscovered a sixth time.
		Unrest.tick_month(sim)
		# V1.8, in main.gd's slot immediately after Unrest, and required for the reason
		# Unrest's own line above gives -- in the one case where it is not about a
		# standing cost at all. A projection that held the event register frozen would
		# never count a pending deadline DOWN, so a president looking at a twelve-month
		# forecast while a crisis sits on their desk would see a future in which the
		# default never arrives and saying nothing is free. It is also the only line in
		# this loop that can fire something new: the hazard is a pure function of
		# (nation, event, month), so the projection sees exactly the events the next
		# twelve months deliver rather than an average of them.
		Events.tick_month(sim, loader)
		# In main.gd's slot a seventh time, and V1.6b is where the question the comment
		# below asks about Media gets the OPPOSITE answer -- so the two sit together
		# deliberately, as the pair that shows what the test actually is.
		#
		# Media is refused because `framing_gain` reaches a figure only through approval
		# and this loop holds no election. Inflation is required because it writes
		# inflation_impulse_pct, the eighth addend in economy.gd's growth sum, so it
		# reaches GDP, revenue and the deficit on the very next iteration of this loop.
		# A projection that held it frozen would report a player heading into an
		# inflationary boom as growing normally for twelve months, and the 1e-9 equality
		# tests/test_budget.gd asserts is a done-when condition rather than a nicety.
		Inflation.tick_month(sim)
		# V1.5d is the first session since V1.3b whose tick does NOT belong here, and
		# the omission is deliberate rather than forgotten. Media.tick_month() writes
		# `framing_gain`, which has exactly one reader -- opinion.gd's bloc loop -- and
		# this projection does not run Opinion at all. Every other addition above
		# reaches a projected FIGURE: the bloc charges a penalty into the deficit, a
		# subsidy costs money, the quality stock decays, a strike shrinks output.
		# Framing reaches a figure only through approval, and approval reaches the
		# budget only through an election this loop does not hold. Adding the call
		# would be a tick whose result nothing reads, which is the failure this project
		# has named four times -- so the seventh instance of V1.3b's repair is refused
		# on the evidence rather than performed by symmetry.
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
		# V1.3g. On the snapshot rather than read off NationState by the panel, for
		# the reason every other figure here is: the budget panel compares a
		# PROJECTED month against the current one, and a projection has no
		# NationState the panel can reach.
		"deployment_bill_pct_gdp": ns.deployment_bill_pct_gdp,
		"military_capability": ns.military_capability,
		# V1.4a, on the snapshot for V1.3g's reason above. The two deviation channels
		# are here as well, because the budget panel's projection is the one surface
		# that can show a subsidy's growth effect arriving before it has arrived.
		"subsidy_bill_pct_gdp": ns.subsidy_bill_pct_gdp,
		"firm_impulse_pct": ns.firm_impulse_pct,
		"firm_jobs_offset_pct": ns.firm_jobs_offset_pct,
		# V1.4c, here for the same reason: the dividend line lags a month, so the
		# projection is the surface that shows it arriving.
		"dividend_revenue_pct_gdp": ns.dividend_revenue_pct_gdp,
		# V1.6d, and on the snapshot for deployment_bill_pct_gdp's reason at V1.3g: the
		# budget panel compares a PROPOSED position against the current one, and a
		# preview has no NationState the panel can reach. It is the EFFECTIVE index --
		# Demography's measured drift plus the player's own policy offset -- because the
		# drift alone is the half the player cannot move and the readout exists for the
		# half they can.
		"gini_effective": float(ns.gini_index) + Tax.gini_policy_offset(ns),
		"deficit_pct_gdp": ns.deficit_pct_gdp,
		"demand_impulse_pct": ns.demand_impulse_pct,
		# V1.6a, and this session added NO tick call to project() at all -- the first
		# since V1.3b not to. The cycle is written inside Economy.tick_month(), which
		# this loop already runs, so the projection reproduces it exactly and
		# tests/test_budget.gd's 1e-9 equality holds untouched with the cycle live.
		# That is the same structural call src/sim/cycle.gd's header makes about the
		# balance harnesses, paying off at a third site nobody had to remember.
		#
		# It is on the snapshot because the budget panel's forecast band needs the
		# projected path and a projection has no NationState the panel can reach --
		# deployment_bill_pct_gdp's reason at V1.3g.
		"cycle_impulse_pct": ns.cycle_impulse_pct,
		"potential_shift_pct": ns.potential_shift_pct,
		# V1.6e, on the snapshot for deployment_bill_pct_gdp's reason at V1.3g: the
		# budget panel compares a PROJECTED month against the current one and a
		# projection has no NationState the panel can reach. BOTH HALVES are here --
		# the bill the treasury pays now and the trend the capital has bought -- because
		# the whole point of this lever is that the two arrive years apart, and the
		# projection is the only surface that can show the second one coming.
		"investment_bill_pct_gdp": ns.investment_bill_pct_gdp,
		"investment_trend_shift_pct": Investment.national_trend_shift_pct(ns),
		# V1.6f, on the snapshot for deployment_bill_pct_gdp's reason at V1.3g: the budget
		# panel compares a PROJECTED month against the current one and a projection has no
		# NationState the panel can reach.
		#
		# ONE KEY AND NOT THREE, which is the fifteenth screenshot pass's correction read
		# from the model side. The first version also carried the accumulated payoff and a
		# count of live builds, on V1.6e's "both halves" argument -- and neither is read
		# by anything, because the payoff belongs on Public Works (which has the
		# NationState) and the count made this panel's widest cell and pushed a column off
		# the window. A snapshot key nothing reads is a tuned constant nothing reads:
		# deleted rather than left, U6a's day budget and V1.3e's AGREEMENT_ACCEPT_MIN.
		"project_bill_pct_gdp": ns.project_bill_pct_gdp,
		# ONE KEY AND NOT TWO, V1.6f's correction inherited: the mobilisation belongs on
		# the Campaign panel, which has the NationState, and a second key here would be a
		# snapshot entry nothing reads.
		"campaign_bill_pct_gdp": ns.campaign_bill_pct_gdp,
		# V2.8, on the snapshot for campaign_bill_pct_gdp's reason one line up: the
		# panel compares a PROJECTED month against the current one and a projection
		# has no NationState to read the bill from.
		"energy_bill_pct_gdp": ns.energy_bill_pct_gdp,
		"sectors": ns.sector_output.duplicate(true),
	}
