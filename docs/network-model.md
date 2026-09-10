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

**Licence removes one road source, not all of them**: `docs/data-sources.md`
rejects OpenStreetMap on ODbL's share-alike, which attaches to derived
databases, and `data/` would be one. It does **not** follow that nothing
permissive exists — V3.4 measured one that does. Natural Earth 1:10m roads are
public domain and put linework in 212 of the roster's 213 regions, and
`docs/data-sources.md` refuses them on a different ground: no property key
attributes a line to a region pair, so an edge's road cannot be looked up.
Routed geometry stays refused on the count above — the handoff's own transit
examples route fine over adjacency, Berlin→Hamburg in three hops and
Berlin→Lombardia in five through a third country — not on there being nothing
to route over.

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
## 12. V3.3: the graph at EU-27, and the two bounds the growth added

The graph rebuilt with the register: **213 regions, 463 edges — 447 land and
16 sea links — one component.** *(This section shipped saying 464, as did
AGENTS.md's V3.3 row and the V3.4 handoff. All three are corrected at the V3.4
close against the committed file: `data/geo/region_graph.json` holds 463 edge
records, whose fourth element is `land` 447 times and `sea` 16. The V3.3
HANDOFF never carried the wrong figure — it predates the count.)*

The components count stayed a measurement -- adjacency alone
leaves 18 pieces on the new roster (measured before authoring), and each link
that closes one is a real crossing in service: the Oresund bridge and the
Great Belt carry the Nordic bloc (Sweden-Finland is its own land mass in this
graph; Denmark's islands are another), the Greek archipelago is served from
Piraeus and Igoumenitsa, Malta from Pozzallo, Cyprus from Piraeus. Ireland
needs no link -- it reaches the continent over the land border with Northern
Ireland. Aland's ferry died with its region: FI20 carries no GeoNames place at
all (cities15000's cut is above Mariehamn), so the register cannot name it,
and a link naming a code the register does not carry is refused.

- **Greece has no motorway endowment**: `tran_r_net` MWAY carries zero EL
  codes at every year -- the rail refusal's cousin, a dataset boundary rather
  than a download bug. The 27 codes missing endowment (all of Greece,
  continental Portugal, most of Croatia) fall back to the roster mean the
  loader already documents; the graph's distance term is measured everywhere
  and the endowment is the local one. A second instrument for a
  dimensionless local term is not bought for one nation.
- **Luxembourg's bound is now five nations'**: CYP, EST, LTU, LVA, MLT are
  single-region at NUTS 2 like LUX -- degree 0 within their own nation, the
  panel's least-connected line names each, and none can differ from itself.


## 13. V3.4: the graph drawn, and the two quantities that share a scale

The graph has been live and invisible since V2.7. V3.4 draws it.
`src/ui/map_network.gd` builds one spine per edge between the two regions'
`cities[0]` — the same anchors `build_region_graph()` measured its kilometres
between (`tools/import_data.py`'s `_principal_lonlat()` feeds the haversine),
so the line on screen and the distance the model discounts by cannot disagree
— and `src/ui/map_view.gd` draws them in `_draw_spines()`, the **eighth** pass
it now owns and the fourth it calls, between the roster fills and the labels,
gated on the existing `CITY_MIN_ZOOM` (2.0) because a spine drawn while neither
of its cities is drawn is a line from nowhere to nowhere. No new threshold was introduced and nothing was swept.

**The sixteen sea links are dashed and the 447 land edges are solid.** One
hue, not two: `LAND` and `SEA` are the same brass and differ only in alpha
(0.30 against 0.42), so a ferry is told apart by its *stroke* rather than by a
second accent competing with the marks the player's own actions put on the
map. The dash is `DASH_PX` 7 / `GAP_PX` 5, and the screenshot pass measured
where that fails: the register's shortest sea edge, DK01–SE22
(Copenhagen–Malmö, 28.4 km), spans 10.6 px at `CITY_MIN_ZOOM` — shorter than
the 12 px cycle, and covered anyway by its two ~5 px city markers. The
constants were left alone because no shrink rescues 10.6 px between two
markers. It draws two dashes from zoom 3.6 and three by zoom 6 -- frame and
arithmetic agree to the pixel. *(That edge also
corrects a claim this project carried: the Channel, FR1–UKI at 343.8 km, is
**twelfth** of the sixteen, not the shortest.)*

**Convoy density is a ratio, and the two families share a scale that was not
invented.** A cross-border spine reads `w(A→B)` and `w(B→A)` from
`Trade.weight_table()` separately, so V1.3b's asymmetry is visible as more
lorries on one side of a crossing — the screenshot pass counted roughly twice
the marks on cross-border spines as on internal ones. An internal spine reads
its two regions' index from `Regions.accessibility_for()`, and carries **equal
counts in both directions**, because accessibility is undirected and drawing a
direction there would be drawing a number that does not exist. Those two look
incomparable and are not: a weight vector sums to 1 over n−1 partners, so
dividing by the even share puts it on a scale whose mean is 1.0, and
accessibility is normalised to an output-weighted mean of *exactly* 1.0 by §5's
construction. Both are already "times the mean". A conversion constant between
them would have been one number nobody could measure — V1.6f's
three-independent-facts rule, and the same refusal §7 argues and §10 lists,
for letting a finished project cut its own site's edge costs.

**Nothing is stored.** A convoy's stagger is `Cycle.unit()` of the edge key
*and its direction* together with the mark's index, and its phase advances off
the sim clock — so pause freezes it, speed moves it, a reloaded save puts every
convoy back where a fresh clock would, and `SAVE_VERSION` stays **33**. V1.8's
events precedent, applied to a drawing. `git diff main..HEAD -- src/sim/
src/core/` is empty for this whole block, and the balance re-run was predicted
bit-identical before it was run and came back byte-identical **unfiltered** --
1 697 of 1 697 raw lines and one md5 across both captures, 50/50 invariants OK,
zero outcome changes, both sides run from worktrees at `bfcda29` and `c4ba7df`.

**Two refusals recorded with their measurements.** Natural Earth 1:10m roads —
public domain, and therefore never a licence problem — were refused **after
passing coverage** (212/213 regions, 99.5 %): the disqualifying test was EDGE
IDENTITY, since road properties carry name/type/sov_a3/length_km and nothing
naming a region or an edge, so 0 of the 463 graph edges can be looked up in
them, where derived spines score 463/463 by construction. The decorative
under-layer was declined on measured cost: Major Highway alone is +77 % vertex
mass on a map whose whole geometry is 37 861 points. `tools/roads_probe.py`
derives every figure; the verdict is in `docs/data-sources.md`. Second refusal:
routing the pair weights over the graph to accumulate a per-edge load — the
physically honest version — refused because it is this block growing the
routed-traffic model the tier told it not to build. What was measured and
therefore *not* refused is geometric attribution (building a graph from the
linework); that stays open and is recorded as such.

**A correction this block made:** the graph is **463 edges** (447 land, 16
sea), not the 464 §12 above, `AGENTS.md`'s V3.3 row and the V3.4 handoff all
carried. Counted from `data/geo/region_graph.json` directly.

**One Godot semantic worth keeping, because it is silent.**
`Rect2.intersects()` defaults to `include_borders = false`, so a *degenerate*
box — an edge whose two `cities[0]` share an exact longitude or latitude — is
culled away at some pan positions and its spine simply never draws, with no
error. `map_network.gd`'s test scans all 463 raw boxes and fails on any zero
width or height, naming the edge and the axis; zero edges have coincident axes
today. (`Rect2.has_point()` is half-open for the same reason — it
excludes the right and bottom edges — so a tight bbox always excludes at least
one of its two defining corners, which is why the box assertion grows by 0.001.)
