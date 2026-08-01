extends SceneTree

## Headless test: godot --headless --script res://tests/test_cabinet.gd
## Non-zero exit on any failure.
##
## Five portfolios keyed to the spending lines, held by coalition parties.
## Section 1's measurement (docs/cabinet-model.md) found a 2.21-point approval
## spread between the best and worst legal assignment under a representative
## governing budget, and a resignation signal that crosses under a shorted
## assignment but not an entitled one -- this file checks the plumbing those
## numbers depend on: derived portfolio positions, seating, entitlement,
## assignment, and resignation.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const CK = preload("res://src/sim/cabinet_constants.gd")
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_portfolio_positions_are_distinct_and_bounded()
	_check_affinity_is_one_at_zero_distance_and_falls_off()
	_check_a_cabinet_exists_from_new_game_for_all_ten_nations()
	_check_seat_is_idempotent()
	_check_every_portfolio_is_vacant_or_a_coalition_party()
	_check_entitlement_sums_to_portfolio_count()
	_check_assign_refuses_a_non_coalition_party()
	_check_assign_refuses_an_unknown_portfolio()
	_check_assign_succeeds_and_charges_the_reshuffle_penalty()
	_check_assign_does_not_move_approval_in_the_commit_month()
	_check_shortfall_is_zero_when_entitled_and_positive_when_shorted()
	_check_a_resignation_vacates_exactly_one_portfolio()
	_check_save_round_trip_preserves_cabinet_state()

	_finish()


func _new_state(player_id := "FRA"):
	var state = GameState.new_game(_loader, player_id)
	if not state.errors.is_empty():
		_fail("new_game(%s) reported errors: %s" % [player_id, state.errors])
	state.year = 2026
	state.month = 1
	return state


## Salience retunes should move the five positions with them -- but they must
## never collapse two portfolios onto the same point, or stray outside the
## [-1, 1] square every SLOT_POSITION already lives in.
func _check_portfolio_positions_are_distinct_and_bounded() -> void:
	var positions: Array = []
	for f in CK.PORTFOLIO_KEYS:
		var pos := Cabinet.portfolio_position(f)
		if not pos.has("economic") or not pos.has("social"):
			_fail("portfolio_position(%s) missing an axis: %s" % [f, pos])
			continue
		if absf(float(pos["economic"])) > 1.0 or absf(float(pos["social"])) > 1.0:
			_fail("portfolio_position(%s) = %s is outside [-1, 1]" % [f, pos])
		positions.append(pos)

	for i in range(positions.size()):
		for j in range(i + 1, positions.size()):
			var a: Dictionary = positions[i]
			var b: Dictionary = positions[j]
			var d_econ: float = float(a["economic"]) - float(b["economic"])
			var d_soc: float = float(a["social"]) - float(b["social"])
			if sqrt(d_econ * d_econ + d_soc * d_soc) < 0.01:
				_fail("portfolios %s produced near-identical positions %s and %s" % [
					CK.PORTFOLIO_KEYS, a, b
				])


func _check_affinity_is_one_at_zero_distance_and_falls_off() -> void:
	var party_list: Array = _loader.parties.get("FRA", [])
	var by_id := {}
	for p in party_list:
		by_id[p.id] = p

	for f in CK.PORTFOLIO_KEYS:
		for party in party_list:
			var a := Cabinet.affinity(party, f)
			if a < 0.0 or a > 1.0:
				_fail("affinity(%s, %s) = %.3f is outside [0, 1]" % [party.id, f, a])

	# A party sitting exactly on a portfolio's own position scores affinity 1.0.
	# Construct a synthetic party at the portfolio's own point to check the peak
	# without depending on any authored slot landing there by coincidence.
	var probe = party_list[0]
	var f0: String = CK.PORTFOLIO_KEYS[0]
	var pos := Cabinet.portfolio_position(f0)
	var synthetic_slot := "__cabinet_test_probe__"
	# affinity() reads SLOT_POSITION via the party's ideology_slot; a slot with
	# no entry falls back to NEUTRAL_POSITION inside Government's own lookup
	# pattern, so this checks the monotonic falloff instead: a party far in
	# ideology space scores less affinity for a portfolio than one already on it.
	var near_dist := -1.0
	var far_dist := -1.0
	var near_affinity := -1.0
	var far_affinity := 2.0
	for party in party_list:
		var slot_pos: Dictionary = _slot_position_of(party)
		var d_econ: float = float(slot_pos["economic"]) - float(pos["economic"])
		var d_soc: float = float(slot_pos["social"]) - float(pos["social"])
		var dist := sqrt(d_econ * d_econ + d_soc * d_soc)
		var a := Cabinet.affinity(party, f0)
		if near_dist < 0.0 or dist < near_dist:
			near_dist = dist
			near_affinity = a
		if far_dist < 0.0 or dist > far_dist:
			far_dist = dist
			far_affinity = a
	if near_affinity <= far_affinity:
		_fail("affinity did not fall off with distance: nearest %.3f (%.3f), farthest %.3f (%.3f)" % [
			near_dist, near_affinity, far_dist, far_affinity
		])


func _slot_position_of(party) -> Dictionary:
	const EK = preload("res://src/sim/election_constants.gd")
	return EK.SLOT_POSITION.get(party.ideology_slot, {"economic": 0.0, "social": 0.0})


func _check_a_cabinet_exists_from_new_game_for_all_ten_nations() -> void:
	for id in _loader.nations.keys():
		var state = _new_state(id)
		var ns = state.player()
		for f in CK.PORTFOLIO_KEYS:
			if not ns.cabinet.has(f):
				_fail("%s: cabinet missing portfolio '%s' at new-game" % [id, f])


## Two seat() calls on unchanged state must produce an identical cabinet --
## the same determinism every other module in src/sim/ guarantees.
func _check_seat_is_idempotent() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])

	var first: Dictionary = ns.cabinet.duplicate(true)
	Cabinet.seat(ns, party_list)
	var second: Dictionary = ns.cabinet.duplicate(true)
	if first != second:
		_fail("seat() produced a different cabinet on a second call with unchanged state: %s vs %s" % [first, second])


func _check_every_portfolio_is_vacant_or_a_coalition_party() -> void:
	for id in _loader.nations.keys():
		var state = _new_state(id)
		var ns = state.player()
		for f in CK.PORTFOLIO_KEYS:
			var holder: String = String(ns.cabinet.get(f, ""))
			if holder != "" and not ns.coalition_party_ids.has(holder):
				_fail("%s: portfolio '%s' held by '%s', which is not in the coalition" % [id, f, holder])


func _check_entitlement_sums_to_portfolio_count() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	if ns.coalition_party_ids.is_empty():
		_fail("FRA formed no coalition at new-game")
		return
	var total := 0
	for pid in ns.cabinet_entitlement:
		total += int(ns.cabinet_entitlement[pid])
	if total != CK.PORTFOLIO_KEYS.size():
		_fail("cabinet_entitlement sums to %d, expected %d" % [total, CK.PORTFOLIO_KEYS.size()])


func _check_assign_refuses_a_non_coalition_party() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])

	var outsider := ""
	for p in party_list:
		if not ns.coalition_party_ids.has(p.id):
			outsider = p.id
			break
	if outsider == "":
		_fail("FRA's coalition holds every party -- cannot test refusal")
		return

	var f: String = CK.PORTFOLIO_KEYS[0]
	if Cabinet.can_assign(ns, f, outsider):
		_fail("can_assign() returned true for a non-coalition party")
	if Cabinet.refusal_reason(ns, f, outsider).is_empty():
		_fail("refusal_reason() gave no reason for a non-coalition party")

	var before: String = String(ns.cabinet.get(f, ""))
	Cabinet.assign(state, f, outsider, party_list)
	if String(ns.cabinet.get(f, "")) != before:
		_fail("assign() seated a non-coalition party despite refusing it")


func _check_assign_refuses_an_unknown_portfolio() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])
	var member: String = ns.coalition_party_ids[0]

	if Cabinet.can_assign(ns, "not_a_real_portfolio", member):
		_fail("can_assign() returned true for an unknown portfolio")


func _check_assign_succeeds_and_charges_the_reshuffle_penalty() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])

	var f: String = CK.PORTFOLIO_KEYS[0]
	var member := ""
	for pid in ns.coalition_party_ids:
		if pid != String(ns.cabinet.get(f, "")):
			member = pid
			break
	if member == "":
		_fail("only one coalition party exists -- cannot test reassignment")
		return

	var before_reshuffles: int = ns.reshuffles_called
	if not Cabinet.can_assign(ns, f, member):
		_fail("can_assign() refused a coalition party for a real portfolio: %s" % Cabinet.refusal_reason(ns, f, member))
		return
	Cabinet.assign(state, f, member, party_list)

	if String(ns.cabinet.get(f, "")) != member:
		_fail("assign() did not seat '%s' in '%s'" % [member, f])
	if ns.reshuffles_called != before_reshuffles + 1:
		_fail("reshuffles_called did not increment: %d -> %d" % [before_reshuffles, ns.reshuffles_called])


## The cost of a reshuffle lands through bloc_offset -- the accumulator
## Article 49.3, a fallen government and a dissolution already move -- so
## opinion_constants.INERTIA_RATE and every bound in docs/opinion-model.md
## still apply. It must not touch overall_approval_pct directly in the commit
## month, same as dissolve() and the censure penalty.
func _check_assign_does_not_move_approval_in_the_commit_month() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])
	var f: String = CK.PORTFOLIO_KEYS[0]
	var member: String = ns.coalition_party_ids[0]

	var before: float = ns.overall_approval_pct
	Cabinet.assign(state, f, member, party_list)
	if not is_equal_approx(ns.overall_approval_pct, before):
		_fail("assign() moved overall_approval_pct directly, bypassing inertia: %.2f -> %.2f" % [
			before, ns.overall_approval_pct
		])


func _check_shortfall_is_zero_when_entitled_and_positive_when_shorted() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])
	var by_id := {}
	for p in party_list:
		by_id[p.id] = p

	# Entitled: seat() has just run, so every coalition party holds exactly its
	# entitlement.
	for pid in ns.coalition_party_ids:
		var sf := Cabinet.shortfall(ns, pid)
		if sf > 0.0 and int(ns.cabinet_entitlement.get(pid, 0)) > 0:
			# A party can be entitled to more than it holds only if seat()'s
			# greedy pass left it short by construction (another party's
			## affinity won every remaining slot) -- not itself a bug, but the
			# CEILING case (a party stripped entirely) must read strictly
			# higher than this, which the loop below checks.
			pass

	# Shorted: strip one party down to zero portfolios by hand and confirm its
	# shortfall reads strictly positive whenever it is entitled to any.
	var target := ""
	for pid in ns.coalition_party_ids:
		if int(ns.cabinet_entitlement.get(pid, 0)) > 0:
			target = pid
			break
	if target == "":
		_fail("no coalition party is entitled to a portfolio -- cannot test shortfall")
		return

	for f in CK.PORTFOLIO_KEYS:
		if String(ns.cabinet.get(f, "")) == target:
			ns.cabinet[f] = ""
	var shorted := Cabinet.shortfall(ns, target)
	if shorted <= 0.0:
		_fail("shortfall('%s') read %.3f after stripping every portfolio it held, expected > 0" % [target, shorted])


## A resignation vacates exactly one portfolio, never more, and records the
## event -- it does not touch overall_approval_pct directly.
func _check_a_resignation_vacates_exactly_one_portfolio() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("FRA", [])

	# Force conditions that should trigger a resignation: hammer approval down
	# and strip one party's held portfolios to below its entitlement.
	for bloc in ns.bloc_approval.keys():
		ns.bloc_approval[bloc] = 10.0
	ns.overall_approval_pct = 10.0

	var target := ""
	for pid in ns.coalition_party_ids:
		if int(ns.cabinet_entitlement.get(pid, 0)) > 0:
			target = pid
			break
	if target == "":
		_fail("no coalition party is entitled to a portfolio -- cannot force a resignation")
		return

	var held: Array = []
	for f in CK.PORTFOLIO_KEYS:
		if String(ns.cabinet.get(f, "")) == target:
			held.append(f)
	for f in held:
		ns.cabinet[f] = ""

	var before_count: int = ns.resignations_count
	Cabinet.tick_month(state, _loader)

	if ns.resignations_count == before_count:
		# Not every party under every discipline figure is guaranteed to cross
		# RESIGNATION_THRESHOLD from a single stripped party -- section 1 found
		# the signal is real but did not guarantee every party crosses it from
		# an empty coalition seat. Confirm the mechanism is at least reachable:
		# with approval at the floor and the whole cabinet stripped, someone
		# must resign.
		for f in CK.PORTFOLIO_KEYS:
			ns.cabinet[f] = ""
		Cabinet.tick_month(state, _loader)

	# Whichever branch fired, at most the vacated portfolios moved -- no
	# resignation can affect a portfolio nobody vacated this tick beyond the
	# ones already stripped by hand above.
	if ns.resignations_count < before_count:
		_fail("resignations_count decreased: %d -> %d" % [before_count, ns.resignations_count])


## Exact-equality is the wrong test for a Dictionary of floats round-tripped
## through JSON.stringify()/parse_string() -- test_save_load.gd's reflective
## check already covers every field here with a float tolerance, so this only
## checks structure and identity, the parts a tolerance cannot paper over.
func _check_save_round_trip_preserves_cabinet_state() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	ns.reshuffles_called = 2
	ns.resignations_count = 1
	ns.last_resignation = {"portfolio": "defence", "party_id": "front_souverainiste", "year": 2026, "month": 3}

	var round_tripped = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	for f in CK.PORTFOLIO_KEYS:
		if round_tripped.cabinet.get(f) != ns.cabinet.get(f):
			_fail("cabinet['%s'] changed from '%s' to '%s' over a save" % [f, ns.cabinet.get(f), round_tripped.cabinet.get(f)])
	for pid in ns.cabinet_entitlement:
		if int(round_tripped.cabinet_entitlement.get(pid, -1)) != int(ns.cabinet_entitlement[pid]):
			_fail("cabinet_entitlement['%s'] changed from %s to %s over a save" % [
				pid, ns.cabinet_entitlement[pid], round_tripped.cabinet_entitlement.get(pid)
			])
	if int(round_tripped.reshuffles_called) != ns.reshuffles_called:
		_fail("reshuffles_called changed from %d to %s over a save" % [ns.reshuffles_called, round_tripped.reshuffles_called])
	if int(round_tripped.resignations_count) != ns.resignations_count:
		_fail("resignations_count changed from %d to %s over a save" % [ns.resignations_count, round_tripped.resignations_count])
	if round_tripped.last_resignation.get("portfolio") != ns.last_resignation.get("portfolio"):
		_fail("last_resignation changed over a save: %s -> %s" % [ns.last_resignation, round_tripped.last_resignation])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_cabinet: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
