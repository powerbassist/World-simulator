"""The act-share and clamp reads of docs/design/bands-v5.2.md's B3 amendment (V5.2b).

Usage:
    APPDATA="$(mktemp -d)" godot --headless --path <checkout> --script res://tests/test_balance.gd -- --bands-reads > tip.log
    (the same at the base checkout, with this tip's tests/test_balance.gd copied in)
    python tools/act_share_reads.py base.log tip.log

Every test_balance run is played to month 168 past a lost office (`--bands-reads`). The
script reports the largest act-written share of bloc_offset per run -- before the first
2032 vote and over the whole run -- and every bloc the tip puts on its +-1 clamp that the
base run with the same number never did.
"""
import collections
import sys

FIRST_2032_VOTE = "2032-05"


def read(path):
    managed, share, pre, at_max, clamps, first = {}, collections.defaultdict(float), collections.defaultdict(float), {}, collections.defaultdict(set), {}
    for line in open(path, encoding="utf-8", errors="replace"):
        p = line.split()
        if len(p) < 3 or p[0] != "BANDREAD":
            continue
        if p[1] == "RUN":
            managed[p[2]] = p[3] == "managed=true"
        elif p[1] == "SHARE":
            run, at, bloc, v = p[2], p[3], p[4], abs(float(p[5]))
            if v > share[run]:
                share[run], at_max[run] = v, (at, bloc)
            if at < FIRST_2032_VOTE:
                pre[run] = max(pre[run], v)
        elif p[1] == "CLAMP":
            clamps[p[2]].add(p[4])
            first.setdefault((p[2], p[4]), p[3])
    return managed, share, pre, at_max, clamps, first


def main() -> int:
    base, tip = read(sys.argv[1]), read(sys.argv[2])
    managed, share, pre, at_max, clamps, first = tip
    runs = sorted(set(managed) | set(share), key=int)
    print("run managed  share-before-2032  share-whole-run (where)")
    for r in runs:
        print("%3s %-7s  %17.3f  %15.3f %s" % (r, managed.get(r, False), pre.get(r, 0.0), share.get(r, 0.0), at_max.get(r, "")))
    print("max share before the 2032 vote: %.3f; over the whole run: %.3f" % (max(pre.values(), default=0.0), max(share.values(), default=0.0)))
    new = [(r, b, first[(r, b)]) for r in sorted(clamps, key=int) for b in sorted(clamps[r] - base[4].get(r, set()))]
    print("blocs newly on the clamp (vs the base run of the same number): %d" % len(new))
    for r, b, at in new:
        print("  run %s %s from %s%s" % (r, b, at, "  (before the 2032 vote)" if at < FIRST_2032_VOTE else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
