#!/usr/bin/env python3
"""The balance probe, sharded (V5.0c0): one isolated headless Godot per regime.

tools/balance_probe.gd runs its 51 regimes serially in one process, ~45 min a
run, and a byte-identity sub-block pays that twice. Each regime boots its own
loader and game, so nothing carries from one regime to the next -- this runs
them as a pool of independent probes and splices their outcome tables back in
the probe's own serial order (`--list`). The proof the split is sound is that
the merged table is `cmp`-identical to a serial run's: if a regime's numbers
depended on the regimes before it in the same process, that would show here.

  python tools/balance_parallel.py --json=PATH [-j N] [NATION]

Every probe gets a private APPDATA / XDG_DATA_HOME (suite_runner.py --isolate's
reason: user:// never touches the real user dir or another probe's), deleted on
success. The pool is one checkout's: the probes only read .godot/, as the suite
runner's own -j pool does. NOT a timing probe and not for beside one -- a pool
of eight saturates the CPU (AGENTS.md, "One Godot at a time").

The splice is textual, not parse-and-dump: Godot's JSON.stringify prints ints
and floats its own way and a round trip through any parser would not give its
bytes back. Each shard's file is the probe's `{"elections": [...], "runs":
[...]}` at two-space indent; the merge lifts the four-space-deep element blocks
out of each and writes them back in the same layout. Stdlib only.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GODOT = os.environ.get("GODOT_BIN", "godot")
PROBE = "res://tools/balance_probe.gd"


def _env(appdata: str) -> dict:
    return {**os.environ, "APPDATA": appdata, "XDG_DATA_HOME": appdata}


def _godot(args: list[str], appdata: str) -> subprocess.CompletedProcess:
    return subprocess.run([GODOT, "--headless", "--path", str(REPO), "--script", PROBE, "--"] + args,
                          cwd=str(REPO), env=_env(appdata), capture_output=True, text=True,
                          encoding="utf-8", errors="replace")


def regime_order(tmp: Path) -> list[str]:
    done = _godot(["--list"], str(tmp / "list_appdata"))
    names = []
    for line in done.stdout.splitlines():
        s = line.strip()
        # The banner and the MCP bridge's port line are not regime names.
        if s and " " not in s and not s.startswith("["):
            names.append(s)
    if done.returncode != 0 or not names:
        sys.exit("balance_parallel: `--list` gave no regimes (exit %d)\n%s" % (done.returncode, done.stderr))
    if len(set(names)) != len(names):
        sys.exit("balance_parallel: a regime name repeats, so one name would run two regimes")
    return names


def blocks(text: str, key: str) -> list[str]:
    """The element blocks of the top-level array `key`, each without its comma."""
    lines = text.split("\n")
    try:
        start = lines.index('  "%s": [' % key)
    except ValueError:
        if '  "%s": []' % key in lines or '  "%s": [],' % key in lines:
            return []
        raise ValueError("no %r array in the probe table" % key)
    out: list[str] = []
    cur: list[str] = []
    for line in lines[start + 1:]:
        if line in ("  ]", "  ],"):
            break
        if line == "    {":
            cur = [line]
        elif line in ("    }", "    },"):
            cur.append("    }")
            out.append("\n".join(cur))
            cur = []
        else:
            cur.append(line)
    return out


def merge(tables: list[str]) -> str:
    parts = []
    for key in ("elections", "runs"):
        rows = [b for t in tables for b in blocks(t, key)]
        parts.append('  "%s": [\n%s\n  ]' % (key, ",\n".join(rows)) if rows else '  "%s": []' % key)
    return "{\n" + ",\n".join(parts) + "\n}"


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", required=True, help="where the merged outcome table goes")
    ap.add_argument("-j", "--jobs", type=int, default=min(8, os.cpu_count() or 1))
    ap.add_argument("nation", nargs="?", default="", help="nation id, as the probe takes it")
    args = ap.parse_args(argv)
    if shutil.which(GODOT) is None:
        print("godot not found -- set GODOT_BIN if it is not on PATH", file=sys.stderr)
        return 2

    tmp = Path(tempfile.mkdtemp(prefix="nsim_balance_"))
    t0 = time.monotonic()
    names = regime_order(tmp)
    extra = [args.nation] if args.nation else []

    def run(i_name: tuple[int, str]) -> tuple[str, int, float]:
        i, name = i_name
        t = time.monotonic()
        out = tmp / ("%02d_%s.json" % (i, name))
        done = _godot([name] + extra + ["--json=" + str(out)], str(tmp / ("appdata_%02d" % i)))
        (tmp / ("%02d_%s.log" % (i, name))).write_text(done.stdout + done.stderr, encoding="utf-8")
        ok = done.returncode == 0 and out.is_file()
        return name, 0 if ok else (done.returncode or 1), time.monotonic() - t

    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        results = list(pool.map(run, enumerate(names)))
    failed = [(n, rc) for n, rc, _d in results if rc != 0]
    if failed:
        print("balance_parallel: %d regime(s) failed: %s -- logs kept in %s"
              % (len(failed), ", ".join("%s (exit %d)" % f for f in failed), tmp), file=sys.stderr)
        return 1

    tables = [(tmp / ("%02d_%s.json" % (i, n))).read_text(encoding="utf-8") for i, n in enumerate(names)]
    Path(args.json).write_text(merge(tables), encoding="utf-8", newline="")
    wall = time.monotonic() - t0
    slowest = max(results, key=lambda r: r[2])
    print("balance_parallel: %d regimes, -j %d, %d:%02d wall (slowest regime %s %.0f s) -> %s"
          % (len(names), args.jobs, int(wall) // 60, int(wall) % 60, slowest[0], slowest[2], args.json))
    shutil.rmtree(tmp, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
