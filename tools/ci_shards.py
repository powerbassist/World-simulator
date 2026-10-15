"""The CI split of the suite: which test runs on which GitHub runner.

The split is a FROZEN list (tools/ci_shards.json), not computed per run, so a
red shard names the same tests every time and a diff shows when it moved. It
is balanced from measured durations, longest first onto the lightest shard
(LPT): a private repo's runner has 2 cores, so the whole suite on one runner
is ~26 min of -j2, and only a split brings it under 10.

  --check            registry on stdin; red unless every registered test is in
                     exactly one shard and every listed test is registered
  --shard K          registry on stdin; prints shard K's tests (1-based),
                     after the same check
  --rebalance EVENTS rewrites ci_shards.json from a run's events.ndjson
                     (reports/suite_runs/<ts>/), keeping the shard count
                     unless --shards N is given

The registry stays tools/run_tests.sh's tests=() array, the only list -- it is
read on stdin (`bash tools/run_tests.sh --print-tests | ...`) so this file
never keeps a copy that could drift.
"""
from __future__ import annotations

import argparse
import heapq
import json
import sys
from pathlib import Path

SHARDS_FILE = Path(__file__).with_name("ci_shards.json")
# Workers per runner: a private repo's ubuntu-latest has 2 vCPUs, and the
# suite runner defaults to -j min(8, cpu_count). Only used for the forecast.
RUNNER_WORKERS = 2


def load() -> list[list[str]]:
    return json.loads(SHARDS_FILE.read_text(encoding="utf-8"))["shards"]


def check(registry: list[str], shards: list[list[str]]) -> list[str]:
    errors = []
    seen: dict[str, int] = {}
    for i, shard in enumerate(shards, 1):
        for t in shard:
            if t in seen:
                errors.append(f"{t} is in shard {seen[t]} and shard {i}")
            seen[t] = i
    for t in registry:
        if t not in seen:
            errors.append(f"{t} is registered but in no shard -- it would run nowhere on CI")
    for t in seen:
        if t not in registry:
            errors.append(f"{t} is in a shard but not registered in tools/run_tests.sh")
    return errors


def unit_durations(events: Path) -> dict[str, list[float]]:
    """test -> the durations of its children (one entry for a plain test)."""
    plain: dict[str, float] = {}
    children: dict[str, list[float]] = {}
    for line in events.read_text(encoding="utf-8").splitlines():
        e = json.loads(line)
        if e.get("event") == "child_done":
            children.setdefault(e["test"], []).append(e["duration"])
        elif e.get("event") == "done":
            plain[e["test"]] = e["duration"]
    return {t: children.get(t) or [plain[t]] for t in set(plain) | set(children)}


def makespan(units: list[float], workers: int) -> float:
    lanes = [0.0] * workers
    for u in sorted(units, reverse=True):
        heapq.heapreplace(lanes, lanes[0] + u)
    return max(lanes)


def rebalance(registry: list[str], units: dict[str, list[float]], n: int) -> list[list[str]]:
    missing = [t for t in registry if t not in units]
    if missing:
        # A test new since the measured run: costed at the median so it lands
        # somewhere, and the next --rebalance prices it properly.
        median = sorted(sum(u) for u in units.values())[len(units) // 2]
        for t in missing:
            units[t] = [median]
    heap = [(0.0, i) for i in range(n)]
    shards: list[list[str]] = [[] for _ in range(n)]
    for t in sorted(registry, key=lambda t: -sum(units[t])):
        load_, i = heapq.heappop(heap)
        shards[i].append(t)
        heapq.heappush(heap, (load_ + sum(units[t]), i))
    order = {t: k for k, t in enumerate(registry)}
    return [sorted(s, key=order.__getitem__) for s in shards]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument("--check", action="store_true")
    g.add_argument("--shard", type=int)
    g.add_argument("--rebalance", type=Path)
    ap.add_argument("--shards", type=int)
    args = ap.parse_args()
    registry = sys.stdin.read().split()
    if not registry:
        print("no registry on stdin (bash tools/run_tests.sh --print-tests | ...)", file=sys.stderr)
        return 2

    if args.rebalance:
        units = unit_durations(args.rebalance)
        n = args.shards or len(load())
        shards = rebalance(registry, units, n)
        SHARDS_FILE.write_text(json.dumps({"shards": shards}, indent=1) + "\n", encoding="utf-8")
        for i, s in enumerate(shards, 1):
            flat = [u for t in s for u in units[t]]
            print(f"shard {i}: {len(s):3d} tests, work {sum(flat)/60:5.1f} min, "
                  f"forecast at -j{RUNNER_WORKERS} {makespan(flat, RUNNER_WORKERS)/60:5.1f} min")
        return 0

    shards = load()
    errors = check(registry, shards)
    for e in errors:
        print("ci_shards: " + e, file=sys.stderr)
    if errors:
        print("ci_shards: fix tools/ci_shards.json, or regenerate it with --rebalance", file=sys.stderr)
        return 1
    if args.shard is not None:
        if not 1 <= args.shard <= len(shards):
            print(f"ci_shards: shard {args.shard} out of 1..{len(shards)}", file=sys.stderr)
            return 2
        print("\n".join(shards[args.shard - 1]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
