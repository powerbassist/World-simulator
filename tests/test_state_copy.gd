extends SceneTree

## Headless test: godot --headless --script res://tests/test_state_copy.gd
## Non-zero exit on any failure.
##
## GameState.duplicate_state() and NationState.duplicate_state() are hand-written
## field lists. A field added to the class and forgotten in the copy fails in the
## nastiest possible way: the budget projection silently shares a Dictionary with
## the live game, so committing a budget mutates history and a projection mutates
## the present. Nothing else in the suite catches it.
##
## So this test does not list fields. It enumerates them off the object, which
## means it keeps working for S6 election state and S9 save/load without anyone
## remembering to edit it.
##
## Two distinct bugs, two distinct checks:
##   1. Field not copied at all — the copy differs from the original immediately.
##   2. Field copied by reference — mutating the original moves the copy too.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Relations = preload("res://src/core/relations.gd")

const SENTINEL_KEY := "__test_state_copy_sentinel__"
const SENTINEL_NUMBER := -987654.321

## Fields duplicate_state() deliberately does not carry. Listed rather than left
## to chance, so "not copied" stays a failure everywhere else.
const NOT_COPIED := {
	"history": "a projection has no past",
	"errors": "new-game diagnostics, meaningless on a copy",
	"recent_effects": "a projection has no past, same reasoning as history",
	"foreign_acts": "a projection has no past; the SCHEDULE that produces acts is on NationState and IS copied",
	"unrest_acts": "a projection has no past; the SCHEDULE that produces acts (unrest_cooldown_months) is on NationState and IS copied -- foreign_acts' split exactly",
}

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return

	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_failures.append("new_game reported %s" % [state.errors])
		_finish()
		return

	# Move every nation off its defaults first, and commit a budget so the policy
	# and impulse fields differ from their starting values too. A field left at
	# its default would compare equal even if it were never copied.
	Budget.commit(state, {
		"tax_rates_pct": {"income": 27.0, "corporate": 31.0, "vat": 23.0},
		"spending_pct_gdp": {"health": 12.5, "education": 6.5, "defence": 3.0, "pensions": 13.0, "infrastructure": 5.0},
	})
	for _i in range(6):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)

	# The pair registers, written directly. This closes a hole the reflective check
	# below cannot see on its own: an EMPTY Dictionary field that duplicate_state()
	# forgets entirely still passes both checks, because 0 entries equals 0 entries
	# and a fresh {} cannot be seen as shared. `measures` sat in that hole from V1.3c
	# until V1.3g, and `pacts`/`deployments` would have joined it.
	state.measures[Relations.directed_key("FRA", "DEU")] = {
		"action_id": "copy_probe", "kind": "tariff", "severity": 0.4,
		"since_year": state.year, "since_month": state.month, "retaliated": false,
	}
	state.pacts[Relations.key("FRA", "ITA")] = {
		"action_id": "copy_probe", "action_name": "Copy Probe",
		"since_year": state.year, "since_month": state.month,
	}
	state.deployments[Relations.directed_key("FRA", "ITA")] = {
		"kind": "chosen", "since_year": state.year, "since_month": state.month,
	}
	# The V4.4 hook stamps, the same hole one register over: both are empty at
	# staging on every nation, so duplicate_state() dropping them ENTIRELY was
	# invisible to the walker below (0 entries equals 0 entries -- the ultra
	# pass-1 finding). Staged on every nation because the check runs per nation:
	# one staged nation would leave twenty-eight vacuous passes behind it.
	var Events = load("res://src/sim/events.gd")
	var staged_event = null
	for candidate in loader.events:
		staged_event = candidate
		break
	if staged_event == null:
		_fail("event-register copy staging needs a loaded event")
	else:
		for id in state.nations:
			var staged_ns = state.nations[id]
			staged_ns.repealed_at["copy_probe_law"] = 1234
			staged_ns.last_accession = {"org": "copy_probe_org", "month_index": 1234}
			staged_ns.assembly_bill_passed_month = 1234
			staged_ns.commodity_high_month = 1234
			staged_ns.event_fired["copy_probe_event"] = true
			staged_ns.event_category_quiet["copy_probe_category"] = 3
			staged_ns.event_cooldowns["copy_probe_event"] = 1234
			staged_ns.event_armed.append({"event_id": String(staged_event.id), "due_index": 1234, "source_id": "copy_probe_source"})
			Events.announce(staged_ns, staged_event, 1234, {})
			staged_ns.event_history.append({"event_id": "copy_probe_event", "event_name": "Copy probe", "choice_id": "copy_probe_choice", "choice_label": "Copy probe", "defaulted": false, "year": 2026, "month": 1})

	var copy = state.duplicate_state()

	_check_pair("GameState", state, copy)
	for id in state.nations.keys():
		if not copy.nations.has(id):
			_fail("GameState.duplicate_state() dropped nation %s" % id)
			continue
		_check_pair("NationState[%s]" % id, state.nations[id], copy.nations[id])

	_finish()


func _check_pair(where: String, original, copy) -> void:
	var names := _script_variables(original)
	if names.is_empty():
		_fail("%s: could not enumerate script variables — the reflective check is not running" % where)
		return

	for name in names:
		if NOT_COPIED.has(name):
			continue
		var a = original.get(name)
		var b = copy.get(name)

		# 1. Copied at all?
		if typeof(a) != typeof(b):
			_fail("%s.%s: original is %s, copy is %s" % [where, name, type_string(typeof(a)), type_string(typeof(b))])
			continue
		if typeof(a) == TYPE_DICTIONARY or typeof(a) == TYPE_ARRAY:
			if a.size() != b.size():
				_fail("%s.%s: original has %d entries, copy has %d — not copied" % [where, name, a.size(), b.size()])
				continue
		elif a != b:
			_fail("%s.%s: original is %s, copy is %s — not copied" % [where, name, a, b])
			continue

		# 2. Copied by reference?
		if typeof(a) == TYPE_DICTIONARY:
			a[SENTINEL_KEY] = _dict_sentinel(a)
			if b.has(SENTINEL_KEY):
				_fail("%s.%s: Dictionary is shared with the copy, not duplicated" % [where, name])
			a.erase(SENTINEL_KEY)
			_check_nested(where, name, a, b)
		elif typeof(a) == TYPE_ARRAY:
			a.append(_array_sentinel(a))
			if b.size() != a.size() - 1:
				_fail("%s.%s: Array is shared with the copy, not duplicated" % [where, name])
			a.pop_back()


## A sentinel the array will actually accept. Until U6a every copied Array on
## either state object was untyped, so a bare float worked and the three
## Array[Dictionary] fields were all in NOT_COPIED for unrelated reasons -- which
## means this branch had never once run against a typed array. GameState.appointments
## is the first, and it pushed the gap into the open: a TypedArray refuses a
## push_back of the wrong type, the size check then reads unchanged, and the test
## reports "shared with the copy" for a field that is duplicated correctly. A
## guard rail that fails for the wrong reason is worse than one that does not run.
func _array_sentinel(a: Array):
	match a.get_typed_builtin():
		TYPE_DICTIONARY: return {SENTINEL_KEY: SENTINEL_NUMBER}
		TYPE_ARRAY: return [SENTINEL_NUMBER]
		TYPE_STRING: return SENTINEL_KEY
		TYPE_INT: return int(SENTINEL_NUMBER)
	return SENTINEL_NUMBER


## The dictionary half of the same lesson, and V4.3's six character registers
## are what pushed it open: until them, every copied Dictionary on either state
## object was untyped, so the bare float sentinel worked -- and a
## Dictionary[String, String] override register REFUSES a float value, the set
## errors into the log, and the suite fails a correctly-duplicated field for
## the wrong reason (the _array_sentinel comment's own argument, one type over).
func _dict_sentinel(a: Dictionary):
	match a.get_typed_value_builtin():
		TYPE_STRING: return SENTINEL_KEY
		TYPE_FLOAT: return SENTINEL_NUMBER
		TYPE_INT: return int(SENTINEL_NUMBER)
	return SENTINEL_NUMBER


## A Dictionary of Dictionaries duplicated shallowly passes the check above and
## still shares its inner Dictionaries. V4.6 gave NationState its first such
## field -- `commodity_state`, a register of per-good dictionaries -- so this
## guard is live now, not dormant: it walks that register on every suite run and
## is what catches a shallow `duplicate()` of it.
func _check_nested(where: String, name: String, a: Dictionary, b: Dictionary) -> void:
	for key in a.keys():
		if typeof(a[key]) != TYPE_DICTIONARY:
			continue
		a[key][SENTINEL_KEY] = SENTINEL_NUMBER
		if b.has(key) and typeof(b[key]) == TYPE_DICTIONARY and b[key].has(SENTINEL_KEY):
			_fail("%s.%s['%s']: nested Dictionary is shared with the copy" % [where, name, key])
		a[key].erase(SENTINEL_KEY)


## Script-declared vars only — not the engine's `script`, `RefCounted` internals,
## or method entries.
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
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_state_copy: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
