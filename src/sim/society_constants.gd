extends RefCounted

## Tuned constants for the delivery layer — V1.5a. The model, and the justification
## for every number here, is docs/society-model.md.
##
## Every value below was set by tools/society_probe.gd against a band AND a
## tiebreaker fixed BEFORE the sweep ran. That is V1.4c's lesson written into the
## file rather than into a doc: DIVIDEND_YIELD's pre-committed band passed three of
## four rows and chose nothing, because a band that measures whether a line is
## READABLE is a different question from whether the number is RIGHT. So each
## constant here names the existing constant its tiebreaker is a ratio against, and
## anything that could not clear its band was DELETED rather than left unused --
## AGREEMENT_ACCEPT_MIN's treatment at V1.3e and the day budget's at U6a.


# --- The outcome stock --------------------------------------------------------

## Which spending lines carry an outcome stock. A REGISTRY, not a mode flag, and
## the same shape src/ui/map_layers.gd's LAYERS takes: a later session adds a line
## by adding an entry here, and nothing else in this file is keyed to the count.
##
## THE EXCLUSIONS ARE THE DESIGN, and they are why this list has one entry rather
## than five. docs/tiers/v1.md §5 asks for "healthcare and education quality as
## outcomes of spending" -- and of the five spending lines, three already have an
## outcome stock under another name:
##
##   defence         -> military_capability      (V1.3g, src/sim/defence.gd)
##   education       -> potential_shift_pct      (S4, economy.gd's EDU_BETA)
##   infrastructure  -> potential_shift_pct      (S4, economy.gd's INFRA_BETA)
##
## So a second education stock on the same input would be that lever twice, which
## is docs/companies-model.md's V1.4b collision in a new place. `pensions` is
## excluded for a different reason and a temporary one: pension adequacy is spend
## per DEPENDENT, and the dependent count is V1.5b's. It joins by becoming an entry.
##
## tests/test_society.gd reads this list and fails if `education`, `defence` or
## `infrastructure` appears in it -- the refusal is the design, the way
## src/core/law.gd's _extract_company() refuses a firm id.
const QUALITY_KEYS := ["health"]

## Fraction of the gap to target closed per month.
##
## BAND, fixed before the sweep: at a reachable sustained spending change of
## +-1.0 point of GDP, the stock must cover a readable fraction of the distance
## inside ONE 60-month presidential term -- taken as 40-90 %. Below that the player
## never sees the consequence of their own budget; above it the stock is not a stock
## and the delta term already models it.
##
## TIEBREAKER, also fixed before the sweep, because the band above admits a range:
## the ratio against defence_constants.CAPABILITY_CONVERGENCE, which is 0.02 and is
## the only other stock of this exact shape in the project. Take the passing value
## NEAREST it; a value differing by more than 2x has to be justified by something
## the probe measured, not by a story about how schools differ from armies.
##
## Measured, table (b): the band passes 0.01 (45.3 % of the gap in a term) and 0.02
## (70.2 %), and fails 0.04 (91.4 %) and 0.08 (99.3 %). Two rows pass, so the band
## chooses nothing on its own -- V1.4c's finding, and the reason a tiebreaker was fixed
## in advance. The tiebreaker then chooses 0.02 outright, at a ratio of exactly 1.00
## against CAPABILITY_CONVERGENCE. This is the one constant of the three whose
## pre-committed pair worked as designed.
const QUALITY_CONVERGENCE := 0.02

## Bounds on the stock, in points of GDP. The floor is a service that has ceased to
## exist; the ceiling is above any authored spending line (France's health is the
## roster's largest at 11.0) so it is a guard rail rather than a lever, which is
## defence_constants.CAPABILITY_MAX's treatment.
const QUALITY_MIN := 0.0
const QUALITY_MAX := 30.0


# --- Corruption, the delivery factor -----------------------------------------

## Signed accumulated corruption, clamped to +-CORRUPTION_MAX. Written by
## Legislature.apply() through effects.society and by nothing else in the project --
## `regulation_burden`'s shape exactly, so it adds no accumulator and no machine.
##
## SYMMETRIC, and the sign is the whole of anti-corruption. This is V1.4b's
## deregulation argument transferred verbatim: there is no repeal verb in this
## project and a `once` law never returns, so a [0, MAX] clamp would make corruption
## a permanent monotone charge -- docs/defence-model.md's named failure -- and an
## anti-corruption law would be INERT at corruption 0, which breaks V1.3f's own
## property that no law on the list does nothing. Negative corruption is a
## cleaner-than-baseline administration, and it raises delivery above 1.0 rather
## than merely failing to lower it.
##
## Set equal to companies_constants.REGULATION_BURDEN_MAX so that "saturated" means
## the same thing across the two registers a law can write.
const CORRUPTION_MAX := 1.00

## How much a point of corruption degrades DELIVERY -- what a unit of spending
## actually buys in outcome.
##
## It multiplies the STOCK'S TARGET rather than the satisfaction delta, and that is
## the session's second call rather than an implementation detail. The row says
## corruption degrades "policy effectiveness", which names Cabinet.effectiveness()
## -- but that function multiplies the DELTA only, deliberately (see opinion.gd's
## own comment: "A player who never touches this spending line is untouched by the
## whole cabinet system"). A corruption factor there would cost a do-nothing player
## EXACTLY ZERO, which is free to precisely the player most likely to deserve it.
## Degrading the target instead means a corrupt state's hospitals decay at unchanged
## spending, which is what the bullet was reaching for.
##
## BAND, fixed before the sweep: a saturated corruption level must move the headline
## approval figure past the +-3.0 noise floor poll_noise.gd imposes. Anything less
## is decorative and the constant is deleted rather than tuned until it looks alive.
##
## TIEBREAKER, fixed before the sweep: the ratio against
## cabinet_constants.VACANT_EFFECTIVENESS, which is 0.50. A factor that degrades
## delivery FURTHER than an empty ministry claims corruption is worse than having no
## minister at all, which is a claim needing an argument rather than a sweep -- so
## DELIVERY_MIN below may not go under 0.50, and that bounds this constant at 0.50
## against a saturated register.
##
## Measured, table (d): the KILL SWITCH CLEARED, and comfortably -- a saturated
## register moves the headline -4.55 at 0.10, -6.34 at 0.20, -8.32 at 0.30 and -12.72
## at 0.50, so all four candidates pass the +-3.0 band.
##
## WHICH MEANS THE PRE-COMMITTED TIEBREAKER WAS A BOUND AND NOT A SELECTOR. Every
## candidate satisfies beta x MAX <= 0.50, so naming it in advance was still not
## enough -- V1.4c's failure repeating inside the session written to avoid it, and the
## sharpest thing this probe found. A tiebreaker can be pre-committed AND not select.
##
## What selected, in two parts, both criteria this session had already established and
## neither reverse-engineered from the rows:
##
##   (i)  ONE law's corruption must be legible on a BLOC ROW, not on the headline --
##        table (c) had just shown a single spending issue cannot reliably carry a
##        headline price. 0.10 (-1.88) and 0.20 (-2.55) fail; 0.30 (-3.29) passes.
##   (ii) The saturated value must leave DELIVERY_MIN strictly SLACK. 0.50 pins it
##        exactly at 0.500, which is the clamp-sets-the-number failure this project has
##        named five times, so 0.50 fails.
##
## Exactly one row passes both. An earlier version of (i) asked for the headline rather
## than a bloc row and chose 0.50, on the mistaken premise that a saturated register was
## unreachable in play -- it is not: emergency_procurement_powers is repeatable on a
## 48-month cooldown, so three passes inside fourteen years reach the clamp.
const CORRUPTION_DELIVERY_BETA := 0.30

## Bounds on the delivery factor. The floor is VACANT_EFFECTIVENESS, for the reason
## the tiebreaker above gives; the ceiling is its reflection, so a spotless
## administration buys as much extra as a saturated one loses. Neither binds at
## CORRUPTION_MAX x CORRUPTION_DELIVERY_BETA = 0.30, which makes both guard rails
## rather than levers -- and that slackness is measured rather than assumed, the way
## docs/defence-model.md measured its bill clamp.
const DELIVERY_MIN := 0.50
const DELIVERY_MAX := 1.50
