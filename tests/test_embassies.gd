extends SceneTree

## V5.1-0d: the embassies that already exist. Nothing modelled them, so
## open_embassy -- gated only on a meeting and relations >= 50 -- was offered to
## France for Croatia and Cyprus, and the AI opened 33 "new" embassies in the
## player's capital in a hands-off run. The seed is a rule data/world/embassies.json
## states: every roster state holds one in every other, except the listed pairs
## without diplomatic relations.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Relations = preload("res://src/core/relations.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const DiplomacyLoader = preload("res://src/core/loaders/diplomacy_loader.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_check_the_exceptions_loaded()
	_check_seed_follows_the_rule()
	_check_no_embassy_offered_where_one_exists()
	_check_opening_one_where_none_exists()
	_check_the_register_round_trips()
	_check_bad_exception_files_refused()
	_finish()


func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	if not state.errors.is_empty():
		_failures.append("new_game reported %s" % [state.errors])
	return state


func _offers_embassy(state, actor: String, target: String) -> bool:
	for action in Diplomacy.available(state, _loader.diplomatic_actions, actor, target):
		if String(action.id) == "open_embassy":
			return true
	return false


## A meeting this month and warm relations: every gate open_embassy had before 0d.
func _open_the_old_gates(state, actor: String, target: String) -> void:
	state.met_months[Relations.key(actor, target)] = state.year * 12 + state.month
	state.relations[Relations.key(actor, target)] = 60.0


func _check_the_exceptions_loaded() -> void:
	# The non-recognition pairs the data names; a file that loaded empty would seed
	# a world with no exception and pass every check below but this one.
	for pair in [["CYP", "TUR"], ["SRB", "XKX"], ["ESP", "XKX"]]:
		if not _loader.embassy_exceptions.has(Relations.key(pair[0], pair[1])):
			_failures.append("%s-%s is not among the pairs without relations" % pair)


func _check_seed_follows_the_rule() -> void:
	var state = _new_state()
	var ids: Array = state.nations.keys()
	for a in ids:
		var held: Array = state.nations[a].embassies
		for b in ids:
			if a == b:
				if held.has(b):
					_failures.append("%s holds an embassy in itself" % a)
				continue
			var expected: bool = not _loader.embassy_exceptions.has(Relations.key(a, b))
			if held.has(b) != expected:
				_failures.append("%s %s an embassy in %s; the rule says %s" % [
					a, "holds" if held.has(b) else "lacks", b, "it should" if expected else "it should not"])
	if state.nations[PLAYER].embassies.size() != ids.size() - 1:
		_failures.append("France holds %d embassies, not one in each of the other %d" % [
			state.nations[PLAYER].embassies.size(), ids.size() - 1])
	if state.nations["TUR"].embassies.has("CYP") or state.nations["CYP"].embassies.has("TUR"):
		_failures.append("Turkey and Cyprus hold missions in each other's capitals")


## The brief's bug: Croatia and Cyprus were offered.
func _check_no_embassy_offered_where_one_exists() -> void:
	var state = _new_state()
	for target in ["HRV", "CYP", "DEU"]:
		_open_the_old_gates(state, PLAYER, target)
		if _offers_embassy(state, PLAYER, target):
			_failures.append("France is offered an embassy in %s, where it already holds one" % target)
	# The AI side of the same gate: the 33 acts aimed at the player's capital.
	_open_the_old_gates(state, "DEU", PLAYER)
	if _offers_embassy(state, "DEU", PLAYER):
		_failures.append("Germany is offered an embassy in Paris, where it already holds one")


## Where none exists the verb still works, and the REGISTER (not the 240-month
## cooldown) is what closes it afterwards.
func _check_opening_one_where_none_exists() -> void:
	var state = _new_state()
	_open_the_old_gates(state, "ESP", "XKX")
	if not _offers_embassy(state, "ESP", "XKX"):
		_failures.append("Spain is not offered an embassy in Pristina, where it holds none")
		return
	var action = null
	for a in _loader.diplomatic_actions:
		if String(a.id) == "open_embassy":
			action = a
	var result: Dictionary = Diplomacy.execute(state, _loader.diplomatic_actions, action, "ESP", "XKX")
	if not bool(result.get("applied", false)):
		_failures.append("open_embassy ESP->XKX did not apply: %s" % [result])
		return
	if not state.nations["ESP"].embassies.has("XKX"):
		_failures.append("an applied open_embassy did not write the register")
	if state.nations["XKX"].embassies.has("ESP"):
		_failures.append("Spain's embassy in Pristina opened Kosovo's in Madrid -- a mission is one-way")
	state.nations["ESP"].diplo_cooldown_months.clear()
	if _offers_embassy(state, "ESP", "XKX"):
		_failures.append("with the cooldown gone, Spain is offered a second embassy in Pristina")


func _check_the_register_round_trips() -> void:
	var state = _new_state()
	state.nations["ESP"].embassies.append("XKX")
	var copy = state.duplicate_state()
	if not copy.nations["ESP"].embassies.has("XKX"):
		_failures.append("duplicate_state() dropped an opened embassy")
	var loaded = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	if loaded.nations["ESP"].embassies != state.nations["ESP"].embassies:
		_failures.append("a save round trip changed Spain's embassies: %s -> %s" % [
			state.nations["ESP"].embassies, loaded.nations["ESP"].embassies])


func _check_bad_exception_files_refused() -> void:
	var cases := {
		"unknown id": {"without_relations": [{"pair": ["FRA", "ZZZ"]}]},
		"self pair": {"without_relations": [{"pair": ["FRA", "FRA"]}]},
		"three ids": {"without_relations": [{"pair": ["FRA", "DEU", "ITA"]}]},
		"duplicate": {"without_relations": [{"pair": ["CYP", "TUR"]}, {"pair": ["TUR", "CYP"]}]},
		"no list": {},
	}
	for label in cases:
		var errors: Array[String] = []
		DiplomacyLoader.parse_embassy_exceptions(_loader, cases[label], "fixture.json", errors)
		if errors.is_empty():
			_failures.append("an embassy file with %s loaded without an error" % label)


func _finish() -> void:
	if _failures.is_empty():
		print("test_embassies: all checks passed")
		quit(0)
		return
	for f in _failures:
		print("FAIL: %s" % f)
	quit(1)
