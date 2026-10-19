---
title: Geography Model
tags:
  - model
  - data
---

# The Geographic Register

What a region is, what a city is, why the level differs by nation, and the one
constant this session measures. Built at V2.2a; [[tiers/v2|V2]] section 2.

> [!important] A register, not a machine
> At V2.2a nothing in `src/sim/` read a region: a region carried no GDP, no
> unemployment and no sector mix; a city carried no population, no jobs of its own
> and no growth. §5 is the session that makes a region load-bearing and §6 the one
> that moves people between cities, and each arrives with the field it needs rather
> than finding it pre-authored and inert. **V2.5 is that session, and the check was
> inverted and narrowed rather than deleted** — V2.2b's treatment of the geometry
> assertion, one file over: exactly ONE file under `src/sim/` may reach the register
> (`src/sim/regions.gd`, which reads it as a duck-typed Array and preloads neither
> type, so the old preload scan was green all along and a second reader arriving the
> same way would never have turned it red — the narrowed check reads the field
> contract instead). **V2.6a is the session §6 promised, and the register is STILL
> content**: the two shares are seeded from these files and then move every month
> ([[migration-model]]), so the authored share is now WHERE A PLACE STARTED rather
> than what it is — the one quantity whose meaning changed, and the reason the
> re-seed-on-load rescue is refused. A city still carries no population of its own
> (only a live share of its region) and no economy of its own; `city.gd`'s own
> error string is unchanged from V2.5 and still defers the head count to §6 —
> *left the city a share of population, which is what docs/tiers/v2.md section 6
> comes here to change* — a framing V2.6a has made stale in the humbler direction:
> the head count it defers now exists, and the economy is the part still owed.
> Updating the string is a `src/` edit no docs pass carries. See
> [[region-economy-model]] and [[migration-model]].

## 1. The shape

A region holds a **share of its nation's population**. A city holds a **share of its
region**. Both sums are at most 1.0 and the remainder is unnamed:

| level | named | residual is |
|---|---|---|
| nation → regions | 112 NUTS regions | extra-regio output (`<CC>ZZ`) and the overseas regions the map's bounding box drops |
| region → cities | 581 GeoNames places | rural and the towns under the cut |

This is [[companies-model|V1.4a]]'s partition exactly — a firm holds a share of its
sector and the unnamed rest of the sector is the residual — and it is the tier's own
call rather than an analogy reached for afterwards: *a city is to population what a
firm is to sector output*. Neither residual is stored. A residual that is `1.0 − Σ`
cannot drift from the thing it is the remainder of, and it is what makes the register
**additive**: a later session naming a further city takes share out of the residual
and moves no existing number.

`data/regions/<NATION>.json` holds regions and each region holds its own cities, on
`data/companies/`'s per-nation shape. Cities nest rather than living in a directory of
their own, for the reason a firm's `share` sits on the same line as its `sector`: the
denominator is named beside the numerator and cannot be mis-keyed.

**An absent file is an error here**, which is the one place this register departs
from the two it copies. A nation with no companies has unpartitioned sectors and a
nation with no outlets has no press, and both are models the roster ran before V1.4a
and V1.5d — so an absent file there is a coverage decision a later session may take.
There is no such prior model here: §5 makes *national = Σ regions* the economic spine.

## 2. The level is per nation, and it is a measurement

§2 of the tier doc says *"Content from Eurostat NUTS 2"*. For the nation this game is
about, **NUTS 2 is the pre-2016 régions**: Eurostat's own labels return `FRC1
Bourgogne`, `FRE1 Nord-Pas de Calais`, `FRE2 Picardie` — units abolished in 2016. A
French player reading "Picardie" in a game set in 2026 reads a bug, and
[[fictionalization]] names **Occitanie** as its example of a real region, which is
NUTS **1** (`FRJ`).

The inverse holds elsewhere, and that is why one level cannot serve the roster: Italy's
NUTS 1 is five statistical macro-areas and Switzerland's is **one**.

| nation | level | units | why |
|---|---|---|---|
| FRA | 1 | 13 régions | NUTS 2 is the abolished pre-2016 set |
| DEU | 1 | 16 Länder | NUTS 2 is Regierungsbezirke |
| GBR | 1 | 12 | 9 English regions + Wales, Scotland, Northern Ireland |
| BEL | 1 | 3 | Flanders, Wallonia, Brussels — Belgium's actual political division |
| ITA | 2 | 21 | 20 regioni, Trentino split into its two autonomous provinces |
| ESP | 2 | 18 | 17 comunidades + Ceuta and Melilla; Canarias dropped by the bbox |
| NLD | 2 | 12 | provinces |
| AUT | 2 | 9 | Bundesländer |
| CHE | 2 | 7 | grandes régions. NUTS 1 is one country |
| LUX | 2 | 1 | one region at every level |

**The level never reaches `src/`.** `tools/import_data.py`'s `REGION_LEVEL` and each
file's `_source` line are the whole record; the loader reads `data/regions/` and never
learns a level exists. That is AGENTS.md's first rule, and `tests/test_geography.gd`
checks it in the *data* — the region files' top-level keys are exactly `_source`,
`_year`, `_note`, `regions` — rather than by grepping `src/` for the word, which was
the first version of the check and failed on the comments explaining the absence.

**Switzerland could be NUTS 3** — the 26 cantons are the politically real unit where
the 7 grandes régions are statistical. Not taken, and recorded rather than left
silent: 26 units for 8.7 M people is finer than every other nation on the roster, and
a register whose grain varies by an order of magnitude is one §5 has to special-case.

## 3. The geometry is the authority on the roster

A region with no polygon cannot be drawn, and this tier exists to locate things. So
the register is the set of NUTS codes that carry **both** a figure and a GISCO
polygon. That single rule resolves three unrelated problems:

- **`<CC>ZZ` — Extra-Regio NUTS 2**, the output belonging to no region (offshore,
  embassies, ships) — carries a figure and has no geometry, so it lands in the
  residual with no filter of its own. Present for FR, IT, ES, BE, NL and AT.
- **The Eurostat response carries two NUTS vintages at once.** `NL35` and `NL36` are
  the 2024 codes for Utrecht and Zuid-Holland and `NL31`/`NL33` the 2021 ones, and
  the values are equal to the person — so summing all fourteen Dutch codes overstates
  the Netherlands by **5.1 M**. Filtering to the codes the 2021 geometry knows leaves
  exactly twelve and the sum is the national figure to the digit.
- **`FRY` and `ES70` are the overseas regions**, and the bounding-box filter that has
  dropped them from the map since S8 drops them here for free.

The partition is exact **in the source itself**, which is worth stating because it is
what makes the residual honest: France's 2022 population, 68 091 703, is the sum of
its own NUTS codes to the unit, and so is its regional GDP (2 653 997.2 M EUR). The
residual is therefore *exactly* what the two rules above removed, and it is non-zero
for two nations only — FRA **0.0330** and ESP **0.0460**.

## 4. Britain, and the half the tier row got wrong

The ROADMAP's V2 preamble records that `nama_10r_2gdp` carries zero `UK` geo codes,
that Eurostat dropped UK regions after withdrawal, and that *"Britain therefore needs a
second source or an authored register"*. Half of that is right and the wrong half is
the one that mattered.

- **Regional GDP**: confirmed absent at **every** year, 2018 included — the codes were
  removed from the dimension rather than left empty, so [[unrest-model|V1.5c]]'s
  nearest-year fallback genuinely has nothing to fall back to.
- **Regional population**: `demo_r_pjangrp3` carries **41 UK NUTS 2 codes and 12 NUTS
  1 codes with values at 2019**, summing to the UK national figure (66 647 112)
  exactly.

So regional population is measured for all ten and only regional GDP is short — and
regional GDP is the quantity §5 makes load-bearing, not §2. **V2.2a's share is a share
of population**, Britain reads 2019 through the same per-series nearest-year fallback
V1.5c wrote for `SI.POV.GINI`, and the year used is written into the file. Regional
GDP and Britain's second source pass to §5 whole.

ONS was probed before that call was taken rather than assumed unavailable: its beta
API publishes `gdp-by-local-authority`, which is 380 LAU rows with **no ITL codes at
all**, so aggregating it to ITL2 needs a fourth dataset as a lookup. Recorded so §5
does not re-derive it.

> [!warning] V2.5 measured the other half, and §4 was half right about it too
> The authored fallback at NUTS 1 is *not* twelve numbers from one product: ONS's
> `regional-gdp-by-year` publishes ITL1 `UKC`–`UKL` — ten of twelve — plus England
> and extra-regio, and Scotland and Northern Ireland come from the devolved
> administrations. The product is an annual index (cvm) besides, not a monetary
> level. The gate was all twelve ITL1 figures; it failed; the **population proxy**
> was taken rather than a number invented, and Britain having no regional
> divergence at all is a measured bound in [[region-economy-model]] §8, with the
> unemployment and GVA series carrying the same zero-`UK` hole.

## 5. The city join is a point in a polygon

**It cannot go through GeoNames' own `admin1`**, and that is why the geometry is
downloaded rather than only a code table: for France `admin1` is the 13 modern
régions, which is NUTS 1 and therefore *coarser* than the NUTS 2 the row asked for. A
code join would be silently wrong for at least one nation and unverifiable for the
rest.

Three outcomes, each saying something true, and anything else stops the import:

| outcome | count | what it is |
|---|---|---|
| inside | 4 002 | the polygon contains the point |
| snapped | 82 | a coastal commune the GISCO 10M coastline cuts — Birkenhead, Portsmouth, A Coruña, Santander, Cádiz, Antibes, Marsala. Tolerance `CITY_SNAP_DEG = 0.25` |
| overseas | 40 | inside, or nearest to, a region the bounding box dropped — the Canaries, the French DOM. These belong in the residual |
| failed | **0** | |

Holes matter here in a way they do not for the national outlines: Berlin is a hole in
Brandenburg and Vienna one in Niederösterreich, so ignoring them would file every
Brandenburg city under Berlin and both partitions would still sum to 1.0.

`tests/test_geography.gd` re-runs the containment check against the committed
geometry, with a **duplicate** ray cast rather than a shared one — a containment check
written against the code that placed the point would always pass.

## 6. The cut, and the three times it was measured wrong

`CITY_MIN_POP = 71000`, plus **each region's largest city whatever its size**, so no
region is unnamed. Two clauses fixed before the sweep ran:

- **(ii) coverage** — the roster's mean named share of national population is at least
  **0.30**, so the register describes the country rather than a rounding error in it.
- **(iii) volume** — at most **600** named cities across the ten, written from the
  drawing side: V2.2b draws by rank and the roster at the opening fit is ~1000 px
  wide, so a bigger register ships content the map can never separate.

Swept 15 000–200 000, refined to 1 000: they cross at **[69 000, 73 000]** — 69 000 is
the first row at or under 600 cities (596) and 73 000 the last at or over 0.30 mean
coverage (0.3006). Both edges are **smooth crossings** rather than plateaux, so
neither selects and the interior governs ([[media-model|V1.5d]]'s rule): the midpoint,
**71 000**. Same answer at a grid of 2 000 and of 1 000, which is
[[demography-model|V1.5b]]'s refinement diagnostic, and interior to the swept range
rather than on its edge. The register is identical for any cut in **70 915–71 010**,
the gap between the two adjacent city populations that bracket it.

**A third clause was written and deleted.** *"The worst nation names at least 0.20 of
its population"* fails at every candidate, and its two failing nations do not move with
the threshold at all: Luxembourg has **one** city and it is 11.9 % of the country, and
Swiss communes are administratively small (Zürich is 341 k of 8.7 M). Both are held at
the floor by the top-up rule rather than by this constant. A band an observable cannot
reach is a bound and not a selector — [[society-model|V1.5a]]'s finding and
[[unrest-model|V1.5c]]'s — so it is recorded here rather than met by shipping 4 691
cities.

> [!warning] Measured three times, and the first answer was wrong by 29 %
> The first sweep landed on **[82 000, 101 000]** and a midpoint of 91 500, and it was
> measuring GeoNames rather than Europe. All three corrections came from **reading the
> generated file**, not from a check — which is why each is now an assertion in
> `tests/test_geography.gd` rather than a paragraph here.
>
> 1. **607 `PPLX` rows** — "section of populated place" — in the ten, 76 above the cut.
>    Hamburg-Nord, Carabanchel, Eixample, Favoriten, `Paris 13e Arrondissement`. Each
>    double-counts the city it is part of. Excluded by feature code, with `PPLQ`
>    (abandoned) beside it.
> 2. **GeoNames mixes administrative levels, and the feature code does not catch it.**
>    `UKI London` named London and then twenty of its own **boroughs** — Islington,
>    Westminster, Bexley, Croydon — summing to **1.325** of the region; Brussels named
>    its communes and reached **1.285**. Fixed by taking cities in descending order
>    only **while they fit**, which needs no list of exceptions.
> 3. **Some Paris arrondissements are coded `PPL`, not `PPLX`** — `Paris 15 Vaugirard`
>    at 229 713 is one — so neither the feature filter nor the fit rule (Île-de-France
>    is large enough to hold Paris *and* its districts) removed thirty-six Paris and
>    Marseille arrondissements. The discriminator is a **number**: a plain name-prefix
>    test also eats `Mansfield Woodhouse`, `Newport Pagnell`, `Amersham on the Hill`,
>    `Ischia Porto` and `Kronberg Tal`, which are five real places, where requiring a
>    digit immediately after the parent's name catches all thirty-six and none of the
>    five.

**Two sources disagree about city-states, and the fit rule settles that too.** Eurostat
puts Hamburg at 1.854 M and GeoNames at 1.974 M, a 6 % difference of definition and
vintage; Ceuta and Melilla are the same case at 1.5 % and 0.1 %. Where the largest city
*is* the region, it is admitted at a share of exactly **1.0** and the residual is zero
— true of a city-state and false of nobody.

**Shares are rounded DOWN**, not to nearest. Rounding to nearest put Germany's sixteen
Länder at 1.000003 of Germany and the Netherlands' twelve provinces at 1.000001 — a
residual of minus three parts in a million, which is arithmetically nothing and is
still a partition that does not hold. The residual absorbs the rounding rather than
losing to it.

## 7. The measured tables

`tools/geography_probe.gd`. It runs **no months at all**, which is worth saying: every
probe since V1.3f has had to be checked against the state it measures, and a register
no tick writes has no wrong state to measure.

**(a) the national partition**

| nat | regions | smallest | largest | residual |
|---|---|---|---|---|
| FRA | 13 | 0.0052 | 0.1818 | 0.032984 |
| DEU | 16 | 0.0081 | 0.2153 | 0.000009 |
| ITA | 21 | 0.0021 | 0.1684 | 0.000010 |
| ESP | 18 | 0.0017 | 0.1792 | 0.046036 |
| BEL | 3 | 0.1058 | 0.5776 | 0.000002 |
| NLD | 12 | 0.0220 | 0.2134 | 0.000007 |
| LUX | 1 | 1.0000 | 1.0000 | 0.000000 |
| CHE | 7 | 0.0403 | 0.2183 | 0.000005 |
| GBR | 12 | 0.0283 | 0.1377 | 0.000005 |
| AUT | 9 | 0.0331 | 0.2151 | 0.000003 |

**(b) the city partition** — coverage is the share of a nation's people living in a
city the register names.

| nat | cities | coverage | fullest region | thinnest |
|---|---|---|---|---|
| FRA | 66 | 0.1823 | FRL 0.3435 | FRB 0.0999 |
| DEU | 122 | 0.3556 | DE6 1.0000 | DE4 0.1062 |
| ITA | 84 | 0.2757 | ITI4 0.4995 | ITF1 0.0937 |
| ESP | 97 | 0.4532 | ES63 1.0000 | ES43 0.2333 |
| BEL | 16 | 0.2804 | BE1 0.9601 | BE3 0.1844 |
| NLD | 45 | 0.4146 | NL23 0.5894 | NL34 0.1202 |
| LUX | 1 | 0.1188 | LU00 0.1188 | LU00 0.1188 |
| CHE | 9 | 0.1588 | CH04 0.3369 | CH05 0.0630 |
| GBR | 132 | 0.4866 | UKI 0.9977 | UKL 0.2659 |
| AUT | 9 | 0.3049 | AT13 0.8757 | AT12 0.0264 |

581 cities, roster mean coverage **0.3031**.

**(c) where the jobs are, and this is the table the row did not ask for.** The firm
domicile is the only thing making `Company.city` load-bearing before V2.2b draws it,
and what it says is that the eighteen firms this game names are concentrated in a way
nothing authored:

| nation | city | jobs | of the named payroll |
|---|---|---|---|
| FRA | Lille | 145 000 | 33.1 % |
| FRA | Toulouse | 112 000 | 25.6 % |
| DEU | Düsseldorf | 198 000 | 34.3 % |
| DEU | Stuttgart | 156 000 | 27.0 % |
| GBR | Manchester | 168 000 | 44.0 % |
| GBR | Birmingham | 88 000 | 23.0 % |

**One city holds a third to a half of a nation's named payroll**, which is what makes
§6's migration a decision rather than a diffusion — and it is worth §5 knowing before
it writes a regional unemployment rate.

**(d) the largest region** — Vlaams Gewest is **57.8 %** of Belgium against Brussels'
10.6 %, the widest single region on the roster; Italy's largest is 16.8 % of it. A
regional economy is a genuinely different object in those two countries.

## 8. What this session does not carry

- **No `SAVE_VERSION` bump**, and it stays at **27**. The register is content: a
  region's share and a city's share round-trip through `data/regions/` the way a
  firm's authored share and headcount round-trip through `data/companies/`, and a
  firm's `city` is one more authored field. `tests/test_save_load.gd` pins the
  **absence** of `regions`, `cities`, `region_share`, `city_share` and
  `region_population` — three absences failing for three different reasons — so §5
  has to come and say why it bumps.
- **No balance re-run and no new regime.** Nothing in `src/sim/` was touched beyond
  one pure query, and a region is not a verb. Predicted in the plan rather than
  discovered, on U6c's precedent. (Unchanged at V2.2b, for the same reason: drawing
  is not a verb either, and both new panels only read.)
- **UI arrived at V2.2b.** `data_loader.gd` loads the geojson into
  `region_features` now — the 180 KB is paid because something draws it — and
  the loader cross-checks every register region against its geometry, the
  fourth `RegionsLoader.validate_regions()` rule, catching at load time an import that drifts
  from its own authority. The map fills each nation from its 1:10m regions under
  the 1:50m national stroke, and what makes that render correctly with holes
  dropped is a two-pass draw: every region fill first, every hairline after, so
  an enclave's boundary survives its host's fill regardless of authored order —
  the roster carries one enclave of EACH direction (Berlin outpopulates
  Brandenburg; Bremen is a third of Niedersachsen), so no single fill-and-stroke
  order renders both. The absence assertion V2.2a left in
  `tests/test_geography.gd` turned red on exactly the day it said it would, and
  was flipped with the reason recorded beside it.
- **No regional GDP, unemployment or sector mix.** §5's.



## 9. V3.3: the register grows to EU-27 + 2, and what the growth measured

**The register is 213 regions over 29 nations, 1 065 named cities.** The ten-era
tables above are kept as the historical record of the clauses; the numbers that
govern now: REGION_LEVEL gained nineteen entries, all NUTS 2 (NUTS 1 for these
nations is either a single region or a grouping coarser than the country's own
planning unit), and five of them are single-region nations on the Luxembourg
precedent -- CYP, EST, LTU, LVA, MLT.

**The importer's bounding box widened east from 32 to 35 for Cyprus**, whose
rings span to 34.6 E; the fit's binding dimension is latitude and did not move
(recomputed, not assumed: 2.08 on 1080p against the old ~2.1), so
`CITY_MIN_ZOOM` 2.0 kept its just-under place.

**CITY_MIN_POP re-swept on BALANCE_PLAN.md's pre-declared band: 71 000 ->
58 000.** The clauses rescaled with the roster: (ii) mean named share >= 0.30
over 29 nations, (iii) at most 1 800 cities. Swept 20 000..120 000 and refined
to the 1 000 grid at both crossings, which sit at 38 000 (count) and 78 000
(coverage); the interior's midpoint shipped, stable across both grid steps --
V1.5b's refinement diagnostic, third constant in a row to land that way.

**THE NINETEEN MEASURED THE IMPORT'S OWN ASSUMPTIONS DEAD, in four places.**
Portugal's NUTS 2024 revision SPLIT AMLisboa (PT17 answers under PT1A+PT1B)
and carved Oeste e Vale do Tejo out (PT16->PT19, PT18->PT1C), so the vintage
join grew a PARTITION shape beside the Netherlands' 1:1 renumbering -- exact
only because GDP and GVA are additive stocks, and the unemployment file answers
under 2021 codes natively. Åland (FI20) carries NO GeoNames place at all
(cities15000's cut is above Mariehamn), so the top-up rule's assumption that
every region has a largest city is false on this roster: a region with no
nameable city drops into the residual -- where extra-regio and the overseas
already live -- and its sea link died with it (a link naming a code the
register does not carry is refused). Greece's motorway density is absent from
tran_r_net at every year: a bound recorded in network-model.md, the mean
fallback the endowment already carried. And the sea links numbered SIXTEEN
(measured: the components adjacency leaves), each a real crossing in service --
the Oresund and Great Belt fixed links carrying the Nordic bloc to the
continent, the Greek archipelago served from Piraeus and Igoumenitsa, Malta
from Pozzallo, Cyprus from Piraeus; Ireland needs none, over the land border
with Northern Ireland.

## 10. V4.11: the neighbourhood, and two kinds of region

**The register is 277 regions over 41 nations, 1 373 named cities, 640 graph edges
(623 land + 17 sea), one component.** The twelve neighbours are simulated and not
playable; the 29's regions, cities and edges are byte-identical to V3.3's, checked
by re-importing and diffing `data/`, because every roster-wide quantity the
importer computes (the cycle anchor, the inflation statistics, the motorway
endowment mean) is pooled on `import_data.ANCHOR_POOL`, the 29.

**Two kinds of region now share the register.** Seven neighbours are NUTS-covered
(NOR, ISL, SRB, TUR at NUTS 1, ALB, MKD, MNE) and go through the V2.2 pipeline
unchanged. Five are not (BIH, UKR, MDA, XKX, BLR): their regions are Natural Earth
admin-1 polygons dressed as NUTS (`inject_admin1`), with ISO 3166-2 ids, the
statistician's own population shares where published, and the population proxy for
every economic series -- Britain's shape, generalised to `PROXY_SERIES`. Bosnia's 18
Natural Earth units are dissolved to its entities (the CHE-cantons refusal: finer than
any nation reads); Moldova and Kosovo are one region each.

**Crimea and Sevastopol are outside the register** -- Natural Earth 5.1.2 draws them
inside Russia in both layers, and the game takes the layer as published (a bound,
recorded in [[data-sources]]). The map draws no front lines; war is refused at the tier.

**Cross-source adjacency is a rule, not a list**: GISCO and Natural Earth never share
a vertex, so a pair with a Natural Earth region on one side is adjacent when 10
boundary vertices of one lie within 0.05 deg of the other's -- swept against the real
map until it admitted every true border and no false one ([[data-sources]] has the
sweep). Iceland joins the graph through its real ferry (Hirtshals-Seydisfjordur).

**The volume clause holds without a re-sweep**: 1 373 named cities against V3.3's
(iii) ceiling of 1 800, at `CITY_MIN_POP` 58 000 held so the 29's cities did not move.

**The grade is derived**: `src/core/roster.gd` reads playable / simulated off the
nation file's one bool and outline off the world register, pinned by `tests/test_roster.gd`.

---

Related: [[tiers/v2]] · [[companies-model]] · [[data-sources]] · [[data-architecture]]
· [[fictionalization]]
