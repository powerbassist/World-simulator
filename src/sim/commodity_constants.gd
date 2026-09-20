extends RefCounted
## Tuning for src/sim/commodities.gd -- V4.6. See docs/tiers/v4.md's V4.6 row and
## the step-0 verdict in reports/production_gdp_probe.txt.
##
## FIVE NUMBERS, and the smallness is the step-0 verdict's own consequence rather
## than restraint: the probe found the recipe form reproduces the RANK of the 29
## economies and not their levels (worst miss LUX at 0.822), so the layer models
## GDP *changes* and there is no productivity lever to tune.
##
## NONE OF THESE IS A SWEPT CONSTANT, and the reason is measured rather than
## assumed: the world's capacity weights and its demand weights come from the
## SAME recipe-derived structure, so the world starts in balance BY CONSTRUCTION
## and the stationary price vector is base. Run 240 months at PRICE_ELASTICITY
## 0.10, 0.30 and 0.60 and the settling prices are identical; the values below
## govern how fast a shock is priced, not where it settles. No shipped verb can
## cause a shock yet -- that is Task 4's panel and the block's later content -- so
## a sweep here would be measuring an input no player can reach. Recorded so the
## session that adds the first shock knows these are unvalidated in the one place
## they matter.

## How far one month's relative world gap moves a price, as a fraction of it.
## NOT A FIXED POINT OF THE MODEL, measured over 240 months on the 29-nation
## roster: the price vector settles to the same figures at 0.10, 0.30 and 0.60,
## because the world starts in balance and only a shortage moves it. What the
## value DOES govern is how fast a shortage prices -- and no player verb creates
## one yet, so the sweep that would choose it belongs to the session that gives
## the player a way to (Task 4). 0.30 is deliberately interior rather than tuned.
const PRICE_ELASTICITY := 0.30

## How much a good's demand quantity answers its price, `(base/price)^1.0`: a
## plain unit-elastic response. This is the term that stops a shortage from
## running away -- without it, demand is a constant and the only equilibrium is
## the clamp.
const DEMAND_ELASTICITY := 1.0

## The tier's own bound, and it is what makes a shortage survivable rather than
## a runaway: a price may reach a quarter of its base and no further, or one and
## three quarters and no further. The probe's pre-committed band, reused.
const PRICE_BAND := 0.75

## Fraction of a surplus offered to deficit nations in one month. Bilateral
## matching walks each good's surplus nations against its deficit nations in
## sorted id order (determinism, not priority), so this is a rate and not an
## equilibrium quantity: 0.50 leaves a persistent imbalance visible for two
## months rather than clearing it inside one, which is what lets a trade
## dependency read as one on a panel.
##
## The surplus ITSELF is the other half of the rule and lives in commodities.gd
## rather than here: a nation offers what it can PRODUCE beyond what it wants,
## not what it happens to hold, so this rate is applied to a figure the recipe
## chain produced and not to a stock nothing maintains.
const TRADE_RATE := 0.50

## Fixed-point iterations when deriving the recipe structure's weights. A FIXED
## count rather than a convergence test, so the answer cannot depend on a
## floating-point comparison. Measured: this register's graph is acyclic and
## 6 deep, so the relaxation reaches EXACTLY zero residual at iteration 7 and
## every further round is bit-identical. 24 is therefore ~17 rounds of margin
## rather than a convergence threshold, and a deeper content pack still has room.
const STRUCTURE_ITERATIONS := 24