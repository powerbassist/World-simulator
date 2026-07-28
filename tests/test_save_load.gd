extends SceneTree

## Headless test: godot --headless --script res://tests/test_save_load.gd
## Non-zero exit on any failure.
##
## Two things S9's done-when list requires, checked directly:
##   1. Saving mid-term, quitting, and reloading produces byte-identical
##      simulation state -- built the same way test_state_copy.gd stresses
##      duplicate_state(): move every nation off its defaults, tick a few
##      months, then compare the reloaded object field-by-field, enumerated
##      off the object rather than listed, so it needs no edit when a session
##      adds a field.
##   2. Loading a save with an unknown save_version fails with a clear message
##      rather than corrupting anything -- checked against a hand-written
##      bogus save file, not a real one.
##
## Uses real filesystem I/O against user://saves/, per docs/data-architecture.md
## (user:// is the live-state location, res:// is read-only static content).
## The slot names here are test-only and removed again at the end.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Clock = preload("res://src/core/clock.gd")

const ROUNDTRIP_SLOT := "__test_save_load_roundtrip__"
const SECOND_NATION_SLOT := "__test_save_load_roundtrip_deu__"
const BOGUS_SLOT := "__test_save_load_bogus_version__"
const FLOAT_EPS := 1e-6

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return

	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
		_finish()
		return

	Budget.commit(state, {
		"tax_rates_pct": {"income": 27.0, "corporate": 31.0, "vat": 23.0},
		"spending_pct_gdp": {"health": 12.5, "education": 6.5, "defence": 3.0, "pensions": 13.0, "infrastructure": 5.0},
	})
	for _i in range(6):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 17

	_run_roundtrip(state, clock)
	_run_atomic_write(state, clock)
	_run_second_nation_roundtrip(loader)
	_run_unknown_version()
	_cleanup()
	clock.free()  # a Node created off-tree isn't owned by anything; free it explicitly
	_finish()


## V1.2a: SAVE_VERSION did not move (see the plan step's own cold count), but
## a save still has to round-trip for whichever nation is playing -- checked
## against Germany specifically, since a v4-era save format built against one
## nation could still quietly assume something about it that a second nation
## breaks. Lighter than _run_roundtrip(): the reflective field check is the
## point, not another pass over atomic writes or version rejection.
func _run_second_nation_roundtrip(loader) -> void:
	var state = GameState.new_game(loader, "DEU")
	if not state.errors.is_empty():
		_fail("new_game(DEU) reported %s" % [state.errors])
		return

	for _i in range(3):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)

	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 9

	var save_error := SaveManager.save_game(state, clock, SECOND_NATION_SLOT)
	clock.free()
	if not save_error.is_empty():
		_fail("save_game(DEU) failed: %s" % save_error)
		return

	var result := SaveManager.load_game(SECOND_NATION_SLOT)
	if not result["ok"]:
		_fail("load_game(DEU) failed on a save this test just wrote: %s" % result["error"])
		return

	var loaded = result["state"]
	if loaded.save_version != GameState.SAVE_VERSION:
		_fail("DEU save round-tripped at save_version %d, expected %d" % [loaded.save_version, GameState.SAVE_VERSION])
	if loaded.player_nation_id != "DEU":
		_fail("loaded DEU save has player_nation_id '%s'" % loaded.player_nation_id)
	_check_pair("GameState[DEU]", state, loaded)
	for id in state.nations.keys():
		if not loaded.nations.has(id):
			_fail("DEU save dropped nation %s" % id)
			continue
		_check_pair("NationState[DEU][%s]" % id, state.nations[id], loaded.nations[id])


func _run_roundtrip(state, clock) -> void:
	var save_error := SaveManager.save_game(state, clock, ROUNDTRIP_SLOT)
	if not save_error.is_empty():
		_fail("save_game failed: %s" % save_error)
		return

	var result := SaveManager.load_game(ROUNDTRIP_SLOT)
	if not result["ok"]:
		_fail("load_game failed on a save this test just wrote: %s" % result["error"])
		return

	if int(result["day"]) != 17:
		_fail("day round-tripped as %s, expected 17" % [result["day"]])

	var loaded = result["state"]
	_check_pair("GameState", state, loaded)

	if loaded.nations.size() != state.nations.size():
		_fail("nation count: original %d, loaded %d" % [state.nations.size(), loaded.nations.size()])
	for id in state.nations.keys():
		if not loaded.nations.has(id):
			_fail("loaded save dropped nation %s" % id)
			continue
		_check_pair("NationState[%s]" % id, state.nations[id], loaded.nations[id])

	if loaded.history.size() != state.history.size():
		_fail("history: original has %d entries, loaded has %d" % [state.history.size(), loaded.history.size()])


## The save is written to a sibling .tmp and renamed into place, so that an
## interrupted write loses the new save rather than the old one. Two observable
## consequences, both checked here, because the failure this guards against —
## a truncated save where a working game used to be — cannot be provoked
## directly without killing the process mid-write.
func _run_atomic_write(state, clock) -> void:
	var temp_path: String = SaveManager._path_for(ROUNDTRIP_SLOT) + SaveManager.TEMP_SUFFIX

	# 1. A completed save leaves no temp behind.
	if FileAccess.file_exists(temp_path):
		_fail("save_game left '%s' behind after a successful write" % temp_path)

	# 2. A temp stranded by an interrupted save is invisible to the slot list and
	#    harmless to the good save sitting next to it -- the point of putting the
	#    suffix after ".json" rather than before it.
	var stranded := FileAccess.open(temp_path, FileAccess.WRITE)
	stranded.store_string("{ truncated")
	stranded.close()

	if SaveManager.list_slots().has(ROUNDTRIP_SLOT + ".json" + SaveManager.TEMP_SUFFIX):
		_fail("list_slots() offered a stranded temp file as a loadable slot")
	if not SaveManager.load_game(ROUNDTRIP_SLOT)["ok"]:
		_fail("a stranded temp file broke loading the good save beside it")

	# 3. Saving again over the stranded temp succeeds rather than failing on it.
	var save_error := SaveManager.save_game(state, clock, ROUNDTRIP_SLOT)
	if not save_error.is_empty():
		_fail("save_game failed when a stranded temp file was present: %s" % save_error)
	if FileAccess.file_exists(temp_path):
		_fail("save_game left '%s' behind on the retry" % temp_path)


func _run_unknown_version() -> void:
	SaveManager._ensure_dir()
	var path: String = SaveManager._path_for(BOGUS_SLOT)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"save_version": 999, "day": 1, "game_state": {}}))
	file.close()

	var result := SaveManager.load_game(BOGUS_SLOT)
	if result["ok"]:
		_fail("load_game accepted an unknown save_version instead of failing loudly")
	elif result["error"].is_empty():
		_fail("load_game rejected an unknown save_version but gave no error message")

	# Version 1 specifically. V1.1a split the executive's term from the
	# assembly's and added the coalition fields, so a version-1 save has no
	# coherent reading — it must be refused outright rather than restored with
	# the government silently empty. Named as a case of its own because a
	# superseded version is the one an actual player will have on disk, unlike
	# 999 above.
	var v1 := FileAccess.open(path, FileAccess.WRITE)
	v1.store_string(JSON.stringify({"save_version": 1, "day": 1, "game_state": {}}))
	v1.close()

	var old := SaveManager.load_game(BOGUS_SLOT)
	if old["ok"]:
		_fail("load_game accepted a version-1 save; the government fields would be missing")
	elif old["error"].is_empty():
		_fail("load_game rejected a version-1 save but gave no error message")

	# Version 2 for the same reason one version on: V1.1b made party discipline
	# live state, so a version-2 save carries no party_discipline table and every
	# coalition bonus and censure vote read out of it would be scored against the
	# authored figure rather than the eroded one.
	var v2 := FileAccess.open(path, FileAccess.WRITE)
	v2.store_string(JSON.stringify({"save_version": 2, "day": 1, "game_state": {}}))
	v2.close()

	var pre_discipline := SaveManager.load_game(BOGUS_SLOT)
	if pre_discipline["ok"]:
		_fail("load_game accepted a version-2 save; the discipline table would be missing")
	elif pre_discipline["error"].is_empty():
		_fail("load_game rejected a version-2 save but gave no error message")

	# Version 3 for the same reason one version further on: V1.1c added
	# dissolution's six fields, so a version-3 save carries no dissolution_rule
	# and the player could never dissolve, or read a stale lockout, after a load.
	var v3 := FileAccess.open(path, FileAccess.WRITE)
	v3.store_string(JSON.stringify({"save_version": 3, "day": 1, "game_state": {}}))
	v3.close()

	var pre_dissolution := SaveManager.load_game(BOGUS_SLOT)
	if pre_dissolution["ok"]:
		_fail("load_game accepted a version-3 save; the dissolution fields would be missing")
	elif pre_dissolution["error"].is_empty():
		_fail("load_game rejected a version-3 save but gave no error message")

	# Version 4 for the same reason one version further on: V1.1d added
	# cabinet's six fields, so a version-4 save carries no cabinet table and
	# every portfolio would read vacant, silently, after a load.
	var v4 := FileAccess.open(path, FileAccess.WRITE)
	v4.store_string(JSON.stringify({"save_version": 4, "day": 1, "game_state": {}}))
	v4.close()

	var pre_cabinet := SaveManager.load_game(BOGUS_SLOT)
	if pre_cabinet["ok"]:
		_fail("load_game accepted a version-4 save; the cabinet fields would be missing")
	elif pre_cabinet["error"].is_empty():
		_fail("load_game rejected a version-4 save but gave no error message")

	# Version 5 for the same reason one version further on: V1.2b added
	# political-system fields (system_id, head-of-state, lose_condition,
	# term_limit), so a version-5 save carries no lose_condition and the run
	# could never end.
	var v5 := FileAccess.open(path, FileAccess.WRITE)
	v5.store_string(JSON.stringify({"save_version": 5, "day": 1, "game_state": {}}))
	v5.close()

	var pre_political_systems := SaveManager.load_game(BOGUS_SLOT)
	if pre_political_systems["ok"]:
		_fail("load_game accepted a version-5 save; the political-system fields would be missing")
	elif pre_political_systems["error"].is_empty():
		_fail("load_game rejected a version-5 save but gave no error message")

	# Version 6 for the same reason one version further on: V1.2c added
	# amendment_rule, mutable at runtime (an amendment may entrench its own
	# threshold), so a version-6 save carries no amendment_rule and no
	# amendment would ever be proposable after a load.
	var v6 := FileAccess.open(path, FileAccess.WRITE)
	v6.store_string(JSON.stringify({"save_version": 6, "day": 1, "game_state": {}}))
	v6.close()

	var pre_amendment := SaveManager.load_game(BOGUS_SLOT)
	if pre_amendment["ok"]:
		_fail("load_game accepted a version-6 save; amendment_rule would be missing")
	elif pre_amendment["error"].is_empty():
		_fail("load_game rejected a version-6 save but gave no error message")


func _cleanup() -> void:
	var dir := DirAccess.open(SaveManager.SAVE_DIR)
	if dir == null:
		return
	for slot in [ROUNDTRIP_SLOT, SECOND_NATION_SLOT, BOGUS_SLOT]:
		for p in [SaveManager._path_for(slot), SaveManager._path_for(slot) + SaveManager.TEMP_SUFFIX]:
			if FileAccess.file_exists(p):
				dir.remove(p)


## Same reflective, enumerate-off-the-object approach as test_state_copy.gd --
## walks whatever fields the class actually has instead of a hand-kept list,
## so it stays correct when a later session adds one.
func _check_pair(where: String, original, loaded) -> void:
	var names := _script_variables(original)
	if names.is_empty():
		_fail("%s: could not enumerate script variables — the reflective check is not running" % where)
		return

	for name in names:
		if name == "errors":
			continue  # new-game diagnostics, deliberately not saved
		if name == "nations":
			continue  # Dictionary of objects, not data -- compared nation-by-nation below
		var a = original.get(name)
		var b = loaded.get(name)
		if not _deep_equal(a, b):
			_fail("%s.%s: original %s, loaded %s" % [where, name, a, b])


func _deep_equal(a, b) -> bool:
	if typeof(a) != typeof(b):
		# int vs float is fine -- JSON has one numeric type and from_dict() casts
		# back to int where the field is declared int; a stray float/int pair
		# elsewhere still compares equal by value.
		if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
			return absf(float(a) - float(b)) < FLOAT_EPS
		return false

	match typeof(a):
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for key in a.keys():
				if not b.has(key) or not _deep_equal(a[key], b[key]):
					return false
			return true
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i in range(a.size()):
				if not _deep_equal(a[i], b[i]):
					return false
			return true
		TYPE_FLOAT:
			return absf(a - b) < FLOAT_EPS
		_:
			return a == b


func _script_variables(obj) -> Array:
	var names: Array = []
	for p in obj.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name: String = p["name"]
		if name == "script" or name.begins_with("_"):
			continue
		names.append(name)
	return names


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_save_load: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
