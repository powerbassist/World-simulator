extends RefCounted

## Every tunable in the legislature model, in one file. Same shape as
## economy_constants.gd, opinion_constants.gd and election_constants.gd — model
## parameters, not content, so not in data/. Rationale for every number is
## docs/legislature-model.md; this file is the values, that file is the argument.

# --- Support -------------------------------------------------------------------

## How fast a party's support for a law falls off with ideological distance from
## the law's own (economic, social) position. Parties are disciplined voting
## blocs, not fuzzy electorates, so this is tighter than election_constants.gd's
## AFFINITY_SIGMA (0.8) — a party a full axis-width from a bill is close to
## indifferent to it rather than merely lukewarm.
const LAW_SIGMA := 0.6

## GOVERNMENT_BONUS (a flat 0.35 for the single incumbent party) lived here
## until V1.1a. A government is now a coalition, so the bonus is earned rather
## than given: government_constants.gd's COALITION_BONUS_MAX, scaled by the
## party's distance from the agreed position and by its discipline. See
## docs/government-model.md.

## |support| below this counts as an abstention rather than a yes or a no.
const ABSTAIN_BAND := 0.05

# --- Majority thresholds --------------------------------------------------------

## "simple" = yes > no among votes cast (abstentions don't count either way).
## "absolute" = yes > half of the whole assembly, abstentions count against it.
## "two_thirds" = yes >= two thirds of the whole assembly. Institutional laws
## use the stricter forms. "amendment" (V1.2c) reads the proposing nation's
## OWN threshold off ns.amendment_rule via AMENDMENT_RULE_FRACTIONS below,
## rather than a fixed fraction here -- see docs/amendment-model.md.
const MAJORITY_KEYS := ["simple", "absolute", "two_thirds", "amendment"]
const ABSOLUTE_MAJORITY_FRACTION := 0.5
const TWO_THIRDS_MAJORITY_FRACTION := 2.0 / 3.0

## Real constitutional amendment thresholds, per docs/political-systems.md's
## amendment_rule. Fraction of the WHOLE assembly, same basis as
## ABSOLUTE_MAJORITY_FRACTION and TWO_THIRDS_MAJORITY_FRACTION above --
## abstentions count against passage. referendum_required has no seat
## fraction: no amendment names it in `systems` (Switzerland is not
## playable), so resolve_vote() never looks it up -- see
## docs/amendment-model.md's reachability sweep for why Germany's real
## two_thirds is measured, not detuned, even though it is unreachable.
const AMENDMENT_RULE_FRACTIONS := {
	"ordinary_law": ABSOLUTE_MAJORITY_FRACTION,
	"three_fifths": 0.6,
	"two_thirds": TWO_THIRDS_MAJORITY_FRACTION,
	"three_quarters": 0.75,
}

# --- Effect channel clamps -------------------------------------------------------

## Structural-unemployment offset a law can accumulate, points. Same order of
## magnitude as economy_constants.gd's STRUCT_INCOME_BETA effect over a term.
const STRUCTURAL_OFFSET_MIN_PCT := -5.0
const STRUCTURAL_OFFSET_MAX_PCT := 5.0

## Long-run trend-growth target a law can accumulate, %/yr — added to the same
## target economy.gd's potential-shift lag already adjusts toward, so it inherits
## the five-year time constant and the +-1.0 hard clamp untouched.
const POTENTIAL_TARGET_MIN_PCT := -1.0
const POTENTIAL_TARGET_MAX_PCT := 1.0

## Off-budget revenue a law can accumulate, percent of GDP. Bounded well below
## the point where it could make other_revenue_pct_gdp negative on its own.
const OTHER_REVENUE_MIN_PCT := -10.0
const OTHER_REVENUE_MAX_PCT := 10.0

## Per-bloc approval-target offset a law can accumulate, on the same [-1, +1]
## scale opinion_constants.gd's satisfaction terms use.
const BLOC_OFFSET_MIN := -1.0
const BLOC_OFFSET_MAX := 1.0

# --- Preconditions ---------------------------------------------------------------

## The only NationState-derived fields a law's preconditions may test. Unknown
## field is a startup error, not a silently-false predicate -- the same failure
## discipline data_loader.gd already applies to an unpositioned ideology_slot.
const PRECONDITION_FIELDS := [
	"debt_to_gdp_pct", "unemployment_pct", "deficit_pct_gdp",
	"overall_approval_pct", "growth_annual_pct", "terms_served",
]

const PRECONDITION_OPS := ["<", "<=", ">", ">=", "=="]
