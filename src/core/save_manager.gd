class_name SaveManager
extends RefCounted

## Save/load for a game in progress. See docs/data-architecture.md Persistence
## and ROADMAP.md S9.
##
## The save file is GameState.to_dict() plus one sibling field, "day". The
## Clock owns year/month/day during play, but GameState only mirrors
## year/month (on each monthly tick, for history stamps) -- it has no day
## field, and inventing one on NationState/GameState just to carry a pacing
## detail would put a UI-only concern in the middle of the simulation state
## the whole rest of this file works hard to keep clean. The day the game was
## saved on is not simulation state -- nothing in src/sim/ reads it -- so it
## lives at the save file's top level, read back into the Clock directly.
## Restoring it makes a reload pick up daily pacing exactly where it left off,
## rather than resetting to day 1 (a two-day-late tick, not a wrong number).

const SAVE_DIR := "user://saves/"
## Appended after ".json", not before it, so list_slots()'s ".json" suffix test
## skips a stranded temp file rather than offering it as a loadable slot.
const TEMP_SUFFIX := ".tmp"
const GameState = preload("res://src/core/game_state.gd")


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func _path_for(slot: String) -> String:
	return SAVE_DIR + slot + ".json"


## Writes `slot`.json under user://saves/. Returns "" on success, an error
## message otherwise.
##
## Written to a sibling .tmp first and renamed into place, so a crash or a full
## disk mid-write loses the new save rather than the old one. Writing straight
## to the destination truncates it on open -- an interrupted save would leave a
## half-written file where a working game used to be, which is the one failure
## this project is least willing to ship. The rename is atomic on POSIX; on
## Windows it is replace-then-rename, so the guarantee there is "the live file
## is never the one being written to", not true atomicity.
static func save_game(state, clock, slot: String) -> String:
	if slot.is_empty():
		return "save slot name cannot be empty"

	_ensure_dir()
	var payload := {
		"save_version": state.save_version,
		"day": clock.day,
		"game_state": state.to_dict(),
	}

	var temp_path := _path_for(slot) + TEMP_SUFFIX
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return "could not open '%s' for writing (%s)" % [temp_path, error_string(FileAccess.get_open_error())]

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		DirAccess.remove_absolute(temp_path)
		return "could not open '%s' (%s)" % [SAVE_DIR, error_string(DirAccess.get_open_error())]

	var err := dir.rename(slot + ".json" + TEMP_SUFFIX, slot + ".json")
	if err != OK:
		DirAccess.remove_absolute(temp_path)
		return "could not replace '%s' (%s)" % [_path_for(slot), error_string(err)]
	return ""


## Result shape: {"ok": bool, "state": GameState, "day": int, "error": String}.
## On any failure "ok" is false and "error" names why -- an unreadable file, a
## corrupt one, or a save_version this build does not know how to read. No
## partial GameState is ever handed back.
##
## `loader` is optional and defaults to null so the call sites can be migrated
## one at a time -- but a state loaded WITHOUT it has an empty region register, and
## Regions.tick_month() then falls back to the pre-V2.5 expression. That is a silently
## different model, so the parameter is passed everywhere in practice and
## tests/test_regions.gd asserts a round trip keeps the register.
static func load_game(slot: String, loader = null) -> Dictionary:
	var path := _path_for(slot)
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "no save named '%s'" % slot}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "error": "could not open '%s' (%s)" % [path, error_string(FileAccess.get_open_error())]}
	var text := file.get_as_text()
	file.close()

	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return {"ok": false, "error": "'%s' is not a valid save file (not a JSON object)" % slot}

	var save_version = parsed.get("save_version")
	if typeof(save_version) != TYPE_FLOAT and typeof(save_version) != TYPE_INT:
		return {"ok": false, "error": "save '%s' has no readable save_version" % slot}
	if int(save_version) != GameState.SAVE_VERSION:
		return {
			"ok": false,
			"error": "save '%s' has save_version %s, this build reads only %d -- refusing to load it" % [
				slot, str(save_version), GameState.SAVE_VERSION
			],
		}

	if not (parsed.get("game_state") is Dictionary):
		return {"ok": false, "error": "'%s' is missing its game_state block" % slot}

	var state = GameState.from_dict(parsed["game_state"])
	if loader != null:
		# The region register is CONTENT on the loader and is not serialised, so the
		# load path re-attaches it -- NationState.eu_member's shape, one level up.
		state.regions = loader.regions
		# V2.7: the transport graph, same shape, same reason.
		state.region_graph = loader.region_graph
	return {"ok": true, "state": state, "day": int(parsed.get("day", 1)), "error": ""}


## Slot names under user://saves/, newest first, for a save/load UI to list.
static func list_slots() -> Array[String]:
	_ensure_dir()
	var names: Array[String] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return names

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			names.append(entry.trim_suffix(".json"))
		entry = dir.get_next()
	dir.list_dir_end()

	names.sort_custom(func(a, b): return FileAccess.get_modified_time(_path_for(a)) > FileAccess.get_modified_time(_path_for(b)))
	return names
