extends RefCounted

## Every tunable in the business cycle, in one file. V1.6a, the first session of the
## V1.6 block. The model and the argument for every number is docs/cycle-model.md;
## this file is the values.
##
## THERE ARE THREE NUMBERS HERE AND ONLY ONE OF THEM IS SWEPT, which is the shape the
## session was designed for rather than an accident: the LEVEL of the cycle is a
## pacing decision this game makes (CYCLE_AMPLITUDE_PCT), the SPREAD across the ten
## nations is a measured fact that lives in data/nations/*.json, and the PERIODS are
## set by argument because no band in this model can discriminate them. See below.

# --- Amplitude ----------------------------------------------------------------

## Standard deviation of the cycle impulse, in points of annualised growth, for a
## nation of exactly average volatility (`cycle_amplitude_rel` = 1.0).
##
## This is a LEVEL and not a measurement, and the distinction is the reason it is
## swept rather than imported. The World Bank series says a European economy's real
## GDP growth has a standard deviation of 1.26 (France) to 2.70 (Luxembourg) points
## once the pandemic is excluded -- but this model already generates deviation from
## trend through the output gap, the demand impulse and five other addends, so
## injecting the full historical figure here would be that variance counted twice.
## What is measured is the RATIO between the ten; what is chosen is the scale.
##
## SET BY A CALIBRATION FIT AND NOT BY ITS BANDS, and the reason is the session's
## sharpest finding. The two pre-committed bands -- readable past opinion's +-3.0
## poll-noise floor, and never reaching GROWTH_MIN/MAX_PCT -- were joined by a third
## when the second turned out to be a bound, and the resulting interval is EMPTY at
## every candidate on a grid refined to 0.05 and widened to 4.00. Readable needs about
## 1.9; a France no more volatile than the real France allows at most about 1.7.
##
##     A BUSINESS CYCLE OF THE SIZE FRANCE ACTUALLY HAS MOVES APPROVAL BY ~2.8 POINTS,
##     UNDER THE +-3.0 POLL FLOOR, AND CANNOT BE LIFTED OVER IT WITHOUT MAKING FRANCE
##     MORE VOLATILE THAN FRANCE IS.
##
## Recorded rather than traded against -- docs/defence-model.md's deployment that could
## not clear its own floor -- and it is the right way round twice over. The floor is a
## property of src/ui/poll_noise.gd, which fuzzes APPROVAL because a poll is published;
## growth, GDP and unemployment are printed exactly, so the cycle's primary readout
## carries no noise and only its secondary one does. And that IS the mechanic: section 6
## asks for recessions arriving whether or not deserved, the essential property is
## ATTRIBUTION rather than surprise, and a slump unmistakable in the figures but
## ambiguous in the polls is exactly a president who cannot prove it was not their fault.
##
## So the value is fitted rather than banded: the candidate whose realised annual-growth
## standard deviation over 168 months of `hands_off` is nearest France's own measured
## 1.262. At 1.70 the model returns **1.260**, a miss of 0.0015. Interior to the grid
## with candidates failing on both sides, and -- unlike a band edge -- it CONVERGES
## under refinement instead of moving, which is what V1.5b's and V1.5c's diagnostics are
## both really asking for. tools/cycle_probe.gd table (a).
const CYCLE_AMPLITUDE_PCT := 1.70

## Share of the cycle's VARIANCE that is common to all ten nations rather than
## idiosyncratic. Applied as sqrt(share) and sqrt(1 - share) so the total standard
## deviation is exactly CYCLE_AMPLITUDE_PCT at every value -- the factor-model form,
## which is what makes this number mean what its name says instead of also being a
## second amplitude control.
##
## MEASURED, NOT SWEPT, AND THE SWEEP THAT WAS PLANNED FOR IT WAS DELETED. The design
## pass had this as the session's second swept constant with a two-sided band -- the
## cycle must cross borders, and must not arrive from abroad harder than it arrives at
## home. Both bands are still checked, in tools/cycle_probe.gd table (b), but they are
## a VERIFICATION and not a selector, because this quantity does not need one: the
## World Bank series that supplies `amplitude_rel` also says what the common share IS.
##
## Over 1990-2024 with 2020-21 excluded, demeaning each of the ten and taking the
## cross-nation mean as the common factor: var(common) / mean var(nation) = **0.619**.
## The independent cross-check is the mean pairwise correlation of the same ten series,
## **0.633** -- two different statistics of the same data, agreeing to 0.014, which is
## the two-harnesses discipline docs/decision-log.md's V1.5c entry spent a session on,
## applied to a measurement rather than to a probe.
##
## A sweep would have produced a number in the same region and called it tuned. This is
## the deletion V1.5c's rule asks for read in the useful direction: *a constant set by
## argument is not a failure; a constant set by argument that claims to have been swept
## is.* Reproduce it with `python tools/import_data.py`, which prints it.
const CYCLE_COMMON_SHARE := 0.62

# --- Periods ------------------------------------------------------------------

## Three frequency bands, in months, one term drawn from each. SET BY ARGUMENT AND
## NOT SWEPT, and this file says so rather than dressing the argument as a
## measurement -- docs/decision-log.md's V1.5c entry: *a constant set by argument is
## not a failure; a constant set by argument that claims to have been swept is.*
##
## The argument is that no band this model can express discriminates a period. Every
## observable a probe could measure -- peak growth, trough unemployment, whether a
## strike fires -- responds to the AMPLITUDE and to the fraction of a 168-month run a
## period fits into, and a sweep over periods would be reading the run length back.
## The literature does discriminate them, so the literature is what is used: a short
## inventory cycle of 2-4 years and a long investment cycle of 8-11 years, with a
## medium band between.
##
## Three bands rather than one period, because one sine is a metronome. Drawn per
## nation from separated bands rather than from one wide range, so the three terms
## can never collide into a near-single frequency for an unlucky nation -- which is a
## content guarantee rather than a hope.
const CYCLE_PERIOD_BANDS := [
	[29, 47],    # inventory: ~2.5-4 years
	[59, 83],    # ~5-7 years
	[97, 131],   # investment: ~8-11 years
]

## Number of sine terms per wave. Not independent of the table above -- it IS the
## table's length, kept as a named constant only because the normalisation below
## needs it as a float and `CYCLE_PERIOD_BANDS.size()` in an arithmetic expression
## reads worse than the name does. tests/test_cycle.gd asserts the two agree.
const CYCLE_TERMS := 3

## The seed the COMMON component is drawn with, in place of a nation id. Any string
## no nation id can equal; the leading underscores are the guarantee.
const CYCLE_COMMON_SEED := "__common"

# --- The epoch ----------------------------------------------------------------

## The month the wave is measured from, and the reason it is a CONSTANT rather than
## something captured at new-game.
##
## docs/decision-log.md's V1.5c entry records that `tools/balance_probe.gd` and
## `tests/test_balance.gd` both set `state.year` AFTER GameState.new_game(), so a
## reference captured at init reads year 0 and every elapsed time derived from it is
## wrong by two millennia. That is what killed V1.5c's own stateless
## `inequality_deviation()` and pushed the Gini drift onto an accumulator. An epoch
## has nothing to capture, so it survives the harness where a captured baseline does
## not -- and it keeps this module free of any state at all, which is the whole
## design.
##
## It says something true as well as convenient: THE CYCLE IS A PROPERTY OF THE
## WORLD, NOT OF THE SAVE. Europe's economy does not restart its cycle because
## somebody began a game. `src/core/clock.gd` starts every game at 2026-01 and no
## scenario moves it, so at the canonical start the epoch coincides and the wave is
## exactly 0.0 -- and a later start date would begin mid-cycle, which is the correct
## behaviour rather than a bound to apologise for.
const CYCLE_EPOCH_YEAR := 2026
const CYCLE_EPOCH_MONTH := 1

# --- Content bounds -----------------------------------------------------------

## Bounds on the per-nation `imported.cycle.amplitude_rel` at load, checked in
## src/core/nation.gd. Not a tuning dial: a ratio outside this is a broken import
## rather than an unusually volatile country, and the measured roster spans
## 0.689 (France) to 1.475 (Luxembourg).
const AMPLITUDE_REL_MIN := 0.20
const AMPLITUDE_REL_MAX := 5.00


## Peak absolute value of the unit wave, as a multiple of its standard deviation.
##
## DERIVED, not tuned, which is why it is a function rather than a fourth const. The
## wave is a sum of CYCLE_TERMS unit sines normalised to unit standard deviation, so
## its extreme is `CYCLE_TERMS / sqrt(CYCLE_TERMS / 2)` and nothing about it is a
## choice. docs/economy-model.md's divergence argument is per-quantity and a new
## addend in the growth sum owes it a bound; this supplies one that cannot be set
## wrong, where coercion, companies and unrest each carry a clamp that can.
static func max_impulse_pct() -> float:
	return CYCLE_AMPLITUDE_PCT * float(CYCLE_TERMS) / sqrt(float(CYCLE_TERMS) / 2.0)
