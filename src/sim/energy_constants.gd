extends RefCounted

## Tuning for src/sim/energy.gd. See docs/energy-model.md.
##
## THREE SWEPT CONSTANTS AND TWO BOUNDS. The catalogue carries every fact about a
## technology, so nothing here turns one authored number into another -- the
## position src/sim/projects_constants.gd and src/sim/pledges_constants.gd each
## reached, and the reason src/core/energy_source.gd may require six independent
## fields where investment_action.gd permits one.
##
## ALL THREE BETAS ARE 0.0 UNTIL TASK 7 MEASURES THEM. Deliberate, and it is
## V2.7's own sequencing: with them at zero every added expression returns exactly
## 0.0, the balance harness is bit-identical, and the sweep runs against a working
## model rather than against a plan's guess.

## The three branches the import measured. The mix is a partition over exactly
## these, so a source naming a fourth is a LOAD ERROR rather than a runtime
## surprise -- src/core/energy_source.gd checks it.
const BRANCHES := ["fossil", "nuclear", "renewable"]

## Register entry shape, asserted by tests/test_save_load.gd the way
## Projects.ENTRY_KEYS is.
## Seven keys, where Projects.ENTRY_KEYS has two. `lon`/`lat` are the PLAYER's own
## coordinate and `region_id` is what it resolved to at commit; `connection` is the
## multiplier that resolution was quoted at, frozen. All four are stored together
## because they are one contract -- see the plan's call 4 and docs/energy-model.md
## section 4 for why this is the OPPOSITE of Projects.site_region()'s derive-every-read.
const ENTRY_KEYS := ["source_id", "region_id", "lon", "lat", "connection", "months_left", "done"]

## Fields an energy action may name in a precondition. deficit_pct_gdp is here for
## the reason every executive verb's list has it; import_dependency_pct is the one
## this session adds, and it is the second PRECONDITION_FIELDS entry naming
## something the player did not directly do -- unrest_pct at V1.5c was the first.
const PRECONDITION_FIELDS := {
	"deficit_pct_gdp": true,
	"debt_to_gdp_pct": true,
	"import_dependency_pct": true,
	"plant_count": true,
	"overall_approval_pct": true,
}

## The operators a precondition may use. projects_constants' own list, borrowed
## rather than re-declared: what a comparison operator IS is not a decision this
## model gets to make twice.
const PRECONDITION_OPS := ["<", "<=", ">", ">=", "=="]

## MEASURED AT TASK 7. How hard a region's position moves what a plant costs to
## build, as the exponent on the accessibility index. A region at exactly the mean
## accessibility pays exactly 1.0 -- a structural zero rather than a clamp, which
## is network.gd's own idiom, and the reason this file ships no "connection cost
## floor". See docs/energy-model.md section 5 for the band.
const ACCESS_ELASTICITY := 0.0

## MEASURED AT TASK 7. Points of bloc_offset per unit of (source opposition x the
## region's concentration). V2.6b1 measured Siting.concentration() and found the
## interval for a price on it EMPTY; V2.8 is its first pricer, and it charges at
## COMMIT rather than monthly, which is why the interval that was empty there can
## be non-empty here. See docs/energy-model.md section 6.
const OPPOSITION_SCALE := 0.0

## MEASURED AT TASK 7. Points of annual growth per point of import-dependency
## deviation against the nation's own start. NEGATIVE in effect: the term is
## -DEP_BETA * deviation, so raising dependency costs growth. See section 7.
const DEP_BETA := 0.0

## BOUNDS, not selectors. A guard rail on the growth addend, and the reason it is
## a bound is V1.5a's: nothing chooses it, it only refuses an absurdity.
const IMPULSE_MAX_PCT := 1.50

## The floor the connection multiplier's own argument cannot go under. A region
## with an accessibility of exactly 0.0 does not exist in the committed graph
## (network.gd's index is mean-one and strictly positive), so this refuses a
## division rather than shaping a price.
const ACCESS_MIN := 0.0001
