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
const GameState = preload("res://src/core/game_state.gd")


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func _path_for(slot: String) -> String:
	return SAVE_DIR + slot + ".json"


## Writes `slot`.json under user://saves/. Returns "" on success, an error
## message otherwise.
static func save_game(state, clock, slot: String) -> String:
	if slot.is_empty():
		return "save slot name cannot be empty"

	_ensure_dir()
	var payload := {
		"save_version": state.save_version,
		"day": clock.day,
		"game_state": state.to_dict(),
	}

	var file := FileAccess.open(_path_for(slot), FileAccess.WRITE)
	if file == null:
		return "could not open '%s' for writing (%s)" % [_path_for(slot), error_string(FileAccess.get_open_error())]

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return ""


## Result shape: {"ok": bool, "state": GameState, "day": int, "error": String}.
## On any failure "ok" is false and "error" names why -- an unreadable file, a
## corrupt one, or a save_version this build does not know how to read. No
## partial GameState is ever handed back.
static func load_game(slot: String) -> Dictionary:
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
