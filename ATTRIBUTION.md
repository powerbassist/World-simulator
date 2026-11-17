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

## Material Symbols

Interface and window icons from Material Symbols (Rounded, filled) by Google, Apache License 2.0 -- the licence text is committed at `LICENSES/Apache-2.0.txt`. Unmodified SVGs from https://github.com/google/material-design-icons, committed under `assets/icons/material/`; only the glyphs the game draws are included.


## MapCamera2D

Map camera panning, zooming and dragging from MapCamera2D by Julian Vos, MIT License. Vendored as a single file at `src/ui/vendor/MapCamera2D.gd`; the licence text is beside it.

It arrived from the Asset Library as a loose `MapCamera2D.gd` plus a bare `LICENSE` in the project root. The licence was renamed and moved with the file it covers, because a root `LICENSE` file states the licence of *this* project — which is not MIT and is not Julian Vos's.

## Office for National Statistics

Britain's regional GDP and unemployment (V5.3): regional GDP at current market prices for 2024 (Table 5 of "Regional gross domestic product: all International Territorial Level regions", published 23 September 2026) and the Labour Force Survey unemployment rate, 16 and over, seasonally adjusted, June to August 2026 (HI00 "Headline Labour Force Survey indicators for all regions", with the UK rate from A01), from the Office for National Statistics, https://www.ons.gov.uk. Contains public sector information licensed under the Open Government Licence v3.0; the licence text is committed at `LICENSES/OGL-UK-3.0.txt`. The figures sit in `tools/gbr_ons_itl1.json` and are generated into `data/regions/GBR.json` by `tools/import_data.py`. GDP stands in for GVA because ONS publishes no GVA per head at ITL1.

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

## World production and the outline register (V4.11b)

Raw-material and agricultural endowments in `data/commodities/endowments.json`:
mine production from the U.S. Geological Survey, *Mineral Commodity Summaries 2025*
(public domain), read through Our World in Data's minerals indicators (CC BY 4.0);
coal, oil and gas production from Our World in Data's energy dataset (CC BY 4.0);
crops, livestock and roundwood from FAOSTAT (Food and Agriculture Organization of
the United Nations, datasets QCL and FO, accessed 2026-10-16, CC BY 4.0 under FAO's
2025 open-data policy and its statistical-database terms of use); fish and seafood (capture and aquaculture) from the World Bank / FAO via
Our World in Data (CC BY 4.0); uranium shares authored from the World Nuclear
Association's 2024 mine-production figures (world-nuclear.org), cited as public facts.
Outline GDP in `data/world/outlines.json` from World Bank Open Data (CC BY 4.0), Taiwan's
from its Directorate-General of Budget, Accounting and Statistics; outline names from
Natural Earth (public domain).


## Spending sectors (V5.3 a)

The shares and start quantities in `data/domains/*.json`, read on 2026-11-01; each row's `source` line gives the table, the year and the address. The yearly need rates in the same files, read on 2026-11-02, come from Eurostat's EUROPOP2023 projections (`proj_23np`) and the Office for National Statistics' *National population projections: 2024-based*, under the Open Government Licence v3.0; each row's `need_source` line says which.

- Eurostat: `gov_10a_exp` (COFOG), `hlth_rs_bds1`, `educ_uoe_perp04`, `educ_uoe_grad01`, `educ_uoe_grad02`, `educ_uoe_fine01`, `isoc_cbt`, `ilc_pnp3`, `spr_exp_pens`, `ert_bil_eur_a`, under Eurostat's re-use policy (Commission Decision 2011/833/EU): re-use is allowed with acknowledgement of the source and a note of any change. Values were recomputed into shares; Eurostat is not responsible for the result.
- HM Treasury, *Public Expenditure Statistical Analyses 2026*, table 5.2 (2024-25 outturn); DWP, *Benefit expenditure and caseload tables 2026* (Great Britain, not the UK); NHS England KH03 bed availability; ONS mid-2025 population estimates. Open Government Licence v3.0, contains public sector information.
- NATO, *Defence Expenditure of NATO Countries (2014-2025)*, tables 8a and 8b, 2024 estimates. NATO's guidelines for the external use of its content require credit to NATO and bar sale or advertising use; the project's data licence is non-commercial.
- OECD (OECD Data Explorer): hospital beds, waiting times and students per teaching staff for the United Kingdom and Poland, credited to the OECD. The OECD's terms for statistical data were not confirmed; the licence for these tables is a standing question in the pull request.
- Germany's Grundsicherung figure comes from a Deutscher Landkreistag circular of 13 May 2025 reproducing the Federal Ministry of Labour and Social Affairs table; Poland's minimum-pension top-up is ZUS's answer to Wyborcza.biz, as reported by Super Biznes on 16 May 2025. Both are single published figures, marked as estimate and press source in their rows.

## Construction register, France (V5.3 c')

`data/units/stock/FRA.json`: lycee enrolment (datasets `fr-en-lycee_gt-effectifs-niveau-sexe-lv`, `fr-en-lycee_pro-effectifs-niveau-sexe-lv`; last observation 1 October 2025, rentree 2024 rows read) and teacher full-time equivalents (`fr-en-indicateurs_personnels_etablissements2d`; last observation 30 November 2025), from the Ministere de l'Education nationale open data portal (https://data.education.gouv.fr), and the number of health establishments 2021 from DREES, Base ARES, file published 6 February 2023 (https://data.drees.solidarites-sante.gouv.fr), both under the Licence Ouverte 2.0 (Etalab). The figures were changed by the project: summed per region, divided into ratios. Hospital beds (`hlth_rs_bdsrg2`) and population (`demo_r_d2jan`), (c) European Union, 1995-2026, Eurostat, under its re-use policy, were also changed: NUTS 2 regions summed to the game's regions and rates derived. Read 2026-11-17; `tools/units_stock_fr.py --check` re-reads them.

## Construction register, Germany (V5.3 c')

`data/units/stock/DEU.json`: full-time upper-secondary pupils and teachers in full-time equivalents by Land, school year 2024/25, from the Kultusministerkonferenz, Dokumentation Nr. 248 (April 2026), Tabellenteil Z, tables Z1.2 and Z3.2 (https://www.kmk.org/fileadmin/Dateien/pdf/Statistik/Dokumentationen/SKL_Teil_Z_Zusammenfassung_2024.xlsx; the document states no terms of use, so the figures are cited as facts, which is an open question); the number of schools by Land from the Statistisches Bundesamt (Destatis), Statistischer Bericht 21111 "Allgemeinbildende Schulen" and 21121 "Berufliche Schulen", 2024/25 (https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Bildung-Forschung-Kultur/Schulen/_inhalt.html); hospitals, set-up beds and beds per 100 000 inhabitants by Land, 2025, from the Destatis Statistischer Bericht "Grunddaten der Krankenhaeuser - Bundeslaender", tables 23111-b02 and 23111-b14 (https://www.destatis.de/DE/Themen/Gesellschaft-Umwelt/Gesundheit/Krankenhauser/Publikationen/_publikationen-innen-grunddaten-krankenhaus.html). Destatis's imprint: "(c) Statistisches Bundesamt (Destatis), 2026. Vervielfaeltigung und Verbreitung, auch auszugsweise, mit Quellenangabe gestattet" (reproduction and distribution, also in part, permitted with a credit to the source); the GENESIS-Online licence Datenlizenz Deutschland - Namensnennung 2.0 is not claimed, as these are the report files. The figures were changed by the project: rows summed per Land, ratios derived. Read 2026-11-17; `tools/units_stock_de.py --check` re-reads them.

## Construction register, Great Britain and Northern Ireland (V5.3 c')

`data/units/stock/GBR.json`, all under the Open Government Licence v3.0, source credit Crown copyright and the publishers below, figures changed by the project (summed per region, ratios derived; England's trusts placed in regions by their registered postcode through the NHS ODS API and postcodes.io, ONS data): Department for Education, School workforce in England, reporting year 2025 (https://explore-education-statistics.service.gov.uk/find-statistics/school-workforce-in-england/2025); Scottish Government, Pupil and teacher characteristics 2025 (https://www.gov.scot/publications/pupil-and-teacher-characteristics-2025/); Welsh Government, Schools' census results: January 2026 (https://www.gov.wales/schools-census-results-january-2026-html) and NHS beds: April 2023 to March 2024 (https://www.gov.wales/nhs-beds-april-2023-march-2024-html); Department of Education and NISRA, Annual enrolments at schools 2025/26 and Teacher workforce statistics bulletin 2025/26 (https://datavis.nisra.gov.uk/DEstatistics/); NHS England, Bed Availability and Occupancy Data - Overnight, KH03 Q4 2024-25 (https://www.england.nhs.uk/statistics/statistical-work-areas/bed-availability-and-occupancy/bed-data-overnight/); Public Health Scotland, Annual NHS beds information (https://www.opendata.nhs.scot/dataset/annual-hospital-beds-information); Department of Health (Northern Ireland), Hospital statistics: inpatient and day case activity 2024/25 (https://www.health-ni.gov.uk/publications/hospital-statistics-inpatient-and-day-case-activity-202425); Office for National Statistics, mid-2024 population estimates through Nomis, and the ONS Postcode Directory through postcodes.io (Contains OS data (c) Crown copyright and database right 2026; Contains Royal Mail data (c) Royal Mail copyright and database right 2026; Source: Office for National Statistics licensed under the Open Government Licence v3.0). Read 2026-11-17; `tools/units_stock_gb.py --check` re-reads them.
