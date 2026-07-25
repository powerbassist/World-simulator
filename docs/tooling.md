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

> [!warning] Gotcha — `--headless --editor --quit` strips the autoloads
> Running the editor headless to force a reimport enables the plugin, then immediately stops it, and the cleanup removes the injected autoloads from `project.godot`. Harmless for import and test runs, but do not expect runtime MCP tools to work in that state. A normal editor session restores them.

### Known state

`npm audit` reports 2 moderate advisories, both in the MCP SDK's HTTP transport dependency chain (`hono`). This server runs over **stdio**, so that code path is not reachable. Non-blocking; re-check after an SDK bump.

## Deliberately not installed

Ten-plus other Godot MCP servers exist. Only one is installed, on purpose.

They overlap almost entirely — the same editor APIs wrapped in different tool names — and every installed server's tool schemas compete for the same context budget. A second Godot MCP would add hundreds of near-duplicate tools, make tool selection ambiguous, and buy close to nothing. 173 tools is already a large surface.

If godot-mcp turns out to be missing something specific, the move is to replace it with the server that has that capability, not to run both.

---

Related: [[index]] · [[engine-decision]] · [[ROADMAP]]
