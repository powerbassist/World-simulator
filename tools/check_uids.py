"""Orphan .uid check over the TRACKED files -- what a fresh clone holds.

Godot writes `<script>.uid` beside every script it imports and never deletes it
when the script goes: deleting `tests/test_bloc.gd` left `tests/test_bloc.gd.uid`
committed (9a8994f2 removed the script, the uid stayed). A uid with no tracked
sibling is dead weight that the next reader has to explain. Exit 1 when one is
found; nothing is read from disk, only `git ls-files`.

    python tools/check_uids.py
    python tools/check_uids.py --selftest
"""
import subprocess
import sys


def orphans(files):
    """The tracked `X.uid` files whose `X` is not tracked."""
    tracked = set(files)
    return sorted(p for p in tracked if p.endswith(".uid") and p[:-len(".uid")] not in tracked)


def selftest():
    files = ["a/x.gd", "a/x.gd.uid", "a/y.gd.uid", "b/z.gdshader", "b/z.gdshader.uid",
             "c/w.uid.txt", "q.uid"]
    got = orphans(files)
    # q.uid names a sibling "q" that is not tracked; y.gd.uid lost its script.
    if got != ["a/y.gd.uid", "q.uid"]:
        print("SELFTEST FAIL: orphans() returned %r" % got)
        return 1
    print("check_uids selftest: all checks passed")
    return 0


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                          text=True, check=True).stdout.strip()
    out = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True)
    bad = orphans([p for p in out.stdout.splitlines() if p])
    for p in bad:
        print("orphan .uid (its %s is not tracked): %s" % (p[:-len(".uid")], p))
    if bad:
        print("%d orphan .uid file(s); `git rm` them." % len(bad))
        return 1
    print("no orphan .uid files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
