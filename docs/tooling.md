---
title: Tooling
tags:
  - tooling
  - setup
---

# Tooling

Machine setup. Not game code — none of this ships.

## Godot

**4.7.2-stable**, installed with winget rather than the portable zip, so upgrades are a command rather than a manual re-download.

```bash
winget install --id GodotEngine.GodotEngine --exact
```

Non-Mono build. The project is GDScript-only per [[engine-decision]]; the Mono build adds a .NET toolchain for nothing.

Binary lands at `%LOCALAPPDATA%\Microsoft\WinGet\Links\godot.exe` and is on `PATH` as `godot`. Upgrade with `winget upgrade --id GodotEngine.GodotEngine`.

`project.godot` pins `config/features` to `4.7`. Bump that line deliberately when the engine moves, and re-run the tests before committing the bump.

> [!note] Why 4.7 and not the 4.3 S0 started on
> Session S0 scaffolded against 4.3. The MCP editor bridge of the day (mkdevkit/godot-mcp, since replaced) required 4.4+, which forced the upgrade. S1's tests passed unchanged on 4.7.1 against a fresh `.godot` cache, so nothing was owed for the jump.

## Godot MCP

[NPGameDev/godot-mcp-toolkit](https://github.com/NPGameDev/godot-mcp-toolkit) — a Godot editor plugin plus an npm bridge that let an AI assistant read the scene tree, edit scripts, launch a playtest, screenshot the running game, inspect live nodes and inject input.

Architecture is three pieces, and the direction of the arrows is the whole point:

```
Claude Code  <--stdio-->  npm bridge (client)  --WS-->  Godot editor  :6550-6560
                                               --WS-->  running game :6570-6585
```

**Each Godot process owns its listener; the bridge dials in.** That is the opposite of what this project ran before, and it is why the setup is no longer fragile — see the box at the end of this section.

### Install

Bridge, installed globally once so no call ever waits on the npm registry:

```bash
npm install -g @npgamedev/godot-mcp-server
```

The editor plugin has to live inside the project, because that is how Godot loads addons. It goes in `addons/godot_mcp_toolkit/` and is enabled in Project Settings → Plugins.

Register the bridge in a project-root `.mcp.json` — either from the plugin's own **Project → Tools → MCP Toolkit → Write .mcp.json**, or by hand:

```json
{
  "mcpServers": {
    "godot-mcp-toolkit": {
      "command": "node",
      "args": ["C:/Users/<you>/AppData/Roaming/npm/node_modules/@npgamedev/godot-mcp-server/dist/index.js"],
      "env": {
        "GODOT_MCP_CONFIG_VERSION": "1",
        "GODOT_MCP_EDITOR_PORT": "6550"
      }
    }
  }
}
```

`node <absolute path>` rather than the `cmd /c npx -y @npgamedev/godot-mcp-server` the plugin writes by default: `npx` resolves the package at every launch, which is a network dependency, and it measured ~11 s of startup against instant. The plugin's health check reads the entry's `env` and never compares `command`/`args`, so the dock stays green on either form.

`.mcp.json` is **gitignored** — it names an absolute path to a global npm install, and the addon it talks to is gitignored too.

### The autoload is a LOCAL step, and it is not committed

Enabling the plugin makes Godot write an autoload into `project.godot`:

```
[autoload]

MCPRuntimeServer="*res://addons/godot_mcp_toolkit/runtime/mcp_runtime_server.gd"
```

**That line must not be committed**, and this is the one step of the install that a
clone cannot inherit. `addons/` is gitignored except `dialogue_manager/`, so on any other
machine the path does not exist and Godot logs three errors *per startup* — including
every `tools/run_tests.sh` run, which still exits 0, which is exactly why it went
unnoticed for a year. That was **V5** in [[playability-audit]], the one finding a new
contributor meets before they have played anything.

It is also two of AGENTS.md's own rules at once: *no autoloads in the game code*, and
*`src/` may reference an addon file only if that file is committed*.

So:

- **The committed `project.godot` has no `[autoload]` section at all.**
- **Your working copy will keep re-growing one**, because the plugin rewrites the file
  whenever it is enabled. Leave it there — it is what publishes the runtime port the
  bridge dials into. Just never stage it.
- `bash tools/check_mcp.sh` checks exactly this, against **the staged file when
  something is staged** and against `HEAD` otherwise, so it catches the mistake at the
  moment it would be made rather than after the push.

The same argument applies to the `[editor_plugins]` `enabled=` line, and it is **left
committed on purpose**: a missing editor plugin is inert under `--headless --script`, so
it costs a clone nothing on the path that matters, and the line is what tells a new
machine which addon this project expects. An autoload is loaded by every process; an
editor plugin is not.

### Preflight

```bash
bash tools/check_mcp.sh
```

One line per check, no log dumps, exit 1 only when the bridge genuinely cannot run. It validates the node version, the registration and its entry point, the addon and the enable line, the machine registry (including a **stale entry naming a dead pid**, which a force-killed game leaves behind), the auth token, the port pin against the port the editor actually bound, and what is really listening in both bands.

Godot being closed is reported, never failed — that is a normal state, not a broken one.

### Using it

**The editor must be open.** Runtime tools reach the game through the editor channel, so a game launched standalone with `godot --path` publishes a runtime port the bridge cannot route to on its own.

**Re-enabling a plugin that went dark** (measured 2026-10-20): with the editor CLOSED, hand-edit the LOCAL `project.godot` -- the `MCPRuntimeServer` autoload line and `res://addons/godot_mcp_toolkit/plugin.cfg` in `[editor_plugins] enabled=` -- or tick it in Project Settings → Plugins; never commit either. An `AUTH_FAILED` "auth timeout" on the first call from a session that started before the editor was up is transient: retry it.

The loop for looking at the running game:

```
game_start           scene_path:"main", if_running:"return"
discover_tools       request:"runtime"        # activates runtime_get_node_state etc.
runtime_screenshot   image_response_mode:"disk", image_detail:"mid"
input_simulate       events:[...]
```

> [!important] Always screenshot to disk
> `image_response_mode:"disk"` returns a **path**; the default `"inline"` returns a base64 PNG that overflows the token limit on a 1920x1080 frame. `image_detail` (`full`/`mid`/`low`) caps the *inline* image's long edge at —/1024/512 and is echoed back, so a size reduction is never silent. The file on disk is always full resolution — `Read` it.

> [!warning] Gotcha — input arguments are strict, and a wrong shape reports success
> `input_simulate` returns `dispatched: true` for an event it built out of nothing, so **assert on the effect, not on the response**. Two shapes bite:
>
> - `keycode` is an **integer** Godot `KEY_*` value, not a name. `"Down"` parses to `0` and the key event goes nowhere. `KEY_DOWN` is `4194320`, `KEY_ENTER` is `4194309`.
> - `position` is a **dict**, not an array. `[960, 501]` falls through `_parse_mouse_position` to `Vector2.ZERO` and the click lands in the top-left corner. Use `{"x": 960, "y": 501}`.
>
> Both were measured here, and both looked exactly like the tool being broken. With the right shapes a click activates a real Button and a key press moves focus.

> [!warning] Gotcha — the plugin writes an autoload into `project.godot`, and it must not be committed
> Enabling the plugin registers `MCPRuntimeServer` under `[autoload]`, pointing into gitignored `addons/`. On a fresh clone that path does not exist. Measured: three `ERROR:` lines per process and the test still passes — noise rather than breakage, but 55 tests' worth of it. `tools/check_mcp.sh` warns when the autoload is in **what the next commit would contain** — the index if `project.godot` is staged, HEAD otherwise — so the working tree can legitimately carry it while the plugin is on. Still worth a glance at `git diff project.godot` after any editor session.
>
> Godot also **strips comments** from `project.godot` when it saves. The `[display]` block's note about the 1920x1080 base has been lost that way once; if the diff shows a comment disappearing, put it back.

> [!note] Why this replaced mkdevkit/godot-mcp and mcp-compressor
> The old stack was never usable, for four compounding reasons measured together:
>
> 1. **The port squat was self-perpetuating.** The Node server *hosted* the WebSocket on a fixed 6505 and the plugin dialled in, so only one Claude session could ever bind. On collision the server did not degrade — an unhandled `EADDRINUSE` killed it — and with no stdin-close handler the Node child outlived its parent and held the port forever. Every later session then died the same way.
> 2. **`mcp-compressor -c medium` collapsed all 173 tools into 3 meta-tools**, so no tool was reachable by name and `ToolSearch` found nothing. Measured 36.6 % of the raw list at `medium` against 36.7 % at `low` — the level was never the point.
> 3. **Three autoloads pointing at a gitignored addon were committed** in `project.godot`.
> 4. **Every input tool was a silent no-op** — the bridge node was looked up in the editor process, where its script has no `@tool` annotation and never runs, and each call returned `{"queued": true}` anyway. `tools/send_input.py` existed to work around exactly this and is deleted: `input_simulate` does the job, verified by effect.
>
> The toolkit inverts the ownership, which removes (1) structurally: a live process owns its port, an orphan cannot squat one, and any number of sessions can dial the same editor. A clean exit deregisters from the machine registry; a force-kill leaves a stale entry, which is what the preflight looks for.

> [!warning] Known bridge bug — why the editor port is pinned
> With the game running and the editor closed, the registry publishes the editor port as `-1`. Bridge 1.0.0 interpolates a discovered port straight into a URL, so `ws://127.0.0.1:-1` throws `ERR_INVALID_URL` and takes the **whole server** down at startup — which looks precisely like the server never being registered.
>
> `GODOT_MCP_EDITOR_PORT` in `.mcp.json` sidesteps it: with a pin the bridge never reads that field, and an unreachable editor becomes a retry loop with a named error instead of a crash. The cost is that the pin and the editor must agree — the editor scans `6550-6560` and takes the first free port, so it lands on 6550 unless something else holds it. `tools/check_mcp.sh` compares the two and says so.

## The in-game dev console (V5.1-0b)

F12 in a debug build (or any build started with `--dev-console`) opens a console over the game: an Errors tab fed by Godot's Logger, a `perf` overlay and a command table (`help` lists it). Dev only: a release build builds none of it. The design and the commands are in [[history]] (V5.1-0b).

**Driving the game from an agent.** The console node is `/root/Main/DevConsole` and has one method, `run_command(text) -> String`. A running game is not an edited scene, so `node_call_method` (editor-only) cannot reach it; use the runtime channel of `execute_code`, which takes an expression:

```
game_start       scene_path:"main", if_running:"return"
execute_code     channel:"runtime",
                 code:"get_node('/root/Main/DevConsole').call('run_command', 'skip 2')"
```

It returns what the console printed (`skipped 2 months -- now 2026-03-01`). The line and its answer also appear in the panel, so a human watching sees what the agent did. A command that changes the game answers `a month is closing -- try again in a moment` while a month runs across frames; retry. Reads (`get`, `person`, `errors`, `help`) answer at once.

Useful lines: `get me.deficit_pct_gdp`, `set me.gdp_eur_bn 3000`, `skip 12`, `term_start`, `event com_gas_squeeze`, `open budget`, `save` / `load`, `errors 20`. `set` takes a number, flag or text field of `src/core/nation_fields.gd` and settles on the next month's tick like any other change.

## The Windows build (`tools/export_windows.py`)

`build/NationSimulator.exe` + `NationSimulator.pck` (+ `NationSimulator.console.exe`, the same game with a console window that prints its log), built from the committed `export_presets.cfg` ("Windows Desktop", release, x86_64, unsigned, no secrets). Run the exe from the folder holding the `.pck`; nothing is installed. `build/` is gitignored.

**One-time: the export templates.** Download `Godot_v4.7.2-stable_export_templates.tpz` (about 1.3 GB) from the [official 4.7.2-stable release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable) together with its `SHA512-SUMS.txt`, check the hash (`sha512sum`), then unzip only `templates/version.txt` and `templates/windows_*_x86_64*.exe` into a folder of your own. Do not install them into `%APPDATA%\Godot`: the build points Godot at a private APPDATA, so the editor's user dir is untouched.

```bash
python tools/export_windows.py --templates PATH/TO/that/folder --smoke
```

`--smoke` then runs two checks, each in a private user dir, each failing on any `ERROR` line: the exe boots headless to the menu and quits (`--quit-after`), and `tools/exe_smoke.gd` runs under the stock engine with the PCK as its main pack (an export template ignores `--script`, measured on 4.7.2): the menu scene, the real New Game boot, a month, a save and load, and a voice clip, a music bed, a portrait, an icon, a font and the summit scenes, all read out of the PCK. The script also audits the PCK's own file list: no `tools/`, `tests/`, `docs/`, `reports/` or dev-console file, and every raw file the game reads is there. Headless throughout, so no window and no cursor.

**Why a stage.** The game reads its icons, audio and summit scenes as bytes or text, never `load()`, and an export keeps an imported file only as its converted form. The script builds a throwaway copy of the tracked tree and sets `importer="keep"` on those `.import` files in the COPY (the webp and jpg already use it), so the committed files do not change. A new asset kind the game reads as bytes needs its extension in `KEEP_EXT` there; the audit fails the build when a raw file is missing. The dev console (`dev_console.gd` and what only it loads) is excluded by the preset's filter; `main.gd` loads it behind `ResourceLoader.exists()`, so its absence is silent, and a release template has no debug build for it anyway.

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

Only `godot_mcp_toolkit` is **enabled** — `project.godot`'s `[editor_plugins]` lists it alone. The rest are installed and dormant, which costs nothing until one is switched on.

| Addon | What it is | Where it could land |
|---|---|---|
| `at-icons` | Icon pack, MIT, icons by Voxy | **Retired.** V5.1a's Material Symbols replaced its icons; V5.1-c removed the committed files |
| `dialogue_manager` | Branching dialogue trees with choices | Plausibly [[v1\|V1.8]] Events. Nothing before it has dialogue |
| `limboai` | Behaviour trees and hierarchical state machines | Would be V1.3 nation AI — but see the collision below |
| `materialLayers` | Layered PBR material authoring, 3D | Nowhere, unless [[scope]]'s "no 3D" constraint changes |
| `road-generator` | Procedural 3D road meshes along curves | Same |
| `godot_mcp_toolkit` | The editor bridge above | In use |

One more is **not** in `addons/` at all, because it is not an addon: `MapCamera2D` is a single 255-line `Camera2D` subclass adding zoom, pan and drag. No `plugin.cfg`, no autoload, no GDExtension, and the UI layer is allowed to be scene-tree bound — so it is vendored and committed at `src/ui/vendor/MapCamera2D.gd` rather than ignored, with its MIT licence beside it.

> [!warning] It unpacked a bare `LICENSE` into the project root
> Asset Library downloads do not all land under `addons/`. This one dropped
> `MapCamera2D.gd` and a root `LICENSE` reading "Copyright (c) 2024 Julian Vos".
> A root `LICENSE` states the licence of **this** project, so it was renamed to
> `MapCamera2D.LICENSE.txt` and moved next to the file it covers. Worth checking
> the repo root after any Asset Library install — `road_demos/`, `demo/` and the
> `@icons` picker page all landed there too, and are gitignored.

### The committing rule (at-icons was its first case)

`addons/` is ignored, but an **asset a scene preloads is not tooling**. A missing plugin is a warning Godot skips; a missing icon a panel preloads is a hard load failure on a fresh clone, and `tools/run_tests.sh` runs headless straight from the repo.

So an addon file `src/` references is committed at its `res://` path (`git add -f addons/<addon>/<file>`), its licence alongside and credited in `ATTRIBUTION.md`. `at-icons` was the first case, until V5.1a's Material Symbols replaced its icons and V5.1-c removed the files. **Nothing under `src/` may reference an addon file that is not committed** — that is the whole rule, and it replaced a vaguer "no plugins in the game code" line in [AGENTS.md](../AGENTS.md).

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
> and fights the deliberate `4.7.2` pin.
>
> Written down here so a V1.3 session does not rediscover it after wiring half a
> tree. If behaviour trees are wanted, the plain-GDScript version is a few
> hundred lines of `RefCounted` and stays headless.

`materialLayers` and `road-generator` both assume 3D. [[scope]] fixes "2D map plus dense UI panels, no 3D" as a constraint everything else is designed around, so neither has a use path without changing that — noted rather than judged; they cost nothing sitting there. **V3.4 settled `road-generator`'s case by building the thing it was parked for.** The road layer shipped as 2D lon/lat spines drawn straight into `map_view.gd`'s `_draw()`; the addon generates 3D meshes along splines and was never a candidate. See [data-sources.md](data-sources.md)'s `road-generator` callout for the full reasoning, recorded there so the addon's NAME cannot re-open a question its shape already closes.

## `tools/screenshot.gd` is CRLF where the rest of the tree is LF

Noted because a scripted text edit against it fails **silently**: a
search-and-replace written with LF endings simply matches nothing, and the tool
goes on running with the old behaviour while the session believes the flag was
added. Use an editor that matches the file's real bytes. `tools/balance_probe.gd`
and `src/ui/budget_panel.gd` are the same.

## Claude Code, in the repo

Four pieces are committed under `.claude/` and `tools/` so a worktree session and a fresh clone get them; the rest of that folder is per-machine (see `.gitignore`).

- **`tools/protect_files.py`**, a PreToolUse hook on `Edit|Write|MultiEdit` (wired in `.claude/settings.json`). It *denies* an edit to `.godot/**`, `reports/suite_runs/**` and `*.uid` (the engine or the runner writes them) and *asks* before `project.godot` or a `*.import` (a deliberate edit is sometimes right: an engine bump, an autoload fix). Paths are judged relative to the project root, so a `.claude/worktrees/` checkout is guarded the same way. The *staging* half of the same footgun is guarded at user level, not here.
- **`tools/lint_on_edit.py`**, a PostToolUse hook on `Edit|Write|MultiEdit`. After an edit it runs the lint that edit can break: `event_lint.py --check` for `data/events/`, `law_lint.py --check` for `data/laws/`, `i18n_extract.py --check` for every `data/` file (rows carry the translatable fields, so a renamed id strands a translation key) and `src/ui/*.gd` (the only `.gd` files that tool reads). A failure comes back as `additionalContext` for the next step. It never blocks (fail-open: a bad payload, a timeout or a missing script passes), starts no Godot, and judges the file against its own checkout (the nearest `project.godot`), so a worktree lints its own tree.
- **`tools/guard_commit_shards.py`**, a PreToolUse hook on `Bash`. On a `git commit` that stages a `tests/test_*.gd` (or names one on the same command line, as in `git add ... && git commit`) it runs CI's shard check, `bash tools/run_tests.sh --print-tests | python tools/ci_shards.py --check`, and answers `permissionDecision: "ask"` with the check's own output when it fails. That closes the recorded bite: a new test registered in `run_tests.sh` but absent from `tools/ci_shards.json` passes the local gate and fails CI. It never denies, and a missing `bash` passes. It reads the index of the checkout the commit runs in: a leading `cd <path> &&` and each `git -C <path>` are followed (a path it cannot resolve, such as a `$VAR`, falls back to the session's own root), so a test staged in a worktree is seen from a session elsewhere. Only `git [global options] commit` counts as a commit; `git log --grep commit`, `git commit-tree` and an alias named commit do not. The settings entry carries `"if": "Bash(git*commit*)"` so Python starts only for a command with a `git ... commit` subcommand in it (the harness checks each `&&`/`;` part separately); the filter is best-effort by the harness's own account, so the script repeats the match. The edit hook's timeout (50 s) covers the two lints an edit under `data/events/` or `data/laws/` runs.
- **`/block-closeout`** (`.claude/skills/block-closeout/SKILL.md`, user-invoked only). The gates AGENTS.md names, in order: tree state, `.uid` pairs, the suite, the cheap checks (names, size, vault, uids, reuse, the event, law and i18n lints, the voice selftest, the shard check), the balance probe for a sim or data change, the windowed screenshot for UI, scratch.

Hooks are read when a session starts, so a change to either takes effect in the next session. Test a script by piping it a payload: `echo '{"tool_input":{"file_path":"project.godot"},"cwd":"."}' | python tools/protect_files.py`. `lint_on_edit.py` and `guard_commit_shards.py` also take `--selftest` (their routing, no lint run). On Windows give them a real Windows path (`cygpath -m "$PWD"` in Git Bash): a `/f/Dev/...` path is read as relative to the current drive and the hook finds no project.

## The real mouse cursor

A windowed Godot run reads the OS cursor: `Viewport.get_mouse_position()` and every `Control.get_local_mouse_position()` are the real pointer, a pushed `InputEventMouseMotion` does not change them, and a `RichTextLabel`'s meta hover reads the OS cursor alone (measured on 4.7.2, windowed). Headless there is no cursor: `DisplayServer.mouse_get_position()` reads `(0, 0)` throughout, a warp is a no-op, and `tools/suite_runner.py` passes `--headless` for every test it runs. So the suite never moved the author's pointer; the windowed tools did.

- **One helper owns every move**: `tools/os_cursor.gd` (`const OsCursor = preload("res://tools/os_cursor.gd")`). `OsCursor.warp(viewport, at)` warps only when `NATION_OS_CURSOR=1` and the display is not headless, and returns whether it did. `tests/test_os_cursor.gd` fails the suite on any other call of the engine's warp function under `tests/`, `tools/` or `src/` (with a positive control for the scanner).
- **A capture does not need the pointer**: `OsCursor.quiet_window()` forces the window to `WINDOW_MODE_WINDOWED` (a fullscreen or maximized window ignores `window_set_position`; an un-isolated run reads the author's `settings.cfg`), moves it to (-30000, -30000) and reads the position back, returning whether it took. There it still renders and returns a correct viewport image, and no hand can reach it. It re-checks each call rather than remembering it moved once, because the saved settings are applied after a script's `_init` and can re-centre or re-fullscreen the window: `screenshot.gd`, `motion_frames.gd` and `label_probe.gd` call it every frame, and `tests/click.gd` on every half-click (a windowed click test: no real motion can land between a pushed press and release). A minimized window does not render (the readback came out blank), so it never minimizes. Not called by the timing probes (`frame_probe`, `month_frame_probe`, `placement_probe`, `boot_stages_probe`), whose numbers a moved window could change; those open a normal window.
- **A windowed run still takes the keyboard, unless it is created without activation, and that needs the author's go otherwise.** Moving the window does nothing for focus. Measured with a victim window holding the foreground and Godot launched as its child (the case Windows allows to steal): the Godot window became the foreground window in 3 of 7 launches, with or without the window off screen, and `window_is_focused()` said true throughout, so the author's keystrokes can go to a game they cannot see. Setting `WINDOW_FLAG_NO_FOCUS` from the script changed no Win32 style bit (it is applied after the window exists). What worked, 6 of 6 launches and `window_is_focused()` false: the project setting `display/window/size/no_focus=true`, which is read when the window is created, so it must be in an `override.cfg` beside `project.godot` before the launch. `tools/screenshot_all.py` writes one for the length of its run and deletes it after (`/override.cfg` is gitignored; a stale one leaves the game without keyboard focus, so delete it if a run was killed). Any other windowed launch (a direct `godot --path . --script res://tools/screenshot.gd`, a probe) takes the keyboard about 4 times in 10: do it only with the author's go, or write that same `override.cfg` for the run and remove it. The window also shows for the first moments of the boot, before a script can move it (`--position` is clamped onto a monitor), and a tool that boots the MENU has it put fullscreen on the nearest monitor by the menu's own `SettingsPanel.apply_saved()` (an isolated `APPDATA` has no `settings.cfg`, so the default, fullscreen, applies): `screenshot.gd` and `motion_frames.gd` call `quiet_window()` right after adding the scene to narrow that to the frames before the call, and again every frame (measured: `screenshot.gd --menu` frame 1920x1080, `motion_frames.gd` 6 captures all 1920x1080, 0 cursor teleports). The exposure that remains is those boot frames.
- **When the proof IS the pointer** (an RTL meta hover, a tooltip's popup `Window`): run with `NATION_OS_CURSOR=1` on the command line and say so in the report, while the author is away. The flag is never set by a script, a hook or CI.
- **Measure it, do not assume it**: `tools/screenshot.gd`'s two former warps are measured with a busy-polled cursor watcher (a "teleport" is two samples 400 px apart; a hand cannot do that); the old code produced one per run and the new produces none.

## Deliberately not installed

Ten-plus other Godot MCP servers exist. Two are installed, and they were chosen to **not** overlap: one drives the editor, one serves docs.

The rest are near-duplicates of the editor bridge — the same APIs wrapped in different tool names. Every installed server's tool schemas compete for the same context budget, so a second editor bridge would add hundreds of ambiguous near-duplicate tools and buy nothing. 173 tools is already a large surface.

The rule: if a server is missing something, **replace** it with the one that has that capability. Do not stack servers that do the same job.

---

Related: [[index]] · [[engine-decision]]
