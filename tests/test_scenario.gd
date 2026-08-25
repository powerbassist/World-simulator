extends SceneTree

## Headless test: godot --headless --script res://tests/test_scenario.gd
## Non-zero exit on any failure.
##
## V1.2e: start scenarios -- an authored starting state (debt, seat composition,
## approval) applied once at GameState.new_game(). Exercises the real
## new_game() path rather than calling the three init_nation() overrides
## directly, so the ordering _build_nation() depends on is under test too.
## See docs/scenario-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const K = preload("res://src/sim/opinion_constants.gd")

const GAME_START_YEAR := 2026
const GAME_START_MONTH := 1

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_every_scenario_names_a_playable_nation()
	_check_standard_start_is_unchanged()
	_check_debt_override_reaches_state()
	_check_seat_override_reaches_state()
	_check_approval_override_reaches_state()
	_check_approval_override_does_not_decay_to_neutral()
	_check_scenario_for_the_wrong_nation_is_refused()
	_check_unknown_scenario_is_refused()
	_check_scenario_runs_a_full_term_headless()
	_check_scenario_id_survives_a_save_round_trip()
	_check_bad_fixture_nation_not_playable()
	_check_bad_fixture_unknown_party()
	_check_bad_fixture_unknown_bloc()
	_check_bad_fixture_shares_do_not_sum()

	_finish()


func _new_state(player_id: String, scenario_id: String = ""):
	var state = GameState.new_game(_loader, player_id, scenario_id)
	if not state.errors.is_empty():
		_fail("new_game(%s, %s) reported errors: %s" % [player_id, scenario_id, state.errors])
	state.year = GAME_START_YEAR
	state.month = GAME_START_MONTH
	return state


## Enforced by the loader, asserted here so the shipped content is covered and
## not only the fixtures -- a scenario for an unplayable nation is unreachable.
func _check_every_scenario_names_a_playable_nation() -> void:
	if _loader.scenarios.is_empty():
		_fail("no scenarios loaded from data/scenarios/")
		return
	for id in _loader.scenarios.keys():
		var s = _loader.scenarios[id]
		if not _loader.nations.has(s.nation_id):
			_fail("scenario '%s' names unloaded nation '%s'" % [id, s.nation_id])
		elif not _loader.nations[s.nation_id].playable:
			_fail("scenario '%s' names unplayable nation '%s'" % [id, s.nation_id])


## The whole no-bump argument rests on this: "" is the game every existing save
## and every existing measured balance number describes.
func _check_standard_start_is_unchanged() -> void:
	var plain = _new_state("FRA")
	var empty = _new_state("FRA", "")
	if plain.player().debt_eur_bn != empty.player().debt_eur_bn:
		_fail("an empty scenario_id did not produce the standard start")
	if plain.scenario_id != "":
		_fail("a standard start recorded scenario_id '%s'" % plain.scenario_id)


func _check_debt_override_reaches_state() -> void:
	var base = _new_state("FRA")
	var state = _new_state("FRA", "fra_inheritance")
	var s = _loader.scenarios["fra_inheritance"]

	var ns = state.player()
	var expected: float = s.debt_to_gdp_pct / 100.0 * ns.gdp_eur_bn
	if absf(ns.debt_eur_bn - expected) > 0.001:
		_fail("fra_inheritance debt: expected %.3f, got %.3f" % [expected, ns.debt_eur_bn])

	# Applied BEFORE Budget.recompute(), which is what makes an inherited debt a
	# permanent drag rather than a number on a panel. If the override landed
	# after, debt service and so the starting deficit would be the base game's.
	if ns.start_deficit_pct_gdp <= base.player().start_deficit_pct_gdp:
		_fail("an inherited debt did not raise the starting deficit: %.3f vs base %.3f" % [
			ns.start_deficit_pct_gdp, base.player().start_deficit_pct_gdp,
		])


func _check_seat_override_reaches_state() -> void:
	var state = _new_state("DEU", "deu_grand_coalition")
	var ns = state.player()
	var s = _loader.scenarios["deu_grand_coalition"]

	var total := 0
	for seats in ns.seats_by_party.values():
		total += int(seats)
	if total != ns.assembly_seats:
		_fail("deu_grand_coalition seats sum to %d, expected assembly_seats %d" % [total, ns.assembly_seats])

	# Allocated by largest remainder, so assert the share rather than an exact
	# seat count -- the rounding belongs to pr_national(), not to this test.
	for party_id in s.seat_share.keys():
		var got: float = float(ns.seats_by_party.get(party_id, 0)) / float(ns.assembly_seats)
		if absf(got - float(s.seat_share[party_id])) > 0.005:
			_fail("deu_grand_coalition '%s': expected share %.3f, got %.3f" % [
				party_id, s.seat_share[party_id], got,
			])


func _check_approval_override_reaches_state() -> void:
	var state = _new_state("FRA", "fra_inheritance")
	var ns = state.player()
	var s = _loader.scenarios["fra_inheritance"]

	for bloc in s.bloc_approval.keys():
		var got: float = float(ns.bloc_approval[bloc])
		if absf(got - float(s.bloc_approval[bloc])) > 0.001:
			_fail("fra_inheritance '%s': expected approval %.3f, got %.3f" % [
				bloc, s.bloc_approval[bloc], got,
			])

	# A bloc the scenario does not name stays neutral -- partial overrides are
	# the common case and must not quietly move the rest of the electorate.
	for bloc in K.BLOC_KEYS:
		if s.bloc_approval.has(bloc):
			continue
		if absf(float(ns.bloc_approval[bloc]) - K.APPROVAL_NEUTRAL) > 0.001:
			_fail("fra_inheritance moved unnamed bloc '%s' to %.3f" % [bloc, ns.bloc_approval[bloc]])

	if ns.overall_approval_pct >= K.APPROVAL_NEUTRAL:
		_fail("fra_inheritance did not roll its blocs up into overall_approval_pct: %.3f" % ns.overall_approval_pct)


## The reason the override writes bloc_offset as well as bloc_approval.
## Every satisfaction term is a delta against the nation's own start, so a fresh
## game's approval target is exactly APPROVAL_NEUTRAL -- an authored figure with
## no target shift decays back to 50 on INERTIA_RATE's ~2.4-month half-life and
## is gone inside a game year, while the debt and seat axes persist. Measured
## before it was built: docs/scenario-model.md.
func _check_approval_override_does_not_decay_to_neutral() -> void:
	var state = _new_state("FRA", "fra_inheritance")
	var ns = state.player()
	var at_start: float = ns.overall_approval_pct

	for _i in range(12):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)

	# Twelve months is five half-lives: a purely positional override would be
	# within a rounding error of neutral by here.
	if ns.overall_approval_pct > at_start + 1.0:
		_fail("authored approval decayed toward neutral: %.3f at start, %.3f after 12 months" % [
			at_start, ns.overall_approval_pct,
		])


func _check_scenario_for_the_wrong_nation_is_refused() -> void:
	var state = GameState.new_game(_loader, "FRA", "deu_grand_coalition")
	var named := false
	for e in state.errors:
		if e.find("deu_grand_coalition") != -1 and e.find("DEU") != -1:
			named = true
	if not named:
		_fail("a scenario authored for another nation was not refused, or did not name both: %s" % [state.errors])


func _check_unknown_scenario_is_refused() -> void:
	var state = GameState.new_game(_loader, "FRA", "no_such_scenario")
	var named := false
	for e in state.errors:
		if e.find("no_such_scenario") != -1:
			named = true
	if not named:
		_fail("an unknown scenario id was not refused: %s" % [state.errors])


## The rule every sim session holds to: a full run works headless with no scene
## tree. Run against the scenario that changes the most state.
func _check_scenario_runs_a_full_term_headless() -> void:
	var state = _new_state("GBR", "gbr_hung_parliament")
	if not state.errors.is_empty():
		return

	var ns = state.player()
	for _i in range(60):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		state.append_history(Budget.snapshot(state))
		Discipline.tick_month(state, _loader)
		Legislature.tick_month(state, _loader)
		Dissolution.tick_month(state)
		Cabinet.tick_month(state, _loader)
		Elections.tick_month(state, _loader)

	if not is_finite(ns.gdp_eur_bn) or ns.gdp_eur_bn <= 0.0:
		_fail("a scenario run produced a non-finite or non-positive GDP: %s" % ns.gdp_eur_bn)
	if not is_finite(ns.overall_approval_pct):
		_fail("a scenario run produced a non-finite approval")


## No SAVE_VERSION bump was taken for scenario_id, on the argument that a
## version-8 save's absent value reads as "" and that is CORRECT rather than
## silently wrong. That argument is only sound if the id round-trips when it IS
## present, and if the scenario's effects ride in the ordinary fields.
func _check_scenario_id_survives_a_save_round_trip() -> void:
	var state = _new_state("DEU", "deu_grand_coalition")
	var restored = GameState.from_dict(state.to_dict())

	if restored.scenario_id != "deu_grand_coalition":
		_fail("scenario_id did not survive a save round trip: got '%s'" % restored.scenario_id)
	if restored.player().seats_by_party != state.player().seats_by_party:
		_fail("a scenario's seat composition did not survive a save round trip")

	# The other half of the no-bump argument: a save written before this field
	# existed must load as the standard start, not as a broken one.
	var older: Dictionary = state.to_dict()
	older.erase("scenario_id")
	if GameState.from_dict(older).scenario_id != "":
		_fail("a save with no scenario_id did not read as the standard start")


func _fixture_errors(scenarios_dir: String) -> Array:
	var fixture_loader := DataLoader.new()
	fixture_loader.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://data/eu_parliament.json", "res://data/laws",
		"res://data/political-systems", scenarios_dir,
	)
	return fixture_loader.errors


func _check_bad_fixture_nation_not_playable() -> void:
	var named := false
	for e in _fixture_errors("res://tests/fixtures/scenarios_bad_nation"):
		if e.find("bad_nation") != -1 and e.find("ITA") != -1:
			named = true
	if not named:
		_fail("a scenario for an unplayable nation loaded, or did not name the nation")


func _check_bad_fixture_unknown_party() -> void:
	var named := false
	for e in _fixture_errors("res://tests/fixtures/scenarios_bad_party"):
		if e.find("bad_party") != -1 and e.find("parti_imaginaire") != -1:
			named = true
	if not named:
		_fail("a scenario naming an unknown party loaded, or did not name the party")


func _check_bad_fixture_unknown_bloc() -> void:
	var named := false
	for e in _fixture_errors("res://tests/fixtures/scenarios_bad_bloc"):
		if e.find("bad_bloc") != -1 and e.find("landowners") != -1:
			named = true
	if not named:
		_fail("a scenario naming an unknown voter bloc loaded, or did not name the bloc")


## The one fixture that passes every per-file check in scenario.gd and fails
## only against the nation's own roster -- which is why the sum check is a
## cross-file check and not a shape check.
func _check_bad_fixture_shares_do_not_sum() -> void:
	var named := false
	for e in _fixture_errors("res://tests/fixtures/scenarios_bad_sum"):
		if e.find("bad_sum") != -1 and e.find("seat_share") != -1:
			named = true
	if not named:
		_fail("a scenario leaving the roster off 1.0 loaded, or did not name seat_share")


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_scenario: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
