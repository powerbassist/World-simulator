extends SceneTree

## Headless test: godot --headless --script res://tests/test_nation_fields.gd
## Non-zero exit on any failure.
##
## src/core/nation_fields.gd is NationState's one field table: duplicate_state(),
## to_dict() and from_dict() each walk it. This file holds the four things a
## table cannot hold about itself:
##
##   1. COMPLETENESS. Every NationState `var` has exactly one row, enumerated off
##      the object rather than listed, and each row's default IS the declaration's
##      -- a field added to the class and not to the table fails here, not in a
##      save a month later.
##   2. ROUND TRIP. Every saved field set to a non-default sentinel comes back
##      exactly (type included) through to_dict()/from_dict(), directly and through
##      JSON, and through duplicate_state() -- generic over the table, so a new
##      row is covered the day it is added.
##   3. ALIASING. Mutating a loaded state must not touch the payload it was loaded
##      from: to_dict() hands back the live fields, so an assigning reader would
##      make two states one simulation (the V4.6 commodity defect, and the three
##      registers V5.0a found still assigned).
##   4. ABSENCE. An absent key reads as the row's default, and the set of fields
##      whose absence reads WRONG is pinned against SAVE_VERSION -- AGENTS.md's
##      bump rule as a column a test reads.
##
## No loader and no game: a bare NationState is the whole fixture, which keeps
## this file fast and makes every sentinel unmistakable.

const NationState = preload("res://src/core/nation_state.gd")
const Fields = preload("res://src/core/nation_fields.gd")
const GameState = preload("res://src/core/game_state.gd")

## The saved fields whose absence reads WRONG (absent_ok == false), as a count and
## the md5 of their sorted names joined by commas, at the SAVE_VERSION they were
## pinned at. A new field marked absent_ok = false changes the digest: bump
## SAVE_VERSION with its argument, then re-pin. A new absent_ok = true field leaves
## it alone -- that is the rule working, not a hole: its row says why absence is
## the truth, and review reads that line. A SAVE_VERSION move alone also fails, so
## the pin is re-read every time the version moves rather than drifting.
## Re-pinned at 41 (V5.1-0d) for one field, `embassies`: absent, a reloaded world
## holds no embassy anywhere (its declaration in nation_state.gd has the argument).
const MUST_BUMP_PIN := {
	"save_version": 41,
	"count": 169,
	"md5": "3b2f3a264e471eb15230b73a72aeba31",
}

## Sentinels per read kind, each in the exact shape and types its reader returns,
## and none a fresh NationState ever holds. Every float a MAP or REGISTER reader
## re-casts is a WHOLE number, unique in its entry so a swapped key shows -- the case the casts exist for. Godot 4.7.2's JSON already hands
## these back as floats (measured: dropping float() from float_map still passes),
## so today the casts are a guard and these sentinels are what shows one missing
## on an engine whose JSON returns ints. A float no reader casts carries a
## fraction; free-form values are strings.
const ALIAS_PROBE := "__alias_probe__"

var _failures: Array[String] = []


func _init() -> void:
	_check_completeness()
	var state = _sentinel_state()
	if state != null:
		_check_round_trip(state)
		_check_aliasing(state)
		_check_absence(state)
	_check_bump_pin()
	_finish()


# --- 1. completeness ---------------------------------------------------------

func _check_completeness() -> void:
	var fresh = NationState.new()
	var declared: Array = []
	for p in fresh.get_property_list():
		if int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			declared.append(String(p["name"]))
	if declared.size() < 200:
		_fail("enumerated only %d NationState vars -- the reflective check is not running" % declared.size())
	var rows := {}
	for row in Fields.FIELDS:
		var name: String = row[Fields.COL_NAME]
		if rows.has(name):
			_fail("%s has two rows in the field table" % name)
		rows[name] = row
	for name in declared:
		if not rows.has(name):
			_fail("NationState.%s has no row in src/core/nation_fields.gd -- duplicate_state, to_dict and from_dict would all skip it" % name)
	for name in rows:
		if not declared.has(name):
			_fail("the field table names %s, which NationState does not declare" % name)
			continue
		var row: Array = rows[name]
		var declared_default = fresh.get(name)
		if not _same(row[Fields.COL_DEFAULT], declared_default):
			_fail("%s: table default %s is not the declaration's %s" % [name, row[Fields.COL_DEFAULT], declared_default])
		var container: bool = typeof(declared_default) in [TYPE_DICTIONARY, TYPE_ARRAY]
		var copy: int = row[Fields.COL_COPY]
		if copy == Fields.SCALAR and container:
			_fail("%s is a container copied as SCALAR -- a projection would share it" % name)
		if copy == Fields.DEEP and not container:
			_fail("%s is a scalar marked DEEP" % name)
		if row[Fields.COL_READ] != Fields.NOT_SAVED and copy == Fields.NONE:
			_fail("%s is saved but not copied: a projection would run without it" % name)


# --- 2. round trip -----------------------------------------------------------

func _check_round_trip(state) -> void:
	var direct = NationState.from_dict(state.to_dict())
	var parsed = JSON.parse_string(JSON.stringify(state.to_dict()))
	var via_json = NationState.from_dict(parsed)
	var dup = state.duplicate_state()
	var fresh = NationState.new()
	for row in Fields.FIELDS:
		var name: String = row[Fields.COL_NAME]
		var want := var_to_str(state.get(name))
		if row[Fields.COL_READ] != Fields.NOT_SAVED:
			if var_to_str(direct.get(name)) != want:
				_fail("%s: to_dict/from_dict returned %s, wanted %s" % [name, var_to_str(direct.get(name)), want])
			if var_to_str(via_json.get(name)) != want:
				_fail("%s: the JSON round trip returned %s, wanted %s" % [name, var_to_str(via_json.get(name)), want])
		elif state.to_dict().has(name):
			_fail("%s is NOT_SAVED but to_dict() carries it" % name)
		var copied := var_to_str(dup.get(name))
		if row[Fields.COL_COPY] == Fields.NONE:
			if copied != var_to_str(fresh.get(name)):
				_fail("%s is NONE but duplicate_state() carried it" % name)
		elif copied != want:
			_fail("%s: duplicate_state() returned %s, wanted %s" % [name, copied, want])


# --- 3. aliasing -------------------------------------------------------------

func _check_aliasing(state) -> void:
	var payload: Dictionary = state.to_dict()
	var loaded = NationState.from_dict(payload)
	for name in payload:
		var before := var_to_str(payload[name])
		var value = loaded.get(name)
		if typeof(value) == TYPE_DICTIONARY or typeof(value) == TYPE_ARRAY:
			_mutate(value)
		if var_to_str(payload[name]) != before:
			_fail("%s: mutating the loaded state moved the payload -- from_dict assigned instead of rebuilding" % name)


## Every level a register has: commodity_state's goods, the ledger's channels
## and months, a poll's kinds are two below the field, so a reader that dropped an
## INNER duplicate is caught as surely as one that assigned the whole payload.
func _mutate(value, depth: int = 0) -> void:
	if depth > 3:
		return
	if typeof(value) == TYPE_DICTIONARY:
		for key in value.keys():
			if typeof(value[key]) == TYPE_DICTIONARY or typeof(value[key]) == TYPE_ARRAY:
				_mutate(value[key], depth + 1)
		match value.get_typed_value_builtin():
			TYPE_FLOAT: value[ALIAS_PROBE] = -1.5
			TYPE_BOOL: value[ALIAS_PROBE] = true
			_: value[ALIAS_PROBE] = ALIAS_PROBE
	else:
		for element in value:
			if typeof(element) == TYPE_DICTIONARY or typeof(element) == TYPE_ARRAY:
				_mutate(element, depth + 1)
		if value.get_typed_builtin() == TYPE_DICTIONARY:
			value.append({ALIAS_PROBE: ALIAS_PROBE})
		else:
			value.append(ALIAS_PROBE)


# --- 4. absence --------------------------------------------------------------

func _check_absence(state) -> void:
	var fresh = NationState.new()
	var full: Dictionary = JSON.parse_string(JSON.stringify(state.to_dict()))
	for row in Fields.FIELDS:
		var name: String = row[Fields.COL_NAME]
		if row[Fields.COL_READ] == Fields.NOT_SAVED:
			continue
		var payload := full.duplicate(true)
		payload.erase(name)
		var loaded = NationState.from_dict(payload)
		if var_to_str(loaded.get(name)) != var_to_str(fresh.get(name)):
			_fail("%s: absent, it read %s rather than its default %s" % [name, var_to_str(loaded.get(name)), var_to_str(fresh.get(name))])
		# The neighbours of an absent field are untouched by its absence.
		var other: String = "id" if name != "id" else "gdp_eur_bn"
		if var_to_str(loaded.get(other)) != var_to_str(state.get(other)):
			_fail("%s: its absence disturbed %s" % [name, other])


func _check_bump_pin() -> void:
	var names: Array = []
	for row in Fields.FIELDS:
		if row[Fields.COL_READ] != Fields.NOT_SAVED and not row[Fields.COL_ABSENT_OK]:
			names.append(String(row[Fields.COL_NAME]))
	names.sort()
	var digest := ",".join(PackedStringArray(names)).md5_text()
	if GameState.SAVE_VERSION != int(MUST_BUMP_PIN["save_version"]):
		_fail("SAVE_VERSION is %d but the must-bump set was pinned at %d: re-read the absent_ok column, then re-pin (count %d, md5 %s)" % [GameState.SAVE_VERSION, MUST_BUMP_PIN["save_version"], names.size(), digest])
	elif names.size() != int(MUST_BUMP_PIN["count"]) or digest != String(MUST_BUMP_PIN["md5"]):
		_fail("the fields whose absence reads wrong changed (now %d, md5 %s) at the same SAVE_VERSION %d: a field like that bumps the version (AGENTS.md, Save format)" % [names.size(), digest, GameState.SAVE_VERSION])


# --- fixture -----------------------------------------------------------------

## A bare NationState with every field set to its read kind's sentinel, the
## transient ones included so the NONE and NOT_SAVED rows are seen to drop them.
func _sentinel_state():
	var state = NationState.new()
	for row in Fields.FIELDS:
		var name: String = row[Fields.COL_NAME]
		var value = _sentinel(row[Fields.COL_READ], state.get(name))
		if value == null:
			_fail("%s: no sentinel for read kind %d -- add one here with the reader" % [name, row[Fields.COL_READ]])
			return null
		state.set(name, value)
		if var_to_str(state.get(name)) != var_to_str(value):
			_fail("%s: the sentinel %s did not take (the field's type refused it)" % [name, var_to_str(value)])
	return state


func _sentinel(read: int, declared):
	match read:
		Fields.VALUE:
			match typeof(declared):
				TYPE_INT: return 7031
				TYPE_FLOAT: return 12.375
				TYPE_BOOL: return not declared
				TYPE_STRING: return "sentinel"
		Fields.COPIED, Fields.NOT_SAVED:
			if typeof(declared) == TYPE_ARRAY:
				return ["sentinel_a", "sentinel_b"]
			return {"sentinel": "x", "inner": {"k": "v"}}
		Fields.FLOAT_MAP: return {"sentinel": 2.0}
		Fields.INT_MAP: return {"sentinel": 7}
		Fields.STRING_MAP: return {"sentinel": "v"}
		Fields.SORTED_STRINGS: return ["a_sentinel", "b_sentinel"]
		Fields.ROWS:
			var rows: Array[Dictionary] = [{"event_id": "sentinel"}]
			return rows
		Fields.FLOAT_MAP_TYPED:
			var floats: Dictionary[String, float] = {"sentinel": 2.0}
			return floats
		Fields.STRING_MAP_TYPED:
			var strings: Dictionary[String, String] = {"sentinel": "v"}
			return strings
		Fields.BOOL_MAP_TYPED:
			var bools: Dictionary[String, bool] = {"sentinel": true}
			return bools
		Fields.PLEDGES:
			return [{"pledge_id": "p", "field": "f", "op": "max", "value": 6.0,
				"from_year": 2026, "from_month": 2, "until_year": 2030, "until_month": 3,
				"breach_months": 4, "months_live": 5}]
		Fields.PROGRAMME:
			return [{"entry_id": "e", "chosen_term": 1, "months_live": 2, "status": "done",
				"concluded_term": 3, "concluded_term_month": 4}]
		Fields.COMMODITY_STATE: return {"capacity": {"steel": 2.0}, "price_index": 1.0}
		Fields.LAW_LEDGER: return {"law_s": {"channels": {"c": 0.5}, "months": ["m"]}}
		Fields.DRAFT_BILLS: return {"d": {"law_id": "x", "size": 2.0, "months_left": 3}}
		Fields.CUSTOM_TAXES:
			return {"t": {"name": "n", "base_share": 1.0, "erosion": 2.0, "ref_pct": 3.0}}
		Fields.POLL_PURCHASES: return {"b": {"k": {"month": 3, "cost": 2.0}}}
		Fields.ASSEMBLY_BILLS:
			return {"b": {"law_id": "l", "months_left": 2, "backer_firm": "f",
				"backer_chief": "c", "endorse_bonus": 1.0}}
		Fields.HELD_BILLS: return {"l": {"months": 2, "origin": "player"}}
	return null


## Equal in type and in content, typed containers compared by content.
func _same(a, b) -> bool:
	return typeof(a) == typeof(b) and JSON.stringify(a, "", true) == JSON.stringify(b, "", true)


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_nation_fields: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
