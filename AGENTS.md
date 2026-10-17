# Nation Simulator

Single-player geopolitics and nation-management game. You are the President of
France: budget, laws, an assembly that need not agree with you, and an election
at the end of the term. Ten European nations, 2D map, dense UI panels.

Design vault is `docs/` — open **the project root** as the Obsidian vault, not
`docs/` (the vault config `.obsidian/` lives at the root). Start at
[docs/index.md](docs/index.md).

## Stack

- **Godot 4.7.1-stable**, non-Mono. Pinned in `project.godot` (`config/features="4.7"`).
  Bump deliberately and re-run the tests before committing the bump.
- **GDScript with static typing** (`var gdp: float`). C# stays available as an
  escape hatch for a hot loop a profiler actually found — not preemptively.
- No database and no autoloads in the game code. Third-party addons are
  editor-side and gitignored by default; `src/` may reference an addon file
  **only if that file is committed** — see `.gitignore`. The `.obsidian/` vault
  is the second stated exception (documentation surface, not game code — `src/`
  reads nothing in it). JSON content, JSON saves.

## Commands

```bash
bash tools/run_tests.sh
```

The human entry: the registry and the unregistered-test check stay here;
execution delegates to `python tools/suite_runner.py` (python is a gate
dependency — `tools/import_data.py` already made it one). `-j1` is
sequential, `--verbose` restores the print-everything stream.

```bash
python tools/suite_runner.py --ci
```

THE AGENT GATE — same core, exit code + `reports/suite_runs/<ts>/`
(JSON + per-test logs). Run tests this way, not by hand-rolling godot
invocations. Single or subset runs: append test paths —
`python tools/suite_runner.py --ci tests/test_clock.gd tests/test_data.gd`.

```bash
bash tools/run_tests_gui.sh
```

The cockpit: per-test results, durations, filters, re-run, live attach.

```bash
bash tools/check_names.sh
```

```bash
bash tools/check_mcp.sh
```

```bash
python tools/check_vault.py
```

The vault check: unresolved wikilinks, docs the index does not reach, orphans, missing
frontmatter -- over tracked files only. What each Obsidian plugin is for: [docs/vault.md](docs/vault.md).

```bash
reuse lint
```

The licence check (`pip install reuse`): every tracked file needs a licence, declared
in `REUSE.toml` — a new asset, a new data source or a third-party file needs an
annotation there. The layers are listed in [README.md](README.md); CI runs it.

```bash
godot --path .
```

`tools/` is dev-only and never ships.

## Architecture — three rules, from [docs/engine-decision.md](docs/engine-decision.md)

1. **Content lives in data, not code.** There is never an `if nation_id == "FRA"`
   anywhere. A nation that behaves differently has a field saying so, read by a
   general rule. Adding a law or a party is a `data/` edit.
2. **One-way dependencies: `data → sim → ui`.** `src/sim/` never knows the UI
   exists — no `get_node()`, no signals into scenes. The UI reads `GameState` and
   never writes it; player intent goes back as an explicit command
   (`Budget.commit()` is the model). The test of this rule is that a full
   ten-year run works headless with no scene tree.
3. **One system, one module, one clear job.** A narrow public surface, usually a
   `tick_month()` and a few queries. Systems talk through `GameState`, never to
   each other. A file past a few hundred lines is doing two jobs — split it then.

Deliberately absent: DI container, event bus, abstract base classes for a single
implementation, plugin architecture.

```
data/     static content, read once at startup, never mutated
          (nations, parties, laws, political-systems, scenarios, geo, regions)
src/core/ game state, clock, save/load, data loader, value types
src/sim/  one file per system, no UI knowledge
src/ui/   scenes and panels, read-only over sim state
tools/    import scripts and checks, not shipped
tests/    headless
```

## Style

- Panels are built in code in `_ready()`, not in `.tscn` files. Two scenes exist:
  `src/ui/menu.tscn` (entry point) and `src/ui/main.tscn` (the game).
- Comments explain **why**, not what — a rejected alternative, a non-obvious
  invariant, the reason a number is that number. Match the existing density.
- Tuning constants live in `src/sim/*_constants.gd`, not inline.
- New simulation behaviour needs a headless test. New UI behaviour that can fail
  silently needs one too — most U1 bugs this session were silent.

## Gotchas

Both confirmed on 4.7.1 and written up in [docs/engine-decision.md](docs/engine-decision.md):

- **A class cannot reference its own `class_name` on first run**, before
  `.godot/global_script_class_cache.cfg` exists. Use bare `new()` for
  self-instantiation; use `const Foo = preload(...)` for cross-file references.
- **A `Control` outside the scene tree is half-dead.** `_ready()` has not run, so
  everything it builds is `null`, and `Range.value_changed` does not emit.
  Configure a panel *after* `add_child()`, and drive UI tests a frame at a time
  with `extends SceneTree` + `func _process(delta) -> bool`.
- **A new `.gd` gets no `.uid` until something imports it.** `--headless
  --script` runs the file without generating one, so a session that only runs
  the tests commits scripts whose siblings all have a `.uid` and whose own is
  missing — U5b did, and paid for it with a follow-up commit. Run `godot --path
  "<repo>" --headless --import` once before `git add`, and check that every new
  script has its pair.

- **`project.godot` is ALWAYS dirty in the working copy, and it is never yours.**
  The Godot editor rewrites it on every open with whatever addons are installed on
  that machine, so `git status` shows `M project.godot` in every session. Do not
  stage it — commit `a1bf146` already paid for that once. What it currently adds,
  written down so no session has to re-derive it:

  ```
  [autoload]
  MCPRuntimeServer="*res://addons/godot_mcp_toolkit/runtime/mcp_runtime_server.gd"
  DialogueManager="*uid://c3rodes2l3gxb"

  [editor_plugins]
  enabled=PackedStringArray("at-icons", "dialogue_manager", "godot_mcp_toolkit",
                            "materialLayers", "road-generator")
  ```

  `godot_mcp_toolkit` is the one this project already uses — it is what
  `runtime_screenshot` and `input_simulate` reach a running game through. **The other
  four are parked on purpose, not junk** — `at-icons` is half adopted (V2.3 committed
  the icons `src/` names) and `materialLayers` and `road-generator` are each installed
  ahead of a planned use, so do not strip any of them on the reasoning that nothing in
  `src/` reads them yet. **`road-generator`'s planned use is now spent and it was not
  this one**: V3.4 drew the road layer and did NOT reach for the addon, because it
  generates 3D road meshes along splines and `map_view.gd` is a 2D plate-carrée
  `_draw()` over lon/lat. The reasoning is in
  [docs/data-sources.md](docs/data-sources.md)'s `road-generator` callout — read it
  before the name tempts a future session to re-open the question. It is still parked
  rather than stripped; what changed is that nothing on any tier is now waiting for
  it. **`dialogue_manager` is no longer parked: V2.4b adopted it**,
  and it is the project's STATED EXCEPTION to the no-autoloads rule — taken knowingly
  at plan time, gated on a headless smoke test (it must init under
  `--headless --script`, which is what `tools/run_tests.sh` is), committed whole into
  `addons/` (790 KB, MIT), with `DialogueManager` carried in the COMMITTED
  `project.godot` and the reason recorded in `.gitignore` beside the exception. The
  committed `[autoload]` names ONLY DialogueManager: the per-machine
  `MCPRuntimeServer` line had crept into HEAD and was cleaned out at V2.4b — a fresh
  clone gets the game's autoload, not the dev bridge's. The local file carries both
  and stays per-machine dirty, exactly as this section documents.

  **IT CREPT BACK, AND THE V2.8 REVIEW PROVED THE COST BY CLONING.** Commit `6818604`
  ("WIP: epitaxy pre-switch from v2.4") put `MCPRuntimeServer` back into the committed
  `[autoload]` and narrowed `[editor_plugins]` to `godot_mcp_toolkit` alone — and that
  addon has ZERO tracked files. A fresh clone therefore autoloaded a script that does
  not exist and `tools/run_tests.sh` FAILED on it: 604 error lines, ending
  `FAIL tests/test_map_cities.gd`. The tell was that `git status` came back CLEAN —
  once the per-machine lines are the committed lines, the "always dirty" signal this
  section relies on to catch exactly this is gone. **So `git status` being clean here
  is itself the alarm, not the all-clear.** Both lines are corrected; the editor will
  re-add them on the next open, which is the dirt this section already describes and
  which must stay OUT of a commit.

  A second half was found the same way, and it is AGENTS.md's first gotcha reaching
  the suite: with no `.godot/`, there is no `global_script_class_cache.cfg`, so
  dialogue_manager's own `class_name` types (`DMExpressionParser`, `DMCompilation`,
  `DMWaiter`) are unresolvable and **DialogueManager itself fails to parse on a cold
  clone**. V2.4b's step-0 adoption gate — *"it must init under `--headless --script`,
  which is what `tools/run_tests.sh` is"* — only ever ran on a machine that already
  had the cache, so the gate passed WARM and the invariant it was gating was false.
  `run_tests.sh` now does one `--headless --import` when `.godot/` is absent, which
  costs a warm run nothing and is what makes "green from a fresh clone" true.

  **The rule the other three still cost, unchanged.** *`src/` may reference an addon
  file only if that file is committed*: `addons/` is gitignored, so the moment
  anything under `src/` imports one, that addon has to be committed or
  `tools/run_tests.sh` fails from a fresh clone — the same fresh-clone reason the
  fonts, the icons and the Blue Marble raster are all read as bytes rather than
  `load()`ed. `dialogue_manager` is the precedent for HOW to adopt one: gate first
  (headless smoke), commit whole, state the exception, rewrite this paragraph.

  **The consequence to know when reading a probe diff:** `MCPRuntimeServer` autoloads
  into *every* local run, headless ones included, and prints its port. V1.7c's balance
  re-run diff carried two lines of `listening on 127.0.0.1:657x` noise for that reason
  and nothing else. Filter it, but do not let it hide a third line — that run had one,
  and it was real.

## Current focus

**V4.4 — EVENTS AT SCALE — IS MERGED (PR #49, merge commit `5a2d00a`, 2026-10-14)** after a 23-pass review loop. The event slot became a severity-ordered desk (`ns.event_queue`, `QUEUE_MAX` 4); the quiet went per-category; hooks (a closed vocabulary in `events_constants.ON_ACTIONS`) make the world react to what the player did; a choice can arm a chain; the other 28 nations answer through a deterministic chooser, with tax, spending and company effects skipped for them (their budgets never tick); the book is 102 events in nine categories with 54 art plates. `SAVE_VERSION` is **39** (argued in `game_state.gd`'s `SAVE_VERSION` block). Suite 104/104, names clean. Model: [docs/events-model.md](docs/events-model.md). The re-baseline's 24 outcome flips (20 HELD→LOST at 2032, through the default-drain channel) were ACCEPTED as the bound by the author on 2026-10-14: ignoring the desk is meant to cost.

**Open for the author, none urgent** (each recorded with a trigger in [docs/someday.md](docs/someday.md), and listed as a checkbox under its "Open author calls" so the vault dashboard shows what is still open): the event-art contact sheet verdict (the plates lean photographic, not painterly — [docs/event-art-plan.md](docs/event-art-plan.md)); `com_industry_bills.protect_the_makers` is a regulation, so the book has no true "protect industry" option. (E4/E5 were re-run on 2026-10-14 after the commodity unbind and the price-drift fix: 12.0 arrivals per term, every band PASSED.)

**V4.5 — THE COUNCIL, CONTESTED — IS MERGED (PR #53, merge commit `127b087`, 2026-10-15)** after a 2-pass review (budget 3, bar fixed up front). Sponsors who lobby and vote for their own proposals, three priced bargaining currencies (favour 12 / aid on the transfer line / vote-trade IOU settled at ratification for treaties), unanimity treaties with vetoes beside QMR, the real EU Council presidency (Decision (EU) 2016/1316, repeated after 2030 — a bound; the chair at the next opening sets the agenda; NATO has none), one opening per council every 6 months, and ratification at home through `Legislature.resolve_vote()` (one rejection kills the treaty for every member). 34 proposals placed by `tools/council_probe.gd`; bands C2–C4 PASS, C1 and C6 BOUND, C5 2.215 raw. UI: the council block (`src/ui/council_section.gd`, `council_bargains.gd`), ratification card on the bill's blurred forecast, desk mark, calendar deadline, top-bar Europe figure. `SAVE_VERSION` stays 39. Suite 106/106. Model: [docs/orgs-model.md](docs/orgs-model.md) §V4.5; history: [docs/history.md](docs/history.md).

**V4.11 — THE NEIGHBOURHOOD — IS MERGED (PR #3, merge commit `d59fd6a1`, 2026-10-17)** after a 3-pass review (built 2026-10-15/17, a1 a2 b1 b2 c). The roster is 41: the 29 plus twelve simulated, not playable (NOR ISL SRB TUR ALB MKD MNE BIH UKR MDA XKX BLR). The grade is DERIVED (`src/core/roster.gd`: playable / simulated / outline), never stored. The 133 outlines carry a name, GDP and real production shares (`data/world/outlines.json`, `tools/endowments_generate.py`) and trade as one world pool; on the map an outline can be hovered and read (`src/ui/map_outlines.gd`) but never clicked. `SAVE_VERSION` **40** (no field; V3.3's argument). Suite 109/109. Re-baselines: 0 outcome flips of 94 (a), byte-identical (b). Open for the author: the month tick is 392 ms at 41 (Diplomacy's N²); clothing still creeps (1.20x at month 120, no crossing since the review's energy fix; likely static world volume — [docs/someday.md](docs/someday.md)). History: [docs/history.md](docs/history.md) §V4.11. **NEXT: V4.8 — the reading surface**, building (see below). Per-block history (what each version built, what each probe measured, each refused alternative) lives in [docs/history.md](docs/history.md), moved out of this file so every session does not pay for it; the tier docs are `docs/tiers/` ([v4](docs/tiers/v4.md) is current) and the parking lot is [docs/someday.md](docs/someday.md).

**V4.8a — THE STRIP, WHOLE — IS MERGED (PR #4, merge commit `fac8e699`, 2026-10-17).** The top bar is one register of thirteen readings (`src/ui/strip_readings.gd`; `top_bar.gd` is its host), stacked caption over value to fit 1920 × 44 (one line measured 2219 px; author's call). Tooltips surface existing queries only -- no `src/sim/` diff (author's call); alerts fire on thresholds the game already holds and name their window with the bound key. `tests/test_strip_readings.gd` is the tooltip walker (it measures WITH the game theme -- unthemed it said 44 px where 50 was drawn). Register B: two rows fixed, four struck. **The UI is fully reworked in V5** (author, 2026-10-17): V4's UI effort goes to registers and walker tests, not layout. History: [docs/history.md](docs/history.md) §V4.8.

**V4.8b -- NESTED TIPS AND THE OUTLINER -- IS MERGED (PR #5, merge commit `c34abc53`, 2026-10-17).** The strip's tooltip is a two-level popup (`src/ui/tip_popup.gd`; level 2 from `src/ui/strip_children.gd`, asked lazily), the strip is twelve readings (People left it), and the outliner is a register (`src/ui/outliner_readings.gd`) drawn by a window (`outliner_panel.gd`, key Q). No `src/sim/` diff. Contract and walker: [docs/panel-system.md](docs/panel-system.md) §20. "Watched firms" has no register in the game, so the outliner reads firms in trouble (author's call; a player watchlist is parked in [docs/someday.md](docs/someday.md)).

**V4.8c -- MESSAGE SETTINGS AND THE LEGEND'S GRADES -- IS MERGED (PR #6, merge commit `881de1c9`, 2026-10-17) after a 2-pass review (one fix: a quiet card's deadline now follows the desk). V4.8 closes here.** Per event category, four switches (notify / feed / popup / pause), each a severity band (`src/ui/message_settings.gd`, `[messages]` in `user://settings.cfg`, no save field); pause defaults to Major+ (author's call). The arrival pause's contract is kept by name: the LAPSE GUARD in `main.gd` holds the clock for an unanswered quiet decision in its last month, so none lapses unseen. The Political legend counts playable / simulated / outlines through `Roster.counts()`. No `src/sim/` diff. Suite 113/113. Contract: [docs/panel-system.md](docs/panel-system.md) §21. **NEXT: V4.9** -- ceremony, motion and sound (`.superpowers/sdd/v4.9-handoff.md`), split a/b/c at the plan gate; a is below.

**V4.9a -- THE LOADING SCREEN AND THE MOTION VOCABULARY -- IS MERGED (PR #7, merge commit `14b6d2a2`, 2026-10-17).** Menu -> game no longer freezes ~7.5 s: `src/ui/boot_stages.gd` runs the boot a stage per frame (threaded scene compile, data, world, `Net.warm_step` -- the one `src/sim/` diff, the same table in slices), the loading screen's bar is the MEASURED stage weights (`tools/boot_stages_probe.gd`), and `main.gd` takes the loader and state it is handed (`pending_loader` / `pending_state`), building its own on a direct load as before. `src/ui/motion.gd`: windows open, cards arrive, strip figures roll, the date beats per day; off under `--headless` and by `[display] motion`. Suite 115. Contract: [docs/panel-system.md](docs/panel-system.md) §22. **NEXT: V4.9b** -- election night as a sequence + map-mode transitions; then V4.9c, the synthesized sound set.

**Save format** is at the version above. The rule for a bump is not "a new field bumps" but "a missing field would read as something wrong": an absent value that reads correctly for every older save (a register that was "nothing yet", a stamp at -1) earns no bump and is pinned by `tests/test_save_load.gd`; a content-derived static that `from_dict()` cannot re-derive does. There has never been a migration — a superseded save is refused outright. The version history is in `game_state.gd` and `docs/history.md`; do not copy the current number into prose that nothing keeps in step with the code.

**A UI session is not finished until `tools/screenshot.gd` has been run windowed** (`--headless` draws nothing, and a green suite says nothing about layout); it takes a flag per staged state, listed in its header, and marks panels dirty the way `main.gd` does.

## UI conventions

Styling rule since U3: colours and the type scale come from `ui_theme.gd`, set
per control with `theme_type_variation`. Never `add_theme_stylebox_override()` or
`add_theme_font_size_override()` in a panel — `tests/test_ui_theme.gd` fails on
it. Separation and margin constants stay at their call sites; they are layout —
**except the panel grammar's own**, which moved into `src/ui/panel_kit.gd` at
V2.1a, because they are that grammar's layout rather than any one panel's. Since
V2.1a a panel builds its rows out of `PanelKit` rather than its own helpers, and
`tests/test_panel_kit.gd` fails if a migrated panel keeps a private copy.

**U5a retuned that theme and moved the shell around it.** The palette is deep
navy with a single **brass** accent, and the visual signature is one rule: a HUD
plate carries a 1px brass hairline on its **top edge only**. `test_ui_theme.gd`
asserts the other three edges stay bare — do not "tidy" it into
`set_border_width_all()`. `assets/fonts/` holds the repo's first committed
binaries (Barlow Condensed for chrome, IBM Plex Mono for figures, both SIL OFL);
they are loaded by a path that works before the editor has imported anything,
because `tools/run_tests.sh` runs headless from a fresh clone. Icons are read
and rasterised from `.svg` text for the same reason — never `load()` an at-icons
path.

The shell is: `map_view` full-rect at the back, `window_manager` over it, `hud`
on top. There is no tab rail. A panel is registered with
`_windows.register(id, title, panel)` **before** its `setup()` is called, because
`register()` is what puts it in the tree. Adding a surface is that one call plus
one line in `main.gd`'s `_build_action_bar()`.


## Workflow

One session, one objective, a fresh chat each time. Commit at every session
boundary, and end each session by writing the next one's handoff prompt — the
handoffs live in .superpowers/sdd/ beside this file. Verify against the
session's done-when list before claiming done.

**There is ONE instructions file, `AGENTS.md`, as of the V3.1 close-out.** A
second copy, `CLAUDE.md`, existed for a different assistant reading a different
filename, and the convention was that a session updated BOTH with a `diff`
gate before committing. The gate was quietly dropped: V2.8.1 stopped updating
the copy and three session rows (V2.8.1/V2.9, V3.0, V3.1) drifted — the copy
that drifts is the one that will be believed, exactly as this section used to
warn. The file is deleted and every code comment, tool and model doc that
cited it by name now cites `AGENTS.md`; the drift failure this paragraph once
guarded against is impossible rather than merely remembered.

**Review loops and delegated work** (lessons of V4.4's 23 passes, which never reached three clean ones):

- **Fix the stop rule before the first pass.** A reviewer that finds something every time never converges on "N clean passes". State a budget and a severity bar up front (stop when no finding changes what a player experiences, or after N passes) and say so when the finds turn from bugs into design calls — do not wait to be asked.
- **Three patches to one subsystem is a design smell.** The third fix to the same code (V4.4: the clock's pause holds) is the moment to propose redoing it once, not a fourth patch; most late findings were made by earlier fixes.
- **Green is not measured.** For a change to what the game delivers or how often, run the real machine with the game's own tick order and report the numbers before calling it done; a probe that omits a machine measures a world the game never runs (V4.4's commodity hook fired 168 months of 168 while every gate was green).
- **One Godot at a time.** Delegated agents run only their targeted test files; the full suite (`bash tools/run_tests.sh`) is run by one session, alone — concurrent Godot processes share caches and die silently.
- **Check a delegated report against the tree.** An agent can return empty or stop on a quota; read `git status` and the diff before trusting a report, and never leave `tmp_*.gd` copies in the repo root (a stray `class_name` duplicate fails the whole suite).
