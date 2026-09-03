extends RefCounted

## Tuning for src/sim/network.gd. See docs/network-model.md.
##
## ONE SWEPT CONSTANT AND ONE DERIVED LENGTH, which is one more than
## src/sim/region_constants.gd ships and one fewer than the row implied. The graph
## itself carries no constant at all: adjacency is derived from the polygons,
## distance is great-circle, the endowment is measured, and the sea-link count is
## the number of components adjacency leaves. What is genuinely a free parameter is
## how hard a region's position is allowed to move its growth, and that is
## NETWORK_BETA alone.


## How far a region's growth deviates, in points per year, per unit of
## `specialisation * ln(accessibility)`. The session's only tuned constant.
##
## MULTIPLIED BY SPECIALISATION RATHER THAN STANDING ALONE, and that is the model
## rather than a coefficient: a region that makes what everyone else makes has no
## reason to care how far the market is, and one that makes something nobody near it
## makes has every reason. So the two terms are a product and the sweep sees one
## number -- V1.6e's refusal of a second authored strength, applied to a pair of
## measured quantities instead of to a pair of dials.
##
## BAND, two clauses, fixed before the sweep (docs/network-model.md section 6):
##   (i)  READABLE. Over 60 months the largest mover's share of national output must
##        move at least 0.1 percentage point -- one digit of src/ui/region_panel.gd's
##        own "%.1f%%", V2.6a's clause (i) on the output partition instead of the
##        population one.
##   (ii) BOUNDED. Over 168 months no region's share of national OUTPUT may drift
##        past region_constants.SHARE_DRIFT_MAX, and no region's share of national
##        POPULATION past the 0.0164 ceiling migration_constants.MIGRATION_RATE is
##        measured against -- because the network term moves output per head, which
##        is half of the Harris-Todaro pull, so it moves people too.
##
## MEASURED, at Task 8, on those clauses -- and the sweep has ONE edge, which is
## the session's central finding about the model:
##
##   beta  move@60(pp)  diff@60(pp)  out-drift  pop-drift   verdicts
##   0.00      0.093        0.000      0.0026     0.0160   (i)-- (ii)OK
##   2.00      0.079        0.020      0.0022     0.0160   (i)-- (ii)OK
##   4.00      0.090        0.040      0.0025     0.0160   (i)-- (ii)OK
##   5.00      0.095        0.050      0.0027     0.0160   (i)-- (ii)OK
##   5.50      0.097        0.055      0.0027     0.0160   (i)-- (ii)OK
##   6.00      0.100        0.060      0.0028     0.0160   (i)-- (ii)OK
##   6.50      0.103        0.065      0.0029     0.0160   (i)-- (ii)OK
##   7.00      0.105        0.070      0.0030     0.0160   (i)-- (ii)OK
##   8.00      0.111        0.080      0.0031     0.0160   (i)-- (ii)OK
##  10.00      0.121        0.100      0.0034     0.0160   (i)OK (ii)OK
##
## move@60 is the largest mover's total output-share move over 60 months (clause
## (i) as written); diff@60 is the same month's largest move against the inert
## channel's own run -- the fingerprint the term itself leaves. Clause (ii) NEVER
## BINDS: at beta 10 the worst output drift is 0.0034 against a SHARE_DRIFT_MAX of
## 0.15 (44x slack, the guard rail's own "a France that is one region" is nowhere
## in reach), and the population drift is PINNED by natural change at 0.0160
## against the 0.0164 ceiling -- the drift MIGRATION_RATE already owns, unmoved by
## the term at any candidate. The emulation is validated at the inert row: its
## pop-drift reads 0.01600 against V2.6c's real-harness 0.01599 at the same rate.
##
## THE MIDPOINT RULE HAD NO INTERVAL TO TAKE A MIDPOINT OF. docs/decision-log.md's
## V1.5d rule assumes two crossings; the measured band is [crossing, infinity) --
## widening the grid moves no upper edge, which is V1.5a's "a band an observable
## cannot reach is a bound and not a selector", recorded rather than tuned
## against. So the crossing ships, and the DIFFERENTIAL one rather than the total:
## the total is confounded by the mix term's own 0.093 pp baseline (V2.5's
## divergence -- a content accident that could drift either way), where the
## fingerprint is the channel's own and EXACTLY LINEAR in beta at 0.010 pp per
## unit across the whole grid, so its crossing at 10.0 is grid-independent --
## V1.5b's refinement diagnostic passed by construction. Both readings of clause
## (i) hold here (0.121 total, 0.100 differential), and the value is interior to
## the swept range on the total reading besides.
const NETWORK_BETA := 10.0


## The decay length of the market-potential sum, in endowment-adjusted km.
##
## DERIVED, NOT SWEPT, and the derivation is the graph's own: the continental
## component's diameter is 13 hops and its mean eccentricity 9.65, so a decay length
## that puts a region's own weight at e^-1 by the mean eccentricity makes the index
## read the CONTINENT rather than a region's own neighbours or the whole of Europe
## flat. Measured at Task 8 as the mean shortest-path km at that hop count and
## written here; it is a property of the roster, so a re-import that changes the
## roster changes it and tools/network_probe.gd prints it every run.
##
## MEASURED at 9.65 -> the 10-hop row of the hop-count-to-km curve (probe table
## "decay"): 300 ordered continental pairs, mean endowment-adjusted 2924.9 km. The
## curve is smooth in the hops (250 km at one hop, 5 349 km at the diameter's far
## end), so the exact hop count is not load-bearing: at 9 hops it is 2 686 and at
## 11 it is 3 188, both inside the index's own e-folding, which is what makes this
## a fit that converges rather than a band edge that moves.
const DECAY_KM := 2924.9
