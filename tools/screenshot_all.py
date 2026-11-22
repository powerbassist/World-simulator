#!/usr/bin/env python3
"""A windowed frame for every staged state (V5.1-d2, the tier's done-when).

tools/screenshot.gd takes one flag per staged state and lists each staging in its
header, one `godot ... -- <args>` line apiece. This runs every one of those lines,
windowed (a headless Godot draws nothing), each in its own temporary user dir, and
writes `<out>/<NN>_<slug>.png` plus contact sheets of four frames
(`<out>/sheet_NN.png`) so a session can look at all of them in a few reads.

It also prints any flag screenshot.gd parses that no header line stages: a state
the header does not list is a state nobody photographs.

Usage: python tools/screenshot_all.py --out DIR [--only SUBSTR] [--repo PATH] [--interface-size N] [--screen auto|off|N]
--screen: where the capture window goes (the author's call of 2026-11-21: his SECONDARY screen, not under
his hands). auto (default) = screen index 1 when the machine has two or more monitors, else off every
monitor as before; off = always off screen; N = that screen. It is passed as the engine's `--screen N`
and as NATION_SHOT_SCREEN, which tools/os_cursor.gd's quiet_window() reads each frame.
The interface size is always written: --interface-size N, else index 1 (1.0), because Auto would follow
the other screen's resolution and change every frame.
--interface-size N writes settings.cfg [display] interface_size_index=N into each run's temp user
dir (src/ui/interface_size.gd: 1 = 1.0, 2 = 0.9, 3 = 0.8, 4 = 0.75); without it the game's default (Auto).
A folder named for a size (t100, t075) must hold that size's frames: --out t075 with --interface-size 0 (Auto) or
1 is refused, because Auto follows the screen and index 4 is 0.75, so the name would lie (Igor, 2026-11-22).
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


# interface_size_index -> the size it means (src/ui/interface_size.gd SIZES; 0 is Auto, no fixed size).
INTERFACE_SIZES = {1: 1.0, 2: 0.9, 3: 0.8, 4: 0.75}
SIZE_DIR = re.compile(r"^t(\d{3})$")


def out_name_mismatch(out: Path, index: int | None) -> str:
    """'' when --out's folder name does not claim a size or claims the one `index` really is; else why not.
    index None is the script's own default, 1 (1.0)."""
    m = SIZE_DIR.match(out.name)
    if not m:
        return ""
    real = 1 if index is None else index
    if real not in INTERFACE_SIZES:
        return f"--out {out.name} names a size but --interface-size {real} is Auto, which follows the screen: pass 1..4 or name the folder otherwise"
    if int(m.group(1)) != round(INTERFACE_SIZES[real] * 100):
        return f"--out {out.name} claims {int(m.group(1))}% but --interface-size {real} is {round(INTERFACE_SIZES[real] * 100)}% (index 4 is 0.75, 1 is 1.0)"
    return ""


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


def selftest() -> int:
    ok = [
        (Path("x/t100"), None), (Path("x/t100"), 1), (Path("x/t075"), 4), (Path("x/t090"), 2), (Path("x/t080"), 3),
        (Path("x/frames"), 0), (Path("x/frames"), 4), (Path("t100x"), 0),
    ]
    bad = [
        (Path("x/t075"), 0), (Path("x/t075"), 1), (Path("x/t075"), None), (Path("x/t100"), 4), (Path("x/t100"), 0),
        (Path("x/t090"), 4),
    ]
    failures = [f"{o} idx {i}: refused ({out_name_mismatch(o, i)})" for o, i in ok if out_name_mismatch(o, i)]
    failures += [f"{o} idx {i}: accepted, a mismatch" for o, i in bad if not out_name_mismatch(o, i)]
    for f in failures:
        print("FAIL " + f)
    print("screenshot_all selftest: " + ("all checks passed" if not failures else f"{len(failures)} failures"))
    return 1 if failures else 0


def main() -> int:
    if "--selftest" in sys.argv[1:]:
        return selftest()
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--repo", default=str(Path(__file__).resolve().parent.parent))
    ap.add_argument("--interface-size", type=int, choices=range(5), default=None, help="interface_size_index to write into each temp user dir (default 1, 1.0)")
    ap.add_argument("--screen", default="auto", help="auto (screen 1 if there are two or more), off, or N")
    opts = ap.parse_args()
    if opts.screen not in ("auto", "off") and not opts.screen.isdigit():
        ap.error("--screen takes auto, off or a screen index")
    bad = out_name_mismatch(Path(opts.out), opts.interface_size)
    if bad:
        ap.error(bad)
    opts.screen_n = resolve_screen(opts.screen)
    print(f"capture window: {'screen %d' % opts.screen_n if opts.screen_n is not None else 'off screen'}")
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


def screen_count() -> int:
    """Monitors the OS reports; 1 where it cannot be asked (not Windows), which keeps the
    off-screen behaviour there."""
    if sys.platform != "win32":
        return 1
    import ctypes
    return int(ctypes.windll.user32.GetSystemMetrics(80))  # SM_CMONITORS


def resolve_screen(arg: str) -> int | None:
    """None = off screen. auto: the second monitor when there is one. An N past the last screen
    falls back to off screen too, which quiet_target() would do anyway."""
    if arg == "off":
        return None
    n = 1 if arg == "auto" else int(arg)
    return n if n < screen_count() else None


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
        write_interface_size(user_dir, 1 if opts.interface_size is None else opts.interface_size)
        cmd = ["godot", "--path", str(repo)]
        if opts.screen_n is not None:
            env["NATION_SHOT_SCREEN"] = str(opts.screen_n)
            cmd += ["--screen", str(opts.screen_n)]
        cmd += ["--script", "res://tools/screenshot.gd", "--"]
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
