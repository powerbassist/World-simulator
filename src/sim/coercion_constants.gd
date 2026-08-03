extends RefCounted

## Every tunable in the coercion model, in one file. Same shape as
## trade_constants.gd, diplomacy_constants.gd and the rest -- model parameters,
## not content, so not in data/. Rationale for every number is
## docs/coercion-model.md; this file is the values, that file is the argument.
##
## PROVISIONAL UNTIL tools/coercion_probe.gd RUNS. V1.3b set every trade constant
## from a probe run before src/sim/trade.gd existed, and V1.3a did the same for
## diplomacy; this file is written first so the probe has something to sweep, and
## the numbers below are the sweep's OUTPUT once it has run. A number here that
## was never measured is the failure docs/scenario-model.md records for an
## authored starting approval: a lever that turns out to be decorative.

# --- What a measure does to trade -------------------------------------------------

## How far a measure at severity 1.0 cuts the raw gravity weight on the pair it
## touches: multiplier = 1 - MEASURE_TRADE_BITE * severity, floored.
##
## Applied for measures in EITHER direction on the pair, because a tariff you
## receive cuts your trade with that partner exactly as much as one you impose.
## The register is directed so the two are separate entries; the trade effect is
## not, because goods stop moving either way.
##
## 0.80 rather than 1.00 so that even the harshest legal measure leaves some
## trade rather than severing the pair outright. A severed pair would make the
## weight vector renormalise onto the remaining eight, which reads as the player
## GAINING trade with everyone else -- true in a share sense and misleading as a
## readout, and it would put the openness ratio on a cliff.
const MEASURE_TRADE_BITE := 0.80

## The floor under that multiplier, so a stack of measures cannot drive a pair's
## raw weight to zero and make the normalisation degenerate.
const MEASURE_TRADE_FLOOR := 0.10

# --- What a measure does to the target's growth -------------------------------------

## Points of annual growth removed from the TARGET, per unit of severity, per unit
## of the target's own trade weight on the imposer.
##
##     coercion_impulse(B) = -COERCION_DAMAGE * severity * w_before_measures(B -> A)
##
## Scaled by w(B->A) -- the TARGET's weight on the IMPOSER -- and that direction is
## the whole point of V1.3b's directed table landing before this session. France
## sanctioning Luxembourg hurts Luxembourg badly (w(LUX->FRA) = 0.257); Luxembourg
## sanctioning France barely registers (w(FRA->LUX) = 0.021). Measured at -2.054
## against -0.170, a ratio of 12.1x against the weights' own 12.2x. A symmetric
## pair key could not express that, and an unweighted constant would have made the
## smallest nation in the roster as dangerous as the largest.
##
## BEFORE measures, and that was the probe's second correction. Read off the
## post-measure weight, damage is proportional to the trade that survives, so a
## full embargo did almost nothing and every severity above the revenue peak of
## 0.625 was strictly dominated -- less revenue AND less damage for more trend
## cost. A trap in the content, caught before any content existed.
##
## Set from tools/coercion_probe.gd table (b) against the poll-noise floor. At 8.0
## one full-severity embargo by the largest partner costs the player 2.6 points of
## growth and 4.9 to 7.4 points of approval, so the weakest playable nation clears
## +-3.0 with 1.9 points to spare rather than by exactly nothing.
const COERCION_DAMAGE := 8.00

## Hard clamp on the accumulated coercion impulse, %/yr, either direction.
##
## docs/economy-model.md's divergence argument is PER QUANTITY -- every term that
## reaches growth carries its own bound rather than relying on GROWTH_MIN/MAX to
## catch it downstream. A new quantity owes that argument a row, and this is it.
##
## Equal to economy_constants.IMPULSE_MAX_PCT rather than under it: a coercion
## shock may be as large as the largest budget shock and no larger, which is a
## principled anchor where "somewhat less" was only a feeling. The probe is what
## moved it. At 4.0 the clamp BOUND in reachable play -- a player who tariffs three
## or more partners collects three or more retaliations, damage sums over imposers,
## and the clamp rather than the model was setting the growth rate. That is the
## IMPULSE_MAX failure docs/economy-model.md already records, and catching it here
## rather than shipping it is what the sweep was for.
const COERCION_IMPULSE_MAX := 6.00

# --- What a tariff collects ----------------------------------------------------------

## Revenue from a tariff, as a percent of GDP at full severity against the whole
## roster:
##
##     revenue_pct_gdp(A) = TARIFF_YIELD * Sigma_B severity(A,B) * w(A,B)
##                          over tariffed B, on the POST-measure weight
##
## SEVERITY IS THE ONLY DIAL, and an authored tariff RATE was cut at measurement
## time rather than shipped. The probe's first revenue table carried both and
## showed yield exactly linear in the rate -- 0.0005 per point at every rate, for
## every nation -- because the trade bite read severity and the rate was an
## independent number that only multiplied the answer. Two numbers describing one
## intensity is the redundancy tools/trade_probe.gd caught between the gravity tie
## bonuses and the relations term, and the resolution is the same: carry it once.
##
## What that buys is a Laffer curve that is REAL rather than asserted. Revenue is
## TARIFF_YIELD * s * w0 * (1 - MEASURE_TRADE_BITE * s) before normalisation, which
## has an interior maximum at s = 1 / (2 * MEASURE_TRADE_BITE) = 0.625. Past that,
## a harsher tariff collects less, because it has destroyed more of the trade it
## is levied on. Nothing authors that curve; it falls out of two constants.
##
## Anchored against the tax lines it sits beside on the same panel:
## economy_constants.TAX_BASE_SHARE makes one point of VAT worth 0.53% of GDP and
## one point of income tax 0.50%, so ONE TAX POINT IS ROUGHLY HALF A PERCENT OF
## GDP. A tariff on the largest partner should be worth appreciably less than that
## -- it is a diplomatic act with a trend cost attached, not a fiscal lever -- and
## tariffing the whole roster should be worth several tax points and cost most of
## the trend. Set from the probe's revenue table against exactly those two floors.
const TARIFF_YIELD := 2.00

# --- Retaliation: the declared stopgap ------------------------------------------------

## Months a target waits before answering a measure in kind.
##
## > [!warning] THE ENTIRE COUNTERPARTY MODEL FOR COERCION, and a DECLARED STOPGAP.
## > The third on V1.3e's checklist, after V1.3a's no-reaction and V1.3b's
## > accept-gate. A nation under a measure mirrors it back once, at a fixed
## > fraction, after a fixed delay. It does not weigh its economy, does not
## > compare the imposer against its other partners, does not escalate beyond the
## > single step, never lifts what it imposed, and never acts first.
## > tests/test_coercion.gd asserts exactly that by mutation, so V1.3e replacing
## > it is a visible test change rather than a silent one.
##
## Non-zero so the exchange has a beat the player can read -- an instantaneous
## mirror would look like the game arguing with itself on the same frame the
## button was pressed.
const RETALIATION_DELAY_MONTHS := 3

## Severity of the answer, as a fraction of what was imposed.
##
## BELOW 1.0, and that is what makes the exchange converge rather than ratchet.
## The mirror fires ONCE per measure (the register's `retaliated` flag), so even
## at 1.0 there would be no infinite spiral -- but a full-strength answer plus the
## imposer's original measure puts more coercion on the pair than the player chose,
## and the asymmetry is the honest one: the retaliating nation is reacting, not
## opening.
const RETALIATION_FRACTION := 0.60

## Relations cost of being retaliated against, points, applied to the pair.
##
## Small next to the imposing action's own effects.relations, because the pair has
## already paid for the original measure. This is the second hit, not the first.
const RETALIATION_RELATIONS_COST := -4.00

# --- Content limits --------------------------------------------------------------------

## The two kinds a measure may be. A tariff collects revenue and bites moderately;
## a sanction collects nothing and bites hard. One verb, two prices -- which is
## what docs/tiers/v1.md section 3 committed to when it put tariffs and sanctions
## in the same session: "both are the same verb pointed at the same pair with a
## different price".
const MEASURE_KINDS := ["tariff", "sanction"]

## How severe one authored measure may be, and the model's ONE intensity dial.
## Bounds the content, not the accumulated state, the same way
## diplomacy_constants.MAX_ACTION_RELATIONS_DELTA does.
##
## 1.00 is deliberately PAST the revenue-maximising severity of 0.625 above, so
## the ceiling is not the interesting point on the curve. An author can write a
## tariff harsh enough to collect less than a milder one, and a player can pick
## the punitive verb over the lucrative one knowing which is which.
const MAX_MEASURE_SEVERITY := 1.00
