---
title: Tooling
tags:
  - tooling
  - setup
---

# Tooling

Machine setup. Not game code — none of this ships.

## Godot

**4.7.1-stable**, installed with winget rather than the portable zip, so upgrades are a command rather than a manual re-download.

```bash
winget install --id GodotEngine.GodotEngine --exact
```

Non-Mono build. The project is GDScript-only per [[engine-decision]]; the Mono build adds a .NET toolchain for nothing.

Binary lands at `%LOCALAPPDATA%\Microsoft\WinGet\Links\godot.exe` and is on `PATH` as `godot`. Upgrade with `winget upgrade --id GodotEngine.GodotEngine`.

`project.godot` pins `config/features` to `4.7`. Bump that line deliberately when the engine moves, and re-run the tests before committing the bump.

> [!note] Why 4.7 and not the 4.3 S0 started on
> [[ROADMAP|Session S0]] scaffolded against 4.3. The Godot MCP server below requires 4.4+, which forced the upgrade. S1's tests passed unchanged on 4.7.1 against a fresh `.godot` cache, so nothing was owed for the jump.

## Godot MCP

[mkdevkit/godot-mcp](https://github.com/mkdevkit/godot-mcp) — 173 tools that let an AI assistant drive the Godot editor: read the scene tree, create and attach scripts, run scenes, take screenshots, simulate input, inspect live game state.

Architecture is three pieces: a Node.js MCP server speaking stdio to the AI client, a WebSocket link on port 6505, and a Godot editor plugin that executes the commands.

### Install

The server is cloned **outside the project**, at `~/.mcp/godot-mcp`, and registered at user scope so it is available in every project:

```bash
git clone --depth 1 https://github.com/mkdevkit/godot-mcp.git ~/.mcp/godot-mcp
cd ~/.mcp/godot-mcp/server && npm install && npm run build
claude mcp add --scope user godot-mcp --env GODOT_MCP_PORT=6505 \
  -- node "C:/Users/<you>/.mcp/godot-mcp/server/build/index.js"
```

The editor plugin has to live inside the project, because that is how Godot loads addons:

```bash
cp -r ~/.mcp/godot-mcp/addons/godot_mcp "<repo>/addons/"
```

### Why `addons/` is gitignored

The addon is third-party tooling, not game code. Vendoring 35 files of an actively-moving repository into the game repo means owning its updates and reading its diffs forever, in exchange for saving one `cp` on a machine that will only ever be set up once.

`project.godot` **does** keep the `[editor_plugins]` enable line. If the addon is missing, Godot logs a warning and skips it — non-fatal, unlike a missing autoload would be.

### Using it

The MCP server only does anything while **the Godot editor is open on this project**. With the editor closed, every tool call fails on the WebSocket connection. Open the editor first, then ask.

Runtime tools — `get_game_scene_tree`, `click_button_by_text`, `capture_frames` — additionally need the scene to be playing, and depend on three autoloads the plugin injects on enable.

The three autoloads are **transient**, and that is the whole mechanism worth understanding. `addons/godot_mcp/plugin.gd` injects them in `_enter_tree()` and removes them in `_exit_tree()`, so they exist for exactly as long as an editor session does:

```gdscript
const AUTOLOADS: Array[Array] = [
	["autoload/MCPRuntimeBridge", "res://addons/godot_mcp/services/mcp_runtime_bridge.gd"],
	...
]
```

> [!warning] Gotcha — `--headless --editor --quit` strips the autoloads
> Running the editor headless to force a reimport enables the plugin, then immediately stops it, and the cleanup removes the injected autoloads from `project.godot`. Harmless for import and test runs, but do not expect runtime MCP tools to work in that state. A normal editor session restores them.

> [!warning] Gotcha, the inverse — a killed editor leaves them behind, and they must not be committed
> `_exit_tree()` only runs on a **clean** close. Kill the editor, or let a
> background launch die, and the `[autoload]` block stays in `project.godot`.
> Committing it is the thing to avoid: those paths point into gitignored
> `addons/`, so a fresh clone gets three autoloads whose scripts do not exist —
> which is exactly the failure mode the `[editor_plugins]` line above is
> deliberately kept *instead of*.
>
> There is nothing to preserve, since the plugin re-injects on the next open. If
> the block is in a diff, either close the editor cleanly and let the plugin
> remove it, or delete it by hand while the editor is shut. Check
> `git diff project.godot` after any editor session.

> [!warning] Gotcha — `simulate_key` and friends are broken, and fail *silently*
> Every input tool (`simulate_key`, `simulate_mouse_click`, `simulate_action`,
> `simulate_sequence`) is a no-op against the running game, and each returns
> `{"queued": true}` regardless. The chain, in the addon:
>
> ```
> input_commands.gd:_simulate_key    -> returns _ok({"queued": true}) unconditionally
> base_commands.gd:_queue_input      -> `if bridge:` ... silently no-ops when null
> base_commands.gd:_get_input_bridge -> get_node_or_null("/root/MCPInputBridge")
> ```
>
> That lookup runs in the **editor** process, and `mcp_input_bridge.gd` carries
> no `@tool` annotation — so the autoload's script never runs there and the node
> is never available. The guard is therefore always false.
>
> Screenshots and `get_scene_tree` work because they do **not** go through that
> node lookup: `_request_screenshot` and `_send_runtime_request` write a request
> *file* and let the game-side autoload pick it up. Input is the one path that
> reaches for a node instead of a file. That asymmetry is the whole diagnosis —
> "screenshots work, so the bridge is up" is the wrong inference.
>
> **Use `tools/send_input.py` instead**, which writes the queue file directly:
>
> ```bash
> python tools/send_input.py key ENTER
> ```
>
> It lives in `tools/` rather than as a patch to `addons/godot_mcp/` because
> `addons/*` is gitignored and reinstalled per machine — a patch there is lost
> on the next reinstall and invisible to the repo. Prefer `key` over `click`:
> the bridge's "mouse_click" branch reuses one event object for press and
> release, so a click lands as hover without activating. Full argument in the
> script's own docstring.

### Known state

`npm audit` reports 2 moderate advisories, both in the MCP SDK's HTTP transport dependency chain (`hono`). This server runs over **stdio**, so that code path is not reachable. Non-blocking; re-check after an SDK bump.

## mcp-compressor

[atlassian-labs/mcp-compressor](https://github.com/atlassian-labs/mcp-compressor) — a stdio proxy that sits in front of an MCP server and collapses its tool list into two: `get_tool_schema` and `invoke_tool`. The client sees a small surface up front and fetches a tool's full schema only when it is about to call it.

Installed once, applied to **godot-mcp only**:

```bash
pip install mcp-compressor
```

The wheel installs to `%APPDATA%\Python\Python313\Scripts\`, off `PATH`. Referenced by full path in the MCP registration below rather than adding it to `PATH` — one fewer thing to keep track of on a machine with several Python install locations.

### Why godot-mcp and not godot-docs

godot-mcp lists **173 tools**; its `tools/list` payload measured **52,634 bytes** raw versus **14,267 bytes** through the compressor at `medium` — and more importantly, 173 individually-declared tool schemas collapse to 2. That is the actual cost this tool removes: a client loads every connected server's full tool list up front, and 173 schemas is real weight before a single tool has been called.

godot-docs already exposes 2 tools. Wrapping it saves nothing on the list, and its real cost — `get_documentation_file` returning uncompressed files past 200 KB — is a per-call payload problem the compressor's tool-list collapsing does not touch. Left direct.

### Registration

```bash
claude mcp add --scope user godot-mcp --env GODOT_MCP_PORT=6505 \
  -- "C:/Users/<you>/AppData/Roaming/Python/Python313/Scripts/mcp-compressor.exe" \
  -c medium -- node "C:/Users/<you>/.mcp/godot-mcp/server/build/index.js"
```

Same effect as calling `godot-mcp`'s tools directly — `invoke_tool` forwards to the real tool name and arguments — just discovered in two steps instead of one.

> [!warning] Consequence — tool names are no longer searchable
> Since the compressor collapses 173 tools to `get_tool_schema` / `invoke_tool`, a
> session (or a subagent) that does `ToolSearch("add_node")` finds nothing. Call
> `get_tool_schema` first to see what exists, then `invoke_tool` by name. This is
> permanent behaviour, not a bug — flagged here because it looks exactly like the
> server being unavailable.

> [!warning] Gotcha — one session at a time, and the compressor turns a partial
> failure into total silence
> The Node.js server behind the plugin binds a **fixed port (6505)**. Only one
> instance can hold it. Two Claude Code windows both connecting to `godot-mcp`
> race for it; the loser's backend dies on `EADDRINUSE`.
>
> Without the compressor that would surface as individual tool calls failing.
> **With it, the compressor's own `initialize` depends on that backend coming up
> first** — so on collision the whole server, not just a tool call, fails to
> appear. From inside the session it looks exactly like godot-mcp was never
> registered, which is the confusing part.
>
> Practical rule: **one window using `godot-mcp` at a time.** Between roadmap
> sessions, `/clear` inside the same window rather than opening a new one — it
> resets context without dropping the MCP connection or re-fighting for the port.
> If a connection does go stale, `tasklist | grep node` / `grep mcp-compressor`
> and kill orphans, then `netstat -ano | grep 6505` to confirm the port is free
> before reconnecting.

## Godot docs MCP

[Nihilantropy/godot-mcp-docs](https://github.com/Nihilantropy/godot-mcp-docs) — the full official Godot documentation, served locally. Two tools: `get_documentation_tree` and `get_documentation_file`.

Chosen because it does not overlap the editor bridge at all. One drives the editor, the other answers "how does `Control` anchoring actually work" without a web round-trip or a guess from stale model memory.

### Install

Runs in Docker, registered at user scope:

```bash
git clone --depth 1 https://github.com/Nihilantropy/godot-mcp-docs.git ~/.mcp/godot-mcp-docs
cd ~/.mcp/godot-mcp-docs
docker build -f deploy/Dockerfile -t godot-mcp-docs:local .
claude mcp add --scope user godot-docs -- docker run --rm -i godot-mcp-docs:local
```

The build downloads `godot-docs` **master** and converts it with pandoc — 1604 markdown files baked into the image. Docs are therefore current as of the build date, not as of the repo's last commit.

Refresh when the engine moves:

```bash
docker build -f deploy/Dockerfile -t godot-mcp-docs:local ~/.mcp/godot-mcp-docs --no-cache
```

> [!warning] `get_documentation_file` returns whole files, with no search and no pagination
> The big class references are enormous — `classes/class_control.md` alone is **232 KB**, roughly 60k tokens in a single tool call. Fetching two or three of those will fill a context window on its own.
>
> Use `get_documentation_tree` to find the narrowest file that answers the question, and prefer the focused tutorial pages (`tutorials/ui/…`) over the class reference when either would do. For a single property or method, plain model knowledge or a targeted web search is usually the cheaper tool.

Pandoc conversion leaves RST artefacts in the output — `{.interpreted-text role="ref"}` around cross-references. Noisy, still readable.

## Editor addons

`addons/` is gitignored, so this is the only record of what is installed. All of these came from the Godot Asset Library and are reinstalled per machine.

Only `godot_mcp` is **enabled** — `project.godot`'s `[editor_plugins]` lists it alone. The rest are installed and dormant, which costs nothing until one is switched on.

| Addon | What it is | Where it could land |
|---|---|---|
| `at-icons` | Icon pack, MIT, icons by Voxy | **Now.** The tab rail is text-only. See below for the committing rule |
| `dialogue_manager` | Branching dialogue trees with choices | Plausibly [[v1\|V1.8]] Events. Nothing before it has dialogue |
| `limboai` | Behaviour trees and hierarchical state machines | Would be V1.3 nation AI — but see the collision below |
| `materialLayers` | Layered PBR material authoring, 3D | Nowhere, unless [[scope]]'s "no 3D" constraint changes |
| `road-generator` | Procedural 3D road meshes along curves | Same |
| `godot_mcp`, `godot_mcp_toolkit` | The editor bridge above | In use |

One more is **not** in `addons/` at all, because it is not an addon: `MapCamera2D` is a single 255-line `Camera2D` subclass adding zoom, pan and drag. No `plugin.cfg`, no autoload, no GDExtension, and the UI layer is allowed to be scene-tree bound — so it is vendored and committed at `src/ui/vendor/MapCamera2D.gd` rather than ignored, with its MIT licence beside it.

> [!warning] It unpacked a bare `LICENSE` into the project root
> Asset Library downloads do not all land under `addons/`. This one dropped
> `MapCamera2D.gd` and a root `LICENSE` reading "Copyright (c) 2024 Julian Vos".
> A root `LICENSE` states the licence of **this** project, so it was renamed to
> `MapCamera2D.LICENSE.txt` and moved next to the file it covers. Worth checking
> the repo root after any Asset Library install — `road_demos/`, `demo/` and the
> `@icons` picker page all landed there too, and are gitignored.

### The committing rule, and why `at-icons` is special

`addons/` is ignored, but an **asset a scene preloads is not tooling**. A missing plugin is a warning Godot skips; a missing icon a panel preloads is a hard load failure on a fresh clone, and `tools/run_tests.sh` runs headless straight from the repo.

So `.gitignore` carves out `at-icons`, and each icon `src/` actually references is committed at its `res://` path:

```bash
git add -f addons/at-icons/control/<icon>.svg
```

Its MIT licence is committed alongside, and `ATTRIBUTION.md` credits it. **Nothing under `src/` may reference an addon file that is not committed** — that is the whole rule, and it replaced a vaguer "no plugins in the game code" line in [CLAUDE.md](../CLAUDE.md).

> [!warning] LimboAI cannot hold the nation AI, and the reason is structural
> Behaviour trees are the obvious tool for [[v1|V1.3]]'s AI foreign policy, which
> that block itself calls "the actual hard part". LimboAI is the wrong vehicle
> here anyway: `BTTask` and `BTPlayer` are `Node`-derived and run inside the
> scene tree, and nation AI lives in `src/sim/`, which
> [[engine-decision|Rule 2]] tests by requiring **a full ten-year run headless
> with no scene tree**. `tools/run_tests.sh` runs `--headless --script`.
>
> Using it would mean either moving simulation logic into the scene tree — the
> one thing the architecture is tested against — or running two AI systems. It
> also ships as a GDExtension in most builds, which pins to the engine version
> and fights the deliberate `4.7.1` pin.
>
> Written down here so a V1.3 session does not rediscover it after wiring half a
> tree. If behaviour trees are wanted, the plain-GDScript version is a few
> hundred lines of `RefCounted` and stays headless.

`materialLayers` and `road-generator` both assume 3D. [[scope]] fixes "2D map plus dense UI panels, no 3D" as a constraint everything else is designed around, so neither has a use path without changing that — noted rather than judged; they cost nothing sitting there.

## `tools/screenshot.gd` is CRLF where the rest of the tree is LF

Noted because a scripted text edit against it fails **silently**: a
search-and-replace written with LF endings simply matches nothing, and the tool
goes on running with the old behaviour while the session believes the flag was
added. Use an editor that matches the file's real bytes. `tools/balance_probe.gd`
and `src/ui/budget_panel.gd` are the same.

## Deliberately not installed

Ten-plus other Godot MCP servers exist. Two are installed, and they were chosen to **not** overlap: one drives the editor, one serves docs.

The rest are near-duplicates of the editor bridge — the same APIs wrapped in different tool names. Every installed server's tool schemas compete for the same context budget, so a second editor bridge would add hundreds of ambiguous near-duplicate tools and buy nothing. 173 tools is already a large surface.

The rule: if a server is missing something, **replace** it with the one that has that capability. Do not stack servers that do the same job.

---

Related: [[index]] · [[engine-decision]] · [[ROADMAP]]
