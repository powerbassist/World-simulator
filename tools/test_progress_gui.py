#!/usr/bin/env python3
"""A progress window for tools/run_tests.sh (V3.3, author request).

The headless suite can run for the better part of an hour printing nothing a
human sees, which reads as "broken". This wraps it in a small always-on-top
window: a progress bar over the runner's own [n/80] lines, the current test's
name, a live failure counter, and the tail of the output so a hang is visible
as a hang. The full output is teed to a log file either way (buffered in
memory, flushed whole on a timer -- the tee is a courtesy copy, not a stream
anyone tails).

Dev tooling, never ships. Run it with tools/run_tests_gui.sh.
"""
import argparse
import re
import subprocess
import sys
import threading
import queue
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
RE_PROGRESS = re.compile(r"\[\s*(\d+)/(\d+)\]\s*(.*)")
RE_FAIL = re.compile(r"^FAIL\s+(tests/\S+)")


def confined_log_path(raw: str) -> Path:
    """The tee target must resolve inside the repo: the path arrives from the
    command line, and a write target is not the place to discover a traversal
    (import_data.py's `confined()` for the same reason)."""
    resolved = (REPO / raw).resolve()
    if REPO != resolved and REPO not in resolved.parents:
        raise SystemExit(f"log path escapes the repo: {raw}")
    return resolved


def suite_command() -> list:
    """The runner through GIT bash, found without trusting PATH's style: this
    script can be launched from a shell whose PATH is MSYS-formatted (/c/...),
    where every Path(entry) probe misses and `bash` would otherwise resolve to
    System32's WSL relay, which fails on a machine with no WSL distro."""
    for candidate in (
        r"C:\Program Files\Git\bin\bash.exe",
        r"C:\Program Files\Git\usr\bin\bash.exe",
    ):
        if Path(candidate).exists():
            return [candidate, "tools/run_tests.sh"]
    raise RuntimeError("no Git Bash at the usual install paths")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--log", default="reports/suite_gui.log",
                        help="file the suite output is teed to (repo-relative)")
    args = parser.parse_args()
    log_path = confined_log_path(args.log)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    import tkinter as tk
    from tkinter import ttk

    root = tk.Tk()
    root.title("Nation Simulator — test suite")
    root.attributes("-topmost", True)
    root.geometry("560x240")
    root.minsize(480, 200)

    status = tk.Label(root, text="starting…", font=("Segoe UI", 11, "bold"), anchor="w")
    status.pack(fill="x", padx=12, pady=(12, 2))
    current = tk.Label(root, text="", font=("Segoe UI", 9), anchor="w", fg="#555")
    current.pack(fill="x", padx=12)
    bar = ttk.Progressbar(root, maximum=1, value=0, mode="determinate")
    bar.pack(fill="x", padx=12, pady=8)
    fails = tk.Label(root, text="failures: 0", font=("Segoe UI", 9), anchor="w", fg="#555")
    fails.pack(fill="x", padx=12)
    tail = tk.Text(root, height=6, font=("Consolas", 8), state="disabled", bg="#111", fg="#ccc")
    tail.pack(fill="both", expand=True, padx=12, pady=(4, 10))

    q = queue.Queue()
    buffer = []
    fail_count = [0]
    total = [1]

    # The tee file exists from the first moment, so an outside reader can watch
    # progress even while the buffer is empty; the periodic flush keeps it near.
    log_path.write_text("", encoding="utf-8")

    def flush():
        if buffer:
            log_path.write_text("".join(buffer), encoding="utf-8", errors="replace")

    def worker():
        try:
            proc = subprocess.Popen(
                suite_command(),
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                text=True, encoding="utf-8", errors="replace", bufsize=1,
                cwd=str(REPO),
            )
        except Exception as e:  # a dead thread swallows even SystemExit; the window must say why
            q.put(f"runner could not start: {e}")
            q.put("__EXIT__ 127")
            return
        for line in proc.stdout:
            buffer.append(line)
            q.put(line.rstrip("\n"))
        proc.wait()
        flush()
        q.put(f"__EXIT__ {proc.returncode}")

    def poll():
        flush()
        try:
            while True:
                line = q.get_nowait()
                if line.startswith("__EXIT__"):
                    flush()
                    code = int(line.split()[1])
                    if code == 0:
                        status.config(text=f"PASSED — suite green ({total[0]} tests)", fg="#0a7a2f")
                    else:
                        status.config(text=f"FAILED — exit {code}, {fail_count[0]} test file(s) red (see {args.log})", fg="#b02020")
                    return
                m = RE_PROGRESS.search(line)
                if m:
                    n, t = int(m.group(1)), int(m.group(2))
                    total[0] = t
                    bar.config(maximum=t, value=n)
                    current.config(text=m.group(3).strip())
                    status.config(text=f"running… {n}/{t}", fg="#000")
                m = RE_FAIL.search(line)
                if m:
                    fail_count[0] += 1
                    fails.config(text=f"failures: {fail_count[0]} — last: {m.group(1)}", fg="#b02020")
                tail.config(state="normal")
                tail.insert("end", line + "\n")
                tail.see("end")
                if float(tail.index("end-1c").split(".")[0]) > 400:
                    tail.delete("1.0", "100.0")
                tail.config(state="disabled")
        except queue.Empty:
            pass
        root.after(120, poll)

    threading.Thread(target=worker, daemon=True).start()
    root.after(120, poll)
    root.protocol("WM_DELETE_WINDOW", root.destroy)
    root.mainloop()
    flush()
    return 0


if __name__ == "__main__":
    sys.exit(main())
