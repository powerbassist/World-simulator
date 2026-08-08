extends RefCounted

## Tuned constants for the demography layer -- V1.5b. The model, and the
## justification for every number here, is docs/demography-model.md.
##
## THERE IS EXACTLY ONE TUNED CONSTANT IN THIS FILE, and that is the session's
## central call rather than an accident of scope. The age structure, its slope, the
## participation rate and the population growth rate are all MEASURED, per nation,
## from World Bank series tools/import_data.py already had on disk -- so they are
## content, they differ by measurement rather than by authoring, and they need no
## band. Everything else below is a guard rail whose slack is measured, which is
## docs/defence-model.md's treatment of its bill clamp.
##
## The alternative shipped nothing extra and cost a constant: a cohort machine with
## births from fertility and deaths from life expectancy needs a convergence rate,
## and it re-derives -- badly -- a number the World Bank publishes directly. A
## uniform 15-64 bucket predicts Luxembourg ages fastest of the ten; measured, it
## ages slowest. See docs/demography-model.md section 2.


# --- The migration lever ------------------------------------------------------

## Signed accumulated migration stance, clamped to +-MIGRATION_STANCE_MAX. Written by
## Legislature.apply() through effects.society and by nothing else in the project --
## society_constants.CORRUPTION_MAX's shape exactly, one register later.
##
## SET EQUAL TO CORRUPTION_MAX and companies_constants.REGULATION_BURDEN_MAX, so that
## "saturated" means the same thing across all three registers a law can write. Not
## swept: this is a units decision, not a tuning one, and V1.5a made the identical
## call for the identical reason.
##
## SIGNED, and the sign is what makes ageing admissible at all. Every nation's
## dependency ratio rises forever, there is no retirement-age or fertility lever in
## this game, and nothing in this project ever lifts a charge the player did not
## open -- so a one-directional migration stance would leave ageing as the permanent
## monotone charge docs/defence-model.md names, with no verb able to close it. A
## positive stance is an opening, a negative one a tightening, and
## tools/demography_probe.gd's band (T1-ii) asks whether the open direction can hold
## the ratio flat rather than merely slow it down.
const MIGRATION_STANCE_MAX := 1.00

## Dependent share removed per year at a saturated stance, AS A FRACTION of the
## population, split between the young and the old in proportion to their sizes.
##
## A FRACTION AND NOT POINTS, and the distinction is not pedantry: the first version
## of this constant was documented in points and applied to fractions, which made a
## saturated tightening add thirty points of dependent share a year and drove France
## past the working-share floor inside sixteen months. tests/test_demography.gd's
## sum-to-1.0 assertion caught it. The comparable figure is the measured ageing slope
## itself -- France's old share rises 0.00366 a year in these units -- so a lever able
## to hold the ratio flat lives in the same third decimal place, not the first.
##
## Migrants arrive of working age, so the lever raises the working share -- and
## because that share is the residual 1 - young - old, raising it IS lowering the
## other two. There is no separate arrivals count and no second population term: a
## migration figure added to `population` as well would be one story told twice, and
## the labour force already picks the composition change up through working_share().
##
## BAND, two parts, both fixed before the sweep (docs/demography-model.md section 7):
##   (i)  READABLE. A saturated stance held for one 60-month term must move the
##        `pensioners` bloc approval row past the +-3.0 poll_noise floor. The BLOC
##        ROW and not the headline, because tools/society_probe.gd table (c) already
##        established that a single spending issue cannot reliably carry a headline
##        price -- a finding this session declines to re-learn.
##   (ii) CLOSABLE. A saturated stance must hold the dependency ratio's deviation at
##        or below 0.0 across the same 60 months for at least the median nation. A
##        lever that only damps an unstoppable ratchet does not discharge the
##        argument MIGRATION_STANCE_MAX above rests on, and no value fixes that.
##
## TIEBREAKER, fixed before the sweep: a ratio against
## society_constants.CORRUPTION_DELIVERY_BETA read through their COMMON LANDING SITE --
## both are law-written accumulators reaching the same quality stock, the only
## genuinely commensurable pair in the project -- requiring STRICTLY that a saturated
## migration stance is worth less on the pensions row than a saturated corruption
## register is on health's, and then taking the LARGEST passing candidate.
##
## AND IT WAS ITSELF A BOUND, WHICH IS THE THIRD TIME THIS PROJECT HAS MADE THAT
## MISTAKE AND THE SECOND INSIDE A SESSION THAT QUOTES THE RULE AGAINST IT.
## docs/decision-log.md's V1.5a rule says a tiebreaker must strictly ORDER the rows
## surviving the band, and this one does -- by size. What it does not do is terminate:
## both bands above are one-sided MINIMUMS, so every candidate above the threshold
## passes and "largest" returns the top row of whatever grid was swept. The first grid
## stopped at 0.010, 0.010 was the only passing row AND the largest candidate, and
## widening the grid moved the answer to 0.016. The RANGE was choosing the constant.
##
## THE RULE IS THEREFORE EXTENDED, and the extension is this session's contribution to
## the discipline: a tiebreaker must strictly order the survivors AND ITS ANSWER MUST
## NOT MOVE WHEN THE CANDIDATE RANGE IS WIDENED. That is checkable in advance -- widen
## the grid and re-read -- where "is it a strict ordering?" is not.
##
## The corrected selector is forced rather than chosen: when both bands are minimums,
## the SMALLEST passing candidate is the least-invasive lever that clears them, and it
## is stable under widening by construction. The corruption reference stays, demoted to
## what it always was -- a ceiling, and a slack one at -14.35.
##
## Measured, table (T1), with the health elasticity already deleted:
##
##   beta     pensioners row   ratio t0 -> t60   band
##   0.0060       -2.03        0.3611 -> 0.3499  fail (i)
##   0.0080       -2.75        0.3611 -> 0.3353  fail (i)
##   0.0090       -3.12        0.3611 -> 0.3281  PASS   <- smallest passing
##   0.0100       -3.49        0.3611 -> 0.3211  PASS
##   0.0120       -4.22        0.3611 -> 0.3074  PASS
##   0.0160       -5.70        0.3611 -> 0.2811  PASS
##
## The chosen value is INTERIOR to the grid -- two candidates fail below it and three
## pass above it -- which is the evidence the correction did something. Full table and
## the method note: docs/demography-model.md.
const MIGRATION_SHARE_BETA := 0.009


# --- Guard rails, not levers --------------------------------------------------

## Bounds on the two live shares, as fractions. Wide enough that no roster nation
## approaches them in a fourteen-year run -- the roster's largest old share is Italy
## at 0.246 drifting to 0.286 -- so they bound the MODEL against a broken import
## rather than shaping any playable outcome. Their slack is measured, table (e).
const SHARE_MIN := 0.02
const SHARE_MAX := 0.60

## Floor on the residual working share. Separate from src/core/nation.gd's
## MIN_WORKING_PCT, which validates CONTENT at load: this one bounds the DRIFT, and
## both are needed because a file can be valid on the day it is written and still
## age past the floor inside a long run. working_share() is a denominator in
## dependency_ratio() and again in labour_force(), so it may not reach zero.
const WORKING_SHARE_MIN := 0.20

## Bounds on the dependency factor -- the ratio of a nation's current old-age
## dependency to its own starting value, which is what Society.quality_target()
## divides by. Exactly 1.0 at new game for all ten nations by construction, so the
## bounds are guard rails on a quantity that starts at neither of them.
##
## The floor is not 0.0 and that matters: it is a DIVISOR, so a factor near zero
## would send a quality target to infinity and the clamp inside quality_target()
## would then be the thing setting the number. Bounding the divisor instead is what
## keeps that clamp slack.
const DEPENDENCY_FACTOR_MIN := 0.50
const DEPENDENCY_FACTOR_MAX := 2.50

# Measured slack, table (e), over 168 months at a saturated stance in both directions
# across all three playable nations -- docs/defence-model.md's bill-clamp discipline,
# and the answer to the clamp-sets-the-number failure this project has named five times:
#
#   share ceiling    0.3245 against SHARE_MAX          0.6000
#   working floor    0.5007 against WORKING_SHARE_MIN  0.2000
#   factor ceiling   1.7791 against DEPENDENCY_FACTOR_MAX 2.5000
#
# All three are guard rails rather than levers, and none of them is what sets any
# number the player sees.
