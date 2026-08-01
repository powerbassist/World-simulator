extends SceneTree

## Headless test: godot --headless --script res://tests/test_censure.gd
## Non-zero exit on any failure.
##
## Censure motions and Article 49.3. Where an assembly has to be hostile for a
## censure to carry, the seat distribution is written directly rather than played
## into — whether the balance pass ever produces such an assembly is a separate
## question from whether the rule resolves correctly, and it is recorded in
## docs/government-model.md rather than asserted here.
##
## The model is docs/government-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Government = preload("res://src/sim/government.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const DK = preload("res://src/sim/discipline_constants.gd")
const GK = preload("res://src/sim/government_constants.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_hostility_is_bounded_and_signed()
	_check_a_strong_government_survives_49_3()
	_check_forcing_costs_approval_even_when_it_survives()
	_check_cooldown_blocks_a_second_force_and_expires()
	_check_49_3_only_exists_where_the_constitution_has_it()
	_check_a_weak_government_is_censured_and_falls()
	_check_defectors_are_barred_from_the_replacement()
	_check_a_legislative_election_clears_the_bar()
	_check_a_nation_that_cannot_be_censured_never_is()
	_check_censure_ends_the_run_without_a_separate_executive()
	_check_censure_is_deterministic()
	_check_save_round_trip_preserves_censure_state()

	_finish()


func _new_state(player_id := "FRA"):
	var state = GameState.new_game(_loader, player_id)
	if not state.errors.is_empty():
		_fail("new_game(%s) reported errors: %s" % [player_id, state.errors])
	state.year = 2026
	state.month = 1
	return state


## The first ORDINARY law -- every check in this file forces a bill and reads
## an ordinary majority/censure outcome, which a constitutional amendment
## does not have (Article 49.3 refuses one outright, see
## docs/amendment-model.md). Skipping law.constitutional keeps that true
## regardless of where data/laws/amendments.json happens to sort
## alphabetically among the law directories.
func _first_law():
	for law in _loader.laws:
		if law.id != "" and not law.constitutional:
			return law
	return null


## Hostility is the inverse of the cohesion term, so it must stay in [-1, +1],
## must be negative for a disciplined party inside the government, and must be
## higher under a forced bill than without one.
func _check_hostility_is_bounded_and_signed() -> void:
	var state = _new_state()
	var ns = state.player()

	for party in _loader.parties["FRA"]:
		for forced in [false, true]:
			var h := Government.hostility(ns, party, forced)
			if not is_finite(h) or h < -1.0 or h > 1.0:
				_fail("hostility('%s', forced=%s) is %s, outside [-1, +1]" % [party.id, forced, h])

		if Government.hostility(ns, party, true) < Government.hostility(ns, party, false):
			_fail("'%s' is less hostile under a forced bill than without one" % party.id)

		if ns.coalition_party_ids.has(party.id) and Government.hostility(ns, party, true) > 0.0:
			_fail("coalition partner '%s' is hostile (%.3f) to its own government under 49.3" % [
				party.id, Government.hostility(ns, party, true)
			])


## France's starting government holds 318 of 577 against a 289 threshold, so the
## opposition cannot censure it even united and even provoked. That is the whole
## reason a strong government can use Article 49.3 at all.
func _check_a_strong_government_survives_49_3() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _first_law()

	var result := Legislature.propose(state, _loader, law, true)

	if not result["passed"]:
		_fail("a forced bill did not pass: %s" % [result])
		return
	if not result.get("forced", false):
		_fail("a forced bill was not marked forced")
	if result["yes_seats"] != 0 or result["no_seats"] != 0:
		_fail("a forced bill recorded a seat tally (%d/%d); there was no division" % [
			result["yes_seats"], result["no_seats"]
		])

	var censure: Dictionary = result["censure"]
	if censure["carried"]:
		_fail("a 318-of-577 government was censured: %d for against a threshold of %d" % [
			censure["for_seats"], censure["threshold"]
		])
	if censure["for_seats"] <= 0:
		_fail("nobody moved to censure a forced bill; the hostility bonus is not biting")
	if not censure["defectors"].is_empty():
		_fail("coalition partners defected on a bill their own government forced: %s" % [censure["defectors"]])


## Surviving is not the same as getting away with it. Without a cost on use,
## forcing is strictly dominant for any government that covers the threshold.
func _check_forcing_costs_approval_even_when_it_survives() -> void:
	var law = _first_law()

	# The same law, landing on the same state two ways. A law's own effects write
	# to law_bloc_offset as well, so comparing against a do-nothing run would
	# measure the law rather than the forcing. Applying it directly is exactly
	# what a won vote does, so the difference between these two is the cost of
	# bypassing the assembly and nothing else.
	var forced_state = _new_state()
	Legislature.propose(forced_state, _loader, law, true)
	var f = forced_state.player()

	if f.last_censure.get("carried", true):
		_fail("this check assumes the government survives; it did not")
		return

	var won_state = _new_state()
	Legislature.apply(won_state, won_state.player(), law, _loader)
	var w = won_state.player()

	for bloc in OpinionK.BLOC_KEYS:
		var forced_offset := float(f.law_bloc_offset.get(bloc, 0.0))
		var won_offset := float(w.law_bloc_offset.get(bloc, 0.0))
		if forced_offset >= won_offset:
			_fail("bloc '%s': forcing left offset %+.3f, winning the vote %+.3f — forcing must cost more" % [
				bloc, forced_offset, won_offset
			])
			return

	# And it must reach approval once opinion has ticked, not sit in the
	# accumulator — the offset feeds a target through INERTIA_RATE.
	for _i in range(12):
		for st in [forced_state, won_state]:
			st.month += 1
			if st.month > 12:
				st.month = 1
				st.year += 1
			Economy.tick_month(st)
			Budget.tick_month(st)
			Opinion.tick_month(st)

	if f.overall_approval_pct >= w.overall_approval_pct:
		_fail("a year on, forcing the bill left approval at %.2f against %.2f for winning the vote" % [
			f.overall_approval_pct, w.overall_approval_pct
		])


## One forced bill per cooldown window, then it comes back.
func _check_cooldown_blocks_a_second_force_and_expires() -> void:
	var state = _new_state()
	var ns = state.player()
	# Ordinary laws only -- Article 49.3 refuses a constitutional amendment
	# outright, so one in this list would make "forcing failed" and "the
	# cooldown never engaged" indistinguishable. See docs/amendment-model.md.
	var laws: Array = []
	for law in Legislature.available(ns, _loader.laws):
		if not law.constitutional:
			laws.append(law)
	if laws.size() < 2:
		_fail("fewer than two proposable ordinary laws; cannot test the cooldown")
		return

	Legislature.propose(state, _loader, laws[0], true)
	if ns.force_cooldown_months != GK.FORCE_COOLDOWN_MONTHS:
		_fail("after forcing, cooldown is %d, expected %d" % [
			ns.force_cooldown_months, GK.FORCE_COOLDOWN_MONTHS
		])
	if Government.can_force(ns):
		_fail("can_force is still true immediately after forcing a bill")

	var second := Legislature.propose(state, _loader, laws[1], true)
	if second["passed"] or not second.get("refused", false):
		_fail("a second forced bill was not refused during the cooldown: %s" % [second])

	for _i in range(GK.FORCE_COOLDOWN_MONTHS):
		Legislature.tick_month(state)
	if ns.force_cooldown_months != 0:
		_fail("cooldown is %d after %d months" % [ns.force_cooldown_months, GK.FORCE_COOLDOWN_MONTHS])
	if not Government.can_force(ns):
		_fail("can_force is still false after the cooldown expired")


## Article 49.3 belongs to one constitution. Every other formation method must
## refuse it outright rather than silently adopting a bill without a vote.
func _check_49_3_only_exists_where_the_constitution_has_it() -> void:
	for id in ["DEU", "BEL", "GBR", "CHE", "ITA", "ESP", "NLD", "AUT", "LUX"]:
		var state = _new_state(id)
		var ns = state.player()
		if Government.can_force(ns):
			_fail("%s (%s) can force a bill; only presidential_appointment may" % [id, ns.formation_method])
			continue

		var law = _first_law()
		var result := Legislature.propose(state, _loader, law, true)
		if result["passed"] or not result.get("refused", false):
			_fail("%s adopted a bill under 49.3 without having the article" % id)


## A government whose agreed position is far from most of the chamber loses a
## censure motion, and the player keeps their office.
func _check_a_weak_government_is_censured_and_falls() -> void:
	var state = _new_state()
	var ns = state.player()
	_install_narrow_government(ns, "union_conservatrice")

	var before_pm: String = ns.pm_name
	var law = _first_law()
	var result := Legislature.propose(state, _loader, law, true)
	var censure: Dictionary = result["censure"]

	if not censure["carried"]:
		_fail("a %d-of-%d government survived censure: %d for, threshold %d" % [
			censure["for_seats"], ns.assembly_seats, censure["for_seats"], censure["threshold"]
		])
		return

	# The law still stands — that is the point of forcing it.
	if not result["passed"]:
		_fail("the forced bill was reverted when the government fell; 49.3 adopts it either way")
	if ns.governments_fallen != 1:
		_fail("governments_fallen is %d after one carried censure" % ns.governments_fallen)
	if not ns.in_government:
		_fail("a censured French government cost the President the presidency")
	if ns.pm_name == before_pm and ns.pm_party_id == "union_conservatrice":
		_fail("the censured head of government is still in office")
	if ns.coalition_party_ids.is_empty():
		_fail("no replacement government formed after the censure")
	if float(ns.law_bloc_offset.get(OpinionK.BLOC_KEYS[0], 0.0)) >= 0.0:
		_fail("a government fell without any opinion cost")


## A coalition partner that votes for censure is out, and cannot walk back into
## the replacement.
func _check_defectors_are_barred_from_the_replacement() -> void:
	var state = _new_state()
	var ns = state.player()

	# A coalition stretched across the economic axis: the partner furthest from
	# the agreed line is ill-disciplined enough to break ranks under 49.3.
	ns.seats_by_party = {
		"renouveau_civique": 120,
		"union_conservatrice": 100,
		"parti_social_uni": 100,
		"alliance_verte": 50,
		"front_souverainiste": 100,
		"gauche_populaire": 107,
	}
	ns.censure_barred_party_ids = []
	Government.form(ns, _loader.parties["FRA"])

	var censure := Government.resolve_censure(ns, _loader.parties["FRA"], true)
	if censure["defectors"].is_empty():
		# Not a failure of the rule — this roster may simply hold together. The
		# barring logic is then exercised directly below.
		Government.fall(ns, _loader.parties["FRA"], {"defectors": ["parti_social_uni"]})
		if not ns.censure_barred_party_ids.has("parti_social_uni"):
			_fail("a named defector was not barred")
		if ns.coalition_party_ids.has("parti_social_uni"):
			_fail("a barred defector walked back into the replacement government")
		return

	var defectors: Array = censure["defectors"].duplicate()
	Government.fall(ns, _loader.parties["FRA"], censure)
	for pid in defectors:
		if not ns.censure_barred_party_ids.has(pid):
			_fail("defector '%s' was not barred" % pid)
		if ns.coalition_party_ids.has(pid):
			_fail("defector '%s' is in the replacement government it voted down" % pid)


## The bar lasts until the voters have spoken, not forever.
func _check_a_legislative_election_clears_the_bar() -> void:
	var Elections = preload("res://src/sim/elections.gd")
	var state = _new_state()
	var ns = state.player()
	ns.censure_barred_party_ids = ["parti_social_uni"]

	# Drive to June 2029, France's legislative election.
	for _i in range(41):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		Discipline.tick_month(state, _loader)
		Legislature.tick_month(state)
		Elections.tick_month(state, _loader)

	if not ns.censure_barred_party_ids.is_empty():
		_fail("the legislative election left parties barred: %s" % [ns.censure_barred_party_ids])


## Switzerland's executive does not depend on parliamentary confidence, so no
## distribution of hostility may ever bring it down.
func _check_a_nation_that_cannot_be_censured_never_is() -> void:
	var state = _new_state("CHE")
	var ns = state.player()
	if ns.censure_rule != "none":
		_fail("CHE censure rule is '%s', expected 'none'" % ns.censure_rule)
		return

	# Every party made maximally hostile by putting the agreed line in a corner.
	ns.coalition_position = {"economic": 1.0, "social": 1.0}
	var censure := Government.resolve_censure(ns, _loader.parties["CHE"], true)
	if censure["carried"]:
		_fail("a directorial executive was censured with %d seats" % censure["for_seats"])
	if censure["for_seats"] <= 0:
		_fail("this check needs a hostile chamber to be meaningful; none was hostile")


## Where the head of government IS the player, a carried censure ends the run.
## France is the only playable nation today, so this exercises the branch
## directly rather than through a played game.
func _check_censure_ends_the_run_without_a_separate_executive() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	ns.has_executive = false
	_install_narrow_government(ns, "union_conservatrice")

	var censure := Government.resolve_censure(ns, _loader.parties["FRA"], true)
	if not censure["carried"]:
		_fail("this check needs the censure to carry; it did not")
		return

	Government.fall(ns, _loader.parties["FRA"], censure)
	if ns.in_government:
		_fail("a parliamentary head of government was censured but stayed in office")


## Same state, resolved twice, identical result — no hidden randomness.
func _check_censure_is_deterministic() -> void:
	var state = _new_state()
	var ns = state.player()
	var parties: Array = _loader.parties["FRA"]

	var a := Government.resolve_censure(ns, parties, true)
	var b := Government.resolve_censure(ns, parties, true)
	for key in ["carried", "for_seats", "against_seats", "abstain_seats", "party_votes"]:
		if a[key] != b[key]:
			_fail("determinism: '%s' differed between two resolutions of the same state" % key)


func _check_save_round_trip_preserves_censure_state() -> void:
	var NationState = preload("res://src/core/nation_state.gd")
	var state = _new_state()
	var ns = state.player()
	Legislature.propose(state, _loader, _first_law(), true)
	ns.censure_barred_party_ids = ["gauche_populaire"]

	var round_tripped = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))

	if round_tripped.force_cooldown_months != ns.force_cooldown_months:
		_fail("cooldown changed from %d to %d over a save" % [
			ns.force_cooldown_months, round_tripped.force_cooldown_months
		])
	if round_tripped.censure_barred_party_ids != ns.censure_barred_party_ids:
		_fail("barred parties changed from %s to %s over a save" % [
			ns.censure_barred_party_ids, round_tripped.censure_barred_party_ids
		])
	if round_tripped.governments_fallen != ns.governments_fallen:
		_fail("governments_fallen changed from %d to %d over a save" % [
			ns.governments_fallen, round_tripped.governments_fallen
		])
	if round_tripped.last_censure.get("for_seats", -1) != ns.last_censure.get("for_seats", -2):
		_fail("last_censure did not survive a save")


## A single-party government at `party_id`, which puts the agreed line far from
## most of the chamber and makes a censure motion carry.
func _install_narrow_government(ns, party_id: String) -> void:
	var by_id := {}
	for party in _loader.parties[ns.id]:
		by_id[party.id] = party
	ns.coalition_party_ids = [party_id]
	ns.coalition_seats = int(ns.seats_by_party.get(party_id, 0))
	ns.coalition_position = Government.position_of(ns.seats_by_party, [party_id], by_id)
	ns.pm_party_id = party_id
	ns.pm_name = by_id[party_id].leader_name
	ns.is_minority = true
	ns.is_cohabitation = false
	ns.force_cooldown_months = 0


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_censure: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
