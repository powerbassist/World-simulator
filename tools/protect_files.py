"""PreToolUse hook (Edit|Write|MultiEdit): stop edits to files a machine owns.

Wired in .claude/settings.json. The git-staging half of this footgun is guarded
at user level (repo-guards, godot-stage-guard.py); nothing guarded the EDIT.

  deny -- the engine or the runner generates it, a hand edit is always wrong:
          .godot/**, reports/suite_runs/**, *.uid
  ask  -- a real edit is sometimes right (AGENTS.md: an engine bump, an autoload
          fix, the committed icon imports), so the human decides:
          project.godot, *.import

Paths are judged relative to the project root (or, under
.claude/worktrees/<name>/, to that worktree's root), so every checkout is
guarded the same way. A file outside the
root, or a payload this script cannot read, passes: a guard that fails closed
would block every edit on a malformed event.

Dev-only, never ships.
"""

import json
import os
import sys

DENY_PREFIXES = (".godot/", "reports/suite_runs/")
DENY_SUFFIXES = (".uid",)
ASK_NAMES = ("project.godot",)
ASK_SUFFIXES = (".import",)


def relative_path(payload):
    path = str((payload.get("tool_input") or {}).get("file_path") or "")
    if not path:
        return None
    root = os.environ.get("CLAUDE_PROJECT_DIR") or str(payload.get("cwd") or "")
    if not root:
        return None
    if not os.path.isabs(path):
        path = os.path.join(root, path)
    try:
        rel = os.path.relpath(os.path.normpath(path), os.path.normpath(root))
    except ValueError:  # another drive on Windows
        return None
    rel = rel.replace("\\", "/").lower()
    if rel.startswith("../") or rel == "..":
        return None
    # A session in the main checkout can edit a worktree's files; judge them
    # by their own root, as the worktree's own session would.
    if rel.startswith(".claude/worktrees/"):
        rel = "/".join(rel.split("/")[3:])
    return rel


def decide(rel):
    if rel.startswith(DENY_PREFIXES) or rel.endswith(DENY_SUFFIXES):
        return "deny", (
            rel + " is generated (the engine or the test runner writes it); "
            "regenerate it instead of editing it."
        )
    if rel in ASK_NAMES:
        return "ask", (
            "project.godot is rewritten by every editor open and is never staged "
            "(AGENTS.md). Approve only for a deliberate change such as an engine "
            "bump or an autoload fix."
        )
    if rel.endswith(ASK_SUFFIXES):
        return "ask", (
            rel + " is an import record the editor writes; edit it by hand only "
            "for a deliberate import setting."
        )
    return None, ""


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    rel = relative_path(payload)
    if rel is None:
        return 0
    verdict, reason = decide(rel)
    if verdict:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": verdict,
                "permissionDecisionReason": reason,
            }
        }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
