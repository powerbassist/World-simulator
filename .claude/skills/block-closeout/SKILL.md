---
name: block-closeout
description: Run the Nation Simulator gates in order before a block is committed or merged, and report each as pass or fail. User-invoked at a session boundary.
disable-model-invocation: true
---

# Block closeout

Run from the repo root, one gate at a time, and report each as PASS or FAIL with
the one decisive line. Do not fix a failing gate silently: name it, then ask.
Every gate below is already named in AGENTS.md; this skill only fixes their order.

**One Godot at a time.** Gate 3 starts Godot. If the editor, the MCP bridge or
another run holds this checkout, stop and say so instead of running it.

## 1. Tree state

```bash
git status --short
```

- `M project.godot` must be present and must stay **unstaged**. It is the editor's,
  never yours (AGENTS.md "Gotchas").
- **A clean `git status` is itself the alarm.** The per-machine lines have been
  committed into HEAD before. Check the committed file directly, whatever the
  status says: `git show HEAD:project.godot | grep -n MCPRuntimeServer` must print
  nothing (the committed `[autoload]` names only DialogueManager).
- Stage by explicit path only. Never `git add -A`, `.`, `-u` or `commit -a`.

## 2. Every new script has its `.uid`

A new `.gd` gets no `.uid` until something imports it. List the new scripts, run
the import once, then confirm each has a sibling:

```bash
git fetch -q origin
{ git status --short -uall | cut -c4-; git diff --name-only --diff-filter=A origin/main...HEAD; } | grep '\.gd$' | sort -u
godot --path . --headless --import
```

(`-uall` lists files inside a new directory; the second command catches scripts
already committed on this branch. It diffs against `origin/main`, not local
`main`, which can be far behind and would list scripts this branch never added.)
The opposite direction, a `.uid` left behind by a deleted script, is gate 4's
`check_uids.py`.

For each new `path/x.gd`, `path/x.gd.uid` must exist. Report any that do not.
Do not run the import while another Godot holds the checkout.

## 3. The suite

```bash
python tools/suite_runner.py --ci
```

Never hand-roll a godot invocation. The no-argument run also checks that every
`tests/test_*.gd` is registered in `tools/run_tests.sh`. For a small block, name
the test files instead: `python tools/suite_runner.py --ci tests/test_x.gd`, say
that the full suite was not run, and check by eye that each new test file has its
row in `tools/run_tests.sh`'s `tests=()`.

## 4. The cheap gates

Run all five; report each separately.

```bash
bash tools/check_names.sh
python tools/check_size.py
python tools/check_vault.py
python tools/check_uids.py
reuse lint
```

`bash tools/check_mcp.sh` is AGENTS.md's sixth. It needs the editor and the
per-machine bridge, so CI never runs it: run it when the block touched the MCP
setup or `.mcp.json`, and otherwise list it under "not run".

- `check_size.py`: a file that shrank lowers its row in `tools/size_baseline.json`
  (`--update`) in the same change.
- `check_vault.py`: exit 1 means an unresolved wikilink. Orphans and unindexed
  docs are reported, not failed; say which are new.
- `check_uids.py`: exit 1 means a tracked `X.uid` whose `X` is not tracked.
- `reuse lint`: a new asset, data source or third-party file needs an annotation
  in `REUSE.toml`.

## 4b. A change to what the game delivers

**Green is not measured** (AGENTS.md, "Review loops"). If the block touched
`src/sim/`, `src/core/` or `data/`, a green suite is not enough: run the game's
own tick order and report numbers. It saturates the CPU, so nothing timed runs
beside it.

```bash
python tools/balance_parallel.py --json=PATH
python tools/balance_diff.py base.json tip.json
```

Capture `base.json` from the base commit in a detached clean worktree, before the
first edit, never under a running probe. When the block claims byte-identity,
`cmp base.json tip.json` instead of reading the diff. If the block did not touch
those folders, say so.

## 5. A UI change

A UI session is not finished until `tools/screenshot.gd` has run **windowed**
(`--headless` draws nothing). If this block touched `src/ui/`, say whether it did.

## 6. Scratch

List, do not delete without a look: `tmp_*.gd` in the repo root (a stray
`class_name` duplicate fails the whole suite), one-off helper scripts, and this
block's `.superpowers/sdd/` task, review and report files. Keep handoffs and
`frames/`. Delete only files this session created.

## Report

One line per gate, then the list of anything not run and why.
