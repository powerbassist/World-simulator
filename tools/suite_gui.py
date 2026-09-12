#!/usr/bin/env python3
"""The suite cockpit (replaces V3.3's progress bar, 2026-09-11 spec).

A view, never a gate: it launches tools/suite_runner.py (or attaches to a
run already writing events -- an agent's --ci run is watchable here), tails
events.ndjson, and shows one row per test with status, duration and full
output on click. Re-run goes through the runner, so there is one execution
path and this file cannot drift from it. Stdlib tkinter only.

Event shapes actually emitted by suite_runner.py: a plain test gives one
worker `done` (test/status/duration, no log) and later a report-phase `done`
that adds `log`; a sharded test gives `child_start`/`child_done` per check
plus that same final `done`. There are no `start` events at all, so a row
exists only from its first `done` onward and last-done-wins is exactly the
right merge.
"""
from __future__ import annotations

import argparse
import json
import queue
import signal
import subprocess
import sys
import threading
from datetime import datetime, timezone
from pathlib import Path
from tkinter import filedialog, messagebox, ttk
import tkinter as tk

import suite_runner  # same tools/ dir; its read_tags is the exclusive lane's own parser

REPO = Path(__file__).resolve().parent.parent
SLOW_SECONDS = 30.0
POLL_MS = 200


def registry() -> list[str]:
    """The test list through the bash run_tests.sh itself needs. A bare
    `bash` on PATH can be System32's WSL relay -- present but dead on a
    machine with no distro -- so a failed or empty listing falls through to
    the Git install paths (the old progress GUI's suite_command() hit this
    first)."""
    for exe in ("bash",
                r"C:\Program Files\Git\bin\bash.exe",
                r"C:\Program Files\Git\usr\bin\bash.exe"):
        try:
            out = subprocess.run(
                [exe, "tools/run_tests.sh", "--print-tests"], cwd=str(REPO),
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, encoding="utf-8")
        except FileNotFoundError:
            continue
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.split()
    raise RuntimeError("could not list the test registry: no working bash")


def rows_from_events(lines: list[str]) -> dict[str, dict]:
    """Pure: events.ndjson lines -> per-test row state. Selftested.

    Last done wins, which is what makes the runner's two-done shape merge
    correctly (the worker's log-less done, then the report-phase done with
    one), and `log` is only ever taken from a done that carries one --
    child_done lines count checks and never invent output."""
    rows: dict[str, dict] = {}
    for line in lines:
        try:
            e = json.loads(line)
        except json.JSONDecodeError:
            continue  # a torn tail line while the writer is mid-write
        if e.get("event") == "done":
            r = rows.setdefault(e["test"], {})
            r.update({"status": e["status"], "duration": e["duration"],
                      "log": e.get("log", "")})
        elif e.get("event") == "child_done":
            r = rows.setdefault(e["test"], {"status": "running", "duration": 0.0,
                                            "log": "", "checks": 0})
            r["checks"] = r.get("checks", 0) + 1
    return rows


def row_keeps(row: dict, mode: str) -> bool:
    """Pure: filter predicate. Selftested."""
    if mode == "all":
        return True
    if mode == "failed":
        return row.get("status") not in ("pass", "running", None)
    if mode == "slow":
        return row.get("duration", 0.0) > SLOW_SECONDS
    if mode == "exclusive":
        return row.get("exclusive", False)
    return True


class Cockpit(tk.Tk):
    def __init__(self, tests: list[str], jobs: int) -> None:
        super().__init__()
        self.title("Nation Simulator — suite cockpit")
        self.geometry("1100x640")
        self.minsize(760, 420)
        self.tests = tests
        self.jobs = jobs
        self.run_dir: Path | None = None
        self.rows: dict[str, dict] = {}
        self.proc: subprocess.Popen | None = None
        self.q: queue.Queue = queue.Queue()
        self.summary: dict | None = None
        self.launched: list[str] = []
        self._escalate: threading.Timer | None = None

        bar = tk.Frame(self)
        bar.pack(fill="x", padx=8, pady=6)
        tk.Button(bar, text="Run all", command=self.run_all).pack(side="left")
        tk.Button(bar, text="Re-run failed", command=self.run_failed).pack(side="left")
        tk.Label(bar, text="jobs").pack(side="left")
        self.jobs_box = ttk.Spinbox(bar, from_=1, to=16, width=3)
        self.jobs_box.set(jobs)
        self.jobs_box.pack(side="left", padx=(2, 6))
        tk.Button(bar, text="Stop", command=self.stop).pack(side="left")
        tk.Button(bar, text="Open run dir", command=self.open_reports).pack(side="right")
        tk.Button(bar, text="Open results.json…", command=self.open_results).pack(
            side="right", padx=6)
        self.mode = tk.StringVar(value="all")
        for mode in ("all", "failed", "slow", "exclusive"):
            rb = tk.Radiobutton(bar, text=mode, variable=self.mode, value=mode,
                                command=self.refresh)
            rb.pack(side="left", padx=3)

        # ttk's panedwindow, not tk's: only the ttk one takes a weight per
        # pane (the classic widget's add() rejects it with TclError).
        pane = ttk.PanedWindow(self, orient="vertical")
        pane.pack(fill="both", expand=True)
        cols = ("status", "test", "seconds")
        self.tree = ttk.Treeview(pane, columns=cols, show="headings",
                                 selectmode="browse")
        for c, w in zip(cols, (90, 420, 90)):
            self.tree.heading(c, text=c)
            self.tree.column(c, width=w, anchor="w")
        pane.add(self.tree, weight=3)
        self.out = tk.Text(pane, wrap="none", bg="#111", fg="#ccc")
        pane.add(self.out, weight=2)
        self.tree.bind("<<TreeviewSelect>>", self.show_log)
        for tag, color in (("pass", "#0a7a2f"), ("fail", "#b02020"),
                           ("timeout", "#b06010"), ("running", "#8a6d1a")):
            self.tree.tag_configure(tag, foreground=color)

        self.status = tk.Label(self, text="idle", anchor="w")
        self.status.pack(fill="x", padx=8, pady=4)
        for t in tests:
            self.tree.insert("", "end", iid=t, values=("—", t, ""))
        # Exclusivity read from each test's own `## suite-exclusive:` tag
        # through the runner's parser -- the same source the lane itself
        # uses, so this filter cannot drift from it into a second list.
        for t in tests:
            if suite_runner.read_tags(t)[0]:
                self.rows.setdefault(t, {})["exclusive"] = True
        self.after(POLL_MS, self._poll)

    # -- running --------------------------------------------------------
    def _start(self, tests: list[str]) -> None:
        if not tests:
            return
        self.stop()
        self.summary = None
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        self.run_dir = REPO / "reports" / "suite_runs" / stamp
        try:
            jobs = max(1, int(self.jobs_box.get()))
        except ValueError:
            jobs = self.jobs
            self.jobs_box.set(jobs)
        cmd = [sys.executable, "tools/suite_runner.py", "-j", str(jobs),
               "--run-dir", str(self.run_dir)] + tests
        # Its own process group so Stop's console signal reaches the runner
        # without touching this window (or anything else on the console).
        self.proc = subprocess.Popen(
            cmd, cwd=str(REPO), stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NEW_PROCESS_GROUP", 0))
        self.launched = list(tests)
        threading.Thread(target=self._tail, daemon=True).start()

    def _tail(self) -> None:
        import time as _time
        # Locals, not self: a second launch must not have the previous
        # thread waiting on the NEW process or reading the NEW run dir.
        run_dir, proc = self.run_dir, self.proc
        events = run_dir / "events.ndjson"
        while not events.exists() and proc is not None and proc.poll() is None:
            _time.sleep(0.2)
        if not events.exists():
            return
        def _done() -> None:
            if proc is not None:
                proc.wait()
                if self._escalate:
                    self._escalate.cancel()

        with open(events, encoding="utf-8") as fh:
            while True:
                line = fh.readline()
                if line:
                    self.q.put(line)
                    try:
                        if json.loads(line).get("event") == "summary":
                            _done()
                            return  # the stream's own end marker
                    except json.JSONDecodeError:
                        pass
                    continue
                # EOF: our own child's exit is the stream's end; an attached
                # run is polled until its writer's summary (its results.json
                # is the fallback if it died without one). A dead attached
                # run with neither leaves a daemon thread at 5 wakes/s.
                if proc is not None:
                    if proc.poll() is not None:
                        _done()
                        return
                elif (run_dir / "results.json").exists():
                    return
                _time.sleep(0.2)

    def run_all(self) -> None:
        self._start(list(self.tests))

    def run_failed(self) -> None:
        failed = [t for t, r in self.rows.items() if r.get("status") not in
                  ("pass", "running", None)]
        self._start(failed or list(self.tests))

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            try:
                # CTRL_BREAK reaches the runner's whole process group (it
                # was spawned into its own). The stop is intentionally
                # abrupt -- the runner's graceful partial-results path is a
                # Ctrl-C in a console of its own, unreachable from here --
                # and its godot children finish their natural exit, bounded
                # by the runner's own timeout if one hangs.
                self.proc.send_signal(signal.CTRL_BREAK_EVENT)
            except (OSError, ValueError, AttributeError):
                self.proc.terminate()
            self._escalate = threading.Timer(5.0, self._force_kill)
            self._escalate.daemon = True
            self._escalate.start()

    def _force_kill(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.kill()

    def open_reports(self) -> None:
        subprocess.Popen(["explorer", str(self.run_dir or REPO / "reports" / "suite_runs")])

    def open_results(self) -> None:
        d = filedialog.askdirectory(
            initialdir=str(REPO / "reports" / "suite_runs"),
            title="Open a run directory (its results.json)")
        if not d:
            return
        path = Path(d) / "results.json"
        if not path.exists():
            messagebox.showerror("suite cockpit", "no results.json in %s" % d)
            return
        data = json.loads(path.read_text(encoding="utf-8"))
        self.load_results(data, Path(d))

    def load_results(self, data: dict, run_dir: Path) -> None:
        """A past run, read-only: rows from its results.json, logs reached
        by the same click that serves a live run."""
        self.stop()
        self.proc = None
        self.summary = None
        self.launched = []
        self.run_dir = run_dir
        self.rows = {}
        for rec in data.get("tests", []):
            row: dict = {"status": rec.get("status"),
                         "duration": rec.get("duration", 0.0), "log": ""}
            checks = rec.get("checks") or []
            if rec.get("sharded") and checks:
                row["checks"] = len(checks)
            self.rows[rec["name"]] = row
        self.refresh()

    # -- view -----------------------------------------------------------
    def _poll(self) -> None:
        got = False
        try:
            while True:
                line = self.q.get_nowait()
                got = True
                try:
                    e = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if e.get("event") == "summary":
                    self.summary = e
                    continue
                for test, row in rows_from_events([line]).items():
                    self.rows.setdefault(test, {}).update(row)
        except queue.Empty:
            pass
        if got:
            self.refresh()
        if self.summary is not None:
            self.status.config(text="finished: %d tests, %d failed, exit %d — %s" % (
                self.summary.get("total", 0), self.summary.get("failed", 0),
                self.summary.get("exit", 0), self.run_dir or ""))
        else:
            total = len(self.launched or self.tests)
            done = sum(1 for r in self.rows.values() if r.get("status") not in
                       ("running", None))
            fails = sum(1 for r in self.rows.values() if r.get("status") not in
                        ("pass", "running", None))
            self.status.config(text="%d/%d done, %d failed%s" % (
                done, total, fails,
                "" if self.proc is None or self.proc.poll() is not None
                else ", running"))
        self.after(POLL_MS, self._poll)

    def refresh(self) -> None:
        for t in self.tests:
            row = self.rows.get(t, {})
            if not row_keeps(row, self.mode.get()):
                self.tree.detach(t)
                continue
            self.tree.reattach(t, "", "end")
            status = row.get("status") or "—"
            self.tree.set(t, "status", status)
            self.tree.set(t, "test", t)
            # A not-yet-run row has no duration; printing 0.0 there is the
            # confident-zero bug in miniature, so it prints nothing.
            dur = row.get("duration") or 0.0
            self.tree.set(t, "seconds", "%.1f" % dur if status != "—" else "")
            self.tree.item(t, tags=(status,))

    def show_log(self, _e=None) -> None:
        sel = self.tree.selection()
        if not sel or not self.run_dir:
            return
        log = self.run_dir / "tests" / (sel[0].removeprefix("tests/") + ".log")
        self.out.delete("1.0", "end")
        self.out.insert("1.0", log.read_text(encoding="utf-8", errors="replace")
                        if log.exists() else "(no log yet)")


def _selftest() -> int:
    failures: list[str] = []

    def expect(cond: bool, msg: str) -> None:
        if not cond:
            failures.append(msg)

    def ev(**kw) -> str:
        return json.dumps(kw)

    sample = [
        # The runner's two-done shape: worker done (no log) first, the
        # report-phase done (with one) second -- last wins.
        ev(event="done", test="tests/test_clock.gd", status="pass",
           duration=2.0, ts=1),
        ev(event="done", test="tests/test_clock.gd", status="pass",
           duration=2.1, log="tests/test_clock.gd.log", ts=2),
        # A sharded test: check events, then the same final done.
        ev(event="child_done", test="tests/test_balance.gd", check="_check_a",
           status="pass", duration=1.0, ts=3),
        ev(event="child_done", test="tests/test_balance.gd", check="_check_b",
           status="fail", duration=1.0, ts=4),
        ev(event="done", test="tests/test_balance.gd", status="fail",
           duration=2.0, log="tests/test_balance.gd.log", ts=5),
        ev(event="done", test="tests/test_data.gd", status="fail",
           duration=0.5, log="x", ts=6),
        # A child_done-only row: mid-run truth -- running, no invented log.
        ev(event="child_done", test="tests/test_shard.gd", check="_c",
           status="pass", duration=9.0, ts=7),
        ev(event="summary", total=4, failed=2, interrupted=False, exit=1, ts=8),
        "{torn",
    ]
    rows = rows_from_events(sample)

    expect(rows["tests/test_clock.gd"]["log"] == "tests/test_clock.gd.log",
           "report-phase done must win over the worker's log-less one")
    expect(rows["tests/test_balance.gd"]["checks"] == 2,
           "child_done accounting must survive the done replacement")
    expect(rows["tests/test_shard.gd"] == {"status": "running", "duration": 0.0,
                                           "log": "", "checks": 1},
           "child_done-only row: running, no log, checks counted")
    expect(len(rows) == 4,
           "summary and torn lines must not become rows: %r" % sorted(rows))

    expect(row_keeps(rows["tests/test_data.gd"], "failed"),
           "failed filter keeps failures")
    expect(row_keeps(rows["tests/test_balance.gd"], "failed"),
           "failed filter keeps a failed shard's test")
    expect(not row_keeps(rows["tests/test_shard.gd"], "failed"),
           "a running child_done-only row is not a failure")
    expect(not row_keeps({"status": "pass"}, "failed"),
           "failed filter drops passes")
    expect(not row_keeps(rows["tests/test_clock.gd"], "slow"),
           "slow filter drops 2.1s")
    expect(row_keeps({"duration": 60.0}, "slow"), "slow filter keeps 60s")
    expect(row_keeps({"exclusive": True}, "exclusive"), "exclusive filter")
    expect(not row_keeps({}, "exclusive"), "exclusive filter drops untagged")
    expect(row_keeps({}, "all"), "all keeps anything")

    if failures:
        for f in failures:
            print("SELFTEST FAIL: %s" % f)
        return 1
    print("suite_gui selftest: all checks passed")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--attach", type=Path, default=None,
                    help="watch an existing run dir instead of launching one")
    ap.add_argument("-j", "--jobs", type=int, default=8)
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("tests", nargs="*")
    args = ap.parse_args()
    if args.selftest:
        return _selftest()
    tests = args.tests or registry()
    app = Cockpit(tests, args.jobs)
    if args.attach:
        app.run_dir = args.attach
        threading.Thread(target=app._tail, daemon=True).start()
    app.mainloop()
    return 0


if __name__ == "__main__":
    sys.exit(main())
