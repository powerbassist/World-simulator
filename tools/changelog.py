#!/usr/bin/env python3
"""The changelog and the build version: check them, cut a release, print its notes.

    python tools/changelog.py --check            fragments parse; version.json matches CHANGELOG.md
    python tools/changelog.py --check-pr BASE    a PR that changes src/, data/ or assets/ adds a fragment
    python tools/changelog.py cut VERSION [--label TEXT] [--date YYYY-MM-DD]
    python tools/changelog.py notes [VERSION]    a version's section; no VERSION: what is unreleased
    python tools/changelog.py --selftest

THE RULE (AGENTS.md, "Versions and changelog"). A pull request that changes what ships
(src/, data/, assets/) adds ONE file, changelog.d/<branch-slug>.md, one line per change a
player notices, each starting with its group:

    Fixed: An answer given in the folder clears its line on the month page.
    None: the loader split, nothing a player sees.

WHY FRAGMENTS. Several children have pull requests open at once. One shared
[Unreleased] block would put every open PR in conflict on the same hunk at each merge;
one file per PR never conflicts. The fragments ARE the unreleased section until a cut.

THE CUT is its own pull request, made when a kit the author plays is ordered: this
script moves the fragments into a dated section of CHANGELOG.md, deletes them and sets
version.json. The parent merges it and tags the merge commit v<version>; the kit is
exported from that tag (tools/export_windows.py reads the tag). Nothing else edits
CHANGELOG.md or version.json.

Stdlib only: CI runs it with no install.
"""
import argparse
import datetime
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
FRAGMENTS = "changelog.d"
README = "README.md"
# Keep a Changelog's groups, in the order a section prints them. "None" is the explicit
# "nothing a player sees": it satisfies --check-pr and prints nowhere.
GROUPS = ("Added", "Changed", "Deprecated", "Removed", "Fixed", "Security")
# A pull request that touches one of these changes what ships, so it carries a fragment.
SHIPPED = ("src/", "data/", "assets/")
# semver.org's own grammar, minus build metadata: the +<commit> part is never committed,
# only written into an export's stage copy.
_NUM = r"(?:0|[1-9]\d*)"
_PRE = r"(?:0|[1-9]\d*|\d*[A-Za-z-][0-9A-Za-z-]*)"
SEMVER = re.compile(r"^%s\.%s\.%s(?:-%s(?:\.%s)*)?$" % (_NUM, _NUM, _NUM, _PRE, _PRE))
HEADING = re.compile(r"^## \[([^\]]+)\](?: - (\S+))?")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def is_semver(text: str) -> bool:
    return bool(SEMVER.match(text))


def parse_fragment(text: str):
    """[(group, line)] for the lines a player reads, and the errors. None lines count, print nothing."""
    out, errs, seen = [], [], 0
    for n, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        seen += 1
        group, sep, body = line.partition(":")
        group, body = group.strip().capitalize(), body.strip()
        if not sep or " " in group:
            errs.append("line %d has no 'Group: ' prefix: %s" % (n, line))
        elif group != "None" and group not in GROUPS:
            errs.append("line %d: '%s' is not one of %s or None" % (n, group, ", ".join(GROUPS)))
        elif not body:
            errs.append("line %d: '%s:' with nothing after it" % (n, group))
        elif group != "None":
            out.append((group, body))
    if not seen:
        errs.append("the fragment is empty")
    return out, errs


def released(changelog: str):
    """[(version, date)] of the released headings, newest first, as written."""
    out = []
    for line in changelog.splitlines():
        m = HEADING.match(line)
        if m and m.group(1) != "Unreleased":
            out.append((m.group(1), m.group(2) or ""))
    return out


def needs_fragment(changed, added) -> bool:
    """A PR that changes what ships adds a fragment (the README is not one)."""
    ships = any(p.startswith(SHIPPED) for p in changed)
    has = any(p.startswith(FRAGMENTS + "/") and p.endswith(".md") and Path(p).name != README for p in added)
    return ships and not has


def _fragments(root: Path):
    d = root / FRAGMENTS
    return sorted(p for p in d.glob("*.md") if p.name != README) if d.is_dir() else []


def _version(root: Path) -> str:
    return str(json.loads((root / "version.json").read_text(encoding="utf-8")).get("version", ""))


def check(root: Path):
    errs = []
    for p in _fragments(root):
        for e in parse_fragment(p.read_text(encoding="utf-8"))[1]:
            errs.append("%s/%s: %s" % (FRAGMENTS, p.name, e))
    try:
        version = _version(root)
    except (OSError, ValueError) as e:
        return errs + ["version.json: %s" % e]
    if not is_semver(version):
        errs.append("version.json: '%s' is not SemVer (no leading v, no +build part)" % version)
    if not (root / "CHANGELOG.md").is_file():
        return errs + ["CHANGELOG.md is missing"]
    heads = released((root / "CHANGELOG.md").read_text(encoding="utf-8"))
    if not heads or heads[0][0] != version:
        errs.append("version.json says %s but the newest released heading in CHANGELOG.md is %s"
                    % (version, heads[0][0] if heads else "none"))
    for v, date in heads:
        if not is_semver(v) or not DATE.match(date):
            errs.append("CHANGELOG.md: heading [%s] needs a SemVer version and an ISO date" % v)
    return errs


def _assemble(root: Path):
    """{group: [lines]} from every fragment, in file-name order, duplicates once."""
    by = {g: [] for g in GROUPS}
    for p in _fragments(root):
        for group, line in parse_fragment(p.read_text(encoding="utf-8"))[0]:
            if line not in by[group]:
                by[group].append(line)
    return by


def _body(by) -> str:
    return "".join("### %s\n\n%s\n" % (g, "".join("- %s\n" % l for l in by[g])) for g in GROUPS if by[g])


def cut(root: Path, version: str, date: str, label: str):
    """Fragments into a dated section under [Unreleased]; [] on success, else why not."""
    if not is_semver(version):
        return ["'%s' is not SemVer" % version]
    if not DATE.match(date):
        return ["'%s' is not an ISO date (YYYY-MM-DD)" % date]
    path = root / "CHANGELOG.md"
    text = path.read_text(encoding="utf-8")
    if version in [v for v, _ in released(text)]:
        return ["%s is already released in CHANGELOG.md" % version]
    errs = check(root)
    if errs:
        return ["fix --check first: " + e for e in errs]
    by = _assemble(root)
    if not any(by.values()):
        return ["no fragment has a line a player reads: nothing to cut"]
    lines = text.splitlines(keepends=True)
    at = next((i for i, l in enumerate(lines) if HEADING.match(l) and not l.startswith("## [Unreleased]")), len(lines))
    head = "## [%s] - %s%s\n\n" % (version, date, " (%s)" % label if label else "")
    path.write_text("".join(lines[:at]) + head + _body(by) + "".join(lines[at:]), encoding="utf-8", newline="\n")
    for p in _fragments(root):
        p.unlink()
    (root / "version.json").write_text(json.dumps({"version": version}) + "\n", encoding="utf-8", newline="\n")
    return []


def notes(root: Path, version):
    """A released version's section as written; None: the fragments as the next cut would print them."""
    if version is None:
        return "## [Unreleased]\n\n" + _body(_assemble(root))
    out, inside = [], False
    for line in (root / "CHANGELOG.md").read_text(encoding="utf-8").splitlines(keepends=True):
        m = HEADING.match(line)
        if m:
            inside = m.group(1) == version
        if inside:
            out.append(line)
    return "".join(out).rstrip("\n") + "\n" if out else ""


def _git(*args) -> list:
    out = subprocess.run(["git", *args], cwd=REPO, capture_output=True, text=True, check=True).stdout
    return [p for p in out.split("\0") if p]


SEED = """# Changelog

Intro.

## [Unreleased]

The lines waiting for the next cut are the files in changelog.d/.

## [0.5.3-gate.2] - 2026-11-10 (V5.3 a + b)

### Fixed

- Old fix.

## [0.5.2] - 2026-10-30 (V5.2)

### Added

- Old feature.
"""


def selftest() -> int:
    fails = []

    def want(cond, what):
        if not cond:
            fails.append(what)

    # SemVer, the spec's own grammar.
    for good in ("0.5.3", "0.5.3-gate.2", "1.0.0-rc.1", "10.20.30"):
        want(is_semver(good), "semver accepts " + good)
    for bad in ("v0.5.3", "0.5", "05.3.1", "0.5.3+abc", "0.5.3-", "0.5.3-gate.02", "V5.3"):
        want(not is_semver(bad), "semver refuses " + bad)

    # A fragment: "Group: text" lines; anything else is an error naming the line.
    lines, errs = parse_fragment("Fixed: A.\n\nadded: B.\nNone: refactor\n")
    want(lines == [("Fixed", "A."), ("Added", "B.")] and not errs, "fragment parses, None dropped: %r %r" % (lines, errs))
    _, errs = parse_fragment("Fixed A.\n")
    want(len(errs) == 1 and "line 1" in errs[0], "a line with no group fails: %r" % errs)
    _, errs = parse_fragment("Improved: A.\n")
    want(len(errs) == 1 and "Improved" in errs[0], "an unknown group fails: %r" % errs)
    _, errs = parse_fragment("Fixed:\n")
    want(len(errs) == 1, "an empty line after the group fails: %r" % errs)
    _, errs = parse_fragment("\n")
    want(len(errs) == 1 and "empty" in errs[0], "an empty fragment fails: %r" % errs)

    # Released headings, newest first.
    heads = released(SEED)
    want([h[0] for h in heads] == ["0.5.3-gate.2", "0.5.2"], "released headings: %r" % heads)

    # Does this PR need a fragment?
    want(needs_fragment(["src/ui/menu.gd"], []), "src change, no fragment: needed")
    want(not needs_fragment(["src/ui/menu.gd"], ["changelog.d/x.md"]), "src change with a fragment: fine")
    want(not needs_fragment(["tools/x.py", "docs/a.md", "tests/t.gd"], []), "tools/docs/tests only: none needed")
    want(needs_fragment(["data/laws/x.json"], ["changelog.d/README.md"]), "the README is not a fragment")
    want(needs_fragment(["assets/icons/a.svg"], []), "assets change: needed")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "changelog.d").mkdir()
        (root / "changelog.d" / "README.md").write_text("how to\n", encoding="utf-8")
        (root / "CHANGELOG.md").write_text(SEED, encoding="utf-8")
        (root / "version.json").write_text('{"version": "0.5.3-gate.2"}\n', encoding="utf-8")
        want(check(root) == [], "a consistent tree passes: %r" % check(root))

        (root / "version.json").write_text('{"version": "0.5.3-gate.3"}\n', encoding="utf-8")
        want(any("0.5.3-gate.3" in e for e in check(root)), "version.json ahead of the changelog fails")
        (root / "version.json").write_text('{"version": "v0.5.3"}\n', encoding="utf-8")
        want(any("SemVer" in e for e in check(root)), "a non-SemVer version.json fails")
        (root / "version.json").write_text('{"version": "0.5.3-gate.2"}\n', encoding="utf-8")

        (root / "changelog.d" / "bad.md").write_text("Fixd: typo\n", encoding="utf-8")
        want(any("bad.md" in e for e in check(root)), "a bad fragment fails --check")
        (root / "changelog.d" / "bad.md").unlink()

        (root / "changelog.d" / "a.md").write_text("Fixed: Second fix.\nAdded: New thing.\n", encoding="utf-8")
        (root / "changelog.d" / "b.md").write_text("Fixed: First fix.\nNone: refactor\n", encoding="utf-8")
        (root / "changelog.d" / "c.md").write_text("None: tests only\n", encoding="utf-8")
        unrel = notes(root, None)
        want("### Added\n\n- New thing." in unrel and "- First fix." in unrel, "notes with no version: the fragments: %r" % unrel)

        want(cut(root, "0.5.3-gate.2", "2026-11-14", "") != [], "cutting an existing version fails")
        want(cut(root, "0.5.3+abc", "2026-11-14", "") != [], "cutting a non-SemVer version fails")
        want(cut(root, "0.5.3-gate.3", "14/11/2026", "") != [], "a non-ISO date fails")
        errs = cut(root, "0.5.3-gate.3", "2026-11-14", "V5.3 fix pass")
        want(errs == [], "a cut succeeds: %r" % errs)
        text = (root / "CHANGELOG.md").read_text(encoding="utf-8")
        want("## [0.5.3-gate.3] - 2026-11-14 (V5.3 fix pass)\n\n### Added\n\n- New thing.\n\n### Fixed\n\n- Second fix.\n- First fix.\n\n## [0.5.3-gate.2]"
             in text,"the cut section, groups in order, lines by fragment name: %r" % text)
        want(text.index("## [Unreleased]") < text.index("## [0.5.3-gate.3]") < text.index("## [0.5.3-gate.2]"),
             "the cut section sits under [Unreleased], above the last release")
        want(sorted(p.name for p in (root / "changelog.d").iterdir()) == ["README.md"], "the fragments are gone, the README stays")
        want(json.loads((root / "version.json").read_text(encoding="utf-8"))["version"] == "0.5.3-gate.3", "version.json is set")
        want(check(root) == [], "the tree after a cut passes --check: %r" % check(root))
        want(notes(root, "0.5.3-gate.3").startswith("## [0.5.3-gate.3]") and "Old fix" not in notes(root, "0.5.3-gate.3"),
             "notes VERSION prints that section only")
        want(cut(root, "0.5.3-gate.4", "2026-11-15", "") != [], "a cut with no fragment lines fails")
        (root / "CHANGELOG.md").unlink()
        want(any("CHANGELOG.md" in e for e in check(root)), "a missing CHANGELOG.md is reported, not a crash")

    for f in fails:
        print("SELFTEST FAIL:", f)
    if fails:
        return 1
    print("changelog selftest: all checks passed")
    return 0


def main() -> int:
    args = sys.argv[1:]
    if args[:1] == ["--selftest"]:
        return selftest()
    if args[:1] == ["--check"]:
        errs = check(REPO)
        for e in errs:
            print("CHANGELOG:", e)
        print("%d problem(s)" % len(errs) if errs else "changelog and version.json consistent (%s)" % _version(REPO))
        return 1 if errs else 0
    if args[:1] == ["--check-pr"] and len(args) == 2:
        # Two-dot against BASE: in CI the pull request's merge commit has the base as its
        # first parent, so BASE is HEAD^1 and a fetch depth of 2 is enough.
        try:
            changed = _git("diff", "-z", "--name-only", args[1], "HEAD")
            added = _git("diff", "-z", "--name-only", "--diff-filter=A", args[1], "HEAD", "--", FRAGMENTS)
        except subprocess.CalledProcessError:
            print("cannot diff against '%s': not in this clone (CI needs fetch-depth: 2)" % args[1])
            return 1
        if needs_fragment(changed, added):
            print("this pull request changes src/, data/ or assets/ and adds no %s/<branch>.md:" % FRAGMENTS)
            print("add one line per change a player notices ('Fixed: ...'), or 'None: <why>'.")
            return 1
        print("changelog fragment: ok")
        return 0
    if args[:1] == ["cut"] and len(args) >= 2:
        ap = argparse.ArgumentParser(prog="changelog.py cut")
        ap.add_argument("version")
        ap.add_argument("--label", default="", help="the tier name for the heading, e.g. 'V5.3 a + b'")
        ap.add_argument("--date", default=datetime.date.today().isoformat())
        a = ap.parse_args(args[1:])
        errs = cut(REPO, a.version, a.date, a.label)
        for e in errs:
            print("cut refused:", e)
        if not errs:
            print("cut %s: CHANGELOG.md section written, fragments removed, version.json set" % a.version)
        return 1 if errs else 0
    if args[:1] == ["notes"] and len(args) <= 2:
        text = notes(REPO, args[1] if len(args) == 2 else None)
        if not text:
            print("no section [%s] in CHANGELOG.md" % args[1])
            return 1
        sys.stdout.write(text)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
