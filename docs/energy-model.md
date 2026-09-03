# The energy model — the mix, the dependency, and the two prices of a place

V2.8. `src/sim/energy.gd` holds one machine: a per-nation register of plants
(`ns.plants`), a build countdown, a computed spending line, and a derived mix.
Everything else in the session is the price of getting the place right.

## 1. The partition

The mix is a **partition, not a stock**. The measured national shares
(`imported.energy.mix`, World Bank, ten of ten) are the baseline; built capacity
is the deviation:

```
national_twh   = energy_kwh_per_capita * population / 1e9
built[b]       = sum of output_twh over DONE plants whose source is in branch b
mix[b]         = (start_mix[b] * national_twh + built[b]) / (national_twh + sum(built))
```

With zero plants `sum(built) == 0.0` and `mix[b] == start_mix[b]` **exactly** —
`trade_baseline_by_partner`'s idiom at V1.3b and credit.gd's
spread-reads-exactly-0.0 at V1.6c. It is the property the re-run prediction is
written against, and `tests/test_energy.gd` asserts it at 0.0 rather than at
1e-9, because "reads as zero" and "reads zero" are different claims and only one
of them survives a re-run.

The importer normalises the three raw shares (which sum to 94–99 %) and folds
the 6-decimal rounding residual into the largest branch, so the content sums to
exactly 1.0 — the imported `sectors` block's own treatment.

## 2. The denominator

`EG.USE.ELEC.KH.PC` × live population. France reads ≈ 6447 kWh/head × 68.1 M ≈
**439 TWh** against a real ≈ 445 TWh of generation. Because the denominator
rides the **live** population, a plant's share of a growing country shrinks on
its own, and the cost is nothing: with an empty register the denominator
cancels out of `mix()` entirely, so no bit-identity is spent buying it.

One reactor is 13 TWh — **3 % of France and 63 % of Luxembourg**. The same
authored plant is a different decision in a small country, which is why capacity
is a physical unit and not a share. Luxembourg's import dependency reads
**109.6 %** and is not clamped: it imports more energy than it consumes and
re-exports the difference, and a clamp there is a number no dataset measured.

## 3. The grid is national

Energy does NOT move regional growth. A power station serves a grid, and the
grid is national; `Regions.trend_deviation_pct()` keeps its three zero-mean
terms and gains no fourth. `tests/test_energy.gd` reads `src/sim/energy.gd` and
fails if it ever preloads `regions.gd` — the refusal is a **check**, not a
paragraph, so a later session adding a regional channel turns it red and has to
come and say why.

## 4. Two sited halves, two opposite rules

`Projects.site_region()` derives its region on every read and stores nothing,
because a stored site *could disagree with `data/nations/`* about where the rail
spine is — the content is the authority. A plant stores `lon`, `lat`,
`region_id` and the frozen `connection` multiplier together, because the
coordinate is the **player's own act** and there is nothing else in the game
with an opinion about it — no authority to disagree with. What there is instead
is a contract: the player was quoted a connection cost for that region and
signed for it, and a re-imported geometry that moved a border must not
retroactively re-price a station already under construction.

**The two rules are opposites because the two facts are opposite kinds** — one
is content, one is an act. This section exists so the next reader does not call
either of them a mistake.

## 5. `ACCESS_ELASTICITY` — the connection cost

**Band, two clauses, fixed before the sweep:**

- **(i) READABLE.** Between France's best-connected and worst-connected region the
  build bill for one reactor must differ by at least **0.010 points of GDP** — one
  digit of `budget_panel.gd`'s own `%.3f` on that row. Below that the player cannot
  see that the place cost them anything.
- **(ii) BOUNDED.** No region may make any plant cost more than **1.60x** its
  authored build cost. Above that the connection charge is larger than the
  difference between two technologies, and the siting decision has eaten the
  technology decision.

## 6. `OPPOSITION_SCALE` — the local price

**Band, two clauses:**

- **(i) READABLE.** Siting a reactor in the nation's largest region rather than its
  smallest must move the worst bloc's approval by at least **3.0 points** — the poll
  floor `poll_noise.gd` sets, the bar V1.3g, V1.5b, V1.5c and V1.8 each wrote their
  own band against.
- **(ii) CAREER-BOUNDED.** V1.8's E1b clause, and it applies here for E1b's own
  reason: `bloc_offset` is a permanent clamped accumulator, so a price that
  saturates it makes every strategy converge on the same floor. Over a full
  fourteen-year run of the most aggressive reachable building programme, no bloc's
  accumulated offset from siting alone may exceed **0.45 of `BLOC_OFFSET_MAX`**.

## 7. `DEP_BETA` — what dependency costs

**Band, two clauses:**

- **(i) READABLE.** Fourteen years of building only gas must cost at least
  **0.30 points of annual growth** against a control that builds nothing —
  `economy_panel.gd`'s own `%.2f`, with margin.
- **(ii) NOT DOMINANT.** The same run's growth cost must stay under
  `DEFICIT_SCALE_PP`'s remaining span, so the dependency channel cannot outweigh
  the budget the player is actually running.

**Escalation declared in advance:** if (i) and (ii) have no overlap, the response is
to record the gap and set `DEP_BETA` by a **ratio against `SECTOR_TREND_BETA`**, not
to widen the clamp — V1.5d's treatment of `PRESS_UNREST_BETA` and V1.1e's of
`JUDICIAL_UNREST_BETA`.

## 8. The sweep — measured

*(the bands above were written first; these tables are the run that answered them)*

**Reachable range, V1.7c's table.** The harness's own `managed` budget on France,
168 months: deficit runs **2.42 → 2.68** for the first seven years and **2.42 →
2.53** after the first election cycle, approval **48.6 → 50.5**. No year in any
table below is tested outside the range the player can actually hold — and the
aggressive building programme the accumulator clause is measured against is
reachable inside it: the deficit precondition never binds on the sustained
cadence, so the clause is not vacuous.

### `ACCESS_ELASTICITY` — France's best 1.101, worst 0.656

| cand | spread (i ≥ 0.010) | max_mult (ii ≤ 1.60) |
|---|---|---|
| 0.10 | 0.0095 `--` | 1.043 `OK` |
| 0.15 | 0.0143 `OK` | 1.065 `OK` |
| 0.20 | 0.0193 `OK` | 1.088 `OK` |
| 0.30 | 0.0294 `OK` | 1.135 `OK` |
| 0.50 | 0.0507 `OK` | 1.234 `OK` |
| 1.00 | 0.1108 `OK` | 1.524 `OK` |

Both edges are smooth crossings — (i) at **0.105**, (ii) at **1.114** — and
neither is within a factor of three of the other, so **the interior governs**
(V1.5d) rather than either edge. **Shipped: `ACCESS_ELASTICITY := 0.30`** — the
log-interior of the band (√(0.105 × 1.114) = 0.34), on the coarse grid, reading
a best-to-worst French reactor at 0.175 against 0.204 points of GDP: a spread
of **0.029**, three times the readability floor, at a worst-case premium of
**1.135x**, three-and-a-bit times inside the bound. Grid refinement 0.05 → 0.025
does not move either crossing (V1.5b's diagnostic) — the crossings are powers of
a measured index, not scan artifacts.

### `OPPOSITION_SCALE` — largest FR1 1.851, smallest FRM 0.053

| cand | approval move (i ≥ 3.0) | accumulated frac of `BLOC_OFFSET_MAX` (ii ≤ 0.45) |
|---|---|---|
| 0.05 | −3.60 `OK` | 0.20 `OK` |
| 0.06 | −4.32 `OK` | 0.24 `OK` |
| 0.07 | −5.04 `OK` | 0.28 `OK` |
| 0.08 | −5.75 `OK` | 0.32 `OK` |
| 0.09 | −6.47 `OK` | 0.36 `OK` |
| 0.10 | −7.19 `OK` | 0.40 `OK` |
| 0.11 | −7.91 `OK` | 0.44 `OK` |

Clause (i) crosses at **0.042** (the move is `APPROVAL_SPAN` × the concentration
spread × the authored opposition, through Opinion's own clamp at a zero score);
clause (ii) crosses at **0.116** (6 sustained orders of gas over 168 months —
one per build length, Task 8's own regime cadence). Interior midpoint **≈
0.08**; **shipped: `OPPOSITION_SCALE := 0.08`**, 1.9x above the readability
floor and 1.4x inside the career bound, stable on the refined grid.

**The bound that is not a selector.** On a ONE-ORDER-A-MONTH reading of
"aggressive", the run fires **137 gas stations** in 168 months and the
accumulator saturates at EVERY candidate — but it saturates through the
AUTHORED `bloc_offset` alone (137 × −0.020 = −2.74, past ±1.0 with the siting
price at zero), which is U6a's finding in a new place: `available()` returns
what is LEGAL and nothing models what the player WANTS, so a career clause
priced against legality always binds and cannot select. The sustained cadence —
one order per build length, which is what a building programme IS — is the
readable test, and the spam run is recorded here so the next session does not
re-derive it.

### `DEP_BETA` — sustained gas, dependency deviation 3.81 points

The deviation does not depend on the candidate, so the emulation at the
candidate is exact (V1.6b's rule, trivially):

| cand | cost (i ≥ 0.30) | (ii) < 0.5639 |
|---|---|---|
| 0.060 | −0.229 `--` | `OK` |
| 0.080 | −0.305 `OK` | `OK` |
| 0.100 | −0.381 `OK` | `OK` |
| 0.120 | −0.458 `OK` | `OK` |
| 0.150 | −0.572 `OK` | `--` |

Clause (i) crosses at **0.079**, clause (ii) at **0.148**. **Shipped:
`DEP_BETA := 0.10`** — the interior on both the linear and the log reading
(1.27x above the floor, 1.48x inside the span), stable on the refined grid.

### The handoff's two obligations

**(a) `MIGRATION_RATE` does not need its re-sweep.** The energy addend is
national and applied uniformly, so every region's level moves by the same
factor and no SHARE moves. Measured, not asserted: fourteen years of sustained
gas building on the full harness stack reads worst output-share drift FRA
**0.00338**, DEU **0.00094**, ITA **0.00212** — and worst population-share
drift FRA **0.01599**, the figure V2.7 measured and V2.6c owns, unchanged to
the printed digit (V2.7 reported 0.0160). The ceiling's 2.5 % slack is intact.

**(b) The graph gains no accumulator.** `energy.gd` never writes
`region_graph`'s `endowment` and never preloads `network.gd` —
`tests/test_energy.gd`'s leaf check forbids the preload, and
`tests/test_save_load.gd`'s V2.7 absences run green on the same suite. A plant
that shortens its own edges is a real design and it belongs to whichever
session argues for it; the refusal was **checked, not inherited**. And one
thing V2.8 does not read at all: `Projects.sited_map()` — a project's payoff
map is a projects quantity, and duplicating a reader of it here would be a
second opinion about where the rail spine is.

## 10. The refusals

- **No fourth zero-mean term in `regions.gd`.** The grid is national. Pinned by
  `tests/test_energy.gd`'s leaf check, which reads the file and fails on a
  `regions.gd` preload — a check rather than a paragraph, so a later session
  adding a regional energy channel turns it red and has to come and say why.
- **No coercion amplifier.** Dependency scaling the damage a supplier's measure
  does would be the truest model of what import dependency is *for* — and
  V1.3g's own probe found the nine **never coerce each other** over 168 months
  with no player (`state.measures` stays empty; every recorded act is a state
  visit), so the channel is inert for every AI nation and reaches only a player
  who has already been sanctioned. Recorded rather than built, with the number
  beside it.
- **No `ISSUE_KEYS` entry.** Answered **NO on test 1**, the sixth consecutive
  session for the same reason: a session shipping a content object has somewhere
  to put the price, and `data/energy-actions/` authors a `bloc_offset`. The
  S10-ratio cost of a fifth salience key is measured the same way every time and
  the answer does not change with the verb.

## 11. What V2.9 reads

The mix is a partition over three branches, each source carries an
`import_intensity`, and **emissions are a weighted sum over exactly that
partition** — V2.9 owns the weights, and the partition means they land on a
quantity that already sums to 1.0. A **sited disaster** now has two precedents
to choose between, and should choose rather than author a third:
`Siting.pick()`, which V2.6b1 built for exactly this and nothing has ever
used; and `plants[id].lon/lat`, which is a point rather than a region — the
one coordinate in the game the player wrote.

## 9. The re-run

**Prediction, written before the run:** every shared regime is **bit-identical**,
because no budget regime issues an energy verb and every added expression reads
exactly 0.0 or exactly the baseline with an empty register. The diff should be
**additions only**. Two new regimes of the **expensive kind** — a plant is a verb
no budget regime issues, V1.3g's and V1.4c's case.

**Held, at the bit level.** Baseline `v2.7` worktree against the branch: the
diff is **77 lines, every one an addition inside the two new regimes' own
blocks** — 48 `invariants: OK` lines on the base side, 50 on the branch, the
+2 exactly the new regimes', zero outcome changes across every shared regime.

**The legibility evidence** — same budget (`managed`), final year 2037, the
only difference between the three runs is the verb:

| | `managed` | `managed_builds_nuclear` | `managed_builds_gas` |
|---|---|---|---|
| GDP (EUR bn) | 3340 | 3340 | 3318 |
| growth | +0.26 % | +0.26 % | +0.14 % |
| unemployment | 7.67 | 7.67 | 7.76 |
| debt (% GDP) | 128.9 | 131.1 | 130.8 |
| deficit (% GDP) | −2.79 | −3.09 | −3.02 |
| approval | 42.9 | 40.7 | 41.1 |
| worst bloc | students 39 | **students 25** | **students 25** |

The deficit and the debt are where the bill lives: the builders' surplus is
three tenths of a point smaller and their debt two points higher, because every
month of every build is on the spending line — the same budget buying a fleet.
The worst bloc is where the politics live: the do-nothing France's harshest
critics are `students` at 39; both builders drive the same bloc to 25, the
authored offset per order accumulating with the siting price on the same
register — and the map price is what pushes them apart, since the nuclear
orders site into a 1.851-concentration region and pay for it. The growth
column is the honest reading of `DEP_BETA` at 0.10: gas moves France's
dependency **+3.81** points over the window (the sweep's own measurement, same
cadence), costing **0.38** points of growth cumulatively and showing as
**+0.14 against +0.26** in the final year — a channel a player can see on the
economy panel and not one that takes the budget's place. The nuclear run moves
the dependency the other way; `tests/test_balance.gd` asserts both directions.
