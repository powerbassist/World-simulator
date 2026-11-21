#!/usr/bin/env python3
"""A windowed frame for every staged state (V5.1-d2, the tier's done-when).

tools/screenshot.gd takes one flag per staged state and lists each staging in its
header, one `godot ... -- <args>` line apiece. This runs every one of those lines,
windowed (a headless Godot draws nothing), each in its own temporary user dir, and
writes `<out>/<NN>_<slug>.png` plus contact sheets of four frames
(`<out>/sheet_NN.png`) so a session can look at all of them in a few reads.

It also prints any flag screenshot.gd parses that no header line stages: a state
the header does not list is a state nobody photographs.

Usage: python tools/screenshot_all.py --out DIR [--only SUBSTR] [--repo PATH] [--interface-size N]
--interface-size N writes settings.cfg [display] interface_size_index=N into each run's temp user
dir (src/ui/interface_size.gd: 1 = 1.0, 2 = 0.9, 3 = 0.8, 4 = 0.75); without it the game's default (Auto).
Run it alone: it opens one Godot window after another (AGENTS.md, one Godot at a
time in a checkout). Needs Pillow for the sheets; without it the frames still land.
"""
from __future__ import annotations

import argparse
import contextlib
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HEADER = re.compile(r'^##\s+godot --path "<repo>" --script res://tools/screenshot\.gd(?: -- (?P<args>.*))?$')
PARSED = re.compile(r'args\[i\] == "(--[a-z0-9-]+)"')
# Flags that steer a staging rather than stage one, so a header line need not carry them.
MODIFIERS = {"--out", "--frames", "--text"}
TIMEOUT_S = 240


def stagings(script: Path) -> list[str]:
    out = []
    for line in script.read_text(encoding="utf-8").splitlines():
        m = HEADER.match(line.rstrip())
        if m:
            out.append((m.group("args") or "").strip())
    return out


def unstaged_flags(script: Path, lines: list[str]) -> list[str]:
    parsed = set(PARSED.findall(script.read_text(encoding="utf-8")))
    used = {tok for args in lines for tok in args.split() if tok.startswith("--")}
    return sorted(parsed - used - MODIFIERS)


def slug(args: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", args.lower()).strip("-")
    return s[:60] or "default"


def sheets(frames: list[Path], out: Path) -> None:
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        print("no Pillow: frames written, no contact sheets")
        return
    w, h = 960, 540
    for n in range(0, len(frames), 4):
        sheet = Image.new("RGB", (2 * w, 2 * h), (0, 0, 0))
        for k, frame in enumerate(frames[n:n + 4]):
            img = Image.open(frame).convert("RGB").resize((w, h))
            ImageDraw.Draw(img).text((8, h - 18), frame.stem, fill=(255, 255, 0))
            sheet.paste(img, ((k % 2) * w, (k // 2) * h))
        sheet.save(out / f"sheet_{n // 4:02d}.png")


@contextlib.contextmanager
def no_focus_override(repo: Path):
    """A windowed Godot launched from the app in the foreground often takes the keyboard
    (3 of 7 measured launches; docs/tooling.md, "The real mouse cursor"). The project
    setting display/window/size/no_focus=true creates the window without activation (0 of
    6 launches), but only at creation, so it has to be in place before the run starts:
    an override.cfg beside project.godot, written for these runs and removed after.
    A stale one would leave the game without keyboard focus, hence the finally and the
    .gitignore line; an existing override.cfg is the author's and is never touched."""
    cfg = repo / "override.cfg"
    if cfg.exists():
        print("override.cfg already exists; leaving it (windows may take focus)")
        yield
        return
    cfg.write_text("[display]\n\nwindow/size/no_focus=true\n", encoding="utf-8")
    try:
        yield
    finally:
        cfg.unlink(missing_ok=True)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--interface-size", type=int, choices=range(5), default=None, help="interface_size_index to write into each temp user dir")
    opts = ap.parse_args()
    repo = Path(opts.repo)
    script = repo / "tools" / "screenshot.gd"
    out = Path(opts.out)
    out.mkdir(parents=True, exist_ok=True)

    lines = stagings(script)
    missing = unstaged_flags(script, lines)
    if missing:
        print("flags screenshot.gd parses that no header line stages: " + " ".join(missing))

    frames: list[Path] = []
    failed: list[str] = []
    with no_focus_override(repo):
        _run_all(lines, opts, repo, out, frames, failed)
    sheets(frames, out)
    print(f"{len(frames)} frames, {len(failed)} failed, into {out}")
    return 1 if failed else 0


def write_interface_size(user_dir: str, index: int) -> None:
    """user:// is APPDATA/Godot/app_userdata/<project> on Windows and XDG_DATA_HOME/godot/... on
    Linux; both point at the same temp dir here, so write the file where either build reads it."""
    for sub in ("Godot", "godot"):
        d = Path(user_dir) / sub / "app_userdata" / "Nation Simulator"
        d.mkdir(parents=True, exist_ok=True)
        (d / "settings.cfg").write_text(f"[display]\n\ninterface_size_index={index}\n", encoding="utf-8")


def _run_all(lines, opts, repo, out, frames, failed) -> None:
    for i, args in enumerate(lines):
        if opts.only and opts.only not in args:
            continue
        target = out / f"{i:02d}_{slug(args)}.png"
        env = dict(os.environ)
        user_dir = tempfile.mkdtemp(prefix="nsim_shot_")
        env["APPDATA"] = user_dir
        env["XDG_DATA_HOME"] = user_dir
        if opts.interface_size is not None:
            write_interface_size(user_dir, opts.interface_size)
        cmd = ["godot", "--path", str(repo), "--script", "res://tools/screenshot.gd", "--"]
        cmd += args.split() + ["--out", str(target)]
        try:
            done = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=TIMEOUT_S)
            ok = done.returncode == 0 and target.exists()
        except subprocess.TimeoutExpired:
            ok = False
        print(f"[{i:02d}] {'ok  ' if ok else 'FAIL'} {args or '(default)'}", flush=True)
        if ok:
            frames.append(target)
            shutil.rmtree(user_dir, ignore_errors=True)  # kept on a failure, for its logs
        else:
            failed.append(args or "(default)")


if __name__ == "__main__":
    sys.exit(main())
