extends SceneTree

## Headless test: godot --headless --script res://tests/test_discipline.gd
## Non-zero exit on any failure.
##
## Party discipline as live state, and the seat-level rebellions it allows.
## Where a run has to be unpopular for a rebellion to appear, approval is written
## directly rather than played into -- whether a given budget regime reaches that
## approval is tools/balance_probe.gd's question, not this file's, and the answer
## is recorded in docs/discipline-model.md.
##
## The model is docs/discipline-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const DK = preload("res://src/sim/discipline_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")

const MONTHS := 168

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_every_nation_is_seeded_from_its_roster()
	_check_the_authored_figure_is_the_ceiling()
	_check_an_unpopular_government_loses_its_grip_and_gets_it_back()
	_check_an_approaching_election_costs_discipline()
	_check_discipline_stays_in_bounds_over_a_full_run()
	_check_a_perfectly_disciplined_party_never_rebels()
	_check_rebels_never_exceed_a_party_and_the_tally_still_balances()
	_check_the_opposition_never_rebels()
	_check_rebellion_is_deterministic()
	_check_rebellion_can_sink_a_bill_the_party_lines_would_pass()
	_check_forcing_a_bill_costs_discipline()
	_check_seat_level_rebels_are_not_party_level_defectors()
	_check_an_unpopular_government_can_be_censured_and_a_popular_one_cannot()
	_check_save_round_trip_preserves_discipline()

	_finish()


func _new_state(player_id := "FRA"):
	var state = GameState.new_game(_loader, player_id)
	if not state.errors.is_empty():
		_fail("new_game(%s) reported errors: %s" % [player_id, state.errors])
	state.year = 2026
	state.month = 1
	return state


## The first ORDINARY law -- both call sites force a bill via Article 49.3,
## which refuses a constitutional amendment outright (see
## docs/amendment-model.md), regardless of where data/laws/amendments.json
## happens to sort alphabetically among the law directories.
func _first_law():
	for law in _loader.laws:
		if law.id != "" and not law.constitutional:
			return law
	return null


## Approval is written straight onto every bloc and the headline. Opinion.tick
## would drag it back toward its own target within a few months, which is exactly
## what these checks want held still.
func _set_approval(ns, approval: float) -> void:
	for bloc in OpinionK.BLOC_KEYS:
		ns.bloc_approval[bloc] = approval
	ns.overall_approval_pct = approval


func _set_discipline(ns, value: float) -> void:
	for pid in ns.party_discipline:
		ns.party_discipline[pid] = value


## All ten, not just the player's -- government.gd reads discipline for every
## nation it forms a government for, and a missing entry would silently fall back
## to the authored figure and hide a seeding bug.
func _check_every_nation_is_seeded_from_its_roster() -> void:
	var state = _new_state()
	for id in state.nations.keys():
		var ns = state.nations[id]
		var roster: Array = _loader.parties.get(id, [])
		if ns.party_discipline.size() != roster.size():
			_fail("%s: seeded %d discipline entries for %d parties" % [
				id, ns.party_discipline.size(), roster.size()
			])
		for party in roster:
			if not ns.party_discipline.has(party.id):
				_fail("%s: party '%s' has no discipline entry" % [id, party.id])
			elif not is_equal_approx(float(ns.party_discipline[party.id]), party.discipline):
				_fail("%s: '%s' seeded at %.3f, authored %.3f" % [
					id, party.id, float(ns.party_discipline[party.id]), party.discipline
				])


## Content is the ceiling: nothing in the model may make a party more cohesive
## than its own file says it is, at any approval or any point in the term.
func _check_the_authored_figure_is_the_ceiling() -> void:
	var state = _new_state()
	var ns = state.player()

	for approval in [0.0, 25.0, 50.0, 75.0, 100.0]:
		_set_approval(ns, approval)
		for months_out in [0, 3, 12, 40]:
			ns.next_election_year = state.year + int(months_out / 12)
			ns.next_election_month = state.month + (months_out % 12)
			if ns.next_election_month > 12:
				ns.next_election_month -= 12
				ns.next_election_year += 1
			for party in _loader.parties["FRA"]:
				var t := Discipline.target(state, ns, party)
				if t > party.discipline + 0.0001:
					_fail("target %.3f for '%s' exceeds the authored %.3f at approval %.0f, %d months out" % [
						t, party.id, party.discipline, approval, months_out
					])
				if t < DK.DISCIPLINE_MIN - 0.0001:
					_fail("target %.3f for '%s' is below the floor %.3f" % [t, party.id, DK.DISCIPLINE_MIN])


## The arc the whole model exists for: a government that loses the country loses
## its own benches, and gets them back when it recovers.
func _check_an_unpopular_government_loses_its_grip_and_gets_it_back() -> void:
	var state = _new_state()
	var ns = state.player()
	var party = _loader.parties["FRA"][0]
	var started := Discipline.of(ns, party)

	_set_approval(ns, 15.0)
	for _i in range(24):
		Discipline.tick_month(state, _loader)
		_set_approval(ns, 15.0)  # Discipline.tick does not move approval; this is belt and braces
	var eroded := Discipline.of(ns, party)

	if eroded >= started - 0.05:
		_fail("two years at 15%% approval moved '%s' from %.3f only to %.3f" % [
			party.id, started, eroded
		])

	_set_approval(ns, 60.0)
	for _i in range(36):
		Discipline.tick_month(state, _loader)
	var recovered := Discipline.of(ns, party)

	if recovered <= eroded:
		_fail("'%s' did not recover: %.3f after three good years against %.3f at the bottom" % [
			party.id, recovered, eroded
		])
	if recovered > party.discipline + 0.0001:
		_fail("'%s' recovered past its authored ceiling: %.3f > %.3f" % [
			party.id, recovered, party.discipline
		])


## Members look to their own seats as the vote approaches, and only the
## LEGISLATIVE one -- in France the presidency is on a different clock entirely.
func _check_an_approaching_election_costs_discipline() -> void:
	var state = _new_state()
	var ns = state.player()
	var party = _loader.parties["FRA"][0]
	_set_approval(ns, OpinionK.APPROVAL_NEUTRAL)

	ns.next_election_year = state.year + 4
	ns.next_election_month = state.month
	var far := Discipline.target(state, ns, party)

	ns.next_election_year = state.year
	ns.next_election_month = state.month
	var imminent := Discipline.target(state, ns, party)

	if not is_equal_approx(far, party.discipline):
		_fail("a popular government four years from a vote does not sit at the authored figure: %.3f vs %.3f" % [
			far, party.discipline
		])
	if imminent >= far:
		_fail("an imminent election cost nothing: %.3f against %.3f four years out" % [imminent, far])


## Fourteen years of the real tick. The one stored quantity this model owns must
## never leave its bounds, and must never exceed the roster's own figure.
func _check_discipline_stays_in_bounds_over_a_full_run() -> void:
	var state = _new_state()
	var ns = state.player()
	var by_id := {}
	for party in _loader.parties["FRA"]:
		by_id[party.id] = party

	var year := 2026
	var month := 1
	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		var entry := Budget.snapshot(state)
		entry.merge(Opinion.snapshot(state))
		state.append_history(entry)
		Discipline.tick_month(state, _loader)
		Legislature.tick_month(state, _loader)
		Elections.tick_month(state, _loader)

		for pid in ns.party_discipline:
			var d := float(ns.party_discipline[pid])
			if not is_finite(d) or d < DK.DISCIPLINE_MIN - 0.0001 or d > 1.0:
				_fail("month %d: '%s' discipline is %s, outside [%.2f, 1.0]" % [
					i, pid, d, DK.DISCIPLINE_MIN
				])
				return
			if by_id.has(pid) and d > by_id[pid].discipline + 0.0001:
				_fail("month %d: '%s' at %.3f, past its authored %.3f" % [
					i, pid, d, by_id[pid].discipline
				])
				return


## The (1 - discipline) factor has to be the whole story at the top of the range:
## a party that delivers every seat delivers every seat.
func _check_a_perfectly_disciplined_party_never_rebels() -> void:
	var state = _new_state()
	var ns = state.player()
	_set_discipline(ns, 1.0)

	for law in _loader.laws:
		var result := Legislature.resolve_vote(ns, _loader.parties["FRA"], law)
		if not result["party_rebels"].is_empty():
			_fail("a perfectly disciplined assembly rebelled on '%s': %s" % [
				law.id, result["party_rebels"]
			])
			return


## Seats are conserved. A split moves seats between columns; it may never create
## or destroy one, at any discipline and on any law.
func _check_rebels_never_exceed_a_party_and_the_tally_still_balances() -> void:
	var state = _new_state()
	var ns = state.player()

	for discipline in [1.0, 0.7, 0.4, DK.DISCIPLINE_MIN]:
		_set_discipline(ns, discipline)
		for law in _loader.laws:
			var result := Legislature.resolve_vote(ns, _loader.parties["FRA"], law)
			var total: int = int(result["yes_seats"]) + int(result["no_seats"]) + int(result["abstain_seats"])
			if total != ns.assembly_seats:
				_fail("discipline %.2f, law '%s': tally sums to %d, not %d" % [
					discipline, law.id, total, ns.assembly_seats
				])
				return
			for pid in result["party_rebels"]:
				var rebels: int = int(result["party_rebels"][pid])
				var seats: int = int(ns.seats_by_party.get(pid, 0))
				if rebels < 0 or rebels > seats:
					_fail("discipline %.2f, law '%s': '%s' rebelled with %d of %d seats" % [
						discipline, law.id, pid, rebels, seats
					])
					return


## The model's own claim, asserted rather than left in a comment: nothing pulls
## an opposition party's members away from where they already stand, so there is
## no strain and no rebellion. Holds at every discipline, including the floor.
func _check_the_opposition_never_rebels() -> void:
	var state = _new_state()
	var ns = state.player()

	for discipline in [0.9, 0.5, DK.DISCIPLINE_MIN]:
		_set_discipline(ns, discipline)
		for law in _loader.laws:
			var result := Legislature.resolve_vote(ns, _loader.parties["FRA"], law)
			for pid in result["party_rebels"]:
				if not ns.coalition_party_ids.has(pid):
					_fail("opposition party '%s' rebelled on '%s' at discipline %.2f" % [
						pid, law.id, discipline
					])
					return


## Same state, resolved twice, identical result — no hidden randomness, the rule
## every other module in src/sim/ keeps.
func _check_rebellion_is_deterministic() -> void:
	var state = _new_state()
	var ns = state.player()
	_set_discipline(ns, 0.35)
	var law = _first_law()

	var a := Legislature.resolve_vote(ns, _loader.parties["FRA"], law)
	var b := Legislature.resolve_vote(ns, _loader.parties["FRA"], law)
	for key in ["passed", "yes_seats", "no_seats", "abstain_seats", "party_rebels"]:
		if a[key] != b[key]:
			_fail("determinism: '%s' differed between two resolutions of the same state" % key)


## The point of the whole block, stated as the player would: a majority on paper
## is not a majority in the chamber. Somewhere in the roster there has to be a
## bill the party lines carry and the actual division rejects.
##
## An existence claim, deliberately. Which bill and at what discipline depends on
## content that a balance pass may legitimately move; that the case exists at all
## is the model working, and is what a constants edit must not quietly remove.
func _check_rebellion_can_sink_a_bill_the_party_lines_would_pass() -> void:
	var state = _new_state()
	var ns = state.player()

	for discipline in [0.8, 0.6, 0.5, 0.4, 0.3, 0.2, DK.DISCIPLINE_MIN]:
		_set_discipline(ns, discipline)
		for law in _loader.laws:
			var result := Legislature.resolve_vote(ns, _loader.parties["FRA"], law)
			if result["passed"] or result["party_rebels"].is_empty():
				continue
			if _passes_on_party_lines(ns, result, law):
				return  # found one; that is the claim

	_fail("no bill in the roster is carried by the party lines and rejected by the division")


## The tally the same vote would have produced with every seat behind its party's
## line -- V1.1a's whole-bloc arithmetic, computed from the result rather than by
## a second resolver, so the two cannot drift.
func _passes_on_party_lines(ns, result: Dictionary, law) -> bool:
	var yes := 0
	var no := 0
	for party in _loader.parties["FRA"]:
		var seats: int = int(ns.seats_by_party.get(party.id, 0))
		match result["party_votes"].get(party.id, "abstain"):
			"yes": yes += seats
			"no": no += seats
	match law.majority:
		"simple": return yes > no
		"absolute": return float(yes) > 0.5 * float(ns.assembly_seats)
		"amendment": return float(yes) >= LK.AMENDMENT_RULE_FRACTIONS.get(ns.amendment_rule, 2.0 / 3.0) * float(ns.assembly_seats)
		_: return float(yes) >= (2.0 / 3.0) * float(ns.assembly_seats)


## The second price of Article 49.3, and the one paid in the chamber. Going over
## your own majority's head must cost you that majority's willingness.
func _check_forcing_a_bill_costs_discipline() -> void:
	var state = _new_state()
	var ns = state.player()
	var before := {}
	for pid in ns.coalition_party_ids:
		before[pid] = float(ns.party_discipline[pid])

	Legislature.propose(state, _loader, _first_law(), true)

	for pid in before:
		if float(ns.party_discipline[pid]) >= float(before[pid]):
			_fail("'%s' discipline is %.3f after a 49.3, was %.3f — forcing cost it nothing" % [
				pid, float(ns.party_discipline[pid]), float(before[pid])
			])


## A party whose line held has not defected, however many of its members walked.
## Expulsion is an act of the party, not of its backbenchers.
func _check_seat_level_rebels_are_not_party_level_defectors() -> void:
	var state = _new_state()
	var ns = state.player()
	_set_approval(ns, 30.0)
	_set_discipline(ns, 0.55)

	var censure := Government.resolve_censure(ns, _loader.parties["FRA"], true)
	var found_split := false
	for pid in censure["party_rebels"]:
		if not ns.coalition_party_ids.has(pid):
			continue
		found_split = true
		if censure["party_votes"].get(pid, "") == "against" and censure["defectors"].has(pid):
			_fail("'%s' voted against censure but was recorded as a defector" % pid)

	if not found_split:
		_fail("no coalition party split on a censure motion at 30%% approval and 0.55 discipline")


## The balance goal V1.1b was tuned against, asserted so a future constants edit
## cannot quietly undo it: an unpopular government that forces a bill can be
## brought down, and a popular one on the same assembly cannot.
func _check_an_unpopular_government_can_be_censured_and_a_popular_one_cannot() -> void:
	var popular = _new_state()
	_set_approval(popular.player(), 55.0)
	var held := Government.resolve_censure(popular.player(), _loader.parties["FRA"], true)
	if held["carried"]:
		_fail("a government at 55%% approval was censured after a forced bill: %d of %d" % [
			held["for_seats"], held["threshold"]
		])

	var unpopular = _new_state()
	var ns = unpopular.player()
	_set_approval(ns, 15.0)
	# Two years of erosion at that approval, through the real tick.
	for _i in range(24):
		Discipline.tick_month(unpopular, _loader)
		_set_approval(ns, 15.0)

	var fell := Government.resolve_censure(ns, _loader.parties["FRA"], true)
	if not fell["carried"]:
		_fail("a government at 15%% approval with two years of eroded discipline survived a 49.3: %d of %d" % [
			fell["for_seats"], fell["threshold"]
		])


func _check_save_round_trip_preserves_discipline() -> void:
	var state = _new_state()
	var ns = state.player()
	_set_approval(ns, 20.0)
	for _i in range(12):
		Discipline.tick_month(state, _loader)
		_set_approval(ns, 20.0)

	var round_tripped = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	if round_tripped.party_discipline.size() != ns.party_discipline.size():
		_fail("discipline table changed size over a save: %d against %d" % [
			round_tripped.party_discipline.size(), ns.party_discipline.size()
		])
		return
	for pid in ns.party_discipline:
		if not is_equal_approx(float(round_tripped.party_discipline.get(pid, -1.0)), float(ns.party_discipline[pid])):
			_fail("'%s' discipline changed from %.4f to %.4f over a save" % [
				pid, float(ns.party_discipline[pid]), float(round_tripped.party_discipline.get(pid, -1.0))
			])

	# And the copy the budget projection runs on must not share the dictionary.
	var copy = ns.duplicate_state()
	copy.party_discipline[ns.party_discipline.keys()[0]] = 0.123
	if is_equal_approx(float(ns.party_discipline[ns.party_discipline.keys()[0]]), 0.123):
		_fail("duplicate_state() shared the discipline dictionary instead of copying it")


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_discipline: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
