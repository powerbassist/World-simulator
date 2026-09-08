---
title: Migration Model
tags:
  - model
  - simulation
---

# People Move

The two population partitions become live. Built at [[ROADMAP|V2.6a]];
[[tiers/v2|V2]] section 6. The register it reads is [[geography-model|V2.2a]]'s
and the quantities it migrates on are [[region-economy-model|V2.5]]'s.

## 1. What changed

V2.2a authored a region's share of its nation's population and a city's share of
its region as **content**, and nothing moved them. V2.6a seeds both onto
`NationState` (`region_pop_share`, `city_pop_share`) — `Migration.init_nation()`,
called once from `GameState.new_game()` beside `Regions.init_nation()`, for its
reason: each seeds a live stock — and `Migration.tick_month()` moves them every
month. The expression `src/ui/city_panel.gd`, `src/ui/region_panel.gd` and
`src/ui/map_cities.gd` have all used since V2.2b — population × region share ×
city share — starts telling a different story each year without any of them
changing a line of arithmetic: the map's brass crosses grow and shrink for free,
and the panels' league tables reorder themselves.

There is no new window, no new keyboard key and **no verb**. The one new surface
is `--move`, which ticks ten years through the real clock and opens the City
panel on its ranked list — the ranking is the claim the flag exists to
photograph. An early draft called it the twenty-fifth screenshot flag and the
ordinal is dropped rather than defended: no basis survives a recount —
AGENTS.md's per-session list names twenty-three flags, `--bloc` and `--open`
arrived in prose, and V2.2b's two view flags and `tools/screenshot.gd`'s own
extras sit outside every one of those counts. The readout arrived the way
V2.5's did: the readers were already written, waiting for the quantity to move.

## 2. The three refused alternatives

**A weighted three-input attractiveness.** [[tiers/v2|§6]] names jobs,
unemployment and service quality. A weighted sum needs three coefficients nothing
could measure, and the third input cannot earn one: `service_quality` is **one
figure per nation** (`src/sim/society.gd`'s `QUALITY_KEYS`), so it has ZERO
variance across cities and cannot discriminate between two of them at any weight.
Dropped and recorded rather than included at a weight that would be measuring
nothing — V1.5b's deletion of `DEPENDENCY_ELASTICITY["health"]` on the same
reasoning. What replaced it is Harris–Todaro (§3), which carries **no free
weight** — a product of two ratios the register already publishes.

**A rural pull producing urbanisation.** The regional residual — rural and the
towns under the cut — is `1.0 − Σ` and is never stored, so it cannot be a
participant in a flow. Authoring a rural pull means storing the residual and
draining it, which breaks the partition idiom the register exists for, and nobody
has measured a rural pull to author anyway. The consequence is worth naming
because a later session will want it: **there is NO NET URBANISATION here**, and
a session that wants some has to author the pull rather than inherit one.

**One flat national partition of cities.** Simpler: all 581 cities holding
shares of the nation, one flow, one mean. Refused because the composition IS the
model — a city is a share of its **region** ([[geography-model|V2.2a]]'s own
call, *a city is to population what a firm is to sector output*), and the two
levels do different jobs: the region flow moves a region's total, the city flow
moves its distribution, and only together do they say "Île-de-France grows while
its cities redistribute". A flat partition also cannot close: each region's city
sum is conserved by the city level, which is what lets both levels read
start-of-month state (§4), and a national flow has no unit whose sum holds.

## 3. The two pulls, and why each is the one its level can see

**Between regions: Harris–Todaro expected income.**

```
region_pull = output per head × probability of being employed
            = (Regions.share_of / live pop share) × (1 − regional unemployment)
```

The textbook model of internal migration, chosen because it carries no
coefficient: a wage nobody can get is worth nothing and a job at half the wage is
worth half, which is the whole content of the multiplication. Output per head
divides by the **live** population share rather than the authored one, and that is
what closes the loop: a region people leave has fewer heads to divide its output
between, so its pull rises and the outflow slows — **NEGATIVE FEEDBACK BY
CONSTRUCTION**, which is why `SHARE_DRIFT_MAX` is a bound with measured slack
rather than the thing setting the number (§6).

**Between a region's cities: named jobs per head.**

```
city_pull = Companies.headcount_in_city / city_population
```

A DIFFERENT SIGNAL AT A DIFFERENT LEVEL, and each is the one its level can see.
Every city in a region shares that region's output per head and its unemployment
rate — the register publishes neither below the region — so expected income
cannot separate Lille from a smaller city in the same region and named employers
can. That is V2.2a's own measured finding read as a mechanism: **one city holds a
third to a half of a nation's named payroll** (Lille 33.1 %, Düsseldorf 34.3 %,
Manchester 44.0 %). The pull is **zero for seven of the ten nations**, because
`data/companies/` names employers in three — a true zero rather than an absent
figure, `src/ui/region_panel.gd`'s own distinction, asserted exact-zero in
`tests/test_migration.gd` for every city of every nation with no employers file.
For those seven the region level is the whole of their movement.

`migration.gd` is deliberately **not a leaf**: it takes the loader the way
`Campaign.tick_month(state, loader)` and `Companies.tick_month(state, loader)`
do, because `city_pull()` needs per-firm headcount and firms are content. What it
does NOT do is name a register field — every regional quantity comes back through
a `Regions` function, so `tests/test_geography.gd`'s assertion that the register
has exactly one reader stays green, asserted on purpose rather than left to luck.

## 4. The zero-sum flow and the two frozen residuals

One expression, applied twice with different denominators — which is what keeps
this one machine rather than two:

```gdscript
static func share_delta(share: float, pull: float, mean: float, rate: float) -> float:
	return rate * share * (pull - mean) / 12.0
```

The mean is taken in the **same share weights**, so each level's sum telescopes
to exactly zero however extreme the spread — `Trade.sector_shift()`'s sum-to-zero
rule and V2.5's zero-mean deviation, the third instance and the first at two
levels at once. Because nothing here is exponentiated, there is no second-order
Jensen term to excuse a larger tolerance: the closure is checked at **1e-12
ABSOLUTE**, against a realised worst drift of **6.66e-16** (~1500× margin, table
(c)) — V2.5's partition needed 1e-9 *relative* for the same claim.

The flow is **proportional**, not absolute: `s × (1 + rate × (pull − mean)/12)`
cannot reach zero from a positive share for any rate small enough that the
monthly factor stays positive, so there is no share floor to set wrong and
`tests/test_migration.gd` asserts positivity instead of a clamp enforcing it.
That argument holds only because every pull is non-negative — the employment
probability stays in [0.6, 1.0] because `Regions.unemployment_pct()` is clamped
by `UNEMP_MAX_PCT = 40.0`, and both a head count and an output share are
non-negative by construction. Three facts that live in other modules; a session
that raises that clamp past 100 or adds a negative term to a pull owes the
no-floor claim a second look.

`share_delta()` is extracted as a pure function so the **direction** of the flow
is testable at all: conservation and direction are orthogonal failures, and a
sign-flipped flow passed every invariant this module asserts (it was caught
before it shipped — the direction check calls the function directly at a rate the
test supplies itself, rather than trusting whatever the shipped rate happens to
be to expose a sign). The month is ticked **cities first, regions second**, so
both levels read start-of-month state: swapping the order would make the city
pull divide by the region's POST-flow share — a same-month look-ahead the region
loop does not get. Every delta is computed against a frozen snapshot of shares
and pulls, so the result does not depend on the order the register is walked in.

The tick runs in all three harnesses — `src/ui/main.gd`, `tools/balance_probe.gd`
and `tests/test_balance.gd` — **after** `Economy.tick_month()` and
`Companies.tick_month()`, because the region pull reads settled output and the
city pull settled headcount. The order is asserted by comparing `find()` indices,
not by presence: a grep for a call cannot see the order it runs in, and a future
edit moving the call ahead of either would otherwise pass silently.

**The two residuals are frozen, for two different reasons worth keeping apart.**
The NATIONAL residual is extra-regio and the overseas regions the map's bounding
box has dropped since S8 — a person cannot migrate to somewhere the game does not
draw, so the named regions redistribute among themselves. The REGIONAL residual
is rural and the towns under the cut, and it carries the region's own mean, which
is the assignment that adds no information — `src/sim/regions.gd`'s treatment of
its own residual exactly. Neither is stored: a residual that is `1.0 − Σ` cannot
drift from the thing it is the remainder of.

## 5. Britain migrates on employers alone

**BRITAIN'S REGION COLUMN IS EXACTLY 0.0000 AT EVERY RATE**, and that is a
recorded bound with the number beside it, not a bug. [[region-economy-model|V2.5]]
§8 took the population proxy because ONS carries ten of twelve ITL1 codes and an
index besides, and measured **BRITAIN HAS NO REGIONAL DIVERGENCE AT ALL** at
`moved 0.000` — so every British region's expected income is identical by
construction, `pull − mean` is exactly zero at the region level, and the whole of
Britain's signal is named employers at the city level (Manchester 0.0026 of its
region at month 168, table (f)). Clause (i) is not read on it: its city column
reaches the floor only at a rate of ~0.095 against a clause (ii) crossing at
0.0123 — no rate satisfies both, and raising the rate until it did would break
clause (ii) for France by a factor of eight. V1.6e's treatment of a bound an
observable cannot reach: recorded, never tuned against. The day somebody authors
the twelve ITL1 figures, `tests/test_migration.gd`'s flat-pull assertion turns
red and says so.

**Luxembourg is the second bound and a harder one**: ONE region holding ONE city
(LU00), so `pull − mean` is exactly 0.0 at both levels and it cannot move at any
rate whatever. Same class as Britain, recorded beside it in table (f).

> **V2.6c: BRITAIN'S BOUND EXTENDS TO NATURAL CHANGE; LUXEMBOURG'S TRANSFORMS.** The
> plan-time premise — *demo_r_pjangrp3 carries all 41 UK codes, so Britain can age
> regionally* — was right about the dataset and wrong about the instrument: the
> rates came from `demo_r_gind3`, whose NATGROWRT covers **eleven of Britain's
> twelve** NUTS 1 codes (London +0.79 %/yr down to the North East's −0.07, window
> 2012–2018) but **UKM — Scotland — publishes none at any year**, and a differential
> mixing measured and invented rates invents flows toward and away from Scotland no
> measurement supports. So every British region carries `natural_change_pct` 0.0 and
> Britain differs by employers only, exactly as this section already recorded — the
> same call V2.5 §8 made, extended. The measured numbers are in
> [[natural-change-model]] §5, usable the day Scotland publishes. Luxembourg is the
> opposite case: one region cannot differ from itself in a SHARE, but the national
> total was never bound — natural change moves `pop_growth_pct`, which was always
> live — so its bound narrows to "no differential, ever" rather than "no growth".

Seven of the ten name no employer at all — `data/companies/` covers FRA, DEU and
GBR — so their city level is inert and the region level is the whole signal. The
city level is not decorative for the three that have it: France's and Germany's
largest city-level movers at month 168 are Lille and Stuttgart, and a month in
which a subsidy moved a firm's hiring moves people in the same month rather than
the next one, which is why the tick runs after `Companies.tick_month()`.

## 6. The band, the sweep, the interior, the bound's slack

Two clauses, both fixed before the sweep ran:

- **(i) READABLE.** Over 60 months — one presidential term — the largest mover's
  share of its nation must move at least **0.001**, one digit of
  `src/ui/region_panel.gd`'s own `%.1f%%`. A movement the panel printing it cannot
  resolve is not a movement the player can see. Read per playable nation, on FRA
  and DEU.
- **(ii) BOUNDED, AND THE CEILING IS MEASURED RATHER THAN BORROWED.** Over 168
  months no region's share may drift more than **0.0164**.

**The first version of clause (ii) read `SHARE_DRIFT_MAX`, and that was the
defect it was meant to avoid.** The bound is 0.05, it is evaluated on exactly the
quantity `Migration.worst_share_drift()` returns, and reading it as the band edge
made the clause and the guard rail ONE NUMBER WITH TWO NAMES — the upper crossing
restated the guard rail instead of measuring the model. This project names that
failure repeatedly: a band whose ceiling is the clamp measures the clamp
(V1.5c's ceiling was one regime's own peak; V1.6c and V1.6e each measured a clamp
a session apart). Caught mid-task, and the ceiling was re-measured from a ruler
the bound does not own:

> **The model's regional population shares may not drift further over fourteen
> years than real European regional population shares actually drift over a
> comparable span.** A model whose people move faster than Europe's people move
> is wrong in a way no internal consistency check can see.

`tools/region_drift.py` (committed, one command to re-derive) reads Eurostat
`demo_r_pjangrp3` 2014–2025 over **exactly the register's roster**, share of the
nation at each end, the widest window that keeps each nation's roster stable. The
ceiling is the LARGEST of the ten nations' worst regions and not their mean —
**0.016381, AT13 Wien, 2014–2025** (0.012871 raw over eleven years, scaled to
168 months), rounded to 0.0164 — because the model must be able to reproduce
Europe's most mobile real region without exceeding the ceiling, and a mean would
forbid the interesting case. Two windows stop early and both are recorded rather
than patched: Britain's series ends at 2019 (Eurostat dropped UK regions after
withdrawal, §8 of the region economy model), and the Dutch window stops at 2023
because NL31/NL33 vanish at 2024 into their 2024-vintage twins NL35/NL36 — equal
to the person — so a window crossing that boundary measures a RE-CODING rather
than a migration.

**V2.7 re-measured the band with a third mover live.** The transport session's
network term moves output per head — half the Harris–Todaro pull — so the
ceiling was re-swept with `NETWORK_BETA` at its shipped value, and the sweep
came back identical at every printed figure: natural-only 0.01558, the shipped
rate 0.01599, the interval unchanged. Migration owns 1–3 % of the combined
movement and the term perturbs the pull by a fraction of a per cent, so the
third mover's contribution lands below the table's fifth decimal. The ceiling
still binds `MIGRATION_RATE` at 2.5 % slack, and a fourth mover inherits it
binding. [[network-model]] §8.

**The ceiling is GENEROUS, not like-for-like, and the model doc must say so
because the player-facing claim is made on it.** The measured quantity is TOTAL
population-share change — fertility, mortality and international migration all
move a region's share of its nation — while the model moves only internal
migrants, with both residuals frozen. Europe's regions drift for reasons this
model does not have; a ceiling measured on all of them and handed to a machine
that moves people internally only is headroom the model did not earn, and the
honesty is that the bound is loose by construction rather than that the model is
slow.

**Headroom is about a third, on a definition stated rather than assumed, and it
is the interesting number rather than a comfortable one.** The definition: the
measured ceiling over the band's upper edge — 0.0164 / 0.0123 − 1 = 0.333, the
ceiling's figure a third above the edge's. The two figures are not the same unit
(the edge is a monthly rate, the ceiling a 168-month drift), so the ratio
compares magnitudes rather than like quantities; on the same formula against a
like quantity, the ceiling is ~20 % above the worst realised drift (0.0164 /
0.0137 − 1 = 0.197). Realised drift is linear in the rate: 0.0081 → 0.0110 at 168
months, 0.0102 → 0.0137, 0.0123 → 0.0163. Clause (i) crosses at 0.0081, so ANY
CEILING BELOW ABOUT 0.0110 EMPTIES THE PASSING INTERVAL ENTIRELY — a fired kill
switch, not a re-sweep, because there would be no rate left that is both readable
and bounded. The roster's runner-up is **ES30 Madrid at 0.009858 — BELOW that
collapse threshold**. If Austria's roster or the window ever moves and AT13 Wien
drops out, the next-largest real region in Europe does not clear clause (i) at
any rate. A re-measured ceiling that lands below ~0.0110 is a kill switch to be
HONOURED — V1.5b's deletion of `DEPENDENCY_ELASTICITY["health"]`, not a number to
tune around.

**The sweep**, emulating each candidate through `share_delta()` in the shipped
order rather than rescaling from the shipped value (a probe that rescales has its
passing interval move when the shipped value moves — V1.6b's "the range was
choosing the constant" in a second costume). Four grids, coarse to fine, because
an answer that moves under refinement is a statement about the grid rather than a
result:

```
step     passing interval        midpoint
0.0020   [0.0100, 0.0120]        0.0110
0.0005   [0.0085, 0.0120]        0.0103
0.0002   [0.0082, 0.0122]        0.0102
0.0001   [0.0081, 0.0123]        0.0102   <- SHIPPED
```

**`MIGRATION_RATE` is 0.0102**: interior to all four grids with candidates
failing on BOTH sides of each, and stable at the two finest resolutions — the
answer has stopped being a statement about the grid (V1.5b's diagnostic). The
response is linear in the rate, so both crossings are smooth and neither edge
selects; [[decision-log|V1.5d]]'s rule applies and the midpoint ships.

`SHARE_DRIFT_MAX` stays 0.05 and is now honestly a guard rail: **worst realised
drift 0.0137 (FRA), slack 0.0363, ~3× the measured ceiling** — a bound doing its
job rather than a dial that lost its purpose, checked and never clamped
(`projects_constants.gd`'s position). Its own comment now says out loud that it
must never be read as a band edge again.

**The realism was bought at a price, and the price is visible.** The defect's
sweep shipped 0.0273; the re-sweep ships 0.0102. Movement is proportional to the
rate, so the player-facing claim fell with it: FRA's month-60 mover reads 0.0051
against the 0.0131 the first sweep shipped, DEU's 0.00126 against 0.0033 — under
two-fifths of the movement for a ceiling that measures Europe rather than the
clamp. And the shipped rate sits only **1.26× above the clause-(i) crossing**:
DEU binds at 0.00126 against the 0.001 floor, so the readable claim is exactly
one panel digit and nothing more. That is the trade working — a rate with 3× the
headroom would have been the defect's arithmetic again — but a later session
tempted to raise the rate for show should read this paragraph before reaching for
the constant.

One judgment call the review priced: "the largest mover's share of its nation" is
ambiguous between *anywhere* and *per playable nation*. Under the literal first
reading the lower crossing lands on 0.0020 — the binding mover is still FRA, the
largest mover anywhere (table (f)'s 0.0137 at 168 leads every nation), whose
month-60 figure 0.0051 at the shipped rate crosses the 0.001 floor at
0.0102 × (0.001 / 0.0051) = 0.0020 — the first row of the coarsest grid, an
endpoint, which this project's own diagnostic calls a suspect rather than a
result. The clause-(ii) upper edge is unchanged at 0.0123, so the literal
midpoint of [0.0020, 0.0123] would read (0.0020 + 0.0123) / 2 ≈ 0.0072, about
30 % below the shipped 0.0102 ((0.0102 − 0.0072) / 0.0102 = 0.29). The per-nation
reading was taken; both the reading and the exclusion are written into
`migration_constants.gd`.

## 7. The measured tables

`tools/migration_probe.gd`, run at the shipped constants — the tables ARE the
model's evidence, and the sweep emulates candidates rather than rescaling (§6).

```
=== (a) starting pull spread: expected income, and named jobs ===
  AUT  best Salzburg                     1.1790 | worst Burgenland                   0.6621 | spread 0.5170 | named jobs 0
  BEL  best Région de Bruxelles-Capitale/Brussels Hoofdstedelijk Gewest 1.4424 | worst Région wallonne              0.6751 | spread 0.7673 | named jobs 0
  CHE  best Zürich                       1.1151 | worst Espace Mittelland            0.8701 | spread 0.2450 | named jobs 0
  DEU  best Hamburg                      1.6985 | worst Sachsen-Anhalt               0.6882 | spread 1.0104 | named jobs 577000
  ESP  best Comunidad de Madrid          1.2323 | worst Ciudad de Melilla            0.5188 | spread 0.7135 | named jobs 0
  FRA  best Ile-de-France                1.4953 | worst Hauts-de-France              0.6984 | spread 0.7969 | named jobs 438000
  GBR  best Northern Ireland             0.9560 | worst North West (England)         0.9560 | spread 0.0000 | named jobs 382000
  ITA  best Provincia Autonoma di Bolzano/Bozen 1.6244 | worst Calabria                     0.5181 | spread 1.1063 | named jobs 0
  LUX  best Luxembourg                   0.9360 | worst Luxembourg                   0.9360 | spread 0.0000 | named jobs 0
  NLD  best Noord-Holland                1.2521 | worst Drenthe                      0.6751 | spread 0.5770 | named jobs 0
```

Britain's spread is **0.0000** — §5's bound measured before anything moved — and
Luxembourg's is 0.0000 because one region cannot differ from itself. The named
jobs column is the city-level signal, and it is zero for seven of ten.

```
=== (b) movement against the band, at MIGRATION_RATE 0.0102 ===
      the largest mover's change in its share of the NATION
  nation  region@60  region@168  city@60   city@168  | (i) >= 0.0010 @60   (ii) <= 0.0164 @168
  FRA     0.0051     0.0137      0.0009    0.0024    | PASS   PASS     movers: Ile-de-France / Paris
  DEU     0.0013     0.0034      0.0008    0.0022    | PASS   PASS     movers: Bayern / Hamburg
  GBR     0.0000     0.0000      0.0001    0.0003    | BOUND   PASS     movers:  / Manchester
```

The region and city columns are printed apart because which level carries a
nation's movement is the finding: France's movement is Île-de-France's (region
0.0051 against its largest city Paris 0.0009), and Britain's is Manchester's.

```
=== (c) does the partition close? worst gap over 168 months ===
  nation  national sum: abs / rel        each region's city sum: abs / rel
  AUT     0.000000000000000333 / 0.000000000000      0.000000000000000000 / 0.000000000000
  BEL     0.000000000000000666 / 0.000000000000      0.000000000000000000 / 0.000000000000
  CHE     0.000000000000000555 / 0.000000000000      0.000000000000000000 / 0.000000000000
  DEU     0.000000000000000333 / 0.000000000000      0.000000000000000666 / 0.000000000000
  ESP     0.000000000000000555 / 0.000000000000      0.000000000000000000 / 0.000000000000
  FRA     0.000000000000000222 / 0.000000000000      0.000000000000000222 / 0.000000000000
  GBR     0.000000000000000000 / 0.000000000000      0.000000000000000333 / 0.000000000000
  ITA     0.000000000000000555 / 0.000000000000      0.000000000000000000 / 0.000000000000
  LUX     0.000000000000000000 / 0.000000000000      0.000000000000000000 / 0.000000000000
  NLD     0.000000000000000444 / 0.000000000000      0.000000000000000000 / 0.000000000000
```

Worst anywhere: **6.66e-16 absolute** against the test's 1e-12 — a ~1500×
margin, measured on the real Economy → Companies → Migration trajectory rather
than inherited from a zero-rate run. This was the first suite run in which the
flow executed at all: until the rate was measured, an early return made every
closure check vacuous, and the sweep task was the flow's first real coverage.

```
=== (d) SHARE_DRIFT_MAX 0.050 -- what is left over, at month 168 ===
  AUT  worst drift 0.0042, slack 0.0458
  BEL  worst drift 0.0113, slack 0.0387
  CHE  worst drift 0.0038, slack 0.0462
  DEU  worst drift 0.0034, slack 0.0466
  ESP  worst drift 0.0067, slack 0.0433
  FRA  worst drift 0.0137, slack 0.0363
  GBR  worst drift 0.0000, slack 0.0500
  ITA  worst drift 0.0082, slack 0.0418
  LUX  worst drift 0.0000, slack 0.0500
  NLD  worst drift 0.0067, slack 0.0433
```

```
=== (e) the sweep, distilled to the columns the band turns on ===
  (the probe's own step-0.0001 grid; four grids swept in full)

  rate     FRA r@60    DEU r@60    worst region @168   band
  0.0070   0.00351     0.00087     0.00959             fail (i)
  0.0080   0.00401     0.00100     0.01089             fail (i)
  0.0081   0.00406     0.00101     0.01102             PASS   <- clause (i) crosses
  0.0090   0.00450     0.00112     0.01218             PASS
  0.0102   0.00508     0.00126     0.01370             PASS   <- SHIPPED, the midpoint
  0.0120   0.00596     0.00148     0.01593             PASS
  0.0123   0.00610     0.00152     0.01630             PASS   <- clause (ii) crosses
  0.0124   0.00615     0.00153     0.01642             fail (ii)
  0.0140   0.00692     0.00172     0.01835             fail (ii)

=== (e2) the emulation against Migration.tick_month(), at 0.0102 ===
  FRA  largest disagreement in any share over 168 months: 0.000000000000000
  DEU  largest disagreement in any share over 168 months: 0.000000000000000
  GBR  largest disagreement in any share over 168 months: 0.000000000000000
```

One rounding wart, recorded rather than papered over: the 0.0080 row's DEU cell
prints **0.00100** at the probe's five decimals, and 0.00100 ≥ 0.001 reads as a
pass — but the true value is **0.0009985**, which FAILS the clause, as the row's
verdict says. The sixth decimal is where the row the clause turns on parts from
the row above it (0.000999 against 0.001008); a table quoting fewer decimals than
that is quoting a lie on the exact row that decides the band.

```
=== (f) reachability: who moves, at MIGRATION_RATE 0.0102 ===
  nation  regions  cities  region@168  city@168  city-in-region@168   note
  AUT      9        9     0.0042      0.0024    0.0000 ()   no named employers: the city level is inert, the region level is the whole signal
  BEL      3       16     0.0113      0.0060    0.0000 ()   no named employers: the city level is inert, the region level is the whole signal
  CHE      7        9     0.0038      0.0010    0.0000 ()   no named employers: the city level is inert, the region level is the whole signal
  DEU     16      122     0.0034      0.0022    0.0015 (Stuttgart)   moves at both levels
  ESP     18       97     0.0067      0.0031    0.0000 ()   no named employers: the city level is inert, the region level is the whole signal
  FRA     13       66     0.0137      0.0024    0.0023 (Lille)   moves at both levels
  GBR     12      132     0.0000      0.0003    0.0026 (Manchester)   BOUND: expected income identical across its regions -- moves only on named employers
  ITA     21       84     0.0082      0.0011    0.0000 ()   no named employers: the city level is inert, the region level is the whole signal
  LUX      1        1     0.0000      0.0000    0.0000 ()   BOUND: one region holding one city -- cannot move at either level
  NLD     12       45     0.0067      0.0017    0.0000 ()   no named employers: the city level is inert, the region level is the whole signal
```

The `city@168` column for the six employer-less nations is non-zero only because
the region moved and carried its cities along; the `city-in-region@168` column
isolates the city level and reads exact 0.0000 for all of them — a reader
skimming the wrong column would conclude Italy's cities migrate. The notes are
read off the CONTENT (the register and `data/companies/`) rather than off the
measurement: a flat expected income is a fact about the register and stays true
at a rate of 0.0, where a note keyed on "this nation did not move" would call
every nation flat.

## 8. `SAVE_VERSION` 29

Two fields earn it, and they are the two V2.5 left behind:
`NationState.region_pop_share` and `NationState.city_pop_share`. Absent, every
share reads 0.0, so every city's population is zero — **no glyph on the map at
any zoom, an empty league table in both panels**; the country does not run a
different model, its people simply do not exist (`region_gdp_eur_bn`'s case at
V2.5 in its strongest form). Re-seeding from the authored shares does NOT rescue
a save, for the same reason it did not rescue the region GDP stock: the authored
share is where a place **started**, and re-seeding would erase the movement the
save exists to remember. The bump is verified load-bearing rather than asserted:
stripping either share register from a round trip comes back with the register at
size 0 and no re-seed.

**The constant lives in `src/core/game_state.gd`** (line 426), beside the comment
that carries both V2.5's and V2.6a's reasons — the plan named `save_manager.gd`,
and that was wrong; the version lives with the state it versions, and the
correction is recorded here so the next session does not re-derive it.

**What stays red is a stored city POPULATION.** A head count is
`population × share × share` and the two shares are now both serialised, so
storing one would be a second answer to a question these already answer — and
the day somebody does, `tests/test_save_load.gd` fails and has to come and say
why. The top-level register (`regions`, `cities` keys) stays content too: it
round-trips through `data/regions/`, and the save carries the live shares, not
the roster. V2.2a pinned three absences; V2.5 flipped one (`region_gdp_eur_bn`);
V2.6a flips the other two and leaves exactly one standing.

One out-of-scope fix rode along, and it is SAVE_VERSION's story: the review found
`tests/test_summits.gd` **authored at V2.4b and never added to `run_tests.sh`**,
hard-pinning `SAVE_VERSION` 27 — silently red since V2.5, which is what a
registered-but-stale pin looks like from the inside. Registered, pin moved to 29
with both reasons; the audit says all 73 test files are in the runner and no
ghost entries remain.

## 9. The balance re-run

**Predicted before the build, and sharper than V2.5's**: bit-identical in every
printed figure AND at the bit level, across every shared regime, zero outcome
changes — because V2.6a moves **no national quantity at all**. `ns.population` is
written by `Economy.tick_month()` alone, no population share enters any equation
in `src/sim/` outside `migration.gd`, and every reader of a share is a panel or
the map. V2.5's swap carried a second-order Jensen term of ~1e-9 relative per
month; this one carries nothing, so **a single moved digit anywhere is a defect
and not a rounding boundary**, and the response is to find the reader, not to
widen a tolerance. No new regime, another session with none — the first draft
counted six from U6c and the ordinal is dropped rather than defended: its own
list omitted V2.2a (whose record says no new regime beside V2.2b's), and V2.4a's
and V2.4b's re-runs moved figures without adding one, so where the run starts is
a definition the claim does not need. No verb, no budget regime can reach it, and
every existing regime exercises the new code because every one calls the tick.

**Measured against the baseline the block branched from** (`d8a1baa`, the tip of
V2.5, verified an ancestor of HEAD — not `HEAD~4`, which the plan text said and
the commit count had moved): **1582 of 1582 printed lines byte-for-byte
identical** — every balance regime, every year row, every closing
`invariants: OK over 168 months`. **Zero outcome changes. Zero digits moved.**

Method honesty, recorded because the plan said otherwise: only the BASELINE side
was a git worktree, so the per-machine addon parse noise did not cancel between
sides the way V2.5's both-sides-from-worktrees run made it cancel. It was
**isolated** instead: the raw line counts differ (1606 against 1585), and the
difference is ONE contiguous block appearing only on the worktree side — the
fresh worktree lacks the gitignored `godot_mcp_toolkit`, its autoload fails, and
the failure cascades a `dialogue_manager` parse error — appearing AFTER the last
`invariants: OK` line, i.e. after all of the probe's actual measurement.
**Both sides carried filterable noise of their own**: 24 lines of that cascade on
the worktree side, and 3 `MCPRuntimeServer` port prints on head, so the raw
counts reconcile only net of both — 1606 − 24 = 1585 − 3 = 1582 content lines,
the figure the byte-identity above is counted on. Checked
for a third stray line (V1.7c's gotcha, the reason the noise is filtered but
never trusted): none. The diff over the probe's actual content is empty.

## 10. What V2.6a did NOT build, and what passes on

- **No verb.** Nothing is booked, nothing is commanded; V2.6a runs under V1.5's
  inverted block rule and ships a statistic with a self-limiting feedback. The
  `--move` flag is a screenshot view that stages ten years, not a player act.
- **No political price.** Migration moves nobody's opinion — there is no
  regional approval channel, and the refused direction is recorded because a
  later session under balance pressure will reach for it: a regional opinion
  number is *a second approval figure with a different label*, which V1.5c
  refused by name. **The political price is V2.6b's**, and it lands where the
  people now are.
- **No net urbanisation.** Both residuals are frozen (§4); the rural share
  neither drains nor fills. A session that wants cities to eat the countryside
  has to author a rural pull, and §2 records why none was inherited.
- **No map layer.** `LAYERS` stays at four; the existing crosses grow and shrink
  through `Migration.city_population()` and need no new draw pass.
- **No city economy beyond a head count.** A city's population moves; its output,
  wages and jobs below the named employers' headcount do not exist.
  `src/core/city.gd`'s own error string still says so.

**To V2.6b — a place for what happens. BUILT AS V2.6b1, AND THE HANDOFF ABOVE WAS
WRONG IN ITS CENTRAL CLAIM.** *"Both decide **where** by reading (a)'s live
shares"* is false and [[siting-model]] §2 measures it: the site is arg-max over
population share times a static signal, and the winner leads the runner-up by
**73.9 % in France** against a fourteen-year migration budget worth about **9 %
relative**. The shares are third-order behind static content, and the signal
changes which region wins for **exactly one nation of ten**. Germany's site does
move once (Ruhr → Berlin, on a +0.4 % margin), which is the exception that
measures the rule.

*"One shape not two"* was half right: the two halves share the WHERE and not the
PRICE. Unrest's place is a derived report whose failure mode is constancy; a
campaign meeting's place is a verb whose failure mode is dominance, so V2.6b split
and **V2.6b2** owns the campaign half on V2.4a's travel days plus a per-region
saturation counter — [[siting-model]] §11 carries the refused signals with numbers.

The political price this session declined was charged **once and not twice**: the
output channel took it free (V2.5's index is already mean-one), and the opinion
channel's own band came back with an **empty** passing interval and its constant
was deleted. [[siting-model]] §5.

**To V2.6c — natural change. BUILT, AND THE GATE'S OWN PREMISE WAS THE STALE ROW.**
Birth rate and life expectancy arrived with the mechanism that reads them — but the
gate asked for regional AGE STRUCTURE from `demo_r_pjangrp3`, and the register's
dataset publishes only the 22 brackets, while the sibling dataset `demo_r_gind3`
publishes **NATGROWRT, the crude rate of natural change, directly per region** —
the quantity the gate wanted to *derive* from brackets, already measured. Importing
brackets to author an age-mix-to-rate mapping would have been the weighted sum
[[demography-model|V1.5b]] refused. The conservation-law warning above held in the
interesting direction: the natural flow redistributes a differential around a
live-share-weighted mean, so it telescopes to zero over the named regions exactly
like this file's flow, and the NATIONAL non-zero-sum half was already inside
`pop_growth_pct` — the partition decision, not a new conservation law. The
re-sweep it forced on `MIGRATION_RATE` — 0.0102 → 0.0003, and the dominance
finding behind that — is [[natural-change-model]] §6.

---

Related: [[tiers/v2]] · [[siting-model]] · [[geography-model]] · [[region-economy-model]] ·
[[demography-model]] · [[decision-log]] · [[ROADMAP]]
## V3.3: the zero-migration bound is now six nations'

LUX's "one region cannot differ from itself" case arrives five times more:
CYP, EST, LTU, LVA and MLT are single-region at NUTS 2, so `pull - mean` is
exactly 0.0 at both levels for each, at any rate whatever. Their people still
move through natural change (measured, unlike Britain's hole) and their cities
still compete for the named jobs of the one region they share.

