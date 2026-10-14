---
title: Vault
tags:
  - tooling
  - setup
---

# The vault

The repository root is the Obsidian vault (`.obsidian/` is committed, plugin
bundles whole, so a fresh clone opens working — `.gitignore` states the
exception). This page says what each piece is for, so a plugin is either
used or removed, never just carried. Start at [[index]].

## Excluded folders

Settings → Files and links → Excluded files lists `reports/ sources/ addons/
assets/ src/ tests/ data/ tools/`. Before the exclusion Obsidian indexed
45 212 files, 106 of them in `docs/`; search, the graph and the quick switcher
were mostly game assets and probe output. Excluded files still show in the
file explorer; they leave search, the graph and link suggestions. A link into
`reports/` therefore reads as unresolved — which is honest, because
`reports/` is gitignored and does not exist on a fresh clone. Cite a report
as a path in backticks instead.

## Plugins and what each is for

| Plugin | Use here |
|---|---|
| Dataview | The live views on [[vault-dashboard]] (docs without a title, docs nothing links to, models by last edit). The Local REST API's `/search/` endpoint accepts the same DQL, so an agent can query the vault instead of reading every file. |
| Tasks | The **Open author calls** checklist in [[someday]]: one `- [ ]` per decision only the author can take, gathered on the dashboard. Tick it with the date when decided. The [[templates/author-call\|author-call template]] writes a well-formed line. |
| Templater | `docs/templates/` (set as the Templater folder; it never runs on file creation). [[templates/model-doc\|model-doc]] writes the frontmatter and the section skeleton a model doc needs — eight docs had shipped without frontmatter. |
| Excalidraw | Diagrams that are clearer drawn than written: [[architecture.excalidraw\|architecture]] draws AGENTS.md's three rules. Embed one with `![[architecture.excalidraw]]`. |
| Git (obsidian-git) | **Read-only use**: the Source Control view (what changed in the working copy), and file history and diff for a doc. Push is disabled and every automatic action is off. Do not commit from it: its "stage all" stages `project.godot` and `addons/`, which the CLI hook guards and the plugin does not. |
| Table editor | Editing the many wide tables in the model docs (Tab and Enter move between cells). |
| Local REST API | The bridge agents use: HTTP on `127.0.0.1:27123` and a native MCP endpoint at `/mcp/`, both behind the API key in the plugin's `data.json` (gitignored, per machine). Never paste that key anywhere. |

## Checks

`python tools/check_vault.py` reports unresolved wikilinks, docs the
[[index]] does not reach, orphans and missing frontmatter, from the tracked
files alone (what a fresh clone sees).
