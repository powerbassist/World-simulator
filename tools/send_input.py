#!/usr/bin/env python3
"""Send synthetic input to the running game, bypassing godot-mcp's broken path.

    python tools/send_input.py key ENTER
    python tools/send_input.py key DOWN
    python tools/send_input.py click 640 360
    python tools/send_input.py action ui_accept
    python tools/send_input.py key DOWN key DOWN key ENTER   # one batch, one frame

Why this exists rather than godot-mcp's `simulate_key`
------------------------------------------------------
`simulate_key` and its siblings are **structurally broken** for the running
game, and they fail silently -- they return `{"queued": true}` whether or not
anything was queued. The chain, in the addon:

    input_commands.gd:_simulate_key   -> returns _ok({"queued": true}) unconditionally
    base_commands.gd:_queue_input     -> `if bridge:` ... silently no-ops when null
    base_commands.gd:_get_input_bridge-> get_node_or_null("/root/MCPInputBridge")

That lookup runs in the **editor** process. `mcp_input_bridge.gd` carries no
`@tool` annotation, so the autoload's script never runs there and the node is
never available -- the `if bridge:` guard is therefore always false and every
input call is a no-op that reports success.

Screenshots and `get_scene_tree` work because they do NOT go through that node
lookup: `_request_screenshot` and `_send_runtime_request` write a request
*file* and let the game-side autoload pick it up. Input is the one path that
reaches for a node instead of a file.

The game-side consumer is fine. `mcp_input_bridge.gd:_process()` polls
`user://mcp_input_queue.json` every frame, applies each event through
`Input.parse_input_event()`, and deletes the file. This script writes that
file directly, which is the same thing the addon *intended* to do.

Deliberately in `tools/` rather than as a patch to `addons/godot_mcp/`:
`addons/*` is gitignored and reinstalled per machine (see docs/tooling.md), so
a patch there is lost on the next reinstall and is invisible to the repo. This
survives both.

Requires the game to be *playing* -- the queue is only drained by the running
game's `_process`. With the editor merely open, events pile up in the file and
apply the moment a scene starts.

> Prefer keyboard navigation over `click`.
>
> `click` is measurably unreliable, and it is a second bug in the same addon:
> `mcp_input_bridge.gd:_apply()`'s "mouse_click" branch builds ONE
> `InputEventMouseButton`, calls `Input.parse_input_event()` with
> `pressed = true`, then mutates `pressed = false` on that SAME object and
> parses it again. Godot may queue the event by reference, in which case both
> parses see `pressed = false` and no press is ever delivered. Observed
> behaviour matches: a `click` on a Button gives it the hover highlight but
> does not activate it.
>
> `key` is unaffected -- each press/release is its own dict here, so the
> bridge builds a separate `InputEventKey` for each. Drive menus with
> `key TAB` / `key DOWN` / `key ENTER`.
"""

from __future__ import annotations

import json
import os
import platform
import re
import sys
from pathlib import Path

# Godot 4 `Key` enum. Only the values worth naming -- anything else can be
# passed as a bare integer.
KEYCODES = {
    "ESCAPE": 4194305, "TAB": 4194306, "BACKTAB": 4194307, "BACKSPACE": 4194308,
    "ENTER": 4194309, "KP_ENTER": 4194310, "INSERT": 4194311, "DELETE": 4194312,
    "HOME": 4194317, "END": 4194318,
    "LEFT": 4194319, "UP": 4194320, "RIGHT": 4194321, "DOWN": 4194322,
    "PAGEUP": 4194323, "PAGEDOWN": 4194324,
    "SPACE": 32,
}
for _i in range(1, 13):
    KEYCODES[f"F{_i}"] = 4194332 + _i - 1
for _c in range(ord("A"), ord("Z") + 1):
    KEYCODES[chr(_c)] = _c
for _d in range(10):
    KEYCODES[str(_d)] = ord("0") + _d

QUEUE_FILE = "mcp_input_queue.json"


def project_name(repo_root: Path) -> str:
    """Read `config/name` out of project.godot, so the user:// path is derived
    rather than hardcoded -- the same value Godot itself keys the dir on."""
    text = (repo_root / "project.godot").read_text(encoding="utf-8")
    match = re.search(r'^config/name\s*=\s*"([^"]+)"', text, re.MULTILINE)
    if not match:
        sys.exit("project.godot has no config/name")
    return match.group(1)


def user_data_dir(name: str) -> Path:
    """Godot's OS.get_user_data_dir() for a project without a custom user dir."""
    system = platform.system()
    if system == "Windows":
        base = Path(os.environ["APPDATA"]) / "Godot"
    elif system == "Darwin":
        base = Path.home() / "Library" / "Application Support" / "Godot"
    else:
        base = Path(
            os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")
        ) / "godot"
    return base / "app_userdata" / name


def parse(argv: list[str]) -> list[dict]:
    """Turn the argument list into the event dicts mcp_input_bridge.gd applies.

    A `key` becomes a press AND a release. The bridge's own "key" handler emits
    exactly one event, so a lone press leaves the key stuck down -- its
    "mouse_click" handler does both internally and its "key" handler does not.
    """
    events: list[dict] = []
    i = 0
    while i < len(argv):
        verb = argv[i].lower()
        if verb == "key":
            token = argv[i + 1].upper()
            code = KEYCODES.get(token)
            if code is None:
                if not token.isdigit():
                    sys.exit(f"unknown key '{argv[i + 1]}'; known: {sorted(KEYCODES)}")
                code = int(token)
            events.append({"type": "key", "keycode": code, "pressed": True})
            events.append({"type": "key", "keycode": code, "pressed": False})
            i += 2
        elif verb == "click":
            events.append({
                "type": "mouse_click",
                "x": float(argv[i + 1]), "y": float(argv[i + 2]),
                "button": 1,
            })
            i += 3
        elif verb == "move":
            events.append({
                "type": "mouse_move",
                "x": float(argv[i + 1]), "y": float(argv[i + 2]),
            })
            i += 3
        elif verb == "action":
            events.append({"type": "action", "action": argv[i + 1], "pressed": True})
            events.append({"type": "action", "action": argv[i + 1], "pressed": False})
            i += 2
        else:
            sys.exit(f"unknown verb '{argv[i]}' -- expected key/click/move/action")
    return events


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)

    repo_root = Path(__file__).resolve().parent.parent
    events = parse(sys.argv[1:])

    path = user_data_dir(project_name(repo_root)) / QUEUE_FILE
    path.parent.mkdir(parents=True, exist_ok=True)

    # Append, matching mcp_input_bridge.gd:queue_events() -- a second call
    # before the game has drained the first must not discard it.
    existing: list = []
    if path.exists():
        try:
            parsed = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(parsed, list):
                existing = parsed
        except json.JSONDecodeError:
            pass  # a half-written file the game is mid-read on; start clean

    path.write_text(json.dumps(existing + events), encoding="utf-8")
    print(f"queued {len(events)} event(s) -> {path}")


if __name__ == "__main__":
    main()
