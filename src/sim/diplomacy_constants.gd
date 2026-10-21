extends RefCounted

## Every tunable in the diplomacy model, in one file. Same shape as
## legislature_constants.gd, opinion_constants.gd and the rest -- model
## parameters, not content, so not in data/. Rationale for every number is
## docs/diplomacy-model.md; this file is the values, that file is the argument.
##
## Every number below was set provisionally and then checked by
## tools/diplomacy_probe.gd BEFORE any action content was authored -- the
## measurement docs/diplomacy-model.md records. A drift rate that made the
## reachable range too narrow for a precondition to bite was named in advance
## as a MODEL decision, not a tuning one.

# --- Scale ---------------------------------------------------------------------

## Relations run 0-100, the same readable scale approval uses, rather than the
## [-1, +1] the ideology axes and the bloc offsets use. The player reads this
## number off a panel and a law's preconditions test it the way they test
## debt_to_gdp_pct -- a number the panel shows and a precondition compares
## should be in the units the player thinks in.
const RELATIONS_MIN := 0.0
const RELATIONS_MAX := 100.0

# --- The derived resting value ---------------------------------------------------

## Where a pair's relations settle if nobody does anything, derived from the two
## inputs docs/data-sources.md can actually supply rather than from 45 authored
## numbers it cannot. Deliberately NOT a third input: size asymmetry. Under a
## symmetric pair key a size disparity has nowhere honest to go -- the pair's
## single number cannot express "the smaller partner has less leverage" -- so it
## belongs to V1.3b's read-time trade weighting instead. See
## docs/diplomacy-model.md.
##
## Two neighbours in the same bloc rest at 68; two nations with neither tie rest
## at 45. That spread is what an action has to be legible against.
const REST_BASE := 45.0

## Both nations in the EU. Live rather than degenerate: GBR and CHE are outside
## it, so eight of the ten share it and two do not.

## A shared land border, from Nation.neighbours. Smaller than co-membership
## because proximity cuts both ways -- neighbours cooperate more AND have more
## to argue about -- so it moves the resting value less than an institution
## whose whole purpose is alignment.
const SHARED_BORDER_BONUS := 8.0

# --- Drift -----------------------------------------------------------------------

## Monthly pull back toward the resting value, as a fraction of the remaining
## gap. Same exponential-approach form opinion_constants.gd's INERTIA_RATE uses
## -- no new functional shape in the project for this.
##
## An order of magnitude slower than INERTIA_RATE (0.25, a ~2.4-month half-life).
## Approval is a mood and should decay inside a season; a diplomatic
## relationship is not, and one that reverted before the next election would be
## the decorative-axis failure docs/scenario-model.md caught for authored
## approval. 0.02 is a ~34-month half-life: a term-and-a-half.
const DRIFT_RATE := 0.02

## The band inside which a pair counts as having returned to its resting value,
## for the probe's recovery measurement. Points.
const RESTING_EPSILON := 1.0

# --- Action content limits -------------------------------------------------------

## The only fields a diplomatic action's preconditions may test. "relations" is
## the pair score against the action's TARGET; every other entry is the acting
## nation's own state, read the same way legislature_constants.gd's
## PRECONDITION_FIELDS are. An unknown field is a startup error, not a silently
## false predicate.
## The three measure fields are V1.3c's, the third piece of pair state and the
## first DIRECTED one: they read the acting nation's own measure against this
## target, not the target's against them. That is what lets impose and lift gate
## themselves generically, the way agreement_active does for enter and exit, with
## no coercion knowledge in src/sim/diplomacy.gd at all.
##
## THREE rather than one, and the content is what forced it. With only
## "measure_active", every lift verb is available against any measure -- so
## lift_sanctions would clear a tariff, because the register knows the pair is
## coerced and the precondition could not ask HOW. One measure per directed pair
## makes "is anything in force" the right gate for imposing and the wrong one for
## lifting.
##
## The five defence fields are V1.3g's, over its two registers. FOUR of them are
## about the pair for the same reason the three measure fields are three: with only
## "deployment_active" a withdraw verb would close an obligation the player is not
## allowed to close, because the register knows a commitment exists and the
## precondition could not ask WHOSE IDEA IT WAS. `pact_count` is the odd one and is
## not about a pair at all -- it is the agenda's brake on signing with everybody,
## authored in the content as `pact_count < N` rather than enforced by a constant in
## src/sim/, which is the data-not-code rule docs/engine-decision.md states first.
##
## `met_recently` is V2.4a's, and it is the reader half of the meeting window: 1.0
## when a state visit either way across the pair happened within
## MEETING_WINDOW_MONTHS, 0.0 otherwise. It rides the precondition machinery rather
## than arriving as a new boolean on the action because that is the whole point --
## "this treaty needs a meeting first" is content, expressed by the treaty's own
## file as {"field": "met_recently", "op": ">=", "value": 1}, and the writer half is
## the action's `opens_meeting` flag. A window of opportunity rather than a
## permanent permission, which is docs/tiers/v2.md section 4's own wording.
const PRECONDITION_FIELDS := [
	"relations", "agreement_active",
	"measure_active", "tariff_active", "sanction_active",
	"pact_active", "pact_count",
	"deployment_active", "deployment_chosen", "deployment_obliged",
	"overall_approval_pct", "debt_to_gdp_pct", "unemployment_pct",
	"deficit_pct_gdp", "growth_annual_pct", "met_recently",
	# V5.1-0d: the actor's own embassy in the target's capital (open_embassy asks 0),
	# and whether the pair has diplomatic relations at all (it asks 1).
	"embassy_held", "relations_exist",
]

const PRECONDITION_OPS := ["<", "<=", ">", ">=", "=="]

## How far one action may move a pair in a single use. Bounds the content, not
## the accumulated state -- RELATIONS_MIN/MAX bound that. A value beyond this is
## a load error, so an action cannot quietly out-scale the drift that is
## supposed to pull against it.
const MAX_ACTION_RELATIONS_DELTA := 25.0

## How far one action may move a single bloc's approval target, on the [-1, +1]
## scale opinion_constants.gd's satisfaction terms use. The same magnitude
## band government_constants.gd's FALLEN_BLOC_PENALTY (-0.12) sits in: a
## diplomatic act should be able to cost about what a collapsed government
## costs, and no more.
const MAX_ACTION_BLOC_OFFSET := 0.15

# --- The counterparty rule ----------------------------------------------------------
#
# AGREEMENT_ACCEPT_MIN lived here and is RETIRED at V1.3e, along with the whole
# idea it carried: that a partner's answer to a trade agreement is a relations
# level against one bar. It is now foreign_policy_constants.ACCEPT_MIN against
# three terms -- how much of the partner's trade runs through the proposer, how
# warm the pair is, and what is on the table.
#
# Deleted rather than left unused, because a tuned constant nothing reads is a
# number a later session will find and reason from. What it MEASURED is not
# deleted and is carried into docs/foreign-policy-model.md instead: every GBR pair
# rests at exactly 45.0 and the strongest positive verb reaches only 60.7 from
# there, so any relations-based bar is capped from above by Britain. The new model
# answers that structurally rather than by staying under the cap -- stake is
# normalised per viewer, so the question became WHO MATTERS TO BRITAIN rather than
# HOW MUCH BRITAIN CARES, and the second has no good answer.

# --- The president's day, V2.4a ----------------------------------------------------
#
# The first tuned constants in this file since V1.3e retired two, and each was set
# by tools/day_probe.gd against a band fixed BEFORE the sweep ran. The day machine's
# quantities live here rather than in calendar_constants.gd on purpose: they gate
# DIPLOMACY (travel_days() prices a booking, met_recently gates a verb), and
# calendar_constants.gd's U6a headline -- no tuned constant, the currency deleted --
# stays true about the scheduler itself. The scarcity is OCCUPANCY, the author's
# call at plan time: a journey occupies its days, overlapping blocks are refused,
# and no ceiling constant exists here because U6a's probe already measured every
# ceiling priced against legality binding in 100 % of months.

## Great-circle kilometres per travel day, capital to capital. The anchor is the
## tier's own example -- "a journey that takes four days because Rome is far" --
## and the probe holds it there: Paris-Rome is ~1105 km, so the rate that yields
## four days is ~280, and the sweep confirms it interior to its grid rather than
## pinned at an edge. Rail-and-road diplomacy pace, not an aeroplane's, because
## the number's job is to make Rome cost more than Brussels, not to model
## transport.
const TRAVEL_KM_PER_DAY := 280.0

## Bounds on one leg's length in days. The floor exists so a neighbour's capital
## is still a day out -- a state visit to Brussels is not a commute. The ceiling
## bounds the block a booking can occupy; nobody in this roster is eight days
## away, so it guards future content rather than any present capital.
const TRAVEL_DAYS_MIN := 1
const TRAVEL_DAYS_MAX := 8

## How many months a meeting keeps the pair's treaty-class verbs unlocked. A
## LEVEL READ off a stamp, never a countdown: nothing ticks, nothing decays, and
## the window closes by arithmetic when state.year*12+month runs past the stamp
## plus this -- the same discipline defence obligations were given at V1.3g so
## that nothing has to remember to lift them. Absent stamp = never met.
##
## Twelve matches the state visit's own cooldown: by the time you could visit
## again, the last visit's introductions have gone stale. The probe swept this
## against that anchor and took the smallest passing candidate, interior to the
## grid (V1.5b's extended tiebreaker rule).
const MEETING_WINDOW_MONTHS := 12
