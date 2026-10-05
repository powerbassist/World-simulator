---
title: Engine Decision
tags:
  - decision
  - architecture
---

# Engine Decision

**Decision: Godot 4.x, using GDScript with static typing.**

## The requirements this is judged against

From [[scope]]:

1. PC only — Windows, Linux, macOS. No console, no mobile, no web.
2. Single-player. No networking of any kind.
3. 2D map plus dense, information-heavy UI. No 3D.
4. Simulation-heavy and data-heavy: dozens of nations, hundreds of laws and parties, thousands of numbers updating on a monthly tick.
5. Long-lived: economy, diplomacy, AI nations, events and more get added over years without the codebase collapsing.

Notably absent: rendering fidelity, physics, animation, asset pipelines, platform certification. Most of what a modern engine sells is irrelevant here.

## Candidates

### Godot 4.x

Free and open source under MIT. Roughly a 100 MB editor. 2D is a first-class renderer rather than a mode of the 3D one. Its UI system is built from `Control` nodes with anchors, containers and themes — the same system the editor itself is written in, which means it is genuinely capable of the kind of dense panel layout this game is entirely made of.

Two scripting options: **GDScript**, a Python-like language purpose-built for the engine with no compile step, and **C#**, via .NET.

### Unity 6

The industry default. Enormously mature, C#, vast learning material, and UI Toolkit is a competent modern UI system. It will unquestionably do this job.

The costs are weight and trust. The editor is heavy and brings a large amount of machinery — render pipelines, asset importers, platform modules — that a 2D map-and-panels game never touches. And the 2023 runtime-fee episode, though rescinded, established that the licensing terms of a proprietary engine can change under a project mid-flight. For a multi-year hobby-scale project, MIT is worth more than "probably fine".

### Unreal Engine 5

C++ and Blueprints, architected around high-end 3D. UMG is workable for UI but is not where the engine's strength lies. Heavy editor, long compile cycles, and 5% royalties past a revenue threshold.

For a 2D data-driven simulation this is the wrong instrument. It is included for completeness and ruled out quickly.

## Tradeoffs

| | Godot 4 | Unity 6 | Unreal 5 |
|---|---|---|---|
| **Dev speed** | Fastest here. No compile step in GDScript; edit, run, see it. Small editor, fast startup. | Good, but C# domain reloads and a heavier editor add friction to every iteration. | Slowest. C++ compile cycles measured in minutes. |
| **Complexity** | Low. Small engine, small API surface, little to ignore. | High. Large amounts of subsystem you must learn to route around. | Very high. |
| **Fit: simulation-heavy / data-heavy** | Good. Plain-object simulation in GDScript, JSON content, no engine involvement in the sim layer at all. | Good. C# is genuinely better for heavy computation, and ECS exists if ever needed. | Adequate, but the engine actively wants to own your data model. |
| **Fit: 2D map + dense UI** | Best. `Control` nodes, containers and themes are the engine's own UI system. | Good. UI Toolkit is capable but is a newer, less-settled layer. | Weakest. UMG is designed for game HUDs, not spreadsheets. |
| **Licensing** | MIT. No royalties, no revenue thresholds, no terms that can change. | Proprietary, free under a revenue threshold. Terms have changed before. | Proprietary, 5% royalty past threshold. |
| **Maintainability** | Good, with discipline. Scene tree encourages modularity; nothing enforces it. | Good. Strong typing and tooling help on large codebases. | Good at scale, at high complexity cost. |
| **PC export** | Trivial for all three targets. | Trivial. | Trivial, large binaries. |
| **Risk** | Smaller ecosystem; some third-party gaps you would fill yourself. | Vendor and licensing risk. | Wrong-tool risk. |

## Why Godot wins

Every requirement points at "small 2D engine with excellent UI, no licensing risk, fast iteration". Unity's advantages — raw compute headroom, ecosystem breadth, mature 3D — are advantages in areas this project does not go. Paying weight and vendor risk for capability you will never use is the definition of a bad trade.

The one place Unity is genuinely better is heavy computation. That is worth taking seriously, and the answer is in the next section.

## Why GDScript, not C#

GDScript is the default path: no compile step, no .NET toolchain, tightest editor integration, and the largest share of Godot documentation and community answers. Static typing (`var gdp: float`) gives most of the safety benefit a TypeScript developer expects, and the engine warns on inferred-type mismatches.

The obvious objection is performance. GDScript is meaningfully slower than C# — but the relevant question is not "which is faster", it is "is the slower one fast enough". The MVP simulation is arithmetic over ten nations on a monthly tick. Even at the full [[someday]] scale of ~195 nations with regional breakdown, this is tens of thousands of floating-point operations twelve times per simulated year, against a 60 fps frame budget of 16 milliseconds. That is orders of magnitude below anything approaching a wall.

**C# stays available as an escape hatch** — Godot supports both in the same project — but only for a hot loop identified by an actual profiler run. Choosing it preemptively costs a build step on every project for a performance problem that does not exist.

> [!note] Reversibility
> This is not a locked door. The simulation layer is designed to be plain data and plain functions with no engine dependency, so porting it is a rewrite of one layer rather than of the game. That property is worth more than getting the language choice perfectly right.

> [!warning] Gotcha — a class can't reference its own `class_name` on first run
> A script that uses its own `class_name` inside its own body — `Foo.new()` or a
> `-> Foo` return type inside a method of `class_name Foo` — fails with
> `Identifier not found` the first time the project loads, before
> `.godot/global_script_class_cache.cfg` exists (fresh checkout, CI, a bare
> `godot --headless --script` run with no prior editor session). Confirmed in S1.
> Use bare `new()` for self-instantiation and skip the self-referencing return-type
> annotation; for *cross-file* references, `const Foo = preload("res://path/foo.gd")`
> sidesteps the same cache dependency entirely and is the safer default throughout.

> [!warning] Gotcha — a `Control` outside the scene tree is half-dead
> In a `godot --headless --script` run there is no scene loaded, so a node you
> build and `add_child()` to `root` during `_init()` is **not yet inside the
> tree**. Two consequences, both silent:
>
> - `_ready()` has not run, so anything it builds is `null`.
> - `Range.value_changed` does **not** emit. Setting `slider.value = 28.0`
>   updates the number and fires nothing.
>
> The second is the dangerous one: a UI test that sets slider values outside the
> tree passes against a panel whose signals were never connected. Confirmed in
> S4 on 4.7.1.
>
> The fix is to drive the test a frame at a time. `extends SceneTree` can
> override MainLoop's `func _process(delta: float) -> bool` — do the setup on
> frame 1, act on frame 2, assert on frame 3. `tests/test_budget_panel.gd` and
> `tests/test_game_loop.gd` both use this shape.

## Maintainability and scalability

The stated risk is real: a project that accretes economy, diplomacy, AI nations, and events over years turns into spaghetti unless the structure resists it. Three rules do most of the work.

### Rule 1 — Content lives in data, not code

No nation, law, party, political system or company is ever written as a code branch. They are JSON files that the game loads and interprets. Adding France's twelfth party, or a new law, or eventually Poland, is a data edit and touches no code.

Concretely: there is never a `if nation_id == "FRA"` anywhere in the codebase. If France needs to behave differently, that difference is a field in France's data file and a general rule that reads the field.

Full specification in [[data-architecture]].

### Rule 2 — One-way dependencies

```
data files  →  simulation  →  presentation
```

- **Simulation** knows about data. It does not know the UI exists — no node references, no signals into scenes, no `get_node()`.
- **Presentation** reads simulation state and sends player intent back as explicit commands. It never mutates simulation state directly.
- Nothing flows backward.

The test: it must be possible to run a full ten-year simulation from a headless script with no scene tree. If that stops working, a dependency has leaked, and it is caught immediately rather than in year two.

### Rule 3 — One system, one module, one clear job

Each simulation system is a separate module with a narrow public surface — usually a single `tick()` and a handful of queries. Systems communicate through the shared game state object, not by calling into each other.

```
res://
├── data/                  static content — JSON, hand-editable
│   ├── nations/
│   ├── parties/
│   ├── laws/
│   ├── political-systems/
│   ├── companies/
│   └── geo/
├── src/
│   ├── core/              game state, clock, save/load, data loader
│   ├── sim/               one file per system, no UI knowledge
│   │   ├── economy.gd
│   │   ├── budget.gd
│   │   ├── opinion.gd
│   │   ├── legislature.gd
│   │   ├── elections.gd
│   │   ├── diplomacy.gd      (V1)
│   │   ├── companies.gd      (V1)
│   │   └── events.gd         (V1)
│   ├── ai/                nation AI, separate from the sim it observes
│   └── ui/                scenes and panels, read-only over sim state
├── tools/                 import scripts, validators — not shipped
└── tests/                 headless sim tests
```

A file growing past a few hundred lines is a signal it is doing more than one job. Split it then, not after.

### What this deliberately does not do

No dependency injection container. No event bus. No abstract base classes for a single implementation. No plugin architecture. These are the standard ways a simulation codebase becomes unnavigable while feeling well-engineered. The rules above are enough, and they are enforceable by reading the code rather than by trusting a framework.

---

Related: [[index]] · [[scope]] · [[data-architecture]]
