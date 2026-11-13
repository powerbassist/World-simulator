"""Two probe tables equal up to the last printed digit of a float -- ACROSS PLATFORMS ONLY.

  python tools/json_close.py LINUX.json WINDOWS.json [--rel=2e-14]

ONLY for a table made on one platform against one made on the other: a CI (Linux)
table from the probes workflow against a Windows one. Godot's JSON.stringify prints
the same double differently on the two platforms when it sits near the 15th-digit
rounding edge (4182/11500 prints 0.363652173913044 on Windows and ...043 on Linux),
so a raw `cmp` fails on numbers that are equal.

Same platform (CI head against CI base, local against local): use `cmp`, never this.
Byte-identity is what proves a refactor moves no number: a reordered float sum shows
only in the last bit, well under 2e-14, and this tool would let it through.

Everything but floats must match exactly: keys, order of lists, ints, strings,
booleans. Line endings do not matter (the files are parsed). Every float it lets
through, equal within the tolerance but not printed the same, is listed with the
two values and their relative difference, so a reader sees what was forgiven.

Exit 0 when equal, 1 with every differing path printed, 2 on a bad argument.
Stdlib only.
"""
from __future__ import annotations

import json
import math
import sys


def diff(a, b, rel: float, path: str, out: list[str], passed: list[str]) -> None:
    if isinstance(a, float) or isinstance(b, float):
        if not (isinstance(a, (int, float)) and isinstance(b, (int, float))) or isinstance(a, bool) or isinstance(b, bool) \
                or not math.isclose(a, b, rel_tol=rel):
            out.append("%s: %r != %r" % (path, a, b))
        elif a != b:
            passed.append("%s: %r vs %r, relative difference %.2e" % (path, a, b, abs(a - b) / max(abs(a), abs(b))))
    elif isinstance(a, dict) and isinstance(b, dict):
        if list(a) != list(b):
            out.append("%s: keys differ: %s != %s" % (path, list(a), list(b)))
            return
        for k in a:
            diff(a[k], b[k], rel, "%s/%s" % (path, k), out, passed)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append("%s: %d items != %d" % (path, len(a), len(b)))
            return
        for i, (x, y) in enumerate(zip(a, b)):
            diff(x, y, rel, "%s[%d]" % (path, i), out, passed)
    elif type(a) is not type(b) or a != b:
        out.append("%s: %r != %r" % (path, a, b))


def main(argv: list[str]) -> int:
    # 2e-14, not 1e-14: a one-digit print difference at the 15th significant digit is up
    # to 1e-14 relative for a value whose leading digit is 1.
    rel = 2e-14
    files = []
    for arg in argv:
        if arg.startswith("--rel="):
            rel = float(arg[len("--rel="):])
        else:
            files.append(arg)
    if len(files) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    a, b = (json.load(open(p, encoding="utf-8")) for p in files)
    out: list[str] = []
    passed: list[str] = []
    diff(a, b, rel, "", out, passed)
    for line in passed:
        print("let through: " + line)
    for line in out:
        print("DIFFERS: " + line)
    verdict = "equal" if not out else "%d difference(s)" % len(out)
    print("json_close: %s, %d float(s) let through (rel %g)" % (verdict, len(passed), rel))
    return 0 if not out else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
