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
const EU_CO_MEMBER_BONUS := 15.0

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
const PRECONDITION_FIELDS := [
	"relations", "overall_approval_pct", "debt_to_gdp_pct",
	"unemployment_pct", "deficit_pct_gdp", "growth_annual_pct",
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
