extends RefCounted

## Every tunable in the cabinet model, in one file. Same shape as
## economy_constants.gd, opinion_constants.gd, election_constants.gd,
## legislature_constants.gd, government_constants.gd and discipline_constants.gd
## — model parameters, not content, so not in data/, per
## docs/engine-decision.md Rule 1.
##
## The party's own `competence` in data/parties/*.json stays content: it says
## how good that particular invented party is at governing, at its best.
## Everything here says how the world turns that number into an effect, which
## is the same for every party. Rationale for every number, and the section 1
## measurement that set COMPETENCE_SPAN, SHORTFALL_PENALTY and
## RESIGNATION_THRESHOLD before any of this file was written, is in
## docs/cabinet-model.md; this file is the values, that file is the argument.

# --- Portfolios ------------------------------------------------------------------

## A fixed set, not content -- the same argument opinion_constants.BLOC_KEYS
## makes for its six blocs. Identical to economy_constants.SPENDING_KEYS by
## construction: a portfolio IS a spending line, so effectiveness has something
## concrete to multiply. Kept as its own list rather than a re-export, so
## cabinet.gd names its own vocabulary the way every other *_constants.gd file
## does.
const PORTFOLIO_KEYS := ["health", "education", "defence", "pensions", "infrastructure"]

## How fast affinity falls off with ideological distance between a party's
## SLOT_POSITION and a portfolio's derived position. Equal to
## election_constants.AFFINITY_SIGMA rather than a fourth sigma of its own: both
## measure the same kind of thing -- how far a fixed point in the ideology space
## can drift before the actor at the other end stops caring -- and the
## bloc-to-slot affinity that constant already governs is the one election-model
## borrowed the number from.
const CABINET_SIGMA := 0.8

# --- Competence and effectiveness -------------------------------------------------

## effectiveness(f) = 1 + COMPETENCE_SPAN * (competence(holder, f) - NEUTRAL), so
## a party at competence 0 for a portfolio delivers 1 - SPAN * NEUTRAL of every
## point of spending change and a party at competence 1 delivers
## 1 + SPAN * (1 - NEUTRAL). Section 1 swept 0.6 first and found a 1.77-point
## spread on a representative governing budget -- under the 2.0 pre-commitment.
## 0.75 was the value that cleared it (2.21 points), so this is the measured
## number, not the first guess. See docs/cabinet-model.md.
const COMPETENCE_SPAN := 0.75

## The competence at which effectiveness is exactly 1.0 -- a portfolio held by a
## party of perfectly average skill delivers exactly what the budget number
## says, neither more nor less. Half of the [0, 1] range political competence is
## authored on, so an unauthored or freshly-vacated middle ground is neutral by
## construction rather than by a second constant.
const COMPETENCE_NEUTRAL := 0.5

## Below the worst a held portfolio can score at COMPETENCE_SPAN -- a vacancy is
## not merely a bad minister, it is nobody steering the department at all. At
## COMPETENCE_SPAN = 0.75 the worst held effectiveness is 0.625; this sits
## clearly under it.
const VACANT_EFFECTIVENESS := 0.5

# --- Loyalty and resignation -------------------------------------------------------

## How much being held below entitlement subtracts from loyalty, at full
## shortfall (a party entitled to a portfolio and holding none of them).
## Section 1 measured the resignation signal — unpopularity * (1 - loyalty) —
## against a threshold of 0.20 at this value and found an entitled coalition
## partner under the `managed` regime never crosses it (max 0.021) while a
## shorted one does, in every regime tried (0.057-0.577). See
## docs/cabinet-model.md.
const SHORTFALL_PENALTY := 0.5

## The resignation signal a party must cross before its minister walks.
## Measured, not assumed, alongside SHORTFALL_PENALTY above -- the two are one
## finding, not two independent guesses that happened to agree.
const RESIGNATION_THRESHOLD := 0.20

## Applied through Government.penalise_blocs() when a minister resigns -- the
## same accumulator Article 49.3, a fallen government and a dissolution already
## move, so opinion_constants.INERTIA_RATE and every bound in
## docs/opinion-model.md still apply. Smaller than
## government_constants.FALLEN_BLOC_PENALTY (-0.12): a resigned minister is a
## coalition partner voicing displeasure from inside the government, not the
## government itself falling.
const RESIGNATION_BLOC_PENALTY := -0.06

## Charged on every Cabinet.seat_party() and Cabinet.vacate() call, win or lose. A President who
## reshuffles constantly reads as unstable regardless of whether the new
## assignment is an improvement -- the same "cost on use" shape
## government_constants.FORCE_BLOC_PENALTY gives Article 49.3.
const RESHUFFLE_BLOC_PENALTY := -0.04

## V5.2 b+ R4 (docs/design/v5.2-bplus-spec.md). The grudge a removal writes on the
## party's current leader: above a refusal (0.18), because losing an office is felt
## more than a denied request; below the brief gate (0.45), so one dismissal alone
## never makes an ordinary leader leak; doubled for a principled one it is 0.50,
## past the gate -- the consequence the author asked for, on the person most
## likely to take it personally.
const REMOVAL_GRUDGE := 0.25

## One removal (Dismiss, or a Reassign away) per portfolio per this many months: a
## government that changes the same office twice in a year reads as chaos, and the
## limit keeps the verb from being a free loop. A purge of all five in one month
## stays possible, at five times the price.
const REMOVAL_LIMIT_MONTHS := 12
