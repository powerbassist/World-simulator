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

WHERE THE COMMIT RUNS. The index to read is the one the commit commits in, which
a worktree session reaches with `cd <wt> && git commit` or `git -C <wt> commit`,
not the session's own $CLAUDE_PROJECT_DIR. commit_calls() reads both off the
command text (a leading cd, then each -C in order, as git applies them) and
resolve() turns them into a directory, falling back to the session's root when a
path does not exist (a $VAR or $(...) it cannot expand). A commit is `git`, then
only global options, then `commit` as the subcommand: `git log --grep commit`,
`git commit-tree` and `git config alias.commit` are not.

The settings.json entry also carries an `if` filter so Python is not started for
every Bash call; the matching here stays, because the filter is best-effort.

Dev-only, never ships.   python tools/guard_commit_shards.py --selftest
"""

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# A shell word: a quoted string or a run of non-separator characters.
_TOK = r"""(?:"[^"]*"|'[^']*'|[^\s;&|()]+)"""
# git's global options before the subcommand. -c and -C take a value; the long
# forms are written --opt or --opt=value (a bare `--git-dir x` is left unread).
_GLOBAL = r"(?:\s+(?:-C\s+%s|-c\s+%s|--[A-Za-z][\w-]*(?:=%s)?|-[pP]))*" % (_TOK, _TOK, _TOK)
COMMIT = re.compile(r"(?<![\w./-])git(?P<opts>%s)\s+commit(?![\w-])" % _GLOBAL)
_C_OPT = re.compile(r"-C\s+(%s)" % _TOK)
# The terminator is a lookahead so `cd a; cd b && ...` still sees the second cd;
# a newline separates commands as well (a multi-line Bash call), hence [ \t]* and \n.
_CD = re.compile(r"(?:^|[;&|(\n])[ \t]*cd[ \t]+(%s)(?=[ \t]*(?:&&|;|\n))" % _TOK)
TEST_PATH = re.compile(r"\btests/test_[A-Za-z0-9_]+\.gd\b")
# Three subprocesses at most (git, bash, ci_shards): 3 x 20 s stays under the
# 70 s hook timeout in .claude/settings.json, so a slow check asks nothing
# instead of being killed half way.
TIMEOUT_S = 20


def _unquote(tok):
    if len(tok) >= 2 and tok[0] == tok[-1] and tok[0] in "\"'":
        return tok[1:-1]
    return tok


def commit_calls(command):
    """[(cd, [-C paths])] for each `git ... commit` in the command, in order.

    cd is the path of the last `cd X &&` / `cd X;` before that commit, or None.
    """
    calls = []
    for m in COMMIT.finditer(command):
        cd = None
        for c in _CD.finditer(command[:m.start()]):
            cd = _unquote(c.group(1))
        paths = [_unquote(t) for t in _C_OPT.findall(m.group("opts") or "")]
        calls.append((cd, paths))
    return calls


def unix_to_windows(path):
    """Git Bash writes F:\\x as /f/x; Python on Windows reads /f/x as F:\\f\\x."""
    m = re.match(r"^/([A-Za-z])(?:/(.*))?$", path)
    if os.name == "nt" and m:
        return "%s:/%s" % (m.group(1).upper(), m.group(2) or "")
    return path


def resolve(base, call):
    """The directory a commit runs in: the cd, then each -C applied to the last.

    A step whose directory does not exist (a $VAR the hook cannot expand) ends the
    walk at the session's own root, which is what the hook read before this existed.
    """
    cd, paths = call
    here = base
    for step in ([cd] if cd else []) + list(paths):
        step = os.path.expanduser(unix_to_windows(step))
        nxt = os.path.normpath(os.path.join(here, step))
        if not os.path.isdir(nxt):
            return base
        here = nxt
    return here


def toplevel(directory):
    """The repository root holding `directory`, or None."""
    try:
        done = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            cwd=directory, capture_output=True, text=True, timeout=TIMEOUT_S,
        )
    except Exception:
        return None
    if done.returncode != 0 or not done.stdout.strip():
        return None
    return os.path.normpath(done.stdout.strip())


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


def is_wsl_launcher(path):
    # System32's bash.exe and the WindowsApps stub are WSL launchers: they would
    # read the CRLF working copy wrong and report a failure that is not one.
    return bool(re.search(r"[\\/](system32|windowsapps)[\\/]", path, re.I))


def find_bash():
    """bash from PATH, as a full path. subprocess's bare "bash" resolves through
    CreateProcess, which on Windows finds System32's WSL launcher before Git's
    bash and chokes on the working copy's CRLF; shutil.which follows PATH."""
    bash = shutil.which("bash")
    if bash and is_wsl_launcher(bash):
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
    calls = commit_calls(command)
    if not calls:
        return 0
    base = os.environ.get("CLAUDE_PROJECT_DIR") or str(payload.get("cwd") or "")
    if not base:
        return 0
    named = named_tests(command)
    reports = []
    seen = set()
    for call in calls:
        root = toplevel(resolve(base, call))
        if root is None or root in seen:
            continue
        seen.add(root)
        if not os.path.isfile(os.path.join(root, "tools", "ci_shards.py")):
            continue
        touched = sorted(set(staged_tests(root)) | set(named))
        if not touched:
            continue
        problem = shard_problem(root)
        if problem:
            reports.append("%s touches %s.\n%s" % (root.replace("\\", "/"), ", ".join(touched), problem))
    if reports:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "ask",
                "permissionDecisionReason": (
                    "This commit touches a test and CI's shard check fails: register a "
                    "new test in tools/run_tests.sh AND tools/ci_shards.json.\n"
                    + "\n\n".join(reports)
                ),
            }
        }))
    return 0


def selftest():
    bad = 0

    def check(label, got, want):
        nonlocal bad
        if got != want:
            print("SELFTEST FAIL: %s -> %r, want %r" % (label, got, want))
            bad += 1

    # Which commands are a commit, and where each one runs (cd first, then -C).
    plain = [
        ("git commit -m x", [(None, [])]),
        ("git add tests/test_a.gd && git commit -m x", [(None, [])]),
        ('git commit -m "$(cat <<EOF\nmsg\nEOF\n)"', [(None, [])]),
        ("git -C wt commit -m x", [(None, ["wt"])]),
        ('git -C "my wt" commit -m x', [(None, ["my wt"])]),
        ("git -c user.name=x --no-pager commit", [(None, [])]),
        ("cd wt && git commit -m x", [("wt", [])]),
        ('cd "/f/Dev/x y" && git add a && git commit -m x', [("/f/Dev/x y", [])]),
        ("cd a; cd b && git commit", [("b", [])]),
        ("cd a && git -C sub commit", [("a", ["sub"])]),
        ("(cd wt && git commit -m x)", [("wt", [])]),
        ("FOO=1 git commit", [(None, [])]),
        ("cd wt\ngit add a\ngit commit -m x", [("wt", [])]),
        ("cd a\ncd b\ngit commit", [("b", [])]),
    ]
    for cmd, want in plain:
        check("calls(%r)" % cmd, commit_calls(cmd), want)
    # Never a commit: another subcommand that mentions the word, or a sibling command.
    for cmd in ["git status", "git log --oneline", "git log --grep commit", "git log --grep=commit",
                "git commit-tree abc", "git show commit", "ls tests", "git diff --cached",
                "git push", "echo commit", "gitk commit", "git config alias.commit x"]:
        check("calls(%r)" % cmd, commit_calls(cmd), [])
    check("two commits", commit_calls("git -C a commit -m x && git -C b commit -m y"),
          [(None, ["a"]), (None, ["b"])])

    # Resolving: a real directory wins, a -C follows the cd, a missing one falls back.
    with tempfile.TemporaryDirectory() as tmp:
        tmp = os.path.realpath(tmp)
        os.makedirs(os.path.join(tmp, "a", "sub"))
        check("resolve cd", resolve(tmp, ("a", [])), os.path.join(tmp, "a"))
        check("resolve -C", resolve(tmp, (None, ["a"])), os.path.join(tmp, "a"))
        check("resolve cd then -C", resolve(tmp, ("a", ["sub"])), os.path.join(tmp, "a", "sub"))
        check("resolve absolute -C", resolve(os.path.join(tmp, "nowhere"), (None, [os.path.join(tmp, "a")])),
              os.path.join(tmp, "a"))
        check("resolve missing", resolve(tmp, (None, ["nope"])), tmp)
        check("resolve none", resolve(tmp, (None, [])), tmp)
    if os.name == "nt":
        check("git-bash drive", unix_to_windows("/f/Dev/x"), "F:/Dev/x")
        check("plain path kept", unix_to_windows("F:/Dev/x"), "F:/Dev/x")

    check("named_tests",
          named_tests("git add tests/test_a.gd tests/test_b.gd src/x.gd tests/helper.gd && git commit"),
          ["tests/test_a.gd", "tests/test_b.gd"])

    # find_bash must refuse a WSL launcher in either slash style.
    for wsl in ["C:\\WINDOWS\\system32\\bash.EXE", "C:/Windows/System32/bash.exe",
                "C:\\Users\\u\\AppData\\Local\\Microsoft\\WindowsApps\\bash.exe"]:
        check("wsl %r" % wsl, is_wsl_launcher(wsl), True)
    check("git bash", is_wsl_launcher("C:\\Program Files\\Git\\usr\\bin\\bash.EXE"), False)

    if bad:
        return 1
    print("guard_commit_shards selftest: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
