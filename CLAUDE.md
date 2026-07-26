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
- No database, no autoloads, no plugins in the game code. JSON content, JSON saves.

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

**V1.1b shipped** — party discipline is live state in `ns.party_discipline`,
eroded by unpopularity and by an approaching legislative election and pulled back
by inertia; both vote resolvers split a party's seats when its line and its
members disagree; and a `DISAFFECTION` term in `Government.hostility()` lets an
eroded coalition bring its own government down, which is what finally makes the
censure branch fire in a played game. Model: [docs/discipline-model.md](docs/discipline-model.md).
MVP, V1.1a–b and U1–U4 are done.

**Next: V1.1c** — dissolution and snap elections. See [ROADMAP.md](ROADMAP.md).

Save format is at **version 3**. There has never been a migration: a superseded
save is refused outright, because a half-understood political state is worse than
a clear refusal.

Styling rule since U3: colours and the type scale come from `ui_theme.gd`, set
per control with `theme_type_variation`. Never `add_theme_stylebox_override()` or
`add_theme_font_size_override()` in a panel — `tests/test_ui_theme.gd` fails on
it. Separation and margin constants stay at their call sites; they are layout.

## Workflow

One session, one objective, a fresh chat each time. Commit at every session
boundary, and end each session by writing the next one's handoff prompt — the
convention is in [ROADMAP.md](ROADMAP.md). Verify against the session's
done-when list before claiming done.
