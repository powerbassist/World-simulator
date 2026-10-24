"""The act-share and clamp reads of docs/design/bands-v5.2.md's B3 amendment (V5.2b).

Usage:
    APPDATA="$(mktemp -d)" godot --headless --path <checkout> --script res://tests/test_balance.gd -- --bands-reads > tip.log
    (the same at the base checkout, with this tip's tests/test_balance.gd copied in)
    python tools/act_share_reads.py base.log tip.log

`--bands-reads` prints only the months the player governs: its read window closes at
the first month out of office, an executive loss or the term limit (bands-v5.2.md,
"Correction: the read window"). The act share is the tip's own: its largest
act-written share of bloc_offset over the months the tip run governed. The clamp row
compares each tip run with the base run of the same number over the months BOTH
governed, the intersection of their MONTH lines: a base clamp after that window does
not excuse the tip, and a tip clamp after it does not count against the tip. A tip
clamp in months only the tip governed has no base to be read against; it is listed
apart, not counted.
"""
import collections
import sys


def read(path):
    managed, months = {}, collections.defaultdict(set)
    shares, clamps = collections.defaultdict(list), collections.defaultdict(list)
    for line in open(path, encoding="utf-8", errors="replace"):
        p = line.split()
        if len(p) < 3 or p[0] != "BANDREAD":
            continue
        if p[1] == "RUN":
            managed[p[2]] = p[3] == "managed=true"
        elif p[1] == "MONTH":
            months[p[2]].add(p[3])
        elif p[1] == "SHARE":
            shares[p[2]].append((p[3], p[4], abs(float(p[5]))))
        elif p[1] == "CLAMP":
            clamps[p[2]].append((p[3], p[4]))
    return managed, months, shares, clamps


def main() -> int:
    b_managed, b_months, _, b_clamps = read(sys.argv[1])
    managed, months, shares, clamps = read(sys.argv[2])
    if set(b_managed) != set(managed):
        print("WARNING: the logs ran different runs: base %s, tip %s" % (sorted(b_managed, key=int), sorted(managed, key=int)))
    print("run managed  tip-last  base-last  both-last  share (where)")
    worst_managed, worst_all, new, apart = 0.0, 0.0, [], []
    for r in sorted(managed, key=int):
        both = months[r] & b_months[r]
        best, where = 0.0, ""
        for at, bloc, v in shares[r]:
            if at in months[r] and v > best:
                best, where = v, "%s %s" % (at, bloc)
        print("%3s %-7s  %8s  %9s  %9s  %.3f %s" % (r, managed[r], max(months[r], default="-"), max(b_months[r], default="-"), max(both, default="-"), best, where))
        worst_all = max(worst_all, best)
        if managed[r]:
            worst_managed = max(worst_managed, best)
        base_on = {bloc for at, bloc in b_clamps[r] if at in both}
        first, first_apart = {}, {}
        for at, bloc in clamps[r]:  # month order, so the first hit is the first month
            if at in both and bloc not in base_on:
                first.setdefault(bloc, at)
            elif at in months[r] and at not in both:
                first_apart.setdefault(bloc, at)
        new += [(r, bloc, at) for bloc, at in sorted(first.items())]
        apart += [(r, bloc, at) for bloc, at in sorted(first_apart.items())]
    print("max act share over the tip's governed months: %.3f in the MANAGED runs (the band's row), %.3f in all" % (worst_managed, worst_all))
    print("blocs newly on the clamp over the months both governed (vs the base run of the same number): %d" % len(new))
    for r, bloc, at in new:
        print("  run %s %s from %s" % (r, bloc, at))
    print("tip clamps in months only the tip governed (no base to read against; not counted): %d" % len(apart))
    for r, bloc, at in apart:
        print("  run %s %s from %s" % (r, bloc, at))
    return 0


if __name__ == "__main__":
    sys.exit(main())
