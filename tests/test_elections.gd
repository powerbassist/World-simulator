extends SceneTree

## Headless test: godot --headless --script res://tests/test_elections.gd
## Non-zero exit on any failure.
##
## Nothing here argues that the formula implies an outcome — every check runs
## the real tick sequence (Economy, Budget, Opinion, Elections, in that order,
## the same order main.gd wires) and reads what actually happened.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
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

	_check_vote_share_invariants()
	_check_neutral_reelects()
	_check_monotone_in_approval()
	_check_schedule_fires_only_on_date_and_advances()
	_check_ep_never_fires_for_non_members()
	_check_governing_badly_loses()
	_check_governing_well_wins_and_second_term_starts()
	_check_determinism()

	_finish()


func _new_state(player_id := "FRA"):
	var state = GameState.new_game(_loader, player_id)
	if not state.errors.is_empty():
		_fail("new_game(%s) reported errors: %s" % [player_id, state.errors])
	state.year = GAME_START_YEAR
	state.month = GAME_START_MONTH
	return state


## Vote shares sum to 1.0 and no party gets a negative share.
func _check_vote_share_invariants() -> void:
	var state = _new_state()
	var ns = state.player()
	var parties: Array = _loader.parties["FRA"]

	var shares := Elections.vote_share(ns, parties, ns.incumbent_party_id)
	var total := 0.0
	for party in shares:
		var s: float = float(shares[party])
		if s < 0.0:
			_fail("vote_share: %s got a negative share %.4f" % [party, s])
		total += s
	if absf(total - 1.0) > 1.0e-6:
		_fail("vote_share: shares sum to %.6f, expected 1.0" % total)


## At approval 50 everywhere (a fresh game), the incumbent's seat_share prior
## dominates and it stays the largest party — a do-nothing term is survivable,
## matching the opinion model's do-nothing row.
func _check_neutral_reelects() -> void:
	var state = _new_state()
	var ns = state.player()
	var parties: Array = _loader.parties["FRA"]
	var result := Elections.resolve(ns, parties, "two_round", 0.0, "national", state.year, state.month)
	if not result["incumbent_largest"]:
		_fail("at neutral approval the incumbent was not the largest party: %s" % [result["seats"]])


## Raising the incumbent's own bloc's approval must raise its vote share at
## every step — the swing term should never point the wrong way.
func _check_monotone_in_approval() -> void:
	var state = _new_state()
	var ns = state.player()
	var parties: Array = _loader.parties["FRA"]

	var previous := -1.0
	for approval in [10.0, 30.0, 50.0, 70.0, 90.0]:
		ns.bloc_approval["workers"] = approval
		var shares := Elections.vote_share(ns, parties, ns.incumbent_party_id)
		var share: float = float(shares[ns.incumbent_party_id])
		if share <= previous:
			_fail("incumbent vote share did not rise with approval: %.4f at %d%% approval, previous was %.4f" % [
				share, approval, previous
			])
		previous = share


## The national election fires in the exact month the data names (FRA: June
## 2029) and no other, and after a win the next date is exactly term_years
## later.
func _check_schedule_fires_only_on_date_and_advances() -> void:
	var state = _new_state()
	var ns = state.player()
	var target_months := (2029 - GAME_START_YEAR) * 12 + (6 - GAME_START_MONTH)

	for i in range(target_months - 1):
		var results := _tick(state)
		if not results.is_empty():
			_fail("election fired early, at month %d (year %d month %d): %s" % [i + 1, state.year, state.month, results])
			return

	var final_results := _tick(state)
	if final_results.is_empty():
		_fail("no election fired at the scheduled month (year %d month %d)" % [state.year, state.month])
		return

	var national = null
	for r in final_results:
		if r["kind"] == "national":
			national = r
	if national == null:
		_fail("national election did not fire alongside the EP election in June 2029")
		return

	if national["incumbent_largest"]:
		if ns.next_election_year != 2034 or ns.next_election_month != 6:
			_fail("after a win, next election is %d-%d, expected 2034-6" % [ns.next_election_year, ns.next_election_month])
	else:
		if ns.in_government:
			_fail("incumbent was not the largest party but in_government is still true")


## An EU member (FRA) resolves an EP election in June 2029 alongside its
## national one. A non-member (GBR, CHE) never resolves one at all — the field
## stays zero and no eu_parliament result ever appears, however long the game
## runs.
func _check_ep_never_fires_for_non_members() -> void:
	for id in ["GBR", "CHE"]:
		var state = _new_state(id)
		var ns = state.player()
		if ns.next_ep_election_year != 0 or ns.next_ep_election_month != 0:
			_fail("%s: non-member started with a scheduled EP election (%d-%d)" % [
				id, ns.next_ep_election_year, ns.next_ep_election_month
			])
		for _i in range(60):
			var results := _tick(state)
			for r in results:
				if r["kind"] == "eu_parliament":
					_fail("%s: a non-member resolved an EP election" % id)
					return


## Ignoring the budget and letting the public finances and services rot must
## cost the incumbent the election.
func _check_governing_badly_loses() -> void:
	var state = _new_state()
	Budget.commit(state, {
		"spending_pct_gdp": {"health": 4.0, "education": 1.5, "defence": 0.0, "pensions": 5.0, "infrastructure": 0.0},
	})

	var target_months := (2029 - GAME_START_YEAR) * 12 + (6 - GAME_START_MONTH)
	var results := []
	for _i in range(target_months):
		results = _tick(state)

	var ns = state.player()
	if ns.in_government:
		_fail("a brutal budget still won re-election (approval %.1f)" % ns.overall_approval_pct)
		return

	var national = null
	for r in results:
		if r["kind"] == "national":
			national = r
	if national == null:
		_fail("no national result recorded for the losing term")
		return
	if national["incumbent_largest"]:
		_fail("in_government is false but the result still names the incumbent as largest")


## A modest, sustainable budget should win re-election, and the game continues
## into a second term with the counters reset and advancing correctly.
func _check_governing_well_wins_and_second_term_starts() -> void:
	var state = _new_state()
	Budget.commit(state, {
		"spending_pct_gdp": {"health": 11.5, "education": 6.0, "defence": 2.0, "pensions": 14.5, "infrastructure": 4.0},
	})

	var target_months := (2029 - GAME_START_YEAR) * 12 + (6 - GAME_START_MONTH)
	for _i in range(target_months):
		_tick(state)

	var ns = state.player()
	if not ns.in_government:
		_fail("a modest, sustainable budget lost re-election (approval %.1f)" % ns.overall_approval_pct)
		return
	if ns.terms_served != 1:
		_fail("terms_served is %d after one election, expected 1" % ns.terms_served)
	if ns.months_in_term != 0:
		_fail("months_in_term is %d right after an election, expected 0" % ns.months_in_term)

	for _i in range(12):
		var results := _tick(state)
		if not results.is_empty():
			_fail("an unscheduled election fired in the second term: %s" % [results])

	if ns.months_in_term != 12:
		_fail("months_in_term is %d after 12 months of a new term, expected 12" % ns.months_in_term)
	if not is_finite(ns.overall_approval_pct):
		_fail("overall approval is not finite after a second term begins: %s" % ns.overall_approval_pct)


## Same state, resolved twice, identical result — no hidden randomness.
func _check_determinism() -> void:
	var state = _new_state()
	var ns = state.player()
	var parties: Array = _loader.parties["FRA"]

	var a := Elections.resolve(ns, parties, "two_round", 0.0, "national", 2029, 6)
	var b := Elections.resolve(ns, parties, "two_round", 0.0, "national", 2029, 6)

	if a["vote_share"] != b["vote_share"]:
		_fail("determinism: vote_share differed between two resolutions of the same state")
	if a["seats"] != b["seats"]:
		_fail("determinism: seats differed between two resolutions of the same state")
	if a["incumbent_largest"] != b["incumbent_largest"]:
		_fail("determinism: incumbent_largest differed between two resolutions of the same state")


## The real tick sequence, one calendar month: Economy, Budget, Opinion, then
## Elections — the exact order main.gd's _on_month_elapsed wires.
func _tick(state) -> Array:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	Economy.tick_month(state)
	Budget.tick_month(state)
	Opinion.tick_month(state)
	return Elections.tick_month(state, _loader)


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_elections: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
