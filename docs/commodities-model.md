---
title: Commodities Model
tags:
  - model
  - simulation
---

# Commodities model

V4.6 — the commodity economy. The machine: `src/sim/commodities.gd` (a leaf
preloading only `commodity_constants.gd`), the register:
`ns.commodity_state` on every nation, the content: `data/commodities/`
(60 goods in seven categories, 34 recipes). Built 2026-09-20 on
`v4.6-commodity-economy`.

## §1 The step-0 verdict and the narrowing

The tier doc gated the block on two probes, both run before a recipe was
authored (`tools/production_gdp_probe.gd`, `tools/production_scale_probe.gd`,
committed dd20c51). The tick-budget probe PASSED (a synthetic month at full
V4.6+V4.7 scale costs 29.3 ms Dictionary-shaped, 5.2 ms flat-array — against
a 300 ms band, twice the whole measured V3 tick; the Victoria 3 late-game
failure form is not reachable at this abstraction). The GDP-reproduction
probe FAILED on levels (worst nation 0.822 relative error against a 0.20
band) while passing on shape (Spearman ρ = 0.902, the ordering of all 29
economies reproduced from population and sector shares alone). The finding,
in the tier's own terms: the abstraction LEVEL was wrong, not the recipes —
GDP per worker varies far more than labour and capital endowments can
explain, and the register carries no productivity-per-worker lever.

**The narrowing that follows is binding on everything below:** the commodity
layer models GDP *changes* — production, trade, shortages, prices — and
never writes `ns.gdp_eur_bn`. The level stays the register's measured value
(V1.5's World Bank figures). A per-nation productivity multiplier was
REFUSED at the gate: fitted against observed GDP it is circular by
construction.

## §2 The register

`commodity_state` is one Dictionary per nation with SEVEN keys (schema
commented at the field declaration in `src/core/nation_state.gd`):

- `capacity` — per good, the SEED-TIME SNAPSHOT: seeded once at `init_nation`
  from the nation's measured sector output times the good's recipe-structure
  weight, divided by its base price. Every good uses that one formula —
  population does not enter the seed. The tick never reads or rewrites this key:
  it derives capacity FRESH from the live `sector_output` every month, so the
  stored figure is the month-0 state and not a live stock.
- `demand`, `output` — per good per month. `demand` is the basket answered by
  the live price through `DEMAND_ELASTICITY` (§3 step 3). `output` is NET of
  what the nation's own downstream recipes consumed; the net form is what makes
  `value_added` genuinely value added rather than gross.
- `surplus`, `trade` — pre- and post-routing balances; `trade` is what
  crossed the border this month.
- `price` — one world price per good, clamped to [0.25×, 1.75×] of the
  authored base every write (the tier's ±75 % band; `PRICE_BAND`). One vector,
  copied per nation.
- `value_added_eur_bn` — ONE scalar per nation, not per good: the month's
  output valued at the live price, in EUR bn. This is the CHANGE the block
  models (the step-0 verdict: levels are not reproducible from recipes, deltas
  are). The register itself has no sim reader; since V4.4 the events machine's
  `commodity_price_high` hook reads the `ns.commodity_high_month` crossing stamp this machine writes on the nation, outside the register — this scalar's own readers
  are the UI surfaces: the Commodities panel and the two map layers (§5).

Serialised whole on SAVE_VERSION 37 (V4.6's bump) with a per-entry rebuild
in `from_dict` — the aliasing-safe pattern; see §6.

## §3 The machine, one pass per month

1. **Lazy seed** — `tick_month` seeds any nation whose register is `{}` via
   `init_nation` itself: one seeding route, the single-writer pin survives.
   This is NOT a pre-37 bridge: the register is serialised and `save_manager`
   refuses a version mismatch outright, so no pre-37 save reaches it — the `{}`
   it catches comes from a payload with the key absent, a hand-built fixture, or
   a caller arriving before the first tick (pinned three ways in
   `tests/test_commodities.gd`).
2. **Capacity, demand and production, per nation** — for every good of every
   nation, capacity is derived FRESH from the live `sector_output`
   (`_bucket(ns, good, structure) / base_price`), and demand from the world
   per-capita basket (step 3). Production then runs in `_production_order()`,
   a total order (recipe-graph depth, then id) computed once per tick from
   loader content alone (`_static_tables()`; hoisting it was measured at
   228 ms/tick and fixed — 44 ms after, fingerprint identical to the bit).
   Missing inputs read as zero is the defect that order exists to prevent: the
   first draft produced steel and machinery out of nothing because
   `CATEGORY_ORDER` was not topological — deleted, with the bug shape recorded
   at the deletion site.
3. **Demand** — each nation wants its share of the world's per-capita basket,
   a quantity taken at the good's BASE price and then answered by the live
   price through `DEMAND_ELASTICITY` (1.0 = unit-elastic). Population enters
   here and nowhere in the seed; the base-price division is what keeps the dial
   single-counted.
4. **Routing** — a SINGLE pass per good: each surplus nation offers
   `spare × TRADE_RATE` once, and deficit nations walk the sellers in sorted id
   order taking `min(want, offered)`. No iteration count, no halving —
   `TRADE_RATE` is the only knob and a rate, not an equilibrium quantity. All
   iteration orders that touch state are explicit sorts; determinism is pinned
   by two-identical-states over 12 ticks.
5. **Pricing and value** — one world price per good moves toward balance under
   `PRICE_ELASTICITY` off the world's own FLOW gap, clamped into the band; the
   month's output is then valued at the new price (`value_added_eur_bn`).
   Pricing itself is iteration-free: `STRUCTURE_ITERATIONS` is the FIXED
   iteration count of `_structure()` — the recipe-graph fixed point, not the
   price step — because a convergence test would be a rand-adjacent
   non-determinism this project refuses.

## §3b The drift, found and fixed (2026-10-14)

The claim above was false as shipped: measured on a new game in main.gd's order,
2 goods sat at >= 1.25x base at month 1, 15 at month 3 and 21 from month 6 on,
12 of them at the 1.75x clamp for the rest of a 168-month run. Two causes, both
fixed:

- **The gap counted intermediate use twice.** Demand reads `_structure()`, which
  already weighs each good by every recipe's use of it, but the gap compared it
  with production NETTED of what the recipes downstream consumed. It now reads
  gross production (`_produce`'s `gross`); the netted figure still feeds output,
  trade and value added.
- **Six recipes cost more in inputs than their output was worth** at base price
  (clothing's cotton alone was 204 against a base of 25). `goods.json` rebased
  clothing 474, appliances 1390, consumer electronics 1440, electronics 2080,
  pharma 4980, uranium fuel 72000 -- relative prices, at least twice the inputs'
  cost, values from the 2026-10-14 probe rather than authored research.

A third finding came out of the first: **a supply shock never reached a price.**
Demand's sector mix was read off the live register, so a nation that lost its
industry took the same slice out of world demand and the gap stayed 0 (the old
shortage test passed only because steel was drifting up anyway). Demand's MIX is
now anchored to the authored sector shares in `data/nations` while its SIZE stays
live world output.

Measured after (scratch probe, Energy -> Economy -> Commodities -> Budget ->
Inflation -> Demography, FRA, 168 months): 0 goods >= 1.25x through month 120,
1 at month 168 (clothing at 1.27x, a slow creep from 1.04x at month 1 that the
probe did not attribute); 0 at the clamp. FRA's industry zeroed for six months
moves steel from 1.005x to 1.105x base against 1.004x in the control run; before
the fix both runs read 1.677x.

## §4 The constants

The machine's five, in `src/sim/commodity_constants.gd`: `PRICE_BAND` 0.75 (the
tier's own precedent, not tuned), `PRICE_ELASTICITY` 0.30, `DEMAND_ELASTICITY`
1.0 (the unit-elastic price response), `TRADE_RATE` 0.50,
`STRUCTURE_ITERATIONS` 24. The world starts in balance by construction, so
PRICE_ELASTICITY is UNVALIDATED — its sweep belongs to whichever task first
lets a player cause a shortage (V4.7's firm verbs are the first candidates).
(0.10 is one of the sweep points named in the constant's own comment, never the
shipped value.)

`SHORTAGE_COVERAGE` 0.25 is a PANEL const, deliberately not a constants-file
entry: that file holds the model's tuning the tick reads, and this is a
presentation threshold the simulation never sees — so it lives beside its only
reader at `src/ui/commodities_panel.gd`. The register carries NO stock — the
alert reads month-flow coverage, the substitution stated at the constant.

## §5 Recorded limitations, each with its reason

- **Route by cost, not availability** — a nation with no coal takes the
  coal route and makes nothing where the electric route was affordable.
  Fixing it needs an availability-weighted route table; deferred until a
  verb can see the difference.
- **`labour_per_unit` / `capital_per_unit` are read by nothing** — no wage
  or capital price exists; V4.7's labour market is where they land.
- **No stock** — a carried stock drove the price vector to 0.50× base under
  a three-month cap in the first prototype; the flow form replaced it
  (measured, recorded at the site).
- **The GDP-delta channel is built but unwired** — `value_added_eur_bn` is
  computed and consumed by no sim module; the UI surfaces read it (§2), and
  wiring it into Economy is a later block's decision, deliberately not taken
  here.

## §6 The aliasing lesson (predates this block, sharpened by it)

`to_dict()` hands out live references, so `from_dict` must REBUILD every
register, never assign. The V4.6 serialisation landed rebuild-style because
the implementer measured two states sharing one register (3 months of drift
per loop). The same hazard is still LIVE for the older whole-dict fields —
`companies`, `plants`, `projects`, `sector_investment`, `service_quality`,
`last_company_result` are assigned straight through in `from_dict` and are
unguarded. Latent only (it bites when a caller mutates a state serialised
from another), and older than V4.6 — recorded here and in the block ledger
so the sweep that fixes it cannot be forgotten.

## §7 What is pinned where

- `tests/test_commodities_data.gd` — register/recipe integrity, load errors loud.
- `tests/test_commodities.gd` — leaf property (source-read), single writer
  (src-wide scan), determinism (two states + duplicate, 12 ticks), price band
  under collapsed endowment, production-chain completeness (the topological
  pin), lazy-seed check (three legs), tick order after Economy before
  Opinion in `src/sim/world_month.gd` -- the one month the game and every
  balance harness run (source-read; `tests/test_world_month.gd` holds the
  harnesses to it).
- `tests/test_commodities_panel.gd` — registration one-source, month-0 build,
  tree one-line-per-recipe (keyed by recipe id), shortage flip at the exact edge
  with whole-register takeover, map-mode toggles, legend swatch AND rendered
  stop text (the `%%` lesson: assert what the player reads).
- `tests/test_save_load.gd` — round-trip with every one of the seven keys
  moved off default; relative+absolute float tolerance measured in the
  comment; mutation-based aliasing pin.
- `tests/test_endowments.gd` (V4.11b) — every natural good endowed and summing
  to one, the outline register one-for-one with the map, Europe's roster share
  of four imported goods under 0.10, Germany's steel made from imported ore, the
  natural goods opening within 2 %, a pool cut moving lithium's price.
- `tools/endowment_probe.gd` (V4.11b2, not a test) — §8's four bands on
  `main.gd`'s month order, the Commodities tick time, the price-high crossings
  and each good's peak; runs on a pre-V4.11b tree for the baseline.

## §8 V4.11 — real endowments and the world pool (clauses declared BEFORE the code, 2026-10-16)

Plan: `docs/superpowers/plans/2026-10-16-v4.11b-the-world-pool.md`. The author's
call: REAL endowments for raw and agricultural goods, for every producer — the 41
and the world's 133 outlines — traded through one world pool.

**Why, measured.** At 41 nations every price sat at 1.00× base after 36 months:
the world was balanced by construction, because each nation's capacity for every
good — lithium ore and rare earths included — was its sector output times a
structure weight, the same weight its demand reads. Europe "mined" lithium in
proportion to its industry. A world pool added beside that could only glut.

**Endowment.** For each good in categories `raw` and `agri`, a producer's capacity
is `share[g][p] × W[g]`: `share` its fraction of WORLD production (content,
`data/commodities/endowments.json`, generated from USGS / OWID / FAOSTAT), `W[g]`
the world volume — the sum of every producer's REQUIREMENT for g. A roster
nation's requirement is what its own industry processes: the pre-V4.11 capacity,
sector output times the structure weight, read from AUTHORED figures for `W`.
An outline's is its own GDP through the world sector mix and the same weight
(`data/world/outlines.json`). The world therefore starts balanced at base prices
(no opening shock); what changes is WHO makes it. `W` reads authored figures
only, so capacity is a pure function of content: no state, no save field.

> [!note] Corrected before the first commit (2026-10-16)
> The first cut sized `W` and routed natural goods on each nation's
> POPULATION-based want. Measured at month 1, Germany held exactly its want of
> coal and ore, its coke and power plants took all the coal, and its steel
> stopped -- an industrial nation processes more than its people's basket. The
> requirement is what the recipes need, and with it a fully supplied nation
> produces exactly what it did before V4.11.

**The world pool.** The outlines aggregated: one seller and one buyer per good,
carrying their summed shares (plus the sources' unnamed "other countries"
remainder) and their summed demand. No per-outline state, no domestic model.

**Order.** Raw and agri goods route FIRST, on REQUIREMENT minus endowment —
roster sellers, then the pool, against roster buyers in sorted id order; the pool
buys any roster surplus left — and
downstream production then reads each nation's POST-TRADE holdings of raw and
agri inputs, so steel can be made from imported ore. Manufactures and services
route after production exactly as before (a closed roster market — a bound).

**Bands, declared now and checked in V4.11b2:**

- (i) the month-1 price vector within ±2 % of base for every good;
- (ii) the EU-27's net import share of lithium ore, rare earths, crude oil and
  nickel ore ≥ 0.70 at month 12 — Europe imports what it actually imports;
- (iii) a six-month 50 % cut in the pool's supply of one good moves that good's
  price to ≥ 1.25× base, the `commodity_price_high` hook's line — the observable
  that makes the pool a foreign-policy surface;
- (iv) no good pinned at the ±75 % clamp at rest after 120 months.

**Refused, with reasons:** per-outline state (the tier: no domestic model);
outline relations (no reader — `someday`); an export-control verb (the tier's
V4.6 lift was never built, and building it is its own block); manufactures
crossing to the outlines (no measured source for outline manufacturing that the
structure weights would not simply invent).

### §8 as measured (V4.11b2, 2026-10-16)

`tools/endowment_probe.gd` on `main.gd`'s month order, base `d6a24346` (before
V4.11b) against the tip:

| Band | Line | Measured | Verdict |
|---|---|---|---|
| (i) natural goods at month 1 | within ±2 % | worst 0.01 % (crude oil) | PASS |
| (ii) EU-27 net import share at month 12 | ≥ 0.70 | lithium 0.991, rare earths 1.000, crude oil 0.976 (0.987 before the review's energy fix), nickel 1.000 | PASS |
| (iii) 50 % pool cut for six months, from rest at month 12 | ≥ 1.25× | 1.75× (the clamp) for each of lithium, rare earths, nickel, crude oil, copper, uranium; over 1.25 in the cut's second month | PASS |
| (iv) pinned at the clamp after 120 months | none | none | PASS |

- **Band (i) is scoped to NATURAL goods, by measurement, not by tuning.** The
  manufactures open off base (worst 3.8 % at month 1) as they did before this
  block; §3b's drift record owns them.
- **Band (ii) divides by HOLDINGS** (endowment plus net trade, what EU industry
  processes). The b1 scratch read 1.12 by dividing by population demand, the
  wrong yardstick.
- **Band (iii) is a cliff, not a curve, at 50 %.** The pool supplies nearly all of
  Europe's ore, so halving it is a world shortage near half, and any lasting gap
  walks the price to the clamp. The dose rows grade it: lithium cut by 5 % reads
  1.057× after six months, 10 % reads 1.117×, 20 % reads 1.255× (over the line in
  the sixth month). A future supply verb has a usable range below ~20 %.
- **The long run changed shape.** Base: every agricultural good drifts to 1.12×
  and clothing to 1.20× by month 120, still rising; no price crosses 1.25×. Tip:
  natural goods hold (none reaches 1.10×), a manufactures wave peaks near 1.13×
  around month 84, and clothing crosses 1.25× once (1.278× at month 96, back to
  1.202× by month 120) -- the one crossing of the `commodity_price_high` line,
  seen by all 41 nations. Clothing's creep predates the block (it reached 1.27×
  at month ~160 before); V4.11b moves its crossing from ~160 to 96. The wave's
  cause is NOT isolated. The likely one, unverified: `W` is static (authored
  figures) while economies grow, so world supply of natural goods stands still as
  requirement rises -- recorded in [[someday]].
- **Re-measured after the V4.11 review (2026-10-17).** The energy endowments had
  read every producer at the world's latest year, and OWID's small-producer series
  end in 2016 -- so 19 roster nations' oil, 16 nations' gas and six nations' coal
  (Germany's, France's and Poland's oil among them, Kosovo's lignite through a blank
  OWID code) read zero and sat in the pool. Each producer now reads its own latest
  year within ten (`producer_years` in the data names each). All four bands still
  PASS; crude oil's EU import share reads 0.976 (was 0.987); the wave peaks at 1.136×
  near month 85, and clothing does NOT cross: 1.202× at month 120, 0 crossings of
  the hook line in 120 months. The tick is unchanged (46.3 ms).
- **No player-facing effect today.** The hook has no consumer (V4.4 pass 23
  unbound its two events, and the author kept them unbound on 2026-10-14), and
  value added feeds no GDP. The balance re-run (51 regimes, 168 months) came back
  BYTE-IDENTICAL, base against tip, and V4.4's E4/E5 tables are identical with
  every band PASSED (12.0 arrivals per term) -- though E4/E5's chain never ticks
  Commodities, so their identity says nothing about this layer (someday's
  re-bind trigger (3)).
- **Tick:** `Commodities.tick_month` 40.1 → 46.5 ms mean (+16 %; the routing
  pass and the pool), about 1.6 % of the 392 ms month.
