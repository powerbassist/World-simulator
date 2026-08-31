extends RefCounted

## Tuning for src/sim/migration.gd. See docs/migration-model.md.
##
## ONE RATE AND ONE BOUND, which is src/sim/region_constants.gd's position one
## session on, and the reason is the model rather than restraint: the PULL carries
## no free weight at all. Between regions it is Harris-Todaro expected income --
## output per head times the probability of being employed, a product of two ratios
## the register already publishes -- and between the cities of one region it is named
## jobs per head. Neither is a weighted sum, so there is no coefficient to author.
##
## docs/tiers/v2.md section 6 names THREE inputs -- jobs, unemployment, service
## quality -- and service quality is one figure per nation (src/sim/society.gd's
## QUALITY_KEYS), so it has ZERO variance across cities and cannot discriminate
## between two of them at any weight. Dropped and recorded rather than included at a
## weight that would be measuring nothing: V1.5b deleted DEPENDENCY_ELASTICITY
## ["health"] on the same reasoning rather than tuning against an arithmetic
## impossibility.


## Share points moved per year at a pull deviation of 1.0, applied proportionally
## to the share already there. The session's only tuned constant.
##
## PROPORTIONAL RATHER THAN ABSOLUTE, and that is what makes a share bounded with no
## number to set wrong -- src/sim/campaign.gd's log-odds argument in a second place.
## `s * (1 + rate * (pull - mean) / 12)` cannot reach zero from a positive share for
## any rate small enough that the monthly factor stays positive, so this file ships
## no share floor and tests/test_migration.gd asserts positivity instead of a clamp
## enforcing it. THAT ARGUMENT HOLDS ONLY BECAUSE EVERY PULL IS NON-NEGATIVE: the
## employment probability stays in [0.6, 1.0] because Regions.unemployment_pct() is
## clamped by economy_constants.UNEMP_MAX_PCT = 40.0, and a head count and an output
## share are both non-negative by construction -- three facts that live in other
## modules, so a session that raises that clamp past 100 or adds a negative term to a
## pull owes this argument a second look before trusting the no-floor claim.
##
## BAND, two parts, both fixed before the sweep (docs/migration-model.md section 6):
##   (i)  READABLE. Over 60 months -- one presidential term -- the largest mover's
##        share of its nation must move at least 0.1 percentage point, which is one
##        digit of src/ui/region_panel.gd's own "%.1f%%". A movement the panel
##        printing it cannot resolve is not a movement the player can see.
##   (ii) BOUNDED. Over 168 months no region's share may drift more than 0.05 -- five
##        points -- so no reachable run produces a France that is one region.
##
## TIEBREAKER, fixed before the sweep: the response is linear in the rate, so the
## band's edges are SMOOTH CROSSINGS rather than plateaux and neither edge selects.
## docs/decision-log.md's V1.5d rule therefore applies: the interior governs, and the
## midpoint of the passing interval ships. Checked for stability by refining the grid
## (V1.5b's diagnostic) -- a value that moves under refinement is a statement about
## the grid rather than a result.
const MIGRATION_RATE := 0.0  # SET BY TASK 8'S SWEEP. 0.0 makes the machine inert.


## How far a region's share of its nation's population may drift from where it
## started, in share points. docs/economy-model.md's divergence argument is PER
## QUANTITY, so a new quantity feeding a compounding path owes it a bound -- and this
## is a bound rather than a dial: tools/migration_probe.gd reports the slack rather
## than tuning against it, which is src/sim/projects_constants.gd's position and
## src/sim/region_constants.gd's.
const SHARE_DRIFT_MAX := 0.05
