extends RefCounted

## Every tunable in the distributional half of the tax model, in one file.
##
## Referenced as `const TaxK = preload("res://src/sim/tax_constants.gd")`, the same
## shape as every other *_constants.gd. Rationale for every number is in
## docs/tax-model.md; this file is the values, that file is the argument.
##
## WHAT IS NOT HERE IS THE HALF THAT WAS ALREADY THERE. The two new tax keys' base
## shares, erosion coefficients and fiscal multipliers live in
## economy_constants.gd's existing three tables, because a fourth and fifth tax is
## the SAME machine with more entries -- Budget.revenue_lines() already loops
## TAX_KEYS. This file holds only what V1.6d genuinely invented: progressivity, and
## what the player's distributional policy does to the Gini index docs/tiers/v1.md
## section 5 shipped as a declared stopgap.

# --- Progressivity ------------------------------------------------------------

## Where every nation's bracket structure starts, as a dimensionless index.
##
## ONE VALUE FOR ALL TEN AND DELIBERATELY NOT PER-NATION CONTENT, which is the
## opposite of the call V1.5b made for the ageing slope and V1.6a for the cycle
## amplitude -- and the difference is that those two had a dataset and this does not.
## Nothing on tools/import_data.py's licence-clean loop separates bracket
## progressivity for this roster: the World Bank publishes tax revenue by broad
## category and no measure of the schedule's slope, and OECD's is behind terms
## docs/data-sources.md has already rejected once.
##
## Ten identical authored values in ten nation files would be the clustered
## `coalition_position` failure with extra steps -- a content field that looks
## per-nation, reads per-nation, and carries exactly no information. So it is a model
## constant, ns.tax_progressivity initialises to it, and start_tax_progressivity
## captures it. Every term below is a DEVIATION against that start, which is what
## makes this whole channel read exactly 0.0 at new game for all ten --
## `trade_baseline_by_partner`'s idiom, the cycle's, inflation's, and the bond
## spread's at V1.6c.
const PROGRESSIVITY_BASE := 1.0

## Bounds on the index. 0.0 is a flat tax -- one rate, no schedule -- and 2.0 is
## twice as steep a schedule as the nation actually runs. Not a guard rail but the
## range of the lever itself, so tests/test_tax.gd asserts the panel's slider spans
## exactly this and no more.
const PROGRESSIVITY_MIN := 0.0
const PROGRESSIVITY_MAX := 2.0

## Fraction of the income tax's effective base given up per unit of progressivity above
## the nation's own start.
##
## THE FIRST OF THE TWO PRICES, and it is not a second revenue channel -- which is
## the constraint docs/tiers/v1.md section 6 states outright ("brackets WITHIN income
## rather than as further keys, so the distributional lever exists without a fourth
## revenue channel"). A steeper schedule rests on a more mobile top of the same base,
## so the SAME headline rate collects less. It multiplies the income LINE inside
## revenue_lines() rather than adding a term beside it, so there is exactly one place
## income revenue is computed and progressivity is a coefficient inside it.
##
## ON THE BASE AND NOT ON THE EROSION COEFFICIENT, which is where the first draft put it.
## That version measured as exactly ZERO rather than as a wrong number: the erosion
## coefficient multiplies `(rate - ref)`, so a player who steepens the brackets and
## leaves the headline rate alone leaves that difference at zero and the entire price
## vanishes -- for precisely the budget this lever exists to express. Caught by
## tests/test_tax.gd. The sign was then ALSO backwards, and caught by the same check.
##
## Writing it as revenue directly would be docs/coercion-model.md's `tariff_rate_pct`
## error -- one intensity written twice -- which V1.3c cut and which is what turned an
## asserted Laffer curve into a real one there. Same here: because progressivity moves
## the erosion, a steeper schedule has an interior revenue optimum that nothing authors.
const PROGRESSIVITY_BASE_BETA := 0.15

# --- The Gini policy offset ---------------------------------------------------

## Points of Gini index removed per unit of progressivity above the nation's own start.
##
## THE SECOND PRICE, AND THE ONE THAT DISCHARGES THE STOPGAP. docs/unrest-model.md
## shipped `gini_index` as a declared stopgap read with docs/tiers/v1.md section 6
## named as its real writer, and tests/test_unrest.gd was written to go RED the day
## this landed rather than to be edited quietly.
##
## The discharge is a DERIVED READ and not a second writer, which the V1.6 decomposition
## called for and this goes one better than: it asked for a second FIELD, and there is
## none. Tax.gini_policy_offset() is a pure function of ns.tax_progressivity and the two
## new rates, all three of which the save already carries, so Demography.tick_month()
## remains the single writer of the drift and this module stores nothing at all --
## Defence.allies()' shape, and Credit.rating()'s at V1.6c. tests/test_save_load.gd pins
## the absence.
const GINI_PROGRESSIVITY_BETA := 1.39

## Points of Gini index removed per point of each redistributive rate above the
## nation's own start.
##
## TWO SCALES, AND THE FACTOR OF EIGHT BETWEEN THEM IS THE UNITS RATHER THAN A CLAIM
## ABOUT IMPORTANCE. economy_constants.TAX_BASE_SHARE puts wealth's base at 4.00 and
## capital gains' at 0.02, so one point of wealth rate reaches two hundred times the
## base one point of capital-gains rate does; a table that gave them the same
## coefficient would be saying a wealth tax is two hundred times the redistributive
## instrument, which is a statement about the base masquerading as a statement about
## policy. These are per POINT OF RATE, and the point sizes differ.
##
## `income` and `vat` are ABSENT, not zero, and that is the same discipline
## society_constants.QUALITY_KEYS uses: this table is section 6's instrument list --
## brackets, capital gains, wealth -- and an entry for the income RATE would say a
## flat rise in a flat tax redistributes, which is what progressivity is for. `corporate`
## is absent for the sharper reason that tests/test_unrest.gd asserts the index stays
## blind to it, and that half of the assertion SURVIVES this session unchanged.
const GINI_RATE_BETA := {
	"capital_gains": 0.0695,
	"wealth": 1.390,
}

## Hard clamp on the whole policy offset, in points of Gini.
##
## Measured against the thing it sits beside rather than invented: the roster's own
## measured spread is NLD 25.7 to ITA 34.3, so 8.6 points separates the most equal
## country in this game from the least. A president who can move their own index
## further than the whole of Europe spans has a lever that is no longer about
## distribution. Half that span is the bound.
##
## docs/defence-model.md's and docs/companies-model.md's treatment of their own clamps
## applies: if the reachable stack sits ON this, the clamp and not the model is setting
## the number and the escalation trigger has fired. tools/tax_probe.gd table (e) reports
## the peak against it.
const GINI_POLICY_MAX_PT := 8.60
