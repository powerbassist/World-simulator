# Roadmap

Build order for Nation Simulator. Short, scoped sessions — **one clear objective each**, git commit at every session boundary.

Sessions are ordered so the **MVP loop closes at S6**, roughly halfway through the MVP work, not at the end. Everything after S6 deepens a game that already plays.

Scope reference: [docs/scope.md](docs/scope.md) · [docs/tiers/mvp.md](docs/tiers/mvp.md)
Stack reference: [docs/engine-decision.md](docs/engine-decision.md) · [docs/data-architecture.md](docs/data-architecture.md)

---

## MVP

### S0 — Project skeleton

**Goal:** A Godot project that opens, runs, and is under version control.

**Scope:** Install Godot 4.x. Create the project. Lay out the folder structure from [docs/engine-decision.md](docs/engine-decision.md#rule-3--one-system-one-module-one-clear-job): `data/`, `src/core/`, `src/sim/`, `src/ui/`, `tools/`, `tests/`. Add `.gitignore` covering Godot artefacts and the raw `sources/` dataset directory. `git init`, first commit. Add `ATTRIBUTION.md` with the World Bank credit line.

**Done when:**
- `godot` opens the project with no errors and an empty main scene runs.
- `git log` shows one commit and `git status` is clean.
- `.gitignore` excludes `.godot/`, `sources/`, and export artefacts.

`chore: project skeleton`

---

### S1 — Nation data: schema, import, load

**Goal:** Ten real nations exist as hand-editable JSON, generated from open data, and the game can load them.

**Scope:** Define the nation schema per [docs/data-architecture.md](docs/data-architecture.md). Write `tools/import_data.py`: reads Natural Earth borders and World Bank indicators from `sources/`, emits `data/nations/*.json` (rounded values) and `data/geo/europe.geojson`. Write the GDScript loader in `src/core/` that parses the JSON into typed objects. Write the validator that checks required fields, types, and ranges.

Nations: France, Germany, Italy, Spain, Belgium, Netherlands, Luxembourg, Switzerland, United Kingdom, Austria.

**Done when:**
- Running the import regenerates every file in `data/nations/` and `data/geo/` from `sources/`, reproducibly.
- The game loads all ten nations at startup and prints a summary line per nation — name, population, GDP, debt ratio.
- The validator rejects a deliberately corrupted nation file with a message naming the field.
- Spot-check: France's GDP and debt ratio are within 5% of the real figure.

`feat: nation data schema, import script, loader`

---

### S2 — Fictional political content

**Goal:** Every nation has a leader and a party system, all invented.

**Scope:** Hand-author `data/parties/*.json` and leader entries per [docs/fictionalization.md](docs/fictionalization.md). Four to six parties per nation, each with an ideology slot and a starting seat share. One head of government per nation. Build the banned-names list and the grep check as a script in `tools/`.

**Done when:**
- All ten nations have a named leader and at least four parties.
- Seat shares per nation sum to 100%.
- `tools/check_names.sh` (or equivalent) greps the whole repo against the banned-names list and returns zero hits.
- Loader parses parties and leaders without schema errors.

`feat: fictional leaders and party systems`

---

### S3 — Time

**Goal:** The clock runs, and you can control it.

**Scope:** `src/core/clock.gd` — a daily tick with pause and three speeds. A monthly signal that simulation systems will subscribe to. Minimal HUD showing the current date and speed state. Keyboard controls: space to pause, 1/2/3 for speed.

**Done when:**
- Starting the game advances the date visibly.
- Space pauses and unpauses; the date stops and resumes.
- Each speed setting is measurably faster than the last.
- A `month_elapsed` signal fires exactly twelve times per simulated year, verified in a headless test.

`feat: game clock with pause and speed control`

---

### S4 — Economy and budget

**Goal:** Money comes in, money goes out, and the numbers move month to month.

**Scope:** `src/sim/economy.gd` — four aggregate sectors, GDP, growth, unemployment, updated monthly. `src/sim/budget.gd` — three tax levers, six spending lines, deficit, accumulated debt, debt service. Budget screen in `src/ui/` showing current allocations, projected effect of a change before committing, and the resulting balance.

**Done when:**
- Raising income tax increases revenue and reduces growth over the following months.
- Spending beyond revenue accumulates debt, and debt service appears as a growing spending line.
- The projection shown before committing a budget change matches what actually happens.
- A headless ten-year run produces no `NaN`, no negative population, and no value diverging to infinity.

`feat: economy model and national budget`

---

### S5 — Public opinion

**Goal:** The population notices what you do.

**Scope:** `src/sim/opinion.gd` — six voter blocs with size, approval, and issue priorities. Issue salience. Overall approval as a weighted roll-up. Opinion inertia so nothing swings on a single month. Polling panel showing approval by bloc, with noise applied to the displayed figures.

**Done when:**
- Cutting pension spending drops pensioner approval within three months and barely moves student approval.
- Rising unemployment drops worker approval without any direct player action.
- Overall approval is a defensible weighted function of bloc approval and bloc size.
- Displayed poll numbers differ from true values by a bounded, random amount that changes between polls.

`feat: voter blocs and approval model`

---

### S6 — Elections — **the loop closes**

**Goal:** The game is playable end to end and you can lose it.

**Scope:** `src/sim/elections.gd` — five-year term timer, vote share computed from bloc approval, bloc size, turnout weighting and party ideology positions. Seat allocation to the assembly. Win/lose resolution and an end-of-term summary screen showing what happened to the key numbers over the term.

**Done when:**
- A full five-year term is playable from start to result without a crash.
- Governing badly — ignoring the budget, letting unemployment rise — loses the election.
- Governing well wins it, and the game continues into a second term.
- The result screen attributes the outcome to specific numbers, so the player can tell *why* they lost.

`feat: elections, seat allocation, win/lose condition`

> [!important] Checkpoint
> After S6 the game is playable. Play it for an hour before starting S7. If the loop is not interesting, the fix belongs in S4–S6, not in more features.

---

### S7 — Laws

**Goal:** The assembly is an obstacle, not a rubber stamp.

**Scope:** `data/laws/*.json` — law templates with preconditions, effects, and per-ideology-slot support. `src/sim/legislature.gd` — proposal, vote resolution by party seat share and ideology alignment, effect application on passage. Law screen listing available laws, their projected effects, and a vote forecast.

**Done when:**
- At least fifteen law templates exist as data, spanning tax, labour, social and institutional themes.
- Proposing a law produces a vote whose outcome follows from assembly composition.
- A law the assembly opposes fails, and the game says which parties voted against.
- Passing a law changes at least one economic and one opinion number over the following months.
- Adding a sixteenth law requires editing only `data/laws/`.

`feat: data-driven laws and assembly votes`

---

### S8 — Map

**Goal:** The game looks like a game about Europe.

**Scope:** Render `data/geo/europe.geojson` as a 2D political map. Nation colouring, hover highlight, click to select. Nation info panel showing the selected nation's statistics. Camera pan and zoom.

**Done when:**
- All ten nations render with recognisable borders.
- Clicking a nation opens its panel with live simulation values, not static data.
- Pan and zoom work at a usable frame rate.

`feat: 2D europe map and nation panel`

---

### S9 — Save and load

**Goal:** A game in progress survives being closed.

**Scope:** Serialise live state to JSON per [docs/data-architecture.md](docs/data-architecture.md). `save_version` field from the first save written. Save, load, and a slot list in the UI.

**Done when:**
- Saving mid-term, quitting, and reloading produces byte-identical simulation state.
- A save file opened in a text editor is readable and its fields are recognisable.
- Loading a save with an unknown `save_version` fails with a clear message rather than corrupting state.

`feat: save and load`

---

### S10 — Balance and polish

**Goal:** The MVP meets its done-when criteria.

**Scope:** Tune the economic and opinion constants until a ten-year playthrough behaves. Fix whatever the checkpoint playtest surfaced. Work through the [docs/tiers/mvp.md](docs/tiers/mvp.md) done-when checklist item by item.

**Done when:**
- Every box in the MVP done-when checklist is ticked, with evidence.
- Two consecutive full terms play without a softlock, a runaway value, or a pinned-at-zero value.
- Losing feels attributable, not random.

`chore: MVP balance pass`

---

## V1 — after the MVP ships

Deliberately coarse. These are not broken into sessions until the MVP is done, because the shape of each depends on what the MVP actually turns out to need. Full detail in [docs/tiers/v1.md](docs/tiers/v1.md).

| Block | Rough content |
|---|---|
| **V1.1 Political depth** | Coalitions, party discipline, confidence votes, dissolution, cabinet, upper house, judiciary, referendums |
| **V1.2 Political systems** | System templates as data, constitutional amendment, monarchy ↔ republic transitions, additional playable nations |
| **V1.3 Diplomacy and trade** | Relations, diplomatic actions, trade agreements, tariffs, sanctions, EU-shaped bloc, nation AI foreign policy |
| **V1.4 Companies** | Named fictional firms, subsidies, regulation, nationalisation, privatisation, bond markets |
| **V1.5 Society** | Media, scandals, unions, strikes, protests, corruption, demographics, migration, inequality |
| **V1.6 Economic depth** | Inflation, business cycle, tax brackets, sectoral investment, infrastructure |
| **V1.7 Campaigns** | Campaign phase, binding promises, electoral system choice |
| **V1.8 Events** | Data-defined events with preconditions, choices, consequences — last, on purpose |

Beyond V1: [docs/tiers/someday.md](docs/tiers/someday.md). Not scheduled.
