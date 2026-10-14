"""Vault hygiene check over the TRACKED docs -- what a fresh clone's vault sees.

Reports unresolved wikilinks, docs/ files the index does not reach, docs nothing
links to, and docs/ files without frontmatter. Exit 1 when a wikilink is
unresolved; the other three are reported, not failed, because each can be a
deliberate call (a plan kept out of the index, say).

Obsidian resolves a bare [[name]] by basename anywhere in the vault, so this
does too; reading the tracked files rather than the disk is the point --
gitignored reports/ would otherwise resolve links a fresh clone cannot.

    python tools/check_vault.py
"""
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict

WIKI = re.compile(r"!?\[\[([^\]\|#\^]*)(?:[#\^][^\]\|]*)?(?:\|[^\]]*)?\]\]")
MDLINK = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
FENCE = re.compile(r"```.*?```", re.S)
INLINE = re.compile(r"`[^`\n]*`")
# Not docs in the index's sense: templates are scaffolding, superpowers/ holds
# build plans (all but one gitignored as scratch).
NOT_INDEXED = ("docs/templates/", "docs/superpowers/")


def git_files(root):
    out = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True, check=True)
    return [p for p in out.stdout.splitlines() if p]


def main():
    root = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True,
                          text=True, check=True).stdout.strip()
    files = git_files(root)
    paths = set(files)
    by_base = defaultdict(list)
    for p in files:
        base = os.path.basename(p).lower()
        by_base[base].append(p)
        if base.endswith(".md"):
            by_base[base[:-3]].append(p)

    def resolve(target, src):
        # "\|" is how a wikilink with an alias is written inside a table cell.
        t = target.strip().rstrip("\\").replace("\\", "/")
        if not t:
            return src
        for cand in (t, t + ".md"):
            if cand in paths:
                return cand
            rel = os.path.normpath(os.path.join(os.path.dirname(src), cand)).replace("\\", "/")
            if rel in paths:
                return rel
        hits = by_base.get(os.path.basename(t).lower()) or by_base.get(os.path.basename(t).lower() + ".md")
        return hits[0] if hits else None

    md = [p for p in files if p.endswith(".md")]
    docs = [p for p in md if p.startswith("docs/")]
    unresolved = defaultdict(set)
    inbound = Counter()
    for p in md:
        raw = open(os.path.join(root, p), encoding="utf-8", errors="replace").read()
        body = INLINE.sub("", FENCE.sub("", raw))
        for m in WIKI.finditer(body):
            rp = resolve(m.group(1), p)
            if rp is None:
                unresolved[m.group(1)].add(p)
            elif rp != p:
                inbound[rp] += 1
        for m in MDLINK.finditer(body):
            u = m.group(1).split("#")[0]
            if u and "://" not in u and not u.startswith("mailto:"):
                rel = os.path.normpath(os.path.join(os.path.dirname(p), u)).replace("\\", "/")
                if rel in paths:
                    inbound[rel] += 1

    index = open(os.path.join(root, "docs/index.md"), encoding="utf-8").read()
    linked = {resolve(m.group(1), "docs/index.md") for m in WIKI.finditer(index)}
    for m in MDLINK.finditer(index):
        linked.add(os.path.normpath(os.path.join("docs", m.group(1).split("#")[0])).replace("\\", "/"))

    def indexable(p):
        return p != "docs/index.md" and not p.startswith(NOT_INDEXED)

    not_in_index = sorted(p for p in docs if indexable(p) and p not in linked)
    orphans = sorted(p for p in docs if indexable(p) and inbound[p] == 0)
    no_fm = sorted(p for p in docs if not p.startswith(NOT_INDEXED) and not p.endswith(".excalidraw.md")
                   and not open(os.path.join(root, p), encoding="utf-8").read(3) == "---")

    print(f"tracked .md: {len(md)} (docs/: {len(docs)})")
    print(f"unresolved wikilinks: {len(unresolved)}")
    for t, srcs in sorted(unresolved.items()):
        print(f"  [[{t}]] in {', '.join(sorted(srcs))}")
    for label, items in (("not reached from docs/index.md", not_in_index),
                         ("linked from nowhere", orphans), ("no frontmatter", no_fm)):
        print(f"{label}: {len(items)}")
        for p in items:
            print(f"  {p}")
    return 1 if unresolved else 0


if __name__ == "__main__":
    sys.exit(main())
