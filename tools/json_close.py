"""Two probe tables equal up to the last printed digit of a float.

  python tools/json_close.py A.json B.json [--rel=1e-14]

For a probe table made on Linux (the probes workflow on GitHub) against one made on
Windows. Godot's JSON.stringify prints the same double differently on the two
platforms when it sits near the 15th-digit rounding edge (4182/11500 prints
0.363652173913044 on Windows and ...043 on Linux), so a raw `cmp` fails on numbers
that are equal. Everything but floats must match exactly: keys, order of lists,
ints, strings, booleans. Line endings do not matter (the files are parsed).

Exit 0 when equal, 1 with every differing path printed, 2 on a bad argument.
Same platform, use `cmp`: it is the stronger check. Stdlib only.
"""
from __future__ import annotations

import json
import math
import sys


def diff(a, b, rel: float, path: str, out: list[str]) -> None:
    if isinstance(a, float) or isinstance(b, float):
        if not (isinstance(a, (int, float)) and isinstance(b, (int, float))) or isinstance(a, bool) or isinstance(b, bool) \
                or not math.isclose(a, b, rel_tol=rel, abs_tol=rel):
            out.append("%s: %r != %r" % (path, a, b))
    elif isinstance(a, dict) and isinstance(b, dict):
        if list(a) != list(b):
            out.append("%s: keys differ: %s != %s" % (path, list(a), list(b)))
            return
        for k in a:
            diff(a[k], b[k], rel, "%s/%s" % (path, k), out)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            out.append("%s: %d items != %d" % (path, len(a), len(b)))
            return
        for i, (x, y) in enumerate(zip(a, b)):
            diff(x, y, rel, "%s[%d]" % (path, i), out)
    elif type(a) is not type(b) or a != b:
        out.append("%s: %r != %r" % (path, a, b))


def main(argv: list[str]) -> int:
    rel = 1e-14
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
    diff(a, b, rel, "", out)
    for line in out:
        print(line)
    print("json_close: %s (rel %g)" % ("equal" if not out else "%d difference(s)" % len(out), rel))
    return 0 if not out else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
