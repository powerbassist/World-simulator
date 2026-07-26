# Roadmap

Build order for Nation Simulator. Short, scoped sessions — **one clear objective each**, git commit at every session boundary.

Sessions are ordered so the **MVP loop closes at S6**, roughly halfway through the MVP work, not at the end. Everything after S6 deepens a game that already plays.

Scope reference: [docs/scope.md](docs/scope.md) · [docs/tiers/mvp.md](docs/tiers/mvp.md)
Stack reference: [docs/engine-decision.md](docs/engine-decision.md) · [docs/data-architecture.md](docs/data-architecture.md)

## Per-session: plan, model, effort

**Plan first** asks whether the session should be designed in plan mode before any code is written. The test is not size — it is **how expensive the decision is to reverse**. A schema or a simulation model that turns out wrong is rewritten along with everything that reads it. A map renderer that turns out wrong is rewritten alone.

**Model and effort** follow the same logic. Opus 5 at high effort is for open design judgement — deciding what the model *should be* when several plausible answers exist. Sonnet 5 at low or medium effort is for executing a decision that is already made, which is most sessions once the docs are written.

| Session | Plan first | Model | Effort | Why |
|---|---|---|---|---|
| S0 Skeleton | **No** | Sonnet 5 | Low | Mechanical. Folder layout already specified in [docs/engine-decision.md](docs/engine-decision.md). |
| S1 Nation data | **Yes** | Opus 5 to plan, Sonnet 5 to build | High → Medium | Schema design. Every later system reads it, so a bad shape costs in proportion to what has been built on top. The import script itself is routine. |
| S2 Fictional content | **No** | Sonnet 5 | Medium | Bulk authoring against rules already written in [docs/fictionalization.md](docs/fictionalization.md). Medium rather than low only because the banned-names constraint needs attention. |
| S3 Time | **No** | Sonnet 5 | Low | Small and fully specified. Tick, pause, three speeds, one signal. |
| S4 Economy + budget | **Yes** | Opus 5 | High | The highest-risk design in the MVP. Formulas, feedback loops and time constants decide whether the game is interesting. Worth the strongest model on both the plan and the build. |
| S5 Public opinion | **Yes** | Opus 5 | High | Same class as S4 and coupled to it. Bloc weighting and inertia are model decisions with no obviously right answer. |
| S6 Elections | **Light** | Opus 5 to plan, Sonnet 5 to build | Medium | Vote-share formula is a genuine design choice; seat allocation and the result screen are bookkeeping. |
| S7 Laws | **Yes** | Opus 5 to plan, Sonnet 5 to build | High → Medium | Law template schema is the same class as S1, and must accommodate V1 laws that do not exist yet without being over-general today. The fifteen templates are data entry, but the build also wires vote resolution and four effect channels into three existing tick formulas plus a third UI surface — corrected from High → Low during this session's plan; see the note below. |
| S8 Map | **No** | Sonnet 5 | Medium | Render GeoJSON, colour, hover, click. Mechanical, though projection and polygon winding have fiddly edges. |
| S9 Save/load | **No** | Sonnet 5 | Low | Already specified in [docs/data-architecture.md](docs/data-architecture.md). |
| S10 Balance | **No** | Opus 5 | Medium | No design decisions left, but diagnosing a runaway feedback loop is exactly the kind of reasoning worth the stronger model. |

Every V1 block gets a plan, on Opus 5. By then there is enough built that changes ripple.

> [!tip] These are starting points
> If a session marked Sonnet stalls — repeated failed attempts, a bug that will not localise — escalate to Opus rather than grinding. The cost of one wrong model choice is minutes; the cost of grinding is a session.

## Session handoff

Every session runs in a **fresh chat**. Context from building S3 is dead weight when starting S4, and a long session degrades before it ends.

That only works if the handoff is written down, so **the last thing every session does, after the commit, is output a copy-ready prompt for the next one.** Not a summary — a prompt, in a code block, ready to paste into a new chat with nothing to edit.

It must contain:

- Which session, and the instruction to do that one only.
- Which docs to read first.
- The plan / model / effort row from the table above, and the instruction to challenge it if it looks wrong.
- Anything the previous session learned that is **not** written in a doc or a commit — a gotcha, a rejected approach, a version pin. If it turns out to be load-bearing, it belongs in a doc instead, so write it there and link it.
- The instruction to verify against that session's done-when list before claiming done.

If the handoff prompt is hard to write because the session ended in a messy state, that is the signal — finish or revert the mess before writing it, not after.

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

**Scope:** `src/sim/economy.gd` — three aggregate sectors, GDP, growth, unemployment, updated monthly. `src/sim/budget.gd` — three tax levers, six spending lines, deficit, accumulated debt, debt service. Budget screen in `src/ui/` showing current allocations, projected effect of a change before committing, and the resulting balance.

> [!note] Three sectors, not the four this line originally said
> The fourth was energy, split out of industry. That was written before
> [docs/data-sources.md](docs/data-sources.md) established no open dataset
> provides the split, and no MVP mechanic distinguishes energy from industry —
> energy mix is [someday](docs/tiers/someday.md) tier. Corrected in S4 rather
> than honoured; the model is [docs/economy-model.md](docs/economy-model.md).

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

> [!note] Real, per-nation election timing and systems, not a five-year timer
> Added on instruction partway through S6's plan: each nation's term length,
> election date and electoral system are real and authored, not a single
> five-year timer, and European Parliament elections exist alongside national
> ones. This changed the row below — "light plan... seat allocation... is
> bookkeeping" assumed one term length and one allocation rule. Ten real
> systems plus the EP made the schedule-and-system shape an [[data-architecture|S1]]-class
> schema decision instead, since S7 laws, [[v1|V1.1]] coalitions and
> [[v1|V1.2]] political systems all read it. Full argument in
> [[electoral-systems]]; the vote-share model itself is [[election-model]].

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

> [!note] Two corrections made during this session's plan
> The effort row below originally read High → Low. Planning at High held; the
> build was corrected to **Medium** — it is not only the fifteen templates, it
> is vote resolution, four effect channels wired into three existing tick
> formulas, a third UI surface, and two new headless tests, the same class of
> work [[ROADMAP|S6]] got Medium for. Per-ideology-slot law support reads the
> same two-axis space [[election-model]] already put every party on, rather
> than inventing a second vocabulary — see [[legislature-model]]. And the vote
> forecast is deliberately **blurred**, not exact: a party inside a band wider
> than the real vote's own threshold shows as Undecided, a display-layer trick
> with no sim-side randomness, the same shape [[opinion-model|polling noise]]
> and [[election-model|no election-day noise]] both already argue for their
> own cases. Full argument in [[legislature-model]].

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

> [!note] V1.1 decomposed into six sub-projects during its plan
> The eight bullets above are not one session and not independent. Dependency
> order, which is **not** the order [[v1]] lists them in:
>
> | # | Sub-project | Depends on | State |
> |---|---|---|---|
> | **a** | Government formation, coalitions, censure, 49.3 | — | Session 1 **done**; session 2 (censure, 49.3) next |
> | **b** | Party discipline and rebellions | a | |
> | **c** | Dissolution and snap elections | a, b | |
> | **d** | Cabinet and ministers | a | |
> | **e** | Upper house and judiciary | — | Independent of a–d |
> | **f** | Referendums | — | Deferred toward V1.7, which brings campaigns |
>
> (a) went first because it is the schema decision — government representation
> and party data are read by b, c and d, and by the save format — the same
> argument S1, S6 and S7 got. Full model in [[government-model]].
>
> Two findings from planning (a) that are now written down rather than
> rediscovered: **the player's term was modelled as the Assembly's**, which made
> the first playable term 41 months instead of 16 and is corrected in
> [[electoral-systems]]; and **a France-honest formation model necessarily
> contains the motion de censure**, because there is no investiture vote in
> France, so (a) and half of (c) could not be separated.
| **V1.2 Political systems** | System templates as data, constitutional amendment, monarchy ↔ republic transitions, additional playable nations |
| **V1.3 Diplomacy and trade** | Relations, diplomatic actions, trade agreements, tariffs, sanctions, EU-shaped bloc, nation AI foreign policy |
| **V1.4 Companies** | Named fictional firms, subsidies, regulation, nationalisation, privatisation, bond markets |
| **V1.5 Society** | Media, scandals, unions, strikes, protests, corruption, demographics, migration, inequality |
| **V1.6 Economic depth** | Inflation, business cycle, tax brackets, sectoral investment, infrastructure |
| **V1.7 Campaigns** | Campaign phase, binding promises, electoral system choice |
| **V1.8 Events** | Data-defined events with preconditions, choices, consequences — last, on purpose |

Beyond V1: [docs/tiers/someday.md](docs/tiers/someday.md). Not scheduled.
