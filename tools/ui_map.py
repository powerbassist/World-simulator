#!/usr/bin/env python3
"""The map of the game's menus, generated from the code (docs/ui-map.md).

Nobody writes this page: where a screen lives is a fact of src/ui/, and a hand-kept
copy drifts with the first PR that adds a tab. It reads

  src/ui/domains.gd      the sidebar's domains and the tabs under each
  src/ui/**/*.gd         every `_windows.register(id, title, panel, key, icon, [also])`
                         call (the window id, its title, its hotkey and extra hotkeys,
                         the panel file), every `_stack.add(ScreenStack.RANK, panel, ...)`
                         and the screen stack's ranks, main.gd's own keys, the dev
                         console's key, and the doors (`open("id")` and kin) a window
                         is reached through from another panel

and writes docs/ui-map.md: a diagram of domain -> tab -> window id, a table with one
row per window, and the surfaces outside the domains.

    python tools/ui_map.py --write      regenerate docs/ui-map.md
    python tools/ui_map.py --check      exit 1 when the page is stale (CI)
    python tools/ui_map.py --selftest   the parser and the renderer on fake sources

Stdlib only. A panel it cannot resolve to a file is shown as `?`, never guessed.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UI = REPO / "src" / "ui"
OUT = REPO / "docs" / "ui-map.md"

REGISTER = re.compile(r"_windows\.register\(")
STACK_ADD = re.compile(r"_stack\.add\(\s*ScreenStack\.(\w+)\s*,\s*([^,)]+)")
DOOR = re.compile(r"\b(?:open|open_window|_toggle_window|toggle_window|show_window)\(\s*\"(\w+)\"")
CONST_PRELOAD = re.compile(r'^const\s+(\w+)\s*(?::=|=)\s*preload\("res://src/ui/(\w+\.gd)"\)', re.M)
CONST_STR = re.compile(r'^const\s+(\w+)\s*(?::=|=)\s*"([^"]*)"', re.M)


def split_args(text: str, start: int) -> list[str]:
    """The top-level arguments of the call whose '(' is at text[start - 1]."""
    args, depth, cur, quote = [], 1, [], ""
    i = start
    while i < len(text) and depth > 0:
        c = text[i]
        if quote:
            cur.append(c)
            if c == "\\":
                i += 1
                cur.append(text[i])
            elif c == quote:
                quote = ""
        elif c in "\"'":
            quote = c
            cur.append(c)
        elif c in "([{":
            depth += 1
            cur.append(c)
        elif c in ")]}":
            depth -= 1
            if depth > 0:
                cur.append(c)
        elif c == "," and depth == 1:
            args.append("".join(cur).strip())
            cur = []
        else:
            cur.append(c)
        i += 1
    last = "".join(cur).strip()
    if last:
        args.append(last)
    return args


def parse_domains(text: str) -> list[dict]:
    rows = []
    for m in re.finditer(r'\{"id":\s*"(\w+)",\s*"title":\s*"([^"]*)",[^\n]*?"tabs":\s*\[([^\]]*)\]', text):
        rows.append({"id": m.group(1), "title": m.group(2),
                     "tabs": re.findall(r'"(\w+)"', m.group(3))})
    return rows


def parse_scenes(text: str) -> list[str]:
    m = re.search(r"^const SCENES\s*:?=\s*\[([^\]]*)\]", text, re.M)
    return re.findall(r'"(\w+)"', m.group(1)) if m else []


def _key(arg: str) -> str:
    m = re.fullmatch(r"KEY_(\w+)", arg.strip())
    return "" if m is None or m.group(1) == "NONE" else m.group(1)


def _title(arg: str) -> str:
    m = re.match(r'(?:tr|Strings\.t)\(\s*"([^"]*)"', arg)
    if m:
        return m.group(1)
    m = re.match(r'(\w+\.\w+)\(\s*"([^"]*)"', arg)
    return "%s: %s" % (m.group(1), m.group(2)) if m else arg


def resolve_file(expr: str, text: str, before: int) -> str:
    """The panel's source file name, from the expression handed to register()/add(), or '?'."""
    expr = expr.strip()
    m = re.search(r'preload\("res://src/ui/(\w+\.gd)"\)', expr)
    if m:
        return m.group(1)
    consts = dict(CONST_PRELOAD.findall(text))
    m = re.match(r"(\w+)\.\w+\(", expr)  # SectorsShell.tab(...)
    if m and m.group(1) in consts:
        return consts[m.group(1)]
    if re.fullmatch(r"\w+", expr):
        pat = re.compile(r"\b%s\s*(?::=|=)\s*(\w+)\.(?:new|\w+)\(" % re.escape(expr))
        found = [x for x in pat.finditer(text[:before])] or list(pat.finditer(text))
        if found:
            cls = found[-1].group(1)
            if cls in consts:
                return consts[cls]
    return "?"


def parse_registers(text: str, fname: str) -> list[dict]:
    out = []
    strs = dict(CONST_STR.findall(text))
    for m in REGISTER.finditer(text):
        args = split_args(text, m.end())
        if len(args) < 3:
            continue
        wid = args[0].strip()
        lit = re.fullmatch(r'"(\w+)"', wid)
        wid = lit.group(1) if lit else strs.get(wid, wid)
        also = re.findall(r"KEY_(\w+)", args[5]) if len(args) > 5 else []
        out.append({"id": wid, "title": _title(args[1]), "key": _key(args[3]) if len(args) > 3 else "",
                    "also": also, "file": resolve_file(args[2], text, m.start()), "in": fname,
                    "line": text.count("\n", 0, m.start()) + 1})
    return out


def parse_stack_adds(text: str, fname: str) -> list[dict]:
    out = []
    for m in STACK_ADD.finditer(text):
        out.append({"layer": m.group(1), "file": resolve_file(m.group(2), text, m.start()), "in": fname})
    return out


def parse_ranks(text: str) -> list[tuple[str, int]]:
    return [(n, int(v)) for n, v in re.findall(r"^const (MAP|WORKSPACE|INBOX|PLACEMENT|SCENE|SYSTEM)\s*:=\s*(-?\d+)", text, re.M)]


def parse_main_keys(text: str) -> list[tuple[str, str]]:
    """main.gd's own keys: the `KEY_X:` arms under `match event.keycode:`, with the first
    statement of each."""
    i = text.find("match event.keycode:")
    if i < 0:
        return []
    lines = text[i:].splitlines()[1:]
    out, k = [], 0
    while k < len(lines):
        m = re.match(r"^\t\t(KEY_[A-Z0-9_, ]+):\s*$", lines[k])
        if m:
            keys = ", ".join(x.strip()[4:] for x in m.group(1).split(","))
            act = ""
            for nxt in lines[k + 1:k + 12]:
                s = nxt.strip()
                if s and not s.startswith("#"):
                    act = s
                    break
            out.append((keys, act))
        elif lines[k] and not lines[k].startswith("\t\t") and not lines[k].startswith("\t"):
            break
        k += 1
    return out


def collect(sources: dict[str, str]) -> dict:
    """Everything the page says, from {file name: text}. Pure."""
    domains = parse_domains(sources.get("domains.gd", ""))
    scenes = parse_scenes(sources.get("domains.gd", ""))
    regs, adds, doors, right = [], [], {}, []
    for fname in sorted(sources):
        text = sources[fname]
        regs += parse_registers(text, fname)
        adds += parse_stack_adds(text, fname)
        for m in DOOR.finditer(text):
            doors.setdefault(m.group(1), set()).add(fname)
        if "MOUSE_BUTTON_RIGHT" in text:
            right.append(fname)
    main = sources.get("main.gd", "")
    return {
        "domains": domains, "scenes": scenes, "regs": regs, "adds": adds, "doors": doors,
        "ranks": parse_ranks(sources.get("screen_stack.gd", "")),
        "keys": parse_main_keys(main),
        "console_key": (re.search(r"TOGGLE_KEY\s*:=\s*KEY_(\w+)", sources.get("dev_console.gd", "")) or [None, ""])[1],
        "right": right,
        "hud": [f for n, f in CONST_PRELOAD.findall(sources.get("hud.gd", "")) if n != "UiTheme"],
    }


def _node(i: str) -> str:
    return "w_" + re.sub(r"\W", "_", i)


def _keys(r: dict) -> str:
    ks = ([r["key"]] if r["key"] else []) + r["also"]
    return " / ".join(ks)


def render(data: dict) -> str:
    regs = {r["id"]: r for r in data["regs"]}
    domain_of = {t: d["id"] for d in data["domains"] for t in d["tabs"]}
    L = ["---", "title: The UI map", "tags:", "  - architecture", "  - ui", "  - generated", "---", "",
         "# The UI map", "",
         "Where each screen lives, so nobody has to open `main.gd` to find out. **Generated by "
         "`python tools/ui_map.py --write` from `src/ui/`; never edited by hand** (`--check` fails CI "
         "when it is stale). The shell it sits in is [[shell]]; the grammar of a panel is [[panel-system]].",
         "", "## Domains and tabs", "",
         "Sidebar domain -> tab -> window id (and its hotkey). A domain with no tab is hidden until a tab "
         "is registered under it.", "", "```mermaid", "flowchart LR"]
    for d in data["domains"]:
        L.append('  subgraph d_%s["%s"]' % (d["id"], d["title"]))
        L.append("    direction TB")
        if not d["tabs"]:
            L.append('    %s_none["(no tab yet)"]' % d["id"])
        for t in d["tabs"]:
            r = regs.get(t)
            label = ("%s<br/>%s" % (r["title"], t)) if r else ("%s<br/>(not registered)" % t)
            k = _keys(r) if r else ""
            if k:
                label += "<br/>key " + k
            L.append('    %s["%s"]' % (_node(t), label))
        L.append("  end")
    loose = sorted(i for i in regs if i not in domain_of)
    if loose:
        L.append('  subgraph outside["Outside the domains"]')
        L.append("    direction TB")
        for i in loose:
            r = regs[i]
            kind = "scene" if i in data["scenes"] else "own tab"
            L.append('    %s["%s<br/>%s<br/>(%s)"]' % (_node(i), r["title"], i, kind))
        L.append("  end")
    L += ["```", "", "## Every window", "",
          "One row per `_windows.register()` call. *Opened by*: the sidebar when the window is a domain's "
          "tab, its hotkey, and the doors found in the code (`open(\"id\")` and kin, by file; a door built "
          "another way is not listed).", "",
          "| domain | tab | window id | key | panel file | registered in | opened by |",
          "|---|---|---|---|---|---|---|"]
    order = [t for d in data["domains"] for t in d["tabs"]] + loose
    for i in order:
        r = regs.get(i)
        dom = domain_of.get(i)
        dtitle = next((d["title"] for d in data["domains"] if d["id"] == dom), "") if dom else ("scene" if i in data["scenes"] else "(none)")
        if r is None:
            L.append("| %s | (not registered) | `%s` |  |  |  |  |" % (dtitle, i))
            continue
        by = []
        if dom:
            by.append("sidebar")
        if _keys(r):
            by.append("key " + _keys(r))
        door_files = sorted(f.removesuffix(".gd") for f in data["doors"].get(i, set()))
        if door_files:
            by.append("door in " + ", ".join(door_files))
        L.append("| %s | %s | `%s` | %s | `%s` | `%s` | %s |" % (
            dtitle, r["title"], i, _keys(r), r["file"], r["in"], "; ".join(by) or "-"))
    L += ["", "## Surfaces outside the domains", "",
          "### The screen stack", "",
          "`screen_stack.gd` ranks what owns the screen; Escape and the hotkeys follow the top. Lowest first.", "",
          "| rank | name |", "|---|---|"]
    for n, v in data["ranks"]:
        L.append("| %d | `%s` |" % (v, n))
    L += ["", "Panels added to a rank (`_stack.add(ScreenStack.RANK, panel, ...)`):", "",
          "| rank | panel file | added in |", "|---|---|---|"]
    for a in sorted(data["adds"], key=lambda a: (a["layer"], a["file"], a["in"])):
        L.append("| `%s` | `%s` | `%s` |" % (a["layer"], a["file"], a["in"]))
    L += ["", "### The HUD's pieces", "",
          "What `hud.gd` builds around the map (the inbox slides over the open tab; the sidebar is the domains above): "
          + ", ".join("`%s`" % f for f in data["hud"]) + ".",
          "", "### Keys that are not a window's", "",
          "From `main.gd`'s key handler (the window hotkeys are in the table above):", "",
          "| key | does |", "|---|---|"]
    for k, act in data["keys"]:
        L.append("| %s | `%s` |" % (k, act.replace("|", "\\|")))
    if data["console_key"]:
        L.append("| %s | the dev console (debug builds), `dev_console.gd` |" % data["console_key"])
    L += ["", "### Right-click", "",
          "Files that handle `MOUSE_BUTTON_RIGHT`: " + ", ".join("`%s`" % f for f in data["right"]) + ".", ""]
    return "\n".join(L)


def load_sources() -> dict[str, str]:
    out = {}
    for p in sorted(UI.rglob("*.gd")):
        out[p.name] = p.read_text(encoding="utf-8", errors="replace")
    return out


def selftest() -> int:
    bad = []

    def expect(label: str, cond: bool) -> None:
        if not cond:
            bad.append(label)

    domains = '''const TABLE := [
	{"id": "gov", "title": "Government", "icon": "g.svg", "tabs": ["people", "ghost"]},  # i18n: msgid title
	{"id": "empty", "title": "Empty", "icon": "", "tabs": []},
]
const SCENES := ["summit"]
'''
    main = '''const PeoplePanel = preload("res://src/ui/people_panel.gd")
const Other = preload("res://src/ui/other_panel.gd")
func _ready():
	_people_panel = PeoplePanel.new()
	_windows.register("people", tr("People"), _people_panel, KEY_R, ICONS + "p.svg", [KEY_Q, KEY_Z])
	_windows.register("summit", tr("Summit"), preload("res://src/ui/summit_panel.gd").new(), KEY_NONE, "")
	_windows.register("x", Strings.t("X (a, b)"), Other.build(self, "k"), KEY_NONE, "")
	_stack.add(ScreenStack.SYSTEM, _people_panel, false, _people_panel.close)
	match event.keycode:
		KEY_SPACE:
			_toggle_pause_by_hand()
		KEY_1, KEY_2:
			_set_speed_by_hand(1)
	_other.open("people")
'''
    drv = '''const WINDOW := "file"
static func register(main) -> void:
	main._windows.register(WINDOW, Strings.t("Decision"), view, KEY_NONE, "")
'''
    stack = "const MAP := -1\nconst WORKSPACE := 0\nconst SYSTEM := 4\n"
    data = collect({"domains.gd": domains, "main.gd": main, "files_driver.gd": drv,
                    "screen_stack.gd": stack, "dev_console.gd": "const TOGGLE_KEY := KEY_F12\n",
                    "country_box.gd": "if b == MOUSE_BUTTON_RIGHT:\n"})
    regs = {r["id"]: r for r in data["regs"]}
    expect("three windows plus the driver's", set(regs) == {"people", "summit", "x", "file"})
    expect("key and also keys", regs["people"]["key"] == "R" and regs["people"]["also"] == ["Q", "Z"])
    expect("a var resolves through its class and const", regs["people"]["file"] == "people_panel.gd")
    expect("an inline preload resolves", regs["summit"]["file"] == "summit_panel.gd")
    expect("a factory call resolves through its class", regs["x"]["file"] == "other_panel.gd")
    expect("a comma inside a string does not split", regs["x"]["title"] == "X (a, b)")
    expect("a const id resolves", "file" in regs and regs["file"]["in"] == "files_driver.gd")
    expect("an unresolved panel is a question mark", regs["file"]["file"] == "?")
    expect("domains parse", [d["id"] for d in data["domains"]] == ["gov", "empty"] and data["domains"][0]["tabs"] == ["people", "ghost"])
    expect("scenes parse", data["scenes"] == ["summit"])
    expect("main keys", data["keys"][0][0] == "SPACE" and data["keys"][1][0] == "1, 2")
    expect("door found", data["doors"].get("people") == {"main.gd"})
    expect("stack add", data["adds"] == [{"layer": "SYSTEM", "file": "people_panel.gd", "in": "main.gd"}])
    hud_src = 'const UiTheme = preload("res://src/ui/ui_theme.gd")\nconst Inbox = preload("res://src/ui/inbox.gd")\n'
    expect("hud pieces", collect({"hud.gd": hud_src})["hud"] == ["inbox.gd"])
    expect("ranks and console key", data["ranks"][0] == ("MAP", -1) and data["console_key"] == "F12")
    page = render(data)
    expect("diagram has the domain and a not-registered tab", 'subgraph d_gov["Government"]' in page and "ghost<br/>(not registered)" in page)
    expect("empty domain says so", "(no tab yet)" in page)
    expect("scene sits outside", "(scene)" in page)
    expect("table row", "| Government | People | `people` | R / Q / Z | `people_panel.gd` | `main.gd` | sidebar; key R / Q / Z; door in main |" in page)
    expect("deterministic", render(data) == page)
    for label in bad:
        print("ui_map selftest FAIL: " + label, file=sys.stderr)
    if not bad:
        print("ui_map selftest: ok")
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    page = render(collect(load_sources()))
    if "--write" in argv:
        OUT.write_text(page, encoding="utf-8", newline="\n")
        print("wrote %s (%d lines)" % (OUT.relative_to(REPO), page.count("\n") + 1))
        return 0
    have = OUT.read_text(encoding="utf-8").replace("\r\n", "\n") if OUT.is_file() else ""
    if have != page:
        print("ui_map: docs/ui-map.md is stale: run `python tools/ui_map.py --write`", file=sys.stderr)
        return 1
    print("ui_map: docs/ui-map.md is current")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
