extends RefCounted

## The distributional half of the tax model: progressivity, and what the player's
## tax policy does to the inequality index docs/unrest-model.md shipped as a
## declared stopgap.
##
## STATELESS BY CONSTRUCTION. No tick_month(), no accumulator, no field on
## NationState written from here, nothing on GameState, and therefore nothing in
## the save format. Every function below is a pure read of state other modules
## already own and the save already carries -- Defence.allies()' shape and
## Credit.rating()'s at V1.6c. tests/test_tax.gd reads this file and fails if a
## tick_month() appears or if anything here assigns to `ns`, and
## tests/test_save_load.gd pins the absence of a stored offset, so a later session
## making this stateful turns two tests red and has to come and say why.
##
## The two new TAX KEYS are not here. A fourth and fifth tax is the same machine
## with more entries -- Budget.revenue_lines() already loops TAX_KEYS -- so their
## base shares, erosion coefficients and multipliers extend
## economy_constants.gd's existing three tables rather than starting a fourth.
## What this file holds is what V1.6d genuinely invented.
##
## The model, every constant and the measured tables are docs/tax-model.md.

const C = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/tax_constants.gd")


## How steep the income-tax schedule is, against the flat-tax floor and the ceiling
## the lever runs to. Clamped on read as well as on write, so a save carrying a
## value outside the band -- or an absent one, which reads 0.0 and means "flat" --
## still produces a number the rest of the model can use.
static func progressivity(ns) -> float:
	return clampf(float(ns.tax_progressivity), K.PROGRESSIVITY_MIN, K.PROGRESSIVITY_MAX)


## How far the schedule has been steepened since the game began. Exactly 0.0 at new
## game for all ten, because GameState captures the start from the same constant it
## initialises the live value from.
static func progressivity_deviation(ns) -> float:
	return progressivity(ns) - float(ns.start_tax_progressivity)


## What a steeper schedule does to the income tax's effective BASE, as a multiplier on
## the income revenue line.
##
## THE FIRST OF PROGRESSIVITY'S TWO PRICES, and the reason there is no fourth revenue
## channel. Budget.revenue_lines() multiplies the income line by this and no other line
## by anything, so income revenue is still computed in exactly one place and
## progressivity is a coefficient inside it rather than a second writer --
## docs/coercion-model.md's `tariff_rate_pct` error avoided rather than repeated.
##
## ON THE BASE AND NOT ON THE EROSION CURVE, which the first draft of this session got
## wrong and which measured as ZERO rather than as a wrong number. The erosion
## coefficient multiplies `(rate - ref)`, so a player steepening the brackets without
## touching the headline rate leaves that difference at exactly zero and the whole price
## disappears for the budget the lever exists to express. It is also the better model:
## a steeper schedule does not change how fast the base responds to a rate change, it
## shrinks the base, because the top of the distribution is its mobile part and
## progressivity is what points the rate at it.
##
## Floored at zero rather than clamped to a band: a schedule flat enough to drive this
## negative would make the income tax collect NEGATIVE revenue, and no clamp downstream
## catches that because the sign flips inside the coefficient. Unreachable at
## PROGRESSIVITY_MIN and the shipped beta, and tests/test_tax.gd says so, which is what
## makes it a guard rail rather than the number.
static func progressivity_base_factor(ns) -> float:
	return base_factor_at(progressivity(ns), float(ns.start_tax_progressivity))


## The same factor for a schedule that is not the one on the state yet, which is what
## apply_pending() needs to price a PENDING bracket change against the current one.
##
## Split out rather than inlined at that call site, and the split is the point: two
## copies of this expression is one formula with two writers, which is exactly the
## discipline `share`, `state_share`, `regulation_burden` and `gini_index` are each
## held to a level up. tests/test_tax.gd asserts the two agree at the live schedule.
static func base_factor_at(level: float, start_level: float) -> float:
	var clamped: float = clampf(level, K.PROGRESSIVITY_MIN, K.PROGRESSIVITY_MAX)
	# MINUS. A steeper schedule SHRINKS the effective base -- the top of the
	# distribution is its mobile part -- so the factor falls below 1.0 as the index
	# rises. Written as a plus in the first draft, which made progressivity collect MORE
	# and turned the lever into free money; caught by tests/test_tax.gd rather than by
	# reading, because the sign is buried one call away from the revenue line it scales.
	return maxf(1.0 - K.PROGRESSIVITY_BASE_BETA * (clamped - start_level), 0.0)


## How far the player's own tax policy has moved the inequality index, in points,
## against where that policy started. Negative is more equal.
##
## THE SECOND PRICE, AND THE DISCHARGE OF docs/unrest-model.md's DECLARED STOPGAP.
## Unrest.inequality_deviation() adds this to the measured drift Demography carries,
## so the effective index is a SUM OF TWO READS and neither of them is stored: the
## drift has one writer and it is Demography.tick_month(), and this half has no writer
## at all. That is what the V1.6 decomposition's "a second field, not a second writer"
## asked for, one step further -- there is no second field either.
##
## Three instruments and no more, and the absences are the design. docs/tiers/v1.md
## section 6 owns brackets, capital gains and wealth; the CORPORATE rate is not on that
## list, and tests/test_unrest.gd has asserted the index is blind to it since V1.5c --
## an assertion this session keeps rather than relaxes. `state_share` and
## `regulation_burden` stay blind for the same reason, so two thirds of that test
## survives the discharge unchanged and only the third that section 6 owns turns over.
##
## Clamped, and the clamp is reported by the probe rather than assumed slack.
static func gini_policy_offset(ns) -> float:
	var offset: float = -K.GINI_PROGRESSIVITY_BETA * progressivity_deviation(ns)
	for key in K.GINI_RATE_BETA:
		var d_rate: float = (
			float(ns.tax_rates_pct.get(key, 0.0))
			- float(ns.start_tax_rates_pct.get(key, 0.0))
		)
		offset -= float(K.GINI_RATE_BETA[key]) * d_rate
	return clampf(offset, -K.GINI_POLICY_MAX_PT, K.GINI_POLICY_MAX_PT)
