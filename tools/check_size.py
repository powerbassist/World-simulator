#!/usr/bin/env python3
"""The size ratchet (V5.0b): a file past a few hundred lines is doing two jobs.

AGENTS.md's rule 3 says split it then; this makes "then" a CI failure rather than
a judgement re-made each block. Counted on CODE lines -- no blank line, no line
that is only a comment -- because comments are the house style, not a second job.

  src/**/*.gd   a new file stays at or under NEW_FILE_MAX code lines; a file in
                tools/size_baseline.json may shrink and never grow, and the
                baseline must be lowered (--update) in the change that shrinks
                it, so the ratchet only ever turns one way; no file past
                TOTAL_MAX total lines (the most an agent reads in one call),
                EXCEPT the named ones below until their block splits them.
  tools/, tests/ files past TOTAL_MAX total lines are printed, not failed
                (the parent session's ruling: a probe or a fixture-heavy test is
                not a module, but it should be seen).

Usage: python tools/check_size.py            (CI; exit 1 on a violation)
       python tools/check_size.py --update   (rewrite the baseline from the tree,
                                              refusing to RAISE or ADD any entry)
       python tools/check_size.py --init     (the one-time first baseline: admits
                                              every file over the line as it stands)
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
TOTAL_MAX = 2000
# The single named exception, until V5.1c dissolves it (docs/tiers/v5.md).
TOTAL_EXCEPTIONS = {"src/ui/main.gd": "V5.1c dissolves main.gd"}


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


def main(argv: list[str]) -> int:
    sizes = measure()
    baseline: dict[str, int] = {}
    if BASELINE.is_file():
        baseline = json.loads(BASELINE.read_text(encoding="utf-8"))["code_lines"]

    if "--update" in argv or "--init" in argv:
        init = "--init" in argv
        if init and BASELINE.is_file():
            print("refusing --init: the baseline exists, and --init would admit any file "
                  "over the line -- use --update", file=sys.stderr)
            return 1
        new = {}
        for p, (code, _total) in sizes.items():
            if code <= NEW_FILE_MAX:
                continue
            if p in baseline and code > baseline[p]:
                print("refusing to raise %s from %d to %d code lines -- split it instead"
                      % (p, baseline[p], code), file=sys.stderr)
                return 1
            if p not in baseline and not init:
                print("refusing to admit %s at %d code lines: a new file stays at or under %d"
                      % (p, code, NEW_FILE_MAX), file=sys.stderr)
                return 1
            new[p] = code
        BASELINE.write_text(json.dumps({
            "_note": "Code lines per src/ file over %d, the most each may hold. Lowered by "
                     "`python tools/check_size.py --update` in the change that shrinks a file; "
                     "never raised (tools/check_size.py)." % NEW_FILE_MAX,
            "code_lines": new,
        }, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        print("size baseline: %d files over %d code lines" % (len(new), NEW_FILE_MAX))
        return 0

    failures = []
    for p, (code, total) in sizes.items():
        if p in baseline:
            if code > baseline[p]:
                failures.append("%s grew to %d code lines, baseline %d: split it rather than grow it"
                                % (p, code, baseline[p]))
            elif code < baseline[p]:
                failures.append("%s shrank to %d code lines from %d: lower the baseline "
                                "(python tools/check_size.py --update) so it cannot grow back"
                                % (p, code, baseline[p]))
        elif code > NEW_FILE_MAX:
            failures.append("%s has %d code lines: a file not in the baseline stays at or under %d"
                            % (p, code, NEW_FILE_MAX))
        if total > TOTAL_MAX and p not in TOTAL_EXCEPTIONS:
            failures.append("%s has %d total lines, past %d: split it by job"
                            % (p, total, TOTAL_MAX))
    for p in baseline:
        if p not in sizes:
            failures.append("%s is in the baseline but no longer tracked: run --update" % p)

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
