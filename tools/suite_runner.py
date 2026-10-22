#!/usr/bin/env python3
"""The suite's one execution core (V3.6 tooling, 2026-09-11 spec).

tools/run_tests.sh keeps the registry and delegates here so the gate's
semantics live in exactly one place: non-zero exit, a SCRIPT ERROR, or an
`ERROR:` line the test did not declare (`## expects-error: <regex>`) in the
output is a failure, MCP bridge noise is filtered from display but never
from the verdict, any failure exits 1. Agents run `--ci`; the cockpit reads
the same events. Stdlib only -- a cold clone needs nothing installed.

There is ONE execution path: jobs run on a worker pool (default
-j min(8, cpu_count)), reported in registry order whatever order the pool
finished in. -j1 is the same code with a one-worker pool, so sequential
semantics hold by construction rather than by a second code path. Tests
tagged `## suite-exclusive:` in their own source run on a dedicated
single-worker lane -- they back up and restore the live user:// state and
must never overlap each other.
"""
from __future__ import annotations

import argparse
import contextlib
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
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
# S7 (V5.1-0d, the test audit's proposal): a test that exits 0 over an engine or
# push_error line used to pass -- test_diplomacy carried G1's two capital errors
# on every run. Now any line that STARTS with ERROR:, or the save path's
# NaN-in-JSON warning, fails it, unless it is one of the engine's at-exit leak reports
# (printed by the engine after the script is done, nothing a test can own) or it
# matches a regex the test declares in its own source with `## expects-error:`.
ERROR_LINE = re.compile(r"^(?:USER )?ERROR:.*$|^WARNING:.*NaN.*JSON\.stringify.*$",
                        re.MULTILINE)
# By SHAPE (pass 2): which at-exit report the engine prints depends on what a test
# left alive -- resources still in use, RID allocations leaked, PagedAllocator pages
# in use -- so a list of two would turn a green test red with no code change. An
# ERROR: about leaks, use or allocations AT EXIT; a test's own line that merely
# mentions exit is not one.
EXIT_LEAK = re.compile(r"^ERROR: .*\b(?:in use|leaked|allocations?)\b.*\bat exit\b")
EXPECTS_TAG = re.compile(r"^[ \t]*## expects-(?:error|warning): *(.+?)\s*$",
                         re.MULTILINE)
# Tags read from the test's own source -- run_tests.sh counts the directory
# the same way rather than keeping a second list.
EXCLUSIVE_TAG = re.compile(r"^## suite-exclusive: *(.+)$", re.MULTILINE)
SHARD_TAG = re.compile(r"^## suite-shard-checks: *(.+)$", re.MULTILINE)

GODOT = os.environ.get("GODOT_BIN", "godot")

# Live child processes, kept so an interrupt can kill them: Ctrl-C is
# delivered to the main thread only -- blocked in as_completed() -- while
# the children belong to worker threads, and a killed runner must not
# orphan godots holding user:// open against the next run's exclusive lane.
_LIVE_CHILDREN: set = set()
_CHILDREN_LOCK = threading.Lock()

# Isolation (V5.0b, the DEFAULT since 2026-10-20): the environment EVERY godot this
# runner spawns gets, the cold-clone --import included. A private APPDATA puts
# user:// (saves, settings, logs, the exclusive lane's backup) under a temp dir,
# so two runs in two checkouts cannot touch each other's state or the real user
# dir. APPDATA and not override.cfg: the isolation experiment (2026-10-19)
# measured a cold --import writing the REAL user dir with override.cfg present.
# XDG_DATA_HOME is the same move off Windows (untested there). Default on rather
# than opt-in: an opt-in flag is the one a second session forgets, and the run
# it forgets it on is the one that clobbers the first. None = inherit, which is
# what --no-isolate asks for.
_CHILD_ENV: dict | None = None


def isolated_env(base: dict, appdata: str) -> dict:
    """The child environment of an isolated run: user:// under `appdata`."""
    return {**base, "APPDATA": appdata, "XDG_DATA_HOME": appdata}


@dataclass
class TestResult:
    name: str
    status: str = "fail"  # pass | fail | timeout
    duration: float = 0.0
    sharded: bool = False
    checks: list[str] = field(default_factory=list)
    log_text: str = ""


class Interrupted(Exception):
    """Ctrl-C mid-run; carries the tests that had completed by then, in
    registry order, for the partial results.json."""

    def __init__(self, results: list[TestResult]) -> None:
        super().__init__("interrupted")
        self.results = results


def filter_noise(lines: list[str]) -> list[str]:
    return [ln for ln in lines if not MCP_NOISE.match(ln)]


def child_verdict(out: str, rc: int, expected=()) -> str:
    if rc != 0 or SCRIPT_ERROR.search(out):
        return "fail"
    for m in ERROR_LINE.finditer(out):
        line = m.group(0)
        # A tag matches as a regex or, failing that, as literal text: an engine
        # line full of parentheses is easier to paste than to escape.
        if EXIT_LEAK.match(line) or any(p.search(line) or p.pattern in line
                                        for p in expected):
            continue
        return "fail"
    return "pass"


def read_expected_from(src: str) -> list:
    """The `## expects-error: <regex>` tags (`## expects-warning:` is the same tag,
    for the NaN warning) in a test's source, compiled. A tag
    that is not a valid regex is matched literally rather than crashing the run."""
    out = []
    for text in EXPECTS_TAG.findall(src):
        try:
            out.append(re.compile(text))
        except re.error:
            out.append(re.compile(re.escape(text)))
    return out


def read_expected(test: str) -> list:
    try:
        return read_expected_from((REPO / test).read_text(encoding="utf-8"))
    except OSError:
        return []


DEST_FILES = re.compile(r'^dest_files=\[(.*)\]\s*$', re.MULTILINE)


def import_gaps(root: Path) -> list[str]:
    """What a cold `--import` should have written and did not: each `.import`
    file's dest_files that is missing, and any `.tmp` left in .godot/imported/
    (an import cut off mid-write). Paths relative to `root`, sorted."""
    gaps: set[str] = set()
    for imp in root.rglob("*.import"):
        if ".godot" in imp.relative_to(root).parts:
            continue
        try:
            m = DEST_FILES.search(imp.read_text(encoding="utf-8"))
        except OSError:
            continue
        if not m:
            continue
        for dest in re.findall(r'"res://([^"]+)"', m.group(1)):
            if not (root / dest).is_file():
                gaps.add(dest)
    imported = root / ".godot" / "imported"
    if imported.is_dir():
        for tmp in imported.glob("*.tmp"):
            gaps.add(tmp.relative_to(root).as_posix())
    return sorted(gaps)


def cold_import(log_path: Path) -> list[str]:
    """One `--import`, its output kept in `log_path`, then checked; a second pass
    if the first left gaps. Returns what is still missing."""
    log_path.parent.mkdir(parents=True, exist_ok=True)
    for attempt in (1, 2):
        with open(log_path, "a", encoding="utf-8", errors="replace") as log:
            log.write("--- cold import, pass %d ---\n" % attempt)
            log.flush()
            subprocess.run([GODOT, "--headless", "--import"], cwd=str(REPO),
                           stdout=log, stderr=subprocess.STDOUT, env=_CHILD_ENV)
        gaps = import_gaps(REPO)
        if not gaps:
            return []
        print("cold import pass %d left %d gap(s), e.g. %s"
              % (attempt, len(gaps), gaps[0]), file=sys.stderr)
    return gaps


def tolerant_console(stream):
    """A console that cannot encode a character prints '?' rather than raising:
    a cp1252 Windows console died on G1's 'ș' printing a failing log, before
    results.json was written. Returns the stream, reconfigured in place."""
    if hasattr(stream, "reconfigure"):
        stream.reconfigure(errors="replace")
    return stream


def read_tags_from(src: str) -> tuple[bool, list[str]]:
    """(exclusive?, [check names]) from the test's own source comments."""
    exclusive = bool(EXCLUSIVE_TAG.search(src))
    m = SHARD_TAG.search(src)
    checks = [c.strip() for c in m.group(1).split(",")] if m else []
    return exclusive, checks


def read_tags(test: str) -> tuple[bool, list[str]]:
    try:
        return read_tags_from((REPO / test).read_text(encoding="utf-8"))
    except OSError:
        return False, []


def _kill_live_children() -> None:
    with _CHILDREN_LOCK:
        live = list(_LIVE_CHILDREN)
    for proc in live:
        try:
            proc.kill()
        except OSError:
            pass


def run_child(cmd: list[str], timeout: float, expected=()) -> tuple[str, int, str]:
    """Returns (filtered output, exit code, status)."""
    proc = subprocess.Popen(
        cmd, cwd=str(REPO), stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT, text=True, encoding="utf-8",
        errors="replace", env=_CHILD_ENV,
    )
    with _CHILDREN_LOCK:
        _LIVE_CHILDREN.add(proc)
    try:
        out, _ = proc.communicate(timeout=timeout)
        rc, status = proc.returncode, child_verdict(out or "", proc.returncode, expected)
    except subprocess.TimeoutExpired as e:
        proc.kill()  # subprocess.run's own timeout path does the same
        out = e.stdout if isinstance(e.stdout, str) else ""
        rc, status = -1, "timeout"
    finally:
        with _CHILDREN_LOCK:
            _LIVE_CHILDREN.discard(proc)
    return "\n".join(filter_noise((out or "").splitlines())), rc, status


def normalize_shard_log(text: str, test: str, all_passed: bool) -> str:
    """Each shard child is its own godot process: every one prints the engine
    banner (and the blank line under it) and, green, its own `_finish()` line,
    while the monolithic run prints ONE banner and ONE green line. Drop each
    child's banner pair and green line, re-emit the banner once at the top,
    and append the single green line iff everything passed. Per-check prints
    (balance's `note:` line) are the only content left and keep their check
    order, which is the tag's order. On red both forms emit only the
    FAIL:/problem lines in check order, so they match byte for byte -- the
    mutation gate (Task 4) proves it rather than trusts it."""
    stem = test.removeprefix("tests/").removesuffix(".gd")
    green = "%s: all checks passed" % stem
    banner = ""
    kept: list[str] = []
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        ln = lines[i]
        if ln.startswith("Godot Engine v"):
            if not banner:
                banner = ln
            # the engine prints one blank line under the banner; drop it too
            i += 2 if i + 1 < len(lines) and lines[i + 1].strip() == "" else 1
            continue
        if ln.strip() != green:
            kept.append(ln)
        i += 1
    out = ([banner, ""] if banner else []) + kept
    if all_passed:
        out.append(green)
    return "\n".join(out) + ("\n" if out else "")


def flatten_jobs(tests: list[str]) -> list[tuple[str, str | None, list[str]]]:
    """(test, check-or-None, command) in registry order; a shard-tagged test
    expands to one child per check using the file's own -- --check contract
    (test_balance.gd's V3.3 crash-isolation dispatch)."""
    jobs: list[tuple[str, str | None, list[str]]] = []
    for test in tests:
        _exclusive, checks = read_tags(test)
        if checks:
            for check in checks:
                jobs.append((test, check,
                             [GODOT, "--headless", "--script", "res://" + test,
                              "--", check]))
        else:
            jobs.append((test, None,
                         [GODOT, "--headless", "--script", "res://" + test]))
    return jobs


def run_parallel(tests: list[str], jobs: list[tuple[str, str | None, list[str]]],
                 timeout: float, verbose: bool, writer: RunWriter,
                 jobs_n: int) -> list[TestResult]:
    from concurrent.futures import ThreadPoolExecutor, as_completed

    tags = {t: read_tags(t) for t in tests}
    exclusive_tests = {t for t, (ex, _c) in tags.items() if ex}
    shard_checks = {t: c for t, (_ex, c) in tags.items()}
    expected = {t: read_expected(t) for t in tests}

    # Children complete out of order; the log is assembled LATER, in the
    # tag's listed order, so the sharded artifact stays byte-identical to
    # the monolithic run whatever order the pool finished in.
    children: dict[str, dict[str, dict]] = {t: {} for t in tests}
    plain: dict[str, dict] = {t: {} for t in tests}

    def _run_job(test: str, check: str | None, cmd: list[str]) -> None:
        t0 = time.monotonic()
        if check is not None:
            writer.event({"event": "child_start", "test": test, "check": check})
        out, rc, status = run_child(cmd, timeout, expected[test])
        rec = {"out": out, "status": status, "start": t0,
               "end": time.monotonic()}
        if check is None:
            plain[test] = rec
            # The log lands when the child finishes, not at the report
            # phase -- the cockpit's reason a finished test is clickable
            # DURING a run. The report phase rewrites it identically.
            rel = writer.write_log_text(test, out + ("\n" if out else ""))
            writer.event({"event": "done", "test": test, "status": status,
                          "duration": round(rec["end"] - t0, 3), "log": rel})
        else:
            children[test][check] = rec
            # Raw, un-normalised, and on disk the moment the child ends, as a
            # plain test's log is: the merged log is assembled only after the
            # whole pool drains, so a failed shard of a run that is then
            # interrupted, killed or outlived by a hung sibling left nothing.
            rel = writer.write_shard_log(test, check, out + ("\n" if out else ""))
            writer.event({"event": "child_done", "test": test, "check": check,
                          "status": status,
                          "duration": round(rec["end"] - t0, 3), "log": rel})

    def _build(test: str) -> TestResult | None:
        """The finished result for one test, or None if it never completed
        (an interrupted run) -- the caller decides what that means."""
        r = TestResult(test)
        if shard_checks[test]:
            recs = [children[test][c] for c in shard_checks[test]
                    if c in children[test]]
            if len(recs) != len(shard_checks[test]):
                return None
            r.sharded = True
            r.checks = list(shard_checks[test])
            statuses = [rec["status"] for rec in recs]
            r.status = ("timeout" if "timeout" in statuses else
                        "fail" if "fail" in statuses else "pass")
            r.duration = max(rec["end"] for rec in recs) - \
                min(rec["start"] for rec in recs)
            text = "".join(rec["out"] + "\n" for rec in recs)
            r.log_text = normalize_shard_log(text, test, r.status == "pass")
        else:
            rec = plain[test]
            if not rec:
                return None
            r.status = rec["status"]
            r.duration = rec["end"] - rec["start"]
            r.log_text = rec["out"] + ("\n" if rec["out"] else "")
        return r

    plain_jobs = [j for j in jobs if j[0] not in exclusive_tests]
    excl_jobs = [j for j in jobs if j[0] in exclusive_tests]
    futures: list = []
    interrupted = False
    try:
        # One start event per test, in registry order, at submission: the
        # cockpit's live "running" state (plain children emit no per-test
        # start of their own, and a queued test is indistinguishable from a
        # never-run one without this).
        for t in tests:
            writer.event({"event": "start", "test": t})
        # The exclusive lane is one worker: two tests that back up and
        # restore the same user:// state cannot overlap, structurally.
        with ThreadPoolExecutor(max_workers=max(1, jobs_n)) as pool, \
                ThreadPoolExecutor(max_workers=1) as excl_pool:
            try:
                futures = [pool.submit(_run_job, *j) for j in plain_jobs]
                futures += [excl_pool.submit(_run_job, *j) for j in excl_jobs]
                for f in as_completed(futures):
                    f.result()  # _run_job does not raise; re-raise if it ever does
            except KeyboardInterrupt:
                interrupted = True
                for f in futures:
                    f.cancel()  # queued jobs never spawn a child
                _kill_live_children()
                # The with-exit's shutdown(wait=True) then drains only the
                # just-killed jobs, fast.
    except KeyboardInterrupt:
        interrupted = True  # a second Ctrl-C during the drain

    if interrupted:
        raise Interrupted([r for r in (_build(t) for t in tests) if r])

    # Report in REGISTRY order, whatever order the pool finished in.
    results = []
    for n, test in enumerate(tests, 1):
        r = _build(test)
        if r is None:  # impossible here: every job completed above
            raise RuntimeError("no record for %s after a complete run" % test)
        rel = writer.write_log(r)
        writer.event({"event": "done", "test": test, "status": r.status,
                      "duration": round(r.duration, 3), "log": rel})
        print("[%d/%d] %s %s %.1fs" % (n, len(tests), test, r.status,
                                       r.duration), file=sys.stderr)
        if r.status != "pass":
            print(r.log_text)
        elif verbose:
            print(r.log_text)
        results.append(r)
    return results


class RunWriter:
    """events.ndjson + per-test logs + results.json for one suite run."""

    def __init__(self, run_dir: Path | None) -> None:
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
        return self.write_log_text(result.name, result.log_text)

    def write_shard_log(self, test: str, check: str, text: str) -> str:
        """One shard child's own output, beside (never over) the merged log."""
        rel = "tests/%s.shards/%s.log" % (test.removeprefix("tests/"), check)
        (self.dir / rel).parent.mkdir(parents=True, exist_ok=True)
        (self.dir / rel).write_text(text, encoding="utf-8")
        return rel

    def write_log_text(self, name: str, text: str) -> str:
        rel = "tests/%s.log" % name.removeprefix("tests/")
        (self.dir / rel).parent.mkdir(parents=True, exist_ok=True)
        (self.dir / rel).write_text(text, encoding="utf-8")
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


# ---------------------------------------------------------------- selftest

def _selftest_shard_logs(expect) -> None:
    """A failed shard child's log is on disk when the child ends, not only after
    the pool drains (an interrupted or killed run left a sharded failure with no
    log at all, where a plain test's log had already landed). Two fake children,
    run one after the other: the second looks for the first's log while the run
    is still going."""
    global run_child, read_tags, read_expected
    saved = run_child, read_tags, read_expected
    seen: dict = {}

    def fake_child(cmd, timeout, expected=()):
        if cmd[-1] == "_check_a":
            return "FAIL: boom in a", 1, "fail"
        seen["during"] = (writer.dir / "tests/test_x.gd.shards/_check_a.log").is_file()
        return "", 0, "pass"

    run_child = fake_child
    read_tags = lambda test: (False, ["_check_a", "_check_b"])
    read_expected = lambda test: []
    try:
        with tempfile.TemporaryDirectory() as tmp:
            writer = RunWriter(Path(tmp))
            jobs = [("tests/test_x.gd", c, ["godot", "--", c])
                    for c in ("_check_a", "_check_b")]
            with contextlib.redirect_stdout(io.StringIO()), \
                    contextlib.redirect_stderr(io.StringIO()):
                results = run_parallel(["tests/test_x.gd"], jobs, 5.0, False, writer, 1)
            writer.finish(results, interrupted=False, jobs=1)
            expect(seen.get("during") is True,
                   "a shard child's log must exist before the run ends")
            log_a = writer.dir / "tests/test_x.gd.shards/_check_a.log"
            expect(log_a.is_file() and "boom in a" in log_a.read_text(encoding="utf-8"),
                   "the failed shard's log must hold its own output")
            expect((writer.dir / "tests/test_x.gd.log").is_file(),
                   "the merged log must still be written")
            events = [json.loads(l) for l in
                      (writer.dir / "events.ndjson").read_text(encoding="utf-8").splitlines()]
            done = [e for e in events if e.get("event") == "child_done"]
            expect(len(done) == 2 and all("log" in e for e in done),
                   "each child_done must name its log: %r" % done)
    finally:
        run_child, read_tags, read_expected = saved


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

    # S7 (V5.1-0d): an engine or push_error line fails a test that exits 0,
    # unless it is the engine's exit-time leak report or the test declared it.
    expect(child_verdict("ERROR: boom\n   at: f (res://x.gd:1)", 0) == "fail",
           "exit 0 over an ERROR line must fail")
    expect(child_verdict("USER ERROR: boom", 0) == "fail",
           "exit 0 over a USER ERROR line must fail")
    expect(child_verdict("WARNING: `NaN` (\"Not a Number\") found in argument "
                         "passed to JSON.stringify(). `NaN` cannot be represented",
                         0) == "fail",
           "exit 0 over a NaN-in-save warning must fail")
    expect(child_verdict("ERROR: 28 resources still in use at exit (run with "
                         "--verbose for details).", 0) == "pass",
           "the engine's exit leak report must not fail a test")
    expect(child_verdict("ERROR: 2 RID allocations of type 'P12TextServer' were "
                         "leaked at exit.", 0) == "pass",
           "the engine's RID leak-at-exit report must not fail a test")
    # Pass 2: the engine's at-exit family by SHAPE, not by list -- what it prints
    # depends on what a test left alive. Every distinct line seen in this
    # checkout's runs and in CI's artifacts, plus PagedAllocator's.
    for leak in ["ERROR: 95 resources still in use at exit (run with --verbose for details).",
                 "ERROR: 1 RID allocations of type 'P12TextServerAdvanced11FontAdvanced' "
                 "were leaked at exit.",
                 "ERROR: Pages in use exist at exit in PagedAllocator: N7Variant8PagedPoolE"]:
        expect(child_verdict(leak, 0) == "pass", "an engine at-exit leak line failed: %r" % leak)
    expect(child_verdict("ERROR: test_x: the save could not be written at exit", 0) == "fail",
           "a test's own error that merely mentions exit must still fail")
    expect(child_verdict("note: an ERROR: mid-line is not the engine's", 0) == "pass",
           "only a line that STARTS with ERROR: counts")
    declared = read_expected_from("extends SceneTree\n"
                                  "\t## expects-error: test_x: expected .*\n"
                                  "## expects-error: Parse JSON failed\n")
    expect([d.pattern for d in declared] == ["test_x: expected .*", "Parse JSON failed"],
           "expects-error tag parse: %r" % [d.pattern for d in declared])
    expect(child_verdict("ERROR: test_x: expected error", 0, declared) == "pass",
           "a declared ERROR line must pass")
    expect(child_verdict("ERROR: test_x: expected error\nERROR: other", 0,
                         declared) == "fail",
           "a declared line must not excuse an undeclared one")
    nan_tag = read_expected_from('\t## expects-warning: `NaN` ("Not a Number") found\n')
    expect(child_verdict('WARNING: `NaN` ("Not a Number") found in argument passed '
                         'to JSON.stringify().', 0, nan_tag) == "pass",
           "an expects-warning tag with parentheses must match its line literally")

    # The cold import, checked (pass 2's blocker): a cut-off import left 17 cache
    # files of 84 and 0-byte font .tmp files, and every UI test then printed
    # "Cannot open file .godot/imported/..." lines that S7 rightly fails on.
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / ".godot" / "imported").mkdir(parents=True)
        (root / "assets").mkdir()
        (root / "assets" / "a.ttf.import").write_text(
            '[deps]\n\nsource_file="res://assets/a.ttf"\n'
            'dest_files=["res://.godot/imported/a.ttf-1.fontdata"]\n', encoding="utf-8")
        (root / "assets" / "b.txt.import").write_text(
            '[remap]\n\nimporter="keep"\n', encoding="utf-8")
        gaps = import_gaps(root)
        expect(gaps == [".godot/imported/a.ttf-1.fontdata"],
               "a missing import destination must be a gap: %r" % gaps)
        (root / ".godot" / "imported" / "a.ttf-1.fontdata").write_bytes(b"x")
        expect(import_gaps(root) == [], "a complete cache has no gap: %r" % import_gaps(root))
        (root / ".godot" / "imported" / "a.ttf-1.fontdata123.tmp").write_bytes(b"")
        expect(import_gaps(root) == [".godot/imported/a.ttf-1.fontdata123.tmp"],
               "a leftover .tmp is a gap: %r" % import_gaps(root))

    # The cp1252 crash: a failing log printed to a Windows console met 'ș' in
    # G1's capital line and died before results.json was written.
    import io
    console = tolerant_console(io.TextIOWrapper(io.BytesIO(), encoding="cp1252",
                                                errors="strict"))
    try:
        console.write("capital 'Chișinău'\n")
        console.flush()
    except UnicodeEncodeError as e:
        expect(False, "a cp1252 console still dies on a log line: %s" % e)

    # Shard normalization: the green collapse and the red order (Task 4), plus
    # the banner rule the baselines forced -- a shard child is its own godot
    # process, so the concat carries the banner once per child while the
    # monolithic run carries it once.
    green = normalize_shard_log(
        "test_x: all checks passed\ntest_x: all checks passed\n",
        "tests/test_x.gd", True)
    expect(green == "test_x: all checks passed\n",
           "green shard concat must collapse to one line: %r" % green)
    red = normalize_shard_log(
        "FAIL: a\ntest_x: all checks passed\nFAIL: b\n",
        "tests/test_x.gd", False)
    expect(red == "FAIL: a\nFAIL: b\n", "red concat keeps failure order: %r" % red)
    bann = normalize_shard_log(
        "Godot Engine vTEST\n\nnote: n\nGodot Engine vTEST\n\n"
        "test_x: all checks passed\n",
        "tests/test_x.gd", True)
    expect(bann == "Godot Engine vTEST\n\nnote: n\ntest_x: all checks passed\n",
           "child banner+blank collapses to one at the top, note kept: %r" % bann)
    ex, checks = read_tags_from("extends SceneTree\n"
                                "## suite-exclusive: writes user://settings.cfg\n")
    expect(ex and checks == [], "exclusive tag parse: %r %r" % (ex, checks))
    ex2, checks2 = read_tags_from("## suite-shard-checks: _check_a, _check_b\n")
    expect(not ex2 and checks2 == ["_check_a", "_check_b"],
           "shard tag parse: %r %r" % (ex2, checks2))

    # The bare gate's registry read (V5.0b): bash's comment rule, and a parse
    # that finds no array yields nothing (main() refuses it) rather than a guess.
    reg = parse_registry("x\ntests=(\n  tests/test_a.gd\n  # tests/test_b.gd\n"
                         "  tests/test_c.gd  # trailing note\n)\n")
    expect(reg == ["tests/test_a.gd", "tests/test_c.gd"], "registry parse: %r" % reg)
    expect(parse_registry("tests = ( tests/test_a.gd )\n") == [],
           "an unmatched registry must parse empty")
    expect(len(registry()[0]) > 100, "the real registry parses: %d" % len(registry()[0]))

    # Isolation is the default and --no-isolate the only way out (2026-10-20); the
    # child env redirects both user:// roots and keeps everything else.
    ap_iso = build_parser()
    expect(ap_iso.parse_args([]).isolate, "a bare run must be isolated")
    expect(ap_iso.parse_args(["--isolate"]).isolate, "--isolate must still parse")
    expect(not ap_iso.parse_args(["--no-isolate"]).isolate, "--no-isolate must opt out")
    env = isolated_env({"PATH": "p", "APPDATA": "real"}, "tmp")
    expect(env == {"PATH": "p", "APPDATA": "tmp", "XDG_DATA_HOME": "tmp"},
           "isolated env: %r" % env)

    _selftest_shard_logs(expect)

    if failures:
        for f in failures:
            print("SELFTEST FAIL: %s" % f)
        return 1
    print("suite_runner selftest: all checks passed")
    return 0


def build_parser() -> argparse.ArgumentParser:
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
    # --isolate stays accepted (and is the default) so every command line and
    # guard written against V5.0b's opt-in flag keeps meaning the same thing.
    ap.add_argument("--isolate", dest="isolate", action="store_true", default=True,
                    help="private APPDATA per run (user:// in a temp dir; the default): "
                         "two runs in two checkouts may overlap; kept on failure for its logs")
    ap.add_argument("--no-isolate", dest="isolate", action="store_false",
                    help="run against the real user dir (debugging a user:// state by hand)")
    ap.add_argument("--selftest", action="store_true")
    return ap


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    tolerant_console(sys.stdout)
    tolerant_console(sys.stderr)

    if args.selftest:
        return _selftest()
    if not args.tests:
        # AGENTS.md's agent gate is this command with no tests, and it used to
        # exit 2 here. The list is still run_tests.sh's tests=() -- read, not
        # copied -- and its unregistered-test rule applies on the way, so a bare
        # gate is as strict as the bash one -- its step 0 (the selftest) and its
        # SUITE_PYTHON export too. Parsed rather than run through bash: a
        # core.autocrlf checkout hands bash a CRLF script it cannot execute.
        if _selftest() != 0:
            return 1
        os.environ.setdefault("SUITE_PYTHON", sys.executable)
        args.tests, unregistered = registry()
        if not args.tests:
            # A reformatted run_tests.sh the parse no longer matches must not
            # become a gate that runs nothing and prints "passed".
            print("no tests parsed from tools/run_tests.sh's tests=() -- "
                  "fix registry() before trusting a bare gate", file=sys.stderr)
            return 2
        if unregistered:
            print("test files on disk but absent from tools/run_tests.sh: %s"
                  % " ".join(unregistered), file=sys.stderr)
            return 1

    if not _godot_available():
        print("godot not found -- set GODOT_BIN if it is not on PATH", file=sys.stderr)
        return 2

    global _CHILD_ENV
    appdata = None
    if args.isolate:
        appdata = tempfile.mkdtemp(prefix="nsim_appdata_")
        _CHILD_ENV = isolated_env(dict(os.environ), appdata)
        print("isolated: APPDATA=%s" % appdata, file=sys.stderr)

    writer = RunWriter(Path(args.run_dir) if args.run_dir else None)
    print("run dir: %s" % writer.dir, file=sys.stderr)

    # The cold-clone rule (V2.8 review): no .godot/ means no script class
    # cache, and the committed autoload does not parse. One import pass --
    # CHECKED since V5.1-0d: a pass that stopped early (seen once on Windows,
    # 17 cache files of 84, the fonts as 0-byte .tmp; its output went to
    # DEVNULL, so why is unknown) let every UI test load a .ttf through a
    # half-built cache. Its output is kept, a gap gets a second pass, and a
    # cache still broken after that stops the run: the tests would measure the
    # cache, not the code.
    if not (REPO / ".godot").is_dir():
        print("no .godot/ -- importing once so the script class cache exists",
              file=sys.stderr)
        gaps = cold_import(writer.dir / "cold_import.log")
        if gaps:
            print("cold import incomplete after two passes (%d gaps, e.g. %s); "
                  "log: %s" % (len(gaps), gaps[0], writer.dir / "cold_import.log"),
                  file=sys.stderr)
            return 2
    t0 = time.monotonic()
    try:
        jobs = flatten_jobs(args.tests)
        results = run_parallel(args.tests, jobs, args.timeout, args.verbose,
                               writer, args.jobs)
    except Interrupted as exc:
        elapsed = int(time.monotonic() - t0)
        print("interrupted after %d:%02d -- partial results in %s"
              % (elapsed // 60, elapsed % 60, writer.dir), file=sys.stderr)
        for r in exc.results:  # the captured output of the finished ones
            writer.write_log(r)
        writer.finish(exc.results, interrupted=True, jobs=args.jobs)
        _report_isolated(appdata)
        return 130
    except KeyboardInterrupt:  # second Ctrl-C, or one before any child ran
        _kill_live_children()
        print("interrupted", file=sys.stderr)
        writer.finish([], interrupted=True, jobs=args.jobs)
        _report_isolated(appdata)
        return 130
    elapsed = int(time.monotonic() - t0)
    code = writer.finish(results, interrupted=False, jobs=args.jobs)
    if code == 0 and appdata is not None:
        shutil.rmtree(appdata, ignore_errors=True)
    else:
        _report_isolated(appdata)
    if code == 0:
        print("test suite passed -- %d tests in %d:%02d"
              % (len(results), elapsed // 60, elapsed % 60))
    else:
        print("test suite failed", file=sys.stderr)
    return code


def _report_isolated(appdata: str | None) -> None:
    """A failed or interrupted isolated run keeps its user dir, and says where."""
    if appdata is not None:
        print("isolated user dir kept for its logs: %s" % appdata, file=sys.stderr)


def registry() -> tuple[list[str], list[str]]:
    """(the tests=() array of tools/run_tests.sh in order, tests/test_*.gd
    files on disk that it does not list)."""
    text = (REPO / "tools" / "run_tests.sh").read_text(encoding="utf-8")
    tests = parse_registry(text)
    on_disk = sorted("tests/" + p.name for p in (REPO / "tests").glob("test_*.gd"))
    return tests, [t for t in on_disk if t not in tests]


def parse_registry(text: str) -> list[str]:
    """The tests=() array as bash reads it: a `#` starts a comment, so a
    commented-out entry is not registered."""
    block = re.search(r"^tests=\((.*?)^\)", text, re.MULTILINE | re.DOTALL)
    if not block:
        return []
    words: list[str] = []
    for line in block.group(1).splitlines():
        words += line.split("#", 1)[0].split()
    return [w for w in words if w.startswith("tests/")]


def _godot_available() -> bool:
    from shutil import which
    return which(GODOT) is not None


if __name__ == "__main__":
    sys.exit(main())
