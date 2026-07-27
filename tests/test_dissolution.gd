extends SceneTree

## Headless test: godot --headless --script res://tests/test_dissolution.gd
## Non-zero exit on any failure.
##
## Dissolution and snap elections -- who may call one, what it costs, and that
## the resulting election is a real one that resolves. Section 1's measurement
## (a 57-seat spread in what a snap returns between the worst and best approval
## a player can hold while still in office) found the gamble already resolves
## without touching the election model, so this file checks the plumbing:
## the rule dispatch, the lockout, the blackout, and that a snap election is
## indistinguishable from a scheduled one except for its "snap" flag.
##
## The model is docs/dissolution-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Elections = preload("res://src/sim/elections.gd")
const Government = preload("res://src/sim/government.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const DK = preload("res://src/sim/dissolution_constants.gd")

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_every_nation_has_a_recognised_rule()
	_check_switzerland_can_never_dissolve()
	_check_confidence_failure_and_self_dissolution_refuse()
	_check_a_dissolution_moves_only_the_legislative_clock()
	_check_the_lockout_blocks_counts_down_and_expires()
	_check_the_blackout_refuses_a_dissolution_too_close_to_the_scheduled_vote()
	_check_a_snap_election_resolves_and_reads_as_one()
	_check_seats_are_conserved_and_two_resolutions_agree()
	_check_dissolving_while_pending_is_refused()
	_check_save_round_trip_preserves_dissolution_state()

	_finish()


func _new_state(player_id := "FRA"):
	var state = GameState.new_game(_loader, player_id)
	if not state.errors.is_empty():
		_fail("new_game(%s) reported errors: %s" % [player_id, state.errors])
	state.year = 2026
	state.month = 1
	return state


## Every nation the loader carries resolved to one of Nation.KNOWN_DISSOLUTION_RULES
## -- checked again here rather than only in test_data.gd, because this file is
## where a reader looks to understand what the rule actually does.
func _check_every_nation_has_a_recognised_rule() -> void:
	var known := ["executive_discretion", "confidence_failure", "head_of_state_limited", "self_dissolution", "none"]
	for id in _loader.nations.keys():
		var n = _loader.nations[id]
		if not known.has(n.dissolution_rule):
			_fail("%s: dissolution_rule '%s' is not recognised" % [id, n.dissolution_rule])


## Switzerland's Federal Council cannot dissolve the Nationalrat under any
## circumstance -- the same "fails safe" shape censure_rule "none" uses.
func _check_switzerland_can_never_dissolve() -> void:
	var state = _new_state("CHE")
	var ns = state.player()
	if ns.dissolution_rule != "none":
		_fail("CHE dissolution_rule is '%s', expected 'none'" % ns.dissolution_rule)
	if Dissolution.can_dissolve(state, ns):
		_fail("can_dissolve() returned true for Switzerland")
	if Dissolution.refusal_reason(state, ns).is_empty():
		_fail("refusal_reason() gave no reason for Switzerland")


## No confidence-vote command exists at V1.1c, so confidence_failure (Germany,
## Belgium) refuses the player's command outright rather than half-model it.
## self_dissolution (Austria) is the chamber's own act, not the executive's, so
## it refuses for the same reason.
func _check_confidence_failure_and_self_dissolution_refuse() -> void:
	for id_and_rule in [["DEU", "confidence_failure"], ["BEL", "confidence_failure"], ["AUT", "self_dissolution"]]:
		var id: String = id_and_rule[0]
		var expected_rule: String = id_and_rule[1]
		var state = _new_state(id)
		var ns = state.player()
		if ns.dissolution_rule != expected_rule:
			_fail("%s dissolution_rule is '%s', expected '%s'" % [id, ns.dissolution_rule, expected_rule])
		if Dissolution.can_dissolve(state, ns):
			_fail("can_dissolve() returned true for %s under '%s'" % [id, ns.dissolution_rule])
		Dissolution.dissolve(state, ns)
		if ns.dissolution_pending:
			_fail("dissolve() set dissolution_pending on %s despite its rule refusing" % id)


## France: executive_discretion, no lockout at new-game, the scheduled election
## (June 2029) is nowhere near the blackout window. Calling it must move
## next_election_year/month by exactly notice_months and touch nothing else --
## the executive's own clock (May 2027) survives untouched, which is what makes
## a French dissolution cost the Assembly and nothing else.
func _check_a_dissolution_moves_only_the_legislative_clock() -> void:
	var state = _new_state("FRA")
	var ns = state.player()

	var before_exec_year: int = ns.next_executive_year
	var before_exec_month: int = ns.next_executive_month
	var before_term_months: int = ns.term_months
	var before_months_in_term: int = ns.months_in_term
	var before_approval: float = ns.overall_approval_pct

	if not Dissolution.can_dissolve(state, ns):
		_fail("can_dissolve() returned false for FRA at new-game: %s" % Dissolution.refusal_reason(state, ns))
		return

	Dissolution.dissolve(state, ns)

	if not ns.dissolution_pending:
		_fail("dissolve() did not set dissolution_pending")
	if ns.dissolutions_called != 1:
		_fail("dissolutions_called is %d, expected 1" % ns.dissolutions_called)
	if ns.last_dissolution.is_empty():
		_fail("last_dissolution was not recorded")

	var expected_total: int = 2026 * 12 + 0 + int(ns.dissolution_notice_months)  # month 1 -> zero-indexed 0
	var expected_year: int = int(expected_total / 12)
	var expected_month: int = expected_total % 12 + 1
	if ns.next_election_year != expected_year or ns.next_election_month != expected_month:
		_fail("dissolve() moved the election to %d-%02d, expected %d-%02d (notice_months=%d)" % [
			ns.next_election_year, ns.next_election_month, expected_year, expected_month, ns.dissolution_notice_months
		])

	if ns.next_executive_year != before_exec_year or ns.next_executive_month != before_exec_month:
		_fail("dissolve() moved the executive's own clock -- it must not")
	if ns.term_months != before_term_months:
		_fail("dissolve() changed term_months from %d to %d" % [before_term_months, ns.term_months])
	if ns.months_in_term != before_months_in_term:
		_fail("dissolve() changed months_in_term from %d to %d" % [before_months_in_term, ns.months_in_term])

	# The cost lands through the same accumulator 49.3 and a fallen government
	# already move -- through the target opinion.gd would tick toward, not a
	# jump in overall_approval_pct itself the same month.
	if not is_equal_approx(ns.overall_approval_pct, before_approval):
		_fail("dissolve() moved overall_approval_pct directly, bypassing inertia: %.2f -> %.2f" % [
			before_approval, ns.overall_approval_pct
		])


## Once the snap resolves, the lockout counts down from dissolution_lockout_months
## and dissolving is refused until it reaches zero.
func _check_the_lockout_blocks_counts_down_and_expires() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])

	Dissolution.dissolve(state, ns)
	_advance_to_snap(state, ns, party_list)

	if ns.dissolution_lockout_remaining != ns.dissolution_lockout_months:
		_fail("lockout did not seed to dissolution_lockout_months (%d) after the snap resolved, got %d" % [
			ns.dissolution_lockout_months, ns.dissolution_lockout_remaining
		])
	if Dissolution.can_dissolve(state, ns):
		_fail("can_dissolve() returned true while the lockout is active")

	for _i in range(ns.dissolution_lockout_months - 1):
		Dissolution.tick_month(state)
	if ns.dissolution_lockout_remaining != 1:
		_fail("lockout remaining is %d one tick before expiry, expected 1" % ns.dissolution_lockout_remaining)
	if Dissolution.can_dissolve(state, ns):
		_fail("can_dissolve() returned true with one month of lockout left")

	Dissolution.tick_month(state)
	if ns.dissolution_lockout_remaining != 0:
		_fail("lockout did not reach zero: %d" % ns.dissolution_lockout_remaining)


## No dissolution within DISSOLUTION_BLACKOUT_MONTHS of an already-scheduled
## legislative election -- without it, dissolving one month early is a free
## reroll of a vote that was coming anyway.
func _check_the_blackout_refuses_a_dissolution_too_close_to_the_scheduled_vote() -> void:
	var state = _new_state("FRA")
	var ns = state.player()

	ns.next_election_year = state.year
	ns.next_election_month = state.month + DK.DISSOLUTION_BLACKOUT_MONTHS - 1
	if Dissolution.can_dissolve(state, ns):
		_fail("can_dissolve() returned true one month inside the blackout window")
	if not Dissolution.refusal_reason(state, ns).contains("close"):
		_fail("refusal_reason() inside the blackout does not mention the scheduled election: %s" % Dissolution.refusal_reason(state, ns))

	ns.next_election_month = state.month + DK.DISSOLUTION_BLACKOUT_MONTHS
	if not Dissolution.can_dissolve(state, ns):
		_fail("can_dissolve() returned false exactly at the blackout boundary")


## A snap election resolves through the same Elections.resolve()/Government.form()
## path a scheduled one does -- it seats an assembly, forms a government, clears
## the censure bar, and is distinguishable from a scheduled election only by its
## "snap" flag.
func _check_a_snap_election_resolves_and_reads_as_one() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])

	ns.censure_barred_party_ids = ["renouveau_civique"]
	Dissolution.dissolve(state, ns)
	var result = _advance_to_snap(state, ns, party_list)

	if result == null:
		_fail("dissolving did not produce a legislative result by its scheduled date")
		return
	if not bool(result.get("snap", false)):
		_fail("a dissolved election's result did not carry snap = true")
	if ns.coalition_seats <= 0:
		_fail("no government formed after the snap election")
	if not ns.censure_barred_party_ids.is_empty():
		_fail("censure_barred_party_ids was not cleared by the snap election")

	# A scheduled election (no dissolution pending) must read snap = false, so
	# the result screen does not call every election a snap.
	var scheduled = _new_state("FRA")
	var sns = scheduled.player()
	scheduled.year = sns.next_election_year
	scheduled.month = sns.next_election_month
	for r in Elections.tick_month(scheduled, _loader):
		if r["kind"] == "national" and bool(r.get("snap", false)):
			_fail("a scheduled election read snap = true")


## Elections.resolve() and Government.form() are pure and deterministic, so two
## resolutions of the same dissolved state must agree exactly, and no seats can
## appear or vanish in the process -- the same guarantee every other module in
## src/sim/ keeps.
func _check_seats_are_conserved_and_two_resolutions_agree() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])

	Dissolution.dissolve(state, ns)
	var result_a = _advance_to_snap(state, ns, party_list)
	if result_a == null:
		_fail("dissolving did not produce a legislative result")
		return

	var total_seats := 0
	for pid in result_a["seats"]:
		total_seats += int(result_a["seats"][pid])
	if total_seats != ns.assembly_seats:
		_fail("snap election seats sum to %d, expected %d" % [total_seats, ns.assembly_seats])

	var state_b = _new_state("FRA")
	var ns_b = state_b.player()
	Dissolution.dissolve(state_b, ns_b)
	var result_b = _advance_to_snap(state_b, ns_b, party_list)
	if result_b == null or result_b["seats"] != result_a["seats"]:
		_fail("two resolutions of the same dissolved state disagree on seats")


## Calling dissolve() again before the pending snap has resolved must refuse --
## a second command cannot move an election that has already been moved.
func _check_dissolving_while_pending_is_refused() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	Dissolution.dissolve(state, ns)
	var pending_year: int = ns.next_election_year
	var pending_month: int = ns.next_election_month

	if Dissolution.can_dissolve(state, ns):
		_fail("can_dissolve() returned true while a dissolution is already pending")
	Dissolution.dissolve(state, ns)
	if ns.next_election_year != pending_year or ns.next_election_month != pending_month:
		_fail("a second dissolve() call while one was pending moved the election again")
	if ns.dissolutions_called != 1:
		_fail("dissolutions_called is %d after one refused repeat call, expected 1" % ns.dissolutions_called)


func _check_save_round_trip_preserves_dissolution_state() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	Dissolution.dissolve(state, ns)
	ns.dissolution_lockout_remaining = 7

	var round_tripped = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	for field in ["dissolution_rule", "dissolution_lockout_months", "dissolution_notice_months",
			"dissolution_lockout_remaining", "dissolution_pending", "dissolutions_called"]:
		if round_tripped.get(field) != ns.get(field):
			_fail("%s changed from %s to %s over a save" % [field, ns.get(field), round_tripped.get(field)])
	# JSON has one numeric type, so year/month round-trip as float -- compare by
	# value, the same tolerance nation_state.gd's from_dict() documents.
	if int(round_tripped.last_dissolution.get("year", -1)) != int(ns.last_dissolution.get("year", -2)) or \
			int(round_tripped.last_dissolution.get("month", -1)) != int(ns.last_dissolution.get("month", -2)):
		_fail("last_dissolution changed from %s to %s over a save" % [ns.last_dissolution, round_tripped.last_dissolution])


## Ticks a state forward, month by month, until the pending dissolution's
## scheduled election fires (or a safety cap is hit), returning its national
## result. Exercises the real tick order -- Dissolution before Elections --
## rather than jumping the date directly.
func _advance_to_snap(state, ns, party_list: Array):
	for _i in range(24):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Dissolution.tick_month(state)
		for r in Elections.tick_month(state, _loader):
			if r["kind"] == "national":
				return r
	return null


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_dissolution: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
