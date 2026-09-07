extends RefCounted

## Every tunable in the trade model, in one file. Same shape as
## economy_constants.gd, diplomacy_constants.gd and the rest -- model parameters,
## not content, so not in data/. Rationale for every number is
## docs/trade-model.md; this file is the values, that file is the argument.
##
## Every number below was set by tools/trade_probe.gd BEFORE src/sim/trade.gd
## existed and before any agreement content was authored. The gravity parameters
## in particular are the OUTPUT of the probe's differentiation sweep, not an input
## to it -- see the escalation the sweep caught, recorded under GRAVITY_EXPONENT.

# --- The gravity weight ----------------------------------------------------------

## How partner size enters the weight. Below 1.0, so a partner twice the size is
## less than twice the trade -- the standard gravity finding, and here it is also
## the constant the whole feature turned on.
##
## THE PROBE'S ESCALATION, AND WHAT SET THIS NUMBER. At 1.0 the weight vector is
## GDP-proportional, and GBR's derived vector is then IDENTICALLY the GDP-weighted
## aggregate this model replaces -- L1 distance 0.000, measured. GBR is in no EU
## pair and its neighbours list is empty, so both tie bonuses below are constant
## across all nine of its partners and cancel when the vector is normalised. The
## headline feature of V1.3b would have been a no-op for one playable nation in
## three, in the same class as the cold read docs/transition-model.md records for
## V1.2d. The exponent is the ONLY lever that moves GBR at all: 1.00 -> 0.000,
## 0.85 -> 0.084, 0.70 -> 0.174, 0.60 -> 0.238. 0.70 rather than 0.85 because
## GBR's distance is a pure function of this one number, and 0.084 is too close to
## the 0.05 line the probe calls a no-op to rest a playable nation on.
const GRAVITY_EXPONENT := 0.70

## Both partners in the EU, and a shared land border. Multiplicative on the raw
## weight, before normalisation.
##
## These do NOT exist to separate a nation from the old aggregate -- the exponent
## does that. They exist to separate the nations from EACH OTHER: with both at
## zero the probe's cross-nation L1 is 0.02-0.07, meaning all three playable
## nations trade almost identically, which is a different way of shipping nothing.
## At these values it is 0.41.
##
## The border bonus is the larger of the two, inverting diplomacy_constants.gd's
## ordering of the same two facts, and deliberately: adjacency dominates real
## bilateral trade far more than co-membership does, whereas for RELATIONS an
## institution whose whole purpose is alignment outweighs a border that cuts both
## ways.
const BORDER_TRADE_BONUS := 1.20

## How far relations move the weight, as a multiplier on the raw weight:
## 1 + INTENSITY_SPAN * (relations - REST_BASE)/100, floored at zero.
##
## This is the ONLY channel by which relations reach the economy, and it moves the
## MIX and never the level -- see openness below for why that is deliberate rather
## than a limitation. At 2.0 a pair at the 68 resting tier carries 1.46x the weight
## of one at 45, and pushing a pair to its measured ceiling of 83.7 buys about 21%
## more weight than resting.
##
## Bounded above by the floor: at relations 0 the multiplier is 1 - 0.9 = 0.1, so
## 2.0 leaves comfortable room before the floor would start clipping and turning a
## smooth response into a cliff. Anything above 2.2 does not.
const INTENSITY_SPAN := 2.00

# --- Cycle transmission ----------------------------------------------------------

## Sensitivity of the player's growth to trade partners' growth deviating from
## their own new-game baselines. Moved here from economy_constants.gd at V1.3b,
## unchanged in value: one system, one module, and leaving it behind would split
## the trade tunables across two files.
##
## Still numerically quiet, and now honestly so. The term is per-partner and
## structurally correct, and it is exactly zero at new-game and under ANY
## re-weighting while partners sit at baseline. It stays near zero because nothing
## perturbs a partner: the nine AI nations have no budget and take no shocks.
## V1.3c's tariffs and sanctions are the first perturbation, and this is the
## machinery they drive. tools/trade_probe.gd injects a synthetic partner recession
## to measure what the term does when something finally moves.
const TRADE_BETA := 0.25

# --- Openness ---------------------------------------------------------------------

## How far the openness index moves trend growth, through the same
## potential_shift_pct channel infrastructure and education already write. An
## index of 1.35 buys TRADE_OPENNESS_BETA * 0.35 points of trend.
##
## Measured in tools/trade_probe.gd's payoff table against two floors: readable at
## sixty months, and smaller than a budget commit of comparable domestic cost.
const TRADE_OPENNESS_BETA := 1.00

# --- Agreement content limits ------------------------------------------------------

## How far one agreement may multiply a pair's raw trade weight. Bounds the
## content, not the accumulated state, the same way
## diplomacy_constants.MAX_ACTION_RELATIONS_DELTA does.
##
## This bound is load-bearing for economy-model.md's divergence argument: the
## openness index is bounded by it, at load, BEFORE economy_constants.SHIFT_MAX_PCT
## ever sees the term. One agreement per pair and nine partners, so the index
## cannot exceed roughly this figure however the player plays.
const MAX_AGREEMENT_WEIGHT_MULTIPLIER := 2.50

## How far one agreement may shift a single sector's trend rate, in points per
## year. The three shifts must also SUM TO ZERO -- checked at load in
## src/core/diplomatic_action.gd, because the cyclical residual in
## Economy._apply_growth_to_sectors() would otherwise redistribute the surplus by
## SECTOR_CYCLE_BETA and silently produce a different composition change than the
## author wrote. See docs/trade-model.md.
const MAX_AGREEMENT_SECTOR_SHIFT := 1.00
