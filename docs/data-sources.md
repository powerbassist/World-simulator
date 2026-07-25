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
- **Used for:** The 2D Europe map. We take 1:50m — enough detail that Belgium and Luxembourg read correctly, small enough that the whole of Europe is a manageable GeoJSON.
- **Note:** Sub-national regions are imported now but decorative at MVP. They exist so regional autonomy in [[v1]] doesn't require a second import pass.

### World Bank Open Data — economic seed values

- **License:** CC BY 4.0. Attribution required.
- **Provides:** GDP, GDP per capita, population, unemployment rate, general government debt as % of GDP, tax revenue as % of GDP, trade balance, inflation.
- **Used for:** Starting statistics for every nation in scope, **rounded**. France starts at roughly €2.9T GDP and roughly 110% debt-to-GDP, not at four decimal places. The simulation cannot justify precision the model doesn't have, and round numbers are far easier to reason about when balancing.

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

## Re-import safety

Fields in `data/nations/*.json` are tagged by origin so a re-import never overwrites hand-written content. The mechanism is specified in [[data-architecture]]. The short version: dataset-derived fields and authored fields live in separate objects within the same file, and the import script only ever writes the former.

---

Related: [[index]] · [[data-architecture]] · [[fictionalization]] · [[scope]]
