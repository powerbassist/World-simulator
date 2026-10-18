---
title: V5 Reflection
tags:
  - tier
  - reflection
---

# V5 Reflection — what V4 left, what the author asked for, what V5 should be

> [!note] Written 2026-10-18/19 by the V5 reflection session
> Brief: `.superpowers/sdd/v5-reflection-brief.md` (machine-local). Read off `main`
> at `ae427364` (PR #14 merged), the running game photographed windowed, the
> tree measured cold, and a long interview with the author, who added most of
> the asks below. [[v4]] is closed and nothing here relitigates it: where V4
> left something open, it is input to V5, not a complaint against V4. The tier
> draft this reflection feeds is [[v5]], **unsigned**.

Every claim that carries a number is tagged **measured** (run in this session,
the command or file named), **recorded** (measured by an earlier block, the
doc named), **inferred** (reasoned, not run), or **author** (said by the author
in the interview). An item with no evidence was dropped.

## 0. What the author asked for, and the calls taken in the interview

The brief named three seeds (an audit of the oldest code, the UI rework, a
real transport network). The interview grew the list; this table is the
author's words reduced to rows, with whose call each answer is.

| Ask | Call | Whose |
|---|---|---|
| Order of V5 | **Audit → people who talk → transport**; war, army and espionage are V6 | author, taking the session's swap of people before transport |
| A play gate | **Every V5 block ends with 30 minutes of the author playing; the felt verdict is a done-when** | author, on the session's proposal |
| UI reference | **Football Manager 2024** — not of the genre, loved | author |
| Shell | Map visible most of the time; a **left sidebar of domains** (Social, Government, Army…); a click opens a **tabbed window** (Social → Education, Health…); a close cross returns to the map; **no "Continue" button** — the real-time clock and its speeds stay | author |
| Dense tables | Their **precision depends on the quality of the service that produces them** | author |
| Graphic charter | **Changes too** — fonts, palette, the lot | author |
| Art | **Photorealistic**, with one shared grade so the library reads as one direction | author, on the session's recommendation (closes [[someday]]'s event-art call when ticked) |
| Language | **Language choice in the options** (EN/FR at least) | author |
| Sound | **Everything** — voices, music, effects. ElevenLabs **Starter** plan bought for the commercial licence | author |
| People | Audiences requested and **booked in the diary**; a scene as a **window over the map** (layout B, picked in the mockup); **branching** dialogue; **influence levers** once a topic is reached; then **other topics** (small talk, gossip, a dinner, flirting) | author |
| Knowing people | The president **does not know everyone equally**; unknown people react unpredictably, close friends are easier; **you learn people over time** | author |
| Social skill | Every person has one: it sets **how fast you read someone** and **whether you catch a lie** | author |
| Phone | **Informal calls** beside formal audiences | author |
| Corruption | **Dialogue choices can include corruption of every kind** | author |
| Affairs | A **secret, dangerous affair if the president is married** | author |
| The president | **The sitting leader by default**; may **create** one or **pick another person eligible** to be president of the played nation | author |
| Domain budgets | Each tab splits its envelope into **sectors with an allocation figure** (Education: primary, secondary, university, buildings, teacher training…) | author |
| Laws in a domain | A **general tile** for the whole domain and a **tile per sector** to enact or repeal; **binary** decisions (ban X) and **graded** ones (build N lycées — how many, at what estimated cost); **where** to build: one region, by hand, or spread | author |
| Likeness | **Keep the portraits**; nobody is excluded from affair or corruption content — "the final image has nothing to do with the original photo" | author, answering the builder check's question |
| Corruption pays in | **All four**: the leader's personal wealth (overturning [[people-model]] §14.7), party and campaign money, diverted budget, favours | author, answering the builder check's question |
| Regime | Under an authoritarian regime a law is **applied by decree**, otherwise it goes to the assembly; the president may **attempt** to tip France into authoritarianism **if approval is extremely high and other parameters allow** | author |
| Transport | At least **motorways / major roads, rail, the main freight ports and airports**; **build new infrastructure** (a TGV line); a line that **crosses a border needs an agreement**, the build cost **split by the share of the line in each country**, adjustable to persuade the other side | author |
| The Union | The EU **co-finances infrastructure and some sectors**; some laws or decisions can **put the nation outside EU law** | author |
| The city at depth | Zoomed in, a city shows **the firms and infrastructure around it** | author: **icons placed on the map**, not a separate screen; map icons **vector**, ElevenLabs raster art in the record a click opens (the session's recommendation, taken) |
| Relief and water | **Relief, rivers, lakes** integrated | author |
| Engine | **Move to the latest Godot** | author; the session's ruling: 4.7.2 (stable maintenance) in V5.0, 4.8 when it is stable (beta 1 on 2026-10-15) |
| War (V6) | Wars for resources, territory and more; **annexation**; the player **moves armies on the map** (Hearts of Iron, not Suzerain); **build or destroy military sites** (bases, naval bases, nuclear silos); **order equipment** from national firms, or foreign ones when allowed (arms embargo) — also when the national industry cannot supply | author |
| Intelligence (V6) | **Espionage**, and a per-nation **level of knowledge** of every other nation (France knows its allies well up to *secret défense*, knows little of North Korea unless it spies or hacks) | author |
| The world (later) | Today only Europe; later e.g. **China trying to invade Taiwan** | author |
| Resource deals (later) | **Deals with other countries about resources** | author |

Rulings the session took itself, each overturnable: the authoritarian
template and the coup attempt go to **V6** with the army (army loyalty is one of
the attempt's conditions and does not exist until then), while V5's law tiles
already carry the decree route as a read of the regime template; the art call
is recorded as the author's on the session's recommendation; the transport
data source is a **gate** of its block, not a call taken here. Six more
were settled after an independent builder read the tier draft cold; they are
listed in [[v5]] ("Rulings the builder check settled").

## 1. The cold count (2026-10-19, `main` at `ae427364`)

All **measured** in this session unless tagged.

- **Code:** 208 GDScript files in `src/` (vendor excluded), 69 674 lines. **73
  of them are over 300 lines** — but the house style is comment-heavy
  (`nation_state.gd` is 1 594 comment lines of 2 900), and counted in **code
  lines** (no comment, no blank) only **23 are over 300, 8 over 500, 3 over
  1 000**: `data_loader.gd` 1 806, `main.gd` 1 459, `nation_state.gd` 1 033.
  The five largest by total are the five oldest:
  `nation_state.gd` 2 900, `data_loader.gd` 2 739, `main.gd` 2 705,
  `map_view.gd` 1 705, `game_state.gd` 1 608 — all created 2026-07-25/26.
- **Reviewed code vs not:** the first commit that names a review is
  2026-09-01 (V2.6a). `git blame` over every line of `src/`: **40 604 of 69 674
  lines (58.3 %) were last touched before that date.** (Assumes the 2026-10-15
  history rewrite kept committer dates; the first commit still reads
  2026-07-25, so it did.)
- **Docs:** 35 603 lines in `docs/` — half the size of the code. `history.md`
  alone is 4 233.
- **Tests:** 121 test files; `bash tools/run_tests.sh` — **121 of 121 passed
  in 11:57**.
- **Content:** 120 laws (7 files), 102 events (9 files), **2 summit scenes**,
  2 147 person records, 277 regions, 640 road edges (623 land, 17 sea).
- **Surfaces:** 22 registered windows (`src/ui/main.gd:303-673`) behind four
  cluster buttons.
- **Art:** 1 595 people with a portrait (× 5 expressions); **552 without**:
  all **464 executives** and 88 politicians. 54 event plates. Scene backdrops
  are **432 × 632** (card-sized).
- **Localisation:** **zero** `tr()` calls in `src/`; no translation table.
- **The sim/UI boundary:** zero direct assignments into `ns.*` or `state.*`
  from `src/ui` (grep for `ns.x =` / `state.x =`; method calls not covered).

## List 1 — Load-bearing debts

Sizes are **inferred**: S = 1–2 sessions, M = 3–5, L = 6+.

### D1 — The save surface is written three times by hand

- **What.** `NationState` carries 217 fields and three parallel hand-written
  lists over them: `duplicate_state()` (`src/core/nation_state.gd:1767`),
  `to_dict()` (`:2048`), `from_dict()` (`:2285`). Every register is added in
  three places, and a slip is silent.
- **Evidence.** The aliasing sweep V4.6 left open is still open — `from_dict`
  ASSIGNS rather than rebuilds three registers: `sector_investment` (`:2548`),
  `projects` (`:2555`), `plants` (`:2582`), against the rule
  [[commodities-model]] §6 states ("`from_dict` must REBUILD every register,
  never assign"). **Measured.**
- **Cost if unpaid.** V5 adds registers by the dozen — knowledge, affinity,
  relationships, social skill, regional service quality, a construction
  catalogue, a real network, EU procedures. Each one triples the surface and
  multiplies the aliasing class.
- **Size.** M. One field table that drives all three functions, the three
  aliasing sites fixed, `tests/test_save_load.gd` extended to round-trip every
  field.

### D2 — `main.gd` is the shell, the card writer, the pause and half the game's wiring

- **What.** 2 705 lines, 68 preloads, 133 commits — the most-edited file in the
  project. It builds the shell, composes every card, holds the clock for
  decisions, opens summits, runs save/load, enforces the programme and draws
  the top bar.
- **Evidence.** `src/ui/main.gd` function list (`_card_*`, `_decision_holds_clock`,
  `_open_summit`, `_on_save_requested`, `_enforce_term_start_programme`,
  `_update_top_bar`). **Measured.**
- **Cost if unpaid.** The V5 shell (sidebar, domain windows, audiences, inbox)
  lands in this file or around it. Building a new UI on top of it means a
  third layer of wiring nobody can hold in one read.
- **Size.** L, but it is the UI rework's own work: dissolving it IS V5.1, not
  a separate refactor.

### D3 — `data_loader.gd` loads twenty-five content types in one file

- **What.** 2 739 lines, 53 functions: people, companies, regions, outlets,
  six action files, energy, commodities, outlines, programme, parties, laws,
  systems, scenarios, orgs, proposals, geo, events, summits — plus every
  cross-file validator.
- **Evidence.** `src/core/data_loader.gd` function list. **Measured.**
- **Cost if unpaid.** V5 adds at least six content types (domains/sectors, a
  construction catalogue, scene templates, string tables, the network, EU
  programmes). Each one grows the monolith.
- **Size.** M. A loader per content type, one orchestrator, validators kept
  beside their type.

### D4 — The month tick is over its band, and V5/V6 want more of it

- **What.** The month at 41 nations is above the 300 ms band V4.6's probe was
  set on, driven by Diplomacy's N².
- **Evidence.** **Recorded:** 218 → 392 ms at V4.11a, Diplomacy 70 → 159 and
  Economy 37 → 76 ([[someday]], "Carried from V4.11"; two known
  recomputations in Diplomacy named there). **Measured** this session
  (`tools/tick_budget_probe.gd`, 60 months, run alone): **446 ms mean**,
  Diplomacy 163 (37 % of the month, max 315), Economy 77, Migration 65,
  Commodities 47 — wall clock on one machine, so the ratios are the finding.
- **Cost if unpaid.** AI nations that use V5's construction verbs and laws
  add work per nation per month; V6's war wants movement between months; a
  global roster (author: "China could try to invade Taiwan") is
  (195/41)² ≈ ×23 on the diplomacy share alone (**inferred**, arithmetic).
- **Size.** M. Attribute first (the probe), then the two Diplomacy
  recomputations; a tiering of nations by distance from the action belongs to
  the block that grows the roster.

### D5 — 58 % of the code has never been reviewed

- **What.** The review loop started 2026-09-01. Most of the MVP, V1 and early
  V2 code never went through one.
- **Evidence.** §1's blame count, 40 604 of 69 674 lines. **Measured.** The
  author's own account: early code was pushed with no review and no method.
- **Cost if unpaid.** Defects of the class V4's reviews kept finding (aliasing,
  stale comments, dead branches) sit in the files every V5 block builds on.
- **Size.** M, with a fixed review budget and bar set before pass 1 (the V4.4
  lesson): hotspots first — size × churn × "a V5 block touches it".

### D6 — The size rule is written, not enforced

- **What.** AGENTS.md: "a file past a few hundred lines is doing two jobs —
  split it then". 73 of 208 files break it by total lines, 23 by code lines,
  and nothing fails.
- **Evidence.** §1. **Measured.** Counting total lines punishes the house
  style — the comments that explain *why* — rather than the second job the
  rule is about. And the three largest files are past what an agent reads in
  one call (2 000 lines), so every session that edits them works from a
  partial read.
- **Cost if unpaid.** The rule erodes one block at a time.
- **Size.** S. A ratchet check beside `check_names.sh`, in CI, on **code
  lines**: a new file stays under 300; an existing file over it may shrink,
  never grow; and no file of any kind passes 2 000 total lines. Splitting
  everything at once is refused: it would move nothing for the player and
  risk everything.

### D7 — Nothing in the game can be translated

- **What.** The author wants a language option. Every string is English,
  written inline in panels built in code and in `data/` text fields.
- **Evidence.** Zero `tr()` calls in `src/`. **Measured.** [[v4]] listed
  localisation under "deliberately does not open".
- **Cost if unpaid.** V5.2 writes thousands of dialogue lines. Writing them
  before the string pipeline exists means writing them twice.
- **Size.** M for the pipeline and the extraction; the French translation of
  existing content is its own content task.

### D8 — The project register cannot build a lycée in Hauts-de-France

- **What.** Five national programmes (rail, grid, freight corridor, fibre,
  flood defence), each a start/cancel pair with one site per nation, no
  quantity, no partial credit, no AI use.
- **Evidence.** `data/project-actions/projects.json` (10 actions);
  [[projects-model]] §15. **Measured.**
- **Cost if unpaid.** The author's construction verb (how many, how much,
  where, build or demolish), the TGV line of the transport block and V6's
  military sites all need one register this is not.
- **Size.** L — it is V5.3's centre.

### D9 — Service quality is national

- **What.** `Society` writes one `service_quality` per key per nation.
- **Evidence.** `src/sim/society.gd:51-55`. **Measured.**
- **Cost if unpaid.** A school built in one region cannot be felt there; the
  "where" of the author's construction verb would be decorative.
- **Size.** M, and a re-baseline.

### D10 — There is no authoritarian machinery

- **What.** Four templates, all democratic. Belarus runs on the
  semi-presidential one, and its own data says so: "the AI's behaviour, not a
  constitutional field, is what makes it autocratic" (`data/nations/BLR.json`,
  `head_of_state._note`).
- **Evidence.** `data/political-systems/` (4 files). **Measured.**
- **Cost if unpaid.** The decree route of the law tiles has nothing to read;
  V6's coup attempt has no target template.
- **Size.** S in V5 (the field the tiles read), M in V6 (the template, the
  attempt, the new lose conditions).

### D11 — Executives have no faces, and scenes are card-sized

- **What.** All 464 executives (and 88 politicians of the neighbours) draw
  the silhouette; backdrops are 432 × 632.
- **Evidence.** §1. **Measured.** The V4.3 claim "no person without art" was
  true of its bench; V4.7's executives came after it.
- **Cost if unpaid.** "The CEO of Aurignac wants to see you" — the author's
  own first example — arrives faceless.
- **Size.** M (generation is resumable: `tools/portraits_generate.py --only`).

### D12 — The AI nations' budgets and unrest never tick

- **What.** `Budget.tick_month` recomputes the player alone
  (`src/sim/budget.gd:48`); `Unrest.tick_month` skips every nation without
  `has_budget` (`src/sim/unrest.gd:120`).
- **Evidence.** **Measured** (both lines read); consequences in [[someday]]
  ("The AI nations' unrest and deficit registers never tick").
- **Cost if unpaid.** An AI nation cannot fund a construction programme, feel
  a strike, or meet the authoritarian attempt's conditions. Cross-border
  negotiation (V5.4) asks a partner to pay from a budget that never moves.
- **Size.** M, and a re-baseline.

### D13 — The commodity layer still does not reach GDP

- **What.** `value_added_eur_bn` is written (`src/sim/commodities.gd:400`)
  and read only by a map layer (`src/ui/map_layers.gd:637`);
  `PRICE_ELASTICITY` is unswept; world production does not grow.
- **Evidence.** [[commodities-model]] §5 ("built but unwired"); [[someday]].
  **Measured** (readers grepped) and **recorded**.
- **Cost if unpaid.** The author's resource deals would move goods that move
  nothing. Not a V5 debt — listed so no V5 block builds on it by accident.
- **Size.** L, owned by whichever tier opens resource deals.

### D14 — The budget panel's forecast costs seconds

- **What.** `Budget.project()` ticks every nation's events per projected month;
  the panel's refresh is ~4.5 s.
- **Evidence.** **Recorded**: 362 ms for 24 months × 29 nations, two passes
  per refresh ([[someday]], "`Budget.project()` ticks every nation's events");
  PR-46's finding 6.
- **Cost if unpaid.** The domain windows put a budget on every tab.
- **Size.** M; the trigger [[someday]] names is "V5's UI rework of the budget
  panel".

### D15 — The open-call pile, with a V5 disposition each

[[someday]]'s "Open author calls" checklist stays as it is (this session edits
neither it nor any box). What V5 does with each:

| Open call | V5 disposition |
|---|---|
| Event art: photographic, not painterly | **Taken in the interview: photographic, with a shared grade.** Tick it at V5.1's plan gate |
| No true "protect industry" option | Trigger: V5.3's sector law tiles |
| Portrait wall face verdict | Still the author's; fold into D11's portrait pass |
| Effects-blind divisions | Decide at V5.3's plan gate: graded decisions make breadth visible to the player, which is when a division blind to it starts to read wrong |
| Hand-curate the 25 generated majors | Untouched by V5 |
| Events dominance standard | Trigger: V5.2 rewrites events with speakers — re-tune or retire E3 there |
| Calendar booking composed laws | Trigger: V5.2's diary rework — recommended yes, **taken by the author 2026-10-19** |
| Month tick at 41 nations | **V5.0's gate** |

### D16 — The desk and the card column were built for six events a career

- **What.** The desk bound drops a critical arrival behind four minor ones;
  the card column is nearly all protected; hook events are rare by
  construction.
- **Evidence.** **Recorded**: [[someday]], "The desk bound outranks severity",
  "The card column is nearly all protected", "Hook events are rare by
  construction".
- **Cost if unpaid.** The inbox the author describes — people asking to see
  you, calls, requests — rides exactly this machinery.
- **Size.** M, inside V5.1/V5.2.

## List 2 — Design tensions

### T1 — The month tick against the roster

- **Sides.** A bigger world (author: neighbours now, China and Taiwan later)
  against a month that must not freeze the screen at speed 3 (a month every
  ~4.3 s, `tools/tick_budget_probe.gd`'s header).
- **Evidence.** D4.
- **Leans today.** Toward the roster: V4.11 grew it past the band and parked
  the cost.
- **V5's answer.** Pay D4 at V5.0, and make "the tick stays inside its band" a
  gate of every block that adds per-nation work.

### T2 — Panel count against the cluster grammar

- **Sides.** One window per system (22, by machine: Economy, Budget, Tax
  Code, Politics…) against a few windows per *domain of government*, each with
  tabs.
- **Evidence.** §1; the author's shell (§0).
- **Leans today.** System-first.
- **V5's answer.** The author's call flips it: about twelve domains in a
  sidebar, tabs inside. A system that spans domains (the budget) appears in
  each domain as that domain's slice.

### T3 — `SAVE_VERSION` discipline against registers that multiply

- **Sides.** The house rule (no migration ever; a missing field bumps only
  when absence would read wrong — AGENTS.md "Save format") against a tier that
  adds a dozen registers.
- **Evidence.** `SAVE_VERSION` 40 (`src/core/game_state.gd:599`); D1's
  triple lists.
- **Leans today.** Discipline held by care, not by structure.
- **V5's answer.** D1's field table carries, per field, its default and
  whether absence reads correctly — so the bump rule becomes a column a test
  reads, not a judgement re-made each block. "Never met" (knowledge 0) reads
  correctly for an old save: no bump.

### T4 — The sim/UI boundary against conversations

- **Sides.** Rule 2 (the UI reads, a command writes — `Budget.commit()`)
  against a scene where every line the player picks may change the sim.
- **Evidence.** The boundary holds today (§1: zero direct writes from
  `src/ui`). Summits already price one choice (V2.4b, [[summits-model]]).
- **Leans today.** Holds.
- **V5's answer.** Every dialogue choice that changes anything resolves to a
  named sim command with its own test; the scene holds no state the sim cannot
  rebuild.

### T5 — Abstract effect channels against concrete decisions

- **Sides.** The composition machine prices a bill as effect channels
  (`spending_pct_gdp`, scalars, `society` terms — [[legislature-model]],
  "Composition") against the author's "forty lycées in these regions, at this
  estimated cost".
- **Evidence.** [[legislature-model]] §Composition; §0.
- **Leans today.** Abstract.
- **V5's answer.** Concrete units are data (a catalogue: unit cost, build
  months, running cost, staff, where it counts) that *translate* into the
  existing channels — one story per decision, the anti-double-count pairs
  `law.gd` already enforces extended to them.

### T6 — Legibility against the fog the author wants

- **Sides.** The house rule — "where realism and legibility conflict,
  legibility wins" ([[calendar-model]]) — against hidden traits, odds as
  ranges, lies, and tables whose precision depends on the statistics service.
- **Evidence.** §0; [[calendar-model]] head.
- **Leans today.** Legibility.
- **V5's answer.** Fog is *shown*, never silent: a range is printed as a
  range with its source and why it is wide. The player always knows *that*
  they do not know.

### T7 — Determinism against chance

- **Sides.** A project with no `rand()` in its machines (composition is "a
  pure function of the spec"; the event hazard is deterministic) against levers
  with a success percentage and people who may lie.
- **Evidence.** [[legislature-model]] §Composition ("No `rand()` anywhere");
  [[events-model]] ("the deterministic hazard").
- **Leans today.** Deterministic.
- **V5's answer.** Seeded rolls — a hash of the ids, the month and a salt —
  so two identical states play out identically and the 51-regime re-runs stay
  comparable.

### T8 — Authored depth against volume (and two languages, and voices)

- **Sides.** V4 authored every event and both summit scenes by hand against
  2 147 people who should all be able to talk, in two languages, voiced.
- **Evidence.** §1 (102 events, 2 scenes); §0.
- **Leans today.** Bespoke.
- **V5's answer.** Scenes templated on the want grammar and traits
  ([[people-model]] §14), bespoke only for the four playable nations' heads
  of state and government (a builder-check ruling, [[v5]]); voices for
  variable-free opening lines and key beats, generated in advance, never at
  run time (**inferred** cost; Starter's monthly credit volume is the binding
  number, not measured here).

### T9 — Real likenesses against scandal content

- **Sides.** The author's 2026-09-13 call that portraits take their likeness
  from Commons photographs of the real politicians each fictional person
  plays on ([[portrait-attribution]]) against V5's affairs, bribes and lies,
  which would put those likenesses in compromising scenes — and voiced.
- **Evidence.** [[portrait-attribution]] head ("names differ, images ground
  the likeness"); [[fictionalization]]; §0. **Measured:** 140 people carry a
  real-photo reference, among them three of the four default leaders —
  `FRA_moucron` from a photograph of the sitting French president,
  `DEU_vogler` and `POL_zawadzki` likewise; only `GBR_marchbanks` has none.
  So "the president's affair" — the author's own example — would put a real
  head of state's likeness in it, which is why the call is needed before
  V5.1a's grade pass, not at V5.2c.
- **Leans today.** Likeness, because nothing compromising existed.
- **Answered by the author, 2026-10-19:** keep the portraits, exclude nobody
  from affair or corruption content — "the final image has nothing to do with
  the original photo". Recorded with its evidence step in [[v5]] (V5.2c: the
  four default leaders' busts side by side with their sources before the
  shadows ship). The licence record is a separate matter and stays owed
  (§2). The question as it was put, kept for the record (this is not legal
  advice): either people whose portrait has a real-person reference are
  never the subject of affair or corruption content (a data field the
  scene picker reads), or the people who can be are regenerated without a
  real-person reference. Voices are always designed, never cloned from or
  prompted to imitate a real person.

### T10 — A game measured by probes against a game nobody plays

- **Sides.** Rigorous bands, probes and re-runs against two play sessions in
  three months (`reports/playtest-2026-09-05*.md`,
  `reports/playtest-2026-09-16/`, machine-local), and the author's own "I have
  not played it because I do not consider it finished".
- **Evidence.** §0; the reports listing. **Measured.**
- **Leans today.** Probes.
- **V5's answer.** The play gate (§0): thirty minutes of the author at every
  block's end, the verdict a done-when.

### T11 — Real-time against conversation

- **Sides.** A real-time clock with three speeds (author: keep it, no
  Continue) against audiences, calls and branching talk.
- **Evidence.** The clock already holds for decisions
  (`_decision_holds_clock`, `src/ui/main.gd`).
- **Leans today.** Holds on decisions.
- **V5's answer.** A scene holds the clock while it is open; booking is the
  diary's occupancy rule ([[calendar-model]] §12), so time stays the scarce
  thing.

## List 3 — Three candidate V5 themes

### A — The World Talks Back — **RECOMMEND**

**The case.** The author's verdict that opened V4 ("unplayable and not fun")
was answered with machines; the interview says what is still missing is
*presence*. Nobody speaks (102 events in a narrator's voice, 2 scenes in the
whole game), nothing is concrete (forty lycées cannot be built), the ground is
abstract (640 straight spines), and the screen is a stack of system windows.
A pays the debts every later system stands on (D1–D7), puts a new shell and a
charter in front of it, then gives the game people who ask, bargain, lie and
remember, decisions in real units in real regions, and a real network you can
extend across a border. Every block ends on something the author plays.
**Cuts.** War, espionage, regimes, resource deals and the world roster, all to
V6 or later; the commodity layer's GDP wiring (D13).
**Verdict: recommend.** It is the author's own order, it front-loads the
foundations V6 needs (save table, tick, construction register, network), and
its middle block is the one that changes how the game feels.

### B — War and the wider world — **REJECT for V5**

**The case.** The author wants war with armies moved on the map, military
sites, arms procurement, espionage, regimes, annexation — and one day a global
roster. It is the most dramatic tier on offer.
**Cuts.** The people layer and the UI rework, or the audit.
**Verdict: reject for V5, schedule as V6.** Its foundations are V5's debts:
the tick is over its band (D4), annexation moves regions between nations on a
save surface written three times (D1), armies need the real network for
supply and movement (V5.4), sites need the construction register (D8), army
loyalty and the coup need regime machinery (D10), and the project itself
calls war "a second game" ([[tiers/someday|someday (ideas)]]). Built first,
it would be built on the debts.

### C — Goods become the economy, finished — **POSSIBLE, not V5**

**The case.** V4.6's signed call ("goods become the economy") did not ship
as signed: the layer models production, trade and prices but never writes
GDP (D13). Wiring it, sweeping `PRICE_ELASTICITY`, growing world production,
then the author's resource deals and export controls, would finish V4's
largest promise.
**Cuts.** Most of V5's people and network work.
**Verdict: possible — but as the economy block of V6 or V7.** It has no
player-facing surface until deals exist, and deals reuse V5.4's negotiation
machine. Doing it now would re-baseline 51 regimes for a change the author
cannot yet feel.

## 2. Docs that disagree with the machine (found by this pass)

- **AGENTS.md's agent gate does not run as written.** "THE AGENT GATE":
  `python tools/suite_runner.py --ci` exits 2 with "no tests given"
  (`tools/suite_runner.py:423-424`); the registry is passed by
  `tools/run_tests.sh:321`. **Measured** (this session ran it first).
- **The brief's tick location is stale.** It points at
  `src/ui/main.gd::_on_month_elapsed`; PR #14 moved the order to
  `src/sim/world_month.gd`.
- **"No person without art" aged.** True of V4.3's bench; since V4.7 all 464
  executives draw the silhouette (D11).
- **The portrait licence record is short by 55 people.** 140 people have a
  real-photo reference (`tools/portraits_photo_sources.json`, untracked);
  [[portrait-attribution]], which calls itself "the single committed record",
  credits **85**. The other **55** have committed busts (all five
  expressions) and fall under `REUSE.toml`'s general glob, which declares
  `assets/portraits/**` **CC-BY-NC-4.0** as "art generated from text alone" —
  untrue for them. 46 of the 55 photographs are CC BY or CC BY-SA (27
  BY-SA), so credit is owed and the BY-SA ones cannot ship as NC. Two of the
  four default leaders are among them (`FRA_moucron`, public domain;
  `POL_zawadzki`, CC BY 3.0 PL). And 12 of the 85 credited entries name a
  different photograph from the local source file, so for those the record
  of which photo a bust used is ambiguous. **Measured**; found by the builder
  check, verified here. A fix in its own small PR, before any V5 block.
- **The network's numbers are historical.** [[data-sources]] (§Natural Earth
  roads) reasons on 463 edges and 213 regions, [[network-model]] on 112
  regions — the V3.4 and V2.7 records. Today: 640 edges over 277 regions. Not
  drift (they are dated records), but V5.4's gates must re-anchor on today's
  count. This session told the author "463" before counting; the number here
  is the measured one.

## 3. What this reflection did not verify

- **EuroGlobalMap** (EuroGeographics): licence text, current version,
  coverage of TUR/BLR/UKR — secondary sources only; V5.4's step-0 gate.
- **ElevenLabs music for games**: "commercial use from Starter" is on the
  official pricing page; a narrower rule for games past a revenue line comes
  from one secondary source.
- **Image outputs through third-party models** (gpt-image, flux) on
  ElevenLabs: their own terms may apply; not read.
- **The ×23 diplomacy cost of a 195-nation roster**: arithmetic, not run.
- **Football Manager details** beyond the sidebar, the Continue button and
  blocking inbox items (verified): attribute masking and staff judging come
  from memory of the game.
- **Every session estimate** in [[v5]].

## 4. Measurements run for this reflection

- Two windowed frames of the running game (`tools/screenshot.gd --zoom 1.6`
  and `--zoom 6 --center 4.5 47.5`): the map at depth draws the road layer as
  straight spines between region centres over the whole continent.
- The suite (121 of 121, 11:57) and the tick probe (446 ms mean at 41
  nations); the detail is recorded once, in [[v5]]'s "Measurements".
- `git blame` over `src/` for §1's reviewed-code split; content and art
  counts by script over `data/` and `assets/`.

---

Related: [[v5]] · [[v4]] · [[someday]] · [[history]] · [[engine-decision]] ·
[[panel-system]] · [[people-model]] · [[projects-model]] · [[network-model]] ·
[[map-platform-model]] · [[commodities-model]]
