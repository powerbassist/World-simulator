"""The shadows probe, sharded (V5.2c): one isolated headless Godot per (regime, seeds).

tools/shadows_probe.gd runs 200 seeds of four regimes, each seed a fresh France game
of 60 months -- hours serially. Every seed boots its own game, so nothing carries
from one to the next; this runs chunks of seeds as a pool of independent probes,
concatenates their rows, and hands them back to the probe's own `--summarize`, so
the bands' arithmetic lives in one place (the probe) and a sharded run and a
single run read the same numbers.

  python tools/shadows_parallel.py --json=PATH [-j N] [--seeds=0-199] [--chunk=25]
         [--regimes=S1,S2,S3,S4] [--exact=10] [--trace]

Isolation, the cold import and the pool are balance_parallel.py's: a private
APPDATA / XDG_DATA_HOME per probe, one checkout read-only, one --import first if
.godot/ is absent. NOT a timing probe and not for beside one -- the pool
saturates the CPU (AGENTS.md, "One Godot at a time"). Stdlib only.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import balance_parallel as bp

PROBE = "res://tools/shadows_probe.gd"
bp.PROBE = PROBE


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", required=True, help="where the merged rows and the summary go")
    ap.add_argument("-j", "--jobs", type=int, default=min(8, os.cpu_count() or 1))
    ap.add_argument("--seeds", default="0-199")
    ap.add_argument("--chunk", type=int, default=25, help="seeds per probe")
    ap.add_argument("--regimes", default="S1,S2,S3,S4")
    ap.add_argument("--exact", type=int, default=10, help="S1 seeds re-run with the real act")
    ap.add_argument("--trace", action="store_true", help="S1's roll and pressure rows, for re-pricing RATE")
    args = ap.parse_args(argv)
    if shutil.which(bp.GODOT) is None:
        print("godot not found -- set GODOT_BIN if it is not on PATH", file=sys.stderr)
        return 2
    lo, hi = (int(x) for x in args.seeds.split("-"))
    regimes = args.regimes.split(",")
    shards = []
    for regime in regimes:
        for start in range(lo, hi + 1, args.chunk):
            extra = ["--trace"] if args.trace and regime == "S1" else []
            if regime == "S1" and start == lo and args.exact > 0:
                extra.append("--exact=%d" % args.exact)
            shards.append((regime, start, min(hi, start + args.chunk - 1), extra))

    tmp = Path(tempfile.mkdtemp(prefix="nsim_shadows_"))
    t0 = time.monotonic()
    if not (bp.REPO / ".godot").is_dir():
        print("no .godot/ -- importing once so the script class cache exists", file=sys.stderr)
        bp._godot(["--import"], str(tmp / "import_appdata"), script=False)

    def run(i_shard):
        i, (regime, a, b, extra) = i_shard
        out = tmp / ("%02d_%s_%d-%d.json" % (i, regime, a, b))
        rc, text = bp._godot(["--regimes=" + regime, "--seeds=%d-%d" % (a, b), "--json=" + str(out)] + extra,
                             str(tmp / ("appdata_%02d" % i)))
        (tmp / ("%02d_%s.log" % (i, regime))).write_text(text, encoding="utf-8")
        return out, 0 if rc == 0 and out.is_file() else (rc or 1)

    try:
        with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
            results = list(pool.map(run, enumerate(shards)))
    except KeyboardInterrupt:
        bp._kill_all()
        print("shadows_parallel: interrupted -- logs kept in %s" % tmp, file=sys.stderr)
        return 130
    failed = [str(out.name) for out, rc in results if rc != 0]
    if failed:
        print("shadows_parallel: %d shard(s) failed: %s -- logs kept in %s" % (len(failed), ", ".join(failed), tmp),
              file=sys.stderr)
        return 1
    rows = [row for out, _rc in results for row in json.loads(out.read_text(encoding="utf-8"))["rows"]]
    merged = tmp / "merged.json"
    merged.write_text(json.dumps({"rows": rows}), encoding="utf-8")
    summary_path = tmp / "summary.json"
    rc, text = bp._godot(["--summarize=" + str(merged), "--json=" + str(summary_path)], str(tmp / "appdata_sum"))
    print(text.strip())
    if rc != 0 or not summary_path.is_file():
        print("shadows_parallel: the summary failed -- logs kept in %s" % tmp, file=sys.stderr)
        return 1
    summary = json.loads(summary_path.read_text(encoding="utf-8"))["summary"]
    Path(args.json).write_text(json.dumps({"rows": rows, "summary": summary}, indent=1), encoding="utf-8")
    wall = time.monotonic() - t0
    print("shadows_parallel: %d shards, -j %d, %d:%02d wall -> %s" % (len(shards), args.jobs, int(wall) // 60,
                                                                    int(wall) % 60, args.json))
    shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
