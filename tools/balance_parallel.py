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
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GODOT = os.environ.get("GODOT_BIN", "godot")
PROBE = "res://tools/balance_probe.gd"
# A regime runs ~1-2 min under a full pool; an hour is a hang, not a slow regime.
TIMEOUT_S = 3600.0

# Live children, killed on an interrupt: the pool's threads own them, and a
# killed runner must not leave eight Godots saturating the CPU behind it
# (suite_runner.py's _LIVE_CHILDREN, for the same reason).
_LIVE: set = set()
_LIVE_LOCK = threading.Lock()


class Failed(Exception):
    pass


def _env(appdata: str) -> dict:
    return {**os.environ, "APPDATA": appdata, "XDG_DATA_HOME": appdata}


def _godot(args: list[str], appdata: str, script: bool = True) -> tuple[int, str]:
    cmd = [GODOT, "--headless", "--path", str(REPO)]
    cmd += (["--script", PROBE, "--"] + args) if script else args
    proc = subprocess.Popen(cmd, cwd=str(REPO), env=_env(appdata), stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    with _LIVE_LOCK:
        _LIVE.add(proc)
    try:
        out, _ = proc.communicate(timeout=TIMEOUT_S)
        return proc.returncode, out or ""
    except subprocess.TimeoutExpired:
        proc.kill()
        return -1, "balance_parallel: timed out after %.0f s" % TIMEOUT_S
    finally:
        with _LIVE_LOCK:
            _LIVE.discard(proc)


def _kill_all() -> None:
    with _LIVE_LOCK:
        live = list(_LIVE)
    for proc in live:
        try:
            proc.kill()
        except OSError:
            pass


def regime_order(tmp: Path) -> list[str]:
    rc, out = _godot(["--list"], str(tmp / "list_appdata"))
    # Prefixed lines only: the banner, the MCP bridge and any stray print are not regimes.
    names = [l.strip()[len("REGIME "):] for l in out.splitlines() if l.strip().startswith("REGIME ")]
    if rc != 0 or not names:
        raise Failed("`--list` gave no regimes (exit %d)\n%s" % (rc, out))
    if len(set(names)) != len(names):
        raise Failed("a regime name repeats, so one name would run two regimes")
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
    merged = "{\n" + ",\n".join(parts) + "\n}"
    # The splice reads a layout, so check it kept every row: the merged table must
    # parse, and hold exactly the shards' rows in the shards' order.
    want = {k: [r for t in tables for r in json.loads(t)[k]] for k in ("elections", "runs")}
    got = json.loads(merged)
    if any(got[k] != want[k] for k in want):
        raise Failed("the splice lost or reordered rows -- has _write_outcomes's layout changed?")
    return merged


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
    try:
        results, names = _run_pool(args, tmp)
    except (Failed, KeyboardInterrupt) as exc:
        _kill_all()
        print("balance_parallel: %s -- logs kept in %s"
              % ("interrupted" if isinstance(exc, KeyboardInterrupt) else exc, tmp), file=sys.stderr)
        return 130 if isinstance(exc, KeyboardInterrupt) else 1
    failed = [(n, rc) for n, rc, _d in results if rc != 0]
    if failed:
        print("balance_parallel: %d regime(s) failed: %s -- logs kept in %s"
              % (len(failed), ", ".join("%s (exit %d)" % f for f in failed), tmp), file=sys.stderr)
        return 1

    tables = [(tmp / ("%02d_%s.json" % (i, n))).read_text(encoding="utf-8") for i, n in enumerate(names)]
    try:
        merged = merge(tables)
    except (Failed, ValueError) as exc:
        print("balance_parallel: %s -- shard tables kept in %s" % (exc, tmp), file=sys.stderr)
        return 1
    Path(args.json).write_text(merged, encoding="utf-8", newline="")
    wall = time.monotonic() - t0
    slowest = max(results, key=lambda r: r[2])
    print("balance_parallel: %d regimes, -j %d, %d:%02d wall (slowest regime %s %.0f s) -> %s"
          % (len(names), args.jobs, int(wall) // 60, int(wall) % 60, slowest[0], slowest[2], args.json))
    shutil.rmtree(tmp, ignore_errors=True)
    return 0


def _run_pool(args, tmp: Path) -> tuple[list, list[str]]:
    # A cold checkout has no .godot/ and so no script class cache: one isolated
    # import first, as suite_runner.py does, rather than eight probes racing to
    # build it (and DialogueManager failing to parse in each).
    if not (REPO / ".godot").is_dir():
        print("no .godot/ -- importing once so the script class cache exists", file=sys.stderr)
        _godot(["--import"], str(tmp / "import_appdata"), script=False)
    names = regime_order(tmp)
    extra = [args.nation] if args.nation else []

    def run(i_name: tuple[int, str]) -> tuple[str, int, float]:
        i, name = i_name
        t = time.monotonic()
        out = tmp / ("%02d_%s.json" % (i, name))
        rc, text = _godot([name] + extra + ["--json=" + str(out)], str(tmp / ("appdata_%02d" % i)))
        (tmp / ("%02d_%s.log" % (i, name))).write_text(text, encoding="utf-8")
        ok = rc == 0 and out.is_file()
        return name, 0 if ok else (rc or 1), time.monotonic() - t

    with ThreadPoolExecutor(max_workers=max(1, args.jobs)) as pool:
        return list(pool.map(run, enumerate(names))), names


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
