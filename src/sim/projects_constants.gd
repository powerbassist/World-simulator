extends RefCounted

## Every tunable in the infrastructure-project model, in one file. Same shape as
## investment_constants.gd, companies_constants.gd and the rest -- model
## parameters, not content, so not in data/. Rationale for every number is
## docs/projects-model.md; this file is the values, that file is the argument.
##
## *** THIS FILE SHIPS NO COST, NO SPEED AND NO STRENGTH CONSTANT, AND THAT IS THE
## SESSION'S SHAPE RATHER THAN AN OMISSION. *** V1.6e had one dial per programme
## (`intensity`) and three constants turning it into a bill, a build rate and a
## trend coefficient. A project is a NAMED THING: what it costs, how long it takes
## and what it is worth are three independent quantities, and a cheap fast small
## project is a different object from an expensive slow large one. Authoring all
## three and deriving none is what makes the content the lever. So what the probe
## bands here is the AUTHORED LADDER in data/project-actions/ -- V1.4b's discipline,
## where not one correction was to the model -- and what is left in this file is
## bounds.
##
## Everything below is therefore a BOUND: a content ceiling that fails a bad file at
## load, or a guard rail on an accumulator. Only PROJECT_POTENTIAL_MAX_PCT is
## reported against a reachable peak, and it is declared a guard rail rather than a
## selector.
##
## A CONCURRENCY CEILING WAS CONSIDERED AND IS NOT HERE. How many projects may run
## at once is set by the `project_count` precondition every authored action carries,
## which makes it CONTENT -- and a model constant duplicating a content gate is the
## clamp-guarding-arithmetic failure V1.6e deleted INVESTMENT_BILL_MAX_PCT_GDP for.
## Recorded rather than left silent, because the next session will reach for one.

# --- Content limits -----------------------------------------------------------

## The ops the effects.project channel takes. `start` puts a named project under
## construction and `abandon` cancels one that is still building.
##
## THERE IS NO `complete` OP AND NO `demolish` OP. Completion is not a player act --
## it arrives when the months run out, which is the whole of what makes this a
## commitment rather than a purchase -- and a finished motorway is not un-built by a
## later president. investment_constants.INVESTMENT_OPS' own absence of `disinvest`,
## one step harder: capital decays and a bridge does not.
const PROJECT_OPS := ["start", "abandon"]

## The terms each op reads, or [] for the op that reads none. A table rather than
## branches in src/core/project_action.gd, for INVESTMENT_OP_TERM's reason: every op
## names its terms or names none, so a third op added without a row here fails to
## load rather than silently ignoring what it was given.
##
## *** THREE TERMS ON ONE OP, WHERE investment_constants.INVESTMENT_OP_TERM ALLOWS
## EXACTLY ONE, AND THE DIFFERENCE IS THE MODEL RATHER THAN A RELAXATION. *** That
## file refuses a second term because an authored cost or rate beside `intensity`
## would be ONE STRENGTH WRITTEN TWICE -- the redundancy tools/coercion_probe.gd
## found between a tariff rate and a measure's severity and deleted. Here there is no
## strength to write twice: this file ships no constant that turns one dial into the
## other two, so duration, price and payoff are three independent facts about a named
## object. Take any one of them away and it would have to become a constant, which is
## the trade this session refuses.
##
## `project_name` is NOT on this list and is required all the same. It is a display
## field -- the noun the diary and the finished list print, where the action name is the
## imperative Public Works puts on a button -- and this list is about QUANTITIES, whose
## whole argument is that none of the three is derived from the others. A name is not a
## strength, so it is checked in src/core/project_action.gd beside `project_id` instead.
const PROJECT_OP_TERMS := {
	"start": ["build_months", "cost_pct_gdp", "potential_growth_pct"],
	"abandon": [],
}

## How long an authored project may take to build, in months.
##
## The floor is what stops a "project" being an executive act with a lag bolted on:
## under two years it is a budget line, which is the thing docs/tiers/v1.md section 6
## already had as INFRA_BETA. The ceiling is two full presidential terms -- past that
## no player who starts one can ever see it finish, and a commitment nobody can
## collect on is docs/scenario-model.md's decorative axis.
const MIN_BUILD_MONTHS := 24
const MAX_BUILD_MONTHS := 120

## What one authored project may cost per year while it is building, in points of
## GDP. A content ceiling and not the ladder: what the ladder is set to is measured
## in tools/projects_probe.gd against what V1.6d and V1.6e left of
## opinion_constants.DEFICIT_SCALE_PP, which is 0.5639 points and not a whole budget.
const MAX_PROJECT_COST_PCT_GDP := 0.60

## What one authored project may add to the trend-growth target on completion, %/yr.
## Below the accumulator's own ceiling by construction, so no single project can
## saturate the register on its own.
const MAX_PROJECT_POTENTIAL_PCT := 0.40

## What an authored project's preconditions may ask about. `project_started` and
## `project_done` are about the project the action NAMES; the rest are the acting
## nation's own state, read exactly as Investment._read_field() reads them.
##
## investment_constants.PRECONDITION_FIELDS with the sector fields swapped for
## project ones, which is the whole difference between the two verbs stated as a
## list: a programme asks whether a sector is already backed, a project asks whether
## this particular thing has already been begun.
const PRECONDITION_FIELDS := [
	"project_started", "project_done", "project_count",
	"deficit_pct_gdp", "debt_to_gdp_pct", "unemployment_pct", "overall_approval_pct",
]

const PRECONDITION_OPS := ["<", "<=", ">", ">=", "=="]

# --- The accumulator's bound --------------------------------------------------

## Hard clamp on what completed projects may accumulate into
## Economy._update_potential_shift()'s TARGET, %/yr.
##
## legislature_constants.POTENTIAL_TARGET_MAX_PCT's exact shape and exact value, and
## the match is the argument rather than a coincidence: a law writing that target and
## a completed project writing this one are the same act -- a one-time decision
## producing a permanent addend -- so the two accumulators bound alike or the model
## says a motorway is worth more than a statute for no reason anybody chose.
##
## *** THIS IS WHY V1.6f ADDS NO THIRD TREND QUANTITY. *** docs/economy-model.md's
## divergence argument is PER QUANTITY, and V1.6e had to add
## investment_constants.SECTOR_TREND_MAX_PCT because its shift reaches
## Economy.trend_pct() directly. This one does not: it reaches the TARGET of a lag
## that economy_constants.SHIFT_MAX_PCT already bounds at +-1.0, so the quantity that
## touches trend is still `potential_shift_pct` and still has exactly one bound. The
## clamp here is on the addend, which is what keeps one act's contribution legible
## rather than what stops the model diverging.
##
## A GUARD RAIL and explicitly not a selector: tools/projects_probe.gd reports it
## against the reachable peak, and if the peak sits ON it then the clamp and not the
## content is setting the number -- docs/economy-model.md's IMPULSE_MAX finding.
const PROJECT_POTENTIAL_MAX_PCT := 1.0
