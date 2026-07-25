---
title: Data Architecture
tags:
  - decision
  - architecture
  - data
---

# Data Architecture

How content is stored, how a game in progress is stored, and why there is no database.

## The two kinds of data

The central split, and the reason this document exists:

| | Static / design-time | Live / runtime |
|---|---|---|
| **What** | Nation definitions, party definitions, law templates, political system templates, company definitions, map geometry | The current game: date, treasury, this term's approval, who holds which seats, which laws have passed |
| **Changes when** | A designer edits a file | Every simulated month |
| **Lives in** | `data/`, committed to git | Memory, serialised to a save file |
| **Format** | JSON, hand-editable | JSON save file |
| **Authority** | The repository | The player's save |

Static data is **read once at startup and never mutated**. When the simulation raises France's unemployment, it writes to live state; France's data file still says what unemployment was at game start. This is what makes a save reloadable and a data edit safe.

## Static data

### Layout

```
data/
├── nations/           one file per nation — FRA.json, DEU.json, …
├── parties/           one file per nation's party system
├── laws/              law templates, grouped by theme
├── political-systems/ institutional templates (V1)
├── companies/         fictional firms (V1)
└── geo/               europe.geojson — borders from Natural Earth
```

One file per entity, named by ISO 3166-1 alpha-3 where a nation is involved. Small files mean readable git diffs and no merge conflicts between unrelated content edits.

### Why JSON, not Godot `.tres` Resources

Godot's native Resource format is the engine-idiomatic choice and was seriously considered. JSON wins on three points that matter more here:

1. **Diffs.** `.tres` carries type metadata and generated IDs that churn on save. JSON diffs show what actually changed.
2. **Editability outside the engine.** Content can be edited, scripted, and bulk-generated — which is exactly what the import script does — without opening Godot.
3. **No engine lock-in on content.** If the simulation layer is ever ported, the content comes along unchanged.

The cost is losing the inspector's type checking. That is bought back by the validator described below, which is more thorough than the inspector anyway.

### Nation schema

```json
{
  "id": "FRA",
  "name": "France",
  "geo_id": "FRA",
  "playable": true,
  "capital": "Paris",
  "stats": {
    "_source": "worldbank",
    "population": 68000000,
    "gdp_eur": 2900000000000,
    "gdp_per_capita_eur": 42600,
    "unemployment_pct": 7.5,
    "debt_to_gdp_pct": 110,
    "tax_revenue_pct_gdp": 46,
    "inflation_pct": 2.1
  },
  "sectors": {
    "agriculture": 0.02,
    "industry": 0.17,
    "services": 0.71,
    "energy": 0.10
  },
  "government": {
    "system": "presidential-republic",
    "leader": "Daniel Moucron",
    "term_years": 5,
    "assembly_seats": 577
  },
  "voter_blocs": [
    { "id": "workers",    "share": 0.30, "priorities": ["unemployment", "wages"] },
    { "id": "business",   "share": 0.10, "priorities": ["corporate_tax", "growth"] },
    { "id": "pensioners", "share": 0.22, "priorities": ["pensions", "health"] }
  ]
}
```

### The re-import safety rule

> [!important] The import script writes exactly one thing
> `tools/import_data.py` may write the `stats` object and nothing else. Every other field is hand-authored and the script never touches it.

The `"_source"` marker inside `stats` makes the boundary explicit and greppable. A re-import a year from now, to refresh economic figures, updates the numbers and leaves every invented name, party, and tuning value intact.

Raw datasets live in `sources/`, which is **gitignored**. A `sources/README.md` records where each file came from and how to re-download it. Shapefiles and multi-megabyte CSVs never enter the repository and never ship.

Full source and licence detail: [[data-sources]].

### Validation

`tools/validate_data.gd` runs over `data/` and checks:

- Required fields present, correct type.
- Numeric fields within sane ranges — no negative populations, no debt ratios of 40,000.
- Referential integrity — every `system` names a real political system template, every party's nation exists.
- Domain invariants — party seat shares per nation sum to 100%, sector shares sum to 1.0.

It runs at startup in debug builds and fails loudly with the offending file and field. This is the cheapest bug-catching in the project: content errors are the most common kind of error in a data-driven game, and they are trivially detectable.

## Live state

### Shape

A single `GameState` object holding plain data, built at new-game time by copying starting values out of the static data.

```
GameState
├── date, speed, paused
├── save_version
├── player_nation_id
├── nations[]            live per-nation values — economy, budget, opinion
├── assembly             current seat distribution
├── passed_laws[]
├── election             term start, term length, next election date
└── history[]            monthly snapshots of key figures, for charts
```

Systems in `src/sim/` read and write `GameState`. Nothing else does. The UI reads it and never writes it — player intent goes back as explicit commands. This is the one-way dependency rule from [[engine-decision]].

### Persistence

Live state is serialised to a JSON save file. The whole `GameState` object, written in one go, read in one go.

**`save_version` is written from the very first save.** It costs one line now. Retrofitting it after there are saves in the wild means guessing at a format from its contents. On load: matching version proceeds, older version runs a migration if one exists, unknown or newer version fails with a clear message rather than half-loading.

Saves are JSON rather than binary, deliberately. A save you can open in a text editor is a save you can debug, and during development that is worth far more than file size or load speed. The switch to a binary format is a two-line change if a save ever gets large or slow enough to matter — measured, not assumed.

## Why there is no database

No SQLite. No embedded key-value store. Nothing beyond files.

This is not "keep it simple" as a slogan. The concrete case:

**Scale.** The MVP is ten nations, roughly sixty parties, fifteen law templates, and sixty voter blocs. Say a few hundred entities carrying a few thousand numbers — well under a megabyte in memory. At the outer [[someday]] scale of all ~195 nations with regional breakdown, it is a few thousand entities and single-digit megabytes. Entirely resident, comfortably.

**Query shape.** Every lookup this game performs is either a direct key lookup ("give me France") or a scan over an array of ten to a few thousand items ("every nation with debt over 90%"). A dictionary handles the first. A `filter()` handles the second, in microseconds. There is no join, no index, no aggregation over a large table, no concurrent access. A query engine would have nothing to do.

**The actual cost.** A database imposes a schema. This game's schema changes constantly during development — every new mechanic adds fields to nations, laws, or state. With JSON, adding a field is adding a field. With a database, it is a migration, every time, forever. That directly attacks the property this architecture exists to protect: *content stays easy to add and tweak*.

**Single-player.** No concurrent writers, no transactions, no crash-consistency requirement beyond "write the save file atomically". The problems a database solves are not present.

### What would change the answer

Stated in advance, so the decision can be revisited on evidence rather than on feeling:

- A **profiled** load time or tick time where data access, not simulation arithmetic, is the bottleneck.
- A real need to query historical state across many simulated years without holding it all in memory — a deep analytics or replay feature.
- Save files large enough that full serialisation causes a visible stall, where incremental writes would fix it.

**Not** on that list: the entity count growing. More nations is more array elements, and the array was never the problem.

---

Related: [[index]] · [[engine-decision]] · [[data-sources]] · [[fictionalization]] · [[scope]]
