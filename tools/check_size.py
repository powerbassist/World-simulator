#!/usr/bin/env python3
"""The size ratchet (V5.0b): a file past a few hundred lines is doing two jobs.

AGENTS.md's rule 3 says split it then; this makes "then" a CI failure rather than
a judgement re-made each block. Counted on CODE lines -- no blank line, no line
that is only a comment -- because comments are the house style, not a second job.

  src/**/*.gd   one rule, per folder. Each file has a MAXIMUM, its folder's:
                NEW_FILE_MAX code lines (300), 400 under src/ui (NEW_FILE_MAX_BY_FOLDER --
                panels are long by grammar, a sim or core module that long is two jobs).
                A file at or under its maximum is not listed and may grow to it. A file
                OVER its maximum must be listed in tools/size_baseline.json, may shrink
                and never grow, and is delisted (--update) once it is back at or under
                its maximum; the baseline is lowered in the change that shrinks it, so
                the ratchet only ever turns one way. An over-maximum path that is not
                listed is refused unless it is a move of a listed file (below). No file
                past TOTAL_MAX total lines (the most an agent reads in one call),
                EXCEPT the named ones below until their block splits them.
  tools/, tests/ files past TOTAL_MAX total lines are printed, not failed
                (the parent session's ruling: a probe or a fixture-heavy test is
                not a module, but it should be seen).

Usage: python tools/check_size.py            (CI; exit 1 on a violation)
       python tools/check_size.py --update   (rewrite the baseline from the tree,
                                              refusing to RAISE or ADD any entry; a
                                              listed file that moved hands its allowance
                                              to ONE over-maximum path no larger than it)
       python tools/check_size.py --init     (the one-time first baseline: admits
                                              every file over its maximum as it stands)
       python tools/check_size.py --selftest (the rules above on fake trees; no repo read)
Stdlib only; reads `git ls-files` (tracked plus not-yet-staged, ignored files out).
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
BASELINE = REPO / "tools" / "size_baseline.json"
NEW_FILE_MAX = 300
# Per-folder override of the new-file maximum, by path prefix; the longest match wins.
NEW_FILE_MAX_BY_FOLDER = {"src/ui/": 400}
TOTAL_MAX = 2000
# The single named exception, until V5.1c dissolves it (docs/tiers/v5.md).
TOTAL_EXCEPTIONS: dict[str, str] = {}  # main.gd's closed at V5.1-d2 (the desk cards moved out)


def max_for(path: str) -> int:
    best = ""
    for prefix in NEW_FILE_MAX_BY_FOLDER:
        if path.startswith(prefix) and len(prefix) > len(best):
            best = prefix
    return NEW_FILE_MAX_BY_FOLDER[best] if best else NEW_FILE_MAX


def maxima_text() -> str:
    folders = ", ".join("%d under %s" % (v, k.rstrip("/")) for k, v in NEW_FILE_MAX_BY_FOLDER.items())
    return "%d, %s" % (NEW_FILE_MAX, folders) if folders else str(NEW_FILE_MAX)


def code_lines(text: str) -> int:
    n = 0
    for line in text.splitlines():
        s = line.strip()
        if s and not s.startswith("#"):
            n += 1
    return n


def tracked(prefix: str, suffixes: tuple[str, ...]) -> list[str]:
    # --others: a new file is held to the rule before it is staged, which is
    # when splitting it is cheap; --exclude-standard keeps ignored scratch out.
    out = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard",
                          prefix], cwd=REPO, capture_output=True, text=True,
                         check=True).stdout
    return sorted(p for p in out.splitlines() if p.endswith(suffixes) and (REPO / p).is_file())


def measure() -> dict[str, tuple[int, int]]:
    sizes = {}
    for p in tracked("src", (".gd",)):
        text = (REPO / p).read_text(encoding="utf-8", errors="replace")
        sizes[p] = (code_lines(text), len(text.splitlines()))
    return sizes


def check(sizes: dict[str, tuple[int, int]], baseline: dict[str, int]) -> list[str]:
    """The CI verdict: every violation, as a message. Pure, so --selftest can run it."""
    failures = []
    for p, (code, total) in sizes.items():
        limit = max_for(p)
        if p in baseline:
            if code > baseline[p]:
                failures.append("%s grew to %d code lines, baseline %d: split it rather than grow it"
                                % (p, code, baseline[p]))
            elif code <= limit:
                failures.append("%s is at %d code lines, within its folder's maximum of %d, but is "
                                "still listed: run --update to delist it"
                                % (p, code, limit))
            elif code < baseline[p]:
                failures.append("%s shrank to %d code lines from %d: lower the baseline "
                                "(python tools/check_size.py --update) so it cannot grow back"
                                % (p, code, baseline[p]))
        elif code > limit:
            failures.append("%s has %d code lines: a file not in the baseline stays at or under %d"
                            % (p, code, limit))
        if total > TOTAL_MAX and p not in TOTAL_EXCEPTIONS:
            failures.append("%s has %d total lines, past %d: split it by job"
                            % (p, total, TOTAL_MAX))
    for p in baseline:
        if p not in sizes:
            failures.append("%s is in the baseline but no longer tracked: run --update" % p)
    return failures


def plan_update(sizes: dict[str, tuple[int, int]], baseline: dict[str, int],
                init: bool = False) -> tuple[dict[str, int] | None, list[str]]:
    """The new baseline, or None and the refusal. Pure, so --selftest can run it.

    The one rule: a path is listed iff it is over ITS folder's maximum. A listed file
    keeps (or lowers) its allowance; an over-maximum path that was not listed may take
    the allowance of ONE listed file that left the tree, the smallest one that still
    covers it (a move or a rename, which must not become a forced split or a hand edit
    of the JSON) -- whatever folder either lives in. Anything else is refused."""
    msgs: list[str] = []
    new: dict[str, int] = {}
    over = {p: code for p, (code, _t) in sizes.items() if code > max_for(p)}
    for p, code in over.items():
        if p in baseline and code > baseline[p]:
            return None, ["refusing to raise %s from %d to %d code lines -- split it instead"
                          % (p, baseline[p], code)]
        if p in baseline or init:
            new[p] = code
    vacated = sorted((v, q) for q, v in baseline.items() if q not in sizes)
    # Largest newcomers first, so a big move is not starved by a small one that fits anywhere.
    for p, code in sorted(over.items(), key=lambda kv: -kv[1]):
        if p in new:
            continue
        pick = next(((v, q) for v, q in vacated if v >= code), None)
        if pick is None:
            return None, ["refusing to admit %s at %d code lines: a new file stays at or under %d"
                          % (p, code, max_for(p))]
        vacated.remove(pick)
        msgs.append("%s takes over %s's allowance (a move)" % (p, pick[1]))
        new[p] = code
    return new, msgs


def baseline_note() -> str:
    return ("Code lines per src/ file over its folder's maximum (%s), the most each may hold. "
            "Lowered by `python tools/check_size.py --update` in the change that shrinks a "
            "file; delisted once it is back under its maximum; never raised "
            "(tools/check_size.py)." % maxima_text())


def selftest() -> int:
    """The ratchet's rules on fake trees: no git, no baseline file read."""
    bad = []

    def expect(label: str, cond: bool) -> None:
        if not cond:
            bad.append(label)

    ui, sim, core = "src/ui/a.gd", "src/sim/a.gd", "src/core/a.gd"
    expect("ui 350 unlisted passes", not check({ui: (350, 350)}, {}))
    expect("ui 400 passes", not check({ui: (400, 400)}, {}))
    expect("ui 401 fails", bool(check({ui: (401, 401)}, {})))
    expect("sim 350 fails", bool(check({sim: (350, 350)}, {})))
    expect("sim 300 passes", not check({sim: (300, 300)}, {}))
    expect("core 301 fails", bool(check({core: (301, 301)}, {})))
    expect("longest prefix wins", max_for("src/ui/x/y.gd") == 400 and max_for("src/sim/x.gd") == 300)
    # Listed files: shrink-only, delisted at or under the folder's maximum.
    expect("listed grew fails", bool(check({sim: (501, 501)}, {sim: 500})))
    expect("listed shrank fails until updated", bool(check({sim: (450, 450)}, {sim: 500})))
    expect("listed equal passes", not check({sim: (500, 500)}, {sim: 500}))
    expect("listed ui 340 must be delisted", bool(check({ui: (340, 340)}, {ui: 340})))
    expect("listed sim 340 stays listed", not check({sim: (340, 340)}, {sim: 340}))
    expect("listed gone fails", bool(check({}, {sim: 500})))
    # --update.
    new, _ = plan_update({ui: (340, 340)}, {ui: 340})
    expect("update delists a ui file under 400", new == {})
    new, _ = plan_update({sim: (450, 450)}, {sim: 500})
    expect("update lowers a listed file", new == {sim: 450})
    new, _ = plan_update({sim: (501, 501)}, {sim: 500})
    expect("update refuses to raise", new is None)
    new, _ = plan_update({sim: (350, 350)}, {})
    expect("update refuses a new sim file at 350", new is None)
    new, _ = plan_update({ui: (350, 350)}, {})
    expect("update admits nothing for ui 350 (not over)", new == {})
    # The reviewer's three cases.
    old_sim, new_ui, new_sim = "src/sim/old.gd", "src/ui/moved.gd", "src/sim/new.gd"
    new, _ = plan_update({"src/ui/tab.gd": (380, 380)}, {"src/ui/panel.gd": 380})
    expect("rename of a 380 ui file (listed) is just under 400: no entry", new == {})
    new, _ = plan_update({new_ui: (420, 420)}, {old_sim: 500})
    expect("a listed sim file moved into src/ui at 420 takes the allowance", new == {new_ui: 420})
    new, _ = plan_update({new_ui: (350, 350)}, {old_sim: 500})
    expect("a listed sim file moved into src/ui at 350 is a plain ui file", new == {})
    new, _ = plan_update({"src/sim/moved.gd": (500, 500), new_sim: (370, 370)}, {old_sim: 500})
    expect("rename plus a new 370 sim file: refused, no allowance stolen", new is None)
    new, _ = plan_update({"src/sim/moved.gd": (500, 500), new_sim: (370, 370)},
                         {old_sim: 500, "src/sim/old2.gd": 400})
    expect("two vacated allowances cover the two newcomers, best fit",
           new == {"src/sim/moved.gd": 500, new_sim: 370})
    new, _ = plan_update({sim: (700, 700)}, {}, init=True)
    expect("--init admits what stands", new == {sim: 700})
    expect("note names the maxima", "300" in baseline_note() and "400" in baseline_note())
    for label in bad:
        print("check_size selftest FAIL: " + label, file=sys.stderr)
    if not bad:
        print("check_size selftest: ok")
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    if "--selftest" in argv:
        return selftest()
    sizes = measure()
    baseline: dict[str, int] = {}
    if BASELINE.is_file():
        baseline = json.loads(BASELINE.read_text(encoding="utf-8"))["code_lines"]

    if "--update" in argv or "--init" in argv:
        init = "--init" in argv
        if init and BASELINE.is_file():
            print("refusing --init: the baseline exists, and --init would admit any file "
                  "over its maximum -- use --update", file=sys.stderr)
            return 1
        new, msgs = plan_update(sizes, baseline, init)
        if new is None:
            for m in msgs:
                print(m, file=sys.stderr)
            return 1
        for m in msgs:
            print(m)
        BASELINE.write_text(json.dumps({"_note": baseline_note(), "code_lines": new},
                                       indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print("size baseline: %d files over their folder's maximum" % len(new))
        return 0

    failures = check(sizes, baseline)
    for prefix, suffixes in (("tools", (".gd", ".py", ".sh")), ("tests", (".gd",))):
        for p in tracked(prefix, suffixes):
            total = len((REPO / p).read_text(encoding="utf-8", errors="replace").splitlines())
            if total > TOTAL_MAX:
                print("note: %s has %d total lines (tools/ and tests/ are printed, not failed)"
                      % (p, total))

    for f in failures:
        print("check_size: " + f, file=sys.stderr)
    if failures:
        return 1
    print("check_size: %d src files, %d in the baseline, clean" % (len(sizes), len(baseline)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
