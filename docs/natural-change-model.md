---
title: Natural Change Model
tags:
  - model
  - simulation
---

# Natural change — V2.6c

Births minus deaths, per region, as a measured rate that moves the population
shares V2.6a made live. This closes the V2.6 block: people now move between
places *and* places now grow and shrink on their own biology, and the national
total stays the measured figure it has always been.

Related: [[migration-model]] · [[demography-model]] · [[region-economy-model]] ·
[[geography-model]] · [[tiers/v2]] · [[data-sources]]

## 1. What changed

One new content field and one new flow:

- **`natural_change_pct`** — every region in `data/regions/`, per cent per year,
  signed, the window-averaged crude rate of natural change from Eurostat
  `demo_r_gind3`'s NATGROWRT. Written by `tools/import_data.py`; absent is an
  import error, not a zero (`src/core/region.gd` refuses it).
- **`src/sim/natural_change.gd`** — the strictest leaf in `src/sim/`: no preloads,
  no NationState, no writes. Three static functions — `share_delta()`,
  `named_mean()`, `deltas()` — and the caller applies what comes back, so
  `migration.gd` stays the **single writer** to the population-share registers.
- **`migration.gd` composes it** at the bottom of `_tick_nation()`, ungated by
  `MIGRATION_RATE` (zeroing the rate isolates migration; the natural flow must
  keep running through that isolation for it to stay an isolation of migration
  alone). The guard moved from `tick_month()` into `_tick_nation()` for exactly
  that reason.

`src/sim/demography.gd` is untouched. `ns.population` is untouched. `SAVE_VERSION`
stays 30 — content round-trips through `data/regions/` the way `gdp_share` does,
and the eleven pins in `tests/test_save_load.gd` pass unchanged.

## 2. The step-0 gate, and the row that named the wrong instrument

The decomposition note gated this session on **regional age structure from
`demo_r_pjangrp3`** — 22 brackets confirmed at FR10@2021 — and refused the
re-split of one measured `pop_growth_pct` into births and deaths without it. The
gate's premise was the stale row: the sibling dataset **`demo_r_gind3` publishes
NATGROWRT, the crude rate of natural change, directly per region**. Probed exactly:

| probe | result |
|---|---|
| FR10 (NUTS 2) @2022 | births 13.1‰, deaths 6.6‰, **NATGROWRT +6.5‰** |
| FR1 (NUTS 1) @2022 | **+6.5‰** — NUTS 1 rates exist, the register's level for FRA/DEU/GBR/BEL |
| DE1 Baden-Württemberg @2022 | **−1.8‰** |
| UKI London @2018 | **+7.9‰** |
| UKC North East @2018 | **−0.7‰** — Britain measured, series ends 2018 |
| NL31 @2023 | **empty** — the totals window does not survive per-series |

Importing brackets to author an age-mix-to-rate mapping would have been the
weighted sum [[demography-model]] §2 refused — a number nothing could measure.
The direct rate needs no coefficient. **The instrument upgrade shrank the build**:
no second import pipeline, no stored age structure.

The gate's other half — *name what reads a head count* — passed cold: map crosses,
city panel, region panel, the economy panel's per-head index, migration's two
pulls, unrest siting, campaign reach, `labour_force()`. Eight readers, no new one.

## 3. The partition decision

**The regions partition the national growth; the national number is not re-based
from regional rates.** `pop_growth_pct` already carries natural change inside
Economy's measured compound, and V1.4a's idiom does the rest: the flow moves each
region's share by its differential against the mean, so the named regions
redistribute the natural component among themselves and the national figure holds
exactly. The refused alternative — re-deriving the national total from regional
rates — is a re-baseline: budgeted, never discovered.

The **unnamed residual** (extra-regio and rural, ~3–5 % of each nation) carries no
rate of its own and implicitly grows at the national rate. Authoring it one would
be a number nobody measured — migration's frozen residuals, one session later.

**Cities ride their region.** There is no data below NUTS 3; `city_pop_share` is
untouched, and Paris grows because Île-de-France does. The ride reaches the cities
through `city_population()`, which has multiplied the live shares since V2.2b.

## 4. The anchor, and which side of the lesson it sits on

The mean is taken in **live share weights**, recomputed every month against the
same snapshot the deltas use — so the sum telescopes to exactly zero over the
named regions, migration's invariant applied to a third flow.

**Population-weighted mean-one is RIGHT here.** V2.6b2 moved campaign reach OFF
population weighting because reach is delivered where the PLAYER goes; this is the
other side of that line — the V2.6b1 output-price side. Births happen where the
people are; a region's birth rate is per-head biology, and a uniform mean-one
anchor would claim a region's rate tells its people nothing about where births
happen. The live mean is also what makes the flow self-damping: a region growing
by natural change raises the mean it is measured against — Harris–Todaro's
negative feedback with the mechanism replaced.

## 5. The measured content

Per-nation window = the widest contiguous run of years in which **every** register
code carries a value (`tools/region_drift.py`'s rule applied to a rate); rates are
averaged over it, because the 2020–2021 COVID deaths would otherwise date-stamp
the field. `tools/natural_change_probe.gd` table (a) prints the roster:

| nation | window | high | low | spread | share-wtd mean |
|---|---|---|---|---|---|
| AUT | 2012–2024 | Vorarlberg +0.245 | Burgenland −0.421 | 0.666 | −0.024 |
| BEL | 2012–2024 | Brussels +0.634 | Wallonia −0.052 | 0.686 | +0.064 |
| CHE | 2012–2024 | Zürich +0.340 | Ticino −0.177 | 0.517 | +0.193 |
| DEU | 2012–2024 | Hamburg +0.090 | Sachsen-Anhalt −0.778 | 0.868 | −0.258 |
| ESP | 2012–2024 | Melilla +0.849 | Asturias −0.739 | 1.588 | −0.103 |
| FRA | 2014–2024 | Île-de-France +0.748 | Nouvelle-Aquitaine −0.206 | 0.954 | +0.154 |
| GBR | — | **0.000 everywhere** | | 0.000 | 0.000 |
| ITA | 2012–2024 | Bolzano +0.125 | Liguria −0.824 | 0.949 | −0.348 |
| LUX | 2012–2024 | Luxembourg +0.339 | (one region) | 0.000 | +0.339 |
| NLD | 2012–2022 | Flevoland +0.584 | Limburg −0.284 | 0.868 | +0.113 |

**BRITAIN CARRIES 0.0 EVERYWHERE, AND THE MEASURED NUMBERS ARE RECORDED BESIDE THE
BOUND.** Eleven of its twelve NUTS 1 codes carry rates 2012–2018 — London +0.79
down to the North East's −0.07, a bigger spread than most nations' migration
produces — but **UKM (Scotland) publishes no rates at ANY year**, and a
differential mixing measured and invented rates invents flows toward and away from
Scotland no measurement supports. Partial measurement inside one nation would be
worse than none: the differential is a RELATIVE quantity. So the bound extends
rather than breaks — Britain differs by employers only, V2.5 §8's call one
quantity over — and the day Scotland publishes, the import picks the rates up and
`tests/test_natural_change.gd`'s zero assertion turns red and says so.

**The Netherlands' window stops at 2022**: NL31/NL33 vanish from THIS series one
year before `demo_r_pjangrp3`'s re-coding to NL35/NL36. Each series gets its own
vintage ruling; the totals ruling did not survive per-series, exactly as the gate
predicted. FRA's window starts at 2014 (one code unpublished at 2013); 2025 is
incomplete for every nation, so no window reaches it.

**Luxembourg transforms, as the plan said it would**: one region cannot differ
from itself in a share — `rate == mean` exactly, `deltas()` returns empty below
two regions, and `tests/test_natural_change.gd` asserts the share is EXACTLY
unchanged after 168 months — but the national total was never bound: natural
change moves `pop_growth_pct`, which was always live.

## 6. The re-sweep, and the finding: natural change dominates

`MIGRATION_RATE` was the only free lever, and the combined model re-swept it under
clauses re-stated before the run:

- **(0)** the natural flow ALONE must hold clause (ii)'s ceiling — measured on the
  sweep's own rate-0.0 row: **worst 0.01558 (FRA), 95 % of the 0.0164 ceiling.
  PASSES**, margin recorded rather than rounded away.
- **(i)** readability ≥ 0.001 @60mo — satisfied at EVERY candidate by the natural
  differential alone (FRA 0.00546 with the rate at zero). **The clause no longer
  selects**; the band's lower edge is the structural floor at 0.0000.
- **(ii)** worst combined drift ≤ 0.0164 @168mo, read across ALL TEN nations now
  — the natural rates arrive with their own ranking nobody had measured.

`tools/migration_probe.gd` table (e), the emulation carrying the natural flow
ungated so the rate-0.0 row IS clause (0):

| rate | FRA r@60 | worst combined @168 | band |
|---|---|---|---|
| 0.0000 | 0.00546 | 0.01558 | PASS — clause (0), natural alone |
| **0.0003** | 0.00561 | 0.01599 | **PASS — SHIPPED, the midpoint** |
| 0.0005 | 0.00571 | 0.01627 | PASS |
| 0.00055 | 0.00574 | 0.01633 | PASS |
| 0.0006 | 0.00576 | 0.01640 | fail (ii) — the crossing |
| 0.0102 | 0.01038 | 0.02844 | fail (ii) — V2.6a's shipped value |

Passing interval **[0.0000, ~0.00057], midpoint 0.0003**, stable across both
full-band grids (step 0.0001 and 0.00005 — V1.5b's refinement diagnostic). The
response stays linear in the rate; the crossing is smooth.

**THE FINDING: AT THE RATES EUROPE'S MEASURED DRIFT CEILING PERMITS, NATURAL
CHANGE DOMINATES INTERNAL MIGRATION.** `MIGRATION_RATE` falls 0.0102 → 0.0003, a
factor of 34, and migration's own readable contribution — V2.6a's clause-(i) floor,
DEU 0.00126 @60 — is no longer deliverable at any rate the ceiling permits. The
reason is structural and recorded rather than patched: the two flows point the same
way in the model (Harris–Todaro pulls INTO the region whose births already outpace
the nation — Île-de-France is France's richest region AND its most natal), where
real Europe's rich regions EXPORT people. The flows compound instead of cancelling,
and the ceiling — which measures TOTAL real drift, natural and migration together —
holds the sum to Wien's number. The pull form carries no congestion or housing-cost
term, and authoring one would be a weight nobody measured. **A later session that
wants to raise the rate must first name the term that makes real Parisians leave
Paris.** `tools/natural_change_probe.gd` table (c) prints the disagreement per
nation — Spain's most natal region (Melilla, +0.95 ‰/yr above the mean) has the
WORST expected income, and the Netherlands' Flevoland is second-most-natal at pull
rank 10 of 12: the flows oppose there, which is why `test_migration.gd`'s direction
check isolates migration by zeroing the natural rates.

**The ceiling now binds at 2.5 % slack** (0.01599 against 0.0164 at the shipped
value), where V2.6a's migration-only model ran at 0.0137 with 16 % to spare.
`SHARE_DRIFT_MAX` stays 0.05, slack 0.034 — a guard rail doing its job.

## 7. Attribution at the shipped rate

`tools/natural_change_probe.gd` table (b), worst drift @168 months:

| nation | natural-only | migration-only | combined | ceiling |
|---|---|---|---|---|
| FRA | **0.0156** | 0.0004 | 0.0160 | PASS |
| BEL | 0.0087 | 0.0004 | 0.0089 | PASS |
| ESP | 0.0052 | 0.0002 | 0.0054 | PASS |
| NLD | 0.0035 | 0.0002 | 0.0035 | PASS |
| AUT | 0.0049 | 0.0001 | 0.0050 | PASS |
| DEU | 0.0033 | 0.0001 | 0.0033 | PASS |
| CHE | 0.0037 | 0.0001 | 0.0038 | PASS |
| ITA | 0.0028 | 0.0003 | 0.0026 | PASS |
| GBR, LUX | 0.0000 | 0.0000 | 0.0000 | PASS |

The natural column is 97–99 % of the combined movement in nine of ten. ITA is the
one nation where migration's contribution visibly offsets the natural flow
(combined below natural-only) — the pull and the differential disagree there, and
the weaker migration rate lets the disagreement show.

## 8. What natural change prices

**Nothing new.** The political price is refused a third time — a regional opinion
channel is *a second approval figure with a different label*, V1.5c's reason,
declined at V2.6a and V2.6b1 and declined here. Natural change prices through the
channels that exist: the shares it moves feed the per-head index, the pulls, the
siting weights and the campaign reach, and every one of those prices in digits the
existing economy and budget channels already carry. A region that empties empties
its tax base and its grievance density through arithmetic the game already runs.

## 9. What is deliberately not built

- **Life expectancy as a separate live quantity.** The death component of the
  measured natural rate already carries it; a second answer to the same question.
- **A regional age structure.** The brackets exist; the mapping to rates would be
  the weighted sum nothing could measure. The direct rate made it unnecessary.
- **A per-city natural rate.** No data below NUTS 3; cities ride their region.
- **A rate for the unnamed residual.** Extra-regio and rural grow at the national
  rate by construction; authoring one would be a number nobody measured.
- **A rural pull or net urbanisation.** Migration's §4 refusal, unchanged — both
  residuals stay frozen, and the natural flow moves only the named regions among
  themselves.
- **A fertility response to `childcare_expansion`.** [[demography-model]] §13's
  standing refusal, untouched.

## 10. Test and probe inventory

- `tests/test_natural_change.gd` — direction (direct `share_delta()` calls at
  test-supplied rates), exact conservation of the COMBINED flow over 168 months at
  1e-12 absolute on all ten nations (conservation IS the call-site pairing
  assertion: a swapped argument stops the sum telescoping), the national figure
  untouched, Luxembourg exactly unchanged, the paired-run ride (Paris ends larger
  with the field than without it), the field's own import contract (Britain at
  zero, every other nation with a real spread), and the composition read from
  source (the leaf preloads nothing and names no register; `migration.gd` calls
  `NaturalChange.deltas()`).
- `tests/test_migration.gd` — the direction check now **isolates migration** by
  zeroing the natural rates for the tick and restoring after (Spain's Melilla and
  the Netherlands' Flevoland are the live counterexamples: most natal, worst
  pull), with the reason recorded in the file.
- `tests/test_geography.gd` — `natural_change_pct` joins the one-reader scan's
  marker list; the register still has exactly one reader, and the rate reaches the
  flow through `Regions.natural_change()`, an accessor named for the quantity
  rather than the field (`share_of()`'s naming rule).
- `tools/natural_change_probe.gd` — the rates themselves, the attribution table,
  and the differential-against-pull disagreement table.
- `tools/migration_probe.gd` — the emulation, the sweep and clause (ii) all run on
  the combined model; the rate-0.0 sweep row is clause (0).

## 11. The screenshot pass

Two frames, no new flag, no new surface — the readouts that multiply the shares
have shown the movement since V2.2b, and the pass judged them rather than the
field. `--move` (ten years of the combined flow, the City panel's list): Paris at
2.4 M, the ledger refreshed, clean. `--site`: **Lille — 246 k — where the unions
are out**, the siting still Hauts-de-France. And the pass found **one bug, older
than the session**: V2.6b2's `_site_the_demonstration()` read `staged["city_id"]`
off the empty dictionary bare `--site` stages, so the bare flag had crashed since
V2.6b2 — its own pass only ever ran `--campaign --site`. Fixed with `.get` and the
reason recorded at the call site; third session running the screenshot pass's bug
predates the session that found it.

## 12. The balance re-run, against a prediction written before it

**PREDICTION**: national headline figures (population, GDP, growth, unemployment,
debt) bit-identical in every regime — no national equation reads the shares;
movers only where the sim reads them — siting (Germany's +0.4 % Ruhr → Berlin
margin the named watch-point), campaign reach in the campaign regimes, and the
unrest price via the site's per-head index in the unrest-firing FRA regimes;
**zero outcome changes**, a verdict flip being a finding to chase rather than a
tolerance to widen.

**MEASURED**: both sides from worktrees (a06b3da against 587557a), 1646 content
lines each, 48 `invariants: OK` lines each, tails identical — V1.7c's
third-stray-line check clean, the addon parse noise two-sided and cancelled.
**4 content lines differ, all last-printed digits**: one regime's unrest peak
48.29 → 48.28; one campaign reach figure +1.641 → +1.642 pts; two opinion digits
in one regime's 2032 row (+3.28 → +3.29, 19.3 → 19.4). National headlines
bit-identical in every regime — GDP 3009, growth +1.52/+1.31, unemployment 8.35
and debt 107.9 print the same on both sides. **Zero outcome changes.** The named
watch-point held: Germany's siting margin did not flip, and no siting line moved
at all — the natural differential moved the shares by ~1.5 % relative over
fourteen years and the site margins are wider than that.

Quieter than the same measurement at V2.6b1 (3 movers) and V2.6b2 (2 regimes +
one noise block): the migration flow that drove those movers is now 34× weaker,
and the natural flow's own contribution reaches the sim readers mostly through
margins that were already wide.
## V3.3: Luxembourg's bound is now six nations'

CYP, EST, LTU, LVA and MLT are single-region at NUTS 2 like LUX: one region
cannot differ from itself, so the differential is exactly zero everywhere and
the nation's total moves only through the live national compound. All five
carry MEASURED rates (Eurostat covers them; only Britain's UKM hole keeps the
zero-everywhere rule). test_natural_change's spread assertion reads the
register's own size rather than a nation list, so it needed no edit -- the
bound generalised in data the way Rule 1 says it should.

