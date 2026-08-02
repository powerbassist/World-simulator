# Nation Simulator

Single-player geopolitics and nation-management game. You are the President of
France: budget, laws, an assembly that need not agree with you, and an election
at the end of the term. Ten European nations, 2D map, dense UI panels.

Design vault is `docs/` — open **the project root** as the Obsidian vault, not
`docs/`, or the `[[ROADMAP]]` links do not resolve. Start at [docs/index.md](docs/index.md).

## Stack

- **Godot 4.7.1-stable**, non-Mono. Pinned in `project.godot` (`config/features="4.7"`).
  Bump deliberately and re-run the tests before committing the bump.
- **GDScript with static typing** (`var gdp: float`). C# stays available as an
  escape hatch for a hot loop a profiler actually found — not preemptively.
- No database and no autoloads in the game code. Third-party addons are
  editor-side and gitignored by default; `src/` may reference an addon file
  **only if that file is committed** — see `.gitignore`. JSON content, JSON saves.

## Commands

```bash
bash tools/run_tests.sh
```

```bash
bash tools/check_names.sh
```

```bash
godot --path "<repo>"
```

Single test: `godot --headless --script res://tests/test_<name>.gd`.
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
          (nations, parties, laws, political-systems, scenarios, geo)
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

## Current focus

**U5a shipped the ruler's shell and U5b the world map, interrupting the S-track
queue on request.** The map is the background, not a tab; `dashboard.gd` and its
rail are deleted; the panels are pinnable floating windows.

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

Two named successors are scheduled and argued in [ROADMAP.md](ROADMAP.md):
**U5c** (map layers — relations and trade colouring, switcher, legend, cut out of
U5b at plan time and deliberately parked behind V1.3c so it can colour tariffs
too) and **U6** (the calendar, as a scheduling skin over existing verbs, plus the
named-individual roster V1.1d deferred). Neither blocks V1.3c.

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
finished.** `--headless` draws nothing, so a green suite says nothing about
layout; U5a shipped two bugs invisible to one. It saves a PNG of the running
game — run it windowed, not headless.

**V1.3 is decomposed into six sessions, V1.3a–f. V1.3a and V1.3b are built.**
The argument, the four calls it made, and the per-session table are in
[ROADMAP.md](ROADMAP.md); [docs/tiers/v1.md](docs/tiers/v1.md) §3 tags every
bullet with the session that builds it. Order: (a) relations and diplomatic
actions, (b) trade intensity and agreements, (c) tariffs and sanctions, (d) the
bloc, (e) AI foreign policy, (f) defence.

**V1.3a shipped the schema everything b–f reads.** Relations are pair state on
`GameState.relations`, **symmetric**, keyed `"DEU|FRA"` by `src/core/relations.gd`
— the only thing allowed to build a key — and derived at start from EU
co-membership and `government.neighbours`. The counterparty response is a
**declared stopgap** V1.3e replaces, asserted as such in `tests/test_diplomacy.gd`.
The model, every constant, and the measured tables are
[docs/diplomacy-model.md](docs/diplomacy-model.md).

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

**Next: V1.3c, tariffs and sanctions.** It is the first session that perturbs a
partner on purpose, which is what makes V1.3b's transmission channel loud rather
than merely correct — `tools/trade_probe.gd` already measures the headroom under a
synthetic recession. Still true for the whole block: no new `ISSUE_KEYS` entry
before V1.3d, because a new issue re-opens the whole `BLOC_SALIENCE_BASE`
measurement. **LimboAI was evaluated for V1.3e and declined** —
[docs/tiers/declined.md](docs/tiers/declined.md).

Two declared stopgaps are now on V1.3e's opening checklist, each asserted by a
test that must fail when it is replaced: the counterparty *reaction*
(`tests/test_diplomacy.gd`) and the counterparty *decision*
(`tests/test_trade.gd`).

MVP, V1.1a–d, V1.2a–e, V1.3a and U1–U4 are done. V1.1e (upper house and
judiciary) is re-parked, not cancelled. One piece of V1.2 work is deferred with
somewhere to point now: V1.2c authored no amendment content for
`parliamentary_republic` because Germany's two-thirds bar was unreachable, and
V1.2e's `deu_grand_coalition` start makes it reachable.

Save format is at **version 10**. There has never been a migration: a superseded
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
saved it. All three are checked in `tests/test_save_load.gd`, not argued in prose.

Styling rule since U3: colours and the type scale come from `ui_theme.gd`, set
per control with `theme_type_variation`. Never `add_theme_stylebox_override()` or
`add_theme_font_size_override()` in a panel — `tests/test_ui_theme.gd` fails on
it. Separation and margin constants stay at their call sites; they are layout.

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
convention is in [ROADMAP.md](ROADMAP.md). Verify against the session's
done-when list before claiming done.
