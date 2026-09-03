# The network model — where a region sits

V2.7. `src/sim/network.gd` turns a transport graph into a per-region
**accessibility index**, and that index enters the model at exactly one site —
`Regions.trend_deviation_pct()`, beside the sector-mix term V2.5 shipped — as a
second zero-mean term. The national aggregate is untouched by construction: the
national GDP is still the sum of the regions, and every new term is measured
against the nation's own output-weighted mean so it cancels.

The one line it changes in `regions.gd`:

```gdscript
return mix + _network_pct(ns, region_list, region, access) + _sited_pct(ns, region_list, region_id, sites)
```

Three terms, each zero-mean by subtraction: the sector mix (V2.5), the network
(V2.7), and the sited-project payoffs (V2.7). `NETWORK_BETA` is the only swept
constant in `src/sim/network_constants.gd`; `DECAY_KM` is derived, not swept.

## 1. The shape question, answered by counting

`docs/tiers/v2.md` §7 left the graph's shape — per-region adjacency or routed
geometry — "deliberately not decided". The probe
(`tools/network_probe.gd`, committed before any `src/` edit) answered it by
counting over the committed geometry, reading **every ring of every polygon**:

```
regions 112   edges 243   cross-border edges 58
enclaves: AT13 -> [AT12], BE1 -> [BE2], DE3 -> [DE4]
DE3 -> DE6 : Berlin -> Brandenburg -> Niedersachsen -> Hamburg   (3 hops)
DE3 -> ITC4: Berlin -> ... -> Sachsen -> Bayern -> Ostschweiz -> Lombardia (5 hops, a third COUNTRY)
FR1 -> UKI : UNREACHABLE
```

The handoff's routed-geometry argument did not survive the roster: its own
example — transit through third regions and third countries — routes fine over
adjacency. What adjacency genuinely cannot express is **water**: nine
components, eight of them off the mainland. Closing them is **exactly eight
authored sea links**, each a real crossing in service
(`tools/import_data.py`'s `SEA_LINKS`): Channel Tunnel, Cairnryan–Larne,
Marseille–Ajaccio, Villa San Giovanni–Messina, Civitavecchia–Olbia,
Barcelona–Palma, Algeciras–Ceuta, Almería–Melilla. The count is the
measurement, not a preference.

**Routed geometry is also refused on licence**: `docs/data-sources.md` rejects
OpenStreetMap on ODbL's share-alike, which attaches to derived databases — and
`data/` would be one — and no permissively-licensed European road or rail
linework exists in this project's chosen sources. So routed geometry is not a
more expensive option; it is one this repo may not take.

A first-pass bug is recorded so no session repeats it: reading only the outer
ring reports **12 components and 10 isolates**, adding AT13 Wien, BE1 Bruxelles
and DE3 Berlin — their adjacency lives in the host's **hole ring**. The holes
are in the committed file (283 rings, 18 of them holes); the bug is in the
reader. Both the probe and the importer read every ring.

## 2. The endowment, and rail's refusal

`tran_r_net` (Eurostat, fetched once to `sources/eurostat/tran_r_net_2018.json`):

```bash
curl -L -o sources/eurostat/tran_r_net_2018.json \
  "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/tran_r_net?format=JSON&lang=EN&time=2018"
```

Coverage at 2018 against the register's own 112 codes:

| branch | unit | coverage |
|---|---|---|
| MWAY | KM and KM_TKM2 | AUT 9/9 BEL 3/3 CHE 7/7 DEU 16/16 ESP 18/18 FRA 13/13 GBR 12/12 **ITA 19/21** LUX 1/1 NLD 12/12 — 110/112 |
| RL | both | AUT **0/9** BEL **0/3** CHE **0/7** DEU 16/16 ESP 18/18 FRA 13/13 GBR **1/12** ITA 20/21 LUX 1/1 NLD 12/12 — 81/112 |

2018 is the year: 2019 onward drops the UK (the withdrawal gap, in a **fourth**
place after regional GDP, regional unemployment and the natural-change rates);
2022 additionally drops two Dutch codes. The missing MWAY codes are ITG2
(Sardinia) and ITH2 (Valle d'Aosta); under clause (c) the widest branch ships
and the gaps take the roster mean (`raw.get(code, mean)` in
`load_transport_endowment()` — the gate clause's "nation's own mean" landed as
the roster mean, with the graph's international-edges argument, and touches
exactly those two codes).

**Rail is refused, on coverage rather than on judgement**: a graph mixing
measured and absent rail invents connections no measurement supports — V2.6c's
rule for Britain's natural-change rates, applied to a network.

The endowment is motorway **density** (KM_TKM2, km per thousand km²) divided by
the roster mean — dimensionless, near 1.0, so `src/` never learns what a
kilometre is. Normalised over the ROSTER rather than per nation: 58 of the 243
land edges cross a border, and a per-nation endowment would make a Belgian
motorway mean the same thing as a Spanish one.

## 3. The graph as content

`data/geo/region_graph.json`, written by the importer's `build_region_graph()`:

```json
{"_source": "...", "_note": "...",
 "edges": [["AT11", "AT12", 118.4, "land"], ...],
 "endowment": {"AT11": 0.412, ...}}
```

An edge is `[a, b, km, kind]`, `a < b`, `km` the great-circle distance between
the two regions' **principal cities** (`cities[0]`, written descending by
population), `kind` `"land"` where two polygons share a vertex and `"sea"`
where a ferry was authored. Three provenances in one file, and `_source` says
which is which: adjacency derived, sea links authored, endowment measured.

## 4. Production: the six branches, and the refusal

`nama_10r_3gva` has carried **six** NACE branches (`A`, `B-E`, `F`, `G-J`,
`K-N`, `O-U`) since V2.5 and `NACE_TO_SECTOR` collapses them to three. Clause
(d) was fixed before the run: the six-branch specialisation had to rank the 112
regions differently from the three-branch one — **Spearman ≤ 0.90** — or the
finer mix is one quantity written twice. Measured: **rho 0.9170**. Above the
bar, so `production_mix` is REFUSED and the refusal is recorded beside
`sector_mix` in `src/core/region.gd`. The five largest rank movers (ITH1 −44,
AT11 −40, ITI4 +34, ITH3 +32, DE4 −29) show the orderings agreeing almost
everywhere that output-weighted mean-one makes load-bearing. `Network.specialisation()`
reads `sector_mix`; nothing was fetched for this and nothing was stored.

## 5. The accessibility index, and the anchor question

`Network.accessibility(graph, weights)` — market potential, discounted by
endowment-adjusted distance, normalised so the `weights`-weighted mean is
**exactly 1.0** at Siting's 1e-12 bar. The endowment shortens the **edge**
rather than weighting either end (`km / mean(endowment_a, endowment_b)`): a
motorway is a property of the crossing, not of either end.

The anchor is a THIRD kind and was measured rather than inherited. V2.6b1
normalises unrest in population weights (a demonstration happens where the
people are); V2.6b2 took campaign reach off it (reach is delivered where the
player goes). Accessibility follows the **infrastructure** — and what actually
decides it is the aggregate: the index rides on regional output growth, and
V2.5's spine closes only when every deviation is zero-mean in **output**
weights. Any other anchor moves the national total and re-opens the
definitional swap. Output-weighted mean-one it is.

Implementation notes: the graph is content, so the 112×112 distance table is
cached per graph and the last index is memoised on weights equality — the
per-month recompute would otherwise put a full Dijkstra sweep in every tick.
`distances_from()` stays public for single reads.

## 6. NETWORK_BETA: the sweep with one edge

`DECAY_KM` first — **derived, not swept**: the continental component's mean
eccentricity is 9.65 hops (diameter 13), and the mean endowment-adjusted km at
the 10-hop row is **2924.9** (300 ordered pairs; 2 686 at 9 hops, 3 188 at 11 —
smooth in the hops, so the exact count is not load-bearing). A fit taken from
the graph converges where a swept value would move.

Clause (e) — collinearity — measured before anything was swept:
**|corr(network_dev, mix_dev)| = 0.3360 ≤ 0.60** over the 112 regions. The
network term is not the mix term renamed (V1.6c deleted its deficit term at
0.9948; V1.6b accepted 0.2276). Accessibility spread [0.498, 1.147]; the raw
term spans [−0.0865, +0.0134] points/yr per unit beta.

The sweep (probe table (f); each candidate emulated through the shipped
arithmetic with the real economy month and the real population flow, the inert
row validating the emulator against V2.6c's real-harness 0.01599):

```
beta  move@60(pp)  diff@60(pp)  out-drift  pop-drift   verdicts
0.00      0.093        0.000      0.0026     0.0160   (i)-- (ii)OK
2.00      0.079        0.020      0.0022     0.0160   (i)-- (ii)OK
4.00      0.090        0.040      0.0025     0.0160   (i)-- (ii)OK
5.00      0.095        0.050      0.0027     0.0160   (i)-- (ii)OK
6.00      0.100        0.060      0.0028     0.0160   (i)-- (ii)OK
7.00      0.105        0.070      0.0030     0.0160   (i)-- (ii)OK
8.00      0.111        0.080      0.0031     0.0160   (i)-- (ii)OK
10.00     0.121        0.100      0.0034     0.0160   (i)OK (ii)OK
```

`move@60` is the largest mover's total output-share move (clause (i) as
written); `diff@60` is the same against the inert channel's own run — the
fingerprint the term leaves. **Clause (ii) never binds**: at β=10 output drift
is 44× under `SHARE_DRIFT_MAX`, and the population drift is pinned by natural
change at 0.0160 against the 0.0164 ceiling — the drift `MIGRATION_RATE`
already owns, unmoved at any candidate.

**THE MIDPOINT RULE HAD NO INTERVAL TO TAKE A MIDPOINT OF.** V1.5d's rule
assumes two crossings; the measured band is [crossing, ∞). Widening the grid
moves no upper edge, which is V1.5a's *a band an observable cannot reach is a
bound and not a selector* — recorded rather than tuned against (tuning to the
0.15 guard's crossing would ship a β≈250 that unemploys Europe). So the
crossing ships, and the **differential** one: the total is confounded by the
mix term's own 0.093 pp baseline (a content accident), where the fingerprint
is exactly linear at **0.010 pp per unit beta** across the whole grid, so its
crossing at **NETWORK_BETA := 10.0** is grid-independent — V1.5b's refinement
diagnostic passed by construction. Both readings of clause (i) hold here.

## 7. The sited projects

V1.6f's `project_sites` coordinates answer "which region" through a hole-aware
point-in-polygon (`Projects.site_region()`), reading the loader's full-ring
geometry (`region_rings` — the renderer keeps its outer-ring shape; Berlin's
site lives inside Brandenburg's outer ring and only the hole says whose it
is). All fifteen authored sites resolve: FRA high_speed_rail → FRC, national_grid
→ FRK, freight_corridor → FRD, national_fibre → FRJ, flood_defence → FRI;
DEU's five and GBR's five likewise (GBR flood_defence and freight_corridor both
→ UKH).

The payoff placement: the site region's deviation gains the authored
`potential_growth_pct`, the rest of the nation loses it in output-weighted
proportion (`Regions._sited_pct()` — zero-mean by the same subtraction), so
the nation's total is untouched and V1.6f's national channel still carries the
level through `project_potential_target_pct`. One act, priced once.

**The refused alternative**: letting a finished project cut the cost of its
site's edges — the honest physical model of a rail spine, and it needs a
payoff-to-kilometre constant nobody could measure (V1.6f's
three-independent-facts rule; `investment_action.gd`'s refusal of one strength
written twice).

The site is **derived and stored nowhere**: the map lives on `GameState` as
non-serialised derived state (`project_sited_pct`), rebuilt each tick by the
one module that owns completions and re-derived on load. The save pins the
absence (`tests/test_save_load.gd`), and `SAVE_VERSION` stays 30.

## 8. The migration re-sweep

The plan's sharpest risk: the term moves output per head, output per head is
half the Harris–Todaro pull, and V2.6c left the ceiling binding at 2.5 %
slack. Measured with `NETWORK_BETA` live at 10.0
(`tools/migration_probe.gd` unchanged): **the sweep came back identical at
every printed figure.** Clause (0)'s natural-only row reads 0.01558 exactly as
V2.6c measured it; the shipped 0.0003 row reads 0.01599 exactly; the interval
is unchanged at [0.0000, ~0.00057]. `MIGRATION_RATE` stays 0.0003. The reason
is arithmetic: the network term moves output shares ~0.1 pp over five years,
the pull by a fraction of a per cent of itself, and migration owns 1–3 % of
the combined movement — the third mover's contribution lands below the drift
table's fifth decimal. The plan expected the 0.0003 row to move up; measured,
it did not, and the kill switch never came close.

## 9. The re-run

Both sides from worktrees (the per-machine addon parse noise identical and
cancelling). Prediction written first: national headlines bit-identical
(zero-mean by construction); unemployment and approval may move through the
unrest-siting chain; zero outcome changes is the bar.

**Measured: 2 moving lines of 1647 content lines per side, 48 invariants OK
each, tails byte-identical, zero outcome changes.**

- `managed_signs_agreement` (FRA) 2032: unemp 7.67 → 7.66 — the plan's own
  predicted channel (`Regions.unemployment_pct()` reads the deviation).
- `managed_bill_is_held` (FRA) 2036: grow +0.35 → +0.36 — the same chain one
  step on: unrest's siting moved, its impulse is a growth addend.

GDP, trend, debt, deficit, approval, seats and every other regime: identical.
No new regime — the network term is not a verb, sixth session running; the
sited payoff lands only through the existing `PROJECT_REGIMES`.

## 10. The two refusals

1. **Routed geometry** — refused twice over: ODbL's share-alike attaches to
   derived databases, and the measurement (Berlin→Hamburg in three hops,
   Berlin→Milan in five through a third country) says adjacency buys the
   transit case anyway. What adjacency cannot express is water, and water is
   eight countable links.
2. **A project cutting its site's edge costs** — one strength written twice;
   the payoff lands on the region instead, zero-mean, priced once.

A third refusal: the six-branch production mix (§4) — a measurement, not a
judgement, and the number is in `region.gd` beside the field that would have
been.

## 11. Bounds

- **Britain's fourth withdrawal gap**: `tran_r_net` drops UK codes from 2019;
  2018 is the only year that carries British motorways at all.
- **Luxembourg's one region**: degree ≥ 1 in the graph (its borders are
  vertices), but degree **0 within its own nation** — one region cannot differ
  from itself, and the panel's least-connected line names it anyway.
- **The readout**: the Region panel's eighth column (`x%.2f`, the same scale
  as output per head), a never-silent land/sea line, the economy panel's reach
  line, and `--network`, the twenty-sixth flag.
