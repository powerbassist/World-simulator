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
- **Does not provide, at usable scope: debt-to-GDP or tax revenue.** `GC.DOD.TOTL.GD.ZS` (central government debt) returns null for France, Germany, Luxembourg and Switzerland entirely, and where it does return a value (UK: 130.7% in 2024) it is central-government debt, not the general-government figure this game means by "debt-to-GDP". `GC.TAX.TOTL.GD.ZS` (central government tax revenue) has the same scope problem — it returns single digits for Switzerland and Germany, nowhere near the 35–46% general-government tax-to-GDP ratios these countries actually have. **`fiscal.debt_to_gdp_pct` and `fiscal.tax_revenue_pct_gdp` are hand-authored**, from IMF/OECD general-government figures, in the `fiscal` block of each nation file — not imported, not refreshed by `tools/import_data.py`. See [[data-architecture]] for the schema.

### Two gotchas in the Natural Earth data, confirmed against the 1:50m file

- **`ISO_A3` is `-99` for France.** The import script matches on **`ADM0_A3`** instead, which is populated correctly for all ten nations in scope.
- **France's feature has 10 polygon rings; 7 are overseas** — Mayotte, Réunion, Martinique, Guadeloupe (×3), French Guiana. Left in, they blow out the map's camera bounds at S8. The import script drops any ring whose bounding box falls entirely outside lon [−11, 32], lat [34, 72], which keeps mainland France, Corsica and Île de Ré and drops the rest. The same filter also drops the Canary Islands from Spain and the Caribbean municipalities from the Netherlands.

### Fixed conversion rate

`USD_TO_EUR = 0.92` is a module constant in `tools/import_data.py`, echoed into each nation file as `imported._usd_eur` so the provenance of every GDP figure is visible in the data itself. Pinning it rather than fetching a live rate is what makes re-imports reproducible.

### GeoNames — cities

- **License:** CC BY 4.0. Attribution required.
- **Provides:** City names, populations, coordinates.
- **Status:** Not imported at MVP. Listed here so the decision is already made when cities become gameplay rather than decoration.

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

for I in NY.GDP.MKTP.CD SP.POP.TOTL SL.UEM.TOTL.ZS NV.AGR.TOTL.ZS NV.IND.TOTL.ZS NV.SRV.TOTL.ZS \
         SP.POP.0014.TO.ZS SP.POP.65UP.TO.ZS SL.TLF.ACTI.ZS; do
  curl -L -o "sources/wb/$I.json" \
    "https://api.worldbank.org/v2/country/FRA%3BDEU%3BITA%3BESP%3BBEL%3BNLD%3BLUX%3BCHE%3BGBR%3BAUT/indicator/$I?format=json&date=2015%3A2024&per_page=1000"
done
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
