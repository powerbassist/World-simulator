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

## MEASURED AT TASK 7, and shipped at the interior because BOTH edges are smooth
## crossings (docs/energy-model.md section 8, table pasted from the run):
##
##   cand   spread (i)   max_mult (ii)
##   0.10   0.0095 --     1.043 OK
##   0.15   0.0143 OK     1.065 OK
##   0.20   0.0193 OK     1.088 OK
##   0.30   0.0294 OK     1.135 OK   <- shipped
##   0.50   0.0507 OK     1.234 OK
##   1.00   0.1108 OK     1.524 OK
##
## (i) READABLE crosses at 0.105 (France's best 1.101 against worst 0.656, a
## 0.010-point spread on the budget panel's %.3f), (ii) BOUNDED at 1.114. Neither
## edge is within a factor of three of the other, so the interior governs --
## V1.5d's rule -- and the log-interior (sqrt(0.105 x 1.114) = 0.34) is 0.30 on
## the coarse grid. A best-to-worst French reactor reads 0.175 against 0.204
## points of GDP: three times the readability floor at a worst-case premium
## three-and-a-bit times inside the bound. Grid refinement does not move either
## crossing (V1.5b's diagnostic) -- the crossings are powers of a measured index,
## not scan artifacts.
##
## How hard a region's position moves what a plant costs to build, as the exponent
## on the accessibility index. A region at exactly the mean accessibility pays
## exactly 1.0 -- a structural zero rather than a clamp, which is network.gd's own
## idiom, and the reason this file ships no "connection cost floor". See
## docs/energy-model.md section 5 for the band.
const ACCESS_ELASTICITY := 0.30

## MEASURED AT TASK 7, and shipped at the interior (docs/energy-model.md section
## 8, table pasted from the run):
##
##   cand   app_move (i)   accum frac (ii)
##   0.05   -3.60 OK        0.20 OK
##   0.06   -4.32 OK        0.24 OK
##   0.07   -5.04 OK        0.28 OK
##   0.08   -5.75 OK        0.32 OK   <- shipped
##   0.09   -6.47 OK        0.36 OK
##   0.10   -7.19 OK        0.40 OK
##   0.11   -7.91 OK        0.44 OK
##
## (i) READABLE crosses at 0.042 -- the move is APPROVAL_SPAN times the
## concentration spread times the authored opposition, read through Opinion's own
## clamp at a zero score, France's largest FR1 1.851 against smallest FRM 0.053.
## (ii) CAREER-BOUNDED crosses at 0.116 on the SUSTAINED programme: six gas
## stations in 168 months, one per build length, the plan's own regime cadence.
## ON A ONE-ORDER-A-MONTH READING THE CLAUSE CANNOT SELECT AT ALL: the run fires
## 137 stations and the accumulator saturates at every candidate -- through the
## AUTHORED bloc_offset alone (137 x -0.020 = -2.74, past +-1.0 with the siting
## price at zero). U6a's finding in a new place: available() returns what is
## LEGAL and nothing models what the player WANTS, so a career clause priced
## against legality always binds. The sustained run is the selector; the spam run
## is a bound, recorded in docs/energy-model.md section 8 rather than tuned
## against.
##
## Points of bloc_offset per unit of (source opposition x the region's
## concentration). V2.6b1 measured Siting.concentration() and found the interval
## for a price on it EMPTY; V2.8 is its first pricer, and it charges at COMMIT
## rather than monthly, which is why the interval that was empty there can be
## non-empty here. See docs/energy-model.md section 6.
const OPPOSITION_SCALE := 0.08

## MEASURED AT TASK 7, and shipped at the interior (docs/energy-model.md section
## 8, table pasted from the run):
##
##   cand   cost@dev 3.81  (i) >= 0.30   (ii) < 0.5639
##   0.060   -0.229         --            OK
##   0.080   -0.305         OK            OK
##   0.100   -0.381         OK            OK   <- shipped
##   0.120   -0.458         OK            OK
##   0.140   -0.534         OK            OK
##   0.150   -0.572         OK            --
##
## The dependency deviation of the sustained gas run is 3.81 points and does not
## depend on the candidate, so the emulation at the candidate is exact (V1.6b's
## rule, trivially). (i) READABLE crosses at 0.079 -- economy_panel.gd's own %.2f,
## with margin -- and (ii) NOT DOMINANT at 0.148 against the 0.5639 points of
## DEFICIT_SCALE_PP that V1.6d and V1.6e left. The interior on both the linear
## and the log reading is 0.10: 1.27x above the floor, 1.48x inside the span,
## stable on the refined grid.
##
## Points of annual growth per point of import-dependency deviation against the
## nation's own start. NEGATIVE in effect: the term is -DEP_BETA * deviation, so
## raising dependency costs growth. See docs/energy-model.md section 7.
const DEP_BETA := 0.10

## BOUNDS, not selectors. A guard rail on the growth addend, and the reason it is
## a bound is V1.5a's: nothing chooses it, it only refuses an absurdity.
const IMPULSE_MAX_PCT := 1.50

## The floor the connection multiplier's own argument cannot go under. A region
## with an accessibility of exactly 0.0 does not exist in the committed graph
## (network.gd's index is mean-one and strictly positive), so this refuses a
## division rather than shaping a price.
const ACCESS_MIN := 0.0001
