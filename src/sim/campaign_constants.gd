extends RefCounted

## Every tunable in the campaign model, in one file. Same shape as
## projects_constants.gd, investment_constants.gd and the rest -- model parameters,
## not content, so not in data/. Rationale for every number is
## docs/campaign-model.md; this file is the values, that file is the argument.
##
## *** ONE TUNED CONSTANT AND FOUR BOUNDS, AND WHICH IS WHICH IS THE SESSION'S
## SHAPE. *** CAMPAIGN_WINDOW_MONTHS is the only number here that decides anything
## about how the game plays: it is the length of the run-up, and it is what turns
## "campaign early and pay for months of it" into a decision rather than a formality.
## Everything else is a content ceiling that fails a bad file at load, or a guard rail
## on an accumulator, and each says which it is.
##
## *** THERE IS NO STRENGTH CONSTANT AND NO PRICE CONSTANT. *** projects_constants.gd's
## call inherited whole: what a campaign act costs and what it moves are two
## independent authored facts about a named act, so data/campaign-actions/ is the
## ladder and tools/campaign_probe.gd bands the ladder rather than a coefficient. A
## constant turning one into the other would be one strength written twice --
## tools/coercion_probe.gd's deleted `tariff_rate_pct`, refused a fourth time.
##
## *** AND THERE IS NO CONCURRENCY CEILING. *** How many acts may run at once is the
## `campaign_count` precondition every authored action carries, which makes it CONTENT.
## A model constant duplicating a content gate is the clamp-guarding-arithmetic failure
## V1.6e deleted INVESTMENT_BILL_MAX_PCT_GDP for. Recorded rather than left silent,
## because projects_constants.gd predicted the next session would reach for one.

# --- The window ----------------------------------------------------------------

## How many months before the vote a campaign may run, inclusive of the month of the
## vote itself. THE ONE TUNED CONSTANT V1.7a SHIPPED, re-selected by V2.6b2's
## re-baseline -- and the re-baseline is the story, because the prediction was that
## total reach falling would move the feasible set, and the set did not just move, it
## changed shape.
##
## *** A LEVEL READ, NOT AN EDGE TRIGGER *** (V1.3g's rule, unchanged): is_open()
## compares the clock against ns.next_executive_year / _month and nothing else, so a
## save reloaded inside the window is inside it and there is no second record of when
## the run-up began that could disagree with the first.
##
## *** THE BAND IS ANCHORED ON APPROVAL RATHER THAN INVENTED (V1.7a, unchanged). ***
## A full run-up must be worth at least one point of approval (below that, governing
## swamps it) and at most the poll floor (above that, a campaign substitutes for the
## record). Measured: 1 point of approval = 0.3415 points of vote share, 3.0 points =
## 1.0147.
##
## *** V2.6b2'S RE-BASELINE, AND THE THREE-WAY COUPLING IT EXPOSED. *** Siting the
## effort changed the lever's total reach, and the re-baseline ran twice:
##
##   Under the FIRST anchor -- the fresh factor mean-one in POPULATION weights, the
##   idiom V2.6b1's output price used -- the band came back EMPTY at every window the
##   emulator can express (worst move 0.176 against the 0.3415 edge, table (d)), and
##   the tour clauses and the calibration were jointly infeasible in every saturation
##   strength. The anchor was the defect, not the lever: reach is delivered WHERE THE
##   PLAYER GOES, not where the people are, so the population-weighted idiom does not
##   transfer. The anchor moved to UNIFORM weights over the regions (the recorded
##   reason is Campaign.fresh_factor()'s doc), and the band refit fully.
##
##   With the uniform anchor, EVERY window in [1, 12] passes both edges -- and the
##   window's own criteria alone would maximin-select 5 (39.8 % worst slack). But the
##   tour's recovery clause rides the window (a region visited once must offer >= 0.5
##   of its fresh factor by the window's end), and at window 5 the tour band is EMPTY:
##   the recovery clause needs D <= W - 1 while the reorder clause needs D >= 4.75.
##   WINDOW AND HALF-LIFE ARE ONE SELECTION, not two -- V2.6b2's own finding, and the
##   reason neither constant's comment may be read alone.
##
##   The joint maximin over all three criteria (lower edge, measured accumulator peak,
##   and the tour pair), on the D grid of 0.25 months:
##
##     W  5   tour band EMPTY                     -- refused
##     W  9   D 6.00  worst slack 20.2 % (tour (i))
##     W 10   D 6.50  worst slack 23.0 % (measured peak 0.6927 against 0.90)  <- ships
##     W 11   D 6.50  worst slack ~16 %  (measured peak, interpolated)
##     W 12   D 6.50  worst slack  9.4 % (measured peak 0.8155)
##
##   The fixed point is stable: at window 10 the tour maximin picks D 6.50, and at
##   D 6.50 the window maximin picks 10. W 10 is interior (W 11 interpolates below
##   it), D 6.50 is interior of the tour
##   band [4.75, 9] and of the rail-bound plateau it sits in. THE RAIL IS THE BINDING
##   CRITERION AT THE SHIPPED POINT -- 18.5 % of real slack, the clamp never set the
##   number, and the read is the run's own MEASURED accumulator peak, not the
##   rate x d formula the pre-siting model could use (tools/campaign_probe.gd table
##   (d) prints the measured peak; table (f)'s raw formula is the pre-siting read).
##
## The sweep of record is run with this constant raised to 12, because the probe's own
## clearing behaviour is a level read of it and rows above it are not emulable -- the
## first pass printed them anyway and reported a campaign wiped on the next tick
## beside a non-zero move. V1.6b's "set the constant once and re-run", applied to an
## integer.
const CAMPAIGN_WINDOW_MONTHS := 10

# --- The site -------------------------------------------------------------------

## How many months a region's spoken-to attention takes to halve. THE ONE TUNED
## CONSTANT V2.6b2 ADDS, and it exists because reach-per-day alone makes the capital
## strictly dominant -- docs/siting-model.md section 11's measurement (Paris x6.70
## fresh against Marseille x0.92 under the shipped uniform anchor, a 7.3x margin), the shape this project has killed
## twelve times. The breaker is the sentence data/campaign-actions/campaign.json
## already wrote in prose: whoever has already been spoken to has already been
## spoken to. A meeting month speaks to a region's whole attention (spoken is a
## fraction clamped at 1.0), the month's reach is scaled by (1 - spoken), and the
## fraction decays on this half-life. tools/tour_probe.gd is what set it.
##
## *** THE BAND, FIXED BEFORE THE SWEEP, BOTH CLAUSES IN FACTOR UNITS. ***
##
##   (i) REORDER -- the optimal tour must leave the capital: >= 2 distinct regions
##       and a window total that beats camping. First crosses at D = 4.8 (the
##       month-2 marginal, +0.7 %).
##   (ii) RETURN -- a region visited once and never again must offer >= 0.5 of its
##       fresh factor after the window's remaining months of pure decay. Holds to
##       D = 7.0 exactly, and its LITERAL draft reading -- measured on the tour's
##       actual history -- was REPLACED, because it was incompatible with (i) at any
##       saturation strength: recovery to half of fresh returns Paris an offer that
##       beats the best other site on its own, so a tour satisfying the literal
##       clause never left. The literal clause was a dominance clause wearing a
##       recovery clause's clothes; this one measures the decay's timescale and
##       cannot be gamed by how the tour is played.
##
##   Feasible [4.8, 6.8]. Selected by maximin relative slack, V1.7a's tiebreaker:
##
##   The band is measured AT THE SHIPPED WINDOW and the two constants select
##   TOGETHER (see CAMPAIGN_WINDOW_MONTHS above for the joint table). At window 10
##   the band is [4.75, 9.0] and the maximin on the 0.25-month grid is
##
##     D 6.00   clause (i) +20.2 %   clause (ii) +29.3 %   min +20.2 %
##     D 6.25                  +23.2 %               +26.3 %       +23.2 %
##     D 6.50                  +26.0 %               +23.4 %       +23.4 %  <- ships
##     D 6.75                  +28.6 %               +20.6 %       +20.6 %
##     D 7.00                  +31.0 %               +18.0 %       +18.0 %
##
##   Interior on the grid, and the two slacks cross near D 6.55 -- the probe's own
##   maximin (tools/tour_probe.gd table T5) is the selection, and the measured
##   accumulator peak bounds the WINDOW choice beside it, not this one.
##
## *** THE UNBOUNDED ACCUMULATOR FORM WAS MEASURED AND REFUSED. *** The draft's
## sat += A with discount 1/(1+sat) reorders the tour only at A >= 10 -- and A = 10
## claims one meeting month spoke to 91 % of a region, which is THIS form's
## spoken-to-1.0 claim stated in unbounded units with a second constant and a
## register that never saturates. tools/tour_probe.gd's table (T4) carries the
## corners. The fraction form is the same claim, bounded in [0, 1] by construction
## -- no clamp to set wrong, docs/cycle-model.md's V1.6a argument.
##
## *** THE LEVEL IS THE RE-BASELINE'S INPUT, RECORDED SO IT IS NOT REDISCOVERED. ***
## The uniform anchor (see Campaign.fresh_factor()) leaves the capital at x6.70 of
## the authored rate (France) -- a Paris month accrues 6.7x the authored
## mobilisation, which is why the measured accumulator peak is the criterion the
## window selection reads, and why it BOUND the joint selection at W 10 rather than
## the tour clauses. The re-baseline's tables are docs/campaign-model.md section 18.
const SATURATION_HALF_LIFE_MONTHS := 6.5

# --- Content limits -------------------------------------------------------------

## The ops the effects.campaign channel takes. `start` puts a named campaign effort
## into the field and `stop` takes it out.
##
## *** `stop` EXISTS AND `abandon` DOES NOT, AND THE DIFFERENCE FROM V1.6f IS THE
## MODEL. *** A project can only be abandoned because half a motorway is worth
## nothing; a campaign effort already run has already reached the voters it reached,
## so stopping it keeps what it bought and ends what it costs. That is
## src/sim/investment.gd's `withdraw` rather than src/sim/projects.gd's `abandon`.
##
## It is here at all for docs/defence-model.md's reason: an obligation only the clock
## can close is a permanent monotone charge, and DEPLOYMENT_BILL_MAX_PCT_GDP stops
## being a guard rail. The window does close this one on its own -- but not until the
## vote, and a president who has run out of money in March should not have to lose in
## June to stop paying.
const CAMPAIGN_OPS := ["start", "stop"]

## The terms each op reads, or [] for the op that reads none. A table rather than
## branches in src/core/campaign_action.gd, for PROJECT_OP_TERMS' reason: every op
## names its terms or names none, so a third op added without a row here fails to
## load rather than silently ignoring what it was given.
##
## TWO TERMS, AND NEITHER IS DERIVED FROM THE OTHER. `cost_eur_per_k_pop_month` is a
## standing rate for as long as the effort runs; `mobilisation` is what one month of it
## adds, per bloc. A cheap effort that reaches one bloc and an expensive one that
## reaches three are different objects, exactly as a cheap fast project and an
## expensive slow one are, so both are authored and neither is a function of the other.
##
## V5.2 C6 (docs/design/v5.2-c6-party-campaigns.md): the governing PARTY pays, so the
## price is euros per thousand inhabitants per month rather than points of GDP a year.
## Per inhabitant because every nation is meant to become playable and their parties
## hold EUR 0.1-70 m: a flat euro price would charge Poland what it charges France.
const CAMPAIGN_OP_TERMS := {
	"start": ["cost_eur_per_k_pop_month", "mobilisation"],
	"stop": [],
}

## What one authored campaign effort may cost while it runs, in euros per thousand
## inhabitants per month. A content ceiling set to catch a mistyped digit, not the
## ladder: the dearest authored effort is 26.9 (broadcast, EUR 1.85 m a month in
## France), and the ladder itself is anchored on France's EUR 22.509 m legal ceiling
## for a campaign (the spec's section 2). 60 is a little over twice the dearest.
const MAX_CAMPAIGN_COST_EUR_PER_K_POP_MONTH := 60.0

## What one authored effort may add to one bloc's mobilisation in one month, as a
## shift in the log-odds of that bloc turning out. A content ceiling, set to catch a
## mistyped digit rather than to shape the ladder: the largest authored rate is 0.055.
##
## SIGNED, AND THE SIGN IS WHAT MADE THE LEVER WORK. The first ladder was almost
## entirely positive -- every effort mobilised somebody and depressed nearly nobody --
## and the probe measured its targeting efficiency at 17 % of what perfect targeting
## reaches at the same cap, so no window and no scale could clear the lower edge. Real
## campaigns demobilise as well as mobilise, and once each effort carried a real
## negative side the same cap cleared it. The correction was to the CONTENT and not to
## any constant here, which is V1.4b's discipline arriving a second time.
const MAX_MOBILISATION_PER_MONTH := 0.10

# --- The accumulator's bound ------------------------------------------------------

## Hard clamp on what a whole run-up may accumulate onto one bloc, in the same
## log-odds units.
##
## A GUARD RAIL and explicitly not a selector: tools/campaign_probe.gd reports it
## against the reachable peak, and if the peak sits ON it then the clamp and not the
## content is setting the number -- docs/economy-model.md's IMPULSE_MAX finding, and
## the failure this project has now recorded in five places.
##
## IT WAS BINDING AT 0.60 AND THE PROBE SAID SO, and what binding did here was worse
## than usual: once the accumulator saturates, a LONGER run-up is strictly worse,
## because it costs more months of bill for exactly the same reach. A guard rail that
## binds was not merely setting the number, it was INVERTING the timing decision the
## whole lever exists to pose. At 0.90 the worst stack two efforts can reach over a
## full window is 0.6800 -- slack by 0.2200, and the content is the lever again.
##
## THE TURNOUT IT PRODUCES NEEDS NO CLAMP OF ITS OWN, which is the point of working
## in log-odds at all: Campaign.turnout_of() is bounded strictly inside (0, 1) BY
## CONSTRUCTION, so there is no value of this constant that can produce a turnout
## above one or below zero. docs/cycle-model.md's V1.6a argument -- a bound with no
## number to set wrong is stronger than a clamp.
const MOBILISATION_MAX := 0.90

# --- Preconditions -----------------------------------------------------------------

## What an authored campaign action's preconditions may ask about.
##
## THERE IS NO `campaign_open` FIELD, AND ITS ABSENCE IS DELIBERATE. Whether the
## window is open is a property of the clock, not an authorial choice, so
## Campaign.available() refuses every action outside it structurally --
## src/sim/projects.gd's argument for checking op legality in code rather than
## trusting the content to say `project_started == 0`. A content file that had to
## remember the window would be a file that could forget it.
##
## `months_to_election` IS here, because "only in the last two months" is a real
## authorial choice about an act that would be absurd earlier.
const PRECONDITION_FIELDS := [
	"months_to_election", "campaign_count",
	"deficit_pct_gdp", "debt_to_gdp_pct", "unemployment_pct", "overall_approval_pct",
]

const PRECONDITION_OPS := ["<", "<=", ">", ">=", "=="]
