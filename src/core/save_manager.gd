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
const Projects = preload("res://src/sim/projects.gd")
const Orgs = preload("res://src/sim/orgs.gd")


static func _ensure_dir() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


static func _path_for(slot: String) -> String:
	return SAVE_DIR + slot + ".json"


## A slot name becomes a filename inside user://saves/, and the name field is
## free text -- so the boundary is HERE, at the source, rather than at each
## caller. Separators and traversal components would leave the saves
## directory, and delete_slot() makes that destructive: the review's
## path-traversal finding, refused once for every path.
static func valid_slot_name(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 64:
		return false
	if slot != slot.strip_edges():
		return false
	if "/" in slot or "\\" in slot or ":" in slot or ".." in slot:
		return false
	# Windows device names: save_game would fail on them with an engine-level
	# "Invalid parameter" the player cannot read -- refused here with the rest.
	var lower := slot.to_lower()
	for reserved in ["con", "prn", "aux", "nul"]:
		if lower == reserved:
			return false
	for i in range(1, 10):
		if lower == "com%d" % i or lower == "lpt%d" % i:
			return false
	return true


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
	# The boundary, as save_load_panel's comment claims: no path reaches a
	# user:// file with a name that could leave the saves directory -- the
	# panel refuses at the field, and this is the refusal every OTHER caller
	# (a future quicksave hotkey, a new menu route) passes through.
	if not valid_slot_name(slot):
		return "'%s' is not a valid save name -- one line of text, no slashes" % slot

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

	# full_precision: grisu2's shortest digits, which name each double exactly.
	# The default writes ~15 significant digits, which lost bits in most floats
	# and moved a small value by 5.8% (the save-precision plan's step 0). The
	# load still is not bit-exact everywhere -- JSON.parse_string reads numbers
	# through Godot's built_in_strtod, which is not correctly rounded -- but
	# that is the parser's residue, a few ULP, and no setting here removes it.
	# The format is the same JSON numbers, so no SAVE_VERSION bump: an older
	# save reads exactly as it did. sort_keys stays at its default, true.
	file.store_string(JSON.stringify(payload, "\t", true, true))
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
		# V2.7: the sited-project payoffs are derived, not serialised, so the load
		# path rebuilds them from the loaded registers and the geometry -- the same
		# derivation Projects.tick_month() runs, and it cannot disagree with it
		# because it IS it.
		state.project_sited_pct = Projects.sited_map(state, loader)
		# V3.2: the org register's standing prices are a snapshot of STATIC
		# content, re-derived here for the same reason -- membership and the
		# council registers travel in the save; the bonuses do not.
		Orgs.rebuild_static(state, loader)
		# The fight machine's save-safety net: referendum-phase fights whose
		# vote resolved before the save (the result is a display record and
		# does not travel) end honestly with membership unchanged.
		Orgs.reconcile_on_load(state, loader)
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


## A slot file's modified time in Unix seconds, for the save/load UI's stamp.
## 0 (the error value) if the file is gone between the listing and this read.
static func slot_mtime(slot: String) -> int:
	return FileAccess.get_modified_time(_path_for(slot))


## Removes a save file. Refuses a name that has no file, so a stale row's
## second click after another path deleted it reports rather than "succeeds".
## Refuses an invalid name for the same reason valid_slot_name exists: this
## is the destructive one, so it never trusts its input.
static func delete_slot(slot: String) -> bool:
	if not valid_slot_name(slot):
		return false
	var path := _path_for(slot)
	if not FileAccess.file_exists(path):
		return false
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	return dir.remove(slot + ".json") == OK
