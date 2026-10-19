---
title: History
tags:
  - history
  - reference
---

# History

The per-block record that used to be AGENTS.md's "Current focus": what each version built, what each probe measured, each refused alternative and each instance of a stale row. Moved here verbatim at the end of V4.4 (2026-10-14) because AGENTS.md is loaded into every session and this part was ~340 KB of it. Newest block first; nothing was rewritten in the move, so a sentence saying "this file" or "this row" means AGENTS.md as it was. Start at [index](index.md); the parking lot is [someday](someday.md).

## V5.0b — the loader split, the size ratchet, isolated runs (2026-10-19)

**The split.** `src/core/data_loader.gd` (2 739 lines, 53 functions) is one orchestrator — every register, `load_all()`, the name helpers — and thirteen per-content loaders in `src/core/loaders/` (people, companies, regions, outlets, the verb actions, energy, campaign, commodities, programme, politics, diplomacy, geo, events), each validator beside its type. Each loader holds static functions over the loader it fills, the old `_<name>()` bodies moved verbatim by a script with members read as `loader.`; the seven private entry points a test drives stay on DataLoader as delegators, so no caller moved. 447 lines; the largest new file 223 code lines. Proof: a dump of all 36 loaded structures (objects walked through their script properties, sorted keys, 5.8 MB) byte-identical before and after; the 23 loader and bad-data tests pass; balance re-run: 51 regimes, 166 vs 166 verdicts, 0 flipped, `tip.json` `cmp`-identical to V5.0a's (`src/` since that capture changed comments and the test-only absent_ok column alone).

**The ratchet.** `tools/check_size.py`, in CI's checks job: code lines (no blank, no comment-only line) over `src/`; a new file at most 300; the 21 files over it in `tools/size_baseline.json` may only shrink, and the change that shrinks one lowers it (`--update`, which refuses to raise or add); nothing past 2 000 total lines but `src/ui/main.gd` until V5.1c; `tools/` and `tests/` past 2 000 printed (four today). A planted new 302-line file, a grown, a shrunk-without-update and a 2 134-line file each fail it.

**The agent gate made true.** `python tools/suite_runner.py --ci` with no tests runs the registry (it exited 2): the `tests=()` array of `tools/run_tests.sh`, parsed rather than run through bash — on this machine's `core.autocrlf` checkouts the working-copy script is CRLF and bash cannot run it — with the same unregistered-test rule.

**Isolated runs** (the author's ask, from the 2026-10-19 isolation experiment). `--isolate` on `suite_runner.py`, passed through by `run_tests.sh`: a private `APPDATA`/`XDG_DATA_HOME` for every godot it spawns, the cold-clone `--import` included (`run_tests.sh`'s own import too), deleted on success and kept on failure. The hand-run line `APPDATA="$(mktemp -d)" godot ...` was proved to land user:// in the temp dir. Two concurrent isolated runs in two checkouts -- the suite-exclusive test_save_load side by side for ~59 s -- both passed and left the real user dir untouched. AGENTS.md's "One Godot at a time" now says what may overlap (isolated runs in separate checkouts) and what stays alone (timing probes, two runs in one checkout, any un-isolated Godot). The orphan `tools/bloc_probe.gd.uid` is gone.

## V5.0a — one field table for NationState (2026-10-19)

`duplicate_state()`, `to_dict()` and `from_dict()` of `src/core/nation_state.gd` were three hand-written lists over 217 fields; each now walks one table, `src/core/nation_fields.gd`. A row carries the field's copy kind (SCALAR / DEEP / NONE), its read kind (VALUE cast to the default's type, COPIED deep copy, or one of seventeen readers in `src/core/nation_field_readers.gd`, which took the old bespoke rebuilds), its default (pinned equal to the declaration's) and **absent_ok** — whether its absence reads correctly for a save older than the field: the bump rule as a column (168 saved fields false, 43 true, 6 not saved). `from_dict()` now rebuilds every register; `sector_investment`, `projects` and `plants` — and every other container it used to assign — were aliased to the payload. `nation_state.gd` 2 900 → 1 801 lines. `SAVE_VERSION` stays 40.

`tests/test_nation_fields.gd` (no loader, ~3 s): completeness off `get_property_list()`; a sentinel round trip of every field, direct, through JSON and through `duplicate_state()`; aliasing (mutating a loaded state must not move its payload); absence (an erased key reads its default); and the must-bump set pinned against `SAVE_VERSION` (count 168 + md5), so a new field whose absence reads wrong fails until the version moves. Mutation-checked: a dropped row, a container marked SCALAR, a flipped absent_ok and an assigning reader each fail it.

Proof: golden `GameState.to_dict()` dumps (sorted keys) of a booted FRA game and of the same game after 24 real months — plain, through `duplicate_state()`, through a JSON round trip and through a direct round trip — byte-identical before (a detached clean worktree of `1b69e83a`) and after: 8 of 8 files. Balance re-run: 51 regimes, `balance_diff.py` 166 vs 166 verdicts, 0 flipped, 0 changes past tolerance, and `base.json`/`tip.json` `cmp`-identical; `base.json` is also `cmp`-identical to a0's tip. Cost, measured (one 41-nation GameState, mean of 20): `duplicate_state` 12.5 → 20.4 ms, `to_dict` 1.4 → 5.6 ms, `from_dict` 19.7 → 33.2 ms — the generic get/set; a UI-only path whose refresh projects 2 × 24 months, so not tuned. `GameState`'s own triple (18 copied, 19 saved, each register a bespoke per-entry schema) was counted and NOT moved onto the table: it would need a reader per register, the new machinery the brief ruled out.

## V5.0a0 — the engine, 4.7.1 → 4.7.2 (2026-10-19)

Godot bumped to **4.7.2-stable** (winget; CI pin `GODOT_VERSION` in `.github/workflows/tests.yml`, AGENTS.md's stack line, README, CONTRIBUTING, tooling.md and the bug template follow). Proof: `tools/balance_probe.gd` over the 51 regimes captured on 4.7.1 (`base.json`, main `14719499`, before the upgrade) and re-run on 4.7.2 after one `--headless --import`; `balance_diff.py`: 166 vs 166 verdicts, 0 flipped, 0 changes past tolerance; the two JSONs are byte-identical (`cmp`). Targeted tests `test_ui_theme`, `test_save_load`, `test_data` pass on 4.7.2; the full suite on 4.7.2 is the parent session's run and CI's four cold-cache shards. The dated 4.7.1 history (engine-decision's S4 note, the S1 tooling note) stays as written.

## V4 — closed (2026-10-18)

The tier's close-out (the merge record, promised against shipped, the measured gates, the lessons) is the closing section of [docs/tiers/v4.md](tiers/v4.md). Several block rows below still say "IS BUILT": each of them merged, and the merge table there gives its PR and commit.

**The AGENTS.md "Current focus" rows at the close, moved here verbatim on 2026-10-18** so every session does not pay for them. One correction in the move: the V4.4 and V4.5 rows cited `5a2d00a` and `127b087`, commits from before the public repo's rewritten history; they now cite main's `6e028eb2` and `8278edb1`.

**V4.4 — EVENTS AT SCALE — IS MERGED (PR #49, merge commit `6e028eb2`, 2026-10-14)** after a 23-pass review loop. The event slot became a severity-ordered desk (`ns.event_queue`, `QUEUE_MAX` 4); the quiet went per-category; hooks (a closed vocabulary in `events_constants.ON_ACTIONS`) make the world react to what the player did; a choice can arm a chain; the other 28 nations answer through a deterministic chooser, with tax, spending and company effects skipped for them (their budgets never tick); the book is 102 events in nine categories with 54 art plates. `SAVE_VERSION` is **39** (argued in `game_state.gd`'s `SAVE_VERSION` block). Suite 104/104, names clean. Model: [docs/events-model.md](docs/events-model.md). The re-baseline's 24 outcome flips (20 HELD→LOST at 2032, through the default-drain channel) were ACCEPTED as the bound by the author on 2026-10-14: ignoring the desk is meant to cost.

**Open for the author, none urgent** (each recorded with a trigger in [docs/someday.md](docs/someday.md), and listed as a checkbox under its "Open author calls" so the vault dashboard shows what is still open): the event-art contact sheet verdict (the plates lean photographic, not painterly — [docs/event-art-plan.md](docs/event-art-plan.md)); `com_industry_bills.protect_the_makers` is a regulation, so the book has no true "protect industry" option. (E4/E5 were re-run on 2026-10-14 after the commodity unbind and the price-drift fix: 12.0 arrivals per term, every band PASSED.)

**V4.5 — THE COUNCIL, CONTESTED — IS MERGED (PR #53, merge commit `8278edb1`, 2026-10-15)** after a 2-pass review (budget 3, bar fixed up front). Sponsors who lobby and vote for their own proposals, three priced bargaining currencies (favour 12 / aid on the transfer line / vote-trade IOU settled at ratification for treaties), unanimity treaties with vetoes beside QMR, the real EU Council presidency (Decision (EU) 2016/1316, repeated after 2030 — a bound; the chair at the next opening sets the agenda; NATO has none), one opening per council every 6 months, and ratification at home through `Legislature.resolve_vote()` (one rejection kills the treaty for every member). 34 proposals placed by `tools/council_probe.gd`; bands C2–C4 PASS, C1 and C6 BOUND, C5 2.215 raw. UI: the council block (`src/ui/council_section.gd`, `council_bargains.gd`), ratification card on the bill's blurred forecast, desk mark, calendar deadline, top-bar Europe figure. `SAVE_VERSION` stays 39. Suite 106/106. Model: [docs/orgs-model.md](docs/orgs-model.md) §V4.5; history: [docs/history.md](docs/history.md).

**V4.11 — THE NEIGHBOURHOOD — IS MERGED (PR #3, merge commit `d59fd6a1`, 2026-10-17)** after a 3-pass review (built 2026-10-15/17, a1 a2 b1 b2 c). The roster is 41: the 29 plus twelve simulated, not playable (NOR ISL SRB TUR ALB MKD MNE BIH UKR MDA XKX BLR). The grade is DERIVED (`src/core/roster.gd`: playable / simulated / outline), never stored. The 133 outlines carry a name, GDP and real production shares (`data/world/outlines.json`, `tools/endowments_generate.py`) and trade as one world pool; on the map an outline can be hovered and read (`src/ui/map_outlines.gd`) but never clicked. `SAVE_VERSION` **40** (no field; V3.3's argument). Suite 109/109. Re-baselines: 0 outcome flips of 94 (a), byte-identical (b). Open for the author: the month tick is 392 ms at 41 (Diplomacy's N²); clothing still creeps (1.20x at month 120, no crossing since the review's energy fix; likely static world volume — [docs/someday.md](docs/someday.md)). History: [docs/history.md](docs/history.md) §V4.11. **NEXT: V4.8 — the reading surface**, building (see below). Per-block history (what each version built, what each probe measured, each refused alternative) lives in [docs/history.md](docs/history.md), moved out of this file so every session does not pay for it; the tier docs are `docs/tiers/` ([v4](docs/tiers/v4.md) is current) and the parking lot is [docs/someday.md](docs/someday.md).

**V4.8a — THE STRIP, WHOLE — IS MERGED (PR #4, merge commit `fac8e699`, 2026-10-17).** The top bar is one register of thirteen readings (`src/ui/strip_readings.gd`; `top_bar.gd` is its host), stacked caption over value to fit 1920 × 44 (one line measured 2219 px; author's call). Tooltips surface existing queries only -- no `src/sim/` diff (author's call); alerts fire on thresholds the game already holds and name their window with the bound key. `tests/test_strip_readings.gd` is the tooltip walker (it measures WITH the game theme -- unthemed it said 44 px where 50 was drawn). Register B: two rows fixed, four struck. **The UI is fully reworked in V5** (author, 2026-10-17): V4's UI effort goes to registers and walker tests, not layout. History: [docs/history.md](docs/history.md) §V4.8.

**V4.8b -- NESTED TIPS AND THE OUTLINER -- IS MERGED (PR #5, merge commit `c34abc53`, 2026-10-17).** The strip's tooltip is a two-level popup (`src/ui/tip_popup.gd`; level 2 from `src/ui/strip_children.gd`, asked lazily), the strip is twelve readings (People left it), and the outliner is a register (`src/ui/outliner_readings.gd`) drawn by a window (`outliner_panel.gd`, key Q). No `src/sim/` diff. Contract and walker: [docs/panel-system.md](docs/panel-system.md) §20. "Watched firms" has no register in the game, so the outliner reads firms in trouble (author's call; a player watchlist is parked in [docs/someday.md](docs/someday.md)).

**V4.8c -- MESSAGE SETTINGS AND THE LEGEND'S GRADES -- IS MERGED (PR #6, merge commit `881de1c9`, 2026-10-17) after a 2-pass review (one fix: a quiet card's deadline now follows the desk). V4.8 closes here.** Per event category, four switches (notify / feed / popup / pause), each a severity band (`src/ui/message_settings.gd`, `[messages]` in `user://settings.cfg`, no save field); pause defaults to Major+ (author's call). The arrival pause's contract is kept by name: the LAPSE GUARD in `main.gd` holds the clock for an unanswered quiet decision in its last month, so none lapses unseen. The Political legend counts playable / simulated / outlines through `Roster.counts()`. No `src/sim/` diff. Suite 113/113. Contract: [docs/panel-system.md](docs/panel-system.md) §21. **NEXT: V4.9** -- ceremony, motion and sound (`.superpowers/sdd/v4.9-handoff.md`), split a/b/c at the plan gate; a is below.

**V4.9a -- THE LOADING SCREEN AND THE MOTION VOCABULARY -- IS MERGED (PR #7, merge commit `14b6d2a2`, 2026-10-17).** Menu -> game no longer freezes ~7.5 s: `src/ui/boot_stages.gd` runs the boot a stage per frame (threaded scene compile, data, world, `Net.warm_step` -- the one `src/sim/` diff, the same table in slices), the loading screen's bar is the MEASURED stage weights (`tools/boot_stages_probe.gd`), and `main.gd` takes the loader and state it is handed (`pending_loader` / `pending_state`), building its own on a direct load as before. `src/ui/motion.gd`: windows open, cards arrive, strip figures roll, the date beats per day; off under `--headless` and by `[display] motion`. Suite 115. Contract: [docs/panel-system.md](docs/panel-system.md) §22.

**V4.9b -- ELECTION NIGHT AND THE MAP'S CROSSFADE -- IS MERGED (PR #8, merge commit `cb7784f3`, 2026-10-17).** The election plate is a count: the player's regions declare smallest first (`src/ui/election_night.gd`), every figure rolls to the running count, the verdict, attribution and sting come last; a click skips, and the footer reads Skip count until the verdict is shown, so no result is dismissed unseen. The regions carry a DERIVED swing (author's call): `Elections.regional_shares()` -- pure, the one `src/sim/` diff -- tilts the incumbent by regional unemployment x jobs salience and renormalises so the weighted totals are the verdict exactly. Map layers crossfade (0.3 s) through `set_layer()`, which V4.10 shares. `Motion.run()` is the new verb. Suite 116. Contract: [docs/panel-system.md](docs/panel-system.md) §23. **NEXT: V4.9c** -- the synthesized sound set.

**V4.9c -- THE SYNTHESIZED SOUND SET -- IS MERGED (PR #9, merge commit `2daf3858`, 2026-10-18).** Every sound generated, none recorded (V3.6's house style): `src/ui/sound_constants.gd` (recipes and levels with reasons), `synth.gd` (pure additive render), `sound.gd` (the one-shot door, worker warm-up), `sound_bed.gd` (looping beds that fade and answer the settings). Beds per screen (menu, game), window open/close, pause/resume by hand, a declare tick per region on election night, the event sting by severity (one per month, worst severity, behind the NOTIFY band -- author's call), V3.6's election sting moved byte-identical (SHA-256 pinned). The level ladder (beds < cues < events < election, <= -8 dB) and the seamless loops are measured on the rendered samples. Renders run on workers (one-shots 193 ms, beds ~300 ms measured). New key `[audio] ambient`, default ON (author's call). No `src/sim/` diff, `SAVE_VERSION` unchanged. Suite 117. Contract: [docs/panel-system.md](docs/panel-system.md) §24. **V4.9 closes here; NEXT: V4.10** -- the map, close up.

**V4.10a -- THE GROUND AT DEPTH -- IS MERGED (PR #10, merge commit `d8abd155`, 2026-10-18).** The satellite is RETIRED AT DEPTH, not scaled (V3.1's per-tile LOD refusal stands): `tools/ground_generate.py` bakes one paper-and-hillshade texture once (NOAA ETOPO 2022 60s, public domain, fetched into gitignored `sources/etopo/`; coast from `data/geo/`'s own rings) into `assets/map/ground_europe.webp` + its bounds sidecar, and `src/ui/map_ground.gd` decodes it from bytes. The band is DERIVED from the photograph's texel density: smoothstep zoom 1.25 -> 2.5 (author signed off the opening fit landing mid-crossfade). The tree was ALREADY over V3.1's 2.0 ms G2 before this block (2.27-2.29); author's call: a is judged on its delta (max zoom -0.44 ms, mid-band +0.12, drag +0.10 -- paired same-run rows in `tools/frame_probe.gd`), the absolute 2.0 returns in V4.10c. Boot `enter` 780 -> 1080 ms (the decode). No `src/sim/` diff. Model: [docs/map-platform-model.md](docs/map-platform-model.md) §9. **NEXT: V4.10b** -- materials, weighted borders, glyph tiers and labels.

**V4.10b -- BORDERS, GLYPHS AND NAMES AT DEPTH -- IS MERGED (PR #11, merge commit `acbde1d0`, 2026-10-18).** Materials moved to c (author: shader work). Borders weighted by the roster grade (`map_view.BORDER_KINDS`, photo colour blending to ink by `ground_alpha()`); city glyphs in three tiers (`src/ui/map_glyphs.gd`: capital ringed, then >= 500k; MLT's capital is a bound, Valletta is not in the register); names placed by a greedy declutter over a grid hash (`src/ui/map_labels.gd`). Band measured by `tools/label_probe.gd` against a rule written first: tiers 1-2 named from 2.0, tier 3 a BOUND (hover only). Nation names may sit over marks (review pass 1: 20 of 41 were lost at the opening fit), and the hovered city's label is reserved. Paired cost: max zoom +0.15 ms, opening fit +0.79, drag at max +0.67; the drag at the opening fit +5.8 ms is c's. No `src/sim/` diff. Model: [docs/map-platform-model.md](docs/map-platform-model.md) §10. **NEXT: V4.10c** -- materials as the first shaders, and G2 back under 2.0.

**V4.10c -- MATERIALS AND THE GATE -- IS MERGED (PR #12, merge commit `d3953709`, 2026-10-18). V4.10 closes here.** Attribution first (`map_view._pass_off`, the "C" rows): the roster pass was the map -- 1.37 ms of max zoom, 65 of the 83 ms opening-fit drag -- and none of it was the camera's. The raster, outline borders, roster fills and roster lines are child layers projected by their transform (`src/ui/map_draw_layer.gd`); the last three are ONE mesh each, built once (`map_fill_mesh.gd`, `map_line_mesh.gd`), coloured and sized from palette texels, so a pan or a zoom re-records none of them. Materials are the first canvas_item shader (`src/ui/map_fill.gdshader`: a 7 px edge band per nation, a faint hatch), cost inside the run spread; `map_line.gdshader` turns palette widths into geometry. **G2 0.26 / 0.58 ms** (two runs; was 1.57-2.29), opening fit 11.5 -> 2.9 ms, drag at the fit 83 -> 18 ms, draw calls at max zoom 585 -> 258. V3.1's ring cull and `tests/test_map_cull.gd` retired. Suite 120/120. No `src/sim/` diff. Model: [docs/map-platform-model.md](docs/map-platform-model.md) §11. **NEXT: the V4 tier close-out** (its own session).

## V4.10

**V4.10c -- MATERIALS AND THE GATE -- IS MERGED (PR #12, merge commit `d3953709`, 2026-10-18). No `src/sim/` diff, `SAVE_VERSION` unchanged. V4.10 closes here.**

- **Attribution before any lever** (`map_view._pass_off`, frame_probe's "C" rows, one run): the roster pass was 1.37 ms of max zoom and 65 ms of the 83 ms drag at the opening fit (fills 41, lines 16, the shared projection loop the rest).
- **The lever:** the roster and the outline borders are projected layers (`src/ui/map_draw_layer.gd`), each one mesh built once in `setup()` (`map_fill_mesh.gd`, `map_line_mesh.gd`); colour and line width are palette texels the shaders read. A pan or a zoom re-records none of them (asserted by draw generation in `tests/test_map_view.gd`).
- **Found by measuring:** lines first kept as `draw_polyline` on an uncull'd layer pushed max zoom 2.9 -> 6.3 ms (~1500 draw calls); that is why lines are a mesh too.
- **Materials:** `src/ui/map_fill.gdshader`, the first canvas_item shader -- a 7 px edge band per nation (vertex-pushed, constant in pixels at every zoom; a baked distance texture was refused, its border quantised 8 px off the line at max zoom) and a faint hatch (first cut ±22 % read as stripes, shipped ±10 %). Paired on/off: inside the run spread in three runs.
- **The gate:** G2 0.26 / 0.58 ms in two full runs (was 1.57-2.29); opening fit 11.5 -> 2.9 ms; drag at the fit 83 -> 18 ms (the rest is cities ~8, labels ~6, roads ~2 -- not pulled).
- **Design questions from PRs #10/#11:** two decided (parchment under every layer; the reserved hover label), six parked in [someday](someday.md) with triggers.
- Model: [map-platform-model](map-platform-model.md) §11.

**V4.10b -- BORDERS, GLYPHS AND NAMES AT DEPTH -- IS MERGED (PR #11, merge commit `acbde1d0`, 2026-10-18). No `src/sim/` diff, `SAVE_VERSION` unchanged.**

- **Plan gate (author):** materials to c; the third border key is the roster grade; greedy labels by tier on a grid; tiers by capital, then population.
- **The band, rule first:** tiers 1-2 named from zoom 2.0 (>= 80 % in the Ruhr and the Po valley), tier 3 a bound (64 % over the Ruhr at max zoom), hover only.
- **Found by measuring:** blocking every glyph made the placement cost 25-45 ms and held tier 2 under 60 %; only tier 1-2 marks are obstacles now, and tier 3 is skipped before projection (1.5-2.9 ms per placement).
- **Capitals:** a folded name match; MDA folds, MLT is a bound (Valletta is below the register's cut).
- **Review pass 1 (Critical):** centred nation names were dropped under capital rings -- 20 of 41 at the opening fit. Names may now sit over marks, never over names; the hovered city's label is reserved; the outline hover follows the ground.
- **Cost (paired, one run, after the fix):** max zoom +0.15 ms, opening fit +0.79, drag at max +0.67; the drag at the opening fit +5.8 ms goes to c.
- Model: [map-platform-model](map-platform-model.md) §10.

**V4.10a -- THE GROUND AT DEPTH -- IS MERGED (PR #10, merge commit `d8abd155`, 2026-10-18). No `src/sim/` diff, `SAVE_VERSION` unchanged, no settings key.**

- **Plan gate (author, 2026-10-18):** a + b + c kept despite V5's UI rework (the map is world drawing; its seams survive); 2-pass review budget per PR; the V4 tier close-out is its own session after c.
- **What shipped:** `tools/ground_generate.py` (one-time bake, ETOPO 2022 60s via NOAA ERDDAP), `assets/map/ground_europe.webp` (4920x3000 at 60 px/deg, 654 KB, extent -31..51 E / 28..78 N derived from the roster's rings + 6 deg), `src/ui/map_ground.gd`, the band in `map_view._draw_raster()`, `tests/test_map_ground.gd`.
- **The gate finding:** G2 measured 2.27 / 2.29 ms on the tree BEFORE any ground work (EU-29 was 1.37) -- V3.4-V4.11 content grew the max-zoom draw 451 -> 574 calls. Author's call: a judged on its own delta; V4.10c owns the absolute 2.0.
- **Measured (1440p, vsync off, paired in one run):** max zoom 3.91 -> 3.47 (the photograph is skipped under an opaque core), mid-band 1.9 9.80 -> 9.92, opening fit 10.20 -> 10.52, max-zoom drag 23.27 -> 23.37. Boot: decode + mipmaps + upload ~285 ms; `enter` re-weighted 780 -> 1080.
- **A crack class found on the preview, not in any test:** the three geometry vintages do not tile, and over paper a gap reads as sea. Filled where the DEM says land (z > 0); straits are below sea level and stay open.
- Model: [map-platform-model](map-platform-model.md) §9.

## V4.9

**V4.9c -- THE SYNTHESIZED SOUND SET -- IS MERGED (PR #9, merge commit `2daf3858`, 2026-10-18). No `src/sim/` diff, `SAVE_VERSION` unchanged, one settings key (`[audio] ambient`, default ON).**

- **Contract and instruments: [panel-system](panel-system.md) §24.**
- **Author calls at the plan gate (2026-10-17):** the beds get their own Ambience switch, default ON; the event sting follows each category's NOTIFY band.
- **The set:** two 16 s beds (menu, game), window open/close, pause/resume by hand, an election-night declare tick, the event sting at three severities, V3.6's election sting -- eleven one-shots and two loops, all additive synthesis from one constants file. The sting's recipe moved out of `sting.gd` with its bytes pinned by hash.
- **Measured first:** the generic render cost 193 ms for the one-shots (80 ms for the critical sting alone) and ~300 ms per bed after hoisting the partials into typed arrays (-45 %, no float changed). Too much for a frame, so beds render on a worker and swell in, and the one-shots warm on a worker as the game opens.
- **The tests caught the tuning:** the first cut put a bed as loud as the quietest tick, the major sting quieter than the minor, and two stings ended on a click -- all four red on the rendered samples, fixed by level and duration.
- **Mutation-checked, and one survived:** a `_skipping` flag meant to silence a skipped count was dead -- `skip()` lands the count at t = 1, where the last-region rule already silences it. Deleted.
- **Review (budget 3, bar: changes what a player hears or sees), 2 passes:** pass 1 fixed three -- an interrupt silenced by its NOTIFY band, its Dispatches' open tick over the sting, two overlapping beds after Ambience off/on -- and left three below the bar; pass 2 clean.
- **Not verifiable here:** how it sounds. Files exported for the author's ear.
- **Refused:** voice, licensed music, a composed score; a click on every button; a volume ladder.

**V4.9b -- ELECTION NIGHT AND THE MAP'S CROSSFADE -- IS MERGED (PR #8, merge commit `cb7784f3`, 2026-10-17). One `src/sim/` diff (`Elections.regional_shares()`, pure, two constants), `SAVE_VERSION` unchanged, no settings key.**

- **Contract and instruments: [panel-system](panel-system.md) §23.**
- **Author call at the plan gate (2026-10-17):** the regions show a DERIVED swing rather than the national shares thirteen times -- the incumbent tilted by regional unemployment x jobs salience, renormalised so the weighted totals are the verdict exactly (1e-12). Measured at France's opening: 24.4-28.0 % by region around 26.5 %.
- **The night** (`src/ui/election_night.gd` + `election_panel.gd`): regions declare smallest first, figures roll to the running count, the verdict, attribution and sting come last. Replaces V3.6's tally; `Motion.run()` is the new verb; the tables are built at their finals, so motion off and skip are the same path.
- **The map's crossfade:** a layer toggle fades the fills from what was on screen over 0.3 s; strokes and legend switch at once. V4.10 shares `set_layer()`.
- **Found on the way:** the first windowed capture showed the held-back verdict as a ~200 px hole above the count (transparent keeps its space) -- now hidden; and `tests/test_geography.gd` caught `regional_shares()` naming the regional register in `src/sim/`, which V2.5 gives `regions.gd` alone -- the caller now reads it and passes a `jobless_index`.
- **Refused:** a running seat projection, rows reordering as the lead moves, regions lit on the map (§23).

**V4.9a -- THE LOADING SCREEN AND THE MOTION VOCABULARY -- IS MERGED (PR #7, merge commit `14b6d2a2`, 2026-10-17). One `src/sim/` diff (`Net.warm_step`, the same table in slices), `SAVE_VERSION` unchanged, one settings key (`[display] motion`).**

- **Contract and instruments: [panel-system](panel-system.md) §22.**
- **Author calls at the plan gate (2026-10-17):** all three sub-blocks, full, despite the V5 rework -- motion as one reusable vocabulary rather than per-panel polish; and `Net.warm` made resumable so the bar moves through its 4.5 s honestly rather than holding on one frozen frame.
- **Measured first:** menu -> game froze ~7 s with the menu showing. Stages windowed: scene compile 1.3 s, data 0.36 s, world 0.07 s, network 5.0 s (4.4 s of work plus frames), enter 0.78 s. The network table had doubled since its comment (~2 s at 29 nations). The bar's weights are those numbers.
- **The same work moved earlier, not duplicated:** `boot_stages.gd` builds the loader and the state across frames and hands them to `main.gd` (`pending_loader` / `pending_state`); a direct scene load builds its own, so the thirty tests that load `main.tscn` are untouched. `test_menu.gd` was rewritten to drive its three starts sequentially through the loading screen, each on a fresh menu.
- **Motion** (`src/ui/motion.gd`): a window opens, a card arrives, the strip's figures roll, the date beats once a day (dimmed when paused). Off under `--headless` and by the settings row; `finish()` is the skip path V4.9b's sequence will use.
- **The capture caught what the suite could not:** a heavy window's ~0.4 s build frame swallowed the whole 0.16 s opening -- motion stepped with a 1/30 s delta cap since, pinned by a stalled-frame test (§22).
- **Two defects found on the way, worth keeping.** A test polling `_watching != null` on a loading screen that had freed itself never advanced (a freed reference is neither null nor usable) -- replaced by an explicit flag. And a Python edit on Windows rewrote twelve LF files as CRLF (text-mode write); caught by git's warning, normalised before commit.
- **Refused:** a close animation, an awaited `main.gd` `_ready()`, a time-estimated fill inside the two stages Godot cannot observe, reusing the menu's loader (all argued in §22).

## V4.8

**V4.8a — THE STRIP, WHOLE — IS BUILT on `v4.8-reading-surface` (2026-10-17): the top bar is one register of thirteen readings with hover breakdowns and an alert tone; no `src/sim/` diff. Plan: `docs/superpowers/plans/2026-10-17-v4.8a-reading-surface.md`.**

- **The register** (`src/ui/strip_readings.gd`, static like `pending.gd`): `ORDER`, `CAPTIONS`, `INPUTS`, and `read(id, state, loader)` → `{text, tip, visible, alert_window}`. `top_bar.gd` is the host and knows no reading. New: approval with its six-month trend (the portrait's polled read), inflation, unrest, the assembly margin, Supplies (V4.6's owed and MISSING interim entry, through `commodities_panel.gd`'s now-static `coverage()`); debt rides the balance tip.
- **Author's call at step 0: tooltips surface only what existing code computes.** The handoff's "Trends' attribution machine" is three pieces -- Trends' six-month deltas, `Elections.attribution`, `briefing.gd` -- and GDP, inflation and unrest have no decomposition anywhere; their tips say what the number is and stop.
- **Alerts** only where the game already holds a threshold: unrest past `UNREST_THRESHOLD_PCT`, a minority or cohabitation, a critical on the desk, a treaty awaiting the assembly, a good under `SHORTAGE_COVERAGE`. The figure turns `FigureAlert` (FIGURE's face, BAD's colour) and the tip names the window with the key `main.gd`'s window manager binds.
- **THE STRIP DID NOT FIT, MEASURED.** Thirteen on one line needed 2219 px of a 1920 screen (2107 even with shortened captions and People out); the author chose stacked figures (caption over value, U2's shape). The first windowed shot drew the stack 50 px against `window_frame`'s 44 px `TOP_MARGIN` while the walker said 44 -- it measured the bar without the game theme. The walker now applies `UiTheme.build()`; the padding dropped 6 → 3; re-shot at 44. The 826 px band is unchanged.
- **The walker** (`tests/test_strip_readings.gd`): every reading resolves; every declared input is perturbed and the reading must move; a history-less game prints dashes, never `0.0 pp`; every alert names a window `main.gd` registers; the strip fits 1920 × 44 at worst-case text. Mutation-checked: a hard-coded unemployment reading failed three ways.
- **Register B**: `approval_delta` no longer invents a movement from an entry without approval, and the top bar no longer crashes on a null `player()` (both pinned in `test_playability.gd`, both seen failing first). The shortcut row was already fixed (D U C R I); the council "0 months", "0 of N seats" and missing-bloc rows do not reproduce by construction (struck in the audit with the reason).
- **Author, mid-block: the UI is fully reworked in V5.** Effort went to the register and the walker, the seams that survive; the layout is the cheapest legible one.

**V4.8b -- NESTED TIPS AND THE OUTLINER -- IS BUILT on `v4.8b-nested-tips` (2026-10-17): the strip's tooltip is two levels deep and People left the strip for an outliner window; no `src/sim/` diff, `SAVE_VERSION` unchanged. Plan: `docs/superpowers/plans/2026-10-17-v4.8b-nested-tips-outliner.md` (local, the folder is ignored).**

- **Contract and walker: [panel-system](panel-system.md) §20.** `read()` grows `lines` (`{text, child_id}`), `tip` stays the joined text; `strip_children.gd` answers a child lazily; `tip_popup.gd` is the custom popup. Seven lines open a child; five readings have none because nothing decomposes them (the V4.8a call).
- **Author calls at the plan gate (all four taken as written):** "watched firms" has no register in the game, so the outliner reads firms in trouble (failing majors in their rescue window, a standing foreign bid) -- a player-chosen watchlist would need a save field and a sim verb, parked in [someday](someday.md); "people you are worried about" is a grudge or a loyalty turned against the term; the outliner is a window on Q, not a HUD plate; every strip tip goes through the popup, one look, one delay.
- **Two defects the tests caught in my own tooling, worth keeping.** A heredoc escape turned `"\n"` into a real line break inside a string literal; the tip join then carried a CRLF the plain tip did not, and the only symptom was a test comparing two texts that looked identical (found by diffing the bytes). And the first windowed capture of the popup was 600 px tall round three lines: a wrapping Label reports its minimum height for the width it had before layout.
- **Mutation checks**, each seen to fail the walker: a hard-coded issue operand (survived the first probe, which compared the satisfaction line too -- the probe now reads line 0), a dropped `child_id`, a debt path printing `0.0` for no history, an unfiltered `pinned`, a wrong shortage order, a bad row window, a popup closing on level 2, a zero grace, a hover signal never connected.
- **The `.import` files** the editor rewrites on every `--import` stay out of every commit, like `project.godot`.

**V4.8c -- MESSAGE SETTINGS AND THE LEGEND'S GRADES -- IS BUILT on `v4.8c-messages` (2026-10-17). No `src/sim/` diff, `SAVE_VERSION` unchanged. V4.8 closes here.**

- **Contract and instruments: [panel-system](panel-system.md) §21.** `src/ui/message_settings.gd` is a register of severity thresholds per category per switch (notify / feed / popup / pause), persisted under `[messages]` in `user://settings.cfg`; the settings screen draws it as a grid.
- **Author call at the plan gate: pause defaults to Major+.** A minor arrival keeps the clock running. Notify, feed and popup default to All -- the game's behaviour before the block.
- **The arrival pause's contract is replaced by name: the lapse guard.** A quiet arrival is unseen but does not hold; in its last month (`months_left <= 1`, defaulted on the next tick) it holds the clock and gets its card. Tested through `Events._tick_countdowns` itself, so a guard one month late fails as it would in play (mutation-checked).
- **Why thresholds, not booleans:** a category has no severity; its events do (`ev.severity`, already on every desk entry). The history record carries no severity, so the ledger reads the event's own -- no sim field added.
- **The legend** gains three Political-layer count rows from `Roster.counts()` (new, counts through `grade()`); the caption no longer claims "every nation the game simulates" is the whole map.
- **Review: 2 passes, bar "changes what a player sees".** Pass 1 (self) clean. Pass 2 found one: a quiet arrival's card stays up while the clock runs, but its "N months to answer" was written once at push, so the guard's last month showed the arrival's number. Every live decision card's deadline is now re-read each month (`_refresh_decision_bodies`, mutation-checked). `test_playability.gd`'s arrival-pause pins now set pause-at-All, so they no longer read the machine's own `settings.cfg`. Known and left: a loaded save's desk entries are not in the unseen set, so the guard does not cover them (V4.4's existing load rule; interrupts still hold).
- **Refused:** filtering the "Decided for you" card (it is the evidence a lapse happened); hiding desk entries under feed (the desk is the answer surface); a per-(category, severity) grid of 108 toggles (the threshold says the same in 36).

## V4.11

**V4.11a — THE NEIGHBOURHOOD'S TWELVE — IS BUILT on `v4.11-neighbourhood` (2026-10-15/16, a1 + a2): the roster is 41, the twelve simulated and not playable (NOR ISL SRB TUR ALB MKD MNE; BIH UKR MDA XKX BLR), `SAVE_VERSION` 39 → 40 on no field (V3.3's argument). Register 277 regions, 1 373 cities, 640 edges (623 land + 17 sea), one component. Plan: `docs/superpowers/plans/2026-10-15-v4.11-the-neighbourhood.md`.**

- **The grade is DERIVED, not stored** (author's call): `src/core/roster.gd`, `playable` stays the one bool; outlines are the world register. The handoff's three-value fold would have migrated 41 files to say what `playable` says.
- **THE 29 STAYED BYTE-IDENTICAL**, checked after every import: pooled statistics AND the motorway-endowment mean on `ANCHOR_POOL` (the endowment mean was the one the plan did not list -- Norway's first import moved every region's endowment); the World Bank cache MERGED, not re-pulled (a fresh pull re-vintages); `firms_generate.py` draws the 29 first on its frozen stream (ALB sorts before AUT).
- **Two kinds of region.** Seven neighbours ride GISCO/Eurostat (Turkey at NUTS 1). Five have no NUTS: Natural Earth admin-1 dressed as NUTS (`inject_admin1`), Bosnia dissolved to its entities, official population shares (the GeoNames city proxy measured badly urban-biased), PROXY_SERIES economics, the national World Bank crude rate for natural change. Crimea and Sevastopol are outside the register (Natural Earth's assignment, a bound). Cross-source adjacency: a tolerance rule swept against the real map.
- **Gaps filled from measured sources only**: OWID (CC BY) and Eurostat `nrg_ind_id` where the World Bank publishes no year; NBU and KAS for the exact-year labour figures. Two load checks widened for real regimes (inflation anchor 20 → 40; natural change 2 → 3 for Southeastern Anatolia's +2.07). Belarus's anchor drops its 1999-2000 hyperinflation under one rule for every nation (34.8 → 18.5).
- **a1 committed ONE RED TEST BY THE AUTHOR'S CALL** (`test_trade`'s counterparty gate): `even_share` = 1/partners diluted as small partners joined (Britain's accept scores +0.22, Italy past the gate). a2 made it per nation, `EVEN_SHARE_SCALE × Σw²` (effective partners), the scale MEASURED on the 29 (0.4054) so the mean yardstick there is the old 1/28 and NO threshold was re-tuned; majors refuse again (FRA 0.67, DEU 1.04, ITA 0.94 vs 1.20).
- **THE RE-BASELINE HELD**: `tools/balance_probe.gd`, `main` vs tip from worktrees: **0 outcome flips of 94**, 50/50 invariants both sides, 582 of 1 724 lines moved, every one inside the seven predicted channels (trajectory drift through trade gravity and commodity prices; three verdicts through the even-share redefinition -- FRA's DEU pact signs, an agreement partner BEL → LUX). No stray line after the last invariant.
- **Tick probe +12**: month mean **218 → 392 ms** (Diplomacy 70 → 159, Economy 37 → 76 -- the N² of (41/29)² ≈ 2.0; the even share adds ~13 % of Diplomacy's growth). Recorded for the author: the real month now sits above the 300 ms the V4.6 synthetic probe was banded on.
- **Frame probe**: deep zoom unchanged (~1.6 ms map cost, the 2.0 ms gate); opening fit 8.0 → 10.0 ms. PANNING at the fit went 51 → 133 ms from Natural Earth's 1:10m density (Ukraine 19 652 region vertices) and back to 73 after the drawn geometry was simplified to GISCO density -- the rest scales with the twelve's real geometry; pan cost was over budget before V4.11 and belongs to V4.10's map pass.
- **V4.11b -- REAL ENDOWMENTS AND THE WORLD POOL (b1 `a44e8fd6`, b2 re-baseline).** Raw and agri goods get each producer's real share of world production (`tools/endowments_generate.py`: USGS through OWID, OWID energy, FAOSTAT, the WNA uranium table authored with its citation); the 133 outlines get a register with GDP (`data/world/outlines.json`) that `Roster.grade` reads; natural goods route BEFORE production on requirement minus endowment, the outlines trading as one world pool. No save field. Bands (`tools/endowment_probe.gd`): (i) natural goods open within 0.01 % (scoped to natural goods -- the manufactures' drift predates the block), (ii) EU import share 0.987-1.000, (iii) a 50 % pool cut hits the clamp in two months (dose: 5 % / 10 % / 20 % cut read 1.057 / 1.117 / 1.255), (iv) nothing pinned at 120 months -- all PASS. **THE RE-BASELINE IS BYTE-IDENTICAL** (balance probe, 1 724 lines, base `d6a24346` vs tip; events probe likewise, every band PASSED): the price-high hook has no consumer and value added feeds no GDP, as predicted. Recorded: clothing now crosses 1.25x at month 96 (was ~160) beside a manufactures wave at month ~84, cause not isolated (likely the static world volume -- `someday`); the Commodities tick 40.1 → 46.5 ms. The first §8 clause (route on population want) was WRONG and corrected before commit: Germany's steel stopped.
- **V4.11c -- THE SURFACES (C1 `662f38d2`, C2 `cac34f5d`, C3 `da758368`, C4 `f007c5fc`).** An outline can be READ on the map: hovered where no roster nation answers, it restrokes brighter and a readout gives its name and its top three goods by share of world output (`src/ui/map_outlines.gd`, a pure function of the loader; Russia: natural gas 15 %, crude oil 12 %, nickel ore 6 %). Its own hit test over `_world_polygons`; `_nation_at_lonlat` stays roster-only, so an outline is never clicked, selected or sent as `nation_hovered` -- pinned by a source check and mutation-checked. The readout anchors where the cursor entered and redraws only on a change (a full map redraw is ~73 ms at the fit). The first readout was bare text and the windowed screenshot showed it unreadable over snow and labels; it sits on a HUD plate (brass top edge). The nation panel says "Simulated nation — not playable" for every nation without `playable` -- 37 of the 41, Italy as much as Ukraine -- and nothing for the four playable (author's call; the first wording said "neighbour" and the review caught it on Italy). **Author calls at the gate:** readout on the map only (the legend and outliner are V4.8's); portraits for the twelve SKIPPED (recorded in `someday`); the grade line only for simulated nations. Screenshots judged windowed: fit, Balkans, Ukraine/Belarus, the Russia and Algeria hovers, Ukraine's panel. Frame probe NOISY (the no-map control row doubled, 0.84 → 1.70 ms), so the +1.8 ms at the fit is unattributed. `tools/screenshot.gd` gains `--hover-outline <ID>`.
- **The block's xhigh review (on PR #3, pass 1: 9 findings).** FIXED, each with a test that fails on the old code: the grade line called Italy a "neighbour" (only four nations are playable -- the docs' "29 playable" was wrong too); a natural good's `output` was the post-trade holding, so the commodities panel showed imports as made AND bought, and value added counted every imported unit on both sides (now: made here net of own use, before trade; an importer's consumed ore comes off its value added); the outline readout outlived the cursor leaving the map (cleared on mouse exit). RECORDED, not fixed (no player-visible change): the natural goods' `demand` register is `_want` while routing reads the requirement, so coverage and the import-dependency layer divide by a figure the routing never used; `target_terms` recomputes the exposure yardstick per target and accept/refusal/pact terms build the trade vector twice (Diplomacy's share of the 392 ms month); the hover ring strokes its rings unculled. **Pass 2** (2 findings, fixed): `tools/endowments_generate.py` read every energy producer at the world's latest year, and OWID's small-producer series end in 2016, so 19 roster nations' oil (Germany's, France's, Poland's), 16 nations' gas and six nations' coal read zero; Kosovo's lignite fell through a blank OWID code. Each producer now reads its own latest year within ten. Re-probed: bands PASS, crude oil's EU import share 0.976, clothing no longer crosses 1.25x (1.202 at month 120). **Pass 3** (GLM 5.3 over the fix diff): no findings.
- **Reviewed twice**: Sonnet (5 risks, 1 question) and GLM 5.3 through OmniRoute (`zai/glm-5.3`, thinking disabled; `zc/glm-5.3` fails in the container) -- fixes landed: one trade basis per yardstick in retaliation, hoisted even shares, loud import gaps, a test that could not fail.

## V4.5

**V4.5 — THE COUNCIL, CONTESTED — IS BUILT on `v4.5-council` (2026-10-14/15) in three parts: a (the machine), b1 (the content and its probe), b2 (the panel). `SAVE_VERSION` 39 UNCHANGED (argued in `game_state.gd`).** V4.5a: `src/sim/council.gd`, `council_constants.gd`, `ratification.gd` -- sponsors (a nation; the face and drive are its live head of government's), lobbying, three bargaining currencies (favour / aid on the transfer line / vote trade), unanimity with vetoes beside QMR, a calendar-derived presidency plus paid tabling, and ratification at home through `Legislature.resolve_vote()` (one rejection kills the treaty for every member); INERT on the then-current content by construction. V4.5b1: 34 proposals, the presidency orders, `tools/council_probe.gd` (C1-C6) and the bands. V4.5b2: the council block in the orgs panel, the ratification card, the desk mark, the calendar deadline, the top-bar Europe figure, `tests/test_orgs_panel.gd` and the screenshot flags. **AUTHOR CALLS:** chair window K=3 (an AI chair chooses within a window of three); the IOU settles at ratification, not at the council; the sponsor votes for its own proposal; one opening per 6 months; ratify window 5 months; NATO G1 waived; C1 kept as declared. **BANDS (V4.5b1, final):** C1 BOUND 0.050 (kept as declared), C2 PASS 8.60 (fragile), C3 and C4 PASS, C5 2.215 raw, C6 BOUND 5. **THE b1 RE-RUN (51 regimes, predicted before it ran): HELD, with three knife-edge LOST to HELD flips at the 2032 presidential (+0.3 to +0.5 vote points)** through the declared channels (agenda cadence, unratified treaties falling, rules in force, collective tariffs). WHICH channel lifts the incumbent despite a heavier burden was not isolated -- an open attribution question, recorded in [docs/orgs-model.md](docs/orgs-model.md) §V4.5. b2's decisions: a deadline verb outranks build order in `claim_primary`; the ratify forecast is the bill's blurred one; orgs needing action sort first. NOT BUILT: event hooks (no authored event needs them); the `Budget.project` bound stands (a projection never ratifies). Model: [docs/orgs-model.md](docs/orgs-model.md) §V4.5. NEXT: V4.11 — the neighbourhood (the signed order: V4.11 → V4.8 → V4.9 → V4.10).**

## V4.4

**V4.4 — EVENTS AT SCALE — IS BUILT on `v4.4-events-at-scale` (2026-10-07): the slot became a severity-ordered DESK, the quiet went per-category, hooks make the world watch you, chains arm consequences, the other 28 nations answer for themselves, and the book is 9 → 102 events across nine categories with 54 category-art plates — subagent-driven build on the Flash fleet, every task review-gated, two real machine defects caught by the loop (typed-array init crashes on `new_game`; the AI chooser routing fiscal effects through the player-scoped `Budget.commit` — fixed with a nation-scoped `apply_pending`).** THE MACHINE (`src/sim/events.gd`, one rewrite): `ns.event_queue` (QUEUE_MAX 4, severity-desc, dedupe by id, `answer()` by entry id beside the kept head-`choose()`), `event_category_quiet` (CATEGORY_QUIET_MONTHS 3 — the global quiet died with the slot), per-event `cooldown_months` back from the V1.8 cut (sparse until-months), the weighted pick a second PURE function (Cycle.unit over nation|category|sorted-roster|month against cumulative authored weights — the roster salt is the review's correlation fix), HOOKS read registers the machines already write plus three V4.4 stamps (`ns.repealed_at` beside the ledger's silent erase; `failed_month`/`bid_month` on firm entries; `ns.last_accession` inside `_flip_membership`) — vocabulary closed at `events_constants.ON_ACTIONS`, `election_lost` REFUSED WITH ITS REASON (a lost election ends the game; nothing could answer it), CHAINS arm at authored delays and deliver due-first (loader refuses unknown targets and cycles at load), and THE AI CHOOSER closes the sixth "no AI chooser" note AT THE RULE — minimal situational scoring (bloc-weighted response + fiscal/corruption/unrest terms), in-tick resolution through the one applier, never defaulted, determinism test-pinned; `once`/cooldown/quiet mark at DELIVERY so the 28 AI nations bind them too (the review's find — announce-only marking left them free). **SAVE_VERSION 39 on six registers, argued in game_state.gd** (a seventh, `event_hook_fired`, was removed at pass 18 as dead state); the no-stored-draw absence pins stand. CONTENT: nine category files (scandals 16, personal 10, fiscal 13, unrest 11, industrial 14, european 10, foreign 10, commodity 8, disaster 10), the six legacies moved and re-tuned (x0.2 likelihoods, five choices to the band), `crises.json`/`climate.json` retired, E1b's mean±0.008 and business-worst≤30% now `tools/event_lint.py` (it failed the five pre-band carried choices on first run, as an instrument should), and **`LIKELIHOOD_MIN` 0.005→0.002 at integration** — the V1.8 floor was calibrated at nine events for player-visibility; at 102 the floor's job is world-visibility, and the [6,18]/term cadence band is arithmetically unreachable above it (all-94-at-0.005 measured 22/term; the ×0.2 proportional book lands 12.0/term dead interior — escalation-authorized, the comment rewritten at the constant). Probes: `events_probe.gd` drives the REAL machine now — E4 cadence/overfull, E5 category spread (all ≤18.9% against 30), E6 8/8 hooks witnessed, E7 28/28 nations answering, zero defaults, choices situating. ART: 54 WebP plates (9 categories × 3 severity bands × 2 variants) on the V3.7 recipe, bytes-loaded, wired into the desk and the arrival cards; the photographic-vs-painterly lean and the contact sheet are the AUTHOR's eye ([docs/event-art-plan.md](docs/event-art-plan.md)). **THE RE-BASELINE (both sides from worktrees, 51 regimes): 0 identical, 24 outcome flips — 20 HELD→LOST at the 2032 second election, ONE-DIRECTIONAL through the declared default-drain channel (hands_off −2.0 approval by 2032; ~12 answers/term vs the slot-era ~4), the prediction's 1–4 a magnitude miss recorded as such — OPEN AUTHOR CALL, not tuned (levers: the defaults' authored means, CATEGORY_QUIET_MONTHS, or accept the bound; the verdict block lives in reports/v44-rerun-prediction.md).** Invariants 50/50, zero stray lines after the last OK (V1.7c), first divergence 2027 everywhere (the AI acts in year one, as predicted). Suite 104/104 (the two convergence-loop content tests included); names clean. Model: [docs/events-model.md](docs/events-model.md) §5/§6/§7/§8/§9/§11 rewritten AT the rule in the block's own commits. NEXT: V4.5 — the council, contested.**

## V4.2

**V4.2 — THE STATUTE BOOK — IS BUILT AND MERGED (PR #48, merged 2026-10-07) after a 20-pass version-close ultra: 63 verified findings, every one discharged (curve 10 → 11 → 8 → 6 → 5 → 3 → 5 → 1 → 2 → 3 → 5 → 1 → 1 → 1 → 2 → 1; the last three passes comment/copy-level only, per the V4.7 convergence standard). Composition (`src/sim/statute.gd`, drafting budget + the auto-derived `bloc_offset` price table, bands declared then swept by `tools/composition_probe.gd`), the per-law effect ledger (`ns.law_ledger`, REALIZED deltas — `SAVE_VERSION` 38, six registers), the repeal verb (a law like any other; constitutional/institutional-channel targets refused; the budget floor `_budget_removal` lands what the register holds), custom tax keys (the `nation_state.gd` sixth-key refusal rewritten at the rule; birth gates cap the base×rate product at wealth's own 12.0, reserved revenue-line names refused at birth via `Budget.COMPUTED_REVENUE_LINES` with a re-deriving pin, and the yield-cap offer gate keeps a re-passage past the ceiling unoffered), the tax panel (KEY_X, rate as a number), the bill briefing + two paid polls (fixed-forecast keyed on the purchase month; `src/sim/` knows no blur — source-scan pin), PMBs + chief-backed lobbying (the `assembly_bills` in-tray; endorse via `resolve_vote`'s DEFAULTED param), content 42 → 120 laws + `tools/law_lint.py`. Re-baseline HELD (51 regimes, 8 identical / 43 moved / 986 pairs, earliest divergence at the first assembly-division month — the assembly acts in the idle world). Suite 100/100. Model: [docs/legislature-model.md](docs/legislature-model.md) §ledger/repeal/composition/assembly; the carried register (refuted-but-real items with re-raise triggers) lives in [docs/someday.md](docs/someday.md). OPEN: the P1(ii) effects-blind-divisions author call, and the V4.4 hooks the block already wired. NEXT: V4.4 — events at scale.**

## V4.7

**V4.7 — INDUSTRY — IS BUILT AND MERGED: V4.7a's two-tier register (PR #46, merged 2026-09-28) and V4.7b's autonomy machine (PR #47, merged 2026-10-02) — closed after a 15-pass version-close ultra over the cumulative diff: 99 verified findings, every one discharged (the curve 8 → 9 → 2 → 10 → 7 → 10 → 7 → 7 → 10 → 5 → 4 → 4 → 4 → 5 → 3; the last three passes comment-level only). B1/B2/B3 reviewed in-session, B4 close-out 2026-09-29. THE REGISTER: 317 majors + 2,420 generated body = 2,737 firms across all 29 nations, SAVE_VERSION stays 37 — the register is SPARSE (majors seeded only, entries appear when touched) and `_seed_missing_majors()` repairs pre-roster saves at the first tick (the PR #46 ultra review's headline: sparse + verbatim-restore + v37 = missing-key crash, four lenses). THE BLOCK'S SPINE (the step-0 finding): the subsidy's share channel is ABSOLUTE, not scale-aware — a 0.01 firm drains the same pool as a 0.14 major and ends a 60-month subsidy at 0.13 — so the pool is MAJORS-ONLY, `BODY_SHARE_MAX` 0.03, body firms never verb targets, and body reads fall back to authored content (`share_of_company`). The plan carries all amendments at the review that forced them.**

**B1 `src/sim/industry.gd` (2026-09-28): firms act — failures with a rescue window, foreign takeover bids, investment drift, relocation priced on V3.4's network — bands declared BEFORE the probe and corrected by it (`FAIL_BASE_MONTHLY` 0.0003, `RELOCATE_HAZARD_YEARLY` 0.002; idle band 0.62 failures/nation per 168-month run), NO rand anywhere (Cycle, private `industry|` key namespace), and the pins caught three pre-ship defects (a two-stage relocation draw dead by construction; `is_equal_approx`'s 1e-5 ABSOLUTE floor skipping real 9.8e-6 drains — the V3.6 lesson's third appearance; a failures-after-invest same-month leak). B2's five verbs ride the one `effects.company` channel (block/allow bid with relations pulses, break_up MAJORS-ONLY — the body-tier draft was the escalator's second appearance, court ×5, appoint_board in B3), and **rescue is a bailout gated on the WINDOW**: gated on `failed` alone it resurrected committed failures and undid break-ups. B3's surfaces: the companies panel's autonomy sections, the SOE chair line, and `pending.gd`'s companies cluster mark — V4.8's obligation landed a block early.**

**B4's re-baseline is THE FIRST NON-BIT-IDENTICAL RE-RUN IN THE PROJECT'S HISTORY, AND THE PREDICTION HELD (`reports/v47b-rerun-prediction.md`, written before the run): the idle world acts now, and the register is priced into national figures at four named places — jobs (`headcount` reads live share and 0 for failed → `firm_jobs_offset_pct` → structural unemployment), growth (`firm_impulse_pct` prices subsidies/burdens through the LIVE share), revenue (the dividend on live output), city (migration's `_jobs_by_city` — never printed). Result: 51 regimes, both sides from worktrees, 0 identical / 840 moved line pairs, EVERY one in a named channel's downstream (unemployment 395 rows, approval 382 lead), FRA's failure timeline shared and non-empty as predicted, `managed_subsidises` diverging at verb month + 1 (pre-failure), ONE verdict flip — `managed_bill_is_held` LOST→HELD on a 0.1-point vote-share margin through jobs→approval→poll, recorded not tuned — zero `characters:` acts, zero verb-answer lines, invariants 50/50, and the A3 clamp obligation closed (the ±2.00 impulse clamp did not newly bind; stay-off-every-clamp suite checks green; no re-sizing owed). THE HARNESS QUIRK THE RUN SETTLED: the full run is 51 regimes ending at REFERENDUM, with the unrest class already inside REGIMES — the `UNREST_REGIMES` dict duplicates three of them and is dispatched by nothing (cosmetic, recorded).**

**B4 ALSO FOUND THE TICK COST NO GATE COULD SEE: the scale probe predates B1 and times Companies only, so the machine's month was never inside a band — the re-baseline's wall clock ran 2.5× slow, and a scratch timing probe measured `Industry.tick_month` at 1,124 ms/month over the roster (~8 unconditional relocation Dijkstras per nation-month; the single draw with the discount inside needs the distance BEFORE the hazard). The memo (`_dist_memo`, keyed on the graph's structural hash — loader content is immutable post-load; it lives in industry.gd, not network.gd, because tests pass synthetic same-size graphs) carries it to 16.45 ms with no distance changed and no draw moved; suite 94/94 (the 94th is test_industry_surfaces.gd, the pass-5 fleet's net for the UI surfaces).** The V1.4 sweep's rival mirror in `companies_probe.gd` follows the majors-only pool by rule now instead of by accident of zeros; `--bid`/`--failing` staging flags captured two judged frames (`FOREIGN TAKEOVER BID — AUI offers € 4.3 bn for Granval Cooperative`, `FAILING FIRMS — Banque Méridienne, rescue window: 6 months left`), both stages writing the register exactly as the machine writes it and neither ticking afterwards (the windows lapse). Model: [docs/companies-model.md](docs/companies-model.md) §31–38; the V4.2 handoff's stub-or-defer clause is RESOLVED — lobbying DEFERRED, V4.2 builds it whole against the 317 chiefs. **Open: the author call on hand-curating the 25 generated nations' majors (narrow `firms_generate.py --check` to the body tier first), and V4.6's from_dict aliasing sweep for `plants`/`projects`/`sector_investment` (companies itself is fixed). Also carried open: the budget panel's per-frame 2×24-month projection (~4.5 s base, pre-PR-47 -- PR-46's finding 6; the machine's share of it is banded at 7.0 s in the scale probe's verdict). NEXT (AMENDED 2026-10-05): V4.2 is BUILT and owns the lobbying machine whole -- see the V4.2 row above; after its merge the order resumes at V4.4.**

## V4.6

**V4.6 — THE COMMODITY ECONOMY — IS BUILT ON `v4.6-commodity-economy` (2026-09-20): both step-0 gates discharged BEFORE a recipe was authored, the block closed in one session of its estimated 15–22 because the gates' verdict narrowed it honestly, and the re-run held its bit-identical prediction (both probe regimes, cold-worktree dialogue_manager noise isolated per V1.7c — the 19 moved lines were the baseline worktree's missing class cache, not content).** The gates (committed dd20c51, `tools/production_scale_probe.gd` + `tools/production_gdp_probe.gd`): the tick budget PASSED (29.3/5.2 ms vs the 300 ms band — the Victoria 3 late-game form is unreachable at this abstraction), and the GDP-reproduction probe FAILED ON LEVELS (Spearman ρ = 0.902 — the ordering of all 29 economies reproduced from population + sector shares alone — but worst relative error 0.822 against a 0.20 band). The finding, in the tier doc's own terms: the ABSTRACTION LEVEL was wrong, not the recipes — **the layer models GDP *changes*; the level stays the register's measured value; a per-nation productivity lever was REFUSED as circular** (fitted against observed GDP it reproduces by construction — the first probe draft did exactly that and was rewritten before it ran). The build: 60 goods in seven categories + 34 recipes (`data/commodities/`, loader-validated loud), `src/sim/commodities.gd` a leaf preloading only its constants, the seven-key `commodity_state` register on **SAVE_VERSION 37**, production in topological recipe order (the first draft grew steel from nothing because category order wasn't topological — measured, fixed, pinned), surplus→deficit routing, world prices clamped ±75 %, the tick wired after Economy before Opinion in `main.gd::_on_month_elapsed` (the plan named game_state.gd; that file has no month tick — recorded at the pin) and the balance_probe mirror, a lazy seed for an ABSENT register (a stripped payload, a hand-built fixture, or a caller before the first tick -- NOT a pre-37 bridge, since save_manager refuses a version mismatch outright; pinned three ways, including the stripped-payload leg), the Commodities panel (KEY_H, flow-coverage shortage alert — the register carries NO stock: a carried stock drove prices to 0.50× base in the prototype, measured and recorded), and two map layers in the existing registry. **T5's serialisation found a REAL from_dict ALIASING DEFECT** (two states sharing one register, found by measurement, fixed rebuild-style, mutation-pinned) and left the same hazard RECORDED LIVE for `companies`/`plants`/`projects`/`sector_investment` — predates the block, in commodities-model §6, waiting for its sweep. PRICE_ELASTICITY is UNVALIDATED (the world is born in balance); its sweep belongs to the first task that lets a player cause a shortage. Suite 90/90; model: [docs/commodities-model.md](docs/commodities-model.md).

## V4.3

**V4.3 — PEOPLE WHO WANT THINGS — IS BUILT ON `v4.3-people` (2026-09-18): the character machine, the deep bench, the surfaces, the V3.7 wall committed, and the re-baseline re-run bit-identical at the first ship (1681/1681, zero diff) then, after the review's channel fixes, EXACTLY THREE moved lines — the two `managed_censors` brief_against act lines the fixed channel exists to fire, 94/94 verdicts identical — with the bench GPU pass since harvested and the branch in PR #44 under review.** The machine: `src/sim/characters.gd`, a leaf preloading only character constants, the act constants, government (the price primitive) and legislature (the ONE applier), meters handed in by the caller (the calendar.gd law), ticks after Cabinet before Elections (pinned from source), player nation only, NO rand anywhere (pinned by two-identical-states). The content: `Person` grew to EIGHT fields — the seven of the character contract (kind/traits/ambition/party_id/wants, closed vocabularies validated at parse, cross-register halves resolved in `_validate_people` where the whole loader is in hand) plus `bench`, the portrait tiering flag. The state: **SIX registers on SAVE_VERSION 36** — the five planned plus `person_want_state`, the edge-trigger's memory (a denial straddling a save must not re-fire its grudge on every load). The events-model §3 and people-model §2/§4/§13 were rewritten AT the rule in the schema's own commit, and people-model §14 is the layer's model section.

**THE BUILD'S TWO MACHINE DEFECTS WERE FOUND BY THE BAND PROBE, NOT THE REVIEW — the bands did the work they were declared for.** The first sweep against the bench FAILED P1 (7 acts in an idle term, every one a `brief_against` by a person whose meter want was denied by the STARTING world): a want denied by the world the player INHERITED wrote grudge every month — V4.0's "prices the inherited cycle, not the record" in miniature. Fixed with the OWNERSHIP-LATCHED want settlement: a want the player's own decisions have never touched is inert however the world denies it, and once latched, a want that TURNS denied writes a grudge pulse and one that turns served a loyalty pulse — while a STANDING denial (the review's C2) accrues every month it stands, the form that makes the channel reachable (§14.6's arithmetic). The first sweep also fired FIVE DAY-ONE COUPS (seeded standing beat every incumbent on month one) — the already-won/lost defect class in a person's shape, fixed with `CHALLENGE_GRUDGE_FLOOR` (standing is the muscle, the grudge is what the player's choices write). The re-swept bands: **P1 PASS (0 acts), P2 the honest split — 4 distinct briefers fire under a held betrayal, challenges and resignations do NOT because escalation needs two-plus simultaneous denials and no authored person carries more than one meter want (the band's ≥2 gate prints FAIL on shipped content; the higher rungs are CONTENT-BOUND, §14.6), P4 bounded by construction (every price through `Government.penalise_blocs`, the accumulator the opinion model already clamps), P5 PASS.** The probe is `tools/characters_probe.gd`; verdicts recorded beside the bands in people-model §14.6.

**THE BENCH: 213 → 1,595 people (55/nation × 29), generated by the COMMITTED `tools/bench_generate.py` (deterministic RNG, seed fixed, `--check` mode), curated name lists (40 inline + 20 in `tools/curated_names/extra_surnames.py`), the kind mix from the plan, wants resolved against each nation's own registers, sidecar auto-seeded to 1,595, the 213 retrofitted with traits/ambition/wants and `bench: false`.** check_names went red ELEVEN TIMES on real-politician names the curated lists had snuck in (twelve names: two prime ministers, two presidents, a queen consort, a crown prince, a party leader, an MEP and three MPs — the names themselves are in the ban list, and are NOT spelled out here because check_names scans every committed file, which this row learned by going red on its own first draft) — each a real catch, each purged and regenerated, ending clean. The orphan rule needed its belt re-deriving: test_people's own `_check_no_orphans` was one rule-version behind the rescoped loader rule (a `party_id` references a person too) — updated to re-derive the rule independently so the two cannot diverge. Politicians generate with a party edge ALWAYS (the one orphan the loader refuses is a slot-less, partyless politician).

**V3.7 CLOSED INSIDE THIS BLOCK, per the signed gate: the wall is committed (61bb3bf) and the BENCH WALL IS HARVESTED (5b90233) — 213×5 emotion WebPs + 303 scene backdrops + 1,382 bench neutral busts, 2,206 rasters in total, zero people without art; the legacy PNG bridge and the 71 duotone PNGs deleted in the same commit as the wall; the completeness gate tier-aware (met cast 5/5, bench 1/1).** NO VISION PATH survived this session for JUDGING GENERATED FACES (the model has no image input — V2.3's honest gap again), but the GUI screenshot path worked and the PEOPLE PANEL IS PHOTOGRAPHED live (`.superpowers/sdd/frames/v43_people_panel.png`: character groups with counts, standing-sorted, want lines with their derived reads in tone) — what remains the AUTHOR's eye is the FACE verdict: the contact sheet at `.superpowers/sdd/frames/v43_wall_contact_neutral.png` and the counterpart review table at `reports/portrait_counterparts_review.md` (140 of 191 references fetched; reject-blind without eyes, so no rejects were applied). The generator grew `--bench-neutral-only` (reading the register's own tier flag) and the bench generator grew `--regen-wants` (rebuilding bench want lists when the MIX changes — the meters-first fix needed it). Suite 87/87; the two new tests (test_characters' structural pins — leaf property, tick order, single writers, determinism, idle silence; test_surfaces_people's scanner — no hand-written person lists under `src/ui/`) are registered in `run_tests.sh` at authoring time.

**Session-level notes a future session needs:** `trait` is a RESERVED WORD in Godot 4.7 GDScript ("Expected variable name after var") — the local is `trait_name`; `test_summits.gd` carries its own copy of the SAVE_VERSION pin (one more to flip on every bump); `test_state_copy`'s reflective dictionary walker now has `_dict_sentinel` for typed dictionaries (the float sentinel errored against `Dictionary[String, String]`); both coder dispatches died upstream rate-limited (T2 completed in-session from the first dispatch's partial, the review-subagent wave DEFERRED to the follow-up — the T1+T2 self-review found and fixed the meter-key-at-parse and the premiership trailing-segment holes); String has NO `strip_punctuation()` in 4.7. The re-run prediction + verdict: [reports/v43-rerun-prediction.md](reports/v43-rerun-prediction.md). **The follow-up standard review (2026-09-20) found two machine defects the bands could not see — a completed programme entry counted as ALIVE (oppose-stance authors billed for ever; fixed with a term gate + alive-only read, pinned in test_characters) and a fired challenge never reaching the premiership (Government refilled from the authored edge; fixed override-first in `_describe`, events_panel's leader line with it), both proven harness-silent (no regime touches Programme; challenges never fire there; hands_off/managed byte-identical against a 72ad3dd worktree, reports/stdrev/). The record fixes: §14.2's trait table matches the shipped constants, the LOYALTY_ACT_COST/GRUDGE_ACT_RELIEF paragraphs name the right valve, the six-register comment sweep, the want voice moved to person_card's shared tables, the probe's .uid staged.** Model: [docs/people-model.md](docs/people-model.md) §14. The block's plan: `docs/superpowers/plans/2026-09-17-v4.3-people-who-want-things.md`.

**THE 2026-09-16 COMPUTER-VISION PLAYTEST'S SIXTEEN FINDINGS ARE CLOSED (2026-09-17): twelve fixed at the surface, three dissolved under measurement or the probe, and the perf headline was the instrument's own artifact — one branch, `playtest-2026-09-16-repairs`, ten commits, two review rounds, suite 85/85, names clean, `SAVE_VERSION` stays 35 and `git diff main..HEAD -- src/sim/` is EMPTY (the re-run was never owed).** The fixed: **B1** the top bar's vote figure gets the zero-and-past branch its own tooltip always had (`-44 mo` reads `now`/`—`; the tooltip says the vote has been held) — the STALE DATE underneath (Elections never advances a termed-out player's clock) is sim behaviour and is recorded OPEN, not fixed; **B2** the defeat sentence lives in `_sections` beside the termed-out paragraph (an autowrapping `PanelKit.line` with no expand inside the ALIGNMENT_END footer HBox collapsed to a one-character column), pinned headless by placement AND geometry (826 px wide, 2.2 lines) and re-photographed on both defeat frames; **B3** both countdowns NAME their clock off the loader's own titles — the bar's tooltip says "The vote for President…", the Society window says "Next Assemblée nationale election:" — with polling's arithmetic routed through the shared `Trends.months_text` and the loader handed over at BOOT (round two's find: without it the panel printed the generic "assembly" until the first load disagreed with itself); **B4** `MessageStack.set_body()` — the "Your term" card ages in place every month (position is the card's age in a front-dropping stack; dismiss-and-repush would jump it) and is TAKEN AWAY at `months_to_vote <= 0`, verified absent ten years in; **B5** the Political caption and the nation-panel sentence are rewritten count-free ("ten" had been wrong since V3.3's 29) and a `test_playability` scanner forbids counted-nation copy anywhere under `src/ui/`; **B6** labels draw ABOVE the city crosses (project pins stay last) behind a 3px `draw_string_outline` halo that replaces the 1px offset shadow — judged clean at 2× over Alpine snow, a crisp dark border where the old evidence frame lost SWITZERLAND entirely; **B8** a trip inside one month prints the month once ("MAR–MAR" was always a duplicate); **B9** the energy run cost carries its `% of GDP a year`; **B10** the deficit figure is relabelled BUDGET BALANCE on the author's call — the signed value it already printed (`+` = surplus) unchanged; **B11** legend key samples draw opaque brass at 2px through panel-local `KEY_LAND/KEY_SEA` while `MapNetwork`'s own alphas stay untouched; **B14** the screenshot harness help names the real registry ids and an unknown `--open` push_errors the valid list instead of photographing an empty map; **B16** the save dialog — every slot dated (mtime, `--` on unreadable, never a confident zero-time), per-slot two-click delete, the hotkey trap closed (letters open nothing behind the dialog, Escape closes it), all close paths unified through `panel.close()` which restores the pause menu it was opened from (the settings panel's own contract, pinned for BOTH origins), and the test suite's save cleanup covers all eleven `__test_` slots so `user://saves/` no longer lists them to players.

**THE THREE THAT DID NOT NEED CODE, AND THE PERF VERDICTS — measured, not argued.** **B7** (panels clip their lower content) is NOT a defect: a throwaway headless probe drove each named panel's own inner ScrollContainer to its bottom and every photographed tail (the last law row's Force button, the EFFORTS entry, the fifth organisation, the fleet ledger, the EP section) came INTO VIEW — the real question is affordance (a 10px scrollbar nobody notices), the fold-hairline generalisation to inner scrolls is DEFERRED, and the probe itself was deleted per the scratch rule; **B15** `--network`'s byte-identical frame is content-fits by construction (both scroll levels at zero range at that state); **3.1** the famous 2.24-second accessibility month was the PROBE's own warmup tick recording the one-time Dijkstra-cache build it existed to exclude into `max` — `_us.clear()` after the warm tick is the whole fix, and the game was never freezing: `main.gd` warms the cache at boot, the LOAD path re-attaches the same `loader.region_graph` instance the warm keyed on, and `duplicate_state()`'s deep copy hits the value-keyed cache at 1.8 ms (V3.7's lesson holding). The corrected instrument reads the accessibility loop at 708 µs mean / 924 µs max and the month at 133 ms. **Recorded open:** 3.2 pan fps (the documented map re-record lever), 3.3 the loading screen (feature work — 15.8 s to the game scene with nothing saying so), 3.4 the ownerless 15 s stall, B12 (month-0 dash placeholders, a product-copy call), B13 (the Summit ObjectDB leak, one run in 105, no repro), and the hover-label shadows in `MapCities`/`MapMarkers` whose comments still describe the replaced 1px technique (review P2 note).

**TWO REVIEW ROUNDS, BOTH LANDED BEFORE MERGE, AND ONE GATE INCIDENT WORTH ITS OWN PARAGRAPH.** The first pass (before the specialist reviewer models were reachable) found three P1s: slot names reached `user://` paths unvalidated — now `SaveManager.valid_slot_name()` refuses separators, traversal, whitespace and Windows device names at the SOURCE, `save_game` and `delete_slot` both pass through it (delete trusts nothing); the termed-out verdict was printing its defeat line TWICE (the duplicate only became visible when the footer stopped crushing one copy to a column — now `defeated and not termed_out`, pinned one-sentence-per-verdict, and the ghost-label trap — `queue_free`'s copy still readable same-frame, the fold finding a third place — is filtered in the check); and the close-path fix above. The second pass (the `code-reviewer` specialist, once its model was available) returned approve-with-fixes on two one-liners: a merged comment had silently commented OUT the polling fixture's `Budget.commit` (the suite stayed green on a fixture that no longer did what it said), and `save_game` lacked the boundary guard its own new comment claimed — both fixed, and the Escape-priority comment now states the choice (dialog first; an armed reticle under a MOUSE_FILTER_IGNORE holder survives one press) instead of a false impossibility. **The gate incident:** Mimosa's commit gate force-blocked the first Wave-1 commit on the playtest's OWN driver scripts — `reports/playtest-2026-09-16/raw/*.py` are SSRF-shaped vision-API clients in a GITIGNORED evidence folder, and the hook scans the whole tree with no exclusion mechanism. The 18 scripts are archived byte-preserved into `raw/playtest-scripts-archived-2026-09-17.zip` with the README noting it — **a future session that drops any HTTP-client script into the working tree will hit this block again.** Screenshot verification: six frames captured through the project's own harness and judged in-session (vision path working) — the defeat modal, the ten-year bar (`NEXT VOTE —`, `BUDGET BALANCE −6.74%`), the legend caption and key rows, and the Alps zoom. Model: [reports/playtest-2026-09-16/report.md](reports/playtest-2026-09-16/report.md) — read-only, nothing in it was modified except the archived scripts and its README row.

## V4.1

**V4.1 SHIPPED THE PROGRAMME 2026-09-15 — the agenda register, the decaying
credit channel at span 4.5 with the gate PASSED, and the game's first answer
to "what are you for".** The machine is `src/sim/programme.gd` (a leaf, four
statuses and no flags — `active → complete|fail|invalid` once, precedence
complete > fail > invalid > timeout, the term-start gate a LEVEL READ of
`months_in_term`), `_load_programme` refuses off the field whitelist loudly,
`SAVE_VERSION` 35 on three serialised pieces (`programme`,
`programme_chosen_term`, `programme_stock`; progress deliberately earns
nothing). The channel is V4.0's declared decaying form driven without the
wait: pulses ±1.0 symmetric by construction (invalid zero-pulse) into a
stock bounded [−1,1] on a 14-month half-life, `programme_credit =
PROGRAMME_SPAN × stock` beside the honeymoon inside `Opinion._tick_nation`,
tick order Programme→Opinion→Elections PINNED at source (Elections is the
stamp pair's only writer and runs last — moved between the pair, a won
election would eat the pulse). **Sweep: PASS** — response exactly linear
0.25 points/unit, P1 +1.125, P2 −1.175, P3 +0.000 to the bit, P4 bounded,
P5 14 vs 13.86; the band is one-sided-up, crossing 4.0 grid-independent by
the linearity, V1.5b's midpoint diagnostic degenerates and is recorded as
such. Content is 37 entries in five groups (economy 9, institutions 7,
europe 7, society 7, office 7); the review's CRITICAL was the
already-won/lost class — co2e fail lines inside their own `possible` bands
offered five nations a FAIL at tick one, and nine ungated entries were
already-won/lost at playable start figures — fixed with authored bands (the
open interval between an entry's own complete and fail lines, unresolvable
at the offer by construction) and the triviality sweep widened into a
mutation-checked suite gate. Pledges stayed APART on a shared read, not a
shared schema; `COMPETENCE_SPAN` stays 0.0. Surfaces: the Agenda panel (K),
a top-bar strip hidden while nothing runs, a never-silent Overview PROGRAMME
section, cards on open/complete/fail/invalid, and the term start as an
arrival pause idempotent and subordinated to the election verdict's. Two
review finds fixed: the agenda icon untracked (fresh-clone class,
force-added) and the boot pending-mark firing before the card it marks.
Suite 85/85. Model: [docs/programme-model.md](docs/programme-model.md) —
its §10 holds the close-out record and the re-run result. The final review fixed three: the offer gates on
not-already-failed (`available()` skips an entry whose authored `fail` trigger
is already true — the mid-game reopening of the already-lost class, which no
authored band can close because the offer re-fires against drifted figures;
deliberately one-sided, an already-WON entry stays offered and the test pins
it), `REQUIRED_FIELDS` is enforced at load (a missing required key or a blank
`summary` is a load error — all 37 entries already carried one), and §4's
shared read SHIPPED: the Campaign panel's Promises section opens on the term's
programme through a new `Programme.this_term()` pure read that replaced the
`chosen_term == terms_served` filter previously hand-written in the agenda and
overview panels. Two limitations recorded in §10, not fixed: the zero-goal
`down` bar draws 0 % until the figure moves (prog_in_the_black), and a
decision event answered after the same-month election dismissal can eat the
term-start pause — three boolean pausers, one clock — with the offer staying
answerable until Elections next advances `months_in_term`.

## V4.0

**V4.0 MEASURED THE AGENCY CALL AND THE LEVEL FORM MISSED ITS GATE — the
verdict is FAIL and the channel's form, not its span, is what missed
(2026-09-14).** The competence-credit channel shipped as designed
(`Opinion.competence_credit`, one addend in the per-bloc target beside
`time_in_office_offset`, three terms — jobs/deficit/growth vs the inauguration
figures, uniform across blocs, no `SAVE_VERSION` move) and the sweep found the
form wrong: **C1 is unreachable at any span** because the level form prices the
WORLD, not the record's policy component — at month 6 the fresh-game cycle has
France 0.4 % below potential (growth 0.08 %/yr vs a 1.31 % trend), so the
growth addend reads −0.31 for EVERY style including idle before any policy
moves, the response is exactly linear in span with a NEGATIVE slope for every
style, C1 needs span ≈ 45 while C3 caps it at ≈ 1.02. `COMPETENCE_SPAN` ships
**1.0 as the C3 bound**, not a tuned value; the negative control (`budget-bad`,
acts with worsening outcomes) held at every candidate — acting badly is
punished MORE the louder the channel. The verdict is wired into
`tools/agency_probe.gd` (PASS needs C1 ≥ +1.0 AND C2 ≤ 0.0). **The declared
next route is the decaying-credit form (docs/agency-model.md §2's refused form
2), then activity-keyed drag — its own scoped block, never a silent extension
of this one.** The two standing obligations discharged: `QUALITY_SCALE_PP`
re-fit 4.5 → **6.75** (the V1.5a delivery-under-announcement rule restored at
ratio 1.125, the V3.0 inversion repaired not retired), and the
Eurozone/Schengen zero-price band measured to a bound (~60× short of the
poll-noise floor at the loader's ceiling; the euro side has no code channel at
all) — recorded in `docs/orgs-model.md`'s deliberately-absent list. The re-run
held with one recorded prediction miss: 821 line pairs moved in 51 regimes,
49/51 verdicts unchanged, two election flips (`managed_then_austerity_settles`
LOST→HELD through the declared unrest-act channel; `ruinous` HELD→LOST on a
23.6→23.2 knife-edge the prediction wrongly called unreachable — recorded as
the miss, mechanism is the two declared channels, not a third). Suite 82/82.
Model: [docs/agency-model.md](docs/agency-model.md). **V4.1 follows and names
this channel verbatim — its handoff carries the agreement clause.**

## V3.7

**V3.7 shipped the portrait wall's PHASE A 2026-09-12, and the block's
central promise held: the whole generation stack is built, wired and tested
with the GPU never fired — `sources/` and `assets/portraits/` are untouched,
`SAVE_VERSION` stays 34, `src/sim/` gained exactly one declared line
(`summits.gd`'s draw dict carrying the new inert `scene` string) and the
balance re-run was bit-identical per prediction.** What exists now: the trait
sidecar (`tools/portraits_traits.json`, 213 ids seeded, hand-editable, sex at
0.35 female against the measured 12.7 % wall), the region/role/wardrobe
prompts with the likeness policy ENFORCED (`--self-check`, gated by
`tests/test_portraits.gd` on every suite run), three workflow templates proven
against the live node graph (`tools/workflow_check.py`), the rewritten
post-pass (mask→alpha bytes, **WebP q90 lossy — and the signature story is
the review's P0, recorded straight because the next session will trust it:
`Image.save_webp(path, lossy, quality)` — the second argument is LOSSY, so
the handoff's `save_webp(path, true, 0.90)` was correct all along and the
plan-time "correction" to `false` shipped the LOSSLESS encoder with quality
ignored. The code review caught it before any asset existed — Phase A writes
none, exactly the silent class the suite cannot see — and a size comparison
pinned the semantics; the committed call is `save_webp(out_path, true,
0.90)`**), and `portrait.gd` rebuilt around
`framed_for(id, size, emotion, scene)` with the `Staged` composite and its
per-scene tint grade as Phase B's dial. **The LEGACY PNG BRIDGE is the load-
bearing consequence**: the repo holds new code and old duotone PNGs, the game
is playable and 82/82 green, and the bridge dies in Phase B's assets commit —
signposted temporary; do not let it rot. Two findings to inherit: Impact Pack
V8.x split `UltralyticsDetectorProvider` into ComfyUI-Impact-Subpack (the
handoff's five-class check failed until it was installed), and the emoji's
`test_hud` contract was re-anchored to the face (bands 55/45/35; the first
full-suite run caught the stale read). **PHASE B IS UNRUN** — the ~2.5 h GPU
pass fires on the author's word alone; runbook: three-person slice first, the
contact sheet is the gate, the legacy branch deleted in the assets commit.
**The V3 tier closes at V3.7, not V3.6** — the retrospective and every open
call (V3.0's gate routes, V3.5's loader-gate ack, Phase B) are in
docs/tiers/v3.md's close-out section, handed to the author in one place.

## V3.6

**V3.6 shipped ceremony, sound and the front door 2026-09-12, and the row's
"small" held: three machines and one told line on surfaces that already
existed, one new `src/` file, and `git diff main..HEAD --stat -- src/sim/
src/core/` EMPTY — `SAVE_VERSION` stays 34, the re-run prediction was
bit-identical by construction and no balance re-run was owed (V3.1/V3.4's
U-track precedent).** The sign-off was taken on the plan's four defaults
(author's "execute"): synthesized sting and its timbre, the default told-line
copy, the 300 ms degrade clause, sound defaulting On.

**The front door is the game's own map, and the plate decision is the record.**
`menu.gd` builds a throwaway `GameState.new_game(loader, "FRA")` — month 0,
measured at **20 ms** against the pre-declared 300 ms degrade clause
(`tools/menu_boot_probe.gd`, threshold written before the probe ran) — and puts
a real `map_view.gd` over it under a 45 % scrim. The refused alternative is
recorded because a later session will reach for it under balance pressure: a
reduced static drawer reading only the loader duplicates the lon/lat->screen
projection map_view's header calls "the one transform" — the two-copies trap.
Month 0 is clean by construction (unrest ring, campaign ring, markers and
plants are all empty before the first tick), the plate is `MOUSE_FILTER_IGNORE`
set AFTER `add_child` (map_view's own `_ready()` claims STOP and clobbers an
earlier assignment — the ordering bug the first draft had), and it has no
`_process`: the door never redraws.

**The tally is a reveal over the computed result, and its skip path is two
paths on purpose.** Each bar's final is recorded at build time and the bar
starts empty; a Tween (1.2 s, 0.08 s stagger, time-based — never
frame-counted) walks them out; any click on the plate finishes it through
`_gui_input()`; Continue is live from frame one and its press is NOT the skip
path — a click that lands on it is a dismissal the player meant, and a
ceremony that could eat that click would be a ceremony that ate a result (the
handoff's own sentence, kept). The test found the shape of "settled":
`bar.value` round-trips a 32-bit property against a 64-bit `final`, so settled
is a 0.005 tolerance and not an equality — the printed digits agree and the
last bits do not.

**The sting is SYNTHESIZED, which is the block's load-bearing refusal: the
handoff's audio obligations dissolved wholesale rather than being met.** No
licence, no ATTRIBUTION row, no committed binary, no `.import`, no bus layout
in `project.godot`, no fresh-clone audio question — the fonts'
bytes-not-`load()` discipline exists because a font cannot be generated, and a
chord can. `src/ui/sting.gd` is a D-chord toll (D3-A3-D4, 1.4 s, -8 dB, 12 ms
attack) as PCM into an `AudioStreamWAV`, cached in a static, byte-identical
across builds (pinned), one self-freeing `AudioStreamPlayer` per election.
`SettingsPanel.sound_enabled()` reads `settings.cfg` at PLAY time (not boot),
so the pause menu's change governs the next sting with no second wiring path;
settings.cfg grew `[audio] enabled` (default true) and the settings screen's
"there is no audio" header sentence was rewritten in the same commit. The
fallback route (a recorded CC0 file and the obligations it re-opens) is in the
plan's audit section if a later session wants a real instrument.

**The told line is the V3.0 probe's route 3 stated in the game's voice, once.**
"The vote follows the economy with a lag. A term that ran the country better
can poll worse than one that did nothing." rides the verdict's attribution
block only (the test counts once on the double-election panel — the first
draft printed it per table). It states the measured bound — approval prices
CHANGE, not level; budget-spend approval 38.1 vs idle 49.4 while unemployment
6.95 vs 7.58 and the deficit halved — and **resolves nothing: V3.0's three
design routes (competence-credit channel, activity-keyed drag, accept the
bound) remain the AUTHOR's open call**, handed to V3.7's tier close-out to put
before the author in one place, which is this block's outstanding obligation.

**Two test findings to inherit.** The double-election panel's text is counted
at the geometry frame because `show_results()` reaps its predecessor with
`queue_free()` — same-frame reads see the ghost's copy (the fold finding, a
third place). And `ConfigFile` has no per-key erase, so "the default fires on
an absent key" is tested by rebuilding the file without the section. The
screenshot pass found NO BUG — the menu plate, the tally mid-fill and its
settled frame were all judged clean in-session (vision path verified working
this harness first). Suite 82/82; names clean; frames in
`.superpowers/sdd/frames/`.

## Test-suite cockpit

**The test-suite cockpit shipped 2026-09-11** — the gate is one execution core,
`python tools/suite_runner.py --ci`, and the measured wall moved **51:56 → 9:18**
(parallel + per-check sharding, 82/82 held at every step); the model doc is
[docs/test-suite-model.md](docs/test-suite-model.md), the cockpit
(`bash tools/run_tests_gui.sh`) is a view and never a gate. Everything below this
row remains the standing record.

**Where the tiers stand (2026-09-11).** [V3](docs/tiers/v3.md) is SIGNED and
**open**: V3.0 (agency), V3.1 (map platform), V3.2 (the alliance system, PR #27),
V3.3 (the EU-27 roster) and V3.4 (roads and motion, PR #32) are built and on `main`;
**V3.5 climate is BUILT** on `v3.5-environment-climate` -- emissions read, two sited
disasters, the climate accord as a fifth org, `SAVE_VERSION` 34, re-run and readout
all shipped; the as-built record is the V3.5 row below and
[docs/tiers/v3.md](docs/tiers/v3.md)'s built-at note -- and **V3.6
ceremony has not started.** **V3.0's gate FAILED by measurement** -- best active play -2.00
approval points against idle -- and the author's route call was taken 2026-09-12
(the competence-credit channel) and **measured at V4.0 (2026-09-14): the level
form missed its gate** -- see the V4.0 row above; the decaying form shipped at
V4.1 as the programme credit (the top row, gate PASSED).
[V4](docs/tiers/v4.md) is **SIGNED (2026-09-13)**: twelve blocks, 70-95 sessions, the agency
call first, then a player agenda, the statute book (compose, repeal, a tax panel, a
bill briefing and two commissioned polls), a deep bench of ~1500-2000 people, events
at scale, the council contested, **the commodity economy**, industry at ~2,900 firms,
the reading surface, ceremony, the stylised deep-zoom map and the roster past the
EU-27. Nothing in it starts before V3 closes. **V4.3
deliberately overturns [events-model](docs/events-model.md) §3's office-never-a-person
rule**, and the session that builds it rewrites that rule at the rule itself. **V4.6
replaces the growth-rate model with a production model** -- the region spine survives
because `economy.gd:289` already makes GDP the region sum, and it carries **two step-0
probes, one of which is a tick budget**: nothing in this project has ever timed a
simulation month (`tools/frame_probe.gd` times frames), and Victoria 3 ships the same
model shape to a late game its own players call unplayable. Everything
below this paragraph is the V2.1 record and has not been re-cut since.

## V2.1a

**V2.1a shipped the panel system, V2.1b migrated every panel onto it, and V2.1c settled navigation.** `src/ui/panel_kit.gd`
holds six static primitives -- `section`, `heading`, `line`, `row`, `figure`, `ledger` --
plus `figure_text()` and `delta()`, and it is **not a base class**: all nineteen panels
already `extends PanelContainer` and the dirty sweep is duck-typed, so a hierarchy would
buy nothing this file's own "deliberately absent" list does not already refuse. Three
shipped bugs are killed at the primitive: **a missing key is an em dash and an error,
never a zero** (V1.6d printed a confident `0.00` against a live 31.80), `delta()` widens
its own precision until the printed number is not a lie (V1.6b printed `+0.0` against a
quantity whose whole range is 0.145 points), and `ledger()` is one grid so two value
columns cannot size apart (V1.6f ran one off the window edge). `line()` uses
**`AUTOWRAP_WORD`** and the choice was measured: the economy panel reports **928px under
WORD and 2602px under WORD_SMART** for identical content at an identical width.

**There were FIVE hand-written lists of panel names, not the one the row named**, and
`WindowManager.register()` had known all fourteen the whole time. All five are deleted for
`panel_ids()` / `panels()` / `mark_all_dirty()`, and `tests/test_panel_kit.gd` forbids a
sixth: **no file under `src/ui/` or `tools/` may name three or more panels in one literal**,
arrays and dictionaries both -- a scanner reading only arrays would have called
`screenshot.gd` clean while it held the longest list of the five. The one nobody was
looking for was `tests/test_shell.gd::EXPECTED_PANELS` at **seven of fourteen**: every
surface added since U5a had never been checked for registration, reachability or cluster
routing. That is `check_names.sh`'s U6b failure in a third place.

**A FOLD IS MEASURABLE HEADLESS, and `tests/test_nation_panel.gd`'s standing claim that it
is not describes that file rather than the engine.** The layout runs; what an autowrapping
Label lacks is not time but a **width**, and its minimum-size cache **lags one
invalidation** -- so a read in the same call as the write returns the answer for the
previous width and a read one frame later is exact to the pixel. **Impose a width, let a
frame pass, then read.** `tools/fold_probe.gd` carries the three tables.

**The fold mark is TWO marks because one rule was doing two jobs.** "There is more below"
is the scrollbar's, and `ui_theme.gd` had themed `ProgressBar` and never `VScrollBar`, so
that affordance already existed and had been engine-default grey on navy since U5a. The
brass hairline along the plate's **bottom** edge (`PLATE_FOLDED`, a separate variation, so
`test_ui_theme.gd`'s top-edge-only assertion is untouched) fires **only when the panel's
primary action is below the fold** -- what five screenshot passes actually paid for, and
something a scrollbar structurally cannot say. A panel declares its verb with an optional
`primary_action() -> Control`, duck-typed like `mark_dirty()`. **A stylebox's content
margins ARE the scrollbar's width**: the first version had none and the bar rendered 0px
wide, disappearing from every panel at once.

**`fit_within()` spent the whole band on the SCROLL** and the title bar, separation and two
content margins went on top, so **every window that filled its band overflowed it by ~50px**
-- and `clamp_into_parent()` constrains only position, so the last row sat under the bottom
furniture. Fixed with a second pass. A window is also sized from its content **as it was
before the refresh that fills it**, since `open()` marks dirty and places in the same call.
**What was handed to V2.1b as "not fixed in either direction" was a STALE READ**, and
V2.1a's own step-0 finding is what it missed: a panel that has never been shown has never
been laid out at the width it will really have. Cold against warm, **4 of 14 differ**
(politics 4725 -> 945, economy 928 -> 424); warm against **drawn extent, 0 of 14 differ**.
The grow-to-the-band heuristic was right to be deleted and V2.1b's booked structural fix
was written, measured and deleted too. Model:
[docs/panel-system.md](docs/panel-system.md).

**V2.1b MIGRATED THE OTHER SIXTEEN PANELS AND TURNED THE FOLD CONTRACT INTO A TEST.** The
row said twenty-five and there were nineteen `*_panel.gd`, three already done; one of the
three files it said would not fit one context together, `map_view.gd`, **is not a panel**.
**Four panels had no private helper at all** -- `law`, `calendar`, `election`, `polling`,
sixty-six raw Labels inline -- so V2.1a's *does this file still define `_row`?* check would
have called them clean forever, which is `check_names.sh`'s U6b failure in a third place
inside the test written to end it. The second assertion closes it: **every
`src/ui/*_panel.gd` must name `PanelKit`**, over a directory scan rather than a sixth list.

**Six more panels declare a verb (ten of fourteen), and politics FAILED the contract at 865
against an 826px band.** That panel holds 945px of content, so no height clears it --
V1.3g's finding as arithmetic rather than a rule of thumb -- and **the verbs moved above the
readout**: 73 now, structural rather than 39px of luck. The report is an assertion,
mutation-checked. `bloc`, `campaign` and `events` report **no verb at month 1** because they
genuinely have none; `--bloc`, `--campaign` and `--event` reach all three.

**Two kit changes, both forced by a panel.** `Tone.PLAIN` on `line()` now means the panel's
own **body** text -- every tone resolved to CAPTION, harmless for V2.1a's three callers and
wrong for the **forty-five plain lines** `government_panel` and `nation_panel` build between
them -- and a figure's caption wraps, because overview's GOVERNMENT column is ~110px.
**Two retained tables became ledgers**, and budget's killed a live bug: `_set_figure()`
returned **silently** on a key with no `FIGURE_ROWS` entry, which is how V1.3g's deployments
line wrote into nothing for three sessions. **`_right()` and `_add_row()` are deliberately
NOT banned**: a cell inside somebody else's grid is the panel's own, because `ledger()`
cannot carry a per-cell tooltip and an autowrapping kit label collapses a fixed column.
`people_panel` went 520 -> 700px, which is height fixing a **readout** rather than a fold.

## V2.1c

**V2.1c SHIPPED NAVIGATION AND THE RESTING SCREEN, AND THE V2.1 BLOCK IS COMPLETE.** The
row's own question -- *should the resting screen show anything at all* -- was answered by
measuring rather than by arguing. `tools/nav_probe.gd` ran the real game for fourteen years
with **nothing ever opened**: of 74 months in which a decision was in front of the player,
the screen said nothing in **42** (a president who never touches a card) and **64** (one who
reads a card and closes it). The message column is the only route a pending thing has ever
had -- `MAX_CARDS` 6, **oldest** dropped, dismissible, never re-pushed -- so an event's whole
visibility is *one click of an X away from nothing*, and a **council vote and an open
campaign window are silent in 100 % of their months**, having no card at all. The response is
**one mark and no plate**: `src/ui/pending.gd` returns window ids, `action_bar.gd` turns them
into clusters, and the mark is the cluster's own icon in **brass** -- *the state's own
material marks what matters*, reused rather than joined by a second visual rule. Nothing is
drawn on the map, `hud.is_over_furniture()` does not move, and **`dashboard.gd` stays
deleted**. What is *not* in `pending.gd` is the design: the test is that it awaits **the
player**, so `dissolution_pending` was measured (0 months) and then refused **on the rule
rather than on the number**.

**THE KEYBOARD WAS A SEVENTH HAND-WRITTEN LIST OF PANEL IDS, and the test written to end that
class could not see it.** `_unhandled_input()` matched **six** keycodes against six window ids
-- so the eight windows added since U5a had no key at all -- and `tests/test_shell.gd` held
**the same six** as a literal dictionary, because a list cannot test a list.
`test_panel_kit.gd`'s scanner reads `src/ui/` and `tools/` for panel **variable** names, and
these were ids and keycodes in `tests/`. The map lives at the `register()` call now --
`register(id, title, content, key)`, `shortcut()`, `id_for_key()`, `push_error` on a key
already taken -- so adding a surface is still **one `register()` and one line in
`_build_action_bar()`**, and the drawer's tooltip **reads the letter off the registry** rather
than restating it. `WindowManager.opened`/`closed` get their **first consumers since U5a**
(`message_stack.card_activated`'s case at V1.8 in a second place): the bar was the only route
that marked itself, so a keypress, a map marker and a message card each opened a window while
the one control that says where you are said nothing.

**The cluster capacity table REFUSED THE QUESTION IT WAS WRITTEN TO ANSWER.** The bar may use
**1384px of 1920** -- the rest is the left stack and the clock -- and the widest drawer this
game could plausibly grow uses **half** of it, 0 of 16 measured rows near the edge. So width
cannot force a fifth cluster and cannot choose one either, and the four hold on **grammar**:
*a cluster is the domain of the decision rather than the shape of the object*, so region,
city and energy are Economy, climate is Society, and a fifth "Territory" cluster is refused
with the count that would reverse it recorded beside it. **Instance fifty-two, the first of
the V2 tier, is in the row's own wording**: of its five surfaces to place, [docs/tiers/v2.md](docs/tiers/v2.md)
§4 calls the day agenda *"a ribbon, not a grid"* and §2 reaches a city by **clicking the map**.

**`tools/run_tests.sh` fails a test that exits 0 with a `SCRIPT ERROR` in its output**, and
the session reproduced the failure it was handed: a parse error in `main.gd` left
`test_shell.gd` printing *"all checks passed"* over a scene that never loaded, because that
file read `_main._state` off a bare Control, which raises rather than returning null. Both
halves fixed; zero script errors are emitted today. **No `SAVE_VERSION` move, no balance
re-run, no new regime** -- predicted in the plan, since nothing in `src/sim/` was touched and
this adds no verb. **The twenty-third screenshot pass found no bug in the readout and one in
the code it was about to ship**: `show_pending()` reached `Icon.load_icon()`, which reads an
SVG off disk and rasterises it **on every call**, on the path that refreshes with the clock.
Both tints are rasterised once at `add_cluster()` now, and the frame before and after is
identical to the pixel -- **a screenshot pass structurally cannot see that class**. Model:
[docs/panel-system.md](docs/panel-system.md) sections 13-17.

## V2.2

**V2.2 SPLIT, AND V2.2a SHIPPED THE GEOGRAPHIC REGISTER.** The per-session table stopped
at V2.1c, so **there was no V2.2 row at all** and the tier/model/effort call was authored
at plan time with nothing to challenge -- the missing-row failure in its purest form, not
a row that was wrong but a row that was absent. Counted cold: **~36 surfaces, ~14 new
files and four machines** (import pipeline, register and loader, map draw and hit test,
two panels) across **two tracks**, so the block cut on the rule that cut V1.6e, V1.6f and
U6c. **(a) is the import and the register with no UI at all; (b) is the map and the two
panels -- BUILT, see below.** Model: [docs/geography-model.md](docs/geography-model.md).

**A REGISTER AND NO BEHAVIOUR, and the test says so by reading the files.** Nothing in
`src/sim/` preloads `region.gd` or `city.gd`; a region carries no GDP, no unemployment
and no sector mix and a city carries no population of its own. V2.5 makes a region
load-bearing and V2.6 moves people between cities, and each arrives with the field it
needs rather than finding it pre-authored and inert. The shape is **V1.4a's partition at
two levels**, which is the tier's own call rather than an analogy: a region holds a share
of its nation's population, a city a share of its region, and **neither residual is
stored** because `1.0 - sum` cannot drift from what it is the remainder of. **112 regions,
581 cities.** An absent `data/regions/<ID>.json` is an **error**, unlike `companies/` and
`outlets/` -- those have prior models (unpartitioned sectors, no press) and there is no
prior model in which a nation has no places.

**THE LEVEL IS PER NATION AND THE ROW SAID NUTS 2.** For the nation this game is about,
NUTS 2 is the **pre-2016 régions** -- Eurostat's own labels return `FRC1 Bourgogne`,
`FRE2 Picardie`, units abolished in 2016 -- and `docs/fictionalization.md` names
**Occitanie** as its example of a real region, which is NUTS **1**. The inverse holds
elsewhere and is why one level cannot serve the roster: Italy's NUTS 1 is five statistical
macro-areas and Switzerland's is **one country**. FRA, DEU, GBR and BEL are NUTS 1, the
other six NUTS 2, and **no level field reaches `src/`** -- `tools/import_data.py`'s
`REGION_LEVEL` plus each file's `_source` line are the whole record. The test checks that
in the **data** (a region file's top-level keys are exactly `_source`, `_year`, `_note`,
`regions`) rather than by grepping `src/` for the word, which was the first version of the
check and failed on the comments explaining the absence.

**THE ROW'S BRITAIN PROBLEM WAS HALF WRONG, IN THE DIRECTION THAT MATTERED.** The V2
preamble booked Britain as needing a second source or an authored register. Confirmed and
worse for **regional GDP**: `nama_10r_2gdp` carries zero `UK` codes at *every* year, 2018
included, because the codes were removed from the dimension rather than left empty. But
`demo_r_pjangrp3` carries **41 UK NUTS 2 codes and 12 NUTS 1 codes with values at 2019**,
summing to the national figure (66 647 112) exactly. **Regional population is measured for
all ten; only regional GDP is short** -- and that is V2.5's quantity. So the register is a
partition of **population**, Britain reads 2019 through V1.5c's own per-series nearest-year
fallback, and the gap passes to V2.5 whole. **ONS was probed before the call was taken**:
its beta API publishes `gdp-by-local-authority`, 380 LAU rows with **no ITL codes at all**,
so aggregating it needs a fourth dataset as a lookup -- recorded so V2.5 does not re-derive
it, and at NUTS 1 the authored fallback is twelve numbers rather than forty-one.

**THE GEOMETRY IS THE AUTHORITY ON THE ROSTER, and one rule settles three problems where
the plan expected one.** The register is the set of NUTS codes carrying both a figure and a
GISCO polygon, because a region with no polygon cannot be drawn and this tier exists to
locate things. `<CC>ZZ` (Extra-Regio) falls into the residual with no filter of its own;
`FRY` and `ES70` are dropped by the bounding box that has dropped them from the map since
S8; and the third was in no plan -- **the Eurostat response carries two NUTS vintages at
once**, `NL35`/`NL36` being the 2024 codes for Utrecht and Zuid-Holland and `NL31`/`NL33`
the 2021 ones, **equal to the person**, so summing all fourteen Dutch codes overstates the
Netherlands by **5.1 M**. The partition is exact **in the source itself** -- France's
68 091 703 is the sum of its own codes to the unit -- so the residual is precisely what
those rules removed, non-zero for two nations only (FRA 0.0330, ESP 0.0460).

**The city join is a point in a polygon and CANNOT go through GeoNames' `admin1`** -- for
France that is the 13 modern régions, which is NUTS 1 and therefore *coarser* than the
level the row asked for, so a code join would be silently wrong for one nation and
unverifiable for the rest. 4 002 inside, 82 snapped at `CITY_SNAP_DEG = 0.25` (coastal
communes the 10M coastline cuts -- Birkenhead, Portsmouth, A Coruña, Cádiz, Antibes), 40
overseas into the residual, **0 failed**.

**THE ONE MEASURED CONSTANT WAS MEASURED THREE TIMES AND THE FIRST ANSWER WAS WRONG BY
29 %, and all three corrections came from READING THE GENERATED FILE rather than from a
check.** `CITY_MIN_POP` is swept against two clauses fixed before it ran -- roster mean
coverage >= 0.30 and at most 600 named cities, the second written from the drawing side
because V2.2b draws by rank and the roster at the opening fit is ~1000 px wide. The first
sweep gave `[82 000, 101 000]` and a midpoint of 91 500, and it was measuring GeoNames
rather than Europe: **607 `PPLX` rows** (sections of a populated place -- Hamburg-Nord,
Carabanchel, Eixample, Favoriten); then **a London naming twenty of its own boroughs** at
1.325 of itself with Brussels at 1.285, fixed by taking cities in descending order only
**while they fit**, which needs no list of exceptions and also settles the city-state case
where Eurostat and GeoNames disagree by 6 % about Hamburg; then **thirty-six Paris and
Marseille arrondissements** that neither the feature filter nor the fit rule could see,
because GeoNames codes some as `PPLX` and others as plain `PPL` and Île-de-France is large
enough to hold Paris *and* its districts. The discriminator is a **number**: a plain
name-prefix test also eats `Mansfield Woodhouse`, `Newport Pagnell`, `Amersham on the
Hill`, `Ischia Porto` and `Kronberg Tal`, five real places, where requiring a digit after
the parent's name catches all thirty-six and none of the five. Corrected, the clauses cross
at **[69 000, 73 000]**, both edges are smooth crossings so **the interior governs**
(V1.5d's rule), and the midpoint is **71 000** -- the same answer at a grid of 2 000 and of
1 000, which is V1.5b's refinement diagnostic, and interior to the swept range.

**A third clause was written and DELETED**: *"the worst nation names at least 0.20 of its
population"* fails at every candidate and its two failing nations do not move with the
threshold at all -- Luxembourg has **one** city and it is 11.9 % of the country, and Swiss
communes are administratively small. A band an observable cannot reach is a bound and not a
selector, V1.5a's and V1.5c's finding, so it is recorded rather than met by shipping 4 691
cities. **Shares are rounded DOWN**, not to nearest: rounding to nearest put Germany's
sixteen Länder at 1.000003 of Germany -- a residual of minus three parts in a million,
arithmetically nothing and still a partition that does not hold.

**The firm domicile is the only thing making `Company.city` load-bearing before V2.2b draws
it**, and the table it produced is one the row did not ask for: **one city holds a third to
a half of a nation's named payroll** -- Lille 33.1 % of France's, Düsseldorf 34.3 % of
Germany's, Manchester 44.0 % of Britain's. Nothing authored that, and it is what makes
V2.6's migration a decision rather than a diffusion. `Companies.headcount_in_city()` lives
in `companies.gd` and **not** on `src/core/region.gd`, because a core value type preloading
a sim system would invert `data -> sim -> ui`.

**`tools/check_names.sh` WENT RED ON A REAL CITY, and both halves of the rule that made
it red are true.** [docs/fictionalization.md](docs/fictionalization.md) says *"Do not
reuse a real company's actual name"* and, four rows above, *"Cities, regions, rivers |
Real | Lyon, Occitanie, the Rhone"* -- and **Santander** is a bank on
`tools/banned_names.txt` and a Spanish city of 173 635 people that GeoNames handed the
register. Banning it everywhere makes the check permanently red over a real place;
deleting the entry lets a session name a fictional bank after a real one. The ban that
matters is the one about **firms**, so `banned_names.txt` grew a `[places]` section
checked in `data/companies/` alone, and the negative case was run rather than assumed:
a firm renamed `Santander` still fails. One entry today, and the criterion for adding
another is written beside it.

**`SAVE_VERSION` stays at 27 and the test pins three ABSENCES rather than three fields** --
V1.6c's shape and V1.8's, the third session on that list whose serialised contribution is
nothing at all. The register is content and round-trips through `data/regions/` the way a
firm's authored share does through `data/companies/`. **No balance re-run and no new
regime**, predicted in the plan rather than discovered (U6c's precedent): nothing in
`src/sim/` was touched beyond one pure query, and a region is not a verb. **No screenshot
pass, for the first time since U5a** -- there is no UI to photograph and a frame of an
unchanged shell proves nothing; it returns at V2.2b. And **`data/geo/regions.geojson` is
written and committed while `data_loader.gd` does NOT load it**: nothing draws it until
V2.2b, so a launch should not pay 180 KB for it, and `tests/test_geography.gd` parses it
directly to assert every named city lies inside its own region's polygon -- U6c's
containment check one level down, and the thing that catches a mistyped digit or a geometry
vintage that has moved under the figures.

## V2.2b

**V2.2b SHIPPED THE MAP AND THE TWO PANELS, and the expected red turned red on the day it
named.** `data_loader.gd` loads `regions.geojson` into `region_features` (NUTS id → outer
rings, `_load_geo`'s shape) with a **fourth `_validate_regions()` rule** cross-checking the
register against the geometry at load time, and V2.2a's absence assertion flipped into a
presence check with both halves of its history recorded beside it -- 112 polygons, key set
equal to the register's ids. `SAVE_VERSION` **stays 27**, no balance re-run, both predicted:
nothing under `src/sim/` was touched, and drawing is not a verb (U6c twice running).

**REGIONS ARE THE FILL, at every zoom.** Each nation draws its 1:10m GISCO regions in the
nation hue under a same-hue 1:50m base and the bright 1:50m national stroke -- the base
exists because the two vintages disagree at the coast by a few km (a few px at MAX_ZOOM)
and turns a hole in the country into a seam the eye cannot find; the screenshot pass judged
the seam and passed it. **The two-pass fill/hairline draw is load-bearing because the roster
carries an enclave of EACH direction**: with holes dropped, a host's outer ring covers its
enclave, so enclave visibility is draw-order luck -- except Berlin (3.7 M) outpopulates its
host Brandenburg (2.6 M) while Bremen (0.7 M) is a third of its host Niedersachsen (8 M),
so **no fill-and-stroke order renders both** and only every-fill-then-every-line does. A
fact in the data, found by reading it; the first version of the draw was one pass.

**BRASS CROSSES are the spend the tier reserved, and `CITY_MIN_ZOOM = 2.0` sits JUST UNDER
the opening Europe fit (~2.1 on 1080p) on `LABEL_MIN_ZOOM`'s own discipline.** The first
draft sat at 2.2, *above* the fit, and would have shipped 581 cities the default frame
never shows -- the volume clause was measured FOR the ~1000 px opening fit, so the
threshold belongs below it; the correction came from computing the fit, not from taste.
Radius is `sqrt(pop / 8 M)` against `RADIUS_BASE` (London ~9.6 px, the smallest towns clamp
at 2), the list is **ascending** so the largest draws last and wins an overlap, and **the
hit test reads the same gate** so a glyph that is not drawn is never a target. One
formatter, `PanelKit.pop_text()`, serves the hover label and both panels so they cannot
print two roundings of one figure.

**The hit test takes the marker contract, and the purity check FIRED ON A COMMENT.**
`_city_at_screen_point()` is a screen-space radius test over the city list, reaching neither
`_polygons` nor the nation test, policed from source by `tests/test_map_cities.gd` the way
`test_map_markers.gd` polices the markers'. That test's extraction swallows the *following*
function's doc comment, and the city doc legitimately named what it must not reach -- the
test was the authority and the function moved to where both extraction windows are clean.
Click chain: markers, then cities, then nations, each hit stopping the fall-through.

**Region (T) and City (V) under Economy, the cluster going 4 → 6**; `nav_probe.gd`'s
`OTHER_ROUTES` carries the city's map cross as its third entry. Region prints the partition
and a league table in authored order (the importer writes descending by population) whose
payroll column -- `headcount_in_city()` over each region's cities -- is the one live number
in it, and **zero is a TRUE zero there for seven of ten nations**, printed as `0` not an em
dash: V1.6d's bug was an absent figure printed as a confident zero, and this is a present
figure that is empty. City carries both of §16's routes (the drawer's ranked list;
`show_city()` for any nation's cross, back button outside the scroll) and every population
is two shares through the LIVE national figure. The screenshot pass **returned** after
V2.2a's skip: three frames judged clean, `--region` and `--city` the first flags that stage
a view rather than a mutation, because the register is static content.

**Two handoff notes were STALE, and both said the same thing: V2.1a already fixed the
drift.** `screenshot.gd`'s `_mark_panels_dirty()` is no hand-written list to extend -- V2.1a
deleted it to one line through the registry, so registering the two panels IS the whole job.
And the month-136 warning on `nav_probe.gd`'s loop was inherited by nothing: no probe this
session runs a month at all, and `geography_probe.gd` still runs none.

## V2.3

**V2.3 SHIPPED THE FACE OF POWER: 71 portraits, a glyph on every window, and the placeholder silhouette PROMOTED to the shared fallback.** The recipe is two
committed halves and one machine dependency stated honestly: `tools/portraits_generate.py`
drives the author's local ComfyUI (updated in-session to 0.34.0 / torch 2.13) through
`tools/portraits_workflow.json` -- API format, where a stray `_comment` key is a 500 --
and `tools/portraits.gd` imposed the ONE look as V2.3 built it: a fixed crop and eyeline,
a posterized INK-to-SLATE-to-brass ramp, 216x296 out, committed `importer="keep"`
.imports beside each. **The pass is deterministic (hash-proven on re-run) and the
committed assets are canonical where the machine drifts.** **Likeness policy, the
author's call: a portrait EVOKES the real politician its fictional name plays on and
never depicts them** -- prompts are described archetypes, never a name. **The player
rejected the first wall on sight -- "too lookalike" -- and the correction is the
session's sharpest finding: "one crop, one eyeline" constrains the FRAME; the FACE is
where variety lives.** A prompt that pinned everything but the seed made 71
near-siblings. **A missing portrait is SILENT in game**: `portrait_card.gd`'s Bust moved
into `src/ui/portrait.gd` and became the fallback behind `control_for()`/`framed_for()`,
so the register can grow a session ahead of the art run; the refused direction is stale
art nobody references, held by the tool and by `tests/test_portraits.gd` alongside the
bytes-not-`load()` check and the one-committed-icon-per-registered-window check.
**V3.7 STRUCK TWO OF THESE CALLS, and this paragraph is corrected rather than deleted
because a comment contradicting its code is a defect:** the **duotone ramp is gone**
(realism is the look; the unifying work that survives is the crop, the eyeline and the
one output size, plus matting masks turned into real alpha), and the **nation-hue band
is gone** -- "background per situation" is now the real thing it stood in for: a 14-scene
backdrop library (`assets/portrait_scenes/`, rendered by `tools/backgrounds_generate.py`)
composited behind the bust at display time, grade-tinted per scene. Five expressions per
person (`neutral/pleased/stern/worried/weary`) replaced the emoji read; WebP q90 with
alpha at 432x592 replaced the duotone PNGs; and the prompt now carries region, role, sex
and wardrobe from the generator-owned sidecar (`tools/portraits_traits.json`) -- the
V2.3 `GENDER` table defaulted 140 of 213 people to male. The likeness policy is unchanged
and is now ENFORCED by a test, not a docstring. Faces live on the card, the People
window and the summit panel; later spread is one `framed_for()` per surface. **Icons
travel on `register()` itself** (drawer entries, title
bars, the test, all one source -- the keycode lesson applied one session early), sixteen
new at-icons SVGs committed via `git add -f`. **No sim file touched, `SAVE_VERSION` stays
27, no balance re-run** -- drawing is not a verb, third time running. **The honest gap: no
vision path survived the session that built a wall of faces** (model, judge agent and CDN
route all refused image input), so the screenshot frames were captured and the AUTHOR
holds the verdict on the second wall -- the same authority that rejected the first.

## V2.4b

**V2.4b SHIPPED THE SCENES, AND THE STEP-0 GATE WAS THE SESSION'S FIRST RESULT.**
`dialogue_manager` had to prove it runs under `--headless --script` -- the regime
`tools/run_tests.sh` IS -- before any content was authored; it did, and the adoption
landed whole: 790 KB and 122 files committed into `addons/`, `DialogueManager` in the
committed `project.godot`, **the project's first stated exception to the no-autoloads
rule**, the reason written beside the `.gitignore` exception and the Gotchas paragraph
rewritten for the addon that finally landed. The same commit cleaned the per-machine
`MCPRuntimeServer` line out of the committed tree, where it had crept into HEAD
undocumented. **A summit is ephemeral by construction**: `Summits.draw()` picks a
scene deterministically off the meeting register's own stamp (the event hazard's
discipline -- a replay produces the same dinner), the panel walks it through the
autoload's own `get_next_dialogue_line()`, the one choice applies through
`Legislature.apply_effects()` -- the applier the law and the event choice already
share, so no new channel -- and NOTHING is serialised: `SAVE_VERSION` stays 27 and
`tests/test_summits.gd` pins the absence, because a record of dinners is derivable
from the state the dinners changed. **The sidecar contract is refused loudly at
load**: every response priced ({} is legal and means lands-nowhere-on-purpose), every
price behind a real response, channels shared with law and event only -- a summit
lands where a law lands, and pair state is out for events-model's own reason. The
shipped content is two scenes (DEU, ITA) plus `blackout_night`, the interrupt crisis
whose `respond_months: 1` is the flag's meaning compressed. **`interrupt: true` is one
boolean on the closed key list**: absent reads false (the truth about every version-27
save), `announce()` copies it into the pending register, and `_enforce_interrupt()` --
reached from BOTH the month tick and the load path, which is what makes the reload
re-raise the same code path rather than a second one -- pauses the clock only behind
the flag read, pinned at source, so V1.8's non-modal argument survives for every
event without it. **The re-run moved where the prediction said it would not -- but not
through the summits**: no regime books a visit, so no scene fires; `blackout_night`
is a HAZARD that draws on debt >= 95 %, most managed regimes hold it, and its default
applies bloc_offset unanswered -- ~990 output lines wobbled, every one a margin or a
last digit, ZERO verdict flips, V1.8's re-run reason exactly. Two compile gotchas the
build paid for: dialogue_manager TITLES reject spaces (the first draft's
`~ Raise the Rhine shipping tolls` did not compile; snake_case titles, human labels),
and a new script cannot type its own return -- AGENTS.md's first gotcha, caught by
`script_check` at the signature. Model:
[docs/summits-model.md](docs/summits-model.md).


## V2.4a

**V2.4a SHIPPED THE DAY, AND THE ROW'S BIT-IDENTITY PREDICTION WAS THE THING THAT
DID NOT HOLD.** Scarcity is **occupancy only** -- an `opens_meeting` booking occupies
travel out, the meeting and travel back, overlapping blocks are refused, and U6a's
deleted currency stays deleted on the author's plan-time call. The price is
`Diplomacy.travel_days()`, great-circle off the V2.2 register's own coordinates at
280 km/day (rail-and-road pace; the tier's "four days because Rome is far" was the
anchor, and `tools/day_probe.gd`'s sweep confirmed the rate interior to its grid, not
pinned at an edge). **The number rides the entry and `calendar.gd` stays a leaf** --
it spans blocks and refuses overlaps without knowing where Rome is, asserted by a
source read. **`GameState.met_months` is the sixth piece of pair state, symmetric
because a handshake is one act either direction**, and the gate is `met_recently` --
a new `PRECONDITION_FIELDS` entry read through the machinery the other pair fields
already use, so the treaty-class verbs ask for a meeting in their own content files.
The lock and the key are both data. **The window is 12 because that is the visit's own
cooldown and the clauses meet there**: below it, a dead zone no visit can reopen
(V1.3g's monotone charge with the sign flipped); at twice it, a gate a punctual player
never sees close. Both hold only on [12, 24), smallest passing 12, stable on the
widened grid. **The ribbon is the bottom-most plate** -- travel hatched, the meeting
solid brass, today underlined, `Calendar.day_cells()` the whole rule about occupancy,
the tooltip named from the register by `verb_key` -- and `tests/test_ribbon.gd` pins
the wiring a headless suite can see (day-tick dirty, furniture coverage,
register-sourced tooltip). **The re-run moved one regime, `managed_imposes_tariffs`,
last digits only, zero outcome changes**: a pair on state_visit cooldown used to fall
through to the treaty verbs, and the gate seals that hole until the pair has met --
"the gate is inert for the nine" was true month-by-month and false across the cooldown
cycle. **Two live bugs found on the way, both older than the session**: main.gd and
balance_probe.gd read `result.get("ok")` off execute(), whose contract is `applied` --
every kept diplomatic arrival since U6a fired its effects and was recorded as refused
-- and LUX's capital was "Luxembourg City" against the register's "Luxembourg". The
probe's occupancy band PASSED at 35 % unplaceable, but the first run measured 0 %:
it fired each visit the moment it booked, letting this month's own visits erase each
other's occupancy -- V1.3f's measuring-the-wrong-state error, in the file written to
avoid it, a third time. `SAVE_VERSION` stays 27, both predicted absences pinned; the
screenshot frames were captured for the author (no vision path, V2.3's honest gap
standing). Model: [docs/calendar-model.md](docs/calendar-model.md) section 12.

## V2.5

**V2.5 MADE NATIONAL GDP THE SUM OF THE REGIONS, and the swap is one line:
`_apply_growth_to_sectors()` now takes the region sum as its target and its last
line is `ns.gdp_eur_bn = target_gdp` -- no reconciliation term, no rescale pass, the
partition IS the model.** The refused alternative is recorded because a later
session under balance pressure will reach for it: keeping the sector sum as the
authority and normalising regional weights into it is exact for free and top-down
wearing the partition's clothes, one step from the ninth-addend version §5's own
warning box declined. **A region's trend IS its own sector mix read through
SECTOR_TREND** -- the same expression `Economy.trend_pct()` applies to a nation --
so the deviation is zero-mean BY CONSTRUCTION and `region_constants.gd` ships a key
and a bound and NO tuned constant, `projects_constants.gd`'s position a second
time; the test reads the file and fails on a third `const`. The divergence is
measured and readable: **FRA's richest-to-poorest output-per-head ratio moves
0.021 and DEU's 0.034 over fourteen years** against a pre-committed floor of 0.010
(one digit of the panel's own %.3f); Île-de-France starts at x1.624 and Thüringen
at x0.712, and NOTHING authored that -- `gdp_share / share` is two partitions of
one nation divided by each other. `SHARE_DRIFT_MAX` is a bound with **78x slack**
(0.0019 worst against 0.15), checked and never clamped. Regional unemployment is a
PURE READ (`national × rel − OKUN × dev`), `credit.gd`'s stateless shape, which is
why **SAVE_VERSION is 28 on ONE field**: `region_gdp_eur_bn` absent means the sum
is 0.0 and the country has no economy at all, and re-seeding on load would erase
fourteen years of divergence the player watched -- the shares stay content and
round-trip through `data/regions/`, and the no-regional-unemployment-stock absence
is still pinned. **THE RE-RUN HELD THE PREDICTION AND TOLD THE TRUTH AT THE BIT
LEVEL**: 143 of 144 runs identical in every printed figure, one run differing by a
single debt digit on a `%.1f` rounding boundary (tax_zero_DEU, 88.8 -> 88.9), zero
outcome changes -- the Jensen second-order term reaching a print edge, exactly what
the prediction wrote down first, measured against a fresh 144-run baseline captured
on the branch before the spine moved, BOTH SIDES FROM WORKTREES because the
worktree's missing-addon parse noise is identical on both sides and cancels in the
diff. No new regime, fifth session running: no verb, and every regime exercises the
new code through `Economy.tick_month()`. **The plan's own decomposition test was a
REAL RED, and the reason is two weightings**: the import normalises
`unemployment_rel` in population weights and the Okun term is zero-mean in GDP
weights, so its population-weighted mean is a 0.0037-point residual -- the test now
asserts the two exact halves separately rather than one approximate figure. **And
`GameState.duplicate_state()` dropping the register collapsed the budget projection
to the residual alone** -- a France losing 98 % of its output in the budget panel's
own forecast -- which `tests/test_budget.gd` caught the same day the spine moved.
Two joins the plan's gate never anticipated, both measured: **the Dutch vintage
sibling** (the register is 2021 geometry; GDP and GVA answer Utrecht and
Zuid-Holland only under their 2024 codes, and the population series proves the
identity -- NL31 = NL35 = 1 369 873, NL33 = NL36 = 3 753 944, equal to the person)
and **Switzerland's mix-only fallback** (`nama_10r_3gva` carries a TOTAL branch and
no branches at all for the country, while its GDP and unemployment are fully
measured, so every Swiss region carries the nation's own World Bank shares and
Switzerland has no MIX divergence -- a bound, not a defect). **Britain's gate
failed honestly**: ONS carries ten of twelve ITL1 codes (no UKM, no UKN -- the
devolved administrations) and an index besides, so the proxy was taken and **BRITAIN
HAS NO REGIONAL DIVERGENCE AT ALL**, measured at `moved 0.000` and recorded with
the number beside it; §6's migration inherits it. `test_geography.gd`'s refusal was
**narrowed without ever going red** -- the one reader takes the register as data
and preloads nothing, so V2.2a's preload scan was green all along and the narrowed
check reads the field contract instead (a bare `gdp_share` marker would have named
companies.gd's own V1.4a subsidy local; the dot form does not). The readout is the
Region panel (both partitions side by side, and a seven-column league table leading
with output per head) plus one never-silent line on the economy panel, and
`--diverge` is the flag that ticks ten years. **The screenshot pass returned for
the twenty-first session and found NO BUG** -- V1.6c's clean-sheet precedent,
reported as such; the vision path WORKED this time, so the three frames
(`--diverge`, `--region`, `--open economy`) are judged, not handed off. Model:
[docs/region-economy-model.md](docs/region-economy-model.md).

## V2.6a

**V2.6a MADE PEOPLE MOVE, and the machine is one expression applied twice with
different denominators.** V2.2a's two share registers are live state now:
`Migration.init_nation()` seeds `region_pop_share` and `city_pop_share` from the
authored shares beside `Regions.init_nation()`, and `Migration.tick_month()` moves
them every month -- `rate x share x (pull - mean)/12` with the mean in the same
share weights, so each sum telescopes to exactly zero, `Trade.sector_shift()`'s
rule and V2.5's zero-mean deviation a third time and the first at two levels at
once. Realised partition drift **6.66e-16** against a 1e-12 ABSOLUTE tolerance
(~1500x margin) -- no Jensen term exists to excuse a larger one, nothing here is
exponentiated -- and this was the FIRST suite run in which the flow executed at
all: until the rate was measured, a zero-rate early return made every closure
check vacuous. **THE PULL CARRIES NO FREE WEIGHT**: between regions it is
Harris-Todaro expected income (output per head on the LIVE share x employment
probability -- negative feedback by construction, which is why the drift bound has
slack instead of setting the number), and between a region's cities it is named
jobs per head, because every city in a region shares its region's output per head
and unemployment and only named employers can separate Lille from a smaller
neighbour -- V2.2a's one-city-holds-a-third-to-a-half-of-the-payroll finding read
as a mechanism, exact zero for seven of the ten. City level runs FIRST so both
levels read start-of-month state, and direction is pinned by `share_delta()`
called directly at a rate the test supplies -- a sign-flipped flow passed every
conservation invariant. **THE RATE WAS MEASURED AND THE MEASUREMENT CAUGHT A
DEFECT IN ITS OWN BAND**: clause (ii) read `SHARE_DRIFT_MAX` (0.05), so the upper
crossing restated the guard rail -- the clamp-measuring failure V1.5c, V1.6c and
V1.6e each named -- and the ceiling was re-measured from Europe:
`tools/region_drift.py` over Eurostat `demo_r_pjangrp3` 2014-2025 on exactly the
register's roster gives a worst real population-share drift of **0.0164** (AT13
Wien, largest not mean), and `MIGRATION_RATE` re-swept **0.0273 -> 0.0102**,
interval [0.0081, 0.0123], midpoint stable at the two finest steps and interior on
all four grids. **THE CEILING IS GENEROUS, NOT LIKE-FOR-LIKE**: it measures TOTAL
population-share change (fertility, mortality, international migration) while the
model moves only internal migrants with both residuals frozen. Headroom is a
third -- the measured ceiling over the band's upper edge, 0.0164/0.0123 = 1.333
-- and the roster's runner-up (ES30 Madrid, 0.009858) sits BELOW the
0.0110 collapse threshold -- a re-measured ceiling under that is a kill switch to
honour, recorded in the constant. **THE REALISM WAS BOUGHT AT A PRICE**: the
shipped rate sits only **1.26x** above the clause-(i) crossing (DEU binds at
0.00126 against the 0.001 floor), and visible movement fell to under two-fifths of
what the defect's sweep shipped (FRA's month-60 mover 0.0051 against 0.0131).
**TWO STRUCTURAL BOUNDS, numbers beside them**: Britain's regions carry an
identical expected income by construction (V2.5 §8's proxy, `moved 0.000`), so
Britain migrates on named employers alone (Manchester 0.0026 of its region at
month 168) and its region column is exactly 0.0000 at every rate; Luxembourg is
ONE region holding ONE city, `pull - mean` exactly 0.0 at both levels, unable to
move at any rate whatever. `SHARE_DRIFT_MAX` stays 0.05 and is now honestly a
guard rail: worst realised drift 0.0137 (FRA), slack 0.0363, ~3x the ceiling.
**SAVE_VERSION is 29 on TWO fields** -- both share registers; absent, every city
has a population of zero, no glyph at any zoom, and re-seeding would erase the
movement the save exists to remember. The constant lives in
`src/core/game_state.gd:426` (the plan said save_manager.gd), the bump is verified
load-bearing by stripping either register from a round trip (size 0, no re-seed),
and **the absence that STAYS red is a stored city POPULATION** -- a head count is
`population x share x share`, and storing one is a second answer. The review also
found **`tests/test_summits.gd` authored at V2.4b and NEVER registered in
`run_tests.sh`**, hard-pinning `SAVE_VERSION` 27 -- silently red for two versions;
registered, and the audit says all 73 test files are in the runner. **THE RE-RUN
HELD A SHARPER PREDICTION THAN V2.5'S**: bit-identical at the bit level, because
no national quantity moves and no population share enters any equation outside
`migration.gd`, so a single moved digit was to be a defect and not a rounding
boundary -- **1582 of 1582 printed lines identical** between baseline `d8a1baa`
and `dcbc42d`, zero outcome changes, no new regime (another session with none). Method
honesty: only the baseline side was a worktree where the plan said both, so the
per-machine addon parse noise did not cancel -- it was isolated instead: one
contiguous block on the worktree side only, AFTER the last
`invariants: OK over 168 months`, checked for a third stray line (V1.7c's gotcha)
and none found. The readout arrived free -- the city panel, the region panel and
the map's brass crosses have multiplied the two shares since V2.2b, so cities grow
and shrink without a UI edit -- and `--move` is the block's one new screenshot flag;
the pass judged four frames and found **NO BUG**, a clean sheet for the third time
after V1.6c and V2.5. What passes: **no verb, no political price, no net
urbanisation** (both residuals frozen -- a session that wants some authors a rural
pull), no map layer, no city economy beyond a head count; a regional opinion
channel was refused as *a second approval number with a different label*, V1.5c's
reason, and the price is **V2.6b's**, which sites unrest and campaign meetings on
these same shares; **V2.6c** owns natural change, whose conservation law differs
(internal migration is zero-sum nationally, birth and death are not) and whose
step-0 gate is whether regional age structure is obtainable from the register's
own dataset. Model: [docs/migration-model.md](docs/migration-model.md).

## V2.6b1

**V2.6b1 GAVE THE GRIEVANCE A PLACE, AND THE ROW'S CENTRAL CLAIM WAS FALSE BEFORE ANY
CODE WAS WRITTEN.** `src/sim/siting.gd` is a leaf that preloads **nothing** -- a caller
hands it weights and a signal and gets back a region id -- and it is the contract V2.9's
sited disasters read. **The row said both halves *"decide WHERE by reading V2.6a's live
shares"*, and the site is chosen by STATIC content**: arg-max over a population share
times a signal whose winner leads the runner-up by **73.9 % in France**, against a
fourteen-year migration budget worth about **9 % relative**. For nine nations of ten the
place is decided at load time and never revisited, and **the signal changes which region
wins for exactly ONE nation of ten**. Nothing in this project could previously ASK that
question, which is how a row could assert a live read that is arithmetically static and no
check contradict it -- so `Siting.margin()` and `signal_moves_site()` are **public
surface**, and a later session siting anything owes its own margin before claiming a place
moves. **The exceptions are the interesting half**: Germany's demonstrations move **Ruhr to
Berlin** on a +0.4 % margin named in advance, and **Britain acquires a site mid-run and
loses it again** because `Regions.unemployment_pct()`'s trend term is measured against a
GDP-weighted mean that V2.5's divergence moves -- so `tests/test_siting.gd` asserts Britain
unsited at month one and deliberately NOT permanently unsited. Luxembourg is the one
unconditional bound, one region unable to differ from itself.

**THE SCORING FORM FLIPS THE SIGN OF THE PRICE, which no plan anticipated.** Scored on the
level, the demonstration goes where the most people are and France's is Ile-de-France for
ever; scored on the **deviation from the nation's own share-weighted mean** --
`Trade.sector_shift()`'s zero-mean idiom used as a SELECTOR, fourth instance -- it goes to
**Hauts-de-France**, where France's unemployment actually is. And a high-unemployment
region is systematically a **poor, small** one, so both multipliers come out **below one**
(FRA 0.759, ITA 0.644, ESP 0.740; only AUT above at 1.147): **siting makes unrest CHEAPER,
not dearer.** **The output price needed NO CONSTANT** -- V2.5 already publishes
`gdp_per_head_index()` normalised to 1.0 at the national average, and `Siting.normalised()`
only makes the share-weighted mean **exactly** 1.0 (worst error 2.22e-16 against a 1e-12
tolerance), so the EXPECTED price is unchanged, `UNREST_IMPULSE_SCALE` keeps V1.5c's
calibration and only the per-nation variation is new.

**THE VISIBILITY PRICE WAS DESIGNED, BANDED, SWEPT AND DELETED, AND THE KILL SWITCH WAS
DECLARED BEFORE THE SWEEP.** Two clauses, both model criteria, both read in points of the
worst bloc row because `polling_panel.gd` prints one as `"%.0f%%"`: readable means **1.0
point**, and siting must not outweigh governing. Measured, the **whole** unrest opinion
price is worth **2.9825** points, one saturated settlement **0.4450**, and clause (i) first
crosses at beta ~3.1 while clause (ii) is crossed at ~1.3 -- so a readable siting term must
be **a third of the entire unrest price and 2.25x what settling the strike is worth**. The
clauses are **INCONSISTENT rather than badly tuned**, which is V1.5c's own finding from the
other side (the opinion model prices rates, the whole channel only just clears the poll
floor at three points, and a modulation of it is a fraction of a fraction) and V1.6a's
legibility floor in a **fourth** place. `siting_constants.gd` was **deleted rather than left
at an unused 0.0** -- V1.3e's `AGREEMENT_ACCEPT_MIN` -- so **the session ships NO TUNED
CONSTANT AT ALL**, `projects_constants.gd`'s position a third time, and
`tests/test_siting.gd` pins the deletion so a session re-adding it must bring a measurement
rather than an opinion. An **affine** factor was also written and replaced mid-build:
`1 + beta(c - 1)` goes negative past `beta = 1/(1 - c)`, **3.47 for Belgium**, which is
unrest RAISING approval, and a clamp there would have let the clamp set the number;
`pow(c, beta)` is positive for every beta, V1.6a's a-bound-with-no-number argument again.

**THE RE-RUN HELD THE PREDICTION EXACTLY, and the deletion is visible in it.** Both sides
from worktrees so the addon noise cancels rather than needing isolation, 1582 content lines
each, tails **byte-identical** (V1.7c's third-stray-line check run and clean): **44 of 47
regimes bit-identical**, the three movers exactly the FRA regimes where unrest fires, **zero
outcome changes**, and **approval identical in every printed row of every regime** --
because with the visibility price gone, siting reaches a voter only through `growth` and
`jobs`, the channel V1.5c measured as unable to reach one. Every moved figure went the
measured direction: GDP 2992 -> 2995, growth +1.18 -> +1.23, unemployment 8.14 -> 8.11,
grievance peak 48.38 -> 48.29. **No new regime and no new tick call** -- the site is a pure
read INSIDE `Unrest.tick_month()`, so both harnesses reach it through calls they already
make, which makes V1.5d's bug structurally impossible rather than remembered.
**`SAVE_VERSION` stays 29**, five absences pinned, and **`game_state.gd` needed no edit at
all**: its `typed_strikes` rebuild casts whole dictionaries, so the act record's four new
display keys ride through. The record carries the place because **a past act's site cannot
be re-derived once the shares have moved**.

**THE SCREENSHOT PASS FOUND ONE BUG AND IT WAS OLDER THAN THE SESSION.** `map_view.gd`
built its city list **once in `setup()`**, under a comment calling it *"static content, so
once rather than per draw"* -- true when V2.2b wrote it, false from V2.6a, which made a
city's population two live shares times a live head count. So **the crosses never grew or
shrank for a whole session** and V2.6a's own *"the map's brass crosses grow and shrink for
free"* was describing a readout that did not refresh; V2.6b1's ring, reading the same list,
drew nothing. Rebuilt on **U5c's monthly hook rather than per draw** -- this walks 581
cities and derives a site per nation, and V2.3 already paid for putting a rasterise on the
clock path, a class a screenshot pass structurally cannot see. **The proof is two frames of
one flag**: *"Lille -- 240 k"* before, **"Lille -- 245 k -- where the unions are out"**
after. `--site` zooms four times rather than twice, because at `--city`'s zoom the ring is
five pixels among several hundred crosses -- V1.6e's correction has a direction on a map as
well as in a scroll. One tool limitation recorded rather than fixed: a windowed capture can
receive a mouse-motion event and overwrite `_hovered_city`, so a hover label is present in
some runs and absent in others, identically for `--city` and `--hover-project`.
`test_geography.gd`'s register scan now **strips comment lines before matching**, because
`siting.gd` and `unrest.gd` each NAME `unemployment_rel` in a docstring while neither
touches it in code -- the correction that check's own sibling already records making, and it
makes the check stricter rather than looser. **V2.6b SPLIT**: the two halves share the WHERE
and not the PRICE, unrest's place being a derived report whose failure mode is constancy and
a campaign meeting's a verb whose failure mode is dominance, so **V2.6b2** owns campaigning
on V2.4a's travel days plus a per-region saturation counter. Model:
[docs/siting-model.md](docs/siting-model.md).

## V2.6b2

**V2.6b2 SITED THE CAMPAIGN, AND THE RE-BASELINE MOVED THE ANCHOR BEFORE IT MOVED THE WINDOW.**
The site is the PLAYER'S -- `Campaign.execute()` takes `region_id`, refuses a start without one
and refuses a region outside the acting nation's own live register, and **`Siting.site()` is not
called anywhere and must never be**: the verb whose place is chosen is the one proof the two sited
halves were never one shape. The month's accrual runs at the site's reach-per-day factor (the
principal city's share of the nation over the journey's travel days) times `(1 - spoken)`, where
`spoken` is the region's saturation -- one meeting month speaks to a region's whole attention,
clamped at 1.0, decaying on a half-life; the register is NOT cleared when the window closes
(attention persists) and the nine carry it empty forever. **`tools/tour_probe.gd` ran BEFORE any
src/ edit and corrected the model twice**: the draft's unbounded accumulator reorders the tour only
at accruals claiming 91-94 % of a region per meeting (the fraction form is the same claim bounded
in [0, 1] with one constant), and the recovery clause read on the tour's actual history was a
DOMINANCE clause in disguise -- incompatible with reorder at any fresh margin above ~2x (FRA's is
7.3x) -- so it measures the decay's timescale instead. **The dominance fell; the kill switch did
not fire.** The window re-baseline then came back EMPTY under V2.6b1's population-weighted
mean-one anchor -- worst move 0.176 against the 0.3415 lower edge at every window <= 12 -- and the
anchor was the defect, not the lever: **reach is delivered where the PLAYER goes, not where the
people are**, so the idiom does not transfer from an output price to a reach multiplier. Uniform
mean-one over the regions (capital x6.70) refits the band at every window; the recorded cost is
that a touring campaign runs ~1.4x V1.7a's expected price. **WINDOW AND HALF-LIFE ARE ONE
SELECTION** -- the calibration probe alone picks 5 and window 5 empties the tour band (recovery
needs `D <= W - 1`, reorder needs `D >= 4.75`) -- so the joint maximin over the lower edge, the
run's own MEASURED accumulator peak (the `rate x d` formula is retired from the rail clause; the
sited model's month-1 spike at x6.70 invalidates it), and the tour pair is a stable fixed point:
**`CAMPAIGN_WINDOW_MONTHS` 8 -> 10, `SATURATION_HALF_LIFE_MONTHS` = 6.5**, worst slack 23.0 %,
the rail binding the selection while never binding the accrual. **`SAVE_VERSION` is 30 on two
fields** -- `campaign_sites` (a verb writes it; a dropped site silently reverts a running effort
to the place-less national reach) and `campaign_saturation` (a dropped spoken-to register hands
every saturated region back at full reach: `campaign_started`'s exploit one level up, the tour
un-spoken). **The re-run held the prediction**: 46 of 49 common regimes bit-identical, the only
content movers the two campaign regimes (the ranking line now names its site; presidential share
25.6 -> 26.0 and 25.8 -> 26.0, both HELD), zero outcome changes; the third apparent mover was the
baseline worktree's own autoload noise, three contiguous lines after the last `invariants: OK`,
isolated per V1.7c. The new `managed_campaigns_tour` regime runs a genuine two-site tour (donor
circuit at FR1, stood down four months in, digital push at FRL) -- the decision the saturation
counter exists to make. **The screenshot pass found one bug and it was a label**: the running
effort's site line printed "x0.00 this month" against a month that had delivered a tenth of fresh
-- the register reads after the tick, when the meeting has just re-spoken the region to its clamp,
so `factor_of()` answers a hypothetical extra meeting -- fixed to print the spoken-to percentage;
`--site` also learned to photograph the ring the staged state actually has ("Marseille -- 867 k --
where the meetings are") instead of ticking past the run-up to find a demonstration. Model:
[docs/campaign-model.md](docs/campaign-model.md) section 18.



## V2.6c

**V2.6c SHIPPED NATURAL CHANGE, THE GATE'S OWN PREMISE WAS THE STALE ROW, AND THE V2.6 BLOCK IS CLOSED.** The decomposition note gated the session on regional AGE STRUCTURE from `demo_r_pjangrp3` -- and the sibling dataset **`demo_r_gind3` publishes `NATGROWRT`, the crude rate of natural change, directly per region**, so the measured quantity arrived without importing the 22 brackets and without authoring the age-mix-to-rate mapping demography-model §2 refused (a weighted sum nothing could measure). The gate's other half passed cold: **eight readers** of the shares already existed -- map crosses, city panel, region panel, the per-head index, migration's two pulls, siting, campaign reach, `labour_force()` -- so no new reader was needed and V1.5b's cut did not apply. **THE PARTITION, NOT A RE-BASELINE**: `ns.population` stays Economy's measured compound, `demography.gd` is untouched (the strictest leaf stays strict), and the regions redistribute the differential around a **live-share-weighted mean** -- `ds_i = s_i (nc_i - mean)/12`, telescoping exactly to zero, migration's invariant on a third flow. **THE ANCHOR LESSON'S OTHER SIDE, RECORDED WHERE THE NEXT SESSION WILL LOOK**: population-weighted mean-one is RIGHT here -- births happen where the people are, the V2.6b1 side of the line -- where V2.6b2 took campaign reach OFF it because reach is delivered where the player goes. The machine is one new leaf preloading NOTHING (`src/sim/natural_change.gd`, stricter than siting.gd: pure arithmetic, argument-fed, no writes), composed inside `migration.gd` so the share registers keep exactly one writer, **ungated by `MIGRATION_RATE`** -- zeroing the rate isolates migration, and the natural flow must run through that isolation for it to stay an isolation of migration alone (the guard moved from `tick_month()` into `_tick_nation()` for that reason). The rate reaches the flow through `Regions.natural_change()`, an accessor named for the QUANTITY rather than the field -- `share_of()`'s naming rule, because the one-reader scan is textual and an accessor that restates the field name IS a second reader to it.

**THE CONTENT IS MEASURED AND BRITAIN'S BOUND EXTENDED RATHER THAN BROKE.** Windows are the widest contiguous run in which every register code carries a value, rates averaged over them (the COVID years would otherwise date-stamp the field): seven nations 2012-2024, FRA 2014-2024, NLD 2012-2022 -- **NL31/NL33 vanish from THIS series one year before pjangrp3's re-coding**, each series gets its own vintage ruling, exactly as the gate predicted. **UKM (Scotland) publishes no rates at ANY year**: eleven of twelve UK codes are measured 2012-2018 (London +0.79 %/yr down to the North East's -0.07 -- a bigger spread than most nations' migration produces) and every British region carries 0.0, because a differential mixing measured and invented rates invents flows toward and away from Scotland no measurement supports -- V2.5's call one quantity over, with the numbers recorded beside it so the import picks them up the day Scotland publishes. Luxembourg TRANSFORMS as the plan said: no differential ever (one region cannot differ from itself; asserted EXACTLY unchanged after 168 months), but the national total was never bound. The plan-time probe's clause-(0) pre-check printed numbers 100x too large -- a permille-to-fraction conversion written once and not twice -- and the corrected estimate (FRA 0.0151) landed within 4 %% of what the sim measured.

**THE RE-SWEEP MOVED THE RATE 34x AND THE FINDING IS DOMINANCE.** Clauses restated before the run: (0) the natural flow ALONE must hold Europe's measured drift ceiling -- **0.01558, 95 %% of 0.0164, PASSES**; (i) readability is satisfied by natural ALONE at every candidate (FRA 0.00546 @60 with the rate at zero), so the clause **no longer selects** and the band's lower edge is the structural floor; (ii) the combined crossing sits at ~0.00057 -- **`MIGRATION_RATE` 0.0102 -> 0.0003**, midpoint stable across both full-band grids (V1.5b's refinement diagnostic). **AT THE RATES EUROPE'S DRIFT CEILING PERMITS, NATURAL CHANGE DOMINATES INTERNAL MIGRATION** -- the two flows point the SAME way in the model (Harris-Todaro pulls INTO the region whose births already outpace the nation; Ile-de-France is France's richest AND its most natal region) where real Europe's rich regions EXPORT people, so they compound and the ceiling holds the sum to Wien's number. The ceiling now binds at **2.5 %% slack** where V2.6a's migration-only model had 16 %%, and the pull form carries no congestion or housing-cost term -- **a later session that wants to raise the rate must first name the term that makes real Parisians leave Paris.** Spain's Melilla (most natal, WORST pull) and NLD's Flevoland are the live opposition cases, which is why `test_migration.gd`'s direction check now ISOLATES migration by zeroing the natural rates and restoring after. Attribution at the shipped rate: natural is 97-99 %% of the combined movement in nine of ten nations; ITA is the one where the flows visibly offset (combined below natural-only).

**THE RE-RUN HELD THE PREDICTION AND THEN SOME: 4 content lines of 1646 differ, all last-printed digits.** Both sides from worktrees (the discipline the plan wrote and V2.6a's session skipped once), 48 invariants each, tails identical, V1.7c's third-stray-line check clean. National headlines bit-identical in every regime; **zero outcome changes**; and the named watch-point -- **Germany's +0.4 %% siting margin -- HELD** (no siting line moved at all; the natural differential moves shares ~1.5 %% relative over fourteen years and the site margins are wider than that). `SAVE_VERSION` stays 30, eleven pins green; no new tick call, no new regime, no new UI -- the readouts that multiply the shares have shown the movement since V2.2b. Surfaces recount: **~15 and 4 new files against the row's ~12 and 2**, the instrument upgrade having removed the bracket pipeline the row's gate would have needed. **THE SCREENSHOT PASS FOUND ONE BUG AND IT WAS OLDER THAN THE SESSION, THIRD SESSION RUNNING**: V2.6b2's `_site_the_demonstration()` read `staged["city_id"]` off the empty dictionary bare `--site` stages, so the bare flag had crashed since V2.6b2 -- its own pass only ever ran `--campaign --site`. Fixed with `.get` and the reason at the call site. Frames clean: `--move` (ten years, Paris 2.4 M, ledger refreshed) and `--site` ("Lille -- 246 k -- where the unions are out"). Model: [docs/natural-change-model.md](docs/natural-change-model.md). **V2.6 CLOSES HERE; the next handoff is V2.7's decomposition call** -- network and resources, whose graph shape (per-region adjacency vs routed geometry) is deliberately undecided and is that session's first question.

## V2.7

**V2.7 SHIPPED THE NETWORK AND THE SITED PROJECTS, AND THE STEP-0 GATE ANSWERED THE TIER'S OPEN QUESTION BY COUNTING.** `tools/network_probe.gd` committed before any `src/` edit: adjacency over the committed polygons reads **every ring of every polygon** -- a reader taking only outer rings reports 12 components and 10 false isolates, because AT13, BE1 and DE3 are connected only through their hosts' HOLE rings -- and measured **243 edges, 9 components, 8 off the mainland**. Berlin reaches Hamburg in three hops and Milan in five THROUGH A THIRD COUNTRY, so the routed geometry the tier note reserved for transit buys nothing this roster can see; what adjacency cannot express is water, and water is **exactly eight authored sea links**, each a real crossing in service. Routed geometry is also a licence refusal this repo had already made: ODbL's share-alike attaches to derived databases and data/ would be one. **Clause (d) REFUSED the six-branch production mix** -- nama_10r_3gva's six NACE branches rank the 112 regions at Spearman **0.9170** against the three-key sector_mix, above the 0.90 clause fixed before the run -- so `production_mix` was never authored and `specialisation()` reads `sector_mix`, the refusal recorded beside the field that would have been. Clause (e) passed at |corr| **0.3360**: the network term is not the mix term renamed.

**THE GRAPH IS CONTENT WITH THREE PROVENANCES** -- `data/geo/region_graph.json`: adjacency derived, endowment measured (tran_r_net MWAY density at 2018, the only year carrying every register code because 2019 drops the UK for the FOURTH time in this import's history; rail refused on its own coverage table, 0 of 9 Austrian codes), sea links authored and each naming its crossing. `src/sim/network.gd` is a LEAF taking Dictionaries, the distance table cached per graph because the per-month recompute would put a Dijkstra sweep in every tick. The anchor is a THIRD KIND and was measured rather than inherited: output-weighted mean-one, because V2.5's spine closes only when every regional deviation is zero-mean in output weights. **DECAY_KM is derived, not swept**: 2924.9 km at the continental component's own mean eccentricity of 9.65 hops. The deviation in `regions.gd` now has THREE zero-mean terms -- mix, network, and sited-project payoffs -- collapsed onto one expression first (proven bit-identical, 1626 lines, filtered diff empty, BEFORE the constant went live), and the `access`/`sites` arguments are REQUIRED everywhere: a defaulted {} would silently run the pre-V2.7 model, V1.5d's own failure.

**THE SWEEP'S BAND HAS ONE EDGE, WHICH IS THE SESSION'S CENTRAL FINDING.** Clause (ii) never binds: at any candidate the output drift is 44x under SHARE_DRIFT_MAX and the population drift is pinned by natural change at 0.0160 against the 0.0164 ceiling -- the drift MIGRATION_RATE already owns. V1.5d's midpoint rule assumes two crossings and the measured band is [crossing, infinity) -- V1.5a's "a band an observable cannot reach is a bound and not a selector", recorded rather than tuned against. So the crossing ships, and the DIFFERENTIAL one: the channel's own fingerprint against the inert run is EXACTLY LINEAR at 0.010 pp per unit beta, crossing the 0.1 pp readability bar at **`NETWORK_BETA` 10.0** -- grid-independent by construction, and the total-move reading (confounded by the mix term's own 0.093 pp baseline) holds there too. **THE MIGRATION RE-SWEEP, THE PLAN'S SHARPEST RISK, CAME BACK IDENTICAL AT EVERY PRINTED FIGURE**: clause (0)'s natural-only row reads 0.01558 exactly as V2.6c left it, the shipped row 0.01599 exactly, and the interval is unchanged -- the third mover's contribution lands below the drift table's fifth decimal because migration owns 1-3 % of the combined movement. `MIGRATION_RATE` stays 0.0003; the ceiling stays binding at 2.5 %% slack.

**A PROJECT NAMES A PLACE NOW, AND THE PLACE IS DERIVED AND STORED NOWHERE.** The authored `project_sites` coordinate answers "which region" through a hole-aware point-in-polygon over full-ring geometry the loader now keeps BESIDE the renderer's outer-ring shape (Berlin's site lives inside Brandenburg's outer ring; only the hole says whose it is) -- all fifteen sites resolve. The payoff lands zero-mean on the site region while V1.6f's national channel still carries the level; the edge-cost cut a rail spine physically is was REFUSED because it needs a payoff-to-kilometre constant nobody could measure. The map lives on GameState as non-serialised derived state (`project_sited_pct`), rebuilt by the one module that owns completions and re-derived on load -- a stored site could disagree with data/nations/ about where the rail spine is. **`SAVE_VERSION` STAYS 30** on three absences pinned apart (graph, accessibility index, site region), and the disk round trip proves "content, not saved" did not become "content, not loaded either". **The re-run held the prediction and then some: 2 moving lines of 1647**, one a hundredth of unemployment and one a hundredth of growth (both the predicted Okun/unrest-siting chain), 48 invariants each, zero outcome changes, no new regime. **The screenshot pass found NO BUG for the first time since V1.6c** -- frames clean, fold probe stable, Corse the least-connected region reading the lowest reach on the new eighth column. Plan-draft bugs fixed in passing: the register payload iteration that would have crashed the graph build, and `write_geojson`'s arity. Model: [docs/network-model.md](docs/network-model.md). **V2.8's siting inheritance is direct** -- adjacency won, a click resolves to a region by `Projects.site_region()`'s own cast, and V2.8 sits on the register rather than on a path set.

## V2.8

**V2.8 MADE ENERGY PLACED, AND THE FIRST VERB WHERE THE PLAYER WRITES A COORDINATE
SHIPPED WHOLE -- the block was planned without the split the count asked for, and
the record says so.** The cold count was ~48 surfaces, 10 new files and FOUR
machines across two tracks, the largest this project has logged, and the a/b cut
was drawn and DECLINED by the author with the reasoning in the plan's own warning
box -- the count that would have split it is written beside the refusal. **The
step-0 probe found the row's likely assumption wrong in the direction that
mattered, before planning**: Eurostat, the source of every regional series since
V2.2, is short in two nations by two different failures -- `nrg_ind_id` carries
GBR only to 2019 and CHE is absent from the geo dimension entirely, `nrg_bal_c`
reads None for GBR at 2022 -- while the World Bank loop already running carries
all ten, so V2.8 needed no second source and no authored register. **The mix is a
PARTITION, not a stock**: World Bank measured shares are the baseline and built
capacity is the deviation, so with zero plants every derived quantity reads
EXACTLY its content -- asserted at 0.0, not 1e-9 -- and that is why the
bit-identity prediction was writable in advance and held exactly: the re-run diff
is 77 lines, every one an addition inside the two new regimes' own blocks, zero
outcome changes. **The denominator is measured consumption, not an invented
unit** -- `EG.USE.ELEC.KH.PC` x live population reads France at ~439 TWh against a
real ~445 -- and one reactor is **3 % of France and 63 % of Luxembourg**, which is
why capacity is a physical unit and not a share. **LUX's import dependency reads
109.6 % and is NOT clamped**: it re-exports fuel, and a clamp there is a number no
dataset measured. `EG.ELC.RNEW.ZS` includes hydro -- checked against CHE and AUT,
not assumed -- so the mix is three branches and `EG.ELC.HYRO.ZS` is deliberately
unfetched.

**THE TWO PRICES OF THE PLACE ARE THE SESSION'S MODEL, and the second one is
`Siting.concentration()`'s first pricer** -- V2.6b1 built that function, measured
it, designed a monthly price on it and found the interval EMPTY; a charge at
COMMIT is why the interval is non-empty here. `ACCESS_ELASTICITY` 0.30 and
`OPPOSITION_SCALE` 0.08, both bands written into docs/energy-model.md before the
sweep ran, both shipped at the interior of two smooth crossings -- and **one
clause refused to select and is recorded as a bound**: on a one-order-a-month
reading of "aggressive", the bloc_offset accumulator saturates at every scale
through the AUTHORED offsets alone (137 orders x -0.020, past the clamp with the
siting price at zero) -- U6a's legality-vs-want finding in a new place, so the
career clause selects on the sustained cadence and the spam run is a bound with
its number beside it. `DEP_BETA` 0.10 prices the dependency as a GROWTH ADDEND and
not a trend shift (V1.6e's employment argument), and the coercion amplifier was
REFUSED on V1.3g's own measurement that the nine never coerce each other over 168
months -- inert for every AI nation, recorded in trade-model.md rather than built.
**The handoff's obligation was measured, not inherited**: fourteen years of
sustained gas on the full harness stack reads FRA pop-drift **0.01599** against
V2.7's 0.0160, unchanged to the printed digit, so `MIGRATION_RATE` owes no
re-sweep; and the graph gains no accumulator, checked rather than inherited.

**THE COORDINATE AND THE REGION ARE BOTH STORED, WHICH INVERTS V2.7'S RULE ON
PURPOSE, and the two rules are opposites because the two facts are opposite
kinds.** `Projects.site_region()` derives every read because a stored site could
disagree with data/nations/ -- content is the authority. A plant's site is an
ACT, so there is nothing to disagree with and a contract to keep: `lon`, `lat`,
`region_id` and the frozen `connection` multiplier travel together, and a
re-imported geometry cannot re-price a station the player was quoted for. The
hole-aware cast moved whole into `src/core/region.gd` because two copies of a
geometry predicate is how one of them quietly stops agreeing with the other, and
the trap is silent -- an enclave's own polygon sits inside its host's outer ring,
so a cast over outer rings alone files Berlin, Vienna and Brussels under their
hosts with no error anywhere; the enclave case is a test. **The grid is national
and the refusal is a CHECK**: `tests/test_energy.gd` reads `src/sim/energy.gd` and
fails if it ever preloads `regions.gd`, so a later session adding a regional
energy channel turns red and has to come and say why. `ISSUE_KEYS` answered NO for
the sixth consecutive session, recorded beside the list. **`SAVE_VERSION` is 31 on
three fields of eight** -- `start_energy_mix`, `start_import_dependency_pct` and
`energy_kwh_per_capita` are content-derived statics `from_dict()` cannot
re-derive, V1.6a's finding at its strongest; the other five earn nothing and are
serialised anyway, and `last_energy_result` is not serialised at all. Tasks 3+4
and 11+12 each landed as one commit because the suite's generic walkers and the
shared click path make the pairs atomic -- said plainly rather than papered over.

**THE TWO NEW REGIMES ARE OF THE EXPENSIVE KIND** -- a plant is a verb no budget
regime issues, V1.3g's and V1.4c's case -- and `managed_builds_nuclear` against
`managed_builds_gas` on the identical managed budget is what makes the channel
legible: the builders' surplus shrinks three tenths of a point and their debt two
points (the same budget buying a fleet), both drive `students` to 25 (the authored
offset and the siting price landing on one register), and gas's final-year growth
reads +0.14 against +0.26 -- DEP_BETA's 0.38 points over the window, visible and
not dominant. **The screenshot pass found two bugs and both were real**: the
energy bill sat inside the spending total with NO "of which energy" row -- V1.4a's
silent-write class, live on a panel, row + snapshot key added -- and `--place`
buried its own filled glyph under Paris's 9.6px city dot while the reticle drew
wherever the OS cursor had been left, so the flag now sites at each region's
smaller named city and warps the cursor to the frame's centre. One tool artifact
recorded rather than chased: the staged fleet row reads months-left two months
behind the sim's true figure (date advances 14, energy ticks 12; headless
arithmetic exact), V1.4c's date/state race in the tool and not the game. The
frames were judged in-session -- the vision path V2.5 opened held. Model:
[docs/energy-model.md](docs/energy-model.md).

## V2.8.1

**V2.8.1 REPAIRED THE PLAYTEST'S BUGS, AND V2.9 BUILT THE PLAYER'S SEAT — both off
the 2026-09-05 play report (`reports/playtest-2026-09-05.md`, gitignored), which played two
full terms through the real UI and returned "a serious simulation wearing no
game." Two branches, one block each: `v2.8.1-repair` (five readout fixes: the
election modal's collapsed table — the one content panel without
`SCROLL_MODE_DISABLED`, its seats column stacking em dashes where no seats exist,
now bars under the ledger à l'économy panel; Overview counting the ASSEMBLY's
clock beside a Diary saying May 2027, closed as decision-log U3 with the finding
that neither figure was wrong — they were on different clocks, so
`Trends.vote_date()` is now the ONE source; the nation-select row that already
reserved its height, whose test-asserted geometry challenged the plan's own
fix; disabled buttons dropping the live EDGE border, Godot painting brass focus
over any state; cooldown tooltips saying Cooldown) and `v2.9-player-seat` on top
(the seat: the top bar's "NEXT VOTE 16 mo"; the opening card "Your term — You
hold France until May 2027 — 16 months. Win the vote.", new-game only; every
committed verb answering with a card — budget deficit, law division, act
refusal-with-reason — by widening three panel signals, one shared by six panels
and kept intact; foreign-act cards grouped per action per month, four state
visits one card; a decision's ARRIVAL pausing the clock, interrupt or not, the
flag keeping only its Dispatches-opening extra; the card itself the answer
surface, `Events.choose` through the same chain Dispatches uses, unpausing
through one writer; and the election owning the screen — blocking, dimmed,
verdict and What-decided-it ABOVE the table, 860x600). **The suite caught the
session's own regression and the point is general**: the arrival pause gave the
clock a second pauser and `test_election_panel`'s driver stalled at March 2027
reading an empty panel — any loop that treats "paused" as "the election
happened" is now behind the feature, and its driver answers what lands on the
desk like a player. `SAVE_VERSION` stays 31; `git diff --stat main..HEAD --
src/sim/ src/core/` is EMPTY — every mechanism is readout, wiring or clock
policy, so the balance gate held by construction (test_balance green, zero
outcome changes possible from zero sim diffs). Screenshot pass: `--election` is
the twenty-ninth flag (its own loop — `_tick_months` DISMISSES the election by
design), two frames judged clean; two nits recorded, not fixed: the opening
card wraps "Win / the vote." onto a third line, and the default-choice marker
truncates at card width. `.gdskills/` is gitignored now. V2.9b (the agency
probe — idle won 26.2, active lost 23.4, the playtest's F6) is the next row and
it is a MEASUREMENT session, not a build.

## V3.0

**V3.0 TUNED THE AGENCY PROBLEM AND THE GATE CAME BACK FAIL BY MEASUREMENT —
which is the outcome the plan named, not a session failure.** A second playtest
of the seat (reports/playtest-2026-09-05-b.md, gitignored, state-verified
through the runtime bridge — no vision path this harness, frames to the author)
confirmed every V2.9 mechanism live through a full term to re-election and
measured the tier's two structural gaps: **the Union is one panel with eight
members and an empty council**, and **max zoom halves the game's own clock
(0.50 vs 1.12 game-days/sec)**. The V3 tier is drafted in
[docs/tiers/v3.md](docs/tiers/v3.md) — agency first, map platform, alliance
system, EU-27 roster in tranches, roads on the V2.7 graph, V2.10/V2.11
absorbed — **pending the author's sign-off**, and V3.0 was executed on that
draft's first row with bands pre-declared in `BALANCE_PLAN.md` before any run.
What shipped: **honeymoon and fatigue as a PURE READ of
`Elections.months_in_term`** — the S5 deferral discharged with no new field and
no `SAVE_VERSION` move, because the counter had existed since V1.2 and the
plan's own `inauguration_month` + version bump were deleted at execution time
(the init-exactness pins forced `offset(0) == 0.0`, which killed the +6-day-one
shape before it ran); the **fiscal re-weight** (income scale 8 → 24, shared tax
8 → 16, `SPEND_SCALE_PP` 3 → 6, `DEFICIT_SCALE_PP` refused at 6.0 after the
halving clamped the spend side's pain and crashed budget-spend to −13.03); the
**grievance relief** (`unrest.gd::relief()` — the mobilised blocs' gross
improvement, gain-amplified on the improving side after the unamplified form
measured 11.4 → 9.3 against a 6.85 target at scale 45), V2.9b F2's path back;
**`UNREST_THRESHOLD_PCT` 45 → 14** — the same scales took the austerity peak
from ~45 to a measured **18.02** and the strike agent became unreachable,
which `test_unrest`'s reachability check caught (tools/measure_austerity_peak.gd
committed as the cited instrument); **B4 REFUSED** — the campaign binder is the
authored 0.03 mobilisation content, not the cap, and at the cap the channel
buys only +0.4 vote, so the content stays and the ceiling is recorded in
campaign-model.md; **B5 monotone**, `INCUMBENT_SWING` untouched. The probe's
bottom line: best active style **−2.00 approval points vs idle, from −7.57**;
vote deficit 3.0 → 0.2 points; the GATE's +1.0 is a measured bound on every
declared lever, and the three design routes past it (competence credit as a
channel, an activity-keyed drag, or accepting the bound) are the AUTHOR's call,
recorded in reports/agency-probe-v3.0.md. `test_balance` was re-contracted
where the findings invalidated premises: the do-nothing France run now LOSES
its 2031 re-election to fatigue (the playtest's F6 ask working — the re-run's
other fatigue flips: redistributive, managed_then_redistributive; and the
honeymoon GAINS managed_captures_the_courts its 2027 vote, a side effect
flagged, not tuned away), and the ten-year clamp watches run past office loss
via a `stop_on_loss` param. `test_opinion`/`test_tax` re-pinned with the
measured numbers beside them. Suite 79/79 green, names clean, two screenshot
frames (polling, economy) captured for the author. Handoff:
.superpowers/sdd/v3.1-handoff.md.

## V3.1

**V3.1 SHIPPED THE MAP PLATFORM, AND THE STEP-0 PROFILE REFUTED THE ROW'S PREMISE IN
BOTH HALVES — the session's first result, before any code.** The handoff's gate was
P4's "max zoom halves the game's own clock (0.50 vs 1.12 game-days/sec)", and the
committed instrument (`tools/frame_probe.gd`, the `measure_austerity_peak.gd` precedent)
killed it with its own regime: **`clock.gd` is time-based** — delta accumulation with a
catch-up `while` — so render cost cannot slow it, and under P4's own conditions (vsync
on, 1440p, speed 1, days counted from the clock's signal, **pause state logged**) the
clock reads **0.999/0.998 days/sec** at fit/max zoom. P4's 1.12 and 0.99 are 9/8 and 8/8
— day quantization of an 8-second sample; the 0.50 is 4/8, a clock PAUSE (the V2.9
decision-arrival pause is the likeliest biter) inside a sample whose pause state was
never recorded. The instrument now records it, so this artifact class cannot pass for a
render number again. **And there is no deep-zoom cliff**: true frame cost (vsync off)
ran 4.40–4.75 ms across the entire zoom range before any work — max/globe 1.02–1.07,
inside the tier's own 10% gate — because the engine replays a cached command list. What
was real is a **~3.6 ms zoom-independent constant**: ~900 draw calls and 68k primitives
replayed every frame (no-map baseline 0.83 ms; geometry: world 251 rings/10 011 pts,
roster 58/4 100, regions 265/9 267, 581 glyphs). **So V3.1 shipped culling, not a LOD
platform, and the gate restated on frame time passed with room to spare: max zoom now
0.51× globe view (2.10 vs 4.13 ms at 1440p) and map cost at deep zoom 1.33 ms against a
pre-declared 2.0 ms — deep zoom is VIEWPORT-BOUNDED, which is the property V3.4's
per-frame animated roads buy.** The cull is a lon/lat bbox per ring (`_ring_reaches_view`,
pad `CULL_PAD_PX = 8.0` DERIVED from the widest stroke, not swept — no BALANCE_PLAN band
exists to record), applied inside the world, roster-fill, region-fill and stroke passes
with **the two-pass enclave rule preserved by construction — the hairline list is built
only from rings the cull let through** — and city glyphs culled on SCREEN points because
their populations are live state, V2.6a's lesson applied to the cull; the hit test is
untouched and `_city_at_screen_point()`'s source-policing contract held. Minimap redraws
on view change now (its 0.35 ms every-frame delta was mostly GPU replay — the change-test
is right design, the saving small, said so in the doc). `tests/test_map_cull.gd` checks
the predicate against a naive bbox over EVERY ring at two framings rather than one fixed
"far region", because **the headless window is square (1920×1920, where a Paris max-zoom
view legitimately reaches Madrid)** — a spot-check would have been aspect-brittle.
Identity acceptance: **0 differing bytes × 4 zooms, same-tree, clock frozen** — and the
method cost two tool findings worth keeping: **same-tree runs are byte-deterministic,
cross-tree runs differ in ~0.3–0.4% of bytes** (sparse AA phase noise, best-aligned at
offset (0,0) — judge identity same-tree or not at all), and **a capture straddling a day
flip is a different frame** (V1.4c's race class live), so `screenshot.gd` grew `--zoom`
and `--paused` — and `--paused` must freeze on frame 1, NEVER in `_init()`: a SceneTree
script's `_init` reads main's `@onready` vars as Nil, the first version silently ran
unpaused, and three of eight captures crossed a day flip. The same Nil-in-`_init` bit
frame_probe's first draft the same hour. Refusals recorded in the model doc: per-tile
raster LOD (the raster is one quad; fill rate did not move 1080p → 1440p), glyph
clustering (no overlap at current thresholds), cached fills (the engine caches), polyline
LOD (the named-but-refused lever if the everything-visible band ever breaks budget).
`git diff main..HEAD -- src/sim/ src/core/` is EMPTY, `SAVE_VERSION` stays 31, no balance
re-run — U-track only, and the re-run prediction (bit-identical) held trivially.
Screenshot pass: vision WORKED this harness — identity frames and diff crops judged
in-session. Model: [docs/map-platform-model.md](docs/map-platform-model.md). Handoff:
.superpowers/sdd/v3.2-handoff.md.

## V3.2

**V3.2 SHIPPED THE ALLIANCE SYSTEM, AND THE STEP-0 AUDIT CORRECTED THE HANDOFF BEFORE
ANY CODE — `bloc_offset` is the VOTER-bloc opinion channel (six electoral blocs) and
carries nothing org-shaped; the bloc machine's opinion surface is the `europe` ISSUE,
one-signed by bloc-model §1's own argument. So "multiple orgs writing the same
channels" resolved to ONE clamped burden — no second approval number is structurally
possible because no second channel is touched (V1.5c).** The audit also found membership
DUAL-SOURCED (nation files' `government.eu` + `data/eu_parliament.json`, held together
only by cross-validation); the register collapsed it to one source and the validation
died with it. Track (a) is the register — `src/sim/orgs.gd` replaces `bloc.gd`,
`src/core/org.gd` the content type, `data/orgs/*.json` the four authored orgs (eu,
eurozone, schengen, nato), `NationState.orgs` LIVE membership, `SAVE_VERSION` 32 on the
bloc->orgs rename (three fields, bloc-model's argument verbatim) with
`GameState.accessions` serialised from day one and `org_effects` NOT serialised
(project_sited_pct's case, pinned) — and it is **BIT-IDENTICAL, as predicted: 1680 of
1680 printed lines, zero outcome changes**, both sides from worktrees. The two co-member
prices moved into eu.json UNCHANGED (relations 15.0, trade 0.50) and the eu agenda kept
flat-file order — that is what the identity run proves. `Orgs.init_state()` runs BEFORE
`Diplomacy.seed_relations()` because resting relations now read live membership.

**Track (b) moved exactly through its named channels, and the FIRST draft of the fight
content was UNWINNABLE — the test caught it, not a probe.** Accession/withdrawal is
referendum-first (machinery reused whole — `Referendum.announce()` takes any question
id), then an authored negotiation countdown (eu 24 months, Art. 50's shape), then the
flip; the draft withdrawal position (econ +0.45) measured yes_share **0.347**, and
`tests/test_orgs.gd` fails on it by running the real vote, so the shipped positions are
swept on Referendum's own curve (**0.510-0.523 at rest** — winnable by a president the
country does not hate, losable by one it does). The 2 % floor MOVED to NATO's new
council (authored, population-shaped seat weights — NATO has none in reality and the
machinery needs numbers), taking the eu agenda 7 -> 6; seats GENERALIZED from EP-only to
any council org because a zero-weight council can never divide, which the loader now
refuses. Embassies and foreign aid landed on the relations channel, the two parked V1
rows, magnitudes anchored on the measured ladder and stated in the file's own _note.
Measured re-run: 47 of 51 regimes differ at 3-5 last-digit lines; **the ONE outcome
change of 99 outcome lines is GBR `managed_abolishes_the_monarchy`** — a 2029
rounding-boundary wobble compounding through the openness channel (trend 1.32 -> 1.30,
V1.3f's own signature) into a 2039 election flip (33.3 % HELD -> 23.3 % LOST). Refusals
recorded in docs/orgs-model.md: no org-side consent for accession (an admission vote has
no material term the appraisal can price without a new term type), no AI desire for
membership (inventing one unmeasured is the synthetic-appetite shape), Eurozone and
Schengen zero-priced with a named trigger (a measured band and a BALANCE_PLAN
pre-declaration, not an opinion), no war. Suite 80/80, names clean; the screenshot pass
found ONE BUG and it was in the TOOL (a rename the staging had not caught), visible only
because the frame's own numbers disagreed — Standing 0.00 against a fine the panel
recomputed live. **No handoff file written at closeout, per the author's standing
instruction for the rest of V3** — v3.3-handoff.md exists and its UNFILLED markers stay
untouched by this session. **The block's closeout ran the PR-review-merge gate, and the
review EARNED IT: bugbot found 1 critical + 3 major + 1 minor, all in the fight machine
the re-run structurally cannot reach** — a save during a fight dropped its `phase` at
load and stranded every membership verb forever; an acceded nation joined with zero seat
weight, zero EP seats and zero contribution (three content-table reads where the design
says live); the EP clock was written from static content, so a post-2029 accession never
voted again; the org's measures aimed at a joiner survived the join; and one test's
re-derive check was vacuous (every member compared against one reference member). All
five fixed pre-merge: `NationState.org_seats` live voting weight seeded from content and
rewritten from the org's authored `accession_seats` at the flip, `phase` serialised,
`Orgs.reconcile_on_load()` ends stranded referendum fights honestly, net positions
re-derive over the LIVE roster, EP clock rolled forward in whole terms — each with a
regression test, suite 80/80 green. Model: [docs/orgs-model.md](docs/orgs-model.md); bloc-model
stands as the one-org record with a forward note.

## V3.3

**V3.3 GREW THE ROSTER TO EU-27 + 2, AND THE STEP-0 AUDIT CORRECTED THE TRANCHE LABEL
BEFORE ANYTHING RAN** — the loader REQUIRES parties, people and a full government block
for every nation, so the tier's "(a) no politics" was impossible as written: (a) shipped
the complete political content for the nineteen and deferred only portraits/playable/
screenshots to (b). The import machinery is one roster list plus per-nation tables; the
nineteen arrive at NUTS 2 without exception, five single-region on the LUX precedent
(CYP EST LTU LVA MLT). **THE REGISTER IS 213 REGIONS, 1 065 CITIES, 463 EDGES (447 LAND + 16 SEA
LINKS), ONE COMPONENT** (this row first said 464; corrected at the V3.4 close
from `data/geo/region_graph.json`, whose 463 edge records tag 447 `land` and
16 `sea`) — components counted before authoring (18), each link a real
crossing (Oresund, Great Belt, the Greek archipelago from Piraeus/Igoumenitsa, Malta,
Cyprus; Ireland needs none over the UKN land border). **THE NINETEEN MEASURED THE
IMPORT'S ASSUMPTIONS DEAD IN FOUR PLACES**: Portugal's NUTS 2024 SPLIT AMLisboa (the
vintage join grew a partition-sum shape beside NL's 1:1; exact because GDP/GVA are
additive stocks and the unemployment file answers 2021 natively); Aland carries NO
GeoNames place at all (cities15000's cut is above Mariehamn) so a region the register
cannot name drops into the residual and its sea link died with it; Greece has NO
tran_r_net MWAY rows at any year (27 codes fall back to the roster mean — a bound);
Cyprus broke the bounding box (LON_MAX 32→35; the fit is lat-bound and did not move —
recomputed at 2.08, CITY_MIN_ZOOM stays). **CITY_MIN_POP re-swept 71 000→58 000** on the
pre-declared band (crossings 38 000/78 000, both smooth, interior ships, same answer at
two grids). **THE WB CACHES WERE TEN-COUNTRY FILTERED** — every indicator re-fetched
with 29 (per_page 2000: 29×35=1015 rows), through an API 5xx window that ate an hour.
**SAVE_VERSION 32→33 ON NO FIELD** — the roster is content, but a v32 save made against
the ten-nation roster loads, unrefused, as a silent ten-nation world against 27-member
org data: the roster a save was made against is part of its contract. **THE SUITE
CAUGHT SIX REAL THINGS**: Slovenia's 1990-2024 inflation mean is 30 %/yr (transition
decade) so the anchor re-windowed to the euro era 1999-2024 for every nation (Rule 1)
— the ten's anchors move −0.05..−0.5, BALANCE_PLAN addendum 2; the cycle anchor DOUBLED
(transition years are real volatility; LVA's growth SD is 8.6 points) so
CYCLE_AMPLITUDE_PCT re-denominated 1.70→3.245 — products invariant <0.1 %, addendum 1;
LUX's contribution formula ran PAST the 1.20 ceiling (EU-27 mean is poorer; ceiling
re-derived by its own placement rule → 1.35); the 27-seat council made constructive
abstention unreachable on EVERY proposal, so debt_reduction_rule's position re-authored
on the tally probe to land in the player's pivotal band (385 for of 639 cast — abstain
carries, opposing blocks, backing passes); EVEN_SHARE was the literal 1/9 and every
stake/accept term priced at a third of its meaning (DEU refused a deal the model was
calibrated to sign) so the anchor derives now — foreign_policy.even_share(state), ten
readers, map ramp and legend with it; and IRL's collected revenue is suppressed by its
MNE-swollen GDP base, so its income rate is the fitted effective 12.7 on AUT's
convention. **THE BALANCE RE-RUN HELD THE GATE**: 2 019 of 3 360 compared lines moved
through exactly the predicted channels (cycle product, inflation window, trade gravity,
org composition, relations seed, network accessibility), **ZERO outcome changes of 94**,
50/50 invariants. **POL IS THE FOURTH PLAYABLE** — companies, outlets, opening scenario,
the flag — on the counted cut that the playable kit is a content tranche, not a boolean;
the other eighteen wait for theirs. Portraits: the author paused the pipeline for a
ComfyUI rewrite — 213 raws exist locally, the duotone pass is pending the rewrite
(missing art is the silent silhouette by design). The screenshot pass ran windowed and
judged in-session. The concurrent-godot crash (two processes sharing .godot caches die
silently at ~340 s) is an environment rule learned the hard way: **serialize godot
runs**. Model docs: geography-model §9, network-model §12, orgs-model addendum,
natural-change/migration single-region notes, BALANCE_PLAN addenda 1-5.

**V3.3f: THE GAME SHIPPED UNCLICKABLE AND THE SUITE SAID GREEN.** V2.9 made the
election panel *blocking*, and `_add_centered()`'s blocking branch tied only the DIM to
the panel's visibility, never the HOLDER -- and a `CenterContainer` defaults to
`MOUSE_FILTER_PASS`, so a full-rect holder over an invisible panel took every click on
the screen from a new game's first frame. Map, bottom bar, windows, HUD: all dead, and
nothing errored. `test_shell.gd` already owned the right check and the wrong SCOPE --
`_check_no_blocking_holder_at_start()` named the pause menu's holder alone, which is the
one panel that had been hiding its holder by hand since U5a, so the check could only ever
pass. The fix is in `_add_centered()` (the holder follows the panel, so the next blocking
panel cannot forget), and the check now asks the question the way the player asks it:
push a motion at four points, read `gui_get_hovered_control()`, fail unless the click
reaches the map, a window or the HUD. **A structural check that names one instance is a
check for that instance, not for the rule** -- and a bug the player meets in the first
second can sit behind a green 80/80 for a whole tier.


## V3.4

**V3.4 DREW THE GRAPH AND SHIPPED NINE FALSE OR OVERSTATED CLAIMS -- REVIEW CAUGHT ALL
NINE, THE SUITE CAUGHT NONE, AND THE PATTERN UNDER THEM IS ONE SENTENCE: A CLAIM'S
CONFIDENCE TRACKED HOW GOOD IT SOUNDED RATHER THAN HOW IT WAS OBTAINED.** Three
committed comments in Task 2 (an INVENTED AT11-AT12 worked example -- they are 0.53 deg
apart and no edge in the register has coincident axes; the Channel named as "the shortest
crossing" when FR1-UKI is 343.8 km and TWELFTH of sixteen, the shortest being DK01-SE22
at 28.4; and a FIX ROUND'S OWN NEW COMMENT crediting a test with a scan it did not
perform), three more in Task 5 (a section number pointing at a file with no such section,
PACE_KM_PER_DAY justified by an unobserved claim about how the animation reads, and a
MAX_CONVOYS glyph collision nobody had measured), one in Task 7 (a test comment about
what a single call would miss, disproved by the reviewer), and two in Task 8 -- a
**FABRICATED GIT CITATION**, a SHA quoted as provenance that is unrelated V1.3f diplomacy
code, plus a convoy tail of 7 marks that MAX_CONVOYS 3 per direction structurally cannot
produce. None was a lie and none was careless prose: each was a plausible specific
written in the voice this project rewards, by an author who had not gone and looked.
**The remedy is structural, not diligence: assert only what you have verified and say in
the same sentence how.** **AND THREE TESTS COULD NOT FAIL, each found by the NEXT task
rather than by the suite** -- `_main._map_flows` on a Node lacking that member RAISES
rather than reading null, so four checks aborted as SCRIPT ERRORs while the file printed
"all checks passed" and exited 0 (only the runner's separate script-error gate saw it);
a source-policing check sliced `func _draw_convoys` to the next `\nfunc ` while the code
it policed lives in `_draw_convoy_run()`, so the slice held a DOC COMMENT that happened
to contain the words it looked for and a planted `randf()` did not fail it; and a
`Rect2.has_point()` assertion could never pass because that method is HALF-OPEN.
Mutation-verify every new assertion. **THE INSTRUMENT WAS WRONG BEFORE ANY OF IT WAS
TRUE, AND ITS WRONG ANSWER WAS A PASS**: the gate rows first sampled with the clock
PAUSED, and `map_flows` only queues a redraw while the clock runs, so they priced an
already-recorded canvas item and reported the overlay at a false **0.24 ms**. Third
instrument finding of this kind in the project's history (P4, the Nil clock in `_init`,
now this); `frame_probe.gd` now carries a "run" key for rows that must pay the per-frame
re-record and prints the clock regime beside every sample.

**What shipped, and it is U-TRACK BY MEASUREMENT: the track row said `S + U` and the
block built `U`.** V2.7 modelled a transport graph that had never drawn a pixel and
V1.3b derived a directed trade weight for every ordered pair that had never drawn one
either; V3.4 draws both. **463 spines** (447 land, 16 sea) between adjacent regions'
`cities[0]` -- the same anchors `build_region_graph()` measured its kilometres between,
so the line on screen and the distance the model discounts by cannot disagree -- as
`_draw_spines()`, the **eighth** draw pass `map_view` now owns (the fourth it calls),
gated on the EXISTING `CITY_MIN_ZOOM` 2.0 with no new constant and nothing swept. The sixteen sea links are dashed and the land edges solid:
ONE hue at two alphas, because a road never needs picking out of the map, only reading
off it. The animated layer is a **sibling overlay** (`src/ui/map_flows.gd`, a separate
full-rect Control, `MOUSE_FILTER_IGNORE`, camera mirrored through
`visible_lonlat_rect()`, culling in DEGREES before it projects): directed trade arcs
below the gate, moving convoys above it. **NOTHING IS STORED** -- a convoy's stagger is
`Cycle.unit()` of the edge key and direction with the mark's index and its phase advances
off the sim clock, so pause freezes it and a reloaded save puts every convoy where a
fresh clock would. `SAVE_VERSION` stays **33**, `git diff main..HEAD -- src/sim/
src/core/` is EMPTY, and **the balance re-run was predicted bit-identical BEFORE it ran
and came back stronger than the prediction: the two captures are byte-identical
UNFILTERED -- 1 697 of 1 697 raw lines, one md5, a zero-line diff**, 50/50 invariants OK
each side, zero outcome changes. Both sides ran from worktrees (bfcda29 and c4ba7df), so
even the addon parse noise cancelled and the comparison needed no filter at all -- which
is also why V1.7c's third-stray-line trap could not be sprung: the filter removed ZERO
lines from either side and therefore hid nothing. Surfaces recount: **5 new source files against the row's 4** (`map_network.gd`,
`map_flows.gd`, their two tests, plus `tools/roads_probe.py` -- the step-0 instrument the
count did not anticipate), 11 files modified.

**THE STEP-0 MEASUREMENT CAME BACK THE OTHER WAY AND THE REFUSAL HAD TO BE REWRITTEN
AROUND A TEST NOBODY HAD WRITTEN DOWN.** Natural Earth 1:10m roads -- public domain, so
never a licence problem -- PASSED coverage at 212/213 regions (99.5 %) where the row, the
handoff and the plan all assumed they would fail, and the first implementer stopped
without committing rather than write a refusal its own numbers contradicted. Correct
call. They were refused on **EDGE IDENTITY** instead: road properties carry
name/type/sov_a3/length_km and nothing naming a region or an edge, so **0 of 463 graph
edges can be looked up in them**, where derived spines score 463/463 by construction. The
decorative under-layer was declined on measured cost (Major Highway alone is **+77 %
vertex mass** on a map whose whole geometry is 37 861 points, landing in the
everything-visible band where culling removes nothing). Geometric attribution was NOT
measured and is therefore NOT refused -- recorded as open in docs/data-sources.md. **A
CORRECTION THIS BLOCK MADE: the graph is 463 EDGES, not 464** -- one number written three
places (network-model.md section 12, AGENTS.md's own V3.3 row above, and the V3.4
handoff), wrong in all three, corrected here against `data/geo/region_graph.json`.

**FOUR NEW GATES DECLARED AND ALL FOUR MEASURED -- TWO FAILED FIRST, AND THE FIX IS
LOAD-BEARING RATHER THAN POLISH.** Uncapped, the overlay put **G4 at 3.01 ms against 1.5
and G5 at 13.73 against 11.0**; the design's named fallback was taken (`map_flows`
rate-limits its own `queue_redraw()` to `REDRAW_HZ` 30, camera moves exempt) and the
re-measure passes all four: **G3 6.94-7.88 ms** (gate 8.0), **G4 0.59** (1.5), **G5 8.88**
(11.0), **G6 1.000 days/sec**. The failing numbers are recorded beside the passing ones
in map-platform-model.md section 4, and the cadence is pinned by five mutation-verified
assertions. **THE CAP COVERS A STILL CAMERA ONLY, and review caught that nothing had
measured a drag**: a dragged frame costs **97.75-99.42 ms -- 10 fps, 9x G5** -- and
**91-93 of those ms are NOT the overlay** (`map_view`'s own re-record is ~69 ms, and the
TRADE layer's roster fill costs 14-17 ms more per re-record than POLITICAL because
`map_layers.swatch()` calls `Trade.weights()` TWICE per nation). Both predate V3.4;
recorded as an OPEN ITEM and deliberately unfixed, because capping the camera move trades
a frame cost for a worse visual defect -- the overlay detaching from the coastline under
the cursor. Spun out as `task_022b47f3`. Strongest evidence yet FOR the block's
architecture: the file header claimed animating inside `map_view._draw()` would be
unaffordable, and it now has a number, and the number is 69 ms. A second open item, also
spun out (`task_a06604dc`): a **~15 s main-thread stall on an event decision**, 15.78 s
wall against 0.72 s counted delta, frames not scheduled at all; `await`, `Thread`, sync
`load()` and timer chaining ruled out by reading -- real freeze vs unattended-window
artifact UNDECIDED, and it needs timestamps rather than more inference.

**FOURTH SCREENSHOT PASS RUNNING TO FIND A BUG, AND THE FIRST TO FIND ONE YOUNGER THAN
ITS OWN SESSION.** `tools/screenshot.gd` called `show_layer()` with one argument, correct
since U5c -- V3.3c (two days earlier) gave it state + viewer_id and updated `main.gd:733`
but not this caller, so **every `--layer trade` frame since had photographed a ramp legend
with no ramp rows**. A signature change that updates one call site of two, in a tool no
test covers, is invisible until somebody looks at a frame. Seven frames judged, every
verdict citing a colour, a count or a pixel run along a computed line, with the vision
path verified against an unrelated pre-existing capture BEFORE any claim was made: roads
read as a network (hubs at Paris, Madrid, Lyon), a ferry is unmistakable by stroke alone,
and convoy asymmetry was COUNTED at ~2x on cross-border spines against internal ones --
V1.3b's directed weights finally drawn. Two honest negatives kept: **the 7 px arrowhead
does not resolve at zoom 1.6** (direction reads by hue and bow; the head is sized for
zoomed-in reading and was left alone), and **DK01-SE22 -- the shortest crossing, the
question `map_network.gd` had deferred by name -- IS INVISIBLE at the zoom roads first
appear**, 10.6 px against a 12 px dash cycle with two ~5 px city markers covering the gap.
Frame and arithmetic agree to the pixel; the constants were left alone because no shrink
rescues 10.6 px between two markers. Suite **82 files** green, names clean. Model:
[docs/network-model.md](docs/network-model.md) section 13;
[docs/map-platform-model.md](docs/map-platform-model.md) section 4 and section 7, whose
obligation this block DISCHARGED and re-issued: **any further animated surface uses the
same split**, and **a cap on a redraw is a cap on the IDLE rate only**.

## V3.5

**V3.5 SHIPPED ENVIRONMENT AND CLIMATE, AND THE BLOCK'S OUTPUT SHIPS NO TUNED CONSTANT
AT ALL -- `projects_constants.gd`'s position a fourth time, this one by design rather
than by swept-and-deleted.** The disasters' magnitudes are authored effects on the two
channels every event already rides (spending_pct_gdp, bloc_offset), the ceiling's value
is DERIVED, and its tolerance and the accession positions were swept with the evidence
recorded in the content's own `_note` lines -- so BALANCE_PLAN.md's V3.5 section
pre-declared no band and made that absence its entry, which is why the re-run
prediction was written in channels rather than digits. What shipped: an emissions read
over V2.8's mix, two sited disasters, the climate accord as a fifth org on the V3.2
register, `SAVE_VERSION` 34 on ONE field, and the closeout's readout line on the energy
panel. Model: [docs/climate-model.md](docs/climate-model.md).

**EMISSIONS ARE A READ OFF THE MIX, NOT A STOCK, AND THE EXACT-ZERO PROPERTY IS
ASSERTED RATHER THAN ARGUED.** The baseline is the measured per-capita footprint
(`imported.emissions.co2e_per_capita_t`, WB `EN.GHG.CO2.PC.CE.AR5`, **29 of 29 at
2024**, so the nearest-year loader falls back for nobody; the AR4 code is retired and
data-sources.md records the probe that found the successor), and the fleet is the
lever: `sum over branches of (mix[b] - start_mix[b]) * intensity[b] * national_twh` --
share displacement, a renewable TWh displacing the fossil share it erodes,
`dependency_deviation_pct()`'s shape one quantity over, three pure reads in
`src/sim/energy.gd`. **The intensities are PHYSICAL CONSTANTS with their basis in the
file**: IPCC AR5 lifecycle medians (nuclear 12000, wind_onshore 12000, solar 48000,
hydro 24000 t CO2e/TWh) with the two thermal stations on fuel figures (coal 950000,
gas 400000 including methane slip), branch level output-weighted. **The plan's sixth
row named offshore and the catalogue's sixth source is hydro** -- the one technology
the planning table had no row for, carrying AR5's 24 directly; the `_emission_note` in
`data/energy-sources.json` is the rule future sources read, and the mismatch is
recorded rather than patched. **`SAVE_VERSION` 33 -> 34 on `start_co2e_per_capita_t`
ALONE**: content-derived static `from_dict()` cannot re-derive, V1.6a's check, a
fourth beside V2.8's three; the tick-rewritten reading is serialised too, so an
unticked save reports the figure it was saved with. The inert check asserts exact 0.0
by running five nations, not by an algebra claim -- the T2 review's correction kept as
the check's own shape.

**A DISASTER CAN HAVE A PLACE NOW, AND THE PLACE IS AS PURE AS THE HAZARD THAT DREW
IT.** `"sited": true` is the whole content-side contract: the site is
`Cycle.unit("%s|%s|site", month)` UNIFORM over the nation's sorted region ids -- NOT
population-weighted, because a weighted draw is Ile-de-France for ever (V2.6b1's
measured 73.9 % margin) and a disaster that cannot move is a decoration -- and the
register carries `region_id` AND `region_name`, because the calendar draws its diary
row off the register and preloads nothing. A non-sited event gains NO keys, so every
version-33 register reads exactly as it did; the single-region bound is
CYP/EST/LTU/LVA/MLT at index 0, where a hash would be a second answer to a question
with one response. The content is `river_flood` (gateless, 0.06 -- rain is not
deserved, the scandals' argument) and `heat_wave`, gated on `co2e_per_capita_t >=
6.5`, **measured before it was authored: the gate opens for SEVEN of twenty-nine and
never for France at 4.0** -- the plan said roughly the dirtier half, the roster says
the dirtier quarter, and the count is recorded rather than the threshold tuned to the
sentence. **The national-price gap is the AUTHOR's accepted call at the plan gate
(2026-09-10)**: the flood names a region and the price lands on the nation -- V2.6b1's
regional-opinion refusal named beside it, because a second approval number with a
different label is still V1.5c's reason.

**THE CLIMATE ACCORD IS A FIFTH ORG WITH NOTHING NEW TO BUILD -- V3.2's council
machinery pointed at a cost the player's own industry pays.** EU-27 founding (every
loaded nation but GBR and CHE), **452 seats** on NATO's pop/1M rule,
`accession_seats` 17 the author's call at the plan gate, bonuses zero-priced on the
eurozone/schengen precedent with the named trigger in the file. **The ceiling 5.5 is
DERIVED, not authored**: the EU-27 population-weighted mean 5.4687 rounded to 0.5,
`CONTRIBUTION_MAX_PCT_GDP`'s placement discipline, 15 of 27 inside at start so the
division is real before anyone builds -- and `tools/climate_probe.gd` table (a)
recomputes it and prints MATCH, so a re-import that moves the numbers turns red
instead of silently re-pricing the council. **The tolerance sweep found the band's
edge by REFUSING to open**: below ~5 the pivotal band is EMPTY (the 180-seat
high-emitter bloc holds against the rule at every position on the grid), 6.0 opens the
219-seat plateau; shipped there, severity 0.33. **The player is PIVOTAL**: for
288/452 passes, abstain 219/383 carries, against 219/452 blocks -- and the solidarity
clause (+0.04 % GDP) is authored OUTSIDE the band on purpose, 306 others-for carrying
it whichever way France casts: a coalition's question, the contrast that makes the
band mean something. GBR/CHE accession 0.5177 and withdrawal 0.5179, both swept into
V3.2's 0.510-0.523 band.

**THE OWED MEASUREMENT CAME BACK CONTACT, AND THE CONTACT IS THE FINDING.**
orgs-model's named bound -- the session that authors a second rule-carrying org owes
the cross-org burden re-measurement -- discharged by probe tables (d)/(d2): at one
rule per org the raw burden is 0.88 and the clamp never touches; at TOTAL defiance of
every authored rule in force, **the pre-existing set filled the clamp exactly (eu 0.78
+ nato 0.22) before the accord existed, and the ceiling's 0.33 takes the raw total to
1.33 against BURDEN_MAX 1.0 -- a 24.8 % overhang**. A defier of the whole register
loses a quarter of the opinion price to the ceiling; the bound has its number now.

**THE RE-RUN HELD THE PREDICTION'S CHANNELS EXACTLY**: 43 of 51 regimes move (the 8
still ones all stop at tick 17, before the tick-42 division -- stillness by TIMING,
not immunity), 869 moved line-positions, 1498 column-moves across the 423 paired
annual rows, **zero outcome changes**; 259 of 280 deficit column-moves sit at exactly
the three transfer magnitudes, and GBR, not a member, carries no +0.04 anywhere --
non-membership immunity confirmed rather than assumed. The ceiling's adoption left NO
fingerprint on any printed line (the handoff's "< 62 %" pass-fraction note was
corrected at prediction time and the run confirmed the correction), `heat_wave` drew
nowhere as predicted, and the excluded channels are bit-identical. Two prediction
misses recorded beside the verdict: the inherited 62 % note, and the event channel's
magnitude undersold -- the two answers regimes compound ten floods and displaced
crises into whole points of bloc spread.

**THE SCREENSHOT PASS JUDGED FOUR FRAMES, ALL PASSING, AND ITS ONE FINDING WAS A HOLE
IN THE TOOL RATHER THAN IN THE GAME**: no existing flag could photograph a SITED card
-- `--event` stops at whatever draws first and only notes a missing subject, so the
sited title suffix this block shipped had no frame. `--climate` is the new flag: tick
until the pending register carries `region_id` (the honest marker -- reading event
content instead would be a second opinion about what sited means), then let `--open
events` compose. The frames: the energy panel's new EMISSIONS section reading
**274.4 Mt / 4.0 t / +0.00 t** against the computed expectation (4.0 x 68.6 M,
exactly); the orgs panel staging the ACCORD's council (it sorts first now) with the
pending solidarity division and the ceiling compliant at 5.5; the flood sited at
Corse, on the card and the panel question both. Honest note kept, not fixed: at month
0 before the first tick the dependency figure reads 0.0 % -- V2.8's documented
recompute-on-first-tick shape, six sessions old and not this block's line. The panel
line itself is one never-silent EMISSIONS section under dependency (`%.1f Mt` -- raw
tonnes print six zeroes the eye cannot read), per head, and the delta riding the
PER-CAPITA form because that is the quantity the ceiling constrains.

Suite **82 files** green -- the brief said 83, the disk says 82, and the runner's own
unregistered-file gate is the count that counts. Names clean. Model:
[docs/climate-model.md](docs/climate-model.md).

**THE V1 TIER IS CLOSED AND V2 IS THE TIER NOW. Read
[docs/tiers/v2.md](docs/tiers/v2.md) before [docs/tiers/v1.md](docs/tiers/v1.md).**
For the first time since the MVP a session opened with **no row to read, challenge or
count** -- `someday.md` says of itself that it is *"a parking lot, not a backlog"* -- so
deciding what followed V1 was the work rather than a preamble to it. The organising goal is
that **the world becomes visible and located**: V1 built machines and every one of them is
legible only as a number on a panel, so the country the player governs has no places in
it. Ten blocks, ~30-40 sessions, ordered so the visible payoff lands before the heavy
rewrite. **V2.1 (the shell, re-cut) is COMPLETE, V2.2 (the geographic register) is COMPLETE, and V2.3 (the face of power) is BUILT -- V2.4 (the president's day) is next, decomposed at plan time into V2.4a (the day becomes real) and V2.4b (the scenes)**, on U5a's own precedent -- U5a moved the
shell *before* U5b, U5c and all of U6 built into it, and V2 adds at least five new
surfaces.

**Two calls decide the tier's shape, and one of them was raised as a concern and
reaffirmed.** A **city is to population what a firm is to sector output** -- a share with
an unnamed residual, V1.4a's idiom, exact by construction. And the economy goes
**bottom-up with regions**: national GDP becomes the sum of regions, a region is a main
city plus the smaller cities under it. The cheaper version -- a ninth `economy.gd` addend
holding a city partition, reading exactly 0.0 until something moves -- was offered and
declined, and the record says so. What makes bottom-up affordable is that **bottom-up and
bit-identical are not opposites**: exact aggregation plus regions initialised on the
national trajectory means the re-run can still be bit-identical, and that is a claim V2.5
must *measure* rather than assert.

**One V1.8 call is reversed and only for a flagged class**: `interrupt: true` events pause
the clock, and [docs/events-model.md](docs/events-model.md)'s argument for a non-modal
Dispatches survives for every event without the flag, which is most of them.

**The first row of the new tier was wrong within the hour, which is the discipline working
rather than failing.** The plan booked Eurostat regional data as *"UK coverage ends around
2020"* and wrote V1.5c's nearest-year fallback in as the remedy. Probed before any code:
`nama_10r_2gdp` carries **zero** geo codes beginning `UK` in a dimension of 471 -- Eurostat
dropped UK regions after withdrawal -- while **GISCO geometry carries all ten**, UK
included at 41 NUTS 2 features. The map and the figures disagree about the roster and only
the figures are short. Two import gotchas came out of the same probe and are in
[docs/data-sources.md](docs/data-sources.md): `XXZZ` **Extra-Regio NUTS 2** carries GDP and
has no geometry, and `FRY1`-`FRY5` are the overseas regions the existing bounding-box
filter already drops. Both belong in the unnamed residual.

**The stale-row count closed at three rather than four, and V2's own spine freed the
fourth.** **Embassies** and **Foreign aid** (instance forty-nine) are a fifteenth and
sixteenth entry in `data/diplomatic-actions/` on the existing `effects.relations` channel;
**honeymoon and fatigue** is deferred *in code* at `opinion_constants.gd`'s
`APPROVAL_NEUTRAL` since S5, the oldest open deferral on the project. **Birth rate and life
expectancy is no longer an orphan**: `demography-model.md` §14 had already found the
dataset objection wrong and identified the real blocker as V1.5b's finding that
`population` enters no equation in `economy.gd` -- and V2.5 is exactly the change that
makes a head count load-bearing, so it is a bullet of V2.6 arriving with the mechanism that
reads it. `someday.md` also lost three lines to V2, struck through and marked as lifts so
the parking lot does not re-propose them.

**The per-session table carries rows for V2.1a-c, written BEFORE the sessions.** That table
records the missing-row failure four times in almost identical words -- *"this table STILL
carries no row for the session being planned"* -- so V2 breaks the pattern by writing the
row first. The effort call still belongs to the receiving session: read the row cold, count
the surfaces, challenge it.

## U5a

**U5a shipped the ruler's shell, U5b the world map and U5c its layers,
interrupting the S-track queue on request.** The map is the background, not a
tab; `dashboard.gd` and its rail are deleted; the panels are pinnable floating
windows.

## U5b

**U5b made the map a map of the world.** Four layers back to front: the NASA Blue
Marble raster, the outlines of ~160 countries the game does not simulate, the ten
it does at `LAND_ALPHA` over the photograph, and labels for those ten only. A
non-simulated country is unclickable **structurally** — `_nation_at_lonlat()`
iterates `_polygons` and world geometry lives in a separate `_world_polygons`, so
there is no filter anywhere that could be forgotten. `MIN_ZOOM` stopped being a
constant and became `min_zoom()`, the cover fit, so the furthest zoom out is
exactly the whole planet on any window size; `_clamp_pan()` is new and keeps the
world under the viewport, which nothing needed before there was anything out
there to leave. The minimap fills the slot `clock_cluster.gd` reserved a session
early, and `tests/test_minimap.gd` asserts the cluster did **not** grow — that,
not the minimap's presence, is what the reservation was for.

## U5c

**U5c made the ten coloured by what the player has with them.**
`src/ui/map_layers.gd` is the only place a roster fill is chosen, and it is a
**registry, not a mode flag** — three layers today (political, relations, trade)
and a fourth is one `LAYERS` entry plus one branch in `_value()`/`ramp()`, which
is what let U5c run *before* V1.3c rather than after it as planned. Three calls:
the **viewer is always the player**, because the symmetric-vs-directed asymmetry
is about what a readout may claim (`FRA–DEU 68` names the pair; a trade share
never claims the partner's side) rather than about whose seat you sit in;
**alpha is per-layer** and `LAND_ALPHA`'s 0.20 is *not* inherited, since U5b's
0.42-goes-grey finding is about a ramp with no hue variation; and **both ramps
are anchored on measured values** — relations on
[docs/diplomacy-model.md](docs/diplomacy-model.md)'s resting tiers over a 40–72
domain, not the nominal 0–100, and trade mid-anchored on an even ninth. Hover
moved from the fill to the stroke: lifting a fill toward the accent is the one
place in this interface where pointing at a number would change it.

**U6** is the one named successor left (the calendar, as a scheduling skin over
existing verbs, plus the named-individual roster V1.1d deferred). It does not
block V1.3c.

`assets/map/blue_marble_5400x2700.jpg` is the repo's first large binary, 2.5 MB,
public domain, provenance in [docs/data-sources.md](docs/data-sources.md). It is
read as **bytes** and decoded in memory — never `load()` — for the same
fresh-clone reason as the fonts and icons, and it carries a committed
`.jpg.import` with `importer="keep"`, without which Godot spends ten minutes
VRAM-compressing 14.6 megapixels nothing reads on every run with no `.godot/`.
World borders are Natural Earth **1:110m** in `data/geo/world.geojson`; the
roster stays 1:50m in `europe.geojson`, and `build_world()` excludes the ten so
nothing is drawn twice.

**`tools/screenshot.gd` exists now, and a UI session that does not run it is not
finished — and V1.3g found the bug in the tool itself.** Every setup flag writes sim
state behind panels that have already refreshed, and hiding a window frame does
**not** clear the child panel's own `visible`, so each panel spent its one dirty
refresh on frame 1 and never rebuilt: `--defence --open budget` printed an em dash
against a live 0.498 bill, and every state-mutating flag since `--coerce` had been
capturing pre-mutation figures. The tool now marks panels dirty in `main.gd`'s own
idiom, and `_apply_view()` runs four frames before the capture rather than one. `--headless` draws nothing, so a green suite says nothing about
layout; U5a shipped two bugs invisible to one, and U5c's ramp was wrong at the
warm end until a frame was looked at. It saves a PNG of the running game — run it
windowed, not headless — and takes `--layer`, `--hover`, (U6a) `--book` and (V1.3c) `--coerce`,
(V1.4a) `--subsidy`,
(V1.4b) `--regulate`,
(V1.4c) `--nationalise`,
(V1.5a) `--corrupt`,
(V1.5b) `--migrate`,
(V1.5c) `--unrest` and
(V1.5d) `--press` and
(V1.6b) `--inflate`,
(V1.6c) `--downgrade`,
(V1.6d) `--redistribute`,
(V1.6e) `--invest`,
(V1.6f) `--build` and
(V1.7a) `--campaign` and
(V1.7b) `--pledge`,
(V1.7c) `--referendum` and `--electoral`,
(V1.8) `--event` and `--event-answered` and
(V2.5) `--diverge` and
(V2.6b1) `--site`,
so every map layer can be captured with something actually on it. **V1.4c replaced
the hand-rolled month loop every tick-forward flag carried with `_tick_months()`,
which drives the real clock**: without it `clock_cluster.refresh()` had nothing new
to draw, so the date read `01 JAN 2026` under `--agenda`, `--book`, `--subsidy` and
`--regulate` while the figures beside it moved. Dismissing the election two real
years now cross is part of the same helper. U6b added no flag — a new game already seats a cabinet and a head of state, so `--open people` captures a full window on frame 1 — but it did extend `--book`, because the diary's new person label is written at booking time and a frame of a field nobody filled in proves nothing. That last flag
exists because a frame of an all-zero data layer proves nothing about its ramp,
which is the one claim a screenshot is there to check. V1.3d added `--bloc` on the
same argument — a new game's council is empty and a frame of three "None" captions
proves nothing — and a generic `--open <window id>`. It earned its keep twice in
one session: the bloc panel was printing `deficit_pct_gdp <= 3.0` at a player, and
its own budget section fell below the fold.

## V1.3

**V1.3 is decomposed into six sessions, V1.3a–f. V1.3a and V1.3b are built.**
The argument, the four calls it made, and the per-session table were in
ROADMAP.md (retired 2026-10-05 -- the tier docs carry the build order now);
[docs/tiers/v1.md](docs/tiers/v1.md) §3 tags every
bullet with the session that builds it. Order: (a) relations and diplomatic
actions, (b) trade intensity and agreements, (c) tariffs and sanctions, (d) the
bloc, (e) AI foreign policy, (f) defence.

## V1.3a

**V1.3a shipped the schema everything b–f reads.** Relations are pair state on
`GameState.relations`, **symmetric**, keyed `"DEU|FRA"` by `src/core/relations.gd`
— the only thing allowed to build a key — and derived at start from EU
co-membership and `government.neighbours`. The counterparty response is a
**declared stopgap** V1.3e replaces, asserted as such in `tests/test_diplomacy.gd`.
The model, every constant, and the measured tables are
[docs/diplomacy-model.md](docs/diplomacy-model.md).

## V1.3b

**V1.3b made external demand directed.** `src/sim/trade.gd` derives a per-viewer
weight over the other nine from partner size, EU co-membership, a shared border
and the pair's relations; `Economy.neighbour_weighted_growth()` is retired.
`GameState.agreements` is the second piece of pair state, on the same key, written
only by `Diplomacy.execute()` through a third effect channel on the existing
diplomatic action — there is no `data/trade-agreements/`. **Relations move the
mix, only an agreement moves the level**, and that is a load-bearing call rather
than a detail: an openness *level* that responded to relations makes the free,
unpriced `state_visit` worth two permanent points of GDP. The model, both
escalation triggers, and the measured tables are
[docs/trade-model.md](docs/trade-model.md).

## V1.3c

**V1.3c shipped coercion, on the project's first directed state.**
`GameState.measures` is keyed `"FRA>DEU"` by a second builder in
`src/core/relations.gd`, on a **different separator** so `other()` refuses a
directed key and `directed_parts()` refuses a symmetric one — the additive escape
hatch V1.3a named in advance, taken without touching a line of relations or
agreements, because a tariff and its retaliation are two acts where a
relationship and a contract are one. Tariffs and sanctions are one verb with two
prices on a fourth effect channel, `effects.measure`; there is no
`data/measures/`, for the same reason there is no `data/trade-agreements/`.

**Three things fall out of two constants rather than being authored**, and that
is the session's shape: a **real Laffer curve** (revenue is collected on the
trade that survives, so it peaks at severity 0.625 and falls after), the
protectionist trade-off (**revenue now, trend later** — the openness
counterfactual became "no agreements *and no measures*", so a tariff costs trend
through the channel V1.3b already measured), and the fact that **who you can hurt
is a different question from who matters to you** — damage scales with
`w(target → imposer)`, making FRA→LUX 12.1× LUX→FRA.

**The probe corrected the model twice before any content existed, which is the
whole case for measuring first.** An authored `tariff_rate_pct` was cut once
revenue came back exactly linear in it — one intensity written twice — and
cutting it is what made the Laffer curve real rather than asserted. Then damage,
read off the *post-measure* weight, made every severity above the revenue peak
**strictly dominated**: less money and less harm for more trend loss. Damage now
reads `Trade.weights_before_measures()`, because you damage in proportion to the
trade you destroy and collect in proportion to what still crosses. The named
escalation trigger — being sanctioned is below the readable floor — **fired on
the first sweep and was resolved by that second correction** rather than by
touching `TRADE_BETA`. `COERCION_IMPULSE_MAX` was separately found *binding in
reachable play* at 4.0 and raised to 6.0, equal to `IMPULSE_MAX_PCT`. The model,
every constant and the measured tables are
[docs/coercion-model.md](docs/coercion-model.md).

## V1.3d

**V1.3d shipped the bloc, and the fourth kind of live state.** `GameState.bloc`
is not per-nation, not a symmetric pair and not a directed pair — it is **one
object binding eight nations at once**, and mirroring it onto each member would
be the divergence the symmetric pair key exists to prevent, at a wider scale. A
proposal reaches the council, the members divide on `coalition_position` weighted
by the `ep_seats` `data/eu_parliament.json` already carried, and what carries
binds the player **whether or not they voted for it**. A rule does not refuse a
budget: comply and you pay in the policy you could not run, defy and you pay a
penalty on the budget line and a share of the national agenda. The model, every
constant and the measured tables are [docs/bloc-model.md](docs/bloc-model.md).

**The `ISSUE_KEYS` question three sessions deferred to V1.3d was answered yes**,
and the reasons are structural rather than thematic. `bloc_offset` never enters
`issue_salience`, so a Europe priced on it could never be named by the polling
panel's agenda list or by the election result screen — the two surfaces that
exist to say *why*. A split price never clears the ±3.0 noise floor in the
headline figure, and Europe divides by nature. And a flat offset cannot become
more **salient**, which is exactly what a rule biting hard should do. The cost
was measured before it was taken: every existing salience weight is scaled by
`1/(1+w)`, and the ratio S10's finding was about moves **+0.39 %**, in the safe
direction. `europe` takes 0.083 of the national agenda, fifth of twelve.

**The political map of Europe fell out of a table written at S5 for unrelated
reasons.** The opinion model has no signed split — every satisfaction reaches
every bloc with the same sign — so `europe` had to be one-signed and the division
had to come from elsewhere. Pensioners and rural weight `growth` at **nothing**,
so 37 % of the electorate takes the sovereignty cost and none of the single
market, while business weights `growth` 0.19 and `public_finances` 0.34 and takes
both. Nothing authored that.

**The probe corrected the model twice again, and a test caught a third.** Rule
severities summing to 1.35 against a ceiling of 1.0 made the fourth rule free to
break — V1.3c's strictly-dominated shape in a new place, fixed by rescaling to
exactly 1.0. `EUROPE_SCALE` at 1.00 cleared the noise floor by almost nothing and
was swept to 0.80, landing on the figure V1.3c measured for a full embargo. And
under a whole-council denominator **abstaining and opposing are the same act**,
so the threshold is a share of the seats *cast*. The council was also a
legislature the player controlled — six of seven proposals decided by France —
and the fix was **content, not a constant**: the members are clustered in ideology
space, so moving `common_defence_floor` to where a defence commitment actually
sits is what put a proposal beyond reach.

`SAVE_VERSION` is **11**, answering the assertion V1.3c left. The rule is
unchanged — *would a missing field read as something wrong?* — and three fields
fail it, the loud ones being `bloc_base_transfer_pct_gdp` (a France that never
paid into a budget it has always paid into) and `start_bloc_burden` (a game
reloaded while in breach scores the breach as new).

**The balance re-run is not bit-identical, and V1.3d said so in advance.** V1.3b's
and V1.3c's were, because an agreement and a measure each need a player command
and no regime issues one; the council meets whether or not the player engages.
That is the difference between a verb and an institution, and it is why this
session needed **no eleventh regime** where b and c each did. GDP, growth, trend
and unemployment are bit-identical in all thirty runs; exactly one run changed
outcome, on a two-seat censure margin.

## V1.3e

**V1.3e shipped the interest model, and the row split.** All four declared
stopgaps are discharged — the counterparty *reaction*, its *decision*, its
*retaliation* and the council's *vote* — and all four mutation tests were watched
going red before being rewritten. The acting agent is now **V1.3f**; defence runs
to **V1.3g**. The split was taken on **machine count**, not on the surface count
the ROADMAP row named: that trigger (*a plan-time count above V1.3a's ~25*) had
already fired on V1.3b, V1.3c and V1.3d without any of them splitting.

**Interest is material; ideology is one weak term**, and that is the session's
central call. `tools/bloc_probe.gd` prints the eight non-player members clustered
in ideology space — economic spanning 0.87, social 1.13 — so a function resting on
`coalition_position` gives nine nations that behave alike, which is `trade.gd`'s
`GRAVITY_EXPONENT = 1.0` finding in a new place. The spine is the directed trade
weight instead. `src/sim/foreign_policy.gd` is a **pure read**: no `tick_month()`,
nothing on `NationState`, nothing new on `GameState`, so `SAVE_VERSION` stays at
**11** — which is what *no grievance ledger* buys, because the relations number
**is** the memory. The model, every constant and the measured tables are
[docs/foreign-policy-model.md](docs/foreign-policy-model.md).

**The probe corrected the model three times and a test caught a fourth**, which is
five sessions running. A globally-anchored amity read Britain's structural
detachment as hostility and closed agreements to it entirely (**0 of 9**);
anchoring sentiment on the pair's own resting value fixed it *and* cut a
double-count, since EU co-membership and the border were already inside the trade
weight. An ideology term commensurate with a rule's severity had every member in
breach of the deficit rule voting **for** it. `vote_reason()` named a cost term
that had lost by a factor of five. And **constructive abstention has a window
11 % of the range wide** that V1.3d never measured — it swept three columns where
four were needed, and got its own abstention property from the content by luck.

**`AGREEMENT_ACCEPT_MIN` and `SUPPORT_SIGMA` are deleted, not left unused**, along
with `bloc_probe.gd`'s sigma sweep — a tuned constant nothing reads is a number a
later session finds and reasons from.

**The screenshot pass earned its keep twice again**: every diplomatic action
button had fallen below the fold at a height unchanged since V1.3a, and a treaty
the partner would refuse rendered as a **live button** that refused silently —
V1.3b's own unread `refused_by_partner`, reappearing inside the session fixing it.
A fold is something the headless suite structurally cannot see: two of that
panel's labels autowrap, and with no layout pass an autowrapped label reports its
one-word-per-line height, so the assertion reads a 500px fold that is not there.
`tests/test_nation_panel.gd` says so rather than shipping a flaky check.

**The re-run is not bit-identical and could not be.** 15 of 30 runs move; every
large mover is GBR taking the bloc's `common_external_tariff` — a V1.3d feature
V1.3d's own re-run never fired, because the old council never adopted it inside
fourteen years. Exactly **one run of thirty changed outcome**, on a one-seat
margin. The re-run also caught a break the suite could not: `balance_probe.gd`
referenced the deleted constant and every new run failed to parse, because
`tools/` is excluded from `run_tests.sh` by design.

## V1.3f

**V1.3f shipped the acting agent, and the block has no stopgaps left.**
`_tick_agenda()` lives in `diplomacy.gd` beside `_tick_retaliation()` — the
interest model preloads `trade.gd` preloads `coercion.gd` and can never reach
`available()` or `execute()`, so it **scores what it is handed** and Diplomacy
decides what to hand it. No new content type, no new effect channel, no new verb:
the agenda uses the ten actions `data/diplomatic-actions/` already ships, the
fifth session running. `SAVE_VERSION` is **12**, earned by exactly one of two
added fields — an absent `diplo_months_to_act` reads as 0 and 0 means *act now*,
so a reload fires nine acts in one month; an absent `foreign_acts` reads as
"nothing yet", which is correct. The test asserts **both** halves.

**Interest MULTIPLIES a bounded opportunity; it is never an addend, and that is
the session's central correction.** As a standing addend a partner's importance
made friendly acts free forever — every nation state-visiting its largest partner
on a loop, mean relations **79.6** against resting tiers of 45–68 and a pair on
the clamp. `AGENDA_AMITY_TARGET` closes the `deepen` term to exactly 0.0 once a
pair is warm enough, so the ratchet is structurally impossible rather than damped.
An inert act reads **exactly 0.0** for all ninety ordered pairs.

**The probe corrected the model four times and each correction is load-bearing.**
Free concessions get spent freely, so the agenda reads the action's **own
authored** `bloc_offset` as its domestic price — the content already said how hard
each act was and the nine were the only ones not listening. `third_party_effects()`
was **unbounded** (an uncapped `care/EVEN_SHARE` reaching 3.0 moved eight other
pairs harder than the act's own) and **backwards for friendly acts** (solidarity
said being nice to Germany cools everyone else toward Germany); both survived
V1.3e because only a player ever reached that function. And the `AGENDA_ACT_MIN`
sweep **measured the wrong state** — the static new-game table said 0.05, but by
month 24 Britain is everyone's top pick and the whole landscape has fallen under
the bar, so the world goes silent and Britain's turn never comes. GBR-aimed acts
**0 → 35** over fourteen years. Model notes:
[docs/foreign-policy-model.md](docs/foreign-policy-model.md) §7.

**The re-run was budgeted as a re-baseline and came back quieter than planned**:
6 of 30 runs differ, all GBR, all last-digit, **zero outcome changes**, FRA and
DEU bit-identical across all twenty. Relations move the trade *mix*, and the mix
reaches an economy only through partner deviations no balance regime produces.

`message_stack.gd` takes its first content since U5a built it as furniture, and
that spends nothing of V1.8's argument: an act by a simulated nation is state
`src/sim/` just wrote, not invented content. The sim writes
`GameState.foreign_acts`, the UI decides what earns a card, and
`tests/test_foreign_policy.gd` asserts **nothing in `src/sim/` reads it back** —
V1.3e's *no grievance ledger* property survives only if that stays true.

## V1.3g

**V1.3g shipped defence, and the V1.3 block is complete.** `GameState.pacts` is
symmetric pair state on `relations.gd`'s existing key builder and
`GameState.deployments` is directed pair state on the one `measures` uses — **two
registers and no new *shape* of live state**, the first session since V1.3a to add
two and no kind. An alliance looks like a set and does not need to be stored as
one: `Defence.allies()` derives it, and the genuinely multilateral case already
exists as the bloc. Capability is a stock converging on the nation's own
`spending_pct_gdp["defence"]`, so **`has_budget` was not lifted** — all ten nations
already author that line, the nine's never moves, and `tests/test_defence.gd`
asserts their capability sits still for a full run rather than leaving it to a
comment. `SAVE_VERSION` is **13**.

**The obligation opens itself, and it is a LEVEL READ rather than an edge trigger.**
That was the design pass's correction and it is the session's sharpest call:
nothing in this project ever lifts a retaliation, so an obligation only the player
could close is a permanent monotone charge and `DEPLOYMENT_BILL_MAX_PCT_GDP` stops
being a guard rail — `IMPULSE_MAX` in a fifth place, avoided rather than found. The
player still cannot close one; only the aggressor lifting its measure, or
abandoning the pact, can.

**What the obligation fires on was authored by nobody.** The probe found the nine
**never coerce each other** — 168 months, no player, `state.measures` stays empty
and every recorded act is `state_visit` — so the only thing that reaches an ally
unprompted is the council's `common_external_tariff`. An alliance obligation
therefore fires on a pact held **outside** the bloc and never on one held inside
it: your pact with Britain bills you when Brussels turns on Britain. That is V1.3d
meeting V1.3g, and it is why the decomposition's "reads a, d" was right in a way it
could not have known.

**The probe corrected the model three times, seven sessions running**, and the
second correction moved what a constant is measured *against* rather than the
constant: `defence` is weighted **0.00 by five blocs of six**, so no value of
`DEPLOYMENT_OPINION_CHOSEN` can move the headline past the ±3.0 noise floor, and
raising it until one did would be tuning against an arithmetic impossibility. The
price is read on the rural row instead — V1.3a's own finding from the other
direction. The third correction was that the first opinion table measured **half
the price**, having set the load and not the bill that widens the deficit every
bloc *does* weight. `DEPLOYMENT_OBLIGED_MULT` was **decorative at 1.50** and is
1.75, solved off a measured slope. One deployment stays below the readable floor
and **cannot be lifted above it** — the value needed saturates two — which is a
structural bound recorded rather than traded against. Of five named triggers one
fired: GBR unable to ally, the sixth time in the block, fixed by a sweep that put
`PACT_ACCEPT_MIN` **below** the trade bar. The bill clamp was measured and found
**slack** (0.586 against 2.00), a first for this block. The model, every constant
and the measured tables are [docs/defence-model.md](docs/defence-model.md).

**The re-run is bit-identical across every shared regime**, which the plan did not
predict, and the probe explains it: `state_visit` wins **90 pairs of 90** on being
the only verb in `data/diplomatic-actions/` priced at exactly 0.000, so four new
verbs changed no AI choice. That is also the session's honest limitation — **the
four verbs are player content**; AI-to-AI pacts are reachable by the model and
unreachable by the agenda, and the fix is a security term in `_desire_parts()`,
which is a session rather than a constant. A **13th balance regime** was still
needed where V1.3d and V1.3f needed none: a pact is a verb, and no budget regime
issues a command.

**The screenshot pass earned its keep for the fifth session running, and this time
the bug was in the tool.** `--defence --open budget` showed an em dash against a
live 0.498 bill: hiding a window frame does **not** clear the child panel's own
`visible`, so every panel spends its one dirty refresh on frame 1 and never
rebuilds — meaning every state-mutating flag since `--coerce` had been capturing
pre-mutation figures and getting away with it. `screenshot.gd` now marks panels
dirty in `main.gd`'s own idiom. The nation panel's fold also reappeared one session
after V1.3e paid for it there, and **height alone could not fix it**: four verbs are
~136px against a ~886px ceiling, so it took 80px of height plus two tightenings.

## U6

**U6 split, and U6a shipped the president's diary.** The row counted **~40
surfaces and four machines** — the largest ever on this project — so it split on
machine count, V1.3e's trigger, cutting the half with the unmade content
decision exactly as U5b cut U5c. **U6b is the roster.**

**The session is judged on legibility, not on scarcity, and that is a
measurement rather than a preference.** Every observable here is
piecewise-constant across a month: `clock.gd` has emitted `day_advanced` since
the MVP and nothing in `src/sim/` has ever listened, so 14 March and 22 March
differ only in the label — which makes booking *as a replacement for acting* a
deferral that buys nothing, V1.3c's and V1.3d's strictly-dominated shape a third
time. So **booking is optional**, every verb keeps its act-now button, and
`tests/test_calendar.gd` asserts a booking moves nothing at the moment it is
made. What the diary shows instead is dated state the game has carried for
sessions with no surface anywhere: election day, the European election, the
presidential term, the council's next proposal and its pending vote, the
dissolution lockout, and every diplomatic and legislative cooldown expiry.

**The one tuned constant this session would have added was DELETED by its own
probe, which is a first.** A monthly budget of the player's days was swept
against a band fixed before the sweep ran, and the band is not mis-tuned but
**structurally unreachable**: the median month offers 27 legal acts asking 124
days, so every budget from 4 to 24 bound in **100 %** of months. A ceiling that
always binds is a cap, not an allocation. Deleted rather than left unused —
V1.3e's treatment of `AGREEMENT_ACCEPT_MIN` — so `src/sim/calendar_constants.gd`
carries **no tuned constant at all**. The reason is carried forward because it is
not about calendars: `available()` returns what is **legal** and nothing yet
models what the player **wants**, so any ceiling priced against legality always
binds. That gap is a session, not a constant.

**The probe corrected itself twice and a panel test found the third, which is
eight sessions running.** The fixed-date density table read a player who never
acts, so cooldowns — much the densest source — reported exactly **0**; and it
counted *after* the tick, so an election had already pushed its own date forward
and 168 months showed **one**. Both are V1.3f's measuring-the-wrong-state error,
in the file written to avoid it: 19.6 % → **31.0 %**. The third is sharper than
the average: a **new game's next twelve months are completely empty**, because
France's nearest dated event is sixteen months out and cooldowns do not exist
until the player has acted — so the page every player sees first is the page with
nothing on it. The pre-committed response to a thin diary was shape rather than a
constant (widening the horizon would have been the constant, since it also bounds
booking), so: a **twelve-month strip** rather than a month's page, a `later`
footer, and a `Next:` line outside the scroll.

**`src/sim/calendar.gd` preloads no other system, and the test reads the file to
say so.** `due()` returns entries as **data** and `main.gd` fires the verb —
`cabinet-model.md`'s orchestrator precedent one scale wider, and it cost **zero**
new preloads because `main.gd` already had all three. `_queue_effect()`'s U4
baseline moved from the button press to arrival, because a booking commits
nothing in the month it is made. `clock.gd` emits `month_elapsed` **before**
`day_advanced`, so a day-1 booking acts *after* that month's tick; `due()` reads
`<=` rather than `==`, so a save reloaded past a date still fires it.

**The re-run is bit-identical across all thirteen existing regimes, and a
fourteenth was needed for a reason V1.3g's was not.** `balance_probe.gd` and
`tests/test_balance.gd` are month loops with **no clock** — this harness has never
called `advance_one_day()` — so a day-resolution dispatch was structurally
invisible to all thirteen and their bit-identity would have meant nothing. The day
loop now runs for every regime; with an empty register it is one `is_empty()`
check.

**Booking does NOT go on `nation_panel.gd`, and the plan said it would.** Every
verb row there is an HBox holding an autowrapping summary label beside one button:
a second button narrows the label, the wrap grows the row, and that panel is at
860px against a ~886 ceiling having paid for that fold twice. Booking lives on the
diary alone. The **screenshot pass earned its keep for the sixth session running**
— `upcoming()` filtered to unfired entries, so the strip's own resolved-entry
styling was dead code and a kept appointment vanished from the diary. And
`tests/test_state_copy.gd` had a branch that had **never run**: its array probe
pushes a float sentinel, every copied Array had been untyped until now, and the
three `Array[Dictionary]` fields were all excluded for unrelated reasons — so it
reported "shared with the copy" for a field that is duplicated correctly.

## U6b

**U6b shipped the register, and the row was wrong about what the work was.**
The roster half already existed: ~70 named people were live as loose strings in
**five** places, and **every one of the ten nation files wrote a person's name
twice** — `party.gd` even documented the duplication as a convention. So U6b was
a *migration* into `data/people/` plus a re-key, not an authoring exercise. Only
**five** names are new, the pretenders for the five republics, and authoring them
fixed a live content bug: `amendments.json` named one king inline and the
Restoration Act applies to any `parliamentary_republic`, so **every republic in
Europe restored the same man**. A law names an office; the nation's own
`government.pretender_person` names the person, and a monarchy points that slot at
its sitting monarch.

**A person is an id and a NAME, and the three fields that were cut are the
design.** `role`, `title` and `party_id` all went before `person.gd` was written,
because the reference that owns each relationship already states it — a title
belongs to the office, a party leader is whoever `leader_person_id` points at, and
an office is *the slot pointing at you*, which Moucron proves cannot even be
single-valued. That leaves **no field that could carry a mechanism**, so "no
mechanism on a person" is true by construction; `tests/test_people.gd` reads the
file and fails if a third field appears. `docs/tiers/v1.md` §4 and §5 inherit the
register and extend it. There is **no `src/core/people.gd`**: it was deleted
before it was written once the bench was cut, because a name lookup is a
dictionary read and every panel already holds the loader.

**The probe corrected the model once and itself twice, nine sessions running, and
its kill switch FIRED and was honoured.** A flat ordered bench picked by rank made
adding one portfolio renumber every minister a party already held — 22 department
changes in one run, for reasons about nobody — so it became a **shadow cabinet**
keyed by portfolio, where churn is structurally impossible rather than damped.
Then its own election counter reported **zero elections for every nation over
fourteen years**, and churn was gated on it; and the first cast table had no
vacancy column, so a collapsed government read the same as a thin roster. With
those fixed, distinct-people-seen came back **6** worst case against a
pre-committed floor of **12** — and a perfectly healthy single-party GBR at **7**
with zero vacancy across three elections. **The minister bench was cut before it
was authored**, U6a's currency deletion one session on; a portfolio still names a
party, and `docs/cabinet-model.md`'s deferral is recorded as still correct rather
than reversed. Model: [docs/people-model.md](docs/people-model.md).

**`verb_key()` is unchanged and U6a's `person_id` hatch was not needed.** A person
is the *face* of a target that already exists, so booking a state visit to Germany
IS booking its leader — one act, one key. `person_id` is a derived label, and
`tests/test_calendar.gd` asserts two entries differing only in it are the same
verb. The hatch cost nothing and was right to carry; what it insured against did
not happen.

**`tools/check_names.sh` cannot see an untracked file**, and the first run over
the new register passed with zero hits and **zero files scanned** — it iterates
`git ls-files`. The largest exposure that check has ever had was, for one run, not
being checked at all. Any session authoring a new content directory must `git add`
before the check means anything. **The balance re-run is bit-identical across all
fourteen regimes with no fifteenth needed** — predicted in advance, and a first
for this run: U6a and V1.3g each needed a new regime because each added a verb,
and a name is not a decision.

## V1.4

**V1.4 is decomposed into three sessions, V1.4a–c; a and b are built.** The row
was one line and one line is not a session: (a) the firm register and subsidies,
(b) sector regulation, (c) nationalisation and privatisation. The split is on
machine count — five machines — and **the a/b line is architectural rather than
thematic**: a subsidy is an executive act and a regulation is a **law**, so (b)
reaches `effects.company` through an assembly division where (a) reaches it
directly. That is V1.3a's own distinction one block later, and it is the only
thing here worth a session boundary.

**The row double-booked twice and named neither.** Bond markets were claimed by §4
and §6 and went to **§6**, because a yield writes `debt_service_pct_gdp` and
shares no state with a firm — and §6 re-baselines the balance harness anyway, so
endogenising the rate there is one re-run rather than two. The second collision
was found by counting: **a subsidy IS §6's "sectoral investment — a lever pointed
at a sector" unless a firm is smaller than a sector**, so
`_validate_companies()` refuses a sector holding one named firm at load time. That
is the eleventh missing-row instance.

**A firm is the first content class that fronts nothing**, so V1.4 owns
`effects.company` — the fifth channel, and the first pointed at something that is
not a nation. `data/company-actions/` takes `data/diplomatic-actions/`'s shape, so
a, b and c share one content type the way V1.3a's directory served five sessions.
A firm is four fields: `id`, `name`, `sector`, `share` of its **sector**, and
`headcount`. Revenue is not authored — it is `share × sector_output`, and
authoring it is one quantity written twice.

**Firms are load-bearing on GDP with no second reconciliation.** A firm holds a
share and its output is read through it, so the partition is exact by construction
and `_apply_growth_to_sectors()`'s existing GDP reconciliation is untouched. What
reaches the economy is **two deviation terms that read exactly 0.0** until a verb
moves something — `trade_baseline_by_partner`'s idiom — which is what let the
whole register go live with **every shared balance regime bit-identical**.
`tests/test_companies.gd` asserts exact equality, not `is_zero_approx`.
**Headcount follows share and not sector output**: read off the level a firm would
hire every month the economy grew, which is a second answer to the Okun term the
macro model already owns. Reallocation is all this channel adds, and all it should.

**The probe corrected the model twice, ten sessions running.** A flat rival floor
made 0.0020, 0.0040 and 0.0080 produce the **identical** five-year outcome — the
clamp-sets-the-number failure in a third place — and the fix moved the model:
`RIVAL_FLOOR_FRACTION`, so a rival keeps half its **authored** share, the endpoint
becomes content, and the rate went back to setting speed and was re-chosen on a
column that did not exist before the correction. `SUBSIDY_GROWTH_BETA` at 0.30 had
one firm worth more than a percentage point of every tax at once and came down to
0.20. **The kill switch cleared**: the jobs channel reaches 0.229 points, and the
table says why in a way nothing authored — subsidising a retailer over a bank moves
0.229, one industrial firm over another moves 0.010, and the whole spread comes
from two authored headcounts. The bill clamp is **slack**, 1.800 against 2.500.
Model: [docs/companies-model.md](docs/companies-model.md).

**The screenshot pass earned its keep for the seventh session running, and it
found a live U6b bug on the way**: `_people_panel` was never added to `main.gd`'s
`_mark_all_dirty()`, so the People window refreshed once on the frame it was built
and never again — a censure, a reshuffle and every seat count after an election
were stale on it until reload. The comment above that list predicted exactly this
failure, about the panel added in the session that wrote the comment. Its own two
bugs were the panel's and the tool's: ledger figures ran under the scroll bar, and
twenty-four ticked months were captured under a top bar still showing the starting
GDP, which `--agenda` has always done and got away with.

`SAVE_VERSION` is **15**, on one field of five. `NationState.companies` earns it —
absent, every firm reads as share 0.0, so the partition is not there and a subsidy
the save is still billing for moves a share that does not exist. The other four are
recomputed on the first tick. **What is not in the register is the interesting
half**: a firm's authored share and headcount are content, so the baseline every
deviation is measured against round-trips through `data/companies/` rather than
through the save.

## V1.4b

**V1.4b shipped sector regulation, and the session boundary was the whole point.**
A regulation is a **law**: it reaches `effects.company` through
`Legislature.apply()` and an assembly division where a subsidy reaches it directly
through `Companies.execute()` — V1.3a's distinction one block later. `law.gd` grew
a fifth `business` theme and a `_extract_company()` validator; `legislature.gd`
grew **one dispatch branch**; nothing in `src/sim/` learned a new verb.

**One quantity read twice, and no new channel at all.**
`NationState.regulation_burden` is signed per-sector state written by
`Legislature.apply()` and by nothing else, priced through the **two channels V1.4a
already built** — a negative term inside `firm_impulse_pct()` and a
`(1 − β·burden)` factor inside `headcount()`, which the existing
`firm_jobs_offset_pct` picks up for free because it already measures live headcount
against authored headcount. That is V1.3c's *one verb, two prices* **literally**
rather than by analogy; a second growth impulse would have been a second machine
wearing the phrase. No budget line and no clamp of its own.

**`_extract_company()` refuses a firm id, and the refusal IS the design.** Share
movement is the subsidy's persistent channel and a law that could name a firm would
be a second writer of it. The a/b split lives in the schema, not only in the docs —
and `tests/test_companies.gd` asserts every share is **exactly** unchanged after
twenty rounds of every rule in the file. A law carrying both `effects.company` and
`structural_unemployment_pct` is a **load error**: same act, same landing site, same
units, so the legislature model's prose rule is mechanical for the one case where it
could be.

**V1.4a's escape from §6 does NOT transfer, and no validator could have caught
it.** V1.4a refused a sector holding one named firm — a rule about the *target* —
and a regulation's target *is* the sector. What separates them had to be found: a
regulation reaches **only the named partition** (a sector 24 % named is a quarter as
regulable; the unnamed residual is unregulated, a bound recorded), and its **jobs
price has no analogue in a sector lever** because jobs-per-share is firm content.
That is why widening the jobs channel's charter from pure reallocation to
reallocation-plus-level was the right trade rather than a compromise — without it
V1.4b *is* §6 early. Both are cross-referenced into `docs/tiers/v1.md` §4 **and**
§6. The row's other miss: **"cost margin" names a quantity `src/sim/` does not
have**, and the corporate-receipts channel that would have invented one was **cut
before it was written**, because it creates V1.4c's dividend dependency instead of
discharging it — a dividend is a yield on *output*, and if V1.4c wants margin,
V1.4c owns it whole. Instances **twelve and thirteen**.

**Deregulation is a direction, not an undo.** The clamp is symmetric, so a
deregulation law carries a negative burden on the same accumulator. There is no
repeal verb in this project and a `once` law never returns, so `[0, MAX]` would have
been a permanent monotone charge — V1.3g's named failure — and a repeal law would
have been *inert at burden 0*, breaking V1.3f's own property on the law list. It
would also have needed a `PRECONDITION_FIELDS` entry carrying a sector parameter
that whitelist has never had.

**The probe corrected the content twice and itself once, eleven sessions running,
and NOT ONE correction was to the model** — which is itself the finding, because both
channels were V1.4a's and already measured. The kill switch **cleared** at 0.0942
points against a pre-committed floor of 0.05, and the prediction written before the
sweep — agriculture cannot clear it at any sane value — **held exactly** at
0.0083–0.0126 and is recorded as a structural bound. The first `business.json` made
the whole regulation stack **free**: +6.45 headline against a ±3.0 floor, because
the design rule said a regulation's losers must not also be named in `bloc_offset`.
The probe's own numbers say why that was too broad — a saturated burden moves growth
~0.1 %/yr and unemployment ~0.02 points, **below the opinion model's resolution**, so
a rule's political price cannot be expressed by the measured channel and must be
authored. Then the cost-against-buy table's **unweighted** `bloc_offset` sum hid two
same-sector dominations; one was fixed by **swapping two burdens** rather than
retuning offsets, because a safety regime genuinely is the heavier compliance load
and the fix that is also true is the better fix. Model:
[docs/companies-model.md](docs/companies-model.md) §10–19.

**`SAVE_VERSION` stays at 15 and the test pins it** — a version-15 save comes from a
game that could not pass a `business` law, so an absent register reads as every
burden 0.0, which is the truth about that save rather than a soft failure
(`measures` at V1.3c, `pacts` at V1.3g, `appointments` at U6a). Serialised anyway,
because a law writes it once and no tick recomputes it. **The re-run is bit-identical
across all fifteen existing regimes, predicted in advance**, and the sixteenth regime
was the **cheap kind**: `AMENDMENT_REGIMES` already applies a law at a month, so only
the content was new. The screenshot pass earned its keep for the **eighth** session
running, and the bug was the flag's: one rule each way came out at `-0.000 pts` on
the ledger because industry's 186k jobs at +0.40 and services' 213k at −0.35 shed and
hire within **fifteen people** of each other.

## V1.4c

**V1.4c shipped ownership, and the V1.4 block is complete.** `state_share` is a
third field on the firm register with a **third single writer**, so `share` moves
only under a subsidy, `state_share` only under an ownership op and
`regulation_burden` only under a law. A dividend is a yield on **output** —
`state_share × share × sector_output × DIVIDEND_YIELD` — exactly as
`companies-model.md` §13 argued a session in advance, so **no margin, profit or
productivity quantity was invented**; it lands as the second computed *revenue* line
after V1.3c's tariffs.

**The purchase and the windfall write the DEBT STOCK, and that one call paid for
itself three times.** A capital transaction is a balance-sheet swap rather than
income, every existing budget line is a standing rate, and a one-off on the revenue
side would move `deficit_pct_gdp` inside the month — which is a company action's own
precondition field, the loop V1.4a's one-month lag exists to avoid. Writing
`debt_eur_bn` instead means the interest is priced by `Budget.recompute()` at
`DEBT_REAL_RATE_PCT`, the level is read by the bloc's own `debt_to_gdp_pct` rule, and
it has been serialised since the MVP. **Nationalising a champion can put the player
in breach of a rule Brussels passed.**

**Row 14: "a permanent loss of control" named a control the model did not have** —
a subsidy works on any firm whoever owns it and a regulation targets the sector — and
that is §13's "cost margin" one session on. The answer is one factor at one existing
site: a state holding absorbs the sector's compliance cost so the payroll does not.
It adds **no constant at all**, because a total holding cancels a term V1.4b had
already measured, and the shield is **signed** so a public firm in a *deregulated*
sector forgoes the hiring too. `tests/test_companies.gd` asserts both directions.

**The probe corrected the model once and the content once, twelve sessions running,
and the model correction is about what a band can and cannot decide.**
`DIVIDEND_YIELD`'s pre-committed band passed **three of four rows**, because it
measures whether the line is *readable* rather than whether it is right. What chose
was the ratio against `DEBT_REAL_RATE_PCT`: at 0.04 the yield on price was 4.0 %
against a 2.0 % borrowing rate, so every nationalisation paid for itself twice over
and came back better than a quiet run on the headline **and** the deficit — free on
both axes, the strictly-dominated shape a fifth time. Set **equal to the borrowing
rate**, the treasury neither gains nor loses on the exchange, which is the honest
model where there is no cycle for an equity premium to compensate for; what
nationalising costs is a **stock** where every other lever in this game is a flow.
The content correction re-authored every `bloc_offset` against `BLOC_SIZE`, V1.4b's
own table (j) discipline. The kill switch **cleared at 0.0942 points** and the
agriculture prediction held exactly — because the shield's size *is* V1.4b's jobs
price read from the other side, to the digit.

**The `ISSUE_KEYS` question a, b and the whole V1.3 block deferred here is answered
NO**, recorded in `opinion_constants.gd` beside `ISSUE_KEYS` so a later session finds
the reasons rather than the silence. V1.3d's tests 1 and 3 hold; the other three
fail. A **regulation** has 1 and 3 identically and V1.4b took no key, and the
proposed distinction — ownership as a single standing stock — does not survive, since
`regulation_burden` summed over sectors is equally a stock. The deciding number is
that the S10 ratio drifts **−1.46 %** where V1.3d's moved **+0.39 %**, and it is
structural: `business` carries `public_finances` at 0.34 and is the bloc that makes
ownership divisive at all, so **the mechanic and the cost are the same number** (at
business 0.04 the drift falls to −0.29 %, and a row that light says nothing).

**`SAVE_VERSION` stays at 15, which is not what the row expected, and the test says
so before pinning it.** An absent `state_share` reads 0.0 — the state owns nothing —
true of every version-15 save; the dividend line is recomputed on the first tick; and
the purchase was never a field. **V1.4b's declared stopgap is INHERITED, not
discharged**: nationalisation is the state acting *on* a firm, and a firm still
cannot refuse, exit, relocate or lobby. **The re-run is bit-identical across all
sixteen existing regimes, predicted in advance**, and the seventeenth is the
expensive kind — an ownership op is a verb no budget regime issues.

**The screenshot pass earned its keep for the ninth session running, and two of its
three bugs were older than the session.** The date has read `01 JAN 2026` under every
tick-forward flag since `--agenda`: each hand-rolled a month loop calling
`_on_month_elapsed()`, which advances the simulation and leaves the Clock node alone,
so `clock_cluster.refresh()` had nothing to draw — V1.4a found the same disagreement
one row up on the top bar and fixed only that. `_tick_months()` now drives
`advance_one_day()`, which immediately surfaced a second thing no hand-rolled loop
ever saw: two years of the real clock cross a real election and the result screen
opens over the panel the flag just set up. And **the budget panel has never had a
deployments row** — V1.3g wrote `_set_figure("deployments", …)` with no `FIGURE_ROWS`
entry, `_set_figure()` returns silently on an unknown key, and V1.4a then wrote
"beside the deployment line" about a line that was not there.

## V1.5

**V1.5 is decomposed into four sessions, V1.5a–d, and (a) is built.** The row was
nine bullets and nine bullets is not a session: (a) the delivery layer, (b)
demographics and migration, (c) unrest, (d) media and information — with **(d)
recorded in advance as the row most likely to split**, scandals being the cut. Five
machines. **The block breaks the rule every previous block was built on**: V1.3 and
V1.4 each shipped a player command per session and V1.3a's rule was that state ships
*with* a verb, where §5 has at most two verbs across nine bullets. So the rule
inverts — **every session ships a statistic and the price it charges**.

**The row missed eight rows, instances fifteen through twenty-two, all found by
counting.** Five collisions, each now cross-referenced into *both* rows: rule of law
is §1's judiciary (and left the block); education quality already exists as
`potential_shift_pct`; scandals are §8's own definition; inequality's instruments are
§6's; government messaging is §7's campaign phase. Three orphans tiered V1 in
`docs/brainstorm/mechanics-society.md` and named in no row at all — government
messaging, **honeymoon and fatigue** (deferred *in code* since S5 and the oldest miss
on the list), and birth rate and life expectancy, for which no data exists. And three
bullets assume quantities the model does not have: `spending_pct_gdp` is a player-set
**rate** so ageing cannot drive a *cost*, `Cabinet.effectiveness()` multiplies
**deltas only** so corruption placed there is free to a do-nothing player, and there
is **no legitimacy quantity** for press freedom to charge against.

**V1.5a's headline is that §5's bullet 9 asks for a machine the project had already
built three times under three names.** `military_capability` is defence's outcome
stock; `potential_shift_pct` is education's *and* infrastructure's, since S4. Of five
spending lines only **health and pensions** have none, and pensions needs V1.5b's
dependent count — so `society_constants.QUALITY_KEYS` holds **one entry**, and the
exclusions are the design: `tests/test_society.gd` fails if `education`, `defence` or
`infrastructure` appears in it. `society.gd` lifts `capability_target()` /
`capability_step()` from `defence.gd` outright, equilibrium-not-zero included.

**Corruption multiplies the STOCK'S TARGET, not the satisfaction delta, and that is
the session's second call.** The row says it degrades "policy effectiveness", which
names `Cabinet.effectiveness()` — but that function multiplies the **delta** only, so
a factor there costs a player who never moves a spending line **exactly zero**, free
to precisely the player most likely to deserve it. Degrading the target means a
corrupt state's hospitals decay at unchanged spending. Signed both ways, which is
V1.4b's deregulation argument plus one V1.4b did not need: a one-way level makes an
anti-corruption law **inert on a clean state**. `effects.society` is the **sixth
channel** and V1.5 owns it the way V1.4 owns `effects.company`; no sixth law theme was
needed, `institutional` already existed.

**The double count had to be resolved rather than avoided, and three of four
resolutions fail on the project's own record.** `health` was already an opinion issue
keyed to the spending delta. Replace fails because `opinion_constants.gd` commits to
no lag and warns against "two lags in series"; multiply fails because two multipliers
on one delta are unattributable and `elections.gd` has one attribution slot; a 13th
`ISSUE_KEYS` entry fails V1.4c's own collinearity test. What ships is **additive and
post-effectiveness** — `deployment_opinion_load`'s shape — so the two price
*different times*: the delta prices the announcement, the stock prices the delivery.

**The probe corrected itself three times, thirteen sessions running, and the finding
is that naming a tiebreaker in advance is STILL NOT ENOUGH.** `QUALITY_CONVERGENCE`
was the only pre-committed pair that worked as designed (band passed 0.01 and 0.02;
tiebreaker chose 0.02 at a ratio of exactly 1.00 against `CAPABILITY_CONVERGENCE`).
`QUALITY_SCALE_PP`'s band was **measured on a path that could not observe it** —
raising a spending line necessarily widens the deficit, so "the quality channel alone"
was never visible there, and the headline came back **−0.70 for a spending INCREASE**;
on the isolated path it passes 3.0/4.5/6.0. Its tiebreaker was **a test that could not
fail** (any positive stock term adds to the total, so "re-measure `SPEND_SCALE_PP`
down" fires for every candidate — V1.3e's own criticism of its split trigger). The
replacement rule chose **4.5** where the constant had been provisionally set to 6.0,
which is the evidence it was not written backwards. And
`CORRUPTION_DELIVERY_BETA`'s **kill switch cleared at every candidate**, which meant
its tiebreaker was a **bound and not a selector** — V1.4c's failure repeating inside
the session written to avoid it. A two-part selector (one law legible on a bloc row;
the saturated value leaving `DELIVERY_MIN` slack) passes **exactly one row**, 0.30.

**`SAVE_VERSION` is 16, on one field of three.** `service_quality` earns it — absent
it reads 0.0 against a France that has funded hospitals for decades, and
equilibrium-init does *not* rescue it because re-deriving on load would erase a
decline the player spent a term earning. `corruption` and `start_service_quality` earn
nothing and are serialised anyway for two different reasons the test states
separately; the split assertion is that `service_quality` does **not** come back on
one tick.

**The re-run is not bit-identical, predicted in advance, and one of its two causes was
not.** 18 of 23 shared regimes identical, 5 movers, **zero outcome changes** across
182 outcome lines. Three movers touch the `health` line as predicted. Two —
`managed_cabinet_shorted` and `austerity_cabinet_shorted` — move because
`quality_target()` multiplies by `Cabinet.effectiveness()`, so **a reshuffle moves the
stock with every spending line untouched**. That widens the cabinet system's charter,
which V1.1d had deliberately kept surgical; kept rather than gated, because a model
where a corrupt state delivers less but an incompetently-run one delivers the same is
not defensible. The eighteenth regime is the **cheap kind** (a law at a month is a
shape the harness has known since `AMENDMENT_REGIMES`) and it is the legibility
evidence: same budget, `managed` **HELD** at 26.8 % in 2032, `managed_corrupts`
**LOST** at 23.8 % with `health` the top attributed issue at salience 0.29. Model:
[docs/society-model.md](docs/society-model.md).

**The readout is on the OVERVIEW and the plan said the polling panel.** That panel's
contract is that *every* figure on it has been through `PollNoise`, and a service
statistic is not a poll — the government knows how well its own hospitals run. Both
lines sit under GOVERNMENT beside `military_capability`, `_fill_defence()`'s slot and
its argument. **The screenshot pass earned its keep for the tenth session running**,
and this time by catching layout rather than a bug: the GOVERNMENT column is ~110px
and the first captions wrapped to eight lines, so both now lead with the deviation
rather than the level. **`tools/run_tests.sh` never ran `tests/test_companies.gd`** —
authored at V1.4a and absent from the list, so V1.4a, V1.4b and V1.4c all shipped with
their own test file running only by hand. Found by noticing `test_society.gd` was
missing from a green suite; it is `check_names.sh`'s U6b failure in a new place, a
check that silently covers less than it appears to. Both are wired in now and both
pass.

## V1.5b

**V1.5b shipped demographics and migration, and the row's central premise was wrong.**
The decomposition deferred (b) partly because ten authored age structures with **no
dataset behind them** would be the clustered `coalition_position` failure a block later.
The dataset exists: the World Bank publishes age structure and 15–64 participation for
all ten, on the same licence through the same loop, and `docs/data-sources.md`'s loop has
always fetched `date=2015:2024` — so a per-nation ageing **slope** cost one extra read of
a series already on disk and **no extra download**. Old-age dependency spans **LUX 0.225
to ITA 0.388**, the slopes span **2.58×**, and nothing clusters. Twenty-third stale-row
instance.

**The cohort machine was designed and CUT, and Luxembourg is the proof.** Nothing reads a
head *count* — `population` enters no equation in `economy.gd`, and
`firm_jobs_offset_pct()` returns before its denominator unless a firm has moved. A
uniform 15–64 bucket predicts Luxembourg ages **fastest** of the ten; measured, it ages
**slowest**. And fertility and life expectancy are *inputs* to a projection whose output
the dataset already publishes. So `src/sim/demography.gd` carries two live shares on a
**linear measured drift**, the working share is the **residual** (`1 − young − old`,
never stored, so the three sum to 1.0 by construction), and
`demography_constants.gd` has **exactly one tuned constant**. Deliberately *not*
`capability_target()`/`capability_step()`'s shape: those converge on a target the player
sets, and a population converges on nothing a president decides.

**The shortfall is a DENOMINATOR at one existing site.** `spending_pct_gdp` is a
player-set rate, so ageing cannot drive it; what ageing does is make the same rate buy
less. `Society.quality_target()` divides by `Demography.dependency_factor()`, exactly 1.0
at new game for all ten — which discharged `QUALITY_KEYS`'s own promise word for word
(*"It joins by becoming an entry"*) for **one entry and zero lines in `opinion.gd`**.
Migration is the **second `effects.society` term**, signed both ways, and the sign is
load-bearing rather than symmetric: ageing is otherwise a permanent monotone charge no
verb can close. `immigration_tightening` was re-authored off `structural_unemployment_pct`
as booked, `labour_migration_scheme` is the other direction, and `law.gd` gained the third
anti-double-count pair — scoped to the **pair**, not the channel, so `labour.json`'s four
laws keep the scalar.

**A pre-committed tiebreaker failed for a THIRD distinct reason and the rule is
extended.** `MIGRATION_SHARE_BETA`'s was a genuine strict ordering — exactly what V1.5a's
restated rule demands — and it still failed, because **both bands are one-sided
minimums**: every candidate above the threshold passes, so "largest passing" returns the
top row of whatever grid was swept, and widening the grid moved the answer from 0.010 to
0.016. **The range was choosing the constant.** The rule now reads: a tiebreaker must
strictly order the survivors **and its answer must not move when the candidate range is
widened**. The corrected selector (smallest passing) chose **0.0090**, *interior* to the
grid. A cheap diagnostic falls out: **a value sitting at an endpoint of the swept range is
a suspect, not a result.** Separately the **kill switch fired** on
`DEPENDENCY_ELASTICITY["health"]` — −0.51 on its widest bloc row even at 1.00 against a
±3.0 floor — so the entry was **deleted** and the table ships with one.

**Two constants were deleted and only content replaced them.** `POP_GROWTH_PCT` (one flat
0.15 for all ten, against measured ITA **−0.238** and LUX **+1.938** — it had every nation
in Europe growing and one of them shrinks) and `LABOUR_FORCE_SHARE` (0.45, whose own
comment called it "measured, not a dial" — true for France to three digits at 0.4543, and
wrong for Germany at 0.5027). `tools/companies_probe.gd` read the second directly and was
fixed in the same commit, which is V1.3e's parse break avoided rather than repeated.

**The re-run held the prediction: 23 of 24 shared regimes bit-identical in GDP, growth,
trend, unemployment, debt and deficit, and ZERO outcome changes.** The one mover is
`managed_subsidises`, exactly the regime the labour-force denominator was predicted to
reach. **The bloc transfer moved nothing and the handoff was wrong to expect it to**:
`Bloc.net_positions()` reads the loader's Nation objects and is called once at new-game,
never re-ticked. The nineteenth regime is the cheap kind, and the legibility evidence is
sharper than the headline — under `managed_corrupts` the result screen now attributes
`pensions` at salience 0.17, where before it could not appear at all. Model:
[docs/demography-model.md](docs/demography-model.md).

**`BLOC_SIZE.pensioners` stays authored and the refusal is recorded beside it**, pinned by
`tests/test_demography.gd`. It is 0.24 against a measured 65+ share of 0.2215 drifting to
~0.27 — one quantity, two writers — but it is an *electorate* share, `BLOC_TURNOUT` already
models the age effect a second time, and the table is read by `elections.gd` twice plus
`cabinet.gd`, `opinion.gd` and `polling_panel.gd`, so making it live would move election
**results** and re-baseline every opinion constant ever measured.

**`tools/import_data.py` was silently deleting fields, and the diff is how it was found.**
`write_nation_file()` rebuilt each nation file from an *enumerated* key list, so every
top-level field a later session added was dropped on the next import — U6b's `leader`
block and the `flag` block both already had been. It now rebuilds from the file's own key
order and writes short scalar arrays back on one line, which is what makes *the diff shows
only what you meant to change* a usable check. **Two test fixtures also predated
`imported.cohorts`** and began failing for a second, unrelated reason before reaching the
check each exists for; both were repaired rather than worked around.

The readout is split: the **dependency ratio** is on the economy panel under the
population caption it decomposes (a fact about the *country*), and the **pensions delivery
line** arrives free on the overview because `_fill_services()` already loops
`QUALITY_KEYS` (a fact about the *government*). `screenshot.gd` gained `--migrate`, and
the pass confirmed both: the economy panel reads *"43 retired per 100 of working age, +7
since the start"* with the clock correctly at 2030, and the overview reads *"Pensions
delivery −0.34 on baseline"* in red while the health line stays **silent**.

## V1.5c

**V1.5c shipped unrest, and it is the session where the block's inverted rule and the
rule it replaced finally agree.** The statistic is `unrest_pct` and **the verb is the
union's** — V1.3a's rule never said the actor had to be the player. `src/sim/unrest.gd` is
a grievance stock, a deterministic agent on `_tick_agenda()`'s shape, and a decaying
output impulse: the **sixth** addend in `economy.gd`'s growth sum and the first on the
decaying side of that comment's distinction since `demand_impulse_pct` itself, because a
strike is a shock and not a standing condition.

**The price the session was designed with does not reach a voter, and the probe is what
said so.** Output-only was the plan: approval would fall through `growth` and `jobs`,
which already exist and which `elections.gd` already attributes. Measured on an isolated
path, fourteen years at maximum grievance costs **4.94 % of GDP** and moves the workers
approval row **0.42 points** — at every candidate, and for a structural reason. The
opinion model prices **rates and ratios**: `growth` reads `growth − trend` and returns to
zero once a shock is steady, unemployment mean-reverts to a structural level a strike
never writes, and every fiscal figure is a share of GDP, so a GDP five per cent smaller
changes almost none of them. **A permanent level loss is invisible to a model that prices
changes**, which is `opinion.gd`'s deficit-not-debt argument from the other side. Raising
the scale would be tuning against an arithmetic impossibility — V1.5b's refusal for
`DEPENDENCY_ELASTICITY["health"]` — but V1.5b's remedy there was to DELETE, and that is
not available to the session's only price. `UNREST_OPINION_SCALE` exists because a
pre-committed band said the design was wrong.

**The row's own warning is the design constraint, and it is defeated mechanically.**
*Unrest driven by nothing the average voter does not already feel is a second approval
number with a different label* — so the hardship term reads **two rows of the electorate
and not six**, because `Discipline.unpopularity()` is already the six-row version and is
read by `discipline.gd`, `government.gd` and `cabinet.gd`; a second one would be
`military_capability` a fifth time. Two rows are still a re-weighting, so the target
carries two terms **no opinion issue reads**: the Gini drift and the settlement stance.
**Zero new weights and zero new scales** — `BLOC_SALIENCE_BASE`, `salience_weights()` and
`BLOC_SIZE` already exist, so who strikes falls out of a table written at S5, and workers
weight `defence` at 0.00 and `tax_vat` at 0.08, which is exactly what `managed` moves.

**§6 said the inequality index "cannot be derived" and was right; it does not have to
be.** World Bank `SI.POV.GINI` covers all ten on the same loop, levels span **NLD 25.7 →
ITA 34.3** and **the signs differ** — six falling, four rising. **Twenty-fourth stale-row
instance.** The cost is booked: coverage stops at 2021–2023, so `import_data.py` gained a
nearest-year fallback **scoped to that one series** (a silent fallback on GDP would turn a
broken download into a stale figure) and records the year it used. It stays a stopgap in
the way that matters — nothing the player does moves it — and `tests/test_unrest.gd`
mutates the corporate rate, every `state_share` and every `regulation_burden` and requires
the index to be **bit-identical**, so §6 discharges it by turning a test red. The
stateless pure read was designed and **cut by the harness**: `balance_probe.gd` and
`tests/test_balance.gd` both set `state.year` *after* `new_game()`, so no elapsed-time
source survives; the drift went to `Demography.tick_month()`, which is V1.5b's own split
made again.

**`settlement` is the third `effects.society` term, and a channel carrying a third
register is schema rather than luck.** Without it the only lever pointed at a strike is a
spending increase, which necessarily widens the deficit. V1.5a's `society` +
`spending_pct_gdp` refusal was **narrowed from the channel to the pair** — its stated
reason is about *corruption* reaching the spending issues, never about the channel — which
is V1.5b's own narrowing one session on and turns an existing red green. **And there is no
fourth anti-double-count**: `settlement` + `structural_unemployment_pct` was written and
deleted once it was checked against the criterion the three existing refusals use (*same
act, same landing site **and same units***) rather than against the pattern they make. One
mechanism priced twice is not two mechanisms landing on one number, and a rule forbidding
the second would forbid `bloc_offset` beside anything. Recorded in `law.gd`, because the
next session will reach for a fifth by symmetry and **symmetry is not the test**.

**The probe corrected the session six times, fourteen sessions running, and four are about
the discipline itself** — a nearest-to-X tiebreaker is only as good as the grid's
**resolution** (0.08 → **0.07** on refinement); a band whose ceiling is one regime's peak
makes *largest passing* mean *that peak* (52.0 rejected, **45.0** ships); V1.5b's
smallest-passing correction **inverts** once the interval is two-sided, so two model
criteria take the **midpoint** and a guard rail does not select at all; and a band can be
applied to an observable the channel does not reach. `UNREST_COOLDOWN_MONTHS` is the
oldest failure a fifth time — every candidate passed, so it is set by argument and says
so. `INEQUALITY_BETA`'s kill switch **cleared** at 0.40 and the surviving term is small,
one month in thirty-six; recorded rather than tuned away. `general_strike` was **cut by
measurement**: no reachable budget produces one.

**A probe can inherit the blind spot it was written to catch, and the cross-check is what
found it.** All twenty-five shared regimes reported **zero acts** — every provocative
budget commits at month 1, loses the 2027 election, and the run stops at month 16 before a
stock converging at 0.07 matures. `unrest_probe.gd` missed it because its own loop has no
elections, so it ran a government already thrown out for fourteen more years: V1.3f's
error a **third** time in one session. `balance_probe.gd` now prints a reachability column
for every regime and gained a **mid-run budget switch**, the first regime shape in this
project that changes policy part-way through a run, because the reachable case is *govern
well, win, then provoke*. `managed_then_austerity` holds 2027 at 26.1 %, reaches grievance
**48.74**, fires **two acts** and is destroyed in 2032 at **9.7 %**. The threshold needed
no retuning.

**The re-run is the cleanest split this block has produced**: all **25 shared regimes
bit-identical in GDP, growth, trend, unemployment, debt and deficit**, approval moving in
all 25 by at most 2.60 points, and **zero outcome changes**. Three new regimes, the
twentieth to twenty-second. The legibility evidence is exact — same budget, one settlement
law at month 60, and `managed_then_austerity_settles` turns the grievance over (46.21 →
40.04), the second strike **does not happen**, and the incumbent's vote is 1.9 points
higher while still losing. `unrest_pct` is the first `PRECONDITION_FIELDS` entry naming
something the player did not do, `>=` only and asserted over the whole law list; the suite
immediately caught that the whitelist and `_read_field()` are the same list in **two
places** and the session had added one. Three test fixtures predated
`imported.inequality`, which is V1.5b's own fixture failure repeating. Model:
[docs/unrest-model.md](docs/unrest-model.md).

## V1.5d

**V1.5d shipped media and information, and the V1.5 block is complete.** The row asked for
outlets that frame the player's actions, and **the framing machine already existed**:
`opinion.gd`'s `salience_weights()` has amplified bad news at a global `SALIENCE_GAIN = 5.0`
since S10 -- amplification with no source, and "bad news travels" is a claim about the press
this project had been making for six blocks with no outlet behind it. So V1.5d builds no
machine; it makes one scalar into **six** and the six average back to the one.
**Twenty-fifth stale-row instance**, plus a twenty-sixth the same day:
`public_broadcasting_reform` had priced itself as `other_revenue_pct_gdp` since the MVP,
which is V1.5a's `anti_corruption_agency` verbatim and the block's **fourth booked
retro-fit**.

**An outlet is five fields, and what it does NOT carry is the design.** `data/outlets/`
takes `data/companies/`'s per-nation shape; an absent file means no press and the model all
ten ran before. It names one **audience bloc**, so `BLOC_SALIENCE_BASE` already says who
cares about what and the session adds **zero new weight tables**. It carries **no authored
alignment, hostility, bias or stance** -- alignment is derived from its position against the
government's own `coalition_position`, so **the press turns on you when your government
re-forms**, and `outlet.gd`'s unrecognised-key error says so out loud rather than leaving an
absence a later reader repairs.

**The mean anchor is the session's one model correction, and a measurement taken before a
line of `src/` forced it.** The design was start-anchored, which is `start_service_quality`'s
idiom and the one this project reaches for by reflex. Step 0's travel table refuted it:
France's `coalition_position` travels **0.044** over 168 months where Germany's travels 0.600
and Britain's 0.870, because France holds a majority through every election -- putting the
constant near 16 for Britain and near **250 for France**, the nation the game is about.
**The pre-committed fallback was REFUSED** (it leaves the register inert until a player
command, which is the decay V1.3a's rule prevents). Anchoring on the size-weighted national
mean makes `sum_b BLOC_SIZE[b] * dev[b]` **exactly 0**, so the mean gain is exactly
`SALIENCE_GAIN` and every opinion constant measured since S10 keeps its calibration -- and it
gives a **friendly** press a channel, which a start anchor structurally could not, since
`severity` is `clampf(-sat, 0, 1)`. Without that, censorship was strictly dominated on the
framing axis.

**Press freedom's "legitimacy cost" named a quantity that already existed.** The row handed
(d) the choice of inventing one or dropping the clause; neither was taken. Legitimacy is
willingness to accept your rule outside the ballot box, which is V1.5c's grievance, whose own
doc says a country can be angry for reasons its approval figure does not contain --
and `UNREST_BLOCS` is `["workers", "students"]`, exactly who marches over censorship. It is
the **fourth `effects.society` term** with **two prices**, and `_extract_society()` needed no
change at all: it is generic over `SOCIETY_TERMS`, so all four error strings updated
themselves.

**`law.gd`'s warning worked, and the refusal that was warranted lives in a SIGNATURE.** That
file records that the next session would reach for a fourth anti-double-count by symmetry.
V1.5d reached, checked four candidate pairs against *same act, same landing site AND same
units*, and every one failed. What is genuinely the first kind -- press freedom reaching the
grievance target through both `PRESS_UNREST_BETA` and `Unrest.hardship()` -- is one register
reaching one number twice through **code**, not two keys on one law, so
`Opinion.salience_weights()` takes its gain as a **required third argument** and `unrest.gd`
states the unframed one out loud. Defaulted, silence would mean "unframed".

**Scandals left the block for §8** -- a third outcome §8's warning box did not enumerate, and
required by that box's own argument: "requiring a response" is a choice list, so a
non-generic scandal has no response and is then a framing shock; and the event schema is the
union of the channels §3-7 create, one of which V1.5d creates. **Government messaging was
cut** as press freedom's positive direction with a different label. Both in both rows.

**The probe corrected the session four times, and the sharpest is about the guard-rail rule.**
`FRAMING_BETA` pre-committed to V1.5c's rule (e) and it failed twice: band (ii) was a
**bound, not a selector**, so the real upper edge is the clamp -- a guard rail -- and (e) then
prescribes smallest-passing, which is wrong because **rule (e) assumes the model edge is a
PLATEAU**. V1.5c's table was lumpy; this response is linear, so smallest-passing is just
"wherever the band crosses" and every refinement moves it. **Rule extended: when the model
edge is a smooth crossing, neither edge selects and the interior governs.** 4.50, the
midpoint of `[3.02, 6.00]`. `PRESS_UNREST_BETA` failed in the older way and is **set by
argument** as a ratio against `SETTLEMENT_BETA`.

**The balance re-run was predicted NOT to be bit-identical, came back with a diff of exactly
ZERO lines, and the wrong prediction is what caught the bug** -- neither `balance_probe.gd`
nor `tests/test_balance.gd` called `Media.tick_month()`, so both harnesses were running the
pre-session model and their agreement was about nothing. **A bit-identical re-run is the
reassuring outcome, so nothing about it invites suspicion, which is exactly why the
prediction must be written down first.** With both fixed: all 28 shared regimes bit-identical
in GDP, growth, trend, unemployment, debt and deficit, approval moving by at most **3.00
points**, and **zero outcome changes**. The 29th regime is the cheap kind and is the
legibility evidence -- one `broadcasting_oversight_act` at month 24 moves the worst bloc from
**rural 45 to students 40**.

**`SAVE_VERSION` stays at 18**, and the design pass predicted 19. It was correct about the
design it was given -- no `start_coalition_position` is serialised, so a `start_press_stance`
would have been `start_bloc_burden`'s case at V1.3d -- and the mean anchor deleted the field
and the bump with it. `tests/test_save_load.gd` pins the **absence**. The readout is one line
on the overview's GOVERNMENT column, silent at zero, printing the **stance** and not the
spread: the spread is non-zero from month 1 in all three authored nations, so a line on it
would be permanent furniture. The effect reaches the polling panel's agenda and
`elections.gd`'s attribution **for free** through `ns.issue_salience`. Model:
[docs/media-model.md](docs/media-model.md).

## V1.6e

**V1.6e shipped sectoral investment, and the row asked for a write the model refuses.**
[[docs/tiers/v1.md]] section 6 says the lever acts "on `sector_output` itself";
`Economy._apply_growth_to_sectors()` reconciles the three sectors against the month's GDP
target **exactly**, so an absolute injection is cancelled by the cyclical residual inside
the same tick -- 27.9 bn into French industry leaves GDP **+0.024 bn** and moves only the
composition. Instance **thirty-five**. The honest landing site is the per-sector **trend
rate**, `Trade.sector_shift()`'s slot, and the difference between them is the session's
sharpest sentence: **a trade shift must sum to zero and an investment shift must not**. So
`Investment.sector_trend_shift()` is read at BOTH of `economy.gd`'s sites, and adding it at
`trend_pct()` share-weighted is what stops the residual taking the level effect back. It
moves **potential**, where V1.6a's cycle deliberately does not.

**Instance thirty-six: "carries no employment term" is a CONSEQUENCE rather than a
prohibition.** Okun reads `growth - trend` and structural unemployment reads only the tax
wedge, the law offset and the firm layer, so a trend-side lever has **no permanent
employment channel available to it at all** -- *sectoral investment buys output and, in the
long run, no jobs*. Pinned bit-identically in `tests/test_sectors.gd` and visible in the
harness: same budget, `industrial_policy` prints the **identical unemployment as `managed`
in every year** while GDP diverges 4.9 % and the rural row falls 43 to 38.

**The probe corrected the model twice, sixteen sessions running, and the first is the
strictly-dominated shape appearing in a PRICE.** Six previous instances were all in
effects; here the effect was proportionate and the BILL was flat, so services moved growth
0.4865 and agriculture 0.0077 for identical money. The bill scales with the sector's own
share of GDP now: no constant added, and one **deleted** -- three shares summing to exactly
1.0 bound the whole bill by construction, so `INVESTMENT_BILL_MAX_PCT_GDP` was a guard rail
guarding arithmetic. The second correction is V1.6d's own finding one session on: the beta
band's clause (ii) was **measuring the clamp**. A third the grid nearly caused: two of three
constants are closed form and the first run still reported the widest passing GRID ROW as
the interval.

**All three constants are closed form or fitted to a fixed point**, the strongest
first-pass position on this project's record. `INVESTMENT_COST_PCT_GDP` = 0.8161, banded
against **what V1.6d left of `DEFICIT_SCALE_PP`** -- 1.38 points of six, the one thing this
session was told to measure first. `CAPITAL_CONVERGENCE` = 0.4518, midpoint taken in
**months** not in the rate; t90 = 60.0 exactly, landing on `SHIFT_ADJUST`'s five-year
constant by accident. `SECTOR_TREND_BETA` = 0.7124, exact emulation, fixed point in one
pass. The kill switch cleared at 0.5760 and **two of three sectors sit below the floor** --
recorded as a structural bound, because French agriculture is 1.4 % of GDP and nothing a
president does to it moves France.

**The sixteenth `ISSUE_KEYS` question is answered NO on test 1 alone**: every YES was paid
because the price was not nameable otherwise, and this ships `data/investment-actions/` with
an authored `bloc_offset`. The S10 ratio was deliberately not swept. `effects.investment` is
the **seventh** channel and `data/investment-actions/` the third directory on
`data/diplomatic-actions/`'s shape; the **sector is authored rather than passed as a
target**, so which sector to back is a political decision as well as an arithmetic one.
The verb does **not** go through `Budget.commit()`, which is deliberate: that is how it
avoids [[docs/tax-model.md]] section 11's live `_pending` bug. `SAVE_VERSION` stays **22**
and the re-run is **bit-identical in all 32 shared regimes**, with two new regimes of the
expensive kind. **The fourteenth screenshot pass found one bug and it was the tool's** -- a
frame of a scrolling panel photographed at the top, showing three sector rows saying "No
state programme" while the ledger read a live 0.654 % of GDP. Model:
[docs/sector-model.md](docs/sector-model.md).

## V1.6f

**V1.6f shipped infrastructure projects, and the V1.6 block is COMPLETE.** The row
split **again, on the same rule V1.6e split on** -- recounted, what was left was two
S-track machines and one U-track one, so the marker layer with per-project geography as
content is **U6c** and V1.6f built the sim half. Two consecutive sessions cut on the
two-track rule, a first. The visible consequence is in the content: **no project names a
place**, because a lon/lat nothing reads is a field carrying no information, so the five
are generic and the session that draws them owns naming them.

## U6c

**U6c shipped the marker layer, and section 6 is complete to its last clause.**
**Instance thirty-nine is in the row's own wording**: every statement of this machine --
this file, `docs/projects-model.md` §1, `docs/sector-model.md` §5, the ROADMAP -- called
it *"per-project geography as content"*, and `data/project-actions/` is a **global flat
list**, so a lon/lat inside `effects.project` puts all ten nations' rail spine at one
point on the planet and the only repair is to make that directory per-nation, reopening
the global-list call V1.6f made freely. **Geography is per-NATION.** `data/nations/*.json`
grew an optional `project_sites` block (`project id -> [lon, lat]`), which is U6b's rule
verbatim -- *a law names an office; the nation's own `government.pretender_person` names
the person* -- so the action list stays global and **`src/core/project_action.gd` was not
edited at all**. The `project_name` exception was offered as precedent for a coordinate
and was not needed. Coverage is FRA/DEU/GBR, `data/companies/`'s and `data/outlets/`'s
rule; an absent block is legal and `tests/test_map_markers.gd` pins that path, along with
the two claims no loader could make -- every site names a project the content defines, and
every site is **inside its own nation's polygon**, which is what a mistyped digit fails.

**A marker is an always-on OVERLAY, not a fifth `LAYERS` entry, and the argument was
already written.** `map_view.gd`'s header says *"no map layer adds, removes or reorders a
draw layer"*: a `LAYERS` entry chooses a roster **fill**, one at a time, from a per-nation
scalar, where a marker is a point and is additive. As a layer it would also be
**structurally dead content** -- the nine never build, so its value reads exactly 0.0 for
nine of ten forever, which is V1.6f's own *a frame of an all-zero data layer proves
nothing* arriving as a design rather than as a frame. Markers are the **fifth draw pass**,
frontmost, and the test pins `LAYERS` at four.

**The hit test does not go through the roster, and the test reads the file to say so.**
U5b's *unclickable structurally* rests on `_nation_at_lonlat()` iterating `_polygons`
alone; a marker test routed through it would make that function answer for two things and
the property would die the day someone widened it. `_project_at_screen_point()` is a
**radius test in screen space** -- screen space because the glyph is a fixed number of
pixels at every zoom, so a degree-radius target would shrink as the player zoomed out to
find it -- and `tests/test_map_markers.gd` extracts its body from the source and fails on
either name, `tests/test_projects.gd`'s idiom for *`calendar.gd` is still a leaf*. A click
opens **Public Works** and does not fall through, or one press opens two windows.

`SAVE_VERSION` stays **23**: a site is content that round-trips through `data/nations/`,
and the marker list is derived at draw time from a register serialised at V1.6f. **No
balance re-run and no new regime** -- nothing in `src/sim/` was touched and a marker is not
a verb -- predicted in the plan rather than discovered. `main.gd`'s existing monthly
`_map_view.queue_redraw()` (U5c's staleness fix) is the whole refresh path; U6c adds none.
**The sixteenth screenshot pass found one bug and it was the readout's**: the hover read
*"12 of 96 months"* against a project with twelve months **left**, which a player reads as
twelve done, and it is now worded exactly as `projects_panel.gd` words it. Model:
[docs/projects-model.md](docs/projects-model.md) §1 and §14.

**Instance thirty-seven: the row never says what a project's PAYOFF IS**, which is V1.6b's
instance thirty in a new place -- and the answer was already in the model.
`ns.law_potential_target_pct` is a permanent accumulator with its own bound added to
`Economy._update_potential_shift()`'s target, and **a passed law and a finished project are
the same act**: a one-time decision producing a permanent addend. So `project_potential_target_pct`
is the **sixth writer of that target** and V1.6f adds **no third quantity reaching trend** --
`economy_constants.SHIFT_MAX_PCT`'s comment, which V1.6e had to amend, needed no second
amendment and now records that it was checked. **Instance thirty-eight: "slow" was already
half spent.** `SHIFT_ADJUST` is a five-year lag on that target (t50 **41.2** months, t90
**137.0**), so a build of N months and then that lag are two answers to one word, and the
band is written on the **delivered fraction from commit** rather than on the build length.

**U6a's `appointments` register was checked before a second scheduler was written and it is
NOT this machine.** That one holds a **deferred command** -- `due()` fires it once,
`Calendar.cancel()` is free and leaves no trace, and `calendar.gd` preloads no system by
design; a project is a **commitment in flight** that bills monthly and can be abandoned
part-built. What IS reused is the **surface**: `fixed_dates()` gained one row per build and
**no preload at all**, because the register counts **months remaining**, the idiom every
other countdown here already uses. `src/sim/projects.gd` does no date arithmetic, and
`tests/test_projects.gd` asserts the calendar is still a leaf.

**The probe corrected the session three times, seventeen sessions running, and the first is
the block's closing finding: a BILL is not a COST.** The cost clause was written on the
arithmetic stack -- 0.5200 against a 0.5639 headroom, inside -- and the measured peak deficit
came back **0.7615**, because a build that runs for eight years **borrows** for eight years
and V1.6c's interest rides on top. Every previous computed line is a standing rate against a
roughly standing debt, so bill and deficit moved together; **a line that runs for a fixed term
and STOPS is the first one where the distinction bites**. Solved to `peak = 1.4626 x stack`,
so the stack may reach 0.3875 and the re-authored ladder ships at 0.3600. The second: the
uniform-scale sweep that found it **declared escalation trigger 2**, and that was a statement
about the sweep -- clause (i) binds the cheapest project and (ii) the dearest pair, so one
multiplier cannot satisfy both and the free variable is the ladder's **spread**. The third:
the abandonment price was measured against a president who never began, so all five rows read
the net of a start and a cancellation in one month -- **identical across five projects that
are not alike**, which is what gave it away. A fourth was the probe reading its own prose.

**The model ships no cost, speed or strength constant at all.** V1.6e had one dial and three
constants turning it into a bill, a build rate and a coefficient, so `investment_action.gd`
refuses a second authored term as one strength written twice; here there is none, so
**duration, price and payoff are three independent facts** and the validator requires all
three. `projects_constants.gd` holds only bounds, and **a concurrency ceiling was considered
and is not there** -- how many run at once is the `project_count` precondition every action
carries, which makes it content. **Cost per unit of payoff FALLS with size and what buys the
discount is time**: the largest project cannot deliver anything inside the term that signs
it, checked as a standing dominance test (**0 dominated pairs**). Kill switch cleared at
**+0.2621 %/yr**; four of five sit below the floor, which is that shape rather than a miss.
**A programme you can stop; a project you can only abandon.**

**`SAVE_VERSION` is 23, earned by the DONE half of one dictionary** -- V1.3g's `deployments`
split in a new place, and the split is worth more than the bump. The **seventeenth
`ISSUE_KEYS` question is answered NO on test 1**, as V1.6e's was, and the interesting half is
that two consecutive sessions failed the same test for the same reason: a session shipping a
content object has somewhere to put the price. **The re-run is bit-identical across all 34
shared regimes**, predicted in advance, with two new regimes of the expensive kind, both
surviving both presidential elections -- same budget, `managed` against `public_works` in
2037 gives GDP 3340 -> **3354**, trend +1.31 -> **+1.53**, worst bloc rural 43 -> **38** and
**unemployment 7.67 in both**. **The fifteenth screenshot pass found two bugs and both
were the readout's**: the budget row's `0.19% (6 bn) (1 building)` is the **widest cell on
the panel**, and both value columns size to their widest row, so one extra clause pushed
the whole `proposed` column past the window edge -- the number was right and the frame
still showed a budget the player could not read without dragging; and the diary read
*"Opens: Build the High-Speed Rail Spine"*, because the only name in the content was the
ACTION's, which is an imperative -- right on a button, wrong after a colon -- so
`effects.project` gained an authored `project_name`, deliberately NOT in the
three-quantity term list, because a name is not a strength. Model:
[docs/projects-model.md](docs/projects-model.md).

## V1.6

**V1.6 is decomposed into five sessions, V1.6a-e, and (a) is built.** The row was five
bullets plus an obligation inherited from V1.4c: (a) the business cycle, (b) inflation,
(c) bond yields and the credit rating, (d) five taxes and brackets, (e) sectoral
investment and infrastructure projects. The split is on **machine count** - five - and
**(e) is recorded in advance as the row most likely to split**, with infrastructure
*projects* as the cut. **Section 6 runs under BOTH block rules and the decomposition
says which per session**: (a), (b) and (c) ship no verb at all, because there is no
monetary policy in this game, so they run under V1.5's inverted rule; (d) and (e) ship
verbs and run under V1.3a's. The row was wrong twice, instances **twenty-seven and
twenty-eight** - "infrastructure projects" names `_update_potential_shift()`'s
`INFRA_BETA` machine from S4 and *merges two mechanics* `mechanics-economy.md` tiers
separately, dropping its "visible on the map" clause; and "arriving whether or not
deserved" collides head-on with `economy-model.md`'s no-randomness rule. The orphan
check came back **clean**, which is itself the finding.

## V1.6a

**V1.6a shipped the business cycle, and it has no `tick_month()`.** `Cycle.impulse_pct()`
is a pure function of (nation id, absolute month) - three sines whose periods and signs
come from a splitmix32 hash, `poll_noise.gd`'s device moved into `src/sim/` and
deliberately duplicated rather than shared. `Economy.tick_month()` writes
`cycle_impulse_pct` from it in the same pre-pass that writes `coercion_impulse_pct`, so
**every harness reaches it through a call they all already make** - V1.5d's bug made
structurally impossible rather than remembered, and falsified before it was trusted with
a 1434-line diff and no wiring edits. The impulse is **bounded by construction** at
`K/sqrt(K/2)`, which is a stronger guarantee than a clamp because there is no value to
set wrong, and it is **exactly 0.0 at the epoch** for all ten - not for a re-run, but
because the content describes a nation at potential.

**The session's sharpest finding is a legibility floor that cannot be met.** The two
pre-committed bands - readable past the +-3.0 poll-noise floor, and no more volatile
than France measurably is - **have no overlap at any candidate** on a grid refined to
0.05 and widened to 4.00. At France's real volatility a recession moves approval ~2.8
points, under the floor, and cannot be lifted over it without making France more
volatile than France is. Recorded rather than traded against, and it is the right way
round twice: `poll_noise.gd` fuzzes *approval* because a poll is published while growth
and unemployment print exactly, so the cycle's primary readout carries no noise; and
**that is the mechanic**, because a slump unmistakable in the figures and ambiguous in
the polls is a president who cannot prove it was not their fault. The constant is
**fitted** instead - realised growth sd **1.260** against France's measured **1.262** -
and the rule that falls out generalises: **a band edge MOVES under widening or
refinement; a fit CONVERGES.**

**Both constants are measured or fitted and one planned sweep was DELETED.**
`CYCLE_COMMON_SHARE` is 0.619 by variance share, cross-checked at 0.633 by mean pairwise
correlation - two statistics of one dataset agreeing to 0.014, which is V1.5c's
two-harness rule applied to a measurement. The per-nation `amplitude_rel` is imported,
0.689 (FRA) to 1.475 (LUX), and **the dataset needed a different window from every other
series in `imported`**: on 2015-2024 France's growth sd is 3.333 and 0.579 with 2020-21
removed, a factor of **5.8**, so a session reusing the existing window would have shipped
a cycle whose whole amplitude was one pandemic. 2008-09 is *not* excluded - a financial
crisis is a business cycle.

**The decomposition's own call 3 was refuted by its own probe**, which is a first: the
procyclical half of V1.4c's obligation was booked to (a) as free and measured **1.07x**
against a 1.5x floor, because `dividend_revenue_pct_gdp()` divides by GDP and the cycle
moves numerator and denominator together. **A quantity expressed as a share of GDP is not
procyclical by construction**, and every fiscal line here is such a share. The obligation
passes to V1.6c whole. **V1.5c's two constants were re-baselined and came back
UNCHANGED** on both harnesses - every grievance peak rises, the act count is identical in
all 29 regimes.

**Three bugs, all harnesses.** `Budget.project()` had **never advanced the clock** on its
copy - twelve ticks at one date for eleven sessions, invisible because nothing in it read
the date until now - and `tests/test_budget.gd`'s own runner froze it too, so the two
agreed to 1e-9 while both were wrong. `tests/test_trade.gd` measured a partner recession
against **zero** and got **+0.039** once eight other partners were moving. The re-run was
predicted NOT bit-identical and was not: **all 29 regimes differ, ZERO outcome changes**,
and the deficit moves 0.07 points against approval's 7.60 because every budget line is a
share of GDP. **No thirtieth regime was needed** - the cycle is not a verb. Model:
[docs/cycle-model.md](docs/cycle-model.md).

## V1.6b

**V1.6b shipped inflation, and the row's own input was refuted by the data.** The
constant-price boundary was decided before any code and holds: **no nominal layer**, four
candidate nominal channels named and cut, and `tests/test_inflation.gd` walks `src/sim/`
and fails if any file outside `inflation.gd` reads the raw stock -- so the boundary is a
check rather than a paragraph. What did not hold is the row's *"price pressure from the
gap, the impulse and (a)'s shock"*: the three are **one quantity written three times**
(the output gap IS the accumulated integral of the growth addends), and regressed on
`FP.CPI.TOTL.ZG` the **output gap carries no signal and its sign FLIPS between
sub-samples** -- +0.204 pre-euro, +0.098 euro era, -0.140 pooled -- while the
**unemployment gap** is stable and correctly signed in both disjoint halves. The model
reads unemployment, which is `economy-model.md`'s own treatment of Okun and dissolves the
double count rather than patching it. **Instances twenty-nine and thirty.**

**Three of five constants are MEASURED, and the selection rule for the slope is the
model's own premise.** Two disjoint sub-samples bracket it at [0.252, 0.376] and the
**euro-era** figure ships, because `out-of-scope-mvp.md` records that France does not set
its own interest rate and that is exactly what 1999-2024 measures; the pooled figure is
the weakest of the three and would have been the wrong one to ship on the use-all-the-data
instinct. Persistence is converted **exactly** -- the twelfth root of the annual AR(1),
where a linear `rho/12` would have made the model 20 % stickier than the data. The anchors
are per-nation content, CHE 1.117 to ESP 2.903, and `_excludes` is `[]` **explicitly**: the
2022-23 energy spike is a price shock in a series measuring prices, where V1.6a's excluded
pandemic was an output shock in a series measuring output.

**The `ISSUE_KEYS` question is answered YES for the first time**, after V1.3d's yes for
`europe` and five noes recorded in `opinion_constants.gd`. Two tests separate it: it ships
**no verb and no content object**, so unlike every previous candidate there is no authored
`bloc_offset` to price it on instead; and **a flat load structurally cannot become more
salient**, which is the one thing inflation must do. Test 4 was measured as a **fit**
against the model's own standard rather than a band -- `|corr(inflation, growth)|` 0.2276
against `|corr(jobs, growth)|` 0.3185 -- and the S10 drift is **+0.75 %** in the safe
direction, with a flat-weight control at **-0.059 %** isolating the cause as the bloc
profile rather than the thirteenth key as such. It is also the first pair of issues one
event moves in **opposite directions**.

**V1.6a's legibility floor appears in a second place, and the rule about deletion gains a
stated exception.** Probe table (a) runs first and puts the reachable deviation at **0.145
points** -- enough for the opinion price, not for the growth one, whose visibility band
needs one point of inflation to cost two points of annual growth. Neither raised (tuning a
measured slope until it is visible is what V1.5b and V1.6a each refused) nor deleted: **a
term that is STRUCTURAL rather than decorative survives a failed visibility band**, and
this one is the only thing making the loop negative feedback. On the GDP axis the channel
is honestly below the readable floor and says so.

**The probe corrected itself twice, and the second is the sharper: its table was not
independent of the constant it chose.** A probe cannot change a `const` at runtime, so the
first version rescaled the measured headline from the shipped value -- and the passing
interval MOVED when the shipped constant moved. V1.5b's *the range was choosing the
constant* in a new costume, caught only by setting the constant once and re-running. The
fix emulates a candidate exactly, by displacing the stock to whatever produces the same
satisfaction.

**The re-run: 0 of 29 regimes bit-identical, ONE outcome change of 47, no thirtieth
regime.** The six approval-only movers are **exactly the contractionary regimes**, which
is the one-sided growth cost visible in the harness rather than a coincidence. `SAVE_VERSION`
is **20 on three fields of four**, a first, and the three fail the rule by three DIFFERENT
failures, so the test asserts them separately. The screenshot pass earned its keep for the
**eleventh** session running and both bugs were the readout's: a format **copied from the
neighbouring row** (`%+.1f` against a quantity whose whole reachable range is 0.145 points,
printing "+0.0" against a live figure) and a flag that ticked 48 months and so ran **past**
the thing it exists to photograph. Model: [docs/inflation-model.md](docs/inflation-model.md).

## V1.6c

**V1.6c shipped the bond market, and two of the four inputs the row names do not exist.**
`economy_constants.DEBT_REAL_RATE_PCT` stays the **anchor** and `Budget.recompute()` reads
`Credit.yield_pct(ns)` where it read the constant since the MVP: the yield is that constant
plus a spread whose every input is a deviation against the nation's **own start**, so the
spread reads **exactly 0.0** at new game and every balance figure this project has quoted
against a flat 2.0 keeps its meaning. That call is the whole of what kept the re-baseline
bounded, and it is `trade_baseline_by_partner`'s idiom in the place with the most to lose by
it. `src/sim/credit.gd` is **stateless** -- no `tick_month()`, no accumulator, nothing it
writes on `NationState` -- so the rating is one extra read of the yield,
`Defence.allies()`'s shape and the thing the decomposition names as this session's split
trigger. **The absence of a stored rating is pinned in the save format**, not only in prose.

**Step 0 looked for a sovereign-rate series before a band was written, and there is not
one.** `FR.INR.RINR` covers 4 of 10 on disjoint windows with **France carrying zero rows**;
`GC.DOD.TOTL.GD.ZS` covers 7 of 10 with four under five years. So the slopes are swept, and
that is a checked result rather than the reach for a band the last three sessions kept
warning about. **The cross-check then nearly agreed** -- an empirical 0.02-0.05 against a
swept **0.0150**, a factor of 1.3 rather than an order of magnitude -- and what excludes an
honest 0.02 is the **opinion model's resolution** and not the bond market: at 0.02 a
do-nothing president's debt service uses half of `DEFICIT_SCALE_PP`'s whole span on its own.

**Instance thirty-one is that the deficit is the DERIVATIVE of the debt, and the sweep is
what turned that from a suspicion into a result.** Three clauses, mutually inconsistent:
isolated against a control the deficit term is legible only above a slope of 0.20, and by
0.145 it already outweighs twelve months of the level it exists to lead. `corr(debt gap,
deficit gap)` measured **0.9948** against V1.6b's accepted 0.3185. Deleting it removed the
session's **only positive feedback loop** with it, since `debt_service_pct_gdp` is *inside*
`deficit_pct_gdp` -- what was going to be an argument about a one-month lag is now a fact
about the call order. **And the inflation term was deleted DESPITE PASSING ITS BAND**, which
is new: `DEBT_REAL_RATE_PCT` is a *real* rate and inflation raises a *nominal* one, so a term
there is the Fisher effect, the nominal layer V1.6b cut smuggled back in through the yield.
**A band is a test of size, not of legitimacy.**

**The debt slope needed THREE sets of bands and the probe caught each, seventeen sessions
running.** The first measured a spendthrift regime, which does not widen the debt but
*spirals* to the clamp -- a band on a saturated run measures the clamp. The second measured
`hands_off` and passed at 0.0005, because a debt ratio walking 110 to 200 moves the service
line 1.8 points **at the anchor rate with no channel at all** -- a band on a raw move
measures the model that was already there, and the fix is the control `tests/test_trade.gd`
needed at V1.6a. The third ships, interior, stable under refinement and **iterated to a fixed
point**: the shipped value equals the midpoint measured at it, stronger than V1.6b's 0.003
check. `YIELD_MIN` moved from -1.0 to **0.0** on a sign bug the probe found -- a player who
runs surpluses drives `debt_eur_bn` negative, and two negatives multiply, so a treasury
holding net assets would have **paid interest on them**.

**V1.4c's obligation is discharged on a RATE**, the one quantity in this model that is not a
share of GDP and exactly what V1.6a's refutation asked for. The dividend is held
`EQUITY_PREMIUM_PCT` = **1.12** above the anchor while the borrowing rate floats past it, so
a nationalisation is a flow gain while the player's credit is good and a flow loss once the
spread exceeds the premium; the crossing is exact and needs no simulation. The kill switch
did **not** fire, and clause (i) was tightened on the record from *some reachable regime* --
a bound rather than a selector, V1.5a's failure -- to `hands_off`: **doing nothing for long
enough turns a nationalisation into a loss.**

**The re-baseline is the cleanest split this block has produced**: 0 of 29 regimes
bit-identical as predicted, **one outcome change of 48**, and growth, trend and unemployment
**bit-identical in all 217 printed year-rows** because the yield reaches the **budget** and
never the economy -- `debt_service_pct_gdp` is not a player-set line, so it never enters
`demand_impulse_pct`. No thirtieth regime. The readout is one caption on the economy panel's
PUBLIC FINANCES column under the debt-service line it explains, never silent, leading with
the rating and red once the letter falls out of the band the anchor sits in;
`screenshot.gd` gained `--downgrade`, and **the twelfth screenshot pass found no bug**, a
first, reported as such rather than dressed up. Model:
[docs/credit-model.md](docs/credit-model.md).

## V1.6d

**V1.6d shipped five taxes and brackets, and the tripwire meant to fire did not.**
`TAX_KEYS` is five; `capital_gains` and `wealth` extend the three tables
`economy_constants.gd` already had, because a fourth and fifth tax is the **same machine
with more entries**. `src/sim/tax.gd` holds only what the session genuinely invented:
progressivity, and what the player's tax policy does to the Gini. It is **stateless** --
no `tick_month()`, nothing written on `NationState`, nothing in the save -- pinned by
`tests/test_tax.gd` reading the file and by `tests/test_save_load.gd` asserting three
absences.

**Step 0 inverted its own prediction.** V1.6c found the World Bank government-finance
branch too thin, so this session was told to check `GC.TAX.*` before planning a measured
base share. It covers **10 of 10** nations, 30-35 rows each -- coverage was never the
problem. What rules it out is that `GC.*` is **central government** (France 22.78 % of
GDP against the 46.1 its file carries, Switzerland 9.45 against 27.8), which
`docs/data-sources.md` rejected at S1, and that `GC.TAX.YPKG.*` puts income, profits
**and capital gains** in one bucket -- precisely the split the session exists to create.
No property series at all. Both base shares are authored, like the three already there,
and the fetch **confirmed a standing rejection rather than discovering one**.

**Instance thirty-two: the wealth tax is not on the other four's rate scale.** Its base is
a **stock** at 4.00x GDP against income's 0.50 flow, so one point of wealth rate is eight
points of income tax in revenue. `TAX_SCALE_PP` was shared by every key in points of rate
and became **per-key**; `Budget._erosion()` returned a flat 1.0 when a nation's own start
was zero, so revenue was **linear in the rate forever** -- correct for a tax nobody has
and a live exploit the moment a player invents one, which this content makes reachable on
frame 1 (Switzerland taxes no private capital gain, eight of ten have no wealth tax). The
zero reference had to be **per key** as well: one shared value put an invented
capital-gains tax's revenue peak at three points against real rates of twenty-five. One
constant cannot serve two rate scales, found twice in one session.

**Instance thirty-three: the row asks the `ISSUE_KEYS` question without noticing** -- its
"visibly different bloc-weight profile" criterion IS V1.3d's collinearity test restated.
Answered **YES twice at once**, a first, at **-0.739 %** on the S10 ratio, the *unsafe*
direction, against V1.3d's accepted +0.39 % and V1.4c's refused -1.46 %. Paid because the
alternative is **no price at all**: `opinion.gd` writes a satisfaction for every
`TAX_KEYS` entry, so a tax with no key is a number nothing weighs and the wealth lever
collects 4.2 points of GDP free. The first rows drifted **-1.640 %** and **the fix was
content** -- the flat-weight control drifts only -0.106 %, so the cause is the profile,
and the first rows gave two taxes eight of ten barely levy twice `tax_corporate`'s share
of the agenda.

**Instance thirty-four: V1.5c's tripwire did not fire and could never have.** It mutates
the corporate rate, every `state_share` and every `regulation_burden` and demands the Gini
be bit-identical -- but **those three are the three section 6 does not own**, whose
instruments are brackets, capital gains and wealth. It was armed against the instruments
the model already had rather than the ones that were coming. The old assertion is kept and
the real tripwire added beside it.

**Brackets are a factor on the income LINE, and the first version failed as zero rather
than as a wrong number.** Putting it on the erosion coefficient multiplies `(rate - ref)`,
which is exactly zero for a player who steepens the schedule and leaves the headline rate
alone -- the whole price vanishing for the budget the lever exists to express. The sign
was then also backwards. Both caught by `tests/test_tax.gd`, not by reading. The Gini
discharge needs **no second field** where the decomposition asked for one:
`Tax.gini_policy_offset()` is a pure read over the schedule and two rates the save already
carries, so `Demography.tick_month()` stays the single writer.

**Two constants banded, three fitted, and one band found unable to select.**
`PROGRESSIVITY_BASE_BETA` = 0.15, the midpoint of a **closed-form** interval no grid can
move. The three Gini betas are fitted to the widest measured roster drift over a term
(NLD, 2.085 points) and land on a **fixed point**. `TAX_SCALE_PP_BY_KEY`'s band could not
discriminate -- clause (i) passed at every candidate with the identical approval move
because the reachable move saturates the satisfaction at every scale, so it measured the
clamp, and clause (ii) reduces to a rearranged inequality -- and was replaced by a fit
against `TAX_SCALE_PP`'s own fraction of income's span. **The kill switch cleared** after
being isolated: the version that committed real budgets showed a *flatter* schedule making
the country calmer, because flattening narrows the deficit. **`GINI_POLICY_MAX_PT`'s first
value bound** at half the roster's Gini span and is the whole span instead. The escalation
trigger is **recorded rather than retuned**: the two new taxes alone move **77 %** of
`DEFICIT_SCALE_PP`'s span.

**The re-run is not bit-identical, the prediction said so, and the reason given was
wrong** -- recorded rather than corrected quietly. Not float ordering: the **salience
simplex**, renormalised by two new issue keys, reaching approval, then `hardship()`, then
the grievance, then V1.6c's yield. **Trend bit-identical in all 217 year-rows**, GDP,
growth and unemployment in 216, approval's worst move **0.90**, **one outcome change of
51**. **Three new regimes** (29 -> 32), needed because every existing regime sets three tax
keys and no schedule, so the session was structurally unreachable by all of them --
V1.3a's rule returning for the first time in this block. `SAVE_VERSION` is **22** on three
fields, two of which **grow a dictionary** rather than adding a key.

**The thirteenth screenshot pass found two bugs after V1.6c's clean sheet.** The sharper
is a defensive default: `Budget.snapshot()` never carried `gini_effective` at all, the
panel read it with `.get(key, 0.0)`, and the row printed a confident **0.00** against a
live 31.80 -- a default that hides a missing key is worse than a crash, and the row now
prints an em dash. The second is **a live bug recorded rather than fixed**:
`budget_panel.gd` refreshes from a `_pending` captured in `setup()`, so a budget committed
by anything but its own sliders leaves the panel stale and offering to undo it -- and
`Legislature.apply()` commits tax changes exactly that way. It needs a design call about a
player's half-finished edits, so `screenshot.gd --redistribute` re-syncs and
[docs/tax-model.md](docs/tax-model.md) §11 carries the bug. Model:
[docs/tax-model.md](docs/tax-model.md).

## V1.7

**V1.7 is decomposed into three sessions, V1.7a-c, and (a) is built.** The row was three
bullets against a block cell naming four items and neither count was right: (a) the
campaign phase, (b) campaign promises and the trust price, (c) electoral system choice
**and referendums**, which are one shape and not two -- an electoral system is a seventh
`effects.institutional` key and a referendum is the amendment machine's own
declared-unresolved `referendum_required`, so `electoral_systems.gd`'s five methods and
`INSTITUTIONAL_EFFECT_KEYS` are the whole machine and V1.6c's credit rating is the
precedent. **Machine count is two**, which is what makes it three sessions. **(b) is
recorded in advance as the row most likely to split**, on the trust quantity. No V1.7
session ships a U-track machine, recorded because two consecutive sessions split on that
rule.

## V1.7a

**V1.7a shipped the campaign phase, and the row was answered by a DELETION.** Of the
bullet's three nouns -- *time, money, messaging* -- only money survived contact with what
is built. **Time does not exist**: U6a swept a monthly budget of the player's days and
deleted it, on a reason that is general rather than about calendars (`available()` returns
what is **legal** and nothing models what the player **wants**, so any ceiling priced
against legality always binds). **Instance forty.** And **messaging is V1.5d's**, exactly
as the bullet itself predicted -- *"if V1.5d builds the peacetime half, this bullet reads
it rather than rebuilding it"* -- which is the first time a prediction written into a row
has come true and been collected. `tests/test_campaign.gd` reads `campaign.gd` and fails
if it so much as names `framing_gain` or `press_freedom`. **Instance forty-one** is in the
section rather than in a row: §7 has **no bullet for referendums** while §1's list, the
re-parked V1.1f row and `nation.gd`'s `KNOWN_AMENDMENT_RULES` comment all point here.

**The target had to be found, and two of three candidates were refused.**
`election_constants.BLOC_TURNOUT` is read in **exactly two places, both inside
`Elections.vote_share()`**, and nothing in this project had ever written it -- so a
per-bloc mobilisation register is a **first writer with no double count**. Approval was
refused because `vote_share()`'s own `pull` term already reads it and approval **is** the
term's record; framing was refused by V1.5d. And the distinction is the honest one rather
than a convenience: **a campaign does not change what people think of your record, it
changes who bothers to vote on it.**

**Mobilisation is a shift in LOG-ODDS, so turnout is bounded strictly inside (0, 1) BY
CONSTRUCTION** and `campaign_constants.gd` ships no turnout clamp at all -- V1.6a's
argument that a bound with no number to set wrong beats a clamp. The property nobody
authored falls out of it: the same effort moves **students +14.9 points** at the cap and
**pensioners +7.2**, because a low-turnout bloc has more room. **The window is a level
read and the clear is its other half**, so the register empties itself the month after the
vote with no hook in `elections.gd` and no flag anywhere. **An effort is a standing rate
with a deadline** -- it accrues and bills every month it runs, which is what kills the
strictly-dominated shape a one-off purchase creates (same reach, less time paying) for the
seventh time. `campaign_bill_pct_gdp` is the **sixth** computed spending line and the
**second that stops**, and it stops on a date the player cannot move, which is why its
decision is about **timing** where V1.6f's is about size.

**The probe corrected the session five times, eighteen sessions running, and the first is
about bands themselves.** Clause (i) was **invented** -- *"at least 0.50 points of vote
share"*, a number picked because it sounded like a margin -- and every candidate failed
against it while the table never said whether 0.50 was the right ruler. The only other
thing that moves `vote_share()` is **approval**, so the band is written in points of it:
at least what one point is worth (0.3415), at most what the **poll floor** is worth
(1.0147), because a swing smaller than the published polls can resolve is exactly the
swing a campaign may own. `_headroom()` was then wrong by a **factor of a hundred**; the
emulation claim was false above the shipped window; and the **content's targeting** was
the gap rather than any constant, at **17 %** of what perfect targeting reaches -- the
first ladder mobilised everybody and depressed nobody, and real campaigns demobilise. The
correction was to the content, V1.4b's discipline a second time.

**A binding guard rail can INVERT a decision rather than merely set a number**, which is
new. `MOBILISATION_MAX` at 0.60 was reached -- and once the accumulator saturates a
**longer** run-up is strictly worse, costing more months of bill for the same reach, so
the clamp was reversing the timing decision the whole lever exists to pose rather than
setting it. At 0.90 the worst reachable stack is 0.6800, slack by 0.2200.
`CAMPAIGN_WINDOW_MONTHS` = **8**, selected by **maximin slack** over the feasible region
-- this page's tiebreaker rules one step past V1.5d's *the interior governs*, because the
interior of a passing **list** is a statement about the grid and V1.5b's finding is that a
grid must never choose.

**And maximising your own vote share is not the same as winning.** The pair that best
raises France's incumbent's share (+0.4204) **narrows** their lead (-0.4033); the pair
that best widens the lead (+0.6475) **lowers** their share (-0.2417). `vote_share()`
renormalises per bloc, so turnout is a rising tide inside a bloc rather than a transfer
between parties, and the parties nearest you in ideology space are exactly the ones
sharing your voters. Recorded rather than fixed -- it is a property of the vote-share
model, not a defect in this one -- and it is why `balance_probe.gd`'s regime ranks efforts
on the **lead**, by a live score naming no effort and no nation.

**`SAVE_VERSION` stays 23 on three fields**, all reading as "no campaign" when absent,
which is the truth about every version-23 save; the test pins the absence so V1.7b has to
say why it moves. **The re-run is bit-identical across all 34 existing regimes, predicted
in advance** -- the diff is additions only -- with two new regimes of the expensive kind.
The eighteenth `ISSUE_KEYS` question is answered **NO on test 1**, as V1.6e's and V1.6f's
were: a session shipping a content object has somewhere to put the price. **The
seventeenth screenshot pass found two bugs**, one content and one the tool's: a stop action
authored as *"Clear the Diary"* -- right in English, and the name of a **window this game
already has** -- and the flag pinning the scroll to the bottom, which put the months-to-
the-vote and the campaign bill off the frame and opened on a sentence cut in half. V1.6e's
correction has a **direction** as well as a subject: scroll to where the flag's own claim
is. Model: [docs/campaign-model.md](docs/campaign-model.md).

There is **no diary row for the campaign**, and the refusal is a property rather than an
omission: `calendar.gd` may preload only its own constants, `tests/test_calendar.gd`
enforces it, and a "campaign opens" entry is a fixed offset from a date the strip already
carries. The window length lives in `campaign_constants.gd`, so the row would have cost
that property for a derived date.

## V1.7b

**V1.7b shipped campaign promises, and the row that was recorded in advance as the one
most likely to SPLIT did not.** The pre-registered trigger was the trust quantity — *if
the price cannot land on an existing register the way V1.5d landed legitimacy on the
grievance, then the ledger and the price are two sessions* — and what discharged it is
**V1.5d's own criterion applied in the other direction**. Legitimacy went to the grievance
because it is willingness to accept your rule **outside** the ballot box; trust in a
promise is squarely **at** it, so the price belongs on the register that reaches the
ballot box. That is `ns.bloc_offset`, which V1.7a §6 had already made a campaign's own
lasting mark. A separate trust stock would have been §5's *second approval number with a
different label*. The landing site was measured **before a line of content existed** —
one machine, no split, **no new quantity anywhere**.

**Instance forty-two is the row's own "read at the END of the term", and it fails on two
things that can be COUNTED.** A single read there is strictly dominated by last-minute
compliance — run unemployment at nine for four years, squeeze it to 6.9 for the final
month, pay nothing, the shape this project has killed eight times. And it is
**structurally invisible at the vote it is about**: `main.gd` runs `Opinion.tick_month()`
long before `Elections.tick_month()`, so a `bloc_offset` written at term end reaches
approval *next* month, and even moved ahead of Opinion `INERTIA_RATE` delivers a quarter
of it. So a promise is judged on a **level every month it is live** and the price is the
integral — V1.7a's *a standing rate with a deadline* applied to the **price** rather than
to the spend. Graded-by-the-miss was designed and cut (a per-field normaliser is a table
with no measurement behind it); **breach is binary per month and the count IS the
memory**, V1.3e's *no grievance ledger* in a new place.

**`PRECONDITION_FIELDS` is the right shape and the wrong list, and the interesting half is
what a pledge list has that it does not.** Three of its seven entries cannot be promised —
`overall_approval_pct` is circular, `terms_served` is not a state of the country, and
`unrest_pct` ships a `>=`-only invariant a `<=`-shaped promise inverts. What is added is
the taxes and spending lines the **player sets**, and the division is measured rather than
thematic: table (c0) reads each field's **LUCK** (the widest span within one budget)
against its **CHOICE** (the span across three at the end). `growth_annual_pct` comes back
**8.215 against 0.641** where every tax and spending row measures luck **exactly 0.000**.
An outcome pledge is a **bet on the world** and V1.6a's cycle is what makes it one; a rate
pledge is a **self-imposed constraint**. `inflation_pct` was on the list and the probe
**deleted** it — 0.114 and 0.045, both under the resolution of the model that produces
them, so an authored threshold is a constant verdict.

**`pledges_constants.gd` ships NO TUNED CONSTANT AT ALL**, `projects_constants.gd`'s
position reached a second time, and `effects.pledge` carries **no `op`** where all five
channels before it do. Five directories ship a start and a stop because an obligation only
the clock can close is a permanent monotone charge; it does not transfer, because a pledge
charges only while it stands **broken** — it stops the month the player comes back into
compliance, and **the off switch is called governing**. A `renounce` op priced below the
accrual would be strictly better than complying and priced above it would never be used.
`PLEDGE_OPS` is two comparators of five, and the three refusals are the design.

**The probe corrected the session five times, nineteen sessions running, and two of the
five were corrections to the CHECK rather than to the model.** The reachability table
measured the wrong state — `_tick()` omits `Elections`, so 168 months reported **one**
run-up and **zero** judgements against a real three and two, which would have read as *the
verb is unreachable and the row should split*; V1.3f's error a fourth time, inside a file
whose header warns about it. The growth pledge failed its readability band and the
**content** moved. **The dominance test itself was the wrong test**: it compared the
authored (reward, breach) pair and reported five dominated promises, and every one is an
artefact, because the third quantity — *how often the promise is actually broken* — is
nowhere in the content and is a property of the budget the player intends to run. That is
V1.7a's *share is not winning* in a new place. **The ordering statistic was LUCK and had to
be EXPOSURE** (luck as a share of luck plus choice): the deficit reads 1.284 of luck
against unemployment's 1.182, eight per cent apart, and 16.445 of choice against 0.656 —
luck alone says the deficit is the less controllable and exposure says the opposite by a
factor of nine. And the balance regime pair was **confounded**, needing a third regime
running the identical budget switch and promising nothing.

**Zero promises are dominated in every column and each column has a different best
promise** — hold `managed` and the hospitals win, switch to austerity and the deficit rule
does, switch to spendthrift and the tax lock does. The ladder is not orderable without
knowing how the player intends to govern, which is what makes it a choice.

`SAVE_VERSION` stays **23**, V1.3c's device **answered and re-armed at V1.7c**: absent,
`pledges` reads as "nothing promised", true of every version-23 save because those games
had no pledge verb. It is serialised anyway and that half is not free — a verb writes it,
no tick recomputes it, and **the reward has already been paid**, so a save that dropped it
would hand the player the upside of every promise and delete the liability. The nineteenth
`ISSUE_KEYS` question is **NO on test 1**, a fourth consecutive session for the same
reason. **The re-run is bit-identical across all 36 existing regimes, predicted in
advance** — the diff is additions only — with three new regimes, and the legibility
evidence is exact: same budget, same promise, **26.2 % in 2027 against a control's 25.9**
and **10.6 % in 2032 against 11.1**, so the promise is worth **+0.3 at the election it is
made for and −0.5 at the election it is judged at**. Keeping it instead holds the office
at 27.0. **The eighteenth screenshot pass found two bugs, both the readout's**: a breach
cost printed in no unit two lines under a turnout figure of the identical shape, and a
live promise that never said what it had cost — the one figure the section exists to be a
ledger of. Model: [docs/pledge-model.md](docs/pledge-model.md).

## V1.7c

**V1.7c shipped the referendum and the electoral system, and the V1.7 block is
COMPLETE.** Two stopgaps discharged, both declared in advance and both pointing here by
name: `nation.gd`'s `KNOWN_AMENDMENT_RULES` carried `referendum_required` with
*"V1.1f/V1.7"* beside it, and `legislature_constants.AMENDMENT_RULE_FRACTIONS`
deliberately had no entry for it.

**Instance forty-three is that `effects.institutional` is legal ONLY on a
`constitutional` law.** [docs/tiers/v1.md](docs/tiers/v1.md) §7 asked for
electoral-system choice as "a seventh `effects.institutional` key", and `constitutional`
forces `majority: "amendment"` — so the row's own wording **entrenches the electoral
system at each nation's amendment threshold**. Electoral law is ordinary legislation in
essentially all ten: France's code électoral (changed by ordinary law in 1985 and again
in 1986), Germany's Bundeswahlgesetz (2023), Italy's Rosatellum, Britain's ordinary Act.
Right for GBR alone, and only because GBR's `amendment_rule` already **is**
`ordinary_law`. So `law.gd`'s whitelist **split**: `ORDINARY_INSTITUTIONAL_KEYS` holds
`election_system` and `election_threshold_pct`, the six entrenched keys still require
`constitutional: true`, and the error string names which rule was broken. V1.4a/V1.4b's
split written into the schema rather than only into the docs, one block later and in the
other direction. No template constrains either key and **none could** —
`constitutional_monarchy` alone covers `fptp`, `pr_dhondt` and `pr_national` — which is
`term_months`' precedent exactly.

**A referendum is a SECOND RATIFICATION STAGE, not a bypass, and every citation was
already in the data.** Art. 89 (FRA), Art. 138 (ITA), Art. 114 (LUX) and Art. 195 (CHE)
all put an ordinary chamber majority **first**, so the popular vote replaces the
*supermajority* and never the division — and all four were sitting in the nation files'
own `government.amendment._note`, authored at V1.2c for a mechanic that did not exist.
`government.amendment.referendum` (`none` / `optional` / `mandatory`) is the **seventh**
dispatch-on-a-data-string field, per-nation and not per-template for
`permits_system_change`'s reason. `referendum_required` gains an ordinary-majority seat
fraction — what makes it *mandatory* is the nation's own mode, not the table.

**THE POPULAR VOTE SHIPS NO TUNED CONSTANT.** It is `Elections.vote_share()` with two
options: YES at the law's own authored `position`, NO at the **size-weighted mean of
`BLOC_IDEAL`**, measured at **(−0.230, +0.084)** — derived from a table written at S5 for
unrelated reasons, V1.5d's mean anchor one block on. Affinity at the existing
`AFFINITY_SIGMA`, weights at `BLOC_SIZE × Campaign.turnout_of()`, and YES carrying the
incumbent's per-bloc pull on the existing `INCUMBENT_SWING`, so de Gaulle 1969 falls out
of the arithmetic. **Two properties nobody authored**: a referendum held inside V1.7a's
run-up reads the campaign's mobilisation for free, and one held outside it reads
`BLOC_TURNOUT` **bit-for-bit** — which is what let the layer go live with the harness
bit-identical. The plan-time hand-computation predicted 45.8 % yes on
`abolish_term_limits` and the live measurement came back **0.458**.

**A KILL SWITCH THAT SWEEPS A RANGE THE PLAYER CANNOT REACH IS NOT A KILL SWITCH.** Table
R1 swept approval 30 to 65 and **cleared** — four of seven amendments winnable
"somewhere". Table R6 then measured what a French president actually holds under a budget
they can stay in office on: **40.0 to 50.3** over fourteen years, against a crossover at
~52. V1.3f's measuring-the-wrong-state error a **fifth** time, inside the probe written
to avoid it. The probe now measures the reachable range **first** and every approval band
is written inside it; the escalation declared in advance, `STATUS_QUO_PULL`, **fired and
was honoured** — 0.90, crossover 46.42, interior to both the passing set and the grid —
rather than `INCUMBENT_SWING` being raised, which is measured for the election.

**The verb was unreachable TWICE for two different reasons, and one fix was the model and
one was CONTENT.** Read as an absolute majority, route B's chamber bar put it at 270 of
the 289 seats it needed in **every one of 168 months**; Art. 89's first stage is the
ordinary legislative procedure, a majority of votes **cast** (Italy's Art. 138 is the
outlier, recorded rather than modelled per nation). Then France's only amendment,
`abolish_term_limits`, is rejected **270–307** by its own assembly. A position sweep over
the ideology grid found a real window — economic −0.4…−0.2, social −0.1…0.0, yes-seat
fraction **0.534–0.551**, above an ordinary majority and below 3/5 — and **that window is
the referendum**. `single_term_reform` is authored into it, the Jospin commission's
*mandat unique*. V1.4b's discipline: the fix that is also true is the better fix. The
probe's own player also had to be corrected — the first version called one every legal
month, lost **24 of 25** and drove its own approval down; a *rational* player calls one
only when already over the bar.

**Withdrawing costs exactly what losing costs, and that is a PROOF rather than a second
constant.** Same offset, same cooldown, so holding the vote **weakly dominates**
withdrawing by construction: identical outcomes except that holding it might carry. Below
a loss it is the free-hedge shape this project has killed ten times; above it needs a
number solved against the first, which `investment_action.gd` refuses as one strength
written twice. What withdrawal buys is the register slot back now.

**No new tick anywhere, and that is deliberate rather than convenient.**
`Legislature.tick_month()` already existed and is already called by `main.gd`,
`balance_probe.gd`, `test_balance.gd` and eight probes, so the countdown and the
settlement go there beside the cooldown tick — `diplomacy.gd`'s `_tick_agenda()`
precedent, and V1.6a's argument taken deliberately so V1.5d's bug is structurally
impossible rather than remembered. Its signature widens to `tick_month(state, loader)`,
**required and not defaulted**, on the reason `legislature.gd` already gives about
`apply()`'s own loader; `tests/test_referendum.gd` reads **both** harnesses and fails if
either omits it. `src/sim/referendum.gd` is a **leaf** — `resolve_due()` returns the
verdict as data and `legislature.gd` applies the law, U6a's `Calendar.due()` one block on
— and the test reads the source to say so.

**`SAVE_VERSION` is 25, on three fields of four, and they fail the rule by three
DIFFERENT failures.** `election_system`/`election_threshold_pct` are the sharpest case
since `military_capability`: absent they read `""` and `0.0`, `ElectoralSystems.allocate()`
falls through its match and **every seat allocation collapses to zero**, and
`from_dict()` never sees the loader (V1.6a's finding). `referendum_mode` earns it for
`eu_member`'s reason — absent it is a legal state for six of the ten and a silently
different constitution for France. `referendum_pending` earns it because an absent
register **deletes a vote the country has already been called to**, a free withdrawal of
the one act this session made un-free — `campaign_started`'s case one commit earlier. And
`last_referendum_result` is **not serialised at all**, `last_project_result`'s case, with
the absence pinned.

**Germany gets nothing, and the decomposition expected otherwise.** The ROADMAP argued
referendums belong here because *"a referendum exists precisely because a supermajority
is sometimes unreachable, and this block measured exactly that for Germany"* — and
**Art. 79 provides no referendum at any stage of a Basic Law amendment**. True in the
abstract, and it does not resolve for the nation it was named about: Germany's mode is
`none`, its `two_thirds` is unchanged, and `restore_the_monarchy` stays unpassable
content. Recorded rather than fixed. Model:
[docs/referendum-model.md](docs/referendum-model.md).

**The re-run is bit-identical in every printed FIGURE across all 38 shared regimes,
predicted in advance, and the one line that moved names a LAW rather than a number.**
`managed_books_ahead` books "the first proposable law" and the new amendment sits first
in `data/laws/amendments.json`, so the diary row reads `Single-Term Presidency Act` where
it read `Term Limits Abolition Amendment` — a content-ordering artefact, and a latent
fragility in that regime worth naming rather than fixing here. Two new regimes, both the
**expensive kind**: a referendum and an electoral-reform Act are verbs no budget regime
issues.

**The legibility evidence is exact and it costs a term.** Same budget, `managed` against
`managed_calls_a_referendum`: GDP, growth, trend, unemployment, debt and deficit are
**identical to the digit** in every year the two share (2032: 3084, +1.27, +1.31, 7.67,
125.2, −2.86), and approval is **56.7 against 49.3** with the worst bloc at rural 52
against rural 45. The referendum carried, the mandate is worth **+7.4 points**, and the
president is **out of office in 2032** — termed out by the very amendment they won,
where `managed` holds a second term at 26.7 %. The electoral half is visible in the
assembly rather than in the figures: after June 2029, `managed_reforms_the_ballot`
governs on **326 of 577** where `managed` has **377**, because the power law's
amplification of the largest party is gone. "Producing visibly different assemblies" is
the row's own phrase, measured.

**The nineteenth screenshot pass found one bug and it was the readout's**: the session
made `election_system` live state and left **no surface saying which one is live**, so a
player who passed the Proportional Representation Act could not read that it had taken
effect until the next legislative election three years later. A lever whose only feedback
is a three-year wait has no readout at all. `government_panel.gd` now names the method
and its threshold beside the amendment rule, and unlike the referendum line it is
**never silent** — an absent referendum route is a fact most constitutions simply do not
have, where every assembly in the world is elected somehow.

**A test fixture predated the new field for the third time on this project's record** —
`tests/fixtures/nation_bad_formation_method.json` failed `Nation.from_dict()` before
reaching the template check it exists for, which is V1.5b's and V1.5c's fixture failure
repeating. `--referendum` and `--electoral` are the twenty-second and twenty-third
screenshot flags, and they want **opposite treatment**: the pending block is the first
thing on the law panel, and an electoral reform is invisible until the next legislative
election, forty-one months out.

`--pledge` is the twenty-first screenshot flag and it wants the **opposite end of the
scroll from `--campaign`**, which is the same panel: the ledger is at the top and the
promises are at the bottom, so V1.6e's correction now has a *direction* per flag rather
than per panel. And `tests/test_pledges.gd` reads **`tools/balance_probe.gd` and
`tests/test_balance.gd`** and fails if either does not name `Pledges.tick_month` — V1.5d
shipped with neither harness calling `Media.tick_month()`, so both ran the pre-session
model and their agreement about a bit-identical re-run was about nothing. A bit-identical
re-run is the reassuring outcome, which is exactly why that check is a test and not a
habit.

## V1.1e

**V1.1e SHIPPED THE UPPER HOUSE AND THE JUDICIARY, AND THE V1 TIER IS COMPLETE.**
Nothing is left in it. The row said *Light / Sonnet 5 / Medium -- a second chamber is
the existing vote resolution run twice with different composition* and named **one of
the three things the session owns**: the block is upper house *and judiciary*, and the
judiciary half inherits section 5's rule-of-law statistic. **Twenty-fourth correction on
that table's record and the first about SCOPE rather than size.** ~40-45 surfaces, and
it did not split on V1.8's argument -- bill → assembly → second chamber → court is ONE
PIPELINE, and in France the two are connected, since Art. 61 lets sixty senators refer a
bill to the Conseil constitutionnel.

**The stopgap this session discharges was declared in the DATA rather than in the code,**
which is new. `data/nations/DEU.json` carried *"Only the Bundestag half is modelled --
there is no Bundesrat in this game"* from V1.2c; `FRA.json` cited Art. 89's "both
chambers" and Art. 12's "the presidents of both chambers"; and **`src/sim/referendum.gd`'s
own header, written one session earlier**, quotes Art. 89's first stage while modelling
only the second. Instances **fifty and fifty-one** are in section 1's own bullet list:
*Coalition formation* and *Confidence votes* were built at V1.1a and left unstruck for
four blocks, found by counting the section this session owns.

**NOT ONE of the ten upper houses is elected by the national electorate**, so a second
chamber is the **lower chamber, lagged**, and `Elections.vote_share()` is never called
with a different weighting. An ideological tilt was designed, measured and **deleted
twice**: a bloc anchor put the nationalist right at **267 of France's 348 senators**,
because every socially-traditional ideal in `BLOC_IDEAL` sits nearest
`nationalist_right`; and anchoring on the chamber's own centre made it refuse **zero** of
what the Assembly carried, because moderation concentrates a chamber where the laws are.
`UPPER_TILT` and `government.upper.electorate` were both cut by their own measurement.
**What makes it a check was already there and costs nothing** -- it votes at a reduced
whip where the Assembly votes at the full coalition bonus.

**THE FOURTH CORRECTION WAS CAUGHT BY A TEST, AND IT KILLED THE MODEL'S CENTRAL CLAIM.**
The design was that the second chamber votes on `spatial_support()` ALONE.
`tests/test_save_load.gd` reported *"no referendum was called, so the round trip measures
nothing"*: that chamber refuses **seven of seven** authored amendments -- France reads
`single_term_reform` 63-156 where the Assembly carries it 308-210 -- and under Art. 89's
`absolute` row every amendment in the game became unpassable, killing V1.7c's verb one
session after it shipped. **No whip at all is not `unwhipped`, it is `no government
exists`**: senators belong to the same parties as deputies, and what the second chamber
lacks is the THREAT. `UPPER_WHIP` = 0.40, passing [0.15, 0.65].

**The court's doctrine is PROPORTIONALITY and every denominator already existed**, so no
`unconstitutionality` field was authored -- a law's reach is the largest fraction of any
effect clamp it uses. The probe's first correction cut `bloc_offset` from that reading:
authored in hundredths against a clamp of 1.0, it dominated every other channel and made
`reach` numerically EQUAL to the largest bloc_offset, so **the court struck down whatever
was unpopular**. Budget levers are out on `legislature-model.md`'s own rule, and an
amendment is never reviewable because it becomes the standard the court applies. The cost
is measured: **ten of thirty-one ordinary laws reach exactly 0.000** and are structurally
unreviewable, `regional_devolution` among them.

**Rule of law is section 5's own statistic and the World Bank publishes it** -- the third
row in three blocks whose "cannot be derived" premise was about the model rather than the
world, after V1.5b's age structure and V1.5c's Gini. All ten nations, all ten years, no
gaps; ITA 67.6 to CHE 87.3, mean 80.38. Two things found by fetching rather than assuming:
the WGI were **re-coded**, so `RL.EST` now answers *"the indicator was not found"* and the
live code is `GOV_WGI_RL.SC` on `&source=3`, the first line in `data-sources.md` to carry
one; and the **score** (0-100) ships rather than the estimate, because every stock this
project keeps on a nation is already on that scale. The measured **slope** exists -- nine
of ten fall and only Italy rises -- and is deliberately NOT imported, because a court that
weakens every year on its own is V1.3g's permanent monotone charge.

**Three nations have no judicial review, by three different doctrines, and nothing
authored that**: Britain by parliamentary sovereignty, the Netherlands by Art. 120
Grondwet in terms, Switzerland by Art. 190's binding-force clause. **Britain's 78.8 is
computed and never read**, which IS parliamentary sovereignty. The linear tolerance form
died in the sweep -- it amplified the roster's spread until Germany could not legislate --
and the inverse form says something defensible instead: a court twice as independent
tolerates half as much, anchored on the roster's measured mean. `JUDICIAL_TOLERANCE` =
0.345, passing [0.323, 0.367] on a 0.001 grid, both edges the model's. The ten split into
**three tiers** out of a World Bank series and one dial.

**The whole judicial ladder was UNREACHABLE in all three playable nations** until its
content moved -- France refused every rung 92-370 -- because the first positions put
court-weakening Acts in the socially-traditional corner and all three start with a
liberal or centrist coalition. The fix is CONTENT and it is the fix that is also true:
rollback in Europe is sold on *democratic legitimacy*, which is majoritarian rather than
traditionalist. **Germany's own court strikes every rung of its own capture** and
Britain's assembly refuses them, both recorded as bounds. `JUDICIAL_UNREST_BETA` is set
as a **ratio** against `PRESS_UNREST_BETA` because its band could not select -- the
one-sided failure V1.5a-d each recorded, a fifth time.

**The hold is pure time and the probe found time is not a cost.** Twelve months moves the
worst bloc 2.39 points against a 3.0 poll floor, and the first candidate to clear it is
15 -- one month short of the whole first playable term. **A hold that only registers when
it consumes the term is a block with a countdown on it.** The escalation declared in
advance fired and was honoured by the response the plan named: the RELEASE carries a
price, through `Government.penalise_blocs()`, Article 49.3's own accumulator, so the
session adds a price and no channel. `UPPER_OVERRIDE_OFFSET` = 0.05, and the **career
bound** chose it -- V1.8's E1b in a new place, where 0.15 stacked thirteen releases to
1.95 against a clamp of 1.00. **Article 49.3 is the way PAST the second chamber** and not
past the court, which is a property nobody authored.

`SAVE_VERSION` is **27**, on eight added fields of ten, failing the rule **three different
ways** and asserted apart. **The re-run is bit-identical across all 45 shared regimes**
-- additions only -- and that is a CONSEQUENCE rather than a coincidence: every law regime
calls `Legislature.apply()`, which by design skips both gates, and `tests/test_judiciary.gd`
asserts it. Three new regimes, all the expensive kind, and the legibility evidence is
exact: same budget, the ladder passed in month 6, rule of law **73.8 → 64.8** (below
Italy's 67.6), grievance **11.87** against a quiet run's 8.79, and the president **LOSES
2027 at 23.5 %** where `managed` holds at 25.8. **Capturing the courts costs the office.**
Model: [docs/upper-house-model.md](docs/upper-house-model.md) and
[docs/judiciary-model.md](docs/judiciary-model.md).

## V1.8

**V1.8 shipped events, and THE V1 TIER IS COMPLETE.** One session, not decomposed --
the first block since V1.1 not to split -- because fire → pending → choose → apply is
**one pipeline**, which is V1.3d's rule, so V1.3e's split trigger answers no. ~36
surfaces against V1.7c's ~30. `src/sim/events.gd` is a scheduler, a register and a
verb; every consequence a choice carries lands on a register an earlier session owns and
is written by the one function that owns it.

**Section 8's own two bullets are tiered NOWHERE, and that is instance forty-four --
the largest gap between a section and its backing the count has found.** Every other V1
section's bullets trace to a `docs/brainstorm/mechanics-*.md` row tiered V1; these two
have no row at all, and every event-shaped mechanic that IS in those four tables is
**Someday** (Terrorism, Pandemics, Emergency powers, the housing market's "own crisis
generator"). The only V1-tiered mechanic §8 owns is the **Scandals** row §5 handed it at
V1.5d. That decided the design rather than decorating it: there is no crisis left to
author that is not already a machine here -- a strike is V1.5c, a downgrade V1.6c, a
foreign act V1.3f -- so **an event does not add a consequence the game did not have; it
adds an occasion on which the player must pick one, a menu, and a deadline.**

**"The event schema is the union of the channels §3-7 create" is right about the TIMING
and wrong about the SHAPE, which is instance forty-six.** Counted, there are ten
channels: four are pair state (`relations`, `agreement`, `measure`, `pact`) and four are
commitments in flight (`investment`, `project`, `campaign`, `pledge`), each with exactly
one writer that has an **actor or a bill** behind it -- and an event is neither. The
union is not writable. What is writable is the LAW channel, extracted at this session
into `Law.extract_shared_effects()` and `Legislature.apply_effects()` so a law and an
event choice cannot drift apart, and the timing argument survives whole on it:
`effects.society` grew from one term to four across V1.5a-d and the institutional
whitelist split at V1.7c, so a schema written at V1.5d would have carried a quarter of
this one. **`institutional` is refused BY NAME** -- it is "Emergency powers", tiered
Someday, and a key refused as an unrecognised typo is one a later session re-adds
(**instance forty-seven**).

**Instance forty-eight is the sharpest and forty-three prior instances missed it.**
*"Decree / executive order -- bypass the assembly on a narrow set of matters, at a
legitimacy cost"* is tiered **V1** in `mechanics-governance.md` and appears in **no row
of any tier doc**. A choice that moves `tax_rates_pct` or `spending_pct_gdp` with no
assembly division IS that mechanic: the narrow matters are what the content names and
the legitimacy cost is the choice's own `bloc_offset`. Discharged here and written into
§1 as well as §8. **Instance forty-nine is NOT this session's** -- the same sweep, the
last one the tier gets, found **Embassies** and **Foreign aid** tiered V1, in no row and
absent from `data/diplomatic-actions/`'s fourteen verbs. Recorded, not built.

**No randomness, and section 8's own "semi-random" is instance forty-five.** V1.6a hit
the identical collision in nearly identical words; the answer transfers whole. The
hazard is `Cycle.unit()` over (nation id, event id, absolute month) -- **preloaded, not
copied**, because cycle.gd's duplication of `poll_noise.gd` rests on a BOUNDARY argument
that does not transfer to a second file inside `src/sim/`, so there is exactly one
deterministic draw in the simulation and one outside it. A save reloaded on the month a
crisis arrived receives **the same crisis**.

**E1b IS WHERE THE SESSION TURNED, and it is `a bill is not a cost` one block on.**
`bloc_offset` is a permanent clamped accumulator whose every previous writer either
charges once for an act the player chose or charges while a condition holds and stops
when they fix it. An event is neither -- it recurs and its default charges with no
decision -- and the first authored ladder passed the per-decision band while **failing
the career bound by a factor of four**: ten defaults reached `BLOC_OFFSET_MAX`, and a
saturated clamp makes **every regime converge on the same floor**. `tests/test_balance.gd`
said so in the sharpest available words -- *managing the budget did not beat ignoring it
on approval: 38.4 managed vs 38.6 ignored*. The plan's **escalation trigger 4 fired and
was honoured by the response it named**: magnitudes down, clamp untouched. Worst
reachable career is now **0.423 of 1.00**, measured and slack.

**Both other bands were corrected by their own first runs.** E1's cadence clause passed
**every** candidate from 3 to 20 -- the one-sided failure V1.5a and V1.5b each recorded --
so `EVENT_COOLDOWN_MONTHS` took V1.5a's **two-part selector**, closed at the far end by
E1b's slack clause: passing [4, 20], failing 3 (saturating) and 24 (cadence), midpoint
**12**. V1.5b's refinement diagnostic fired on the way, moving the answer from 10 to 12
once the grid held every integer. And **E2's AXIS was wrong**: written on the headline
approval figure it failed five events of six and came back *negative* on the fiscal one,
because refusing to fix a deficit is the most popular thing a president can do. An event
moves a few blocs hard, so the band is the **widest per-bloc spread** -- V1.3g's rural
row, V1.5b's deleted term and V1.5c's workers row, a fourth time -- with both edges
measured (3.0 poll floor, 5.8 what V1.7b measured a full-term breach to cost). All six
pass at 3.31 to 5.15; **the headline fails for all six and is recorded rather than tuned
against.**

**E3's kill switch cleared at 0 dominated alternatives and 0 toothless defaults, after
its own RULE was corrected.** The first run reported five violations of which four are
the design -- an active choice dominating the **default** is the pressure, not a trap,
because a default is suffered rather than taken. Dominance counts between **alternatives
only**; the one real violation was fixed in the **content**. Two further corrections to
the test: a **tolerance**, because the first run decided a verdict on a ninth-decimal
difference and therefore stayed silent about two options identical in every readable
sense; and a **fourth axis, `corruption`**, admitted because it has an unambiguous better
direction where `press_freedom`, `settlement_stance` and `regulation_burden` have none --
without it `inquiry` dominated `dismiss` while leaving the state dirtier.

`SAVE_VERSION` is **26**, on three fields of four, and they fail the rule by **three
different failures** -- `event_pending` is `referendum_pending`'s free escape,
`event_fired` is `passed_law_ids` letting a settled `once` event charge twice, and
`event_quiet_months` is U6a's `diplo_months_to_act` reading 0 as *act now*. Asserted
apart, and `event_history` earns nothing and is serialised anyway. **What was not added
is pinned**: no stored hazard, no draw, no RNG state.

**The re-run is a re-baseline and E0c named the movers before it ran.** All 43 shared
regimes differ -- three hazard-only events have no precondition to fail -- but **30 of 43
keep GDP, growth, trend, unemployment, debt and deficit bit-identical**, and the 13 that
move are exactly the runs where a choice touched a budget line. Worst approval move
**5.80**, **one outcome change of 78**. `managed` is the cleanest row: 2032 identical to
the digit (3084, +1.27, +1.31, 7.67, 125.2, -2.86) against approval **49.3 → 48.6**.
**Two new regimes**, and the only thing that varies is whether the player opens the
window: same budget, same events, **same arrival months**, because the hazard is
deterministic -- V1.7b's confounded pair avoided rather than repeated. They were first
called `best` and `worst` **and the run refuted the names**: the soft run ends *below*
the hard one on approval AND the deficit, because the choices that buy the most approval
on the day are the ones that concede money. V1.7a's *share is not winning* in a new
place. Both still beat the control, which is the property the deadline needs.

**E0 corrected the plan before a line of content existed**, which is the whole case for
running it first: **`deficit_pct_gdp` is POSITIVE for a shortfall**
(`total_spending - total_revenue`), so `austerity` reads -9.41 because it runs a surplus
and `balance_probe.gd` negates it for display -- an event authored on the plan's sign
would have fired only on a **surplus**. Every threshold is written inside a measured
occupancy that **separates the regimes**: `deficit >= 5.5` holds 74 % of `hands_off` and
**0 %** of `managed`; `unemployment >= 7.5` holds 40 % and 43 %; `unrest >= 10.0` holds
9 % and **0 %**.

**`message_stack.gd` gets its FIRST EVER consumer of `card_activated`**, emitted since
U5a and connected to nothing -- so U5a's call 3 held to the letter: V1.8 added calls, not
a column. **Dispatches** is a non-modal window in the State cluster (a crisis you can
ignore and pay for is the whole of "time pressure"; a modal removes the choice by
removing the option of not making it), with the pending block at the top and the
**ledger** below. One diary row, `FIXED_EVENT`, and `calendar.gd` still preloads nothing.
**The subject is an OFFICE and never a person** -- U6b's rule verbatim -- and the frame
reads *"Cécile Aumont — Prime Minister"* with no content saying so.

**The screenshot pass earned its keep for the twentieth session running, with four bugs,
two of them the tool's.** `--event` announced the register directly and then ticked, so
`main.gd` -- which cards an event absent before the tick and present after it -- never
carded anything, and the frame showed an empty column beside a live crisis; it ticks
until one arrives now, affordable precisely because the hazard is deterministic.
`_mark_panels_dirty()` was missing **`_projects_panel` and `_campaign_panel`** as well as
this session's, so `--build` and `--campaign` had each been photographing a panel that
refreshed once on frame 1 -- V1.4a's failure a fourth time. The readout's two: the
deadline line rendered in **green**, the colour this interface uses for good news, and
the ledger named the button and not the consequence -- V1.7b's own *a live promise that
never said what it had cost*, fixed by deriving the choice's authored sentence from
content so the save-format assertion survives intact. Model:
[docs/events-model.md](docs/events-model.md).

MVP, **V1.1a-e**, V1.2a-e, V1.3a-g, V1.4a-c, V1.5a-d, V1.6a-f, V1.7a-c, V1.8, U1-U5, U6 (a, b and c), **V2.1a-c** and **V2.2 (a and b)** are done. **THE V1 TIER IS COMPLETE. Nothing is left in it, and V2 has started.** Sections 5, 6, 7 and 8 all closed, section 6's last clause and section 7's with them. (e) split and (f) split again on the same two-track rule, and **U6c built what they left** -- the map marker layer. V1.1e (upper house and
judiciary) is re-parked, not cancelled. One piece of V1.2 work is deferred with
somewhere to point now: V1.2c authored no amendment content for
`parliamentary_republic` because Germany's two-thirds bar was unreachable, and
V1.2e's `deu_grand_coalition` start makes it reachable.

Save format is at **version 39** (V4.4's bump, on six event registers -- `event_queue`, `event_category_quiet`, `event_cooldowns`, `event_armed`, `repealed_at` and `last_accession`; a seventh, `event_hook_fired`, was removed at pass 18 as dead state -- argued in `game_state.gd`'s `SAVE_VERSION` block; the V2.6b2-to-V2.8 history below stops at 31), and this line has now drifted THREE times -- the third was 31 standing through eight bumps until V4.4's pass-15 review found it. It said **28**
until V2.6b1 corrected it to 29, and it still said 29 until the V2.8 review found
`game_state.gd` at 31 -- so it missed V2.6b2's bump to 30 and V2.8's to 31, while both
of those sessions' own paragraphs below state their numbers correctly. That is precisely
the two-files-one-fact drift the Workflow section warns about, arriving inside a single
file instead of between two, and the second offence by the same sentence: a session that
reads this summary rather than the newest paragraph reasons from a stale save format.
**V2.8's three fields are `start_energy_mix`, `start_import_dependency_pct` and
`energy_kwh_per_capita`**, content-derived statics `from_dict()` cannot re-derive;
**V2.6b2's two are `campaign_sites` and `campaign_saturation`**. V2.6a's two fields are
`NationState.region_pop_share` and `.city_pop_share`: absent, every share reads 0.0, so
every city has a population of zero, no glyph at any zoom and an empty league table in
both panels. **V2.6b1 adds nothing and pins five absences** -- the site is arg-max over
those two registers, derived every read, so a stored site, region, concentration, output
index or per-region impulse would each be a second answer to a question the shares already
answer. Version 28 was V2.5's, on ONE field -- `NationState.region_gdp_eur_bn`,
V2.5's region level, and `military_capability`'s case at V1.3g in its strongest
form: national GDP is the sum of this dictionary now, so an absent register reads
0.0 and the definitional swap writes the country's GDP to zero on the first tick --
not a different model, no economy at all -- and re-seeding on load would erase
divergence the player watched happen, `service_quality`'s reason at V1.5a. V2.2b had
been the fourth session on this list whose serialised contribution was **nothing at
all** -- V1.6c's shape and V1.8's -- and V2.5 is the session that came here to argue
for the change, exactly as the pin below demanded. The geographic SHARES are still
content: a region's share of its nation and a city's share of its region
round-trip through `data/regions/` the way a firm's authored share and headcount
round-trip through `data/companies/`, and a firm's `city` is one more authored field in a
file the save has never carried. So `tests/test_save_load.gd` FLIPPED ONE ABSENCE AND
KEPT TWO: `region_gdp_eur_bn` must now be present (a save without it loads a nation
whose GDP is the sum of nothing), while a stored region share still means the
partition can drift from the content defining it and a stored city population still
means a head count exists that `share x population` does not already give -- and
there is still no regional unemployment stock to store, because `src/sim/regions.gd`
reads a regional rate as a pure function of the national one. There has never been a migration: a superseded
save is refused outright, because a half-understood political state is worse than
a clear refusal. The rule is not "a new field bumps" but "a missing field would
read as something wrong" — V1.2e added `GameState.scenario_id` **without** a bump
because an absent one reads as `""`, which is correct; V1.3a bumped because an
absent `relations` reads every pair as 0.0, which is the *worst possible*
relations rather than a neutral default. V1.3b is the sharpest case yet: neither
`agreements` nor the trade baselines earned it (one reads correctly as "nothing
signed", the other fails soft), and what did is `NationState.eu_member` and
`.neighbours` — absent, the trade weight silently collapses back to the aggregate
V1.3b replaced, so a reloaded game runs a *different model* from the one that
saved it. All three are checked in `tests/test_save_load.gd`, not argued in prose. **V1.3c
earned no bump and the test said so** — an absent `measures` reads as `{}`, which
is correct for every version-10 save because those games could not impose one —
and it left an assertion that the version was *still* 10 so a later session
raising it had to come and say why. **V1.3d is that session.** Three fields fail
the rule: an absent `bloc` register reads as a bloc with no rules, an absent
`bloc_base_transfer_pct_gdp` as a France that never paid into a budget it has
always paid into, and an absent `start_bloc_burden` as 0.0 against a live burden,
which mis-signs the `europe` issue for the rest of the run. **V1.3e adds no serialised field at
all**, and the test says why: both interest functions are pure reads over live
state, and the two things they write — `relations` and `measures` — were
serialised at V1.3a and V1.3c. That is a property rather than a coincidence, and
it is what *no grievance ledger* buys: the relations number **is** the memory, so
there is nothing for a save to carry. **V1.3g is the sharpest case on this list,
because one of its three fields falls on BOTH sides.** `military_capability` is the
bump: absent it reads 0.0 against a France that has spent 2 % of GDP on defence
since before the game started, the deployment cost divides by it so every
commitment jumps to the clamp, and `would_accept_pact()` reads the whole roster as
militarily worthless — a reloaded game running a *different model*, which is
`eu_member`/`neighbours` in its strongest form. `pacts` earns nothing, reading
correctly as "nothing signed" for every version-12 save. `deployments` **splits**:
the *obliged* half is re-derived on the next tick from `pacts` × `measures`, both
of which the save carries, and fails soft for one month the way
`trade_baseline_by_partner` does — while the *chosen* half is derivable from
nothing, so an absent register silently withdraws the player's own forces and drops
their bill with them. `tests/test_save_load.gd` asserts all four, and the split is
the assertion worth having rather than the bump: it **pins** the property that
obliged deployments are derived, so a later session making them stateful turns it
red and has to come and say why. **U6a adds one field and earns nothing, and what
it did NOT add is the interesting half**: `appointments` absent reads as "nothing
booked", correct for every version-13 save because those games could not book one
— `measures`' case exactly. `GameState.day` is not serialised at all, because
`save_manager.gd` already carries `clock.day` at the payload's top level and a
copy in `to_dict()` would be two records of one fact; the test asserts its
**absence**, which pins that property. And the field that *would* have earned a
bump — a spent-days counter, which reads 0 when absent and hands a save-scumming
player their month back — was never written, because the probe cut the currency it
counted first. **U6b bumps to 14 on a RE-KEY rather than a new
field, which is new on this list.** Nothing was added: `pm_name`,
`head_of_state_name` and `start_head_of_government_name` stopped holding names and
started holding person ids. The naive reading is that nothing is at risk, but a
version-13 save carries the *old* keys, so without the bump all three load as `""`
while the file looks intact and the game renders a government nobody governs —
`military_capability` at V1.3g and `eu_member`/`neighbours` at V1.3b, in their
strongest form yet. And U6b adds **no per-person serialised state at all**, because
a person is pure content; the one field that would have earned the bump on its own,
a stored `ns.cabinet_person`, was never written because the probe cut the bench
that needed it. **V1.4a bumps to 15 on one field of five, and the split is again
the assertion worth having.** `NationState.companies` is the bump: absent, every
firm reads as share 0.0, so the partition is not there, every firm produces
nothing, and a subsidy the save is still billing for through a serialised budget
line moves a share that does not exist — `military_capability` at V1.3g in its
strongest form. The bill and both deviation channels fail the rule cleanly, being
recomputed from the register on the first tick and reading 0.0 when absent, which
is correct for every version-14 save because those games could not subsidise
anybody. And the baseline is **content**: a firm's authored share and headcount
round-trip through `data/companies/`, so the test asserts a save carries no company
content and no register entry beyond `share` and `subsidy` — which pins that a
later session storing a baseline turns it red and has to say why. **V1.4b adds a
serialised field and earns NOTHING, and the test says so and then pins the number.**
`regulation_burden` absent reads as every burden 0.0, correct for every version-15
save because those games carried no `business` law — `measures`' case a third time.
It is serialised regardless, and that half is not free: a law writes it once and no
tick recomputes it, unlike V1.4a's three prices, so a save that dropped it would
silently repeal every rule the assembly ever passed. The test checks that premise
(dropping it moves `firm_impulse_pct`) rather than asserting it, then leaves V1.3c's
device in place — *the version is still 15* — so V1.4c's ownership register has to
come and say why it bumps. **V1.4c came and said it does not, which is not what the
row expected.** `state_share` absent reads 0.0 — the state owns nothing — correct for
every version-15 save because those games had no ownership verb;
`dividend_revenue_pct_gdp` is recomputed on the first tick; and the purchase and the
windfall were **never a field**, because they are in `debt_eur_bn`, serialised since
the MVP. A capital transaction needing its own save entry would have been the sign it
should not have been a balance-sheet write, and the test checks that premise rather
than asserting it. The only thing that *would* have bumped it is a
`start_state_ownership` baseline for a thirteenth issue — `start_bloc_burden` at
V1.3d exactly — and the `ISSUE_KEYS` answer was no, so the device points at the next
session a third time. What V1.4c *did* turn red on purpose is V1.4a's **other**
assertion: a serialised register entry now carries three keys rather than two,
widened by exactly one, and a fourth still fails. **V1.5a is the session V1.4c's device
pointed at, and it bumps to 16 on one field of three.** `service_quality` earns it, and
it is `military_capability`'s case in its strongest form yet: absent it reads 0.0
against a France that has funded hospitals for decades, *and* equilibrium-init does not
rescue it, because re-deriving on load would erase an accumulated decline the player
spent a term earning. `corruption` earns nothing (`regulation_burden`'s case a fourth
time) and `start_service_quality` earns nothing either (recomputed at init from
authored spending, so it round-trips through `data/nations/` — a firm's authored share
at V1.4a). Both are serialised regardless and for two *different* reasons, which the
test states separately rather than folding together. The assertion worth having is
again the split: the test checks that `service_quality` does **not** come back on one
tick, which is exactly what separates it from V1.4a's and V1.4c's four derived prices,
so a later session making the stock derivable turns it red and has to say why. **V1.5b
bumps to 17, earns it TWICE, and the second half adds no field at all — which is new on
this list.** `young_share` and `old_share` are the ordinary half: absent they read 0.0,
which is not a neutral default but a *different model* (working share 1.0, dependency
ratio 0.0, labour force the whole population), and init-from-content does not rescue them
for `service_quality`'s reason. The sharp half is **`service_quality["pensions"]`**, a key
added to a dictionary that was already serialised: a version-16 save carries
`{"health": …}` and no `pensions` entry, `_tick_nation()` reads `.get(key, 0.0)` so the
stock starts at zero, and `quality_deviation()` measures it against a
`start_service_quality` that is also absent — so the deviation reads as a large and
growing **positive**, a France whose pension system has just been invented and is
improving fast. A windfall the player did not earn, mis-signed for the rest of the run.
The two references, the four content fields and `migration_stance` all earn nothing and
are serialised anyway for the reasons already on this list. `tests/test_save_load.gd`
asserts the two halves **separately**, and that split is the assertion worth having: it
pins that **growing a registry dictionary can earn a bump**, which nothing here had said
out loud and which V1.5c and V1.5d will each be tempted to do. **V1.5c is that session, and it bumps to 18 on TWO fields, which is a first on this
list.** `unrest_pct` is `service_quality`'s case -- absent it reads 0.0, a perfectly calm
France, so a save reloaded mid-crisis silently ends the crisis, and re-deriving on load
cannot rescue it because the accumulation IS the state. `unrest_cooldown_months` is U6a's
`diplo_months_to_act` -- absent it reads 0, 0 means *act now*, and a reloaded save fires a
strike in its first month whatever the player was doing. They fail the rule by DIFFERENT
failures, one erasing accumulated state and one resetting a schedule to now, so
`tests/test_save_load.gd` asserts them separately rather than together; a single combined
check would let either half be quietly wrong. `gini_index` would have earned it a third
time on `young_share`'s reasoning and is folded into the same bump. `start_gini_index` and
`gini_index_per_yr` are content and round-trip through `data/nations/`;
`settlement_stance` is `migration_stance`'s case exactly; `unrest_impulse_pct` and
`unrest_opinion_load` are both recomputed on the next tick and fail soft for one month;
`unrest_acts` is a display record. And the test pins one ABSENCE as well: the inequality
read has no serialised field at all, because it is a subtraction over content and a drift
Demography already carries -- so a later session storing an index turns it red and has to
come and say why.

**V1.6c bumps to 21 on ONE field, and it is the smallest addition on this list ever to earn one** -- `start_debt_to_gdp_pct`, a single float with no register behind it. Absent it reads 0.0 against a live ~140, so `src/sim/credit.gd`'s debt gap reads the whole stock as newly borrowed: the yield comes back at **4.1 against a kept 2.4**, a France paying seventy per cent more interest for the rest of the run because it saved. `cycle_amplitude_rel` at V1.6a and `military_capability` at V1.3g. Re-deriving on load does not rescue it, which is what separates it from every derived price on this list: the live ratio has moved, so re-anchoring on it would silently forgive every point of debt the player added. **What was NOT added is the half worth pinning** -- no stored yield, no stored spread, no stored rating, because the module is a pure read over a debt stock serialised since the MVP and a grievance serialised at V1.5c. `tests/test_save_load.gd` asserts those three absences, so a later session making the module stateful turns it red and has to come and say why -- **the decomposition's split trigger, pinned in the save format rather than only in the docs**. The first draft of that check said an absent field puts the yield *on the clamp*; it does not, it puts it at 4.1, and the check is written against the measured number instead.

**V1.8 bumps to 26 on THREE fields of four, and they fail the rule by THREE DIFFERENT failures**, which is why `tests/test_save_load.gd` asserts them apart -- the pattern V1.5c set and V1.6b extended, because a combined check lets any one of them be quietly wrong while the other two carry it. `event_pending` is `referendum_pending`'s case exactly: absent, a crisis the country is already facing VANISHES, which is a free escape from the one act this session deliberately made un-escapable -- a player cannot decline an event, only answer it or be answered for. `event_fired` is `passed_law_ids`': absent, a resolved `once` event happens a second time and the player pays its price twice for something already settled, which is also why `once` is marked at ANNOUNCEMENT rather than at resolution. `event_quiet_months` is U6a's `diplo_months_to_act`: absent it reads 0, and 0 means *may fire now*. `event_history` earns nothing -- a display record nothing in `src/sim/` reads back, `unrest_acts`' case -- and is serialised anyway, because the ledger is half of what the Dispatches window exists to be and a session-only ledger is one the player loses by saving. **What was NOT added is the half worth pinning**, and it is V1.6c's shape a second time: no stored hazard, no stored draw and no RNG state, because `Events.hazard_passes()` is a pure function of (nation id, event id, absolute month) -- which is what makes a save reloaded on the month a crisis arrived receive the SAME crisis. The test asserts those absences, so the day a session gives an event's arrival an accumulator it turns red and has to come and say why.

**V1.6a bumps to 19 on one field of two, and the session's plan predicted no bump at all.** Its reason was true about the wrong thing: `src/sim/cycle.gd` is genuinely stateless -- no accumulator, no `tick_month()`, nothing to save -- but `NationState.from_dict()` rebuilds from the dictionary ALONE and never sees the loader, so every content-derived static fact on that class is already serialised (`eu_member`, `neighbours`, `pop_growth_pct`, `gini_index_per_yr`). **Statelessness is a property of the module, not of the save file.** `cycle_amplitude_rel` is the bump: absent it reads the default 1.0, every nation runs the roster-average cycle instead of its own -- France 45 % louder than its content says -- and the reloaded game runs a *different model* from the one that saved it, which is `eu_member` at V1.3b and `military_capability` at V1.3g. `cycle_impulse_pct` earns nothing: absent it reads 0.0 and `Economy.tick_month()` overwrites it from the clock on the next tick, `coercion_impulse_pct`'s case. The test asserts both halves and then pins what was NOT added -- no stored phase, no month counter, no accumulated wave -- so a later session making the module stateful turns it red and has to come and say why.

