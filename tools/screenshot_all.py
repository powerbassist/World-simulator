#!/usr/bin/env python3
"""A windowed frame for every staged state (V5.1-d2, the tier's done-when).

tools/screenshot.gd takes one flag per staged state and lists each staging in its
header, one `godot ... -- <args>` line apiece. This runs every one of those lines,
windowed (a headless Godot draws nothing), each in its own temporary user dir, and
writes `<out>/<NN>_<slug>.png` plus contact sheets of four frames
(`<out>/sheet_NN.png`) so a session can look at all of them in a few reads.

It also prints any flag screenshot.gd parses that no header line stages: a state
the header does not list is a state nobody photographs.

Usage: python tools/screenshot_all.py --out DIR [--only SUBSTR] [--repo PATH]
Run it alone: it opens one Godot window after another (AGENTS.md, one Godot at a
time in a checkout). Needs Pillow for the sheets; without it the frames still land.
"""
from __future__ import annotations

import argparse
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
MODIFIERS = {"--out", "--frames"}
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


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parent.parent))
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
    for i, args in enumerate(lines):
        if opts.only and opts.only not in args:
            continue
        target = out / f"{i:02d}_{slug(args)}.png"
        env = dict(os.environ)
        user_dir = tempfile.mkdtemp(prefix="nsim_shot_")
        env["APPDATA"] = user_dir
        env["XDG_DATA_HOME"] = user_dir
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
    sheets(frames, out)
    print(f"{len(frames)} frames, {len(failed)} failed, into {out}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
