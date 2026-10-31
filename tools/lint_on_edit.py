"""PostToolUse hook (Edit|Write|MultiEdit): run the authoring lint the edit can break.

Wired in .claude/settings.json beside protect_files.py. The CI jobs for these
lints are slow to come back (a push, a runner); the lints themselves are
stdlib and take well under a second, so the edit that breaks one hears about it
in the same turn.

  data/events/**            -> tools/event_lint.py --check
  data/laws/**              -> tools/law_lint.py --check
  any other data/**, src/ui/*.gd -> tools/i18n_extract.py --check

i18n_extract reads two sources (its header): the literals of src/ui/*.gd, and
the translatable fields of the rows in data/<kind>/*.json. So a row edit can
strand a translation key (a renamed id) as surely as a UI edit can, and a .gd
elsewhere than src/ui cannot move its verdict.

FAIL-OPEN. This hook never blocks: a PostToolUse has nothing left to block, and
a hook that raised on a malformed payload, a missing python or a slow lint would
turn every edit into noise. It prints the failing lines as additionalContext and
exits 0; anything it cannot read, it passes. It starts no Godot.

The project root is the nearest ancestor of the edited file that holds a
project.godot, so a .claude/worktrees/<name>/ checkout lints its own tree.

Dev-only, never ships.   python tools/lint_on_edit.py --selftest
"""

import json
import os
import subprocess
import sys

# (rel-path prefix or suffix test, the tool and its flag). First match per tool.
RULES = (
    (lambda rel: rel.startswith("data/events/"), ("tools/event_lint.py", "--check")),
    (lambda rel: rel.startswith("data/laws/"), ("tools/law_lint.py", "--check")),
    (
        lambda rel: rel.startswith("data/")
        or (rel.startswith("src/ui/") and rel.endswith(".gd")),
        ("tools/i18n_extract.py", "--check"),
    ),
)
TIMEOUT_S = 20
MAX_LINES = 30  # a runaway report must not flood the model's context


def tools_for(rel):
    return [cmd for matches, cmd in RULES if matches(rel)]


def find_root(path):
    """Nearest ancestor of `path` holding a project.godot, else None."""
    d = os.path.dirname(os.path.normpath(path))
    while True:
        if os.path.isfile(os.path.join(d, "project.godot")):
            return d
        parent = os.path.dirname(d)
        if parent == d:
            return None
        d = parent


def locate(payload):
    """(root, rel) for the edited file, or None when there is nothing to judge."""
    tool_input = payload.get("tool_input")
    path = str(tool_input.get("file_path") or "") if isinstance(tool_input, dict) else ""
    if not path:
        return None
    if not os.path.isabs(path):
        base = os.environ.get("CLAUDE_PROJECT_DIR") or str(payload.get("cwd") or "")
        if not base:
            return None
        path = os.path.join(base, path)
    root = find_root(path)
    if root is None:
        return None
    try:
        rel = os.path.relpath(os.path.normpath(path), root)
    except ValueError:  # another drive on Windows
        return None
    return root, rel.replace("\\", "/").lower()


def run_lint(root, cmd):
    """The lint's failing lines, or "" when it passes (or cannot be run)."""
    try:
        done = subprocess.run(
            [sys.executable, os.path.join(root, cmd[0]), cmd[1]],
            cwd=root, capture_output=True, text=True, timeout=TIMEOUT_S,
        )
    except Exception:  # timeout, missing script: fail open
        return ""
    if done.returncode == 0:
        return ""
    lines = (done.stdout + done.stderr).strip().splitlines()
    if len(lines) > MAX_LINES:
        lines = lines[:MAX_LINES] + ["... (%d more lines)" % (len(lines) - MAX_LINES)]
    return "%s %s failed:\n%s" % (cmd[0], cmd[1], "\n".join(lines))


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0
    found = locate(payload)
    if found is None:
        return 0
    root, rel = found
    reports = [r for r in (run_lint(root, c) for c in tools_for(rel)) if r]
    if reports:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PostToolUse",
                "additionalContext": "\n\n".join(reports),
            }
        }))
    return 0


def selftest():
    cases = {
        "data/events/shadows.json": ["tools/event_lint.py", "tools/i18n_extract.py"],
        "data/laws/tax.json": ["tools/law_lint.py", "tools/i18n_extract.py"],
        "data/i18n/fr/ui.json": ["tools/i18n_extract.py"],
        "src/ui/budget_panel.gd": ["tools/i18n_extract.py"],
        "src/sim/economy.gd": [],  # not a src/ui script: i18n_extract ignores it
        "tests/test_clock.gd": [],
        "tools/event_lint.py": [],
        "data/nations/fra.json": ["tools/i18n_extract.py"],  # a row: translatable fields
        "docs/index.md": [],
    }
    bad = 0
    for rel, want in cases.items():
        got = [c[0] for c in tools_for(rel)]
        if got != want:
            print("SELFTEST FAIL: %s -> %r, want %r" % (rel, got, want))
            bad += 1
    if bad:
        return 1
    print("lint_on_edit selftest: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
