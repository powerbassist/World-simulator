---
title: Open Data Sources
tags:
  - data
  - licensing
---

# Open Data Sources

Which open datasets seed the game's content, what each one is licensed under, and the rule that keeps them from leaking into the runtime.

> [!important] Import-time, never runtime
> Datasets are read **once**, by a script, to generate the JSON in `data/`. The generated JSON is committed and then hand-edited freely. The shipped game never opens a shapefile, never parses a CSV, and never touches the network. See [[data-architecture]] for the pipeline.

## Chosen sources

### Natural Earth — map geometry

- **License:** Public domain. No attribution required, no conditions.
- **Provides:** Country borders (`admin_0_countries`), sub-national regions (`admin_1_states_provinces`), populated places. Available at 1:10m, 1:50m, and 1:110m detail.
- **Used for:** The 2D map, at **two detail levels for two jobs**. The ten simulated nations come from 1:50m — enough detail that Belgium and Luxembourg read correctly, small enough that the whole of Europe is a manageable GeoJSON — into `data/geo/europe.geojson`. Every other country comes from **1:110m** into `data/geo/world.geojson`, added at U5b as the backdrop beyond the roster.
- **Why 1:110m for the world:** 242 countries at 1:50m is several megabytes of JSON parsed at every launch, larger than the satellite raster it is drawn over, to gain detail on borders nothing in the game can click. World coordinates are rounded to **2 decimals** (~1 km, below one screen pixel at every zoom the map offers) rather than the roster's 4, and rings whose bounding box is under 1 deg² are dropped — at the furthest zoom out such an island is about 2.5 px across, and the raster underneath still shows it.
- **The two files never overlap.** `build_world()` excludes the ten in `NATIONS`. Drawn from both, they would be outlined twice and tinted over their own coastline.
- **Label anchors:** Natural Earth's own `LABEL_X` / `LABEL_Y` are carried into both files as `label_lon` / `label_lat`. They are hand-placed and better than a polygon centroid — Norway's centroid is in Sweden.
- **Note:** Sub-national regions are imported now but decorative at MVP. They exist so regional autonomy in [[v1]] doesn't require a second import pass.

### Natural Earth roads — measured at V3.4, and refused on ATTRIBUTION after passing coverage

The probe was written expecting to refuse this on coverage, the way the V3.4
row and its handoff both assumed. **It passed coverage and was refused anyway**,
which is why the number is worth keeping: the reason recorded here is not the
reason anyone predicted.

- **License:** public domain, like the rest of Natural Earth. Licence was never
  the discriminator — that is exactly why this was the alternative worth
  measuring and OpenStreetMap was not (ODbL share-alike attaches to derived
  databases, and `data/` would be one).
- **Coverage — PASSED** (`tools/roads_probe.py`, 1:10m at tag `v5.1.2`): the
  probe's first-match count is **210 of 213** regions, 98.6 %, with AT13, ES63
  and RO32 empty; the true figure is **212 of 213**, 99.5 %, and only **ES63**
  (Ceuta, 19 km² of Spanish North Africa) is genuinely empty of linework. The
  gap is the attribution method, not the data: the probe files each road vertex
  under the *first* region ring that contains it and then stops, so a vertex
  inside an enclave is taken by whichever host ring came first in feature order.
  Re-tested against their own rings alone, AT13 Wien carries 24 vertices and
  RO32 București 101. **This is the second time the same enclave class has
  bitten a probe here** — [[network-model]] §1 records the V2.7 network probe
  reporting 12 components and 10 isolates over AT13, BE1 and DE3 — but by the
  *opposite* mechanism, and it caught a different subset. V2.7 ignored hole
  rings; this probe reads them and lets whichever ring comes first in feature
  order take the point, so AT13 and RO32 (whose hosts AT12 and RO31 precede
  them) lost their vertices while BE1 Bruxelles and DE3 Berlin, which precede
  their hosts, were counted correctly this run. RO32 is not in §1's list at all.
  The re-test corrects **false negatives only** — it runs on the empty codes —
  so a host with no linework of its own but a road-bearing enclave in its hole
  ring would be credited and never re-tested; no host on this roster is in that
  state, which is why 212 is exact. Both numbers are printed side by side by the
  probe, so neither can be read alone. Either is well clear of the ~90 % line
  set before the run.
- **Edge identity — no attribute join exists, and that decided.** The probe
  prints all 31 property keys and **not one names a region or an edge**: no NUTS
  code, no region id, no origin/destination pair. `sov_a3` names a sovereign
  state, which is a nation and not one of the 213 regions — and over the 7 850
  features inside the roster's box it is **null on every one of them**. `name`
  is filled on only **1 719** of those 7 850, and what it holds is a route
  number (`E` + `65`), a road designation rather than a place. `add`, `toll`,
  `ignore` and `uident` are `0` on all 7 850. What is actually populated there
  is `type`, `featurecla` and `continent` (7 850 each), `length_km` (7 789) and
  the cartographic ranks — none of which is an identity. So a line for one of
  `data/geo/region_graph.json`'s 463 edges cannot be **looked up** in this file;
  the count of edges Natural Earth can name by attribute is **zero**, and the
  probe derives both that zero and the 463 rather than printing them. This block
  draws one line per edge because the convoys ride those lines and
  `Network.accessibility()` is priced over that same graph — undifferentiated
  linework cannot carry either. Generated spines score 463 of 463 on this test
  by construction, because they are DERIVED from the graph rather than matched
  to it.
- **What was NOT measured, and is therefore not refused:** *geometric*
  attribution — building a graph out of the linework itself and routing between
  two regions' principal cities. That needs no identifier, so nothing above
  rules it out. It was not attempted and not priced, and it is **out of V3.4's
  scope**: it is a routing engine, not a draw call, against a block whose G3/G5
  frame budgets are already set. The refusal stands on the two things that were
  measured — no attribute join, and the vertex cost below — not on a claim that
  this data cannot be attributed at all.
- **The decorative-layer option, priced and declined.** Natural Earth could
  still have gone UNDER the spines for looks. The probe prices it **two ways**,
  because a bounding box is a rectangle and the roster is not — the box reaches
  into Anatolia, North Africa and the Atlantic, and 846 of its 7 850 features
  are on `continent` Asia or Africa. Both are derived from
  `data/geo/regions.geojson`, not typed in, so both still describe the roster
  after the eleventh nation joins:

  | | box (the ceiling) | inside the region rings (what the map draws) |
  |---|---|---|
  | all types | 7 850 features / 129 706 vertices | 5 526 / 90 716 |
  | `Major Highway` | 1 338 / 29 209 | 1 200 / 27 253 |
  | `Major Highway` + `Secondary Highway` | 3 432 / 81 017 | 2 956 / 67 690 |
  | that pair as coordinate text | **1.44 MB** | **1.20 MB** |

  The MB is geometry only — `[lon,lat],` per vertex at the roster's 4 decimals,
  no properties and no envelope. **The file such a clip produces is bigger**:
  the same box-scoped pair written out as GeoJSON with its properties intact is
  **3.37 MB**, and that is the number to weigh when asking whether to commit it.
  The probe prints the filter that produces it rather than writing a file nobody
  asked for. The map's entire committed geometry today is **37 861 points**
  (europe 9 383 + regions 19 018 + world 9 460, counted by the probe), so the
  cheap half of that option is **+77 %** vertex mass by the box and **+72 %**
  inside the rings, and the full one is **×3.14** by the box and **×2.79**
  inside them. It lands in the everything-visible band on either reading, which
  is where culling removes nothing and where the 7.08–7.23 ms measurement lives.
  Taking it would have meant re-declaring V3.4's G3 and G5 gates upward before
  drawing anything, which is choosing a gate to fit what you wanted to build.
- **What would reopen it:** a European road source that is permissive, covers
  the roster, AND lets a line be attributed to a region pair — either by
  carrying an identifier that resolves to one, which nothing measured here does,
  or by a routing pass over the linework, which nobody has costed. The first two
  conditions are already met by this file; the third is open, not closed, and
  reopening it means measuring a route, not re-reading these keys.

> [!note] `road-generator` is not the road layer either
> AGENTS.md records the addon as parked ahead of a planned use. It generates 3D
> road meshes along splines; `src/ui/map_view.gd` is a 2D plate-carrée `_draw()`
> over lon/lat. It is not this planned use, and the name should not make a
> future session re-open it.

### NASA Blue Marble — the map raster

- **License:** Public domain (NASA Earth Observatory imagery policy). No attribution required; credited anyway, because an unattributed asset is one nobody can re-source.
- **Provides:** `world.topo.bathy.200412.3x5400x2700.jpg` — next-generation Blue Marble, topography and bathymetry, December 2004. 5400×2700, 2.5 MB.
- **Used for:** The satellite backdrop the whole map is drawn over, from U5b.
- **Why it needs no reprojection:** the image is plate carrée, which is already `map_view.gd`'s projection. Longitude maps linearly to x and latitude linearly to y across the whole image, so its rect in map space is derived from four constants in `src/ui/map_raster.gd` rather than fitted by eye.
- **The one rule about loading it:** never `load()`. That path returns the editor's imported texture out of `.godot/`, which is gitignored and absent on a fresh clone, while `tools/run_tests.sh` runs headless straight from the repo. The bytes are read and decoded in memory — the same escape `icon.gd` uses for SVG and `ui_theme.gd` for fonts, and `tests/test_map_view.gd` asserts the texture is non-null so a regression to `load()` fails the suite rather than only the clone.

> [!note] This is committed, not downloaded at build time
> `sources/` is gitignored and holds datasets a script reads once. The raster is not one of those: it is an *asset the running game draws*, so it lives in `assets/map/` and is committed, under the same reasoning the `.gitignore`'s at-icons exception already states. At 2.5 MB it is a tenth of the at-icons set that exception was written for.

### World Bank Open Data — economic seed values

- **License:** CC BY 4.0. Attribution required.
- **Provides:** GDP (`NY.GDP.MKTP.CD`), population (`SP.POP.TOTL`), unemployment rate (`SL.UEM.TOTL.ZS`), and value-added by sector — agriculture (`NV.AGR.TOTL.ZS`), industry (`NV.IND.TOTL.ZS`), services (`NV.SRV.TOTL.ZS`). **And, since [[ROADMAP|V1.5b]], age structure** — population aged 0–14 (`SP.POP.0014.TO.ZS`) and 65+ (`SP.POP.65UP.TO.ZS`) — **plus the 15–64 labour-force participation rate (`SL.TLF.ACTI.ZS`)**.
- **Used for:** Starting statistics for every nation in scope, **rounded**. GDP converted USD → EUR at a fixed rate pinned in the import script (see below), so re-running the import doesn't drift on exchange-rate noise. Sector shares are normalised to sum to 1.0 — the three World Bank value-added indicators sum to roughly 89–95% of GDP on their own (the residual is taxes less subsidies on products), so dividing by their sum is required, not optional polish.
- **Read at two years, not one, and that is what makes ageing measured rather than modelled.** The download loop below has always fetched `date=2015:2024`, so [[ROADMAP|V1.5b]]'s per-nation ageing slope cost one extra read of a series already on disk and no extra download. `imported._trend_from_year` records the base year in the data, beside `_year`, for the reason `_usd_eur` is echoed there: without it the provenance record claims the block describes one year while the cohort slopes describe two. The slopes genuinely differ — Luxembourg **+0.142** points of 65+ share per year against France's **+0.366** — which is why the ten pyramids are not the clustered `coalition_position` failure the decomposition feared. See [[demography-model]].
- **Does not provide, at usable scope: debt-to-GDP or tax revenue.** `GC.DOD.TOTL.GD.ZS` (central government debt) returns null for France, Germany, Luxembourg and Switzerland entirely, and where it does return a value (UK: 130.7% in 2024) it is central-government debt, not the general-government figure this game means by "debt-to-GDP". `GC.TAX.TOTL.GD.ZS` (central government tax revenue) has the same scope problem — it returns single digits for Switzerland and Germany, nowhere near the 35–46% general-government tax-to-GDP ratios these countries actually have. **Re-checked at [[ROADMAP|V1.6d]] before that session planned a measured base share for capital gains or wealth, and the rejection stands with two more reasons.** Coverage is not the issue -- `GC.TAX.TOTL.GD.ZS`, `GC.TAX.YPKG.*` and `GC.TAX.GSRV.RV.ZS` all return 10 of 10 nations over 1990-2024 with 30-35 rows each. The scope problem above is confirmed to the digit (FRA 22.78 % of GDP, DEU 10.89, CHE 9.45); `GC.TAX.YPKG.*` bundles income, profits **and capital gains** into one bucket, which is exactly the split V1.6d exists to create; and `GC.TAX.PRPT.*` returns **no rows at all**, so there is no wealth series on this provider. V1.6d's two new `TAX_BASE_SHARE` entries are therefore authored model parameters, like the three that preceded them, and this file gains no download line.
- **`fiscal.debt_to_gdp_pct` and `fiscal.tax_revenue_pct_gdp` are hand-authored**, from IMF/OECD general-government figures, in the `fiscal` block of each nation file — not imported, not refreshed by `tools/import_data.py`. See [[data-architecture]] for the schema.

#### V2.8 — energy

Five indicators on the loop already running, `EG.IMP.CONS.ZS`, `EG.ELC.FOSL.ZS`,
`EG.ELC.NUCL.ZS`, `EG.ELC.RNEW.ZS`, `EG.USE.ELEC.KH.PC`, **10 of 10 nations**.

**Eurostat was probed first and is short in two nations by two different
failures**, which is why this block does not come from the source every regional
series since V2.2 came from: `nrg_ind_id` carries GBR values only to **2019** and
**CHE is absent from the geo dimension entirely** (41 codes, no `CH`), and
`nrg_bal_c` GEP reads `None` for GBR at 2022. Recorded so a later session does not
re-probe it hoping for a regional energy series.

- **`EG.ELC.RNEW.ZS` includes hydro.** Checked rather than assumed: CHE 67.9 against
  a hydro share of 59.1, AUT 79.9 against 59.9. So the mix is three branches, and
  `EG.ELC.HYRO.ZS` is deliberately not fetched — a sub-share of a branch already in
  the partition is a key a later reader sums by mistake.
- **`EG.ELC.PROD.KH` is discontinued**, 0 of 10 at every year. The denominator is
  `EG.USE.ELEC.KH.PC` × live population instead, which reads France at ≈ 439 TWh
  against a real ≈ 445 TWh of generation.
- **Luxembourg's import dependency is 109.6 % and is not clamped.** It imports more
  than it consumes and re-exports the difference.
- **None of the five is complete at 2024**, so all five go through
  `load_wb_indicator_nearest_year()` and each nation file records the year every
  series came from in `imported.energy._years` — the dependency and the fossil
  share read at 2023, the renewable share at 2021, the nuclear share at 2023–24,
  per head at 2024. The three mix shares are normalised to sum to exactly 1.0, the
  same treatment the value-added indicators above get, because raw they sum to
  94–99 % (statistical difference and years that do not line up).

### Two gotchas in the Natural Earth data, confirmed against the 1:50m file

- **`ISO_A3` is `-99` for France.** The import script matches on **`ADM0_A3`** instead, which is populated correctly for all ten nations in scope.
- **France's feature has 10 polygon rings; 7 are overseas** — Mayotte, Réunion, Martinique, Guadeloupe (×3), French Guiana. Left in, they blow out the map's camera bounds at S8. The import script drops any ring whose bounding box falls entirely outside lon [−11, 32], lat [34, 72], which keeps mainland France, Corsica and Île de Ré and drops the rest. The same filter also drops the Canary Islands from Spain and the Caribbean municipalities from the Netherlands.

### Fixed conversion rate

`USD_TO_EUR = 0.92` is a module constant in `tools/import_data.py`, echoed into each nation file as `imported._usd_eur` so the provenance of every GDP figure is visible in the data itself. Pinning it rather than fetching a live rate is what makes re-imports reproducible.

### GeoNames — cities

- **License:** CC BY 4.0. Attribution required.
- **Provides:** City names, populations, coordinates.
- **Status:** **Imported at [[ROADMAP|V2.2a]]**, from `cities15000`, which is the pre-registered decision taken as written rather than re-argued. 581 places of the 4 732 the file holds for the ten, filed under the NUTS region whose polygon contains them. See [[geography-model]].
- **Three gotchas, all of them GeoNames mixing administrative levels, and all three found by reading the generated file rather than by a check:**
  - **`PPLX` is a section of a populated place, not a place** — 607 rows across the ten, 76 of them above the population cut. Hamburg-Nord, Carabanchel, Eixample, Favoriten, `Paris 13e Arrondissement`. Each double-counts the city it is part of. Excluded by feature code, with `PPLQ` (abandoned) beside it.
  - **A borough is coded like a city.** `UKI London` carries London *and* twenty of its own boroughs — Islington, Westminster, Bexley, Croydon — summing to **1.325** of the region; Brussels carries its communes and reaches 1.285. The importer takes cities in descending order only **while they fit**, which needs no list of exceptions and also settles the city-state case where Eurostat and GeoNames disagree by 6 % about Hamburg.
  - **Some Paris arrondissements are coded `PPL`, not `PPLX`.** `Paris 15 Vaugirard` at 229 713 is one, so neither the feature filter nor the fit rule removed thirty-six Paris and Marseille arrondissements. The discriminator is a **number** after the parent's name: a plain name-prefix test also eats `Mansfield Woodhouse`, `Newport Pagnell`, `Amersham on the Hill`, `Ischia Porto` and `Kronberg Tal`, which are five real places.

### Eurostat and GISCO — regions

- **License:** Eurostat's re-use policy, equivalent to CC BY 4.0. Attribution required, and it goes into `ATTRIBUTION.md` at the same time as the fetch rather than at ship time.
- **Provides:** Regional GDP (`nama_10r_2gdp`), regional population by age group (`demo_r_pjangrp3`), and NUTS 2 geometry from GISCO.
- **Used for:** [[v2|V2.2]]'s region register — a region is a main city plus the sum of the smaller cities under it, holding a share of the nation the way [[companies-model|a firm holds a share of its sector]].
- **Endpoints, probed and returning 200 at the time this section was written:**

```
https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/nama_10r_2gdp?format=JSON&lang=EN&unit=MIO_EUR&time=2022
https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/demo_r_pjangrp3?format=JSON&lang=EN&sex=T&age=TOTAL&time=2022
https://gisco-services.ec.europa.eu/distribution/v2/nuts/geojson/NUTS_RG_10M_2021_4326_LEVL_2.geojson
```

**Coverage was measured before this section was written, and the geometry and the figures do not agree about the roster.** GISCO's NUTS 2021 geometry carries all ten nations, the United Kingdom included at 41 NUTS 2 features. `nama_10r_2gdp` carries **nine**: the UK is not thin or stale, it is **entirely absent** — zero geo codes beginning `UK` in a dimension holding 471 of them, because Eurostat dropped UK regions after withdrawal. Measured 2022 NUTS 2 codes carrying a value: FR 28, DE 38, IT 22, ES 20, BE 12, NL 13, LU 1, CH 7, AT 10, **UK 0**.

> [!warning] V2.2a took that call, and half of the paragraph above is wrong — in the direction that mattered
> The UK gap is real for **regional GDP** and confirmed worse than recorded: `nama_10r_2gdp` carries zero `UK` codes at **every** year, 2018 included, because the codes were removed from the dimension rather than left empty. But `demo_r_pjangrp3` carries **41 UK NUTS 2 codes and 12 NUTS 1 codes with values at 2019**, summing to the UK national figure (66 647 112) exactly. **Regional population is measured for all ten; only regional GDP is short.**
>
> V2.2a's register is a partition of **population**, so it needs no second source at all: Britain reads 2019 through the same per-series nearest-year fallback [[unrest-model|V1.5c]] wrote for `SI.POV.GINI`, and the year used is written into each file. Regional GDP is what [[v2]] section 5 makes load-bearing, so importing it at section 2 would ship a number nothing reads — and the whole gap passes to that session.
>
> **ONS was probed before the call was taken rather than assumed unavailable.** Its beta API publishes `gdp-by-local-authority`, which is 380 LAU rows with **no ITL codes at all**, so aggregating it to ITL2 needs a fourth dataset as a lookup. Recorded so section 5 does not re-derive it. The standing alternative is still authoring, which is what `fiscal.debt_to_gdp_pct` and `fiscal.tax_revenue_pct_gdp` already do for every nation — and at NUTS 1 that is twelve numbers rather than forty-one.

- **The geometry is the authority on the roster, and one rule settles three problems.** A region with no polygon cannot be drawn and this tier exists to locate things, so the register is the set of codes carrying **both** a figure and a GISCO polygon. `<CC>ZZ` falls into the residual with no filter of its own; `FRY` and `ES70` are dropped by the bounding box that has dropped them from the map since S8; and the third problem is one this section did not know about — **the Eurostat response carries two NUTS vintages at once**. `NL35` and `NL36` are the 2024 codes for Utrecht and Zuid-Holland and `NL31`/`NL33` the 2021 ones, equal to the person, so summing all fourteen Dutch codes overstates the Netherlands by **5.1 M**. Filtering to the codes the 2021 geometry knows leaves exactly twelve and the sum is the national figure to the digit.
- **The level is per nation**, and that is a measurement rather than a taste: NUTS 2 for France is the régions abolished in 2016 (`Picardie`, `Nord-Pas de Calais`), while NUTS 1 for Italy is five statistical macro-areas and for Switzerland is one country. The table and its reasons are in [[geography-model]] section 2; `tools/import_data.py`'s `REGION_LEVEL` is the record, and no level field reaches `src/`.

#### V2.5 — the three regional economic series

- **`nama_10r_2gdp`** — regional GDP, million EUR (`unit=MIO_EUR`), the series V2.2a already probed; now fetched at 2022 for the region's `gdp_share`.
- **`lfst_r_lfu3rt`** — regional unemployment rate, per cent (`sex=T`, `age=Y15-74`, `isced11=TOTAL`, `unit=PC`), for `unemployment_rel`.
- **`nama_10r_3gva`** — regional gross value added by branch, current prices (`unit=CP_MEUR`), six `nace_r2` aggregates, for `sector_mix`. The unit filter is load-bearing: without it the response carries four units (`CP_MEUR`, `CP_MNAC`, `PYP_MEUR`, `PYP_MNAC`), and a reader that collapses the unit dimension silently mixes current prices with previous-year prices and national currency.

Coverage, measured at 2022 before any code was written (NUTS codes of this game's ten carrying a value; the GVA row is TOTAL-branch codes and the geo dimension carries several vintages at once, so its counts exceed one code per region):

```
GDP         {'FR': 44, 'DE': 55, 'IT': 29, 'ES': 29, 'BE': 17, 'NL': 19, 'LU': 3, 'CH': 9, 'AT': 15, 'UK': 0}
UNEMP       {'FR': 41, 'DE': 52, 'IT': 27, 'ES': 27, 'BE': 15, 'NL': 17, 'LU': 3, 'CH': 9, 'AT': 13, 'UK': 0}
GVA(TOTAL)  {'FR': 146, 'DE': 455, 'IT': 137, 'ES': 89, 'BE': 62, 'NL': 60, 'LU': 4, 'CH': 35, 'AT': 51, 'UK': 0}
```

All three carry zero `UK` geo codes at 2022, for the same reason `nama_10r_2gdp` does — the codes were removed from the dimension after withdrawal rather than left empty, so V1.5c's nearest-year fallback has nothing to fall back to.

`docs/geography-model.md` §4 records the authored fallback at NUTS 1 as twelve numbers. Measured: the ONS beta API's `regional-gdp-by-year` publishes ITL1 codes UKC–UKL — ten of twelve — plus England and extra-regio. Scotland and Northern Ireland are published by the devolved administrations and are not in that product.

**Britain's decision: the population proxy.** The gate was all twelve ITL1 GDP figures; ONS offers ten of twelve, and the product is an annual **index** (`aix`, chained volume measure) rather than a monetary level, so even the ten would not have been figures in this game's units. No number was invented: a British region's `gdp_share` is its population share, `unemployment_rel` is exactly 1.0 and `sector_mix` is the national mix, and the `_source` string in `data/regions/GBR.json` says so in words. The consequence — Britain has no regional divergence at all — is recorded as a measured bound in [[region-economy-model]] §10.

### Two gotchas in the Eurostat regional data, confirmed against the 2022 figures

- **`XXZZ` is "Extra-Regio NUTS 2" and has GDP but no geometry.** Present for FR, IT, ES, BE, NL and AT; absent for DE, LU and CH. It is the output that cannot be assigned to any region — offshore, embassies, ships. Left in, the region shares do not sum against a geometry that has one fewer entry; dropped silently, the nation's GDP no longer equals the sum of its regions. It belongs in the **unnamed residual**, which is the same slot [[companies-model|V1.4a]] gives the firms a sector does not name.
- **`FRY1`–`FRY5` are the French overseas regions** — Guadeloupe, Martinique, Guyane, La Réunion, Mayotte — and they are exactly what the Natural Earth import filter above already drops by bounding box. The region register inherits that filter for free, and their GDP inherits the residual for the same reason `XXZZ` does. Spain's Canary Islands (`ES70`) and the Dutch Caribbean are the same case.

#### V2.6a — the migration drift window

`tools/region_drift.py` reads `demo_r_pjangrp3` over every published year to measure how far real European regional population shares actually drift — [[migration-model|the ceiling `migration_constants.MIGRATION_RATE`'s clause (ii) is checked against]]. The fetch loop above starts at **2014**, and that lower bound is chosen rather than merely convenient: **2011, 2012 and 2013 each return an EMPTY value dict for this exact request** — not a short one, an empty one — which is where the NUTS 2021 back-cast begins. A fresh clone that only runs the recorded loop (2014 onward) cannot see this directly, since the loop never fetches the empty years to observe the emptiness; it is recorded here instead, so the window's lower bound is explained rather than merely chosen.

## Rejected sources

### OpenStreetMap

- **License:** ODbL — share-alike on derived databases.
- **Why rejected:** ODbL's share-alike provision attaches to derived databases, which is exactly what `data/` would be. Natural Earth provides the same borders at the same useful detail under public domain. Taking on a viral license to gain nothing is a bad trade.

### IMF World Economic Outlook

- **Why rejected:** Redistribution terms are more restrictive than World Bank's clean CC BY, and the extra indicators it offers are ones the MVP economy model doesn't consume. Revisit only if the economic model outgrows World Bank's coverage.

## What datasets cannot provide

Everything covered by the [[fictionalization]] rule is hand-authored. There is no dataset for:

- Heads of state and government
- Political parties and their ideology positions
- Assembly seat distributions
- Companies
- Law templates and their effects
- Events

This is by design, not a gap. These are the parts of the game that need to be *tuned*, and tuning is authoring.

## Attribution

World Bank and GeoNames both require credit. The credit line goes in `ATTRIBUTION.md` at the project root and is surfaced in the game's credits screen when one exists. It is written down at [[ROADMAP|session S0]], not deferred — an attribution obligation you remember at ship time is an attribution obligation you have already breached.

Draft line:

> Economic data derived from World Bank Open Data (CC BY 4.0). Geographic data from Natural Earth (public domain).

## How to fetch the raw datasets

`sources/` is gitignored, so nobody can commit a `sources/README.md` there — these
instructions are that file's replacement. Run once, or whenever the seed data needs
a refresh.

```bash
mkdir -p sources/wb

curl -L -o "sources/ne_50m_admin_0_countries.geojson" \
  "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_50m_admin_0_countries.geojson"

curl -L -o "sources/ne_110m_admin_0_countries.geojson" \
  "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_110m_admin_0_countries.geojson"

# V3.4. Roads, 48 MiB, and NOT imported -- this is the file tools/roads_probe.py
# measures, and the roads verdict above is only re-derivable if it can be fetched.
# Nothing in data/ is built from it; skip this line unless you are re-running the probe.
curl -L -o "sources/ne_10m_roads.geojson" \
  "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/v5.1.2/geojson/ne_10m_roads.geojson"

<!-- V3.3: every World Bank line below was re-fetched with the nineteen added to
the country filter when the roster grew to EU-27 + 2; the wide 1990-2024 pulls
carry per_page=2000 because 29 nations x 35 years is 1015 rows, past 1000. -->

for I in NY.GDP.MKTP.CD SP.POP.TOTL SL.UEM.TOTL.ZS NV.AGR.TOTL.ZS NV.IND.TOTL.ZS NV.SRV.TOTL.ZS \
         SP.POP.0014.TO.ZS SP.POP.65UP.TO.ZS SL.TLF.ACTI.ZS SI.POV.GINI; do
  curl -L -o "sources/wb/$I.json" \
    "https://api.worldbank.org/v2/country/FRA%3BDEU%3BITA%3BESP%3BBEL%3BNLD%3BLUX%3BCHE%3BGBR%3BAUT%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE/indicator/$I?format=json&date=2015%3A2024&per_page=1000"
done

# V1.6a. One indicator, on its own line, over a DIFFERENT WINDOW -- and the split is
# the honest cost of the business cycle rather than an untidiness. Measuring how
# volatile a country's growth is takes several cycles, and 2015-2024 contains one.
curl -L -o "sources/wb/NY.GDP.MKTP.KD.ZG.json" \r
  "https://api.worldbank.org/v2/country/FRA%3BDEU%3BITA%3BESP%3BBEL%3BNLD%3BLUX%3BCHE%3BGBR%3BAUT%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE/indicator/NY.GDP.MKTP.KD.ZG?format=json&date=1990%3A2024&per_page=2000"

# V1.6b. Two more on the SAME window, and this is where "one extra read of a series
# already on disk" stops being true: load_wb_indicator_series() reads one file per
# indicator CODE, so sharing V1.6a's window buys nothing on the download. Unemployment
# is re-fetched wide rather than duplicated -- the 1990-2024 pull is a strict superset
# of the 2015-2024 one (verified row by row, zero differing values) and every other
# caller reaches it through an exact-year match.
for I in FP.CPI.TOTL.ZG SL.UEM.TOTL.ZS; do
  curl -L -o "sources/wb/$I.json"     "https://api.worldbank.org/v2/country/FRA%3BDEU%3BITA%3BESP%3BBEL%3BNLD%3BLUX%3BCHE%3BGBR%3BAUT%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE/indicator/$I?format=json&date=1990%3A2024&per_page=2000"
done

# V1.1e. Rule of law, and the FIRST line here to carry `&source=3`. The Worldwide
# Governance Indicators live on a database of their own and were re-coded: `RL.EST`,
# which is what every citation of this series still names, now answers *"The indicator
# was not found. It may have been deleted or archived."* The live code is
# `GOV_WGI_RL.SC` -- the 0-100 SCORE rather than the -2.5..+2.5 estimate, because every
# other stock this game keeps on a nation is already on a 0-100 scale, so the estimate
# would be the one quantity in the game needing a conversion nobody could check.
# Complete for all ten over the standard window, so it needs no nearest-year fallback.
curl -L -o "sources/wb/GOV_WGI_RL.SC.json" \r
  "https://api.worldbank.org/v2/country/FRA%3BDEU%3BITA%3BESP%3BBEL%3BNLD%3BLUX%3BCHE%3BGBR%3BAUT%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE/indicator/GOV_WGI_RL.SC?format=json&date=2015%3A2024&per_page=1000&source=3"

# V2.8. Energy, five series on the standard window -- but every one through
# load_wb_indicator_nearest_year(), because none of the five is complete at 2024.
for I in EG.IMP.CONS.ZS EG.ELC.FOSL.ZS EG.ELC.NUCL.ZS EG.ELC.RNEW.ZS EG.USE.ELEC.KH.PC; do
  curl -L -o "sources/wb/$I.json"     "https://api.worldbank.org/v2/country/FRA%3BDEU%3BITA%3BESP%3BBEL%3BNLD%3BLUX%3BCHE%3BGBR%3BAUT%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE%3BBGR%3BHRV%3BCYP%3BCZE%3BDNK%3BEST%3BFIN%3BGRC%3BHUN%3BIRL%3BLTU%3BLVA%3BMLT%3BPOL%3BPRT%3BROU%3BSVK%3BSVN%3BSWE/indicator/$I?format=json&date=2015%3A2024&per_page=1000"
done
```

> [!note] The pandemic is excluded from that one series, and the exclusion is load-bearing
> `tools/import_data.py`'s `CYCLE_EXCLUDE_YEARS` drops **2020 and 2021** from
> `NY.GDP.MKTP.KD.ZG` and from nothing else. On the 2015-2024 window every other
> indicator uses, France's real-growth standard deviation is **3.333** -- and **0.579**
> with those two years removed, a factor of **5.8**. Every nation collapses the same
> way. A session that reused the existing window would have shipped a "business cycle"
> whose entire amplitude was one pandemic, and it would have looked measured. A
> pandemic is an exogenous disaster, which [[v1]] section 8 owns; a business cycle is
> section 6's. **2008-09 is not excluded**, because a financial crisis *is* a business
> cycle. The years actually dropped are written into each nation file as
> `imported.cycle._excludes` rather than implied, for the reason `inequality._year` is:
> a provenance record that hides its own editorial act is worse than none. See
> [[cycle-model]] section 3.

> [!warning] `SI.POV.GINI` is the one series with gaps, and it needs the fallback
> [[ROADMAP|V1.5c]] added it for section 5's inequality statistic, and it is the only
> indicator in the loop above that is **not published at `YEAR` for any of the ten**:
> coverage stops at 2021 (GBR, NLD), 2022 (CHE, DEU) or 2023 (the other six), because it
> is EU-SILC-based rather than an annual national account.
> `load_wb_indicator_for_year()`'s exact-year match would return nothing and
> `build_imported_block()`'s `sys.exit` would refuse the whole import, so
> `tools/import_data.py` carries `load_wb_indicator_nearest_year()` and a
> `SPARSE_INDICATORS` table holding this series alone.
>
> **Scoped to that one series deliberately.** A silent nearest-year fallback on GDP or
> population would turn a broken download -- which should stop the import loudly -- into
> a quietly stale figure nobody notices. And `imported.inequality` records **both** years
> it used, beside `_year` and `_trend_from_year`, for the reason those two exist: a
> provenance record that names a year the number does not come from is worse than no
> record.
>
> The measured spread is what made the series worth adding: **NLD 25.7 to ITA 34.3** on
> the level, and the slopes differ in **sign** -- six nations growing more equal, four
> less. See [[unrest-model]].

```bash
# V2.2a. The geographic register: three sources, and the only lines here that are
# not World Bank or Natural Earth. Two Eurostat years rather than one -- the UK is
# absent from 2022 and complete at 2019, which is V1.5c's nearest-year fallback on a
# second series. GISCO at TWO LEVELS, because the level is per nation.
mkdir -p sources/eurostat sources/gisco sources/geonames

for Y in 2022 2019; do
  curl -L -o "sources/eurostat/demo_r_pjangrp3_$Y.json"     "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/demo_r_pjangrp3?format=JSON&lang=EN&sex=T&age=TOTAL&time=$Y"
done

# V2.6a. The SAME series across every published year, for tools/region_drift.py --
# how far real European regional population shares actually drift, which is what
# migration_constants.MIGRATION_RATE's clause (ii) is measured against. Only the
# import needs 2022 and 2019; the drift measurement needs the span. 2011-2013 come
# back with an EMPTY value dict, which is where the NUTS 2021 back-cast begins.
#
# WARNING: this range OVERWRITES demo_r_pjangrp3_2019.json and demo_r_pjangrp3_2022.json,
# the exact two files tools/import_data.py reads the region register from. Fetching
# both loops today is harmless because both request the identical URL for those two
# years -- but a session that re-runs THIS loop alone after a Eurostat revision (a
# late correction to a published year, say) would silently change the import's
# cached inputs without anyone re-running the import. Re-run tools/import_data.py's
# own check after touching this loop, or fetch this range into a separate directory
# if the two must ever disagree.
for Y in $(seq 2014 2025); do
  curl -L -o "sources/eurostat/demo_r_pjangrp3_$Y.json"     "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/demo_r_pjangrp3?format=JSON&lang=EN&sex=T&age=TOTAL&time=$Y"
done

# V2.6c. Natural change -- demo_r_gind3's NATGROWRT, the crude rate of births minus
# deaths per region, which is what data/regions/'s natural_change_pct is measured
# from. One series, all published years: the window per nation is the widest
# contiguous run in which every register code carries a value, and the rates are
# AVERAGED over it because the 2020-2021 COVID deaths would otherwise date-stamp the
# field. 2025 is incomplete (published so far for only some codes), so every window
# ends at 2024. Britain's window is 2012-2018 for ELEVEN of its twelve codes -- UKM
# (Scotland) publishes no rates at any year, which is why every British region
# carries 0.0 -- and the Netherlands' NL31/NL33 vanish from THIS series at 2023, one
# year before pjangrp3's re-coding, so each series gets its own vintage ruling.
for Y in $(seq 2012 2025); do
  curl -L -o "sources/eurostat/demo_r_gind3_NATGROWRT_$Y.json" "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/demo_r_gind3?format=JSON&lang=EN&indic_de=NATGROWRT&time=$Y"
done

for L in 1 2; do
  curl -L -o "sources/gisco/NUTS_RG_10M_2021_4326_LEVL_$L.geojson"     "https://gisco-services.ec.europa.eu/distribution/v2/nuts/geojson/NUTS_RG_10M_2021_4326_LEVL_$L.geojson"
done

curl -L -o "sources/geonames/cities15000.zip"   "https://download.geonames.org/export/dump/cities15000.zip"

# V2.7. The transport endowment -- tran_r_net, one year, one branch. The graph's
# `endowment` is motorway DENSITY (KM_TKM2, km per thousand km2) over the roster
# mean, from data/geo/region_graph.json. 2018 is the only year that carries every
# register code: 2019 onward drops the UK codes -- the WITHDRAWAL gap, in a fourth
# place after regional GDP, regional unemployment and the natural-change rates --
# and 2022 additionally drops two Dutch codes. MWAY covers 110 of 112 at 2018
# (never published: ITG2, ITH2; the gaps take the roster mean). RAIL IS NOT
# IMPORTED: the RL branch carries 0 of 9 Austrian, 0 of 3 Belgian, 0 of 7 Swiss
# and 1 of 12 British codes at every year, and a graph mixing measured and absent
# rail invents connections no measurement supports. docs/network-model.md
# section 2 carries the full coverage table.
curl -L -o "sources/eurostat/tran_r_net_2018.json" "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/tran_r_net?format=JSON&lang=EN&time=2018"
```

```bash
# V2.5. The three regional ECONOMIC series, all at 2022, all carrying ZERO `UK`
# codes -- see the "V2.5" subsection under "Eurostat and GISCO -- regions" above.
# nama_10r_3gva's `unit=CP_MEUR` is load-bearing: without a unit filter the
# response carries four units and a reader that collapses the unit dimension
# silently mixes current prices with previous-year prices.
curl -L -o "sources/eurostat/nama_10r_2gdp_2022.json"     "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/nama_10r_2gdp?format=JSON&lang=EN&unit=MIO_EUR&time=2022"

curl -L -o "sources/eurostat/lfst_r_lfu3rt_2022.json"     "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/lfst_r_lfu3rt?format=JSON&lang=EN&sex=T&age=Y15-74&isced11=TOTAL&unit=PC&time=2022"

curl -L -o "sources/eurostat/nama_10r_3gva_2022.json"     "https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/nama_10r_3gva?format=JSON&lang=EN&unit=CP_MEUR&time=2022&nace_r2=TOTAL&nace_r2=A&nace_r2=B-E&nace_r2=F&nace_r2=G-J&nace_r2=K-N&nace_r2=O-U"
```

The Natural Earth URLs are pinned to tag `v5.1.2` rather than `master`, so the
files don't silently change under a future re-download. Then run
`python tools/import_data.py`.

> [!warning] An import used to delete fields it did not know about, and that is why the diff is the check
> `write_nation_file()` rebuilt each file from an **enumerated** key list — `id`,
> `name`, `geo_id`, `capital`, `playable`, `government`, `fiscal`, `imported` — so
> every top-level field a later session added was silently dropped the next time
> anyone ran the import. Two already had been: U6b's `leader` block and the `flag`
> block. Found at [[ROADMAP|V1.5b]] by diffing the ten files after an import and
> asking why the change was larger than the block it claimed to add. It now rebuilds
> from the file's own key order, so there is no list to forget to update, and short
> scalar arrays are written back on one line so the output already matches what is
> committed. **After any import, `git diff data/nations/` should show only what you
> meant to change** — that check is only readable because of the second fix.

The map raster is **not** fetched here, because it is not a dataset — it is a
committed asset and is already in the repo at
`assets/map/blue_marble_5400x2700.jpg`. Only if it needs replacing:

```bash
curl -L --create-dirs -o "assets/map/blue_marble_5400x2700.jpg" \
  "https://eoimages.gsfc.nasa.gov/images/imagerecords/73000/73909/world.topo.bathy.200412.3x5400x2700.jpg"
```

## Re-import safety

Fields in `data/nations/*.json` are tagged by origin so a re-import never overwrites hand-written content. The mechanism is specified in [[data-architecture]]. The short version: dataset-derived fields and authored fields live in separate objects within the same file, and the import script only ever writes the former.

---

Related: [[index]] · [[data-architecture]] · [[fictionalization]] · [[scope]]
