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
## vote itself. THE ONE TUNED CONSTANT IN THIS FILE.
##
## *** A LEVEL READ, NOT AN EDGE TRIGGER, AND THAT IS WHY THERE IS NO "THE CAMPAIGN
## HAS OPENED" FLAG ANYWHERE IN THE REGISTER. *** docs/defence-model.md's V1.3g rule:
## the alliance obligation opens itself by comparison against live state rather than
## by an event that fires once, because nothing in this project ever lifts a flag it
## has set. Campaign.is_open() compares the clock against ns.next_executive_year /
## _month and nothing else, so a save reloaded inside the window is inside it, a
## dissolution that moves the date moves the window with it, and there is no second
## record of when the run-up began that could disagree with the first.
##
## *** THE BAND IS ANCHORED ON APPROVAL RATHER THAN INVENTED, AND THE FIRST VERSION OF
## IT WAS NOT. *** tools/campaign_probe.gd's first pass asked for "at least 0.50 points
## of vote share" -- a number picked because it sounded like a margin -- and refused
## every candidate against it without ever saying whether 0.50 was the right ruler. It
## was not. The honest ruler is the only other thing that moves Elections.vote_share()
## at all: approval, through the `pull` term. Measured (probe table (c4)):
##
##   1 point of approval  = 0.3415 points of vote share, 0.4512 of the winning GAP
##   3 points (the poll floor) = 1.0147 / 1.3404
##
## So a full run-up must be worth at least one point of approval -- below that,
## governing swamps it and the lever is decorative -- and at most the poll floor, above
## which a campaign substitutes for the record and a president buys back a term they
## had lost. The upper edge is POLL_FLOOR_PTS because a swing smaller than the
## published polls can resolve is exactly the swing a campaign may own: the player has
## spent the term reading blurred figures, and the campaign decides the race those
## figures could not call.
##
## *** SELECTED BY MAXIMIN SLACK, WHICH IS THIS SESSION'S ADDITION TO THE TIEBREAKER
## RULES. *** The feasible set is [7, 10]: below 7 the authored ladder cannot reach the
## lower edge, above 10 the reachable stack passes MOBILISATION_MAX. V1.5d says neither
## edge selects when two model criteria bound from opposite sides and the interior
## governs -- but "the interior of a passing LIST" is a statement about the grid, and
## V1.5b's whole finding is that a grid must never choose. The interior of the FEASIBLE
## REGION needs none: take the candidate whose WORST relative slack is largest.
##
##   d=7   lower-edge slack  5.8 %   guard-rail slack 33.9 %   min  5.8 %
##   d=8                    23.1 %                    24.4 %       23.1 %   <- ships
##   d=9                    40.3 %                    15.0 %       15.0 %
##   d=10                   57.3 %                     5.6 %        5.6 %
##
## Stable under refinement (both slacks are continuous in d), stable under widening (a
## candidate outside the region has negative slack), and it degrades correctly: where
## one criterion is far looser than the other it returns the edge of the tighter one,
## which is what a bound should do.
##
## The sweep of record is run with this constant raised to 12, because the probe's own
## clearing behaviour is a level read of it and rows above it are not emulable -- the
## first pass printed them anyway and reported a campaign wiped on the next tick beside
## a non-zero move. V1.6b's "set the constant once and re-run", applied to an integer.
const CAMPAIGN_WINDOW_MONTHS := 8

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
## TWO TERMS, AND NEITHER IS DERIVED FROM THE OTHER. `cost_pct_gdp` is a standing
## rate for as long as the effort runs; `mobilisation` is what one month of it adds,
## per bloc. A cheap effort that reaches one bloc and an expensive one that reaches
## three are different objects, exactly as a cheap fast project and an expensive slow
## one are, so both are authored and neither is a function of the other.
const CAMPAIGN_OP_TERMS := {
	"start": ["cost_pct_gdp", "mobilisation"],
	"stop": [],
}

## What one authored campaign effort may cost per year while it runs, in points of
## GDP. A content ceiling and not the ladder: where the ladder sits is measured in
## tools/campaign_probe.gd against what V1.6d, V1.6e and V1.6f left of
## opinion_constants.DEFICIT_SCALE_PP, which is 0.2039 points and not a whole budget.
## The dearest pair the concurrency gate allows costs 0.1750, inside it by 0.0289.
const MAX_CAMPAIGN_COST_PCT_GDP := 0.20

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
