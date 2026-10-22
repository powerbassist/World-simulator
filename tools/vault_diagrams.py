"""Generated vault diagrams, and the check that keeps them true to the code.

Two diagrams live in the vault as Mermaid between marker comments:

    <!-- vault-diagram:NAME begin ... -->
    <!-- vault-diagram:NAME end -->

* tick-order     docs/tick-order.md       -- src/sim/world_month.gd's STEPS, in run order
* layers         docs/data-architecture.md -- data -> core -> sim -> ui, real module names

    python tools/vault_diagrams.py            # check (exit 1 on any drift)
    python tools/vault_diagrams.py --write    # regenerate the blocks in place

tools/check_vault.py runs the check, so CI and a fresh clone get it. What it
fails on, and why each exists:

* The block in the doc differs from what the code now generates. A system added
  to STEPS changes the diagram; the fix is `--write`, nothing to hand-edit.
* A step in STEPS has no group, or a group names a step STEPS no longer has. The
  step-to-group table below is authored -- a grouping is a judgement, not
  something the code states -- so it is the one thing a new system must be told.
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
    ("data", "data/ -- content, read once, never mutated",
     ["data/nations", "data/parties", "data/laws", "data/events", "data/commodities",
      "data/companies", "data/people", "data/orgs", "data/glossary", "data/i18n"]),
    ("core", "src/core/ -- state, clock, save, loaders",
     ["src/core/game_state.gd", "src/core/nation_state.gd", "src/core/nation_fields.gd",
      "src/core/data_loader.gd", "src/core/loaders", "src/core/clock.gd", "src/core/save_manager.gd"]),
    ("sim", "src/sim/ -- one file per system, no UI knowledge",
     ["src/sim/world_month.gd", "src/sim/economy.gd", "src/sim/budget.gd", "src/sim/opinion.gd",
      "src/sim/legislature.gd", "src/sim/diplomacy.gd", "src/sim/orgs.gd", "src/sim/events.gd",
      "src/sim/elections.gd"]),
    ("ui", "src/ui/ -- scenes and panels, read-only over state",
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
    out = ["```mermaid", "flowchart LR"]
    for key, title, mods in LAYERS:
        out.append(f'  subgraph {key}["{title}"]')
        out.append("    direction TB")
        for i, mod in enumerate(mods):
            out.append(f'    {key}{i}["{os.path.basename(mod.rstrip("/"))}"]')
        out.append("  end")
    out += ['  data -->|"read once at startup"| core',
            '  core -->|"GameState"| sim',
            '  sim -->|"GameState, read"| ui',
            '  ui -.->|"player intent: explicit commands, e.g. Budget.commit()"| sim',
            "```", "",
            "Dependencies point one way: a file in `src/sim` or `src/core` never loads anything "
            "under `src/ui` and never reaches the scene tree. `python tools/vault_diagrams.py` "
            "fails on a violation, and on a module drawn above that no longer exists."]
    return "\n".join(out)


def block(name, body):
    return (f"<!-- vault-diagram:{name} begin (generated by tools/vault_diagrams.py --write; "
            f"do not edit) -->\n{body}\n<!-- vault-diagram:{name} end -->")


TARGETS = {"tick-order": "docs/tick-order.md", "layers": "docs/data-architecture.md"}


def expected(steps):
    return {"tick-order": render_tick(steps), "layers": render_layers()}


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
    problems = group_problems(steps) + layer_problems()
    if problems:
        print("vault diagrams: " + str(len(problems)) + " problem(s)")
        for p in problems:
            print("  " + p)
        return 1
    stale = []
    for name, body in expected(steps).items():
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
        print(f"vault diagrams: {len(TARGETS)} diagrams match the code ({len(steps)} steps)")
    return 1 if stale else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
