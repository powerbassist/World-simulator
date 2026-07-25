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

## Deliberately not installed

Ten-plus other Godot MCP servers exist. Two are installed, and they were chosen to **not** overlap: one drives the editor, one serves docs.

The rest are near-duplicates of the editor bridge — the same APIs wrapped in different tool names. Every installed server's tool schemas compete for the same context budget, so a second editor bridge would add hundreds of ambiguous near-duplicate tools and buy nothing. 173 tools is already a large surface.

The rule: if a server is missing something, **replace** it with the one that has that capability. Do not stack servers that do the same job.

---

Related: [[index]] · [[engine-decision]] · [[ROADMAP]]
