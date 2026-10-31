#!/usr/bin/env python3
"""Build the Windows release: build/NationSimulator.exe + NationSimulator.pck.

    python tools/export_windows.py --templates PATH/TO/4.7.2.stable [--out build]

--templates is a folder holding windows_release_x86_64.exe (+ _console) and
version.txt, taken from the OFFICIAL Godot_v4.7.2-stable_export_templates.tpz after
its SHA-512 was checked against the release's SHA512-SUMS. docs/tooling.md has the
steps. Nothing is installed into %APPDATA%\\Godot: the export runs under a private
APPDATA/XDG_DATA_HOME (the same isolation tools/suite_runner.py gives a test run), so
an export beside the editor or another run touches neither's user dir.

WHY A STAGE. The game reads the SVG icons, every OGG clip and
bed, the summit .dialogue scenes -- as BYTES or text (`FileAccess`), never `load()`:
that is how a fresh clone runs headless. An export keeps an imported file only as its
converted form, so those reads would find nothing in the PCK. `importer="keep"` makes
the export ship the file as is (the webp and the jpg already use it). Flipping it in
the committed .import files would touch ~430 files and fight every editor that
re-imports a new clip, so it is flipped in a throwaway COPY of the tracked tree.

The stage also takes project.godot from HEAD, never the working copy: the editor
rewrites that file per machine (AGENTS.md "Gotchas") and an autoload for an addon that
is not in the export would break the exe.

Dev-only: tools/ never ships. Exit 0 only when the PCK passes its own audit.
"""
import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PRESET = "Windows Desktop"
EXE_NAME = "NationSimulator.exe"
# What the exe needs at runtime; everything else (tools/, tests/, docs/, reports/,
# .obsidian/, the design vault) stays out of the stage altogether.
STAGE_ROOTS = ("src", "data", "assets", "addons")
STAGE_FILES = ("export_presets.cfg",)
# Extensions the game reads as bytes/text (see the docstring). The .ttf is NOT here:
# ui_theme.gd load()s the imported FontFile first and only falls back to bytes.
KEEP_EXT = (".ogg", ".svg", ".dialogue")
# Prefixes that must be absent from the PCK (its paths carry no res:// and a script
# appears as .gdc + .gd.remap, hence the stems).
FORBIDDEN = ("tools/", "tests/", "docs/", "reports/", "src/ui/dev_console.", "src/ui/dev_registry.",
             "src/ui/dev_log.", "src/ui/dev_perf.", "src/sim/dev_commands.")
TEMPLATE_FILES = ("windows_release_x86_64.exe", "windows_release_x86_64_console.exe",
                  "windows_debug_x86_64.exe", "windows_debug_x86_64_console.exe",
                  "version.txt")


def run(cmd, env, log, timeout, cwd=None):
    """Run, send stdout+stderr into `log`, return the exit code."""
    with open(log, "wb") as f:
        p = subprocess.run(cmd, env=env, cwd=cwd, stdout=f, stderr=subprocess.STDOUT, timeout=timeout)
    return p.returncode


# The editor-side dialogue_manager plugin builds a code editor with no theme when Godot runs
# headless, and prints this once at startup -- from a plain `godot --headless --import` of the
# repo too, so it is not the build's. Matched on the line after it; any other ERROR still fails.
EDITOR_NOISE = "DMCodeEdit.@theme_overrides_setter"


# Shutdown leak accounting ("... leaked at exit", "... still in use at exit") is reported when the
# harness quits with a game scene's fonts still alive; it is not a fault of the game at runtime.
def error_lines(log: str) -> list[str]:
    lines = log.splitlines()
    return [l for i, l in enumerate(lines)
            if "ERROR" in l and " at exit" not in l
            and EDITOR_NOISE not in (lines[i + 1] if i + 1 < len(lines) else "")]


def tracked(*roots):
    out = subprocess.run(["git", "ls-files", "-z", "--", *roots], cwd=REPO, check=True,
                         capture_output=True).stdout.decode("utf-8")
    return [p for p in out.split("\0") if p]


def build_stage(stage: Path) -> int:
    files = tracked(*STAGE_ROOTS, *STAGE_FILES)
    for rel in files:
        src = REPO / rel
        if not src.is_file():  # tracked but deleted in the working copy
            continue
        dst = stage / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
    head = subprocess.run(["git", "show", "HEAD:project.godot"], cwd=REPO, check=True,
                          capture_output=True).stdout
    (stage / "project.godot").write_bytes(head)
    return len(files)


def flip_to_keep(stage: Path) -> int:
    n = 0
    # Only the game's own folders: addons/dialogue_manager's editor plugin load()s its own
    # SVG icons while the stage imports, and a kept file cannot be load()ed.
    for imp in (p for root in ("assets", "data") for p in (stage / root).rglob("*.import")):
        source = imp.name[: -len(".import")]
        if not source.endswith(KEEP_EXT):
            continue
        rel = imp.relative_to(stage).as_posix()[: -len(".import")]
        imp.write_text('[remap]\n\nimporter="keep"\n\n[deps]\n\nsource_file="res://%s"\n' % rel,
                       encoding="utf-8", newline="\n")
        n += 1
    return n


def read_pck(path: Path) -> list[str]:
    """Paths inside a standalone .pck (format 2 and 3), as stored: no res:// prefix."""
    with open(path, "rb") as f:
        if f.read(4) != b"GDPC":
            raise ValueError("not a Godot pack")
        version, = struct.unpack("<I", f.read(4))
        f.read(12)  # engine major, minor, patch
        f.read(4)   # pack flags
        f.read(8)   # file base
        if version >= 3:
            dir_offset, = struct.unpack("<Q", f.read(8))
            f.seek(dir_offset)
        else:
            f.read(64)  # 16 reserved u32
        count, = struct.unpack("<I", f.read(4))
        names = []
        for _ in range(count):
            length, = struct.unpack("<I", f.read(4))
            names.append(f.read(length).split(b"\0", 1)[0].decode("utf-8"))
            f.read(8 + 8 + 16 + 4)  # offset, size, md5, flags
        return names


def audit(pck: Path, stage: Path) -> list[str]:
    """Return the problems; empty means the PCK has what the game reads and nothing else."""
    names = set(read_pck(pck))
    problems = []
    for bad in sorted(n for n in names if n.startswith(FORBIDDEN)):
        problems.append("shipped but must not: " + bad)
    must = [p for p in tracked("data", "assets")
            if p.endswith((".json", ".geojson", ".webp", ".jpg") + KEEP_EXT)
            and not p.endswith(".import") and "/gitkeep" not in p]
    for rel in must:
        if rel not in names:
            problems.append("missing raw file: " + rel)
    for core in ("project.binary", "src/ui/menu.tscn.remap", "src/ui/main.tscn.remap"):
        if core not in names:
            problems.append("missing: " + core)
    # The font is the one asset load()ed as a resource, so it ships in its imported form.
    if not any(n.endswith(".fontdata") for n in names):
        problems.append("missing: the Archivo font (imported form)")
    print("pck: %d entries, %d raw files audited" % (len(names), len(must)))
    return problems


def smoke(godot: str, exe: Path, out: Path) -> int:
    """Two checks, each in a private user dir, each failing on any ERROR line.

    1. The exe itself boots headless to the menu and quits. An export template ignores
       --script (measured, 4.7.2: it just boots the game), so it cannot run a harness...
    2. ...which therefore runs under the stock engine with the PCK as its main pack:
       res:// is the exported pack, the settings and autoloads the exported ones.
    """
    user = Path(tempfile.mkdtemp(prefix="nationsim-smoke-"))
    env = dict(os.environ, APPDATA=str(user), XDG_DATA_HOME=str(user))
    try:
        runs = [("exe-boot", [str(exe), "--headless", "--quit-after", "200", "--log-file", str(out / "exe-boot-engine.log")]),
                ("pck-smoke", [godot, "--headless", "--main-pack", str(exe.with_suffix(".pck")),
                               "--script", str(REPO / "tools" / "exe_smoke.gd")])]
        bad = 0
        for name, cmd in runs:
            log_path = out / (name + ".log")
            # cwd = the empty private dir: the stock engine looks for a project.godot in the
            # current folder first and would run the CHECKOUT instead of the pack (measured:
            # run from the repo, the 'not in the PCK' checks fail, which is how it showed).
            code = run(cmd, env, log_path, 600, cwd=user)
            log = log_path.read_text(errors="replace")
            if name == "exe-boot":  # the exe's own log-file holds what a console would show
                log += (out / "exe-boot-engine.log").read_text(errors="replace")
            errors = error_lines(log)
            keep = [l for l in log.splitlines() if l.startswith(("ok", "FAIL", "exe_smoke"))]
            print(chr(10).join(keep) if not (code or errors) else log[-2000:])
            print("%s: exit %d, %d ERROR lines" % (name, code, len(errors)))
            bad += 1 if code or errors else 0
        return 1 if bad else 0
    finally:
        shutil.rmtree(user, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--templates", default=os.environ.get("GODOT_EXPORT_TEMPLATES"),
                    help="folder with the 4.7.2 windows templates (or $GODOT_EXPORT_TEMPLATES)")
    ap.add_argument("--godot", default=os.environ.get("GODOT") or shutil.which("godot"))
    ap.add_argument("--out", default=str(REPO / "build"), help="output folder (default build/, gitignored)")
    ap.add_argument("--smoke", action="store_true", help="after the export, boot the exe headless under tools/exe_smoke.gd")
    ap.add_argument("--keep-stage", action="store_true", help="keep the stage folder on success too")
    a = ap.parse_args()
    if not a.godot:
        sys.exit("no godot on PATH (set $GODOT)")
    if not a.templates or not (Path(a.templates) / TEMPLATE_FILES[0]).is_file():
        sys.exit("--templates must be a folder holding %s" % TEMPLATE_FILES[0])

    version = subprocess.run([a.godot, "--version"], check=True, capture_output=True, text=True).stdout
    m = re.match(r"(\d+\.\d+(?:\.\d+)?\.[a-z0-9]+)", version.strip())
    if not m:
        sys.exit("cannot read the godot version: " + version)
    tpl_version = (Path(a.templates) / "version.txt").read_text().strip()
    if tpl_version != m.group(1):
        sys.exit("templates are %s, the editor is %s" % (tpl_version, m.group(1)))

    out = Path(a.out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob("NationSimulator*"):
        old.unlink()
    work = Path(tempfile.mkdtemp(prefix="nationsim-export-"))
    stage, appdata = work / "stage", work / "appdata"
    ok = False
    try:
        stage.mkdir()
        # APPDATA on Windows, XDG_DATA_HOME on Linux (same pair suite_runner.py sets).
        tpl_dir = appdata / "Godot" / "export_templates" / tpl_version
        tpl_dir.mkdir(parents=True)
        shutil.copytree(a.templates, tpl_dir, dirs_exist_ok=True)
        if sys.platform != "win32":
            (appdata / "godot").symlink_to(appdata / "Godot")
        env = dict(os.environ, APPDATA=str(appdata), XDG_DATA_HOME=str(appdata))

        print("stage: %d tracked files" % build_stage(stage))
        print("stage: %d .import files set to keep" % flip_to_keep(stage))

        # No separate --import: the export's own first scan imports the stage (a second
        # pass over the 4 000 kept files was three minutes of the same work).
        exe = out / EXE_NAME
        code = run([a.godot, "--headless", "--path", str(stage), "--export-release", PRESET, str(exe)],
                   env, out / "export.log", 900)
        log = (out / "export.log").read_text(errors="replace")
        errors = error_lines(log)
        if code or not exe.is_file() or errors:
            print("export failed (exit %d), %d ERROR lines; first: %s" % (code, len(errors), errors[:3]))
            return 1
        pck = exe.with_suffix(".pck")
        if not pck.is_file():
            print("no .pck beside the exe")
            return 1
        problems = audit(pck, stage)
        for p in problems[:20]:
            print("AUDIT", p)
        if problems:
            print("%d audit problems" % len(problems))
            return 1
        for f in sorted(out.glob("NationSimulator*")):
            print("%-34s %9.1f MB" % (f.name, f.stat().st_size / 1e6))
        ok = True
        return smoke(a.godot, exe, out) if a.smoke else 0
    finally:
        if ok and not a.keep_stage:
            shutil.rmtree(work, ignore_errors=True)
        else:
            print("stage kept: %s" % work)


if __name__ == "__main__":
    sys.exit(main())
