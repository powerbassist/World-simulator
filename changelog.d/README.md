# changelog.d

One file per pull request that changes `src/`, `data/` or `assets/`, named after its
branch (`interface/v5.3-folder` becomes `interface-v5.3-folder.md`). One line per change
a player notices, in the player's words, starting with its group:

```
Added: A corner of the main menu shows which build you are playing.
Fixed: An answer given in the folder clears its line on the month page.
Changed: Saves from earlier builds no longer load.
None: the loader split, nothing a player sees.
```

Groups: Added, Changed, Deprecated, Removed, Fixed, Security, and None (nothing a player
sees; it prints nowhere). No file or field names, no real person's or firm's name.

These files are the unreleased part of `CHANGELOG.md`. A cut
(`python tools/changelog.py cut <version> --label "<tier>"`) moves them into a dated
section and deletes them; nothing else edits `CHANGELOG.md` or `version.json`. The rule
and why: AGENTS.md, "Versions and changelog".
