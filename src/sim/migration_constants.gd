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
##
## MEASURED, tools/migration_probe.gd table (e), emulating each candidate through
## share_delta() rather than rescaling from the shipped value -- a probe that
## rescales has its passing interval move when the shipped value moves, which is
## V1.6b's "the range was choosing the constant" wearing a second costume. The two
## columns are the largest mover's change in its share of the nation at month 60 and
## the worst region drift at month 168, over the three playable nations:
##
##   rate     FRA @60   DEU @60   worst region @168   band
##   0.0070   0.0035    0.0009    0.0096              fail (i)
##   0.0080   0.0040    0.0010    0.0109              fail (i)
##   0.0081   0.0041    0.0010    0.0110              PASS   <- clause (i) crosses
##   0.0100   0.0050    0.0012    0.0134              PASS
##   0.0200   0.0097    0.0024    0.0252              PASS
##   0.0273   0.0131    0.0033    0.0329              PASS   <- SHIPPED, the midpoint
##   0.0400   0.0186    0.0046    0.0447              PASS
##   0.0465   0.0213    0.0053    0.0500              PASS   <- clause (ii) crosses
##   0.0466   0.0214    0.0053    0.0501              fail (ii)
##   0.0480   0.0220    0.0054    0.0511              fail (ii)
##
## Passing interval [0.0081, 0.0465], midpoint 0.0273, and the value is INTERIOR to
## every grid swept -- 0.0020-0.1000, 0.0050-0.0600, 0.0080-0.0500 and 0.0070-0.0480,
## with candidates failing on BOTH sides in each. STABLE UNDER REFINEMENT, which is
## the diagnostic rather than the reassurance: the midpoint reads 0.0280 at a step of
## 0.0020, 0.0275 at 0.0005, 0.0273 at 0.0002 and 0.0273 at 0.0001, so the last two
## resolutions agree and the answer has stopped being a statement about the grid.
##
## BRITAIN IS A STRUCTURAL BOUND AND CLAUSE (i) IS NOT READ ON IT, recorded with the
## number beside it rather than tuned around -- V1.6e's treatment of the two sectors
## that sat under its floor, and V1.6a's legibility floor before that. Every British
## region carries an identical expected income by construction (docs/region-economy-model.md
## section 8: ten of twelve ITL1 codes exist, so the index was taken as a proxy), so
## its region column is EXACTLY 0.0000 at every candidate and its whole signal is
## named employers at the city level. That column reaches 0.0010 only at ~0.095,
## against a clause (ii) ceiling of 0.0465 -- no rate satisfies both clauses for
## Britain, at any grid, and raising the rate until it did would break clause (ii)
## for France. Luxembourg is the second bound and a harder one: ONE region holding
## ONE city, so `pull - mean` is exactly 0.0 at both levels and it cannot move at any
## rate whatever. Table (f) reports both.
const MIGRATION_RATE := 0.0273


## How far a region's share of its nation's population may drift from where it
## started, in share points. docs/economy-model.md's divergence argument is PER
## QUANTITY, so a new quantity feeding a compounding path owes it a bound -- and this
## is a bound rather than a dial: tools/migration_probe.gd reports the slack rather
## than tuning against it, which is src/sim/projects_constants.gd's position and
## src/sim/region_constants.gd's.
const SHARE_DRIFT_MAX := 0.05
