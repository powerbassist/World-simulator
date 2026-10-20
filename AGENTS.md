# Nation Simulator

Single-player geopolitics and nation-management game. You are the President of
France: budget, laws, an assembly that need not agree with you, and an election
at the end of the term. Ten European nations, 2D map, dense UI panels.

Design vault is `docs/` — open **the project root** as the Obsidian vault, not
`docs/` (the vault config `.obsidian/` lives at the root). Start at
[docs/index.md](docs/index.md).

## Stack

- **Godot 4.7.2-stable**, non-Mono. Pinned in `project.godot` (`config/features="4.7"`).
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
(JSON + per-test logs). With no test paths it runs the whole registry, parsed
from `tools/run_tests.sh`'s `tests=()` (its unregistered-test check
included). Run tests this way, not by hand-rolling godot invocations.
Single or subset runs: append test paths —
`python tools/suite_runner.py --ci tests/test_clock.gd tests/test_data.gd`.
Every run is ISOLATED by default (since 2026-10-20): a private `APPDATA` /
`XDG_DATA_HOME` (user:// in a temp dir, the cold-clone `--import` included;
deleted on success, kept on failure for its logs) — see "One Godot at a time"
below for what it permits. `--isolate` is still accepted and means the same;
`--no-isolate` runs against the real user dir. `tools/run_tests.sh` and the
cockpit go through the runner, so they isolate too. Two suites at once: one
`git worktree add --detach <path> HEAD` each, then the gate in each.

```bash
APPDATA="$(mktemp -d)" godot --headless --path . --script res://tools/balance_probe.gd -- --json=PATH
```

The same isolation for a hand-run probe (Git Bash turns the temp path into a
Windows one for Godot): user:// lands in the temp dir, never the real
`%APPDATA%\Godot\app_userdata\Nation Simulator`.

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
python tools/check_size.py
```

The size ratchet, on CODE lines (no blank, no comment-only line) over `src/`:
a new file stays at or under 300; a file in `tools/size_baseline.json` may
shrink, never grow, and the change that shrinks it lowers the baseline
(`--update`); no `src/` file past 2 000 total lines, `src/ui/main.gd` the
named exception until V5.1c. `tools/` and `tests/` past 2 000 are printed,
not failed. CI runs it.

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

**V4 — THE WORLD WANTS THINGS — IS CLOSED (2026-10-18; last merge PR #12, `d3953709`; tag `v4-end`).** Twelve blocks merged in the signed order V4.0 → V4.1 → V4.3 → V4.6 → V4.7 → V4.2 → V4.4 → V4.5 → V4.11 → V4.8 → V4.9 → V4.10: the programme and its credit channel, 1,595 people who want things, 2,737 firms that act, 60 goods (a layer beside the growth model, not yet feeding GDP), 120 laws with composition and repeal, 102 events on a severity-ordered desk, the contested council, a 41-nation roster with four playable, the reading surface, motion and synthesized sound, and the map at depth (G2 0.26 / 0.58 ms against 2.0). Suite 120/120. The record: the close-out section of [docs/tiers/v4.md](docs/tiers/v4.md) (merge table, promised against shipped, gates, lessons); per-block detail, including the V4 rows this section used to carry, in [docs/history.md](docs/history.md); open items and the author's open calls in [docs/someday.md](docs/someday.md). **The UI is fully reworked in V5** (author, 2026-10-17).

**V5 — THE WORLD TALKS BACK — SIGNED 2026-10-19** ([docs/tiers/v5.md](docs/tiers/v5.md); the reflection behind it, with the author's asks and calls: [docs/v5-reflection.md](docs/v5-reflection.md)). Order V5.0 foundations (the audit) → V5.1 the shell → V5.2 people who talk → V5.3 domains and decisions → V5.4 the real network → V5.5 close-out; war, espionage and regimes are V6. **Every V5 block closes with the author playing it for thirty minutes, the verdict a done-when** (author, 2026-10-19). **V5.0a0 (engine 4.7.2) and V5.0a (the field table) merged; V5.0b (the loader split, the size ratchet, isolated runs) merged; V5.0c0 (the balance probe sharded) merged; V5.0c (the tick: 424 → 316 ms mean, byte-identical levers) merged; V5.0c2 (the author's A + B: micro-levers and Diplomacy on worker threads, 241 ms mean / 304 ms worst, both bands met, still byte-identical) built; NEXT: V5.0d**, through the version session (`.superpowers/sdd/v5-version-session.md`: one child session per block, sub-blocks inside it; the tier-end review is built from the `v4-end` tag).

**Save format** is at the version above. The rule for a bump is not "a new field bumps" but "a missing field would read as something wrong": an absent value that reads correctly for every older save (a register that was "nothing yet", a stamp at -1) earns no bump and is pinned by `tests/test_save_load.gd`; a content-derived static that `from_dict()` cannot re-derive does. Since V5.0a the verdict for a NationState field is a column — `absent_ok` in `src/core/nation_fields.gd` — and `tests/test_nation_fields.gd` pins its false set against `SAVE_VERSION`. There has never been a migration — a superseded save is refused outright. The version history is in `game_state.gd` and `docs/history.md`; do not copy the current number into prose that nothing keeps in step with the code.

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
- **Green is not measured.** For a change to what the game delivers or how often, run the real machine with the game's own tick order and report the numbers before calling it done; a probe that omits a machine measures a world the game never runs (V4.4's commodity hook fired 168 months of 168 while every gate was green). The game's own tick order is `src/sim/world_month.gd`: a harness calls `WorldMonth.tick_month()` and acts or times through its step hook, never copies the order (`tests/test_world_month.gd` fails on a copy). `tools/balance_probe.gd -- --json=PATH` writes the outcome table and `python tools/balance_diff.py base.json tip.json` diffs two. `python tools/balance_parallel.py --json=PATH` writes the same table, byte for byte, from one isolated probe per regime (7:19 instead of 37:06 at `-j 8`); it is ONE isolated run (its eight probes share one checkout read-only, as `suite_runner.py`'s `-j` pool does, after one cold `--import` if `.godot/` is absent), and it saturates the CPU, so nothing timed runs beside it.
- **One Godot at a time — unless both are isolated, in separate checkouts.** Concurrent Godot processes in one checkout share `.godot/` and the user dir, and die silently. Since V5.0b, ISOLATED runs (every `suite_runner.py` / `run_tests.sh` run unless `--no-isolate` -- the default since 2026-10-20 -- `balance_parallel.py`, or the `APPDATA="$(mktemp -d)"` line for a hand-run probe) in SEPARATE checkouts (a `git worktree add --detach <path> <sha>` each) may overlap (Windows via APPDATA, Linux via XDG_DATA_HOME; macOS is NOT covered -- Godot ignores both there): each gets its own user dir — measured with two concurrent runs, the suite-exclusive `test_save_load` included, the real user dir untouched. STILL ALONE: timing probes (`tick_budget_probe`, the G2 frame probe — CPU contention), two runs in one checkout, and any un-isolated Godot (the editor, the MCP bridge, a probe without the line). The repo-guards mod (0.2.0) lets an isolated launch (`--isolate` or an `APPDATA=` prefix) through beside another run -- it predates the default and reads the flag, so a concurrent gate still spells `--isolate` out; a plain second run still needs `# allow-concurrent-godot`, and a timing probe stays alone, marker or not. The full suite is still one session's run; delegated agents run only their targeted test files. Never edit a checkout a probe or test is running from.
- **Check a delegated report against the tree.** An agent can return empty or stop on a quota; read `git status` and the diff before trusting a report, and never leave `tmp_*.gd` copies in the repo root (a stray `class_name` duplicate fails the whole suite).
