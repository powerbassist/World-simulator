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

const SENTINEL_KEY := "__test_state_copy_sentinel__"
const SENTINEL_NUMBER := -987654.321

## Fields duplicate_state() deliberately does not carry. Listed rather than left
## to chance, so "not copied" stays a failure everywhere else.
const NOT_COPIED := {
	"history": "a projection has no past",
	"errors": "new-game diagnostics, meaningless on a copy",
	"recent_effects": "a projection has no past, same reasoning as history",
	"foreign_acts": "a projection has no past; the SCHEDULE that produces acts is on NationState and IS copied",
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
			a[SENTINEL_KEY] = SENTINEL_NUMBER
			if b.has(SENTINEL_KEY):
				_fail("%s.%s: Dictionary is shared with the copy, not duplicated" % [where, name])
			a.erase(SENTINEL_KEY)
			_check_nested(where, name, a, b)
		elif typeof(a) == TYPE_ARRAY:
			a.append(SENTINEL_NUMBER)
			if b.size() != a.size() - 1:
				_fail("%s.%s: Array is shared with the copy, not duplicated" % [where, name])
			a.pop_back()


## A Dictionary of Dictionaries duplicated shallowly passes the check above and
## still shares its inner Dictionaries. NationState has no such field today; this
## is here so that the day one is added, it is caught.
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
