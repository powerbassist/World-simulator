#!/usr/bin/env python3
"""The suite's one execution core (V3.6 tooling, 2026-09-11 spec).

tools/run_tests.sh keeps the registry and delegates here so the gate's
semantics live in exactly one place: non-zero exit or a SCRIPT ERROR in the
output is a failure, MCP bridge noise is filtered from display but never
from the verdict, any failure exits 1. Agents run `--ci`; the cockpit reads
the same events. Stdlib only -- a cold clone needs nothing installed.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
REPORTS = REPO / "reports"

# Ported verbatim from the bash loop this replaces (V1.7c's third-stray-line
# lesson: filter the bridge noise, never let it hide a real line).
MCP_NOISE = re.compile(r"^\[MCP(RuntimeServer|Registry)\]")
SCRIPT_ERROR = re.compile(r"SCRIPT ERROR|Parse Error")
# Tags read from the test's own source -- run_tests.sh counts the directory
# the same way rather than keeping a second list.
EXCLUSIVE_TAG = re.compile(r"^## suite-exclusive: *(.+)$", re.MULTILINE)
SHARD_TAG = re.compile(r"^## suite-shard-checks: *(.+)$", re.MULTILINE)

GODOT = os.environ.get("GODOT_BIN", "godot")


@dataclass
class TestResult:
    name: str
    status: str = "fail"  # pass | fail | timeout
    duration: float = 0.0
    sharded: bool = False
    checks: list[str] = field(default_factory=list)
    log_text: str = ""


def filter_noise(lines: list[str]) -> list[str]:
    return [ln for ln in lines if not MCP_NOISE.match(ln)]


def child_verdict(out: str, rc: int) -> str:
    if rc == 0 and not SCRIPT_ERROR.search(out):
        return "pass"
    return "fail"


def _tags_from_text(src: str) -> tuple[bool, list[str]]:
    exclusive = bool(EXCLUSIVE_TAG.search(src))
    m = SHARD_TAG.search(src)
    checks = [c.strip() for c in m.group(1).split(",")] if m else []
    return exclusive, checks


def read_tags(test: str) -> tuple[bool, list[str]]:
    """(exclusive?, [check names]) from the test's own source comments."""
    try:
        src = (REPO / test).read_text(encoding="utf-8")
    except OSError:
        return False, []
    return _tags_from_text(src)


def run_child(cmd: list[str], timeout: float) -> tuple[str, int, str]:
    """Returns (filtered output, exit code, status)."""
    try:
        proc = subprocess.run(
            cmd, cwd=str(REPO), stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, encoding="utf-8",
            errors="replace", timeout=timeout,
        )
        out, rc = proc.stdout, proc.returncode
        status = child_verdict(out, rc)
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or "") if isinstance(e.stdout, str) else ""
        rc, status = -1, "timeout"
    return "\n".join(filter_noise(out.splitlines())), rc, status


class RunWriter:
    """events.ndjson + per-test logs + results.json for one suite run."""

    def __init__(self, run_dir: Path | None) -> None:
        import threading
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        self.dir = run_dir or (REPORTS / "suite_runs" / stamp)
        (self.dir / "tests").mkdir(parents=True, exist_ok=True)
        self.events_path = self.dir / "events.ndjson"
        self.started = time.time()
        self._lock = threading.Lock()
        self._events = open(self.events_path, "a", encoding="utf-8")

    def event(self, obj: dict) -> None:
        obj["ts"] = time.time()
        with self._lock:  # worker threads emit child events concurrently
            self._events.write(json.dumps(obj, ensure_ascii=False) + "\n")
            self._events.flush()

    def write_log(self, result: TestResult) -> str:
        rel = "tests/%s.log" % result.name.removeprefix("tests/")
        (self.dir / rel).parent.mkdir(parents=True, exist_ok=True)
        (self.dir / rel).write_text(result.log_text, encoding="utf-8")
        return rel

    def finish(self, results: list[TestResult], interrupted: bool, jobs: int) -> int:
        exit_code = 0 if all(r.status == "pass" for r in results) and not interrupted else 1
        # The summary event goes out BEFORE the stream closes -- a closed
        # events file is the "run is over" signal for the cockpit.
        self.event({"event": "summary", "total": len(results),
                    "failed": sum(1 for r in results if r.status != "pass"),
                    "interrupted": interrupted, "exit": exit_code})
        self._events.close()
        payload = {
            "started": datetime.fromtimestamp(self.started,
                                              tz=timezone.utc).isoformat(),
            "finished": datetime.now(timezone.utc).isoformat(),
            "jobs": jobs,
            "interrupted": interrupted,
            "tests": [
                {"name": r.name, "status": r.status, "duration": round(r.duration, 3),
                 "sharded": r.sharded, "checks": r.checks}
                for r in results
            ],
            "exit": exit_code,
        }
        (self.dir / "results.json").write_text(
            json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
        return exit_code


def run_sequential(tests: list[str], timeout: float, verbose: bool,
                   writer: RunWriter) -> list[TestResult]:
    results: list[TestResult] = []
    for n, test in enumerate(tests, 1):
        writer.event({"event": "start", "test": test})
        t0 = time.monotonic()
        out, rc, status = run_child(
            [GODOT, "--headless", "--script", "res://" + test], timeout)
        result = TestResult(test, status, time.monotonic() - t0,
                            log_text=out + ("\n" if out else ""))
        rel = writer.write_log(result)
        writer.event({"event": "done", "test": test, "status": result.status,
                      "duration": round(result.duration, 3), "log": rel})
        print("[%d/%d] %s %s %.1fs" % (n, len(tests), test, result.status,
                                       result.duration), file=sys.stderr)
        if status != "pass":
            print(out)
        elif verbose:
            print(out)
        results.append(result)
    return results


# ---------------------------------------------------------------- selftest

def _selftest() -> int:
    failures: list[str] = []

    def expect(cond: bool, msg: str) -> None:
        if not cond:
            failures.append(msg)

    # The noise filter drops bridge lines and keeps a third line (V1.7c).
    kept = filter_noise([
        "[MCPRuntimeServer] listening on 127.0.0.1:6570",
        "real line",
        "[MCPRegistry] runtime port 6570 registered",
    ])
    expect(kept == ["real line"], "noise filter: %r" % kept)

    expect(child_verdict("ok", 0) == "pass", "clean run must pass")
    expect(child_verdict("SCRIPT ERROR: oops", 0) == "fail",
           "exit 0 over a script error must fail (V2.1c)")
    expect(child_verdict("x", 1) == "fail", "non-zero exit must fail")

    # Shard normalization arrives in Task 4; its cases are added there.
    ex, checks = _tags_from_text("extends SceneTree\n"
                                 "## suite-exclusive: writes user://settings.cfg\n")
    expect(ex and checks == [], "exclusive tag parse: %r %r" % (ex, checks))
    ex2, checks2 = _tags_from_text("## suite-shard-checks: _check_a, _check_b\n")
    expect(not ex2 and checks2 == ["_check_a", "_check_b"],
           "shard tag parse: %r %r" % (ex2, checks2))

    if failures:
        for f in failures:
            print("SELFTEST FAIL: %s" % f)
        return 1
    print("suite_runner selftest: all checks passed")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("tests", nargs="*", help="test paths, e.g. tests/test_clock.gd")
    ap.add_argument("--ci", action="store_true",
                    help="canonical agent gate: default output, exit 1 on any failure")
    ap.add_argument("-j", "--jobs", type=int,
                    default=min(8, os.cpu_count() or 1),
                    help="worker count (sequential order is preserved at -j1)")
    ap.add_argument("--timeout", type=float, default=1800.0,
                    help="per-child timeout seconds (a hang is red, not silent)")
    ap.add_argument("--verbose", action="store_true",
                    help="print every test's full output, green included (the old default)")
    ap.add_argument("--run-dir", default=None)
    ap.add_argument("--selftest", action="store_true")
    args = ap.parse_args(argv)

    if args.selftest:
        return _selftest()
    if not args.tests:
        ap.error("no tests given (bash tools/run_tests.sh --print-tests prints the registry)")

    if not _godot_available():
        print("godot not found -- set GODOT_BIN if it is not on PATH", file=sys.stderr)
        return 2

    # The cold-clone rule (V2.8 review): no .godot/ means no script class
    # cache, and the committed autoload does not parse. One import pass.
    if not (REPO / ".godot").is_dir():
        print("no .godot/ -- importing once so the script class cache exists",
              file=sys.stderr)
        subprocess.run([GODOT, "--headless", "--import"], cwd=str(REPO),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    writer = RunWriter(Path(args.run_dir) if args.run_dir else None)
    print("run dir: %s" % writer.dir, file=sys.stderr)
    t0 = time.monotonic()
    results = run_sequential(args.tests, args.timeout, args.verbose, writer)
    elapsed = int(time.monotonic() - t0)
    code = writer.finish(results, interrupted=False, jobs=1)
    if code == 0:
        print("test suite passed -- %d tests in %d:%02d"
              % (len(results), elapsed // 60, elapsed % 60))
    else:
        print("test suite failed", file=sys.stderr)
    return code


def _godot_available() -> bool:
    from shutil import which
    return which(GODOT) is not None


if __name__ == "__main__":
    sys.exit(main())
