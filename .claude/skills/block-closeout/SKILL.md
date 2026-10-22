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
  committed into HEAD before. If `project.godot` is not modified, run
  `git diff HEAD~5 -- project.godot` and look for `MCPRuntimeServer` in `[autoload]`.
- Stage by explicit path only. Never `git add -A`, `.`, `-u` or `commit -a`.

## 2. Every new script has its `.uid`

A new `.gd` gets no `.uid` until something imports it. List the new scripts, run
the import once, then confirm each has a sibling:

```bash
git status --short | grep -E '^(\?\?|A)' | grep '\.gd$'
godot --path . --headless --import
```

For each new `path/x.gd`, `path/x.gd.uid` must exist. Report any that do not.
Do not run the import while another Godot holds the checkout.

## 3. The suite

```bash
python tools/suite_runner.py --ci
```

Never hand-roll a godot invocation. It also checks that every `tests/test_*.gd`
is registered in `tools/run_tests.sh`. For a small block, name the test files
instead: `python tools/suite_runner.py --ci tests/test_x.gd`, and say that the
full suite was not run.

## 4. The cheap gates

Run all four; report each separately.

```bash
bash tools/check_names.sh
python tools/check_size.py
python tools/check_vault.py
reuse lint
```

- `check_size.py`: a file that shrank lowers its row in `tools/size_baseline.json`
  (`--update`) in the same change.
- `check_vault.py`: exit 1 means an unresolved wikilink. Orphans and unindexed
  docs are reported, not failed; say which are new.
- `reuse lint`: a new asset, data source or third-party file needs an annotation
  in `REUSE.toml`.

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
