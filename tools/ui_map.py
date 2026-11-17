#!/usr/bin/env python3
"""The map of the game's menus, generated from the code (docs/ui-map.md).

Nobody writes this page: where a screen lives is a fact of src/ui/, and a hand-kept
copy drifts with the first PR that adds a tab. It reads the TRACKED files of src/ui/
(`git ls-files`, so a stray scratch file never reaches the page), with their comments
stripped first:

  domains.gd   the sidebar's domains, the tabs under each, the scenes
  labels.gd    the English a `Labels.sector("agriculture")` title shows
  every file   `_windows.register(id, title, panel, key, icon, [also])` (a const id, a
               panel var / factory call / inline preload are resolved), the panels added
               to a screen-stack rank (`<any>.add(ScreenStack.RANK, panel, ...)`), the
               doors a window is opened through from another file (`open("id")` or
               `open(CONST)` and kin), the keys (main.gd's `match event.keycode:` arms,
               `TOGGLE_KEY := KEY_X`, `keycode == KEY_X`) and the right-click files

and writes docs/ui-map.md: a diagram of domain -> tab -> window id, a table with one
row per window, and the surfaces outside the domains.

    python tools/ui_map.py --write      regenerate docs/ui-map.md
    python tools/ui_map.py --check      exit 1 when the page is stale (CI only)
    python tools/ui_map.py --selftest   the parser and the renderer on fake sources

Stdlib only. A panel it cannot resolve to a file is shown as `?`, never guessed.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
UI = "src/ui/"
OUT = REPO / "docs" / "ui-map.md"

REGISTER = re.compile(r"_windows\.register\(")
STACK_ADD = re.compile(r"\.add\(\s*ScreenStack\.(\w+)\s*,\s*([^,)]+)")
DOOR = re.compile(r'\b(?:open|open_window|_toggle_window|toggle_window|show_window)\(\s*(?:"(\w+)"|([A-Z_][A-Z0-9_]*))\s*[,)]')
OTHER_KEYS = re.compile(r"(?:TOGGLE_KEY\s*:=|keycode\s*==)\s*KEY_(\w+)")
CONST_PRELOAD = re.compile(r'^const\s+(\w+)\s*(?::=|=)\s*preload\("res://src/ui/([\w/]+\.gd)"\)', re.M)
CONST_STR = re.compile(r'^const\s+(\w+)\s*(?::=|=)\s*"([^"]*)"', re.M)


def strip_comments(text: str) -> str:
    """Each line without its `#` comment (a `#` inside a string stays); line numbers are kept."""
    out = []
    for line in text.splitlines():
        quote, cut, skip = "", len(line), False
        for i, c in enumerate(line):
            if skip:
                skip = False
            elif quote:
                if c == "\\":
                    skip = True
                elif c == quote:
                    quote = ""
            elif c in "\"'":
                quote = c
            elif c == "#":
                cut = i
                break
        out.append(line[:cut].rstrip())
    return "\n".join(out)


def parse_labels(text: str) -> dict[str, dict[str, str]]:
    """labels.gd: {accessor: {id: shown English}} for `static func x(id: String) -> String: return of(TABLE, id)`."""
    tables = {}
    for m in re.finditer(r"^const (\w+) := \{(.*?)\n\}", text, re.M | re.S):
        tables[m.group(1)] = dict(re.findall(r'"(\w+)":\s*"([^"]*)"', m.group(2)))
    out = {}
    for m in re.finditer(r"static func (\w+)\(id: String\) -> String:\s*return of\((\w+), id\)", text):
        out[m.group(1)] = tables.get(m.group(2), {})
    return out


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


def _title(arg: str, labels: dict) -> str:
    m = re.match(r'(?:tr|Strings\.t)\(\s*"([^"]*)"', arg)
    if m:
        return m.group(1)
    m = re.match(r'Labels\.(\w+)\(\s*"(\w+)"', arg)  # the title as the player sees it
    if m and m.group(1) in labels:
        return labels[m.group(1)].get(m.group(2), m.group(2).capitalize())
    return arg


def resolve_file(expr: str, text: str, before: int, fname: str = "") -> str:
    """The panel's source file, from the expression handed to register()/add(), or '?'."""
    expr = expr.strip()
    m = re.search(r'preload\("res://src/ui/([\w/]+\.gd)"\)', expr)
    if m:
        return m.group(1)
    consts = dict(CONST_PRELOAD.findall(text))
    m = re.match(r"(\w+)\.\w+\(", expr)  # SectorsShell.tab(...)
    if m and m.group(1) in consts:
        return consts[m.group(1)]
    if re.fullmatch(r"\w+", expr):
        if re.search(r"\b%s\s*(?::=|=)\s*new\(" % re.escape(expr), text):
            return fname or "?"  # the file builds itself: `var card := new()`
        pat = re.compile(r"\b%s\s*(?::=|=)\s*(\w+)\.(?:new|\w+)\(" % re.escape(expr))
        found = list(pat.finditer(text[:before])) or list(pat.finditer(text))
        if found:
            cls = found[-1].group(1)
            if cls in consts:
                return consts[cls]
    return "?"


def parse_registers(text: str, fname: str, labels: dict | None = None) -> list[dict]:
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
        out.append({"id": wid, "title": _title(args[1], labels or {}), "key": _key(args[3]) if len(args) > 3 else "",
                    "also": also, "file": resolve_file(args[2], text, m.start(), fname), "in": fname})
    return out


def parse_stack_adds(text: str, fname: str) -> list[dict]:
    return [{"layer": m.group(1), "file": resolve_file(m.group(2), text, m.start(), fname), "in": fname}
            for m in STACK_ADD.finditer(text)]


def parse_ranks(text: str) -> list[tuple[str, int]]:
    return [(n, int(v)) for n, v in re.findall(r"^const (MAP|WORKSPACE|INBOX|PLACEMENT|SCENE|SYSTEM)\s*:=\s*(-?\d+)", text, re.M)]


def parse_main_keys(text: str) -> list[str]:
    """main.gd's own keys: the `KEY_X:` arms under `match event.keycode:`."""
    i = text.find("match event.keycode:")
    if i < 0:
        return []
    out = []
    for line in text[i:].splitlines()[1:]:
        m = re.match(r"^\t\t(KEY_[A-Z0-9_, ]+):\s*$", line)
        if m:
            out.append(", ".join(x.strip()[4:] for x in m.group(1).split(",")))
        elif line and not line.startswith("\t"):
            break
    return out


def collect(raw: dict[str, str]) -> dict:
    """Everything the page says, from {path under src/ui: text}. Pure."""
    sources = {f: strip_comments(x) for f, x in raw.items()}
    domains = parse_domains(sources.get("domains.gd", ""))
    scenes = parse_scenes(sources.get("domains.gd", ""))
    labels = parse_labels(sources.get("labels.gd", ""))
    regs, adds, doors, right, others = [], [], {}, [], set()
    for fname in sorted(sources):
        text = sources[fname]
        regs += parse_registers(text, fname, labels)
        adds += parse_stack_adds(text, fname)
        strs = dict(CONST_STR.findall(text))
        for m in DOOR.finditer(text):
            wid = m.group(1) or strs.get(m.group(2))
            if wid:
                doors.setdefault(wid, set()).add(fname)
        if "MOUSE_BUTTON_RIGHT" in text:
            right.append(fname)
        for k in OTHER_KEYS.findall(text):
            others.add((k, fname))
    keys = [(k, "main.gd") for k in parse_main_keys(sources.get("main.gd", ""))] + sorted(others)
    return {
        "domains": domains, "scenes": scenes, "regs": regs, "adds": adds, "doors": doors,
        "ranks": parse_ranks(sources.get("screen_stack.gd", "")),
        "keys": keys, "right": right,
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
    first_tab = {d["tabs"][0] for d in data["domains"] if d["tabs"]}
    L = ["---", "title: The UI map", "tags:", "  - architecture", "  - ui", "  - generated", "---", "",
         "# The UI map", "",
         "Where each screen lives, so nobody has to open `main.gd` to find out. **Generated by "
         "`python tools/ui_map.py --write` from the tracked files of `src/ui/`; never edited by hand** "
         "(CI runs `--check` and fails when it is stale). The shell it sits in is [[shell]]; the grammar of a "
         "panel is [[panel-system]].",
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
            kind = "scene" if i in data["scenes"] else "own tab, no domain row"
            L.append('    %s["%s<br/>%s<br/>(%s)"]' % (_node(i), r["title"], i, kind))
        L.append("  end")
    L += ["```", "", "## Every window", "",
          "One row per `_windows.register()` call. *Opened by*: the sidebar (a domain's first tab) or the "
          "domain's tab strip, its hotkey, and the doors found in the code (`open(\"id\")` / `open(CONST)` and kin, "
          "by file; a door built another way is not listed).", "",
          "| domain | tab | window id | key | panel file | registered in | opened by |",
          "|---|---|---|---|---|---|---|"]
    order = [t for d in data["domains"] for t in d["tabs"]] + loose
    for i in order:
        r = regs.get(i)
        dom = domain_of.get(i)
        if dom:
            dtitle = next(d["title"] for d in data["domains"] if d["id"] == dom)
        else:
            dtitle = "(scene)" if i in data["scenes"] else "(own tab, no domain row)"
        if r is None:
            L.append("| %s | (not registered) | `%s` |  |  |  |  |" % (dtitle, i))
            continue
        by = []
        if dom:
            by.append("sidebar" if i in first_tab else "tab strip")
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
    L += ["", "Panels added to a rank (`<stack>.add(ScreenStack.RANK, panel, ...)`):", "",
          "| rank | panel file | added in |", "|---|---|---|"]
    for a in sorted(data["adds"], key=lambda a: (a["layer"], a["file"], a["in"])):
        L.append("| `%s` | `%s` | `%s` |" % (a["layer"], a["file"], a["in"]))
    L += ["", "### The HUD's pieces", "",
          "What `hud.gd` builds around the map (the inbox slides over the open tab; the sidebar is the domains above): "
          + ", ".join("`%s`" % f for f in data["hud"]) + ".",
          "", "### Keys that are not a window's", "",
          "The window hotkeys are in the table above.", "",
          "| key | handled in |", "|---|---|"]
    for k, f in data["keys"]:
        L.append("| %s | `%s` |" % (k, f))
    L += ["", "### Right-click", "",
          "Files that handle `MOUSE_BUTTON_RIGHT`: " + ", ".join("`%s`" % f for f in data["right"]) + ".", ""]
    return "\n".join(L)


def load_sources() -> dict[str, str]:
    """The tracked src/ui files, keyed by path under src/ui (a name can repeat in two folders)."""
    names = subprocess.run(["git", "ls-files", UI], cwd=REPO, capture_output=True, text=True, check=True).stdout.splitlines()
    out = {}
    for n in sorted(names):
        if n.endswith(".gd") and (REPO / n).is_file():
            out[n[len(UI):]] = (REPO / n).read_text(encoding="utf-8", errors="replace")
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
    labels = '''const SECTOR := {
	"agriculture": "Agriculture", "industry": "Industry",  # i18n: msgid
}
static func sector(id: String) -> String:
	return of(SECTOR, id)
'''
    main = '''const PeoplePanel = preload("res://src/ui/people_panel.gd")
const Other = preload("res://src/ui/other_panel.gd")
func _ready():
	_people_panel = PeoplePanel.new()
	_windows.register("people", tr("People"), _people_panel, KEY_R, ICONS + "p.svg", [KEY_Q, KEY_Z])
	_windows.register("summit", tr("Summit"), preload("res://src/ui/summit_panel.gd").new(), KEY_NONE, "")
	_windows.register("x", Strings.t("X (a, b)"), Other.build(self, "k"), KEY_NONE, "")
	_windows.register("sector_agriculture", Labels.sector("agriculture"), Other.build(self, "a"), KEY_NONE, "")
	# _windows.register("commented", tr("Gone"), p, KEY_NONE, "")
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
static func show(main) -> void:
	main._windows.open(WINDOW)
'''
    card = '''static func ask(stack) -> Node:
	var card := new()
	stack.add(ScreenStack.SYSTEM, card, true, card.hide)
	return card
'''
    stackf = "const MAP := -1\nconst WORKSPACE := 0\nconst SYSTEM := 4\n"
    data = collect({"domains.gd": domains, "main.gd": main, "files_driver.gd": drv, "labels.gd": labels,
                    "confirm_card.gd": card, "screen_stack.gd": stackf,
                    "dev_console.gd": "const TOGGLE_KEY := KEY_F12\n",
                    "window_mode.gd": "const TOGGLE_KEY := KEY_F11\n",
                    "glossary_tip.gd": "if f.keycode == KEY_F1:\n\tpass\n",
                    "country_box.gd": "if b == MOUSE_BUTTON_RIGHT:\n"})
    regs = {r["id"]: r for r in data["regs"]}
    expect("windows found, the commented one not (T6)", set(regs) == {"people", "summit", "x", "file", "sector_agriculture"})
    expect("key and also keys", regs["people"]["key"] == "R" and regs["people"]["also"] == ["Q", "Z"])
    expect("a var resolves through its class and const", regs["people"]["file"] == "people_panel.gd")
    expect("an inline preload resolves", regs["summit"]["file"] == "summit_panel.gd")
    expect("a factory call resolves through its class", regs["x"]["file"] == "other_panel.gd")
    expect("a comma inside a string does not split", regs["x"]["title"] == "X (a, b)")
    expect("a const id resolves", regs["file"]["in"] == "files_driver.gd")
    expect("an unresolved panel is a question mark", regs["file"]["file"] == "?")
    expect("a Labels title shows as the player sees it (T9)", regs["sector_agriculture"]["title"] == "Agriculture")
    expect("domains parse", [d["id"] for d in data["domains"]] == ["gov", "empty"] and data["domains"][0]["tabs"] == ["people", "ghost"])
    expect("scenes parse", data["scenes"] == ["summit"])
    expect("door by literal", "main.gd" in data["doors"].get("people", set()))
    expect("door through a same-file const (T3)", data["doors"].get("file") == {"files_driver.gd"})
    expect("rank add on any receiver, a bare new() resolves to its own file (T4)",
           {"layer": "SYSTEM", "file": "confirm_card.gd", "in": "confirm_card.gd"} in data["adds"])
    expect("rank add with a var", {"layer": "SYSTEM", "file": "people_panel.gd", "in": "main.gd"} in data["adds"])
    expect("main keys and other keys, F11 and F1 included (T4)",
           ("SPACE", "main.gd") in data["keys"] and ("1, 2", "main.gd") in data["keys"]
           and ("F11", "window_mode.gd") in data["keys"] and ("F1", "glossary_tip.gd") in data["keys"]
           and ("F12", "dev_console.gd") in data["keys"])
    expect("ranks", data["ranks"][0] == ("MAP", -1))
    hud_src = 'const UiTheme = preload("res://src/ui/ui_theme.gd")\nconst Inbox = preload("res://src/ui/inbox.gd")\n'
    expect("hud pieces", collect({"hud.gd": hud_src})["hud"] == ["inbox.gd"])
    expect("a # inside a string survives comment stripping", strip_comments('x = "a # b"  # gone') == 'x = "a # b"')
    page = render(data)
    expect("diagram has the domain and a not-registered tab", 'subgraph d_gov["Government"]' in page and "ghost<br/>(not registered)" in page)
    expect("empty domain says so", "(no tab yet)" in page)
    expect("scene sits outside", "(scene)" in page)
    expect("the first tab is the sidebar's, the second is the tab strip's (T5)",
           "| Government | People | `people` | R / Q / Z | `people_panel.gd` | `main.gd` | sidebar; key R / Q / Z; door in main |" in page
           and "| Government | (not registered) | `ghost` |" in page)
    expect("an own-tab window reads the same in the table and the diagram (T5)",
           "| (own tab, no domain row) | Decision | `file` |" in page and "(own tab, no domain row)" in page.split("```mermaid")[1].split("```")[0])
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
