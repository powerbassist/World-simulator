"""PreToolUse hook (Bash): a commit that touches a test must keep the shard list true.

Wired in .claude/settings.json. AGENTS.md's recorded bite: a new tests/test_*.gd
registered in tools/run_tests.sh but not in tools/ci_shards.json passes the local
gate (the runner does not check shards) and fails CI. This is the same check CI
runs ("Every registered test is in exactly one shard"):

  bash tools/run_tests.sh --print-tests | python tools/ci_shards.py --check

run_tests.sh --print-tests also fails on a test file on disk that is not in
tests=(), so a test registered nowhere is caught by the same call.

It fires on a `git commit` while a tests/test_*.gd is staged (git diff --cached),
or is named in the same command line -- `git add tests/test_x.gd && git commit`
runs the hook before the add. On a failure it answers permissionDecision "ask"
with the check's own output, so the human decides; it never denies. On a pass,
a non-commit command, or anything it cannot read, it prints nothing and exits 0.
No Godot is started.

Dev-only, never ships.   python tools/guard_commit_shards.py --selftest
"""

import json
import os
import re
import shutil
import subprocess
import sys

COMMIT = re.compile(r"\bgit\b[^;&|\n]*?\bcommit\b")
TEST_PATH = re.compile(r"\btests/test_[A-Za-z0-9_]+\.gd\b")
# Three subprocesses at most (git, bash, ci_shards): 3 x 20 s stays under the
# 70 s hook timeout in .claude/settings.json, so a slow check asks nothing
# instead of being killed half way.
TIMEOUT_S = 20


def is_commit(command):
    return bool(COMMIT.search(command))


def named_tests(command):
    return sorted(set(TEST_PATH.findall(command)))


def staged_tests(root):
    try:
        done = subprocess.run(
            ["git", "diff", "--cached", "--name-only"],
            cwd=root, capture_output=True, text=True, timeout=TIMEOUT_S,
        )
    except Exception:
        return []
    if done.returncode != 0:
        return []
    return [p for p in done.stdout.splitlines() if TEST_PATH.fullmatch(p.strip())]


def find_bash():
    """bash from PATH, as a full path. subprocess's bare "bash" resolves through
    CreateProcess, which on Windows finds System32's WSL launcher before Git's
    bash and chokes on the working copy's CRLF; shutil.which follows PATH."""
    bash = shutil.which("bash")
    # System32's bash.exe and the WindowsApps stub are WSL launchers: they would
    # read the CRLF working copy wrong and report a failure that is not one.
    if bash and re.search(r"[\/](system32|windowsapps)[\/]", bash, re.I):
        return None
    return bash


def shard_problem(root):
    """The check's output when it fails, "" when it passes or cannot be run."""
    bash = find_bash()
    if not bash:
        return ""
    try:
        reg = subprocess.run(
            [bash, "tools/run_tests.sh", "--print-tests"],
            cwd=root, capture_output=True, text=True, timeout=TIMEOUT_S,
        )
        if reg.returncode != 0:
            return "tools/run_tests.sh --print-tests failed:\n" + (reg.stderr or reg.stdout).strip()
        chk = subprocess.run(
            [sys.executable, "tools/ci_shards.py", "--check"],
            cwd=root, input=reg.stdout, capture_output=True, text=True, timeout=TIMEOUT_S,
        )
    except Exception:  # no bash, a timeout: fail open
        return ""
    if chk.returncode == 0:
        return ""
    return "tools/ci_shards.py --check failed:\n" + (chk.stdout + chk.stderr).strip()


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    if not isinstance(payload, dict):
        return 0
    tool_input = payload.get("tool_input")
    command = str(tool_input.get("command") or "") if isinstance(tool_input, dict) else ""
    if not is_commit(command):
        return 0
    root = os.environ.get("CLAUDE_PROJECT_DIR") or str(payload.get("cwd") or "")
    if not root or not os.path.isfile(os.path.join(root, "tools", "ci_shards.py")):
        return 0
    touched = sorted(set(staged_tests(root)) | set(named_tests(command)))
    if not touched:
        return 0
    problem = shard_problem(root)
    if problem:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": (
                    "This commit touches %s, and CI's shard check fails: "
                    "register a new test in tools/run_tests.sh AND tools/ci_shards.json.\n%s"
                    % (", ".join(touched), problem)
                ),
            }
        }))
    return 0


def selftest():
    commits = [
        "git commit -m x",
        "git -C wt commit -m x",
        "git add tests/test_a.gd && git commit -m x",
        'git commit -m "$(cat <<EOF\nmsg\nEOF\n)"',
    ]
    others = ["git status", "git log --oneline", "ls tests", "git diff --cached", "git push"]
    bad = 0
    for c in commits:
        if not is_commit(c):
            print("SELFTEST FAIL: not seen as a commit: %r" % c)
            bad += 1
    for c in others:
        if is_commit(c):
            print("SELFTEST FAIL: wrongly seen as a commit: %r" % c)
            bad += 1
    got = named_tests("git add tests/test_a.gd tests/test_b.gd src/x.gd tests/helper.gd && git commit")
    if got != ["tests/test_a.gd", "tests/test_b.gd"]:
        print("SELFTEST FAIL: named_tests -> %r" % got)
        bad += 1
    if bad:
        return 1
    print("guard_commit_shards selftest: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
