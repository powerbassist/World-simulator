extends SceneTree

## Headless test: godot --headless --script res://tests/test_government.gd
## Non-zero exit on any failure.
##
## Nothing here asserts that the formula implies an outcome — every check builds
## a real GameState or runs the real tick sequence and reads what actually
## happened, the same discipline test_elections.gd and test_balance.gd keep.
##
## The model is docs/government-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const GK = preload("res://src/sim/government_constants.gd")

const ALL_IDS := ["AUT", "BEL", "CHE", "DEU", "ESP", "FRA", "GBR", "ITA", "LUX", "NLD"]

const GAME_START_YEAR := 2026
const EXEC_TARGET_MONTHS := 16   # January 2026 to May 2027.
const LEG_TARGET_MONTHS := 41    # January 2026 to June 2029.

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_every_nation_forms_a_government()
	_check_cordons_are_never_crossed()
	_check_partners_stay_within_the_distance_cap()
	_check_coalition_position_is_bounded_and_weighted()
	_check_censure_threshold_matches_the_authored_rule()
	_check_france_needs_three_parties()
	_check_formation_is_deterministic()
	_check_cohabitation_is_reachable()
	_check_coalition_bonus_is_earned_not_given()
	_check_legislative_election_reforms_without_ending_the_term()
	_check_government_stays_coherent_over_fourteen_years()
	_check_save_round_trip_preserves_the_government()

	_finish()


func _new_state(player_id := "FRA"):
	var state = GameState.new_game(_loader, player_id)
	if not state.errors.is_empty():
		_fail("new_game(%s) reported errors: %s" % [player_id, state.errors])
	state.year = GAME_START_YEAR
	state.month = 1
	return state


## Every one of the ten assembles a government at new-game, names a head of
## government, and seats only parties that actually hold seats.
func _check_every_nation_forms_a_government() -> void:
	for id in ALL_IDS:
		var state = _new_state(id)
		var ns = state.player()

		if ns.coalition_party_ids.is_empty():
			_fail("%s: formed no government at all" % id)
			continue
		if ns.pm_party_id == "" or ns.pm_person_id == "":
			_fail("%s: government has no named head of government" % id)
		if not ns.coalition_party_ids.has(ns.pm_party_id):
			_fail("%s: head of government's party '%s' is not in the coalition" % [id, ns.pm_party_id])

		var summed := 0
		for pid in ns.coalition_party_ids:
			var seats := int(ns.seats_by_party.get(pid, 0))
			if seats <= 0:
				_fail("%s: seated '%s', which holds no seats" % [id, pid])
			summed += seats
		if summed != ns.coalition_seats:
			_fail("%s: coalition_seats is %d but its members hold %d" % [id, ns.coalition_seats, summed])

		# is_minority must agree with the arithmetic, not be set independently.
		var expected_minority: bool = ns.coalition_seats <= Government.majority_seats(ns)
		if ns.is_minority != expected_minority:
			_fail("%s: is_minority is %s at %d of %d seats (majority needs more than %d)" % [
				id, ns.is_minority, ns.coalition_seats, ns.assembly_seats, Government.majority_seats(ns)
			])


## The authored cordons are the point of the field. No government anywhere may
## contain a pair that refuses each other, in either direction.
func _check_cordons_are_never_crossed() -> void:
	for id in ALL_IDS:
		var state = _new_state(id)
		var ns = state.player()
		var by_id := {}
		for party in _loader.parties[id]:
			by_id[party.id] = party

		for a in ns.coalition_party_ids:
			for b in ns.coalition_party_ids:
				if a == b or not by_id.has(a) or not by_id.has(b):
					continue
				if by_id[a].excluded_partners.has(b) or by_id[b].excluded_partners.has(a):
					_fail("%s: seated '%s' and '%s' together despite a cordon between them" % [id, a, b])


## A partner further than MAX_PARTNER_DISTANCE from the agreed position refuses
## to join, whatever the arithmetic wants. Without this the search buys any seat
## that closes a gap.
func _check_partners_stay_within_the_distance_cap() -> void:
	for id in ALL_IDS:
		var state = _new_state(id)
		var ns = state.player()
		# Directorial governments are seated by formula, not by a search, so the
		# cap does not apply to them.
		if ns.formation_method == "directorial":
			continue
		for party in _loader.parties[id]:
			if not ns.coalition_party_ids.has(party.id):
				continue
			var d := _distance_from_line(ns, party)
			if d > GK.MAX_PARTNER_DISTANCE + 1.0e-6:
				_fail("%s: '%s' sits %.2f from the agreed position, past the %.2f cap" % [
					id, party.id, d, GK.MAX_PARTNER_DISTANCE
				])


## The agreed position is a seat-weighted mean of positions that are all inside
## the [-1, +1] square, so it must be too — and a single-party government must
## sit exactly on its own party's position.
func _check_coalition_position_is_bounded_and_weighted() -> void:
	for id in ALL_IDS:
		var state = _new_state(id)
		var ns = state.player()
		for axis in ["economic", "social"]:
			var v: float = float(ns.coalition_position[axis])
			if not is_finite(v):
				_fail("%s: agreed position %s is not finite (%s)" % [id, axis, v])
			elif v < -1.0 or v > 1.0:
				_fail("%s: agreed position %s is %+.3f, outside [-1, +1]" % [id, axis, v])

	# A one-party coalition pins the line to that party exactly.
	var state = _new_state("FRA")
	var ns = state.player()
	var by_id := {}
	for party in _loader.parties["FRA"]:
		by_id[party.id] = party
	var solo := Government.position_of(ns.seats_by_party, ["renouveau_civique"], by_id)
	var expected: Dictionary = preload("res://src/sim/election_constants.gd").SLOT_POSITION["centrist_liberal"]
	if not is_equal_approx(float(solo["economic"]), float(expected["economic"])):
		_fail("a one-party line is economic %+.3f, expected its own %+.3f" % [solo["economic"], expected["economic"]])
	if not is_equal_approx(float(solo["social"]), float(expected["social"])):
		_fail("a one-party line is social %+.3f, expected its own %+.3f" % [solo["social"], expected["social"]])


## Each authored censure rule produces the threshold the real rule names, and a
## nation that cannot be censured reports a threshold no opposition can reach.
func _check_censure_threshold_matches_the_authored_rule() -> void:
	for id in ALL_IDS:
		var state = _new_state(id)
		var ns = state.player()
		var needed := Government.censure_seats(ns)

		if ns.censure_rule == "none":
			if needed <= ns.assembly_seats:
				_fail("%s: censure rule is 'none' but the threshold %d is reachable in a %d-seat chamber" % [
					id, needed, ns.assembly_seats
				])
			continue

		if needed <= 0 or needed > ns.assembly_seats:
			_fail("%s: censure threshold %d is outside a %d-seat chamber" % [id, needed, ns.assembly_seats])

		if GK.ABSOLUTE_CENSURE_RULES.has(ns.censure_rule):
			var half := int(floor(float(ns.assembly_seats) / 2.0)) + 1
			if needed != half:
				_fail("%s: absolute censure needs %d, expected %d in a %d-seat chamber" % [
					id, needed, half, ns.assembly_seats
				])

	# The specific French number, because it is the one the model is built on.
	var fra = _new_state("FRA").player()
	if fra.assembly_seats != 577 or Government.censure_seats(fra) != 289:
		_fail("France: censure threshold is %d of %d, expected 289 of 577" % [
			Government.censure_seats(fra), fra.assembly_seats
		])


## The authored French roster allocates so that no two parties reach 289. That
## is what makes the French government interesting, so it is asserted rather
## than left to be noticed.
func _check_france_needs_three_parties() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var needed := Government.censure_seats(ns)

	var parties: Array = _loader.parties["FRA"]
	for a in parties:
		for b in parties:
			if a.id >= b.id:
				continue
			var pair := int(ns.seats_by_party.get(a.id, 0)) + int(ns.seats_by_party.get(b.id, 0))
			if pair >= needed:
				_fail("France: '%s' plus '%s' reach %d seats, so a two-party majority exists" % [a.id, b.id, pair])

	if ns.coalition_party_ids.size() < 3:
		_fail("France: formed a government of %d parties; the roster requires three" % ns.coalition_party_ids.size())
	if ns.is_minority:
		_fail("France: formed a minority government at new-game, expected a majority of three")


## Same state, formed twice, identical government — no hidden randomness, the
## same guarantee elections.gd and legislature.gd both give.
func _check_formation_is_deterministic() -> void:
	for id in ALL_IDS:
		var state = _new_state(id)
		var ns = state.player()
		var first: Dictionary = ns.last_formation.duplicate(true)
		var second := Government.form(ns, _loader.parties[id])

		if first["coalition_party_ids"] != second["coalition_party_ids"]:
			_fail("%s: forming twice gave different coalitions, %s then %s" % [
				id, first["coalition_party_ids"], second["coalition_party_ids"]
			])
		if first["pm_party_id"] != second["pm_party_id"]:
			_fail("%s: forming twice gave different heads of government" % id)


## Cohabitation is the outcome that is neither a win nor a loss, and the branch
## that justifies modelling France as semi-presidential rather than
## parliamentary. It has to be REACHABLE from a real assembly, not just
## displayable — a branch no distribution of seats can enter is dead code.
##
## Driven by writing a hostile assembly directly rather than playing into one,
## because whether the 2029 election produces this depends on the balance pass,
## and this check is about the formation rule, not about balance.
func _check_cohabitation_is_reachable() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var parties: Array = _loader.parties["FRA"]

	# The President's party reduced to a rump, with a right bloc that can reach
	# 289 without it: 250 + 60 = 310 > 289, and neither excludes the other.
	ns.seats_by_party = {
		"renouveau_civique": 40,
		"union_conservatrice": 250,
		"parti_social_uni": 120,
		"alliance_verte": 47,
		"front_souverainiste": 60,
		"gauche_populaire": 60,
	}

	var result := Government.form(ns, parties)

	if not result["cohabitation"]:
		_fail("a President's party reduced to 40 of 577 seats did not produce cohabitation: %s at %d seats" % [
			result["coalition_party_ids"], result["coalition_seats"]
		])
		return
	if result["coalition_party_ids"].has("renouveau_civique"):
		_fail("cohabitation seated the President's own party: %s" % [result["coalition_party_ids"]])
	if result["coalition_seats"] <= Government.majority_seats(ns):
		_fail("cohabitation declared on %d of %d seats, which is not a majority" % [
			result["coalition_seats"], ns.assembly_seats
		])
	if result["pm_party_id"] == "renouveau_civique" or result["pm_person_id"] == "":
		_fail("cohabitation left the premiership with the President's party or unnamed")
	if not ns.is_cohabitation:
		_fail("form() returned cohabitation but did not write it onto the state")

	# And the opposite case must NOT be cohabitation: a President whose own bloc
	# can still reach a majority governs normally, however few seats it holds
	# directly.
	ns.seats_by_party = {
		"renouveau_civique": 200,
		"union_conservatrice": 100,
		"parti_social_uni": 150,
		"alliance_verte": 47,
		"front_souverainiste": 40,
		"gauche_populaire": 40,
	}
	var normal := Government.form(ns, parties)
	if normal["cohabitation"]:
		_fail("a President whose bloc reaches %d of %d seats was put into cohabitation" % [
			normal["coalition_seats"], ns.assembly_seats
		])
	if not normal["coalition_party_ids"].has("renouveau_civique"):
		_fail("a normal government excluded the President's own party: %s" % [normal["coalition_party_ids"]])


## The bonus replaced a flat 0.35 for one party. It must be zero for opposition,
## inside [0, COALITION_BONUS_MAX] for everyone, and strictly larger for a
## partner sitting closer to the agreed line than another of equal discipline.
func _check_coalition_bonus_is_earned_not_given() -> void:
	var state = _new_state("FRA")
	var ns = state.player()

	var in_gov: Array = []
	for party in _loader.parties["FRA"]:
		var bonus := Government.coalition_bonus(ns, party)
		if bonus < 0.0 or bonus > GK.COALITION_BONUS_MAX + 1.0e-9:
			_fail("'%s' scores a coalition bonus of %.3f, outside [0, %.2f]" % [
				party.id, bonus, GK.COALITION_BONUS_MAX
			])
		if ns.coalition_party_ids.has(party.id):
			in_gov.append([party, bonus])
		elif bonus != 0.0:
			_fail("'%s' is in opposition but scores a coalition bonus of %.3f" % [party.id, bonus])

	if in_gov.size() < 2:
		_fail("fewer than two coalition partners to compare bonuses between")
		return

	# Closer to the line, at equal discipline, must mean a larger bonus.
	for a in in_gov:
		for b in in_gov:
			if a[0].id == b[0].id:
				continue
			if not is_equal_approx(a[0].discipline, b[0].discipline):
				continue
			var da := _distance_from_line(ns, a[0])
			var db := _distance_from_line(ns, b[0])
			if da < db - 1.0e-6 and float(a[1]) <= float(b[1]):
				_fail("'%s' is closer to the line than '%s' (%.3f vs %.3f) but scores no more (%.3f vs %.3f)" % [
					a[0].id, b[0].id, da, db, a[1], b[1]
				])


## The load-bearing behaviour of the whole block: France's June 2029 legislative
## election rewrites the assembly and installs a new government, and does not
## end the presidency won in May 2027.
func _check_legislative_election_reforms_without_ending_the_term() -> void:
	var state = _new_state("FRA")
	var ns = state.player()

	for _i in range(EXEC_TARGET_MONTHS):
		_tick(state)
	if not ns.in_government:
		_fail("lost the 2027 presidency on a do-nothing budget, so the rest of this check cannot run")
		return
	var terms_after_presidency: int = ns.terms_served

	var before_seats: Dictionary = ns.seats_by_party.duplicate(true)
	var results: Array = []
	for _i in range(LEG_TARGET_MONTHS - EXEC_TARGET_MONTHS):
		var r := _tick(state)
		if not r.is_empty():
			results = r

	var national = null
	for r in results:
		if r["kind"] == "national":
			national = r
	if national == null:
		_fail("no legislative election resolved by June 2029 (clock at %d-%d)" % [state.year, state.month])
		return

	if not ns.in_government:
		_fail("the June 2029 legislative election ended the presidency; only an executive election may")
	if ns.terms_served != terms_after_presidency:
		_fail("a legislative election changed terms_served from %d to %d" % [
			terms_after_presidency, ns.terms_served
		])
	if not national.has("formation"):
		_fail("the legislative result carries no formation; the government was not re-formed")
	if ns.seats_by_party == before_seats:
		_fail("the legislative election left seats_by_party untouched")
	if ns.coalition_party_ids.is_empty():
		_fail("no government was formed after the legislative election")
	if ns.coalition_seats <= 0:
		_fail("the post-election government holds %d seats" % ns.coalition_seats)


## The same standard test_balance.gd holds every economic scalar to, applied to
## the government: checked every month across a 168-month run covering three
## presidential elections (2027, 2032, 2037) and three legislative ones (2029,
## 2034, 2039), not just at the end. A government that empties and then re-forms
## still means the model stopped working.
func _check_government_stays_coherent_over_fourteen_years() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var legislative_elections := 0
	var executive_elections := 0

	for _i in range(168):
		var results := _tick(state)
		for r in results:
			if r["kind"] == "national":
				legislative_elections += 1
			elif r["kind"] == "executive":
				executive_elections += 1

		if not ns.in_government:
			break

		if ns.coalition_party_ids.is_empty():
			_fail("month %d-%d: the government emptied" % [state.year, state.month])
			return
		if ns.coalition_seats <= 0 or ns.coalition_seats > ns.assembly_seats:
			_fail("month %d-%d: government holds %d of %d seats" % [
				state.year, state.month, ns.coalition_seats, ns.assembly_seats
			])
			return
		if ns.pm_party_id == "" or ns.pm_person_id == "":
			_fail("month %d-%d: government has no head" % [state.year, state.month])
			return
		for axis in ["economic", "social"]:
			var v: float = float(ns.coalition_position[axis])
			if not is_finite(v) or v < -1.0 or v > 1.0:
				_fail("month %d-%d: agreed position %s is %s" % [state.year, state.month, axis, v])
				return

	if ns.in_government:
		if executive_elections < 3:
			_fail("expected three presidential elections in 168 months, saw %d" % executive_elections)
		if legislative_elections < 3:
			_fail("expected three legislative elections in 168 months, saw %d" % legislative_elections)
		if ns.terms_served < 3:
			_fail("terms_served is %d after three held presidential elections" % ns.terms_served)


## Every government field survives a save and load. The save format changed for
## this block, so a field that serialises but does not restore would silently
## reset the player's government on load.
func _check_save_round_trip_preserves_the_government() -> void:
	var state = _new_state("FRA")
	for _i in range(EXEC_TARGET_MONTHS + 6):
		_tick(state)

	var before = state.player()
	var restored = state.duplicate_state().player()
	_compare_government("duplicate_state", before, restored)

	var NationState = preload("res://src/core/nation_state.gd")
	var round_tripped = NationState.from_dict(
		JSON.parse_string(JSON.stringify(before.to_dict()))
	)
	_compare_government("to_dict/from_dict", before, round_tripped)


func _compare_government(label: String, a, b) -> void:
	if a.coalition_party_ids != b.coalition_party_ids:
		_fail("%s: coalition changed from %s to %s" % [label, a.coalition_party_ids, b.coalition_party_ids])
	if a.coalition_seats != b.coalition_seats:
		_fail("%s: coalition_seats changed from %d to %d" % [label, a.coalition_seats, b.coalition_seats])
	if a.pm_party_id != b.pm_party_id or a.pm_person_id != b.pm_person_id:
		_fail("%s: head of government changed from %s/%s to %s/%s" % [
			label, a.pm_person_id, a.pm_party_id, b.pm_person_id, b.pm_party_id
		])
	if a.formation_method != b.formation_method or a.censure_rule != b.censure_rule:
		_fail("%s: formation rules changed from %s/%s to %s/%s" % [
			label, a.formation_method, a.censure_rule, b.formation_method, b.censure_rule
		])
	if a.is_minority != b.is_minority or a.is_cohabitation != b.is_cohabitation:
		_fail("%s: standing changed (minority %s→%s, cohabitation %s→%s)" % [
			label, a.is_minority, b.is_minority, a.is_cohabitation, b.is_cohabitation
		])
	if a.has_executive != b.has_executive:
		_fail("%s: has_executive changed from %s to %s" % [label, a.has_executive, b.has_executive])
	if a.next_executive_year != b.next_executive_year or a.next_executive_month != b.next_executive_month:
		_fail("%s: executive schedule changed from %d-%d to %d-%d" % [
			label, a.next_executive_year, a.next_executive_month,
			b.next_executive_year, b.next_executive_month
		])
	for axis in ["economic", "social"]:
		if not is_equal_approx(float(a.coalition_position[axis]), float(b.coalition_position[axis])):
			_fail("%s: agreed position %s changed from %+.4f to %+.4f" % [
				label, axis, a.coalition_position[axis], b.coalition_position[axis]
			])


func _distance_from_line(ns, party) -> float:
	var K = preload("res://src/sim/election_constants.gd")
	var pos: Dictionary = K.SLOT_POSITION.get(party.ideology_slot, {"economic": 0.0, "social": 0.0})
	var d_econ: float = float(pos["economic"]) - float(ns.coalition_position["economic"])
	var d_social: float = float(pos["social"]) - float(ns.coalition_position["social"])
	return sqrt(d_econ * d_econ + d_social * d_social)


## The real tick sequence, one calendar month, in the order main.gd wires it.
func _tick(state) -> Array:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	Economy.tick_month(state)
	Budget.tick_month(state)
	Opinion.tick_month(state)
	Discipline.tick_month(state, _loader)
	Legislature.tick_month(state, _loader)
	return Elections.tick_month(state, _loader)


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_government: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
