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
├── geo/               europe.geojson — borders from Natural Earth
└── policy_defaults.json   starting tax rates and spending split
```

`policy_defaults.json` is shared by every nation rather than split per file, because only the player's nation has a budget at MVP — see [[economy-model]]. Like every other file here it is read once at startup, validated, and never mutated; `tools/import_data.py` neither reads nor writes it.

One file per entity, named by ISO 3166-1 alpha-3 where a nation is involved. Small files mean readable git diffs and no merge conflicts between unrelated content edits.

### Why JSON, not Godot `.tres` Resources

Godot's native Resource format is the engine-idiomatic choice and was seriously considered. JSON wins on three points that matter more here:

1. **Diffs.** `.tres` carries type metadata and generated IDs that churn on save. JSON diffs show what actually changed.
2. **Editability outside the engine.** Content can be edited, scripted, and bulk-generated — which is exactly what the import script does — without opening Godot.
3. **No engine lock-in on content.** If the simulation layer is ever ported, the content comes along unchanged.

The cost is losing the inspector's type checking. That is bought back by the validator described below, which is more thorough than the inspector anyway.

### Nation schema

As implemented at [[ROADMAP|S1]]. Fields owned by later sessions — leader (S2),
`voter_blocs` (S5), `system` (V1) — are added by the session whose model reads them,
not stubbed in ahead of time.

```json
{
  "id": "FRA",
  "name": "France",
  "geo_id": "FRA",
  "capital": "Paris",
  "playable": true,

  "government": {
    "term_years": 5,
    "assembly_seats": 577
  },

  "fiscal": {
    "_source": "authored",
    "_note": "General government, IMF/OECD estimates, rounded",
    "debt_to_gdp_pct": 116.0,
    "tax_revenue_pct_gdp": 46.1
  },

  "imported": {
    "_source": "worldbank",
    "_year": 2024,
    "_usd_eur": 0.92,
    "population": 68600000,
    "gdp_eur_bn": 2910.0,
    "unemployment_pct": 7.4,
    "sectors": {
      "agriculture": 0.015,
      "industry": 0.192,
      "services": 0.793
    }
  }
}
```

Three sectors, not four — no open dataset splits energy out of industry. If S4's
economy model wants an energy lever, it splits industry as a hand-tuned constant at
that point, against a concrete model rather than a placeholder.

`debt_to_gdp_pct` and `tax_revenue_pct_gdp` sit in their own `fiscal` object because
they are **authored, but real** — same class as `assembly_seats`, not the same class
as a party name. World Bank's central-government indicators are null or wrong-scope
for this purpose; see [[data-sources]] for the specifics. They do not refresh on
re-import.

### Unit conventions

| Kind | Convention | Example |
|---|---|---|
| Money | suffix `_eur_bn`, float, EUR billions | `gdp_eur_bn: 2910.0` |
| Population | bare integer, persons | `population: 68600000` |
| Rate | suffix `_pct`, range 0–100 | `unemployment_pct: 7.4` |
| Share | no suffix, range 0–1, group sums to 1.0 | `services: 0.793` |

Everything is EUR, including nations that don't use it. The MVP has one playable
nation and one budget; a `currency` field has no reader until V1.3 trade, if ever.

### The re-import safety rule

> [!important] The import script writes exactly one thing
> `tools/import_data.py` replaces the top-level `imported` object wholesale on every
> run. Every other key in the file — including `fiscal`, which is also real-world
> data — is hand-authored and the script never reads or writes it. It also never
> creates a nation file: if `data/nations/<ID>.json` doesn't exist, the script errors
> rather than inventing one.

A dedicated top-level key the script owns entirely is a structural boundary, not just
a marker to grep for. The validator enforces the other direction — no key inside
`imported` outside the known list — so an authored value can't drift into the block
that gets overwritten.

Raw datasets live in `sources/`, which is **gitignored** — so a `sources/README.md` could never be committed there. Download instructions live in [[data-sources]] instead. Shapefiles and multi-megabyte CSVs never enter the repository and never ship.

Full source and licence detail: [[data-sources]].

### Validation

Validation lives in `src/core/` (`nation.gd`, `data_loader.gd`), not in `tools/` —
`tools/` is not shipped, and validation must run every time the game starts, not just
at import time. It checks:

- Required fields present, correct type.
- Numeric fields within sane ranges — no negative populations, no debt ratios of 40,000.
- Referential integrity — every `geo_id` resolves to a feature in `europe.geojson`, every party's nation exists (V1: every `system` names a real political system template).
- Domain invariants — party seat shares per nation sum to 100%, sector shares sum to 1.0.

It runs unconditionally at startup and fails loudly with the offending file and field. This is the cheapest bug-catching in the project: content errors are the most common kind of error in a data-driven game, and they are trivially detectable.

## Live state

### Shape

A single `GameState` object holding plain data, built at new-game time by copying starting values out of the static data. Built in [[ROADMAP|S4]], the first session that had anything to mutate.

```
GameState                        src/core/game_state.gd
├── save_version
├── year, month                  mirrored from the Clock each monthly tick
├── player_nation_id
├── nations{}                    String id -> NationState
├── history[]                    dated monthly snapshots, for charts
└── errors[]                     problems found while building the state

NationState                      src/core/nation_state.gd
├── economy    sector_output{}, gdp, potential_gdp, trend, growth,
│              unemployment, structural_unemployment, population
├── policy     has_budget, tax_rates_pct{}, spending_pct_gdp{}, the starting
│              values of both, other_spending_pct_gdp, other_revenue_pct_gdp
├── fiscal     revenue_pct_gdp{}, totals, debt_service, deficit, debt_eur_bn
└── impulses   demand_impulse, potential_shift, external_impulse, trade_baseline
```

Later sessions add their own fields the same way the nation schema is grown — S5 opinion, S6 election state. The clock stays authoritative for the date; folding it in is S9's call, when save/load needs one place to read it from.

`NationState.duplicate_state()` and `GameState.duplicate_state()` deep-copy the whole thing. That is not a convenience: the budget projection runs the real simulation forward on a copy, which is what makes the projected path identical to what subsequently happens rather than merely close. Every Dictionary field must be duplicated, not shared.

Systems in `src/sim/` read and write `GameState`. Nothing else does. The UI reads it and never writes it — player intent goes back as explicit commands, of which `Budget.commit()` is the first. This is the one-way dependency rule from [[engine-decision]].

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
