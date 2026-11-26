# Nation Simulator

Single-player geopolitics and nation-management game. You are the President of
France: budget, laws, an assembly that need not agree with you, and an election
at the end of the term. 41 European nations simulated, four of them playable (France, Germany, Britain, Poland), a 2D map, dense UI panels.

Design vault is `docs/` — open **the project root** as the Obsidian vault, not
`docs/` (the vault config `.obsidian/` lives at the root). Start at
[docs/index.md](docs/index.md).

## Stack

- **Godot 4.7.2-stable**, non-Mono. Pinned in `project.godot` (`config/features="4.7"`).
  Bump deliberately and re-run the tests before committing the bump — and
  `tools/opcache_race_probe.gd -- --kind=raw` on the Linux build (pinned to two
  cores, several processes): while it still crashes, the GDScript operator-cache
  race behind G2 is live and `src/core/parallel.gd` rule 5 stays.
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
a new file stays at or under 300 (400 under `src/ui/`); a file in `tools/size_baseline.json` may
shrink, never grow, and the change that shrinks it lowers the baseline
(`--update`); no `src/` file past 2 000 total lines, no exception (the last,
`src/ui/main.gd`, closed at V5.1-d2: 2 705 -> 2 124 at c, 1 919 once the desk cards
moved to `desk_cards.gd`). `tools/` and `tests/` past 2 000 are printed,
not failed. CI runs it.

```bash
python tools/check_vault.py
```

The vault check: unresolved wikilinks, docs the index does not reach, orphans, missing
frontmatter -- over tracked files only. What each Obsidian plugin is for: [docs/vault.md](docs/vault.md).

```bash
python tools/ui_map.py --check
```

Where each screen lives (domain, tab, window id, key, panel file, the screen stack's surfaces):
`docs/ui-map.md` is GENERATED from the tracked `src/ui/` files. It goes stale when a PR adds,
renames or re-keys a window (`_windows.register`), changes a domain row in `domains.gd`, adds a
panel to a screen-stack rank, or changes a hotkey; then run `python tools/ui_map.py --write`.
CI runs `--check` (last step of the checks job); the local gate (`run_tests.sh`) does NOT, so run it
yourself. Never edit the page by hand.

```bash
python tools/check_uids.py
```

Fails on a tracked `X.uid` whose `X` is not tracked: Godot never deletes a script's `.uid`
when the script goes, so a deletion commit has to `git rm` it too. CI runs it.

```bash
python tools/check_skills.py
```

Every shipped `start_regard_offset` is inside its range, and, where the gitignored
`tools/private/skills_basis.json` is present, every one on a marked person has a basis line
(a worktree has no copy: `--basis PATH`, the main checkout's). CI has no file and checks the
numbers only. The basis and the mark are never committed: nothing but numbers ships.

```bash
reuse lint
```

The licence check (`pip install reuse`): every tracked file needs a licence, declared
in `REUSE.toml` — a new asset, a new data source or a third-party file needs an
annotation there. The layers are listed in [README.md](README.md); CI runs it.

```bash
python tools/event_lint.py --check
python tools/law_lint.py --check
```

The authoring lints over `data/events/` and `data/laws/` (schema plus the book's spread
bands; stdlib, no Godot). CI runs the first; `tests.yml` does not run the second.

```bash
python tools/i18n_extract.py --check
```

The translation tables: a stale key, an empty value or a placeholder mismatch in
`data/i18n/`. CI runs it, after `--selftest`.

```bash
python tools/voice_pipeline.py --selftest
```

No network, no credits spent. CI runs it.

```bash
bash tools/run_tests.sh --print-tests | python tools/ci_shards.py --check
```

Every registered test is in exactly one shard of `tools/ci_shards.json`. The local gate
does not check it and CI does, so a new test needs its row in `run_tests.sh` AND in the
shard file. CI runs it. Two hooks wired in `.claude/settings.json` run these for you
([docs/tooling.md](docs/tooling.md)): the lints after an edit under their folders, this
check before a `git commit` that stages a test.

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
  silently needs one too.

## Gotchas

Engine gotchas; the first two were confirmed on 4.7.1 and are written up in [docs/engine-decision.md](docs/engine-decision.md):

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

- **`project.godot` is always dirty in the main working copy, and it is never yours.**
  The Godot editor rewrites it on every open with whatever addons are installed on
  that machine. Do not stage it. What it adds locally:

  ```
  [autoload]
  MCPRuntimeServer="*res://addons/godot_mcp_toolkit/runtime/mcp_runtime_server.gd"
  DialogueManager="*uid://c3rodes2l3gxb"

  [editor_plugins]
  enabled=PackedStringArray("at-icons", "dialogue_manager", "godot_mcp_toolkit",
                            "materialLayers", "road-generator")
  ```

  The committed file carries only `DialogueManager`, in `[autoload]` and in
  `[editor_plugins]`. **So a clean `git status` on this file in the main checkout is
  the alarm, not the all-clear**: the per-machine lines may have been committed, and a
  fresh clone then autoloads a script that does not exist.

  `godot_mcp_toolkit` is in use: it is what `runtime_screenshot` and `input_simulate`
  reach a running game through. `at-icons`, `materialLayers`, `road-generator` and
  `limboai` are **parked on purpose, not junk**; do not strip them because nothing in
  `src/` reads them. `road-generator` is not for the 2D road layer: read its callout in
  [docs/data-sources.md](docs/data-sources.md) before reopening that question.

  **`dialogue_manager` is the stated exception to the no-autoloads rule**, committed
  whole into `addons/`, with the reason in `.gitignore`. Its `class_name` types do not
  resolve without `.godot/`, so `run_tests.sh` runs one `--headless --import` when
  `.godot/` is absent.

  **`src/` may reference an addon file only if that file is committed**: `addons/` is
  gitignored, so otherwise `tools/run_tests.sh` fails from a fresh clone. The same
  reason has fonts, icons and the Blue Marble raster read as bytes, not `load()`ed. To
  adopt an addon: gate it with a headless smoke test on a cold clone, commit it whole,
  state the exception, and rewrite this section.

  **When reading a probe diff:** `MCPRuntimeServer` autoloads into every local run,
  headless ones included, and prints its port. Filter those lines, but do not let them
  hide another difference.

## Current focus

**V5 — THE WORLD TALKS BACK** (signed 2026-10-19, [docs/tiers/v5.md](docs/tiers/v5.md); the author's asks and calls: [docs/v5-reflection.md](docs/v5-reflection.md)). The live state of each block is the `state:` map in that page's frontmatter, and the running record is its newest progress section; read both before starting. The record of closed blocks is that page and [docs/history.md](docs/history.md); open items and the author's open calls are in [docs/someday.md](docs/someday.md). The UI is fully reworked in V5 (author, 2026-10-17). War, espionage and regimes are V6.

- **Every V5 block closes with the author playing it for thirty minutes, and the verdict is a done-when** (author, 2026-10-19).
- **Screens are rebuilt one at a time, the picture before the code**: mockups, the author's pick, the build, QA, then QA plays the exported build in a real window with the mouse (author, 2026-11-13).
- Work runs through the version session (`.superpowers/sdd/v5-version-session.md`: one child session per block, sub-blocks inside it); the tier-end review is built from the `v4-end` tag.

**Save format** is `SAVE_VERSION` in `src/core/game_state.gd`. The rule for a bump is not "a new field bumps" but "a missing field would read as something wrong": an absent value that reads correctly for every older save (a register that was "nothing yet", a stamp at -1) earns no bump and is pinned by `tests/test_save_load.gd`; a content-derived static that `from_dict()` cannot re-derive does. Since V5.0a the verdict for a NationState field is a column — `absent_ok` in `src/core/nation_fields.gd` — and `tests/test_nation_fields.gd` pins its false set against `SAVE_VERSION`. There has never been a migration — a superseded save is refused outright. The version history is in `game_state.gd` and `docs/history.md`; do not copy the current number into prose that nothing keeps in step with the code.

**A UI session is not finished until `tools/screenshot.gd` has been run windowed** (`--headless` draws nothing, and a green suite says nothing about layout); it takes a flag per staged state, listed in its header, and marks panels dirty the way `main.gd` does. Run it through `python tools/screenshot_all.py --out <dir> --only <flag>`, which creates the window without taking the keyboard; a direct windowed run needs the author's go (Workflow, "The real mouse cursor").

## Versions and changelog

Three numbers, kept apart:

| number | what | where | changed by |
|---|---|---|---|
| build version | SemVer, `0.<tier>.<block>`; a kit the author plays is `0.5.3-gate.N`, the block's close `0.5.3` | `version.json` | a cut, nothing else |
| save format | `SAVE_VERSION`, an integer | `src/core/game_state.gd` | the PR that breaks the format ("Save format" above) |
| tier name | V5.3, "a + b", "block 0" | changelog headings, docs | the author |

- **Every PR that changes `src/`, `data/` or `assets/` adds `changelog.d/<branch-slug>.md`**: one
  line per change a player notices, in the player's words and in English, starting with its
  group (`Added:` `Changed:` `Deprecated:` `Removed:` `Fixed:` `Security:`), or `None: <why>`. No
  file or field names, no real person's or firm's name. A save-format bump adds
  `Changed: Saves from earlier builds no longer load.` CI fails a PR that forgets
  (`python tools/changelog.py --check-pr`). One file per PR, because children have PRs open at
  once and a shared `[Unreleased]` block would conflict on every merge.
- **Nobody edits `CHANGELOG.md` or `version.json` outside a cut.** A cut happens when a kit
  the AUTHOR plays is ordered: its builder opens a PR that is only
  `python tools/changelog.py cut 0.5.3-gate.N --label "V5.3 ..."`, the parent merges it and
  tags the merge commit `v0.5.3-gate.N`, and the kit is exported from that tag. QA's kits
  from unmerged heads are never cut.
- **What a build shows** (menu corner, dev console `version`, the kit's `RELEASE.md`):
  `tools/export_windows.py` stamps it into the stage only -- the bare version from its own
  tag, otherwise `dev build <sha> (after <version>)`; the editor and the suite read
  `<version>+dev`. `python tools/changelog.py notes <version>` prints the section a kit's
  `RELEASE.md` opens with. `docs/history.md` stays the engineering record.
- `project.godot` carries no version, on purpose: it is per-machine dirty (Gotchas).

## UI conventions

Styling rule since U3: colours and the type scale come from `ui_theme.gd`, set
per control with `theme_type_variation`. Never `add_theme_stylebox_override()` or
`add_theme_font_size_override()` in a panel — `tests/test_ui_theme.gd` fails on
it. Separation and margin constants stay at their call sites; they are layout —
**except the panel grammar's own**, which moved into `src/ui/panel_kit.gd` at
V2.1a, because they are that grammar's layout rather than any one panel's. Since
V2.1a a panel builds its rows out of `PanelKit` rather than its own helpers, and
`tests/test_panel_kit.gd` fails if a migrated panel keeps a private copy.
A button's width is one of four classes (`PanelKit.button`, and `PanelKit.buttons`
for a group), never its label's: a group takes the class its longest label needs in
the language shown, and every class times the text size. `tests/test_panel_kit.gd`
fails a group whose buttons do not share a class.

**G3 replaced BUREAU's look (the author's pick, 2026-11-21, "Sheets on glass").**
The map fills the screen and the chrome is three floating glass panes (the sidebar, the
top strip, the time bar), `GAP_PANE` from the screen's edges and from each other: a dark
tint over the blurred map (`src/ui/frost.gd`, under `PanelKit.pane()`), a 1px light rim,
`R_PANE` corners and no shadow (a stylebox's shadow darkens the blur under its own body);
the "Glass" setting turns the blur off and the panes `PANE_SOLID`, which keep `ELEV_PANE`.
Nothing else is a pane. The workspace has no pane: its content sits on solid **sheets**
(`UiTheme.PLATE`, `PanelKit.sheet()`), one job per sheet, `GAP_PANE` apart, with a
contact shadow of a few px and a faint `SHEET_RIM` on all four sides (elevation C, the
author's pick, 2026-11-21: the soft halo was wider than the gap it sat in); tooltips and
menus are opaque popovers that never blur.
Things are separated by space and by a change of surface; the only lines G3 keeps are a
sheet's faint rim and the divider between a table's rows (screens that draw their own lines keep BUREAU's `EDGE`
until their slice). Text never sits on glass over the map without the
pane's tint, and never on a sheet that is not opaque. `test_ui_theme.gd` fails a
sheet that is translucent, without its rim or with a wide shadow, a pane that drops its rim, and a pane that
still reads the screen with Glass off. The BUREAU hairline on four sides is gone; do
not bring it back. A toggle that is ON wears the accent fill through its own variation,
`UiTheme.PICKED` (`PanelKit.toggle()`), because "pressed" is also a plain button held
down, which takes `CONTROL_PRESSED`; `test_button_sizes.gd` fails a toggle left on the
plain look. G3 lands in slices (Design's `g3-spec.md`): S0 is the theme, so every screen
took the colours, corners and button states at once; S1 floated the shell; S2 to S8
re-lay the screens one by one. Until a screen's slice, it may still
draw with BUREAU's names (`HULL`, `SLATE`, `EDGE`), now aliases of the G3 surface
each became.

The accent is chosen by a **rule over the flag's bands** (`src/ui/accent_rule.gd`,
`data/nations/*.json`), never by nation id: of the bands with enough chroma, the one
that needs the **smallest** hue shift (ties to file order), its hue **shifted** if it falls within 24° of a state tone (alert red,
good-news green, attention amber) to the nearest clear edge of that zone, and
lifted in HSL lightness to WCAG AA (4.5:1) on the lightest graphite surface
(`TILE_HOVER`, where the accent is read as text), still qualifies. The rule gives two
results: the accent as text and outline (`UiTheme.accent()`), and the accent as a
fill (`UiTheme.accent_fill()`), darkened until white text on it holds 4.5:1, or left
as it is under a dark label when its hue cannot. The fill is for today's date, the
armed verb, a picked chip, a bookable day under the pointer and a screen's one main
action (`UiTheme.PRIMARY`); no other button is filled. A status tone or the accent
is never the colour of text on a control. Polish crimson
becomes raspberry, German gold a bright yellow; the flag's colour family survives and is never mistaken for a
state. `UiTheme.ACCENT_FALLBACK` is for a flag with no chroma at all, and for the
menu. **Two kinds of colour, never mixed:** IDENTITY follows the nation
(`UiTheme.accent()` -- the open cluster's bar, focus, fills, today's mark, the
home outline, and the PLAYER's own city, project and plant marks; every other
nation's are `UiTheme.MAP_NEUTRAL`; headings are neutral) and STATUS is a fixed tone (`GOOD`, `BAD`,
`WARN` -- a mood, a pending mark, the placement reticle). There is no `ACCENT`
const. `main.gd` re-applies the theme once the played nation is known and on a
load (`UiTheme.apply_for`); the menu resets it. `test_accent_rule.gd` runs the
rule over all 41 flags.

Type is **Archivo** (variable, SIL OFL) cut by weight and width axes — keyed by
OpenType *tag*, an int, since a string key is accepted and does nothing — with
`tnum` on figures. The scale has one size for a title, `SIZE_TITLE` (the `Title`
variation). Icons are filled **Material Symbols Rounded** SVGs under
`assets/icons/material/` (Apache-2.0). Photographs (portraits, scene backdrops,
event-art plates) go through one runtime material, `src/ui/grade.gd`, applied
with `Grade.apply(rect)`; `test_grade.gd` fails a surface that forgot. Fonts and
icons are loaded by a path that works before the editor has imported anything
(bytes for the font, SVG text for icons), because `tools/run_tests.sh` runs
headless from a fresh clone — never `load()` an icon path.

**Text a player reads goes through `tr("English")`** (V5.1b, [docs/localisation.md](docs/localisation.md)): the English is the msgid, French is `data/i18n/fr/ui.json`, a row of `data/` is shown through a `Strings` row accessor (`row_name`, `row_summary`, `choice_label`, `record_event_name`, `noun`, ... over `Strings.row(kind, id, field, english)`; `tests/test_i18n_rows_lint.gd` fails a raw read of a row's English) and an id made into a word through `Labels` (never `id.capitalize()`). The caller wraps, helpers never translate, a `static func` uses `Strings.t()`, and never use a `tr()` result as a key or compare shown text to an English literal. `tests/test_i18n_lint.gd` fails a bare literal at a text sink or anywhere it reads as prose (a const table of prose carries `# i18n: msgid`) and a ternary of short fragments inside a format argument -- a sentence is whole, a count picks its form with `tr_n` / `Strings.tn`; a figure with decimals goes through `Num.f` / `Num.fs` (the language's decimal separator, never a raw `%.2f`) and a date through `DateText`; `tests/test_i18n_fit.gd` opens every window under +35% pseudolocalization. Map place names are the one exception to the body width: `UiTheme.map_face()` at `UiTheme.SIZE_MAP`, the narrow end of Archivo's width axis, because the label packer drops a name that does not fit.

The shell is (G3 S1): `map_view` full-rect at the back; `window_manager` over it, a
workspace of sheets beside the sidebar, `GAP_PANE` from every pane, that shows one tab at
a time under its domain and fills the band between the panes (the author's decision 9;
Regions alone docks narrow, its place being the map it tints; while the inbox shows, the
workspace ends `GAP_PANE` short of it, so nothing sits under it); the tabs are
a segmented control in the workspace's first sheet, beside the breadcrumb
(`src/ui/domains.gd` is the table of domains and their tabs; back and forward walk the
player's path); `hud` on top -- the three glass panes: the sidebar, the top strip with
the figures (it folds its lowest-priority figures into "+N" when its slot is short) and
the title bar's tools in one row, the time bar -- then the legend, the inbox (a column
of sheets at the right, beside the workspace, never over it) and the front pages; and
`screen_stack` above them, which ranks what owns the screen (workspace, inbox,
placement, scene, system) for the keys, Escape and the game's own arrivals. A
panel is registered with `_windows.register(id, title, panel)` **before** its
`setup()` is called, because `register()` is what puts it in the tree. Adding a
surface is that one call plus its row in `domains.gd`; a modal is
`_stack.add(layer, panel, dim, cancel)`.

**Glossary terms** (V5.1-c, [docs/design/glossary-tooltips.md](docs/design/glossary-tooltips.md)):
a writer marks a term as `[g=id]word[/g]` in prose shown through `PanelKit.rich()` -- a
`TermText` (`src/ui/term_text.gd`), the one place a term is drawn; the ids are
`data/glossary/terms.json`'s, read by `src/ui/glossary.gd`, and the tooltip chain is
`glossary_tip.gd`, the screen stack's last child. Rich prose is not BBCode: every other
`[` is escaped. `PanelKit.line()` draws a `TermText` when its text carries a mark and a `Label` otherwise (V5.1-d3); a site that needs a `Label` calls `PanelKit.plain_line()`.


## Workflow

One session, one objective, a fresh chat each time. Commit at every session
boundary, and end each session by writing the next one's handoff prompt — the
handoffs live in .superpowers/sdd/ beside this file. Verify against the
session's done-when list before claiming done. Whoever closes a block updates its line in the `state:` map of
docs/tiers/v5.md.

**`AGENTS.md` is the only instructions file.** The root `CLAUDE.md` holds one line,
`@AGENTS.md` (Claude Code's import syntax), so tools that read `CLAUDE.md` load these
same rules. Never write anything else in `CLAUDE.md`; edit `AGENTS.md`.

**Review loops and delegated work** (lessons of V4.4's 23 passes, which never reached three clean ones):

- **Fix the stop rule before the first pass.** A reviewer that finds something every time never converges on "N clean passes". State a budget and a severity bar up front (stop when no finding changes what a player experiences, or after N passes) and say so when the finds turn from bugs into design calls — do not wait to be asked.
- **Three patches to one subsystem is a design smell.** The third fix to the same code (V4.4: the clock's pause holds) is the moment to propose redoing it once, not a fourth patch; most late findings were made by earlier fixes.
- **Green is not measured.** For a change to what the game delivers or how often, run the real machine with the game's own tick order and report the numbers before calling it done; a probe that omits a machine measures a world the game never runs (V4.4's commodity hook fired 168 months of 168 while every gate was green). The game's own tick order is `src/sim/world_month.gd`: a harness calls `WorldMonth.tick_month()` and acts or times through its step hook, never copies the order (`tests/test_world_month.gd` fails on a copy). A session that adds a step to `STEPS` there must also add it to `GROUPS` in `tools/vault_diagrams.py` and run `python tools/vault_diagrams.py --write`, or `tools/check_vault.py` (and CI) fails. `tools/balance_probe.gd -- --json=PATH` writes the outcome table and `python tools/balance_diff.py base.json tip.json` diffs two. `python tools/balance_parallel.py --json=PATH` writes the same table, byte for byte, from one isolated probe per regime (7:19 instead of 37:06 at `-j 8`); it is ONE isolated run (its eight probes share one checkout read-only, as `suite_runner.py`'s `-j` pool does, after one cold `--import` if `.godot/` is absent), and it saturates the CPU, so nothing timed runs beside it.
- **One Godot at a time — unless both are isolated, in separate checkouts.** Concurrent Godot processes in one checkout share `.godot/` and the user dir, and die silently. Since V5.0b, ISOLATED runs (every `suite_runner.py` / `run_tests.sh` run unless `--no-isolate` -- the default since 2026-10-20 -- `balance_parallel.py`, or the `APPDATA="$(mktemp -d)"` line for a hand-run probe) in SEPARATE checkouts (a `git worktree add --detach <path> <sha>` each) may overlap (Windows via APPDATA, Linux via XDG_DATA_HOME; macOS is NOT covered -- Godot ignores both there): each gets its own user dir — measured with two concurrent runs, the suite-exclusive `test_save_load` included, the real user dir untouched. STILL ALONE: timing probes (`tick_budget_probe`, the G2 frame probe — CPU contention), two runs in one checkout, and any un-isolated Godot (the editor, the MCP bridge, a probe without the line). The repo-guards mod lets an isolated launch through beside another run -- a bare `suite_runner.py` / `run_tests.sh` counts as isolated (their default), as does an `APPDATA=` prefix, and only `--no-isolate` is plain; a plain second run (an un-isolated `godot`) beside a headless run still needs `# allow-concurrent-godot`, and a timing probe stays alone, marker or not. The guard counts only `--headless` processes, so it lets a plain run through beside the editor: the editor is STILL ALONE all the same, by this rule rather than the guard. The full suite is still one session's run; delegated agents run only their targeted test files. Never edit a checkout a probe or test is running from.
- **The real mouse cursor is the author's.** A windowed Godot run reads the OS cursor (a pushed motion does not move `get_mouse_position()`), so a warp would drag it across whatever they are doing; headless has no cursor and the suite never touched it. `tools/os_cursor.gd` is the ONE place that may warp, and only under `NATION_OS_CURSOR=1` (off by default); `tests/test_os_cursor.gd` fails any other `warp_mouse` call in `tests/`, `tools/` or `src/`. A windowed capture calls `OsCursor.quiet_window()` (the window goes windowed and off every monitor, or onto the screen `NATION_SHOT_SCREEN` names, which `tools/screenshot_all.py` sets to a secondary monitor by default when there is one; re-checked each frame). **That does not keep the keyboard**: a windowed Godot launched from the foreground app took the foreground in 3 of 7 measured launches, off screen or not, so a windowed run needs the author's go unless it is created without activation (an `override.cfg` with `display/window/size/no_focus=true`, which `tools/screenshot_all.py` writes for its runs; measured 0 of 6). A probe that needs the pointer HERE sets the flag in its own command line and says so; one that does not pushes its own motion or sets the position. [docs/tooling.md](docs/tooling.md).
- **Check a delegated report against the tree.** An agent can return empty or stop on a quota; read `git status` and the diff before trusting a report, and never leave `tmp_*.gd` copies in the repo root (a stray `class_name` duplicate fails the whole suite).
