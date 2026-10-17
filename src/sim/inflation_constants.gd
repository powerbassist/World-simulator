extends RefCounted

## Tunables for src/sim/inflation.gd — V1.6b, the second session of the V1.6 block.
## The model and the evidence for every value here is docs/inflation-model.md;
## tools/inflation_probe.gd is where the two swept ones were measured.
##
## THREE OF FIVE ARE MEASURED OFF THE WORLD BANK RATHER THAN SWEPT, which is V1.6a's
## instrument choice inherited rather than rediscovered. `FP.CPI.TOTL.ZG`, all ten
## nations, 35 of 35 years, on the 1990-2024 window tools/import_data.py already
## fetches for the cycle. The per-nation anchor is content and lives in
## data/nations/*.json as imported.prices; the two below it are roster-wide and live
## here.


## V1.6b. The Phillips slope: points of annual inflation per point of unemployment
## BELOW the structural rate. Positive, because inflation.gd writes
## `target = anchor + BETA * (structural - u)` while the regression that measured it
## reads pi on (u - u_mean) and so comes back negative. The sign is flipped once, at
## the point of measurement, and tools/import_data.py's build_prices_blocks() says so
## where it prints.
##
## MEASURED, AND THE MEASUREMENT REFUTED THE ROADMAP ROW THAT ASKED FOR IT. V1.6b's
## row specifies "a price pressure from the gap, the impulse and (a)'s shock".
## Regressed against an output gap built the way src/sim/economy.gd builds one -- the
## running sum of (growth - own-mean growth), per nation, demeaned -- the output gap
## carries no signal and its sign FLIPS between sub-samples:
##
##     window            pi ~ output gap      pi ~ unemployment gap
##     1990-1998         +0.156  r +0.204     0.376  r -0.383
##     1999-2024         +0.048  r +0.098     0.252  r -0.339
##     1990-2024         -0.053  r -0.140     0.148  r -0.207
##
## The unemployment gap carries a stable, correctly-signed relation in both DISJOINT
## halves, agreeing on sign and within 1.5x on magnitude. Two disjoint windows
## agreeing is V1.6a's cross-check discipline applied to two sub-samples rather than
## to two statistics.
##
## THE EURO-ERA SLOPE SHIPS, AND THE SELECTION RULE IS THE MODEL'S OWN PREMISE rather
## than a preference between two numbers. docs/tiers/out-of-scope-mvp.md records that
## France does not set its own interest rate and docs/brainstorm/mechanics-economy.md
## tiers the central bank Someday -- so this game's nations have no monetary autonomy,
## which is precisely what the 1999-2024 sub-sample measures and precisely what the
## pre-euro one does not. Shipping 0.376 would calibrate the model on a monetary
## independence the game explicitly does not give the player.
##
## The POOLED figure is the weakest of the three and would have been the wrong one to
## ship on the "use all the data" instinct: it is attenuated by pooling two regimes
## with different means, which is why all three are printed rather than one.
const INFLATION_UNEMP_BETA := 0.25

## V1.6b. One month of convergence toward the target, as a fraction of the remaining
## distance. src/sim/society.gd's quality_step() shape and units -- a MONTHLY rate
## with no /12 at the call site.
##
## MEASURED, and converted exactly rather than approximately. The World Bank series
## gives an ANNUAL AR(1) coefficient of rho = 0.5232 (r 0.546, n 340) on each nation's
## deviation from its own anchor, demeaned per nation so the fit measures how sticky
## inflation IS rather than how different the ten countries are. The monthly rate that
## reproduces it is the exact twelfth root:
##
##     1 - (0.5232)^(1/12) = 0.052551,  and (1 - 0.052551)^12 = 0.5232
##
## A linear `rho / 12` would have been 0.0436 and would have made the model 20 %
## stickier than the data, which is the kind of quiet units error the realised-sd
## cross-check in tools/inflation_probe.gd exists to catch.
##
## Half-life 12.8 months. Deliberately SLOWER than QUALITY_CONVERGENCE's and
## CAPABILITY_CONVERGENCE's, and that is what makes the thirteenth issue distinct
## rather than collinear: `jobs` prices unemployment now, this prices where
## unemployment was a year ago, so the two say different things at the moment of an
## election. See docs/inflation-model.md section 6.
const INFLATION_CONVERGENCE := 0.0526

## The satisfaction scale is NOT here. It lives in src/sim/opinion_constants.gd as
## INFLATION_SCALE_PP, beside JOBS_SCALE_PP, DEFICIT_SCALE_PP and EUROPE_SCALE, because
## it converts a measured quantity into what a voter feels rather than describing the
## quantity -- EUROPE_SCALE's own argument for not being folded into BURDEN_MAX.

## V1.6b. Points of annual growth lost per point of inflation above the anchor. The
## standard real cost of inflation -- relative-price distortion and uncertainty
## depressing output -- which needs no nominal quantity and so survives this project's
## constant-price boundary. See docs/inflation-model.md section 4.
##
## SWEPT, with a guard the model supplies analytically rather than by taste. Composing
## Okun's law with unemployment's own reversion, a standing growth deficit of
## `G * dpi` settles at
##
##     u - u* = OKUN * G * dpi / UNEMP_REVERT = (0.4 / 0.35) * G * dpi
##     loop gain = INFLATION_UNEMP_BETA * 1.143 * G = 0.286 * G
##
## so the feedback loop this channel closes is stable for G below ~3.5. That is a
## bound DERIVED from three constants that already exist rather than chosen, which is
## cycle_constants.max_impulse_pct()'s idiom, and the shipped value is an order of
## magnitude under it -- guard slack 0.0857 against 1.0, reported by
## tools/inflation_probe.gd rather than quietly satisfied. docs/defence-model.md's and
## docs/companies-model.md's treatment of their own clamps.
##
## *** THE VISIBILITY BAND FAILED AT EVERY HONEST CANDIDATE, AND IT IS RECORDED RATHER
## THAN TRADED AGAINST. *** This is V1.6a's legibility floor in a second place, and the
## arithmetic is short. Table (a) measures the reachable inflation deviation at 0.145
## points -- INFLATION_UNEMP_BETA is a measured 0.25, a reachable unemployment gap is
## about one point, and the 12.8-month lag means the stock never catches a target that
## is itself decaying. Band (iii) asked for 0.25 % of GDP over a term, and that needs
## G >= 2.0: one point of inflation costing two points of annual growth, which is more
## per point than V1.6a's whole business cycle moves and is not a number about the
## world. The empirical cost of moderate inflation is a fraction of a point.
##
## So the band's own prescription -- ship it visible or DELETE it -- is refused in both
## halves, and the reasons are different for each. Not raised, because tuning a
## measured slope's consequence until it is visible is what V1.5b refused for
## DEPENDENCY_ELASTICITY["health"] and V1.6a refused for CYCLE_AMPLITUDE_PCT. Not
## deleted, because unlike U6a's day budget and V1.5b's deleted elasticity this term is
## STRUCTURAL rather than decorative: it is the only thing making the inflation loop
## negative feedback, and without it the statistic reaches the economy not at all and
## the model's "two prices" claim collapses to one. docs/tiers/v1.md section 6's (c)
## reads this stock through the bond yield, where a level that has always existed is
## worth more than a level invented later.
##
## What is honestly true and is written here rather than implied: ON THE GDP AXIS THIS
## CHANNEL IS BELOW THE READABLE FLOOR at any defensible value -- 0.049 % of GDP over a
## term. The player feels inflation through the thirteenth issue, not through output.
## A note the same shape as docs/defence-model.md's unliftable deployment.
##
## The asymmetry underneath it is worth naming too, because it is not obvious: the
## LARGEST reachable deviation is DEFLATIONARY (-0.140 under a `cold` budget against
## +0.134 under a `hot` one), and this cost is one-sided above the anchor, so it never
## fires on the biggest movement the player can actually cause.
const INFLATION_OUTPUT_BETA := 0.30

## Guard rails on the stock. NOT the thing that sets the number: the target is a
## bounded expression (an anchor plus a slope times a clamped unemployment gap) and a
## first-order lag on a bounded target is bounded, so this pair is a guard rail in
## docs/economy-model.md's sense -- unreachable under any input the player can
## express. tests/test_inflation.gd measures the slack rather than asserting it,
## because a clamp nobody has measured is a clamp that might be setting the model.
##
## The lower bound is negative on purpose. Deflation is reachable -- a deep enough
## recession opens an unemployment gap wide enough to push the target below zero --
## and clamping at 0.0 would make a slump's price stop accruing at exactly the moment
## the model is trying to describe.
const INFLATION_MIN := -5.0
const INFLATION_MAX := 30.0

## Bounds on the per-nation anchor at load, in src/core/nation.gd's validator. Same
## job as cycle_constants.AMPLITUDE_REL_MIN/MAX: a content check, not a runtime clamp.
## The measured roster spans 1.117 (Switzerland) to 2.903 (Spain), so these are wide
## enough that a re-import cannot trip them and narrow enough that a broken download
## cannot pass.
##
## V4.11 widened the ceiling 20 -> 40, and the reason is a measured regime, not a
## loosened check: the neighbourhood's euro-era (1999-2024) means are Turkey 23.4,
## Serbia 14.7, Belarus 18.5 -- real high-inflation economies, which the window rule
## (one window for every nation, Rule 1) cannot and should not re-cut. (Belarus read
## 34.8 until tools/import_data.py dropped hyperinflation years above 100 % from
## every anchor -- its 1999 and 2000; the runtime clamp is 30.) 40 still refuses a
## percent-for-per-mille download error.
const ANCHOR_MIN := -2.0
const ANCHOR_MAX := 40.0
