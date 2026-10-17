"""Diff two balance-probe outcome tables: what a re-baseline moved.

tools/balance_probe.gd writes the table with `--json=PATH` -- one row per verdict
it prints and one per run. A re-baseline used to be read by eye across ~1700
lines of text; this reads the two tables and prints only what changed:

  FLIP     a verdict that changed (HELD -> LOST, majority -> MINORITY, ...)
  MARGIN   the same verdict on a lead that moved more than --tol
  ONLY     a vote held in one tree and not the other (a run that ended sooner)
  RUN      a run whose end state moved (left office, invariant problems, acts)

  python tools/balance_diff.py base.json tip.json [--tol 0.005]

Exit 0 when nothing moved past the tolerance, 1 when something did, 2 on bad
input -- so a re-baseline that is meant to be a no-op can be gated on it.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

RUN_FIELDS = ("out_of_government", "problems", "unrest_acts")


def _load(path: Path) -> dict:
    try:
        table = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"balance_diff: cannot read {path}: {e}", file=sys.stderr)
        sys.exit(2)
    if not isinstance(table, dict) or "elections" not in table or "runs" not in table:
        print(f"balance_diff: {path} is not a balance_probe outcome table", file=sys.stderr)
        sys.exit(2)
    return table


def _key(row: dict) -> tuple:
    return (row["regime"], row["nation"], int(row["year"]), int(row["month"]), row["kind"])


def _label(key: tuple) -> str:
    regime, nation, year, month, kind = key
    return f"{regime} ({nation}) {year}-{month:02d} {kind}"


def diff(base: dict, tip: dict, tol: float) -> list[str]:
    out: list[str] = []
    a = {_key(r): r for r in base["elections"]}
    b = {_key(r): r for r in tip["elections"]}
    for key in sorted(a.keys() | b.keys()):
        if key not in b:
            out.append(f"ONLY base  {_label(key)}: {a[key]['verdict']}")
            continue
        if key not in a:
            out.append(f"ONLY tip   {_label(key)}: {b[key]['verdict']}")
            continue
        ra, rb = a[key], b[key]
        ma, mb = float(ra["margin"]), float(rb["margin"])
        if ra["verdict"] != rb["verdict"]:
            out.append(f"FLIP       {_label(key)}: {ra['verdict']} -> {rb['verdict']} "
                       f"(margin {ma:+.4f} -> {mb:+.4f})")
        elif abs(mb - ma) > tol:
            out.append(f"MARGIN     {_label(key)}: {ra['verdict']}, margin {ma:+.4f} -> {mb:+.4f} "
                       f"({mb - ma:+.4f})")

    ra_runs = {(r["regime"], r["nation"]): r for r in base["runs"]}
    rb_runs = {(r["regime"], r["nation"]): r for r in tip["runs"]}
    for key in sorted(ra_runs.keys() | rb_runs.keys()):
        if key not in ra_runs or key not in rb_runs:
            side = "base" if key in ra_runs else "tip"
            out.append(f"RUN        {key[0]} ({key[1]}): only in {side}")
            continue
        moved = [f"{f} {ra_runs[key].get(f)!r} -> {rb_runs[key].get(f)!r}"
                 for f in RUN_FIELDS if ra_runs[key].get(f) != rb_runs[key].get(f)]
        if moved:
            out.append(f"RUN        {key[0]} ({key[1]}): " + ", ".join(moved))
    return out


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("base", type=Path)
    parser.add_argument("tip", type=Path)
    parser.add_argument("--tol", type=float, default=0.005,
                        help="margin change (vote-share points, 0-1 scale) worth reporting; default 0.005")
    args = parser.parse_args(argv)
    base, tip = _load(args.base), _load(args.tip)
    lines = diff(base, tip, args.tol)
    flips = sum(1 for line in lines if line.startswith("FLIP"))
    for line in lines:
        print(line)
    print(f"balance_diff: {len(base['elections'])} vs {len(tip['elections'])} verdicts, "
          f"{flips} flipped, {len(lines)} change(s) past tol {args.tol}")
    return 1 if lines else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
