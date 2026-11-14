extends RefCounted

## THE BUILD VERSION A PLAYER READS (AGENTS.md, "Versions and changelog").
##
## res://version.json holds the last version cut ({"version": "0.5.3-gate.2"}). An
## export's STAGE copy also holds "build", written by tools/export_windows.py: the bare
## version when the exported commit carries the tag v<version> (a kit the author plays),
## "dev build <sha> (after <version>)" for any other export. The game prints "build"
## verbatim and never decides that itself, so the menu, the dev console and the kit's
## RELEASE.md cannot disagree. With no stamp (the editor, the suite) it reads
## "<version>+dev": a working copy is never a released version.
##
## Not SAVE_VERSION: that integer says which saves this build reads, and moves on its
## own rule (AGENTS.md, "Save format").
##
## Read as text through FileAccess, never load(): a cold headless clone has no import.

const PATH := "res://version.json"


static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	return parsed if parsed is Dictionary else {}


static func from_dict(d: Dictionary) -> String:
	var build := String(d.get("build", ""))
	if not build.is_empty():
		return build
	var version := String(d.get("version", ""))
	return version + "+dev" if not version.is_empty() else "?"


static func text() -> String:
	return from_dict(read())
