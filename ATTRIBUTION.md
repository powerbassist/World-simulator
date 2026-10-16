# Attribution

## World Bank

Nation economic statistics sourced from the World Bank Open Data catalog (https://data.worldbank.org/), used under the World Bank's Terms of Use for datasets (CC BY 4.0).

## Our World in Data

Per-nation figures the World Bank publishes for no year at all (Serbian, Montenegrin and Kosovan CO2 per capita, Albanian renewable electricity share, Kosovan electricity consumption per head) are read from Our World in Data's CO2 and energy datasets (https://github.com/owid/co2-data, https://github.com/owid/energy-data), used under CC BY 4.0. Hannah Ritchie, Pablo Rosado and Max Roser, Our World in Data.

## Natural Earth

Border geometry sourced from Natural Earth (https://www.naturalearthdata.com/), public domain -- admin-0 for the nations and outlines, and since V4.11a2 admin-1 (1:10m) for the regions of Ukraine, Belarus, Bosnia and Herzegovina, Moldova and Kosovo.

## NASA Blue Marble

Satellite map imagery from NASA's Earth Observatory — Blue Marble: Next Generation, topography and bathymetry, December 2004 (https://visibleearth.nasa.gov/collection/1484/blue-marble). Public domain.

Committed at `assets/map/blue_marble_5400x2700.jpg`. NASA imagery requires no attribution; credited anyway, so the source of the one large binary in the repo is recoverable without archaeology.

## @icons

Interface icons from the @icons addon — icons by Voxy (Valentin Fossati), in-editor picker by SuperDuperSword and Voxy. MIT License; the full text is committed at `addons/at-icons/LICENSE.txt`.

Only the icon files the game actually references are committed, so this credit covers a subset of the pack rather than all of it. Listed here from the moment the first one ships, not at ship time — an attribution obligation you remember late is one you have already breached, the same rule [docs/data-sources.md](docs/data-sources.md) states for the datasets.

## MapCamera2D

Map camera panning, zooming and dragging from MapCamera2D by Julian Vos, MIT License. Vendored as a single file at `src/ui/vendor/MapCamera2D.gd`; the licence text is beside it.

It arrived from the Asset Library as a loose `MapCamera2D.gd` plus a bare `LICENSE` in the project root. The licence was renamed and moved with the file it covers, because a root `LICENSE` file states the licence of *this* project — which is not MIT and is not Julian Vos's.

## Eurostat and GISCO

Regional population by NUTS region from Eurostat (`demo_r_pjangrp3`,
https://ec.europa.eu/eurostat) and NUTS 2021 region geometry from GISCO
(https://ec.europa.eu/eurostat/web/gisco), used under Eurostat's re-use policy —
equivalent to CC BY 4.0, attribution required.

Generated into `data/regions/*.json` and `data/geo/regions.geojson` at V2.2a, and
credited here in the same commit as the fetch rather than at ship time.

V4.11: the energy-dependency table (`nrg_ind_id`) supplies Kosovo's and Iceland's import
dependency, under the same policy.

## Official regional statistics (V4.11a2)

Regional population shares for Ukraine (State Statistics Service of Ukraine, 2022
estimates), Belarus (Belstat, 1 January 2024) and Bosnia and Herzegovina (2013 census,
entity totals); Ukrainian unemployment from the National Bank of Ukraine's Inflation
Report (October 2024); Kosovan labour figures from the Kosovo Agency of Statistics
Labour Force Survey 2024. Official statistics, cited in `tools/import_data.py` and
`docs/data-sources.md`.

## GeoNames

City names, populations and coordinates from the GeoNames geographical database
(https://www.geonames.org), `cities15000`, licensed CC BY 4.0.

Cities are filed under the NUTS region whose polygon contains them, so the
attribution covers a derived subset — 1 065 places of the file's holdings for the
ten nations in scope — rather than the database.

## Juggernaut X (portrait generation)

The committed portraits under `assets/portraits/` are AI-generated images
produced locally with RunDiffusion's Juggernaut X (Hyper variant, CivitAI,
https://civitai.com/models/133005/juggernaut-xl), then duotoned by this repo's
own `tools/portraits.gd`. The model's licence permits use with credit; this is
the credit. Every face is fictional — the roster is invented, and the prompts
describe archetypes rather than naming any real person.

The generation recipe (`tools/portraits_generate.py` +
`tools/portraits_workflow.json`) depends on the local ComfyUI install that ran
it; the committed PNGs are the shipped artefact, and the recipe is how person
seventy-two gets a portrait, not a claim the bytes are reproducible on another
machine.
