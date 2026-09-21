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

- `capacity` — per good, seeded at `init_nation` from the nation's measured
  sector shares and population (raw/agri/services goods track their matching
  sector; manufacturable goods seed from recipe depth and input capacity).
- `demand`, `output` — per good per month. `output` is NET of what the
  nation's own downstream recipes consumed; the net form is what makes
  `value_added` genuinely value added rather than gross.
- `surplus`, `trade` — pre- and post-routing balances; `trade` is what
  crossed the border this month.
- `price` — one world price per good, clamped to [0.25×, 1.75×] of the
  authored base every write (the tier's ±75 % band; `PRICE_BAND`).
- `value_added` — per good, the sum that a later block's GDP-delta channel
  will read. NOTHING READS IT YET (see §5).

Serialised whole on SAVE_VERSION 37 (V4.6's bump) with a per-entry rebuild
in `from_dict` — the aliasing-safe pattern; see §6.

## §3 The machine, one pass per month

1. **Lazy seed** — `tick_month` seeds any nation whose register is `{}` via
   `init_nation` itself: one seeding route, the single-writer pin survives,
   and a pre-37 save loaded mid-term cannot crash (pinned three ways in
   `tests/test_commodities.gd`, including the stripped-payload leg that
   simulates exactly the old save).
2. **Production, topological** — goods produce in `_production_order()`,
   a total order (recipe-graph depth, then id) computed once per tick from
   loader content alone (`_static_tables()`; hoisting it per-nation was
   measured at 228 ms/tick and fixed — 44 ms after, fingerprint identical
   to the bit). Missing inputs read as zero is the defect that order
   exists to prevent: the first draft produced steel and machinery out of
   nothing because `CATEGORY_ORDER` was not topological — deleted, with
   the bug shape recorded at the deletion site.
3. **Routing** — per good, surplus nations feed deficit nations in sorted
   id order, half the deficit per step, `TRADE_RATE` iterations. All
   iteration orders that touch state are explicit sorts; determinism is
   pinned by two-identical-states over 12 ticks.
4. **Pricing** — one world price per good moves toward balance under
   `PRICE_ELASTICITY`, clamped into the band. `STRUCTURE_ITERATIONS`
   relaxations, fixed count — a convergence test would be a rand-adjacent
   non-determinism this project refuses.

## §4 The constants (`src/sim/commodity_constants.gd`)

`PRICE_BAND` 0.75 (the tier's own precedent, not tuned), `PRICE_ELASTICITY`
0.10, `DEMAND_ELASTICITY`, `TRADE_RATE`, `STRUCTURE_ITERATIONS`,
`SHORTAGE_COVERAGE` (the panel's alert threshold; the register carries NO
stock — the alert reads month-flow coverage, the substitution stated at the
constant). The world starts in balance by construction, so PRICE_ELASTICITY
is UNVALIDATED — its sweep belongs to whichever task first lets a player
cause a shortage (V4.7's firm verbs are the first candidates).

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
- **The GDP-delta channel is built but unwired** — `value_added` is
  computed and consumed by no sim module; wiring it into Economy is a
  later block's decision, deliberately not taken here.

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
  pin), lazy-seed bridge (three legs), tick order after Economy before
  Opinion in `main.gd::_on_month_elapsed` AND `tools/balance_probe.gd`
  (source-read over both mirrors).
- `tests/test_commodities_panel.gd` — registration one-source, month-0 build,
  shortage flip at the exact edge with whole-register takeover, map-mode
  toggles, legend swatch AND rendered stop text (the `%%` lesson: assert what
  the player reads).
- `tests/test_save_load.gd` — round-trip with every one of the seven keys
  moved off default; relative+absolute float tolerance measured in the
  comment; mutation-based aliasing pin.
