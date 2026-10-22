"""Generated vault diagrams, and the check that keeps them true to the code.

Two diagrams live in the vault as Mermaid between marker comments:

    <!-- vault-diagram:NAME begin ... -->
    <!-- vault-diagram:NAME end -->

* tick-order     docs/tick-order.md       -- src/sim/world_month.gd's STEPS, in run order
* layers         docs/data-architecture.md -- data -> core -> sim -> ui, real module names
* roadmap        docs/tiers/v5.md         -- V5's blocks, drawn from its block table and `state:`
* domains        docs/shell.md            -- the sidebar's domains and tabs, from src/ui/domains.gd

    python tools/vault_diagrams.py            # check (exit 1 on any drift)
    python tools/vault_diagrams.py --write    # regenerate the blocks in place

tools/check_vault.py runs the check, so CI and a fresh clone get it. What it
fails on, and why each exists:

* The block in the doc differs from what the code now generates. A system added
  to STEPS changes the diagram; the fix is `--write`, nothing to hand-edit.
* A step in STEPS has no group, or a group names a step STEPS no longer has. The
  step-to-group table below is authored -- a grouping is a judgement, not
  something the code states -- so it is the one thing a new system must be told.
* The roadmap's block table and the frontmatter `state:` map disagree: a block with
  no state, or a state for a block the table does not have. The states are the one
  thing a person keeps true (closing sessions update them at each block close).
* A tab in src/ui/domains.gd's TABLE that main.gd never registers as a window, or a
  canvas file node / backticked path in docs/shell.canvas that is not on disk.
* A module the layers diagram names is not on disk (a renamed file cannot stay
  drawn).
* A file under src/sim or src/core loads anything under res://src/ui, or reaches
  the scene tree. This is AGENTS.md's rule 2, which the layers diagram asserts;
  the diagram would otherwise be a picture of an intention.
"""
import os
import re
import subprocess
import sys

ROOT = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                      text=True, check=True).stdout.strip()

STEPS_FILE = "src/sim/world_month.gd"

# Authored: which domain a step belongs to. Fails loudly on a step it does not know.
GROUPS = [
    ("Economy", "#cfe3f7", ["Access", "Energy", "Economy", "Commodities", "Budget", "Inflation"]),
    ("Opinion and agenda", "#f6dcc2", ["Orgs", "Media", "Programme", "Opinion", "History", "Calendar"]),
    ("Assembly", "#dccff0", ["Discipline", "Legislature", "Statute", "Dissolution"]),
    ("The world", "#cdebd3", ["Diplomacy", "Defence", "Companies", "Industry", "Migration",
                              "Investment", "Projects"]),
    ("Campaign and society", "#f3e7b5", ["Campaign", "Pledges", "Demography", "Society", "Unrest"]),
    ("People and the vote", "#f2cfd3", ["Events", "Cabinet", "Characters", "Elections"]),
]
ROW = 8

# Authored: the modules worth naming per layer. Each must exist (checked).
LAYERS = [
    ("data", "data/",
     ["data/nations", "data/parties", "data/laws", "data/events", "data/commodities",
      "data/companies", "data/people", "data/orgs", "data/glossary", "data/i18n"]),
    ("core", "src/core/",
     ["src/core/game_state.gd", "src/core/nation_state.gd", "src/core/nation_fields.gd",
      "src/core/data_loader.gd", "src/core/loaders", "src/core/clock.gd", "src/core/save_manager.gd"]),
    ("sim", "src/sim/",
     ["src/sim/world_month.gd", "src/sim/economy.gd", "src/sim/budget.gd", "src/sim/opinion.gd",
      "src/sim/legislature.gd", "src/sim/diplomacy.gd", "src/sim/orgs.gd", "src/sim/events.gd",
      "src/sim/elections.gd"]),
    ("ui", "src/ui/",
     ["src/ui/main.gd", "src/ui/month_runner.gd", "src/ui/window_manager.gd",
      "src/ui/screen_stack.gd", "src/ui/hud.gd", "src/ui/map_view.gd", "src/ui/panel_kit.gd",
      "src/ui/ui_theme.gd"]),
]

# What src/sim and src/core may never do. Comments are skipped: world_month.gd
# names src/ui/month_runner.gd in prose, which is documentation, not a dependency.
UI_REF = re.compile(r"""\b(?:preload|load)\s*\(\s*["']res://src/ui""")
TREE_REF = re.compile(r"\bget_node\s*\(|\bget_tree\s*\(|\$[A-Za-z_]")


def read(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return f.read()


def parse_steps():
    src = read(STEPS_FILE)
    m = re.search(r"const STEPS: Array\[String\] = \[(.*?)\]", src, re.S)
    if not m:
        raise SystemExit(f"{STEPS_FILE}: no `const STEPS: Array[String] = [...]` found")
    return re.findall(r'"([A-Za-z]+)"', m.group(1))


def group_problems(steps):
    known = [s for _, _, ss in GROUPS for s in ss]
    out = [f"step {s!r} is in STEPS but in no group of tools/vault_diagrams.py GROUPS"
           for s in steps if s not in known]
    out += [f"GROUPS names {s!r}, which STEPS no longer has" for s in known if s not in steps]
    out += [f"GROUPS names {s!r} twice" for s in set(known) if known.count(s) > 1]
    return out


def render_tick(steps):
    group_of = {s: (name, fill) for name, fill, ss in GROUPS for s in ss}
    lines = [f"The month runs **{len(steps)} steps** in this order, once per game month "
             f"(`STEPS` in [`{STEPS_FILE}`](../{STEPS_FILE}), held to the real calls by "
             "`tests/test_world_month.gd`). Read each row left to right, then the next row. "
             "Colour and the second line of each box give the domain."]
    for r in range(0, len(steps), ROW):
        row = steps[r:r + ROW]
        lines += ["", f"Steps {r + 1} to {r + len(row)}:", "", "```mermaid", "flowchart LR"]
        names = [f"s{r + i + 1}" for i in range(len(row))]
        for i, step in enumerate(row):
            g, fill = group_of[step]
            lines.append(f'  {names[i]}["{r + i + 1} {step}<br/>{g}"]'
                         f":::g{[x[0] for x in GROUPS].index(g)}")
        lines.append("  " + " --> ".join(names))
        for gi, (g, fill, _) in enumerate(GROUPS):
            lines.append(f"  classDef g{gi} fill:{fill},stroke:#555,color:#1a1a1a")
        lines.append("```")
    lines += ["", "Domains:"]
    for g, _, ss in GROUPS:
        lines.append(f"- **{g}**: " + ", ".join(s for s in ss if s in steps))
    return "\n".join(lines)


def render_layers():
    out = ["```mermaid", '%%{init: {"flowchart": {"rankSpacing": 12, "nodeSpacing": 30}}}%%', "flowchart LR"]
    for key, title, mods in LAYERS:
        out.append(f'  subgraph {key}["{title}"]')
        out.append("    direction TB")
        for i, mod in enumerate(mods):
            out.append(f'    {key}{i}["{os.path.basename(mod.rstrip("/"))}"]')
        # Unlinked nodes lay out as one wide row; invisible links make a column, which
        # is what keeps four layers legible side by side (QA, PR 80).
        out.append("    " + " ~~~ ".join(f"{key}{i}" for i in range(len(mods))))
        out.append("  end")
    out += ['  data -->|"read once at startup"| core',
            '  core -->|"GameState"| sim',
            '  sim -->|"GameState, read"| ui',
            '  ui -.->|"player intent: explicit commands, e.g. Budget.commit()"| sim',
            "```", "",
            "`data/` is content, read once and never mutated; `src/core/` is state, clock, save and the loaders; `src/sim/` is one file per system with no UI knowledge; `src/ui/` is scenes and panels, read-only over state. Dependencies point one way: a file in `src/sim` or `src/core` never loads anything "
            "under `src/ui` and never reaches the scene tree. `python tools/vault_diagrams.py` "
            "fails on a violation, and on a module drawn above that no longer exists."]
    return "\n".join(out)


V5_FILE = "docs/tiers/v5.md"
DOMAINS_FILE = "src/ui/domains.gd"
MAIN_FILE = "src/ui/main.gd"
CANVAS_FILE = "docs/shell.canvas"
STATES = ("closed", "built", "in-progress", "planned")
STATE_STYLE = (("closed", "#cdebd3", ""), ("built", "#cfe3f7", ""),
               ("inprogress", "#f3e7b5", ""), ("planned", "#ececec", ",stroke-dasharray:4 3"))


def parse_roadmap():
    """Return (blocks, state): blocks = [(id, name, [depends])] from the block table,
    state = {key: (state, label)} from the frontmatter `state:` map."""
    text = read(V5_FILE)
    blocks = []
    for m in re.finditer(r"^\| (V5\.\d) \| ([^|]+?) \| [^|]* \| ([^|]+?) \|", text, re.M):
        name = re.split(r"\s\u2014\s", m.group(2).strip())[0]
        dep = m.group(3).strip()
        blocks.append((m.group(1), name, [] if dep in ("\u2014", "-") else
                       ["all"] if dep == "all" else re.findall(r"V5\.\d", dep)))
    fm = re.match(r"---\n(.*?)\n---", text, re.S)
    state = {}
    if fm:
        m = re.search(r"^state:\n((?:[ \t]+\S.*\n?)+)", fm.group(1) + "\n", re.M)
        for line in (m.group(1).splitlines() if m else []):
            k, _, v = line.strip().partition(":")
            st, _, label = v.partition("|")
            state[k.strip()] = (st.strip(), label.strip())
    return blocks, state


def roadmap_problems(blocks, state):
    ids = [b[0] for b in blocks]
    out = [] if blocks else [f"{V5_FILE}: no block table rows found"]
    out += [f"{V5_FILE}: block {i} has no entry in the frontmatter `state:` map" for i in ids
            if i not in state]
    for k, (st, _) in state.items():
        if k.split("-")[0] not in ids:
            out.append(f"{V5_FILE}: `state:` names {k}, which the block table does not have")
        if st not in STATES:
            out.append(f"{V5_FILE}: `state: {k}` is {st!r}, not one of {', '.join(STATES)}")
    return out


def _nid(i):
    return i.replace(".", "").replace("-", "_")


def _state_node(nid, title, st, label):
    text = f"{title}<br/>{label}<br/>{st}" if label else f"{title}<br/>{st}"
    return f'  {nid}["{text}"]:::{st.replace("-", "")}'


def render_roadmap(blocks, state):
    ids = [b[0] for b in blocks]
    out = ["```mermaid", "flowchart LR"]
    for bid, name, _ in blocks:
        out.append(_state_node(_nid(bid), f"{bid} {name}", *state[bid]))
    deps = {bid: d for bid, _, d in blocks}
    depended = {x for d in deps.values() for x in d if x != "all"}
    for bid, d in deps.items():
        sources = [i for i in ids if i != bid and i not in depended] if d == ["all"] else d
        out += [f"  {_nid(src)} --> {_nid(bid)}" for src in sources]
    out += [f"  classDef {n} fill:{f},stroke:#555,color:#1a1a1a{d}" for n, f, d in STATE_STYLE]
    out.append("```")
    subs = [(k, v) for k, v in state.items() if "-" in k]
    if subs:
        out += ["", "The sub-blocks that have a state of their own:", "", "```mermaid", "flowchart LR"]
        out += [_state_node(_nid(k), k, *v) for k, v in subs]
        out.append("  " + " --> ".join(_nid(k) for k, _ in subs))
        out += [f"  classDef {n} fill:{f},stroke:#555,color:#1a1a1a{d}" for n, f, d in STATE_STYLE]
        out.append("```")
    out += ["", "Each box says its state in words, so colour is never the only signal. "
            "`closed`: the play gate is scored and recorded. `built`: merged, not yet closed by a play "
            "gate. The states live in this page's frontmatter `state:` map and are updated by the "
            "session that closes a block; the diagram is generated from them and from the block table."]
    return "\n".join(out)


def parse_domains():
    """Return (rows, scenes): rows = [(id, title, [tabs])] from TABLE in domains.gd."""
    text = read(DOMAINS_FILE)
    rows = [(m.group(1), m.group(2), re.findall(r'"([a-z_]+)"', m.group(3)))
            for m in re.finditer(r'\{"id": "([a-z_]+)", "title": "([^"]+)", "icon": "[^"]*", '
                                 r'"tabs": \[([^\]]*)\]\}', text)]
    scenes = re.search(r"const SCENES := \[([^\]]*)\]", text)
    return rows, re.findall(r'"([a-z_]+)"', scenes.group(1) if scenes else "")


def _registered():
    return set(re.findall(r'_windows\.register\("([a-z_]+)"', read(MAIN_FILE)))


def domain_problems(rows, scenes):
    if not rows:
        return [f"{DOMAINS_FILE}: no TABLE rows found"]
    registered = _registered()
    tabs = [t for _, _, ts in rows for t in ts]
    out = [f"{DOMAINS_FILE}: tab {t!r} is not registered as a window in {MAIN_FILE}"
           for t in tabs + scenes if t not in registered]
    # parse_domains() reads one row shape; a row written another way would be skipped
    # silently, and the diagram would quietly lose a domain.
    block = re.search(r"const TABLE := \[(.*?)\n\]", read(DOMAINS_FILE), re.S)
    n = block.group(1).count('"id":') if block else 0
    if n != len(rows):
        out.append(f"{DOMAINS_FILE}: TABLE has {n} rows but only {len(rows)} match the shape "
                   "tools/vault_diagrams.py parse_domains() reads (id, title, icon, tabs, in that order)")
    return out


def render_domains(rows, scenes):
    own = sorted(_registered() - {t for _, _, ts in rows for t in ts} - set(scenes))
    out = ["```mermaid", "flowchart LR", '  sb["Sidebar"]']
    for did, title, ts in rows:
        if ts:
            out.append(f'  sb --> d_{did}["{title}"]')
            out += [f'  d_{did} --> t_{t}["{t}"]' for t in ts]
        else:
            out.append(f'  sb -.-> d_{did}["{title}<br/>hidden until a tab registers"]:::hidden')
    out += [f'  sb -.-> s_{t}["{t}<br/>a scene, in no domain"]:::hidden' for t in scenes]
    out += [f'  sb --> o_{t}["{t}<br/>its own one-tab domain"]' for t in own]
    out += ["  classDef hidden stroke-dasharray:4 3,fill:#ececec,stroke:#555,color:#1a1a1a", "```"]
    return "\n".join(out)


def canvas_problems():
    import json
    try:
        data = json.loads(read(CANVAS_FILE))
    except (OSError, ValueError) as e:
        return [f"{CANVAS_FILE}: {e}"]
    out = []
    for n in data.get("nodes", []):
        refs = [n["file"]] if n.get("type") == "file" else \
            re.findall(r"`((?:src|tests|tools|data|docs)/[\w./\-]+)`", n.get("text", ""))
        out += [f"{CANVAS_FILE}: node {n['id']} names {r}, which is not on disk" for r in refs
                if not os.path.exists(os.path.join(ROOT, r.split("#")[0]))]
    ids = [n["id"] for n in data.get("nodes", [])] + [e["id"] for e in data.get("edges", [])]
    out += [f"{CANVAS_FILE}: duplicate id {i}" for i in set(ids) if ids.count(i) > 1]
    nodes = {n["id"] for n in data.get("nodes", [])}
    out += [f"{CANVAS_FILE}: edge {e['id']} points at a missing node" for e in data.get("edges", [])
            if e["fromNode"] not in nodes or e["toNode"] not in nodes]
    return out


def block(name, body):
    return (f"<!-- vault-diagram:{name} begin (generated by tools/vault_diagrams.py --write; "
            f"do not edit) -->\n{body}\n<!-- vault-diagram:{name} end -->")


TARGETS = {"tick-order": "docs/tick-order.md", "layers": "docs/data-architecture.md",
           "roadmap": V5_FILE, "domains": "docs/shell.md"}


def expected(steps, roadmap, domains):
    return {"tick-order": render_tick(steps), "layers": render_layers(),
            "roadmap": render_roadmap(*roadmap), "domains": render_domains(*domains)}


def splice(text, name, body):
    pat = re.compile(rf"<!-- vault-diagram:{name} begin.*?<!-- vault-diagram:{name} end -->", re.S)
    return pat.subn(lambda _: block(name, body), text, count=1)


def layer_problems():
    out = []
    for _, _, mods in LAYERS:
        out += [f"layers diagram names {m}, which is not on disk" for m in mods
                if not os.path.exists(os.path.join(ROOT, m))]
    for sub in ("src/sim", "src/core"):
        for dirpath, _, files in os.walk(os.path.join(ROOT, sub)):
            for fn in files:
                if not fn.endswith(".gd"):
                    continue
                path = os.path.join(dirpath, fn)
                rel = os.path.relpath(path, ROOT).replace("\\", "/")
                with open(path, encoding="utf-8") as f:
                    for n, line in enumerate(f, 1):
                        code = line.split("#", 1)[0]
                        if UI_REF.search(code):
                            out.append(f"{rel}:{n} loads src/ui (rule 2: data -> sim -> ui)")
                        elif TREE_REF.search(code):
                            out.append(f"{rel}:{n} reaches the scene tree (rule 2)")
    return out


def main(argv):
    write = "--write" in argv
    steps = parse_steps()
    roadmap, domains = parse_roadmap(), parse_domains()
    problems = (group_problems(steps) + layer_problems() + roadmap_problems(*roadmap)
                + domain_problems(*domains) + canvas_problems())
    if problems:
        print("vault diagrams: " + str(len(problems)) + " problem(s)")
        for p in problems:
            print("  " + p)
        return 1
    stale = []
    for name, body in expected(steps, roadmap, domains).items():
        rel = TARGETS[name]
        text = read(rel)
        new, n = splice(text, name, body)
        if n != 1:
            stale.append(f"{rel}: no vault-diagram:{name} markers")
        elif new != text:
            if write:
                with open(os.path.join(ROOT, rel), "w", encoding="utf-8") as f:
                    f.write(new)
                print(f"vault diagrams: wrote {rel}")
            else:
                stale.append(f"{rel}: the {name} diagram is out of date -- run "
                             "`python tools/vault_diagrams.py --write`")
    for s in stale:
        print("vault diagrams: " + s)
    if not stale:
        print(f"vault diagrams: {len(TARGETS)} diagrams match their sources ({len(steps)} steps)")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
