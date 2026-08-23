extends SceneTree

## Headless test: godot --headless --script res://tests/test_bloc.gd
## Non-zero exit on any failure.
##
## V1.3d. The invariants; tools/bloc_probe.gd prints the spread a human reads.
##
## The load-bearing one is _check_the_council_reads_its_own_books(), which asserts the
## member-vote rule by MUTATION and MUST FAIL at V1.3e. That is the point of it,
## and it is the fourth on this project's stopgap checklist after
## tests/test_diplomacy.gd's no-reaction, tests/test_trade.gd's accept-gate and
## tests/test_coercion.gd's fixed retaliation.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const K = preload("res://src/sim/bloc_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Budget = preload("res://src/sim/budget.gd")
const Economy = preload("res://src/sim/economy.gd")
const Relations = preload("res://src/core/relations.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")

const PLAYER := "FRA"
const OUTSIDER := "GBR"

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_new_game_is_exactly_quiet()
	_check_severities_sum_to_the_ceiling()
	_check_burden_reads_the_breach()
	_check_a_non_member_carries_nothing()
	_check_transfers_are_derived_and_signed()
	_check_the_council_divides_and_binds()
	_check_an_abstention_is_not_a_no()
	_check_the_external_measure_uses_the_directed_key()
	_check_the_europe_issue_is_the_only_new_one()
	_check_the_council_reads_its_own_books()
	_check_the_council_still_divides()
	_finish()


func _fresh(nation_id := PLAYER):
	return GameState.new_game(_loader, nation_id)


## Everything about the bloc must be EXACTLY zero at new-game, not approximately.
## That is what makes the europe issue exactly zero like every other satisfaction,
## and it is half of what makes the balance re-run readable: a regime that never
## touches the council must produce a burden of literally 0.0 rather than a
## rounding artefact.
func _check_new_game_is_exactly_quiet() -> void:
	var state = _fresh()
	if not (state.bloc.get("rules", {}) as Dictionary).is_empty():
		_fail("a new game starts with rules in force")
	if not (state.bloc.get("pending", {}) as Dictionary).is_empty():
		_fail("a new game starts with a proposal already before the council")

	for ns in state.nations.values():
		if ns.bloc_burden != 0.0:
			_fail("%s starts with burden %.17f, not exactly 0.0" % [ns.id, ns.bloc_burden])
		if ns.start_bloc_burden != 0.0:
			_fail("%s starts with start_bloc_burden %.17f, not exactly 0.0" % [ns.id, ns.start_bloc_burden])

	var sat := Opinion.issue_satisfaction(state.player())
	if sat["europe"] != 0.0:
		_fail("the europe issue starts at %.17f, not exactly 0.0" % float(sat["europe"]))


## The severities of every authored rule must sum to exactly BURDEN_MAX.
##
## Not decoration. The probe's first run had them summing to 1.35 against a
## ceiling of 1.0, so the clamp removed 0.35 of real burden and a player already
## defying three rules got NOTHING from breaching the fourth -- the strictly
## dominated shape docs/coercion-model.md's probe caught for tariff severity. This
## is the assertion that stops a later session authoring a fifth rule and
## reintroducing it silently.
func _check_severities_sum_to_the_ceiling() -> void:
	var total := 0.0
	var constraining := 0
	for p in _loader.bloc_proposals:
		if p.constraint.is_empty():
			continue
		constraining += 1
		total += float(p.constraint["severity"])

	if constraining > K.MAX_RULES_IN_FORCE:
		_fail("%d proposals carry a constraint but only %d can bind at once" % [
			constraining, K.MAX_RULES_IN_FORCE
		])
	if absf(total - K.BURDEN_MAX) > 1.0e-9:
		_fail("authored rule severities sum to %.6f, not BURDEN_MAX %.2f -- either the clamp bites before total defiance, or total defiance does not reach it" % [
			total, K.BURDEN_MAX
		])


## The burden is the breach, scaled by tolerance and severity, and it is zero for
## a member that complies. A complying player pays in the policy they could not
## run, which lands on the spending lines rather than here.
func _check_burden_reads_the_breach() -> void:
	var state = _fresh()
	var ns = state.player()

	# A rule the player is comfortably inside.
	state.bloc["rules"]["probe_slack"] = _rule("deficit_pct_gdp", "<=", 99.0, 6.0, 0.5)
	if Bloc.burden(state, ns) != 0.0:
		_fail("a rule the player complies with produced a burden of %.6f" % Bloc.burden(state, ns))

	# The same rule, tightened until the player is exactly one tolerance outside:
	# the burden must then be exactly the rule's severity, which is what makes
	# `tolerance` mean "the breach at which this rule counts in full".
	state.bloc["rules"] = {}
	state.bloc["rules"]["probe_full"] = _rule(
		"deficit_pct_gdp", "<=", ns.deficit_pct_gdp - 6.0, 6.0, 0.5
	)
	if absf(Bloc.burden(state, ns) - 0.5) > 1.0e-9:
		_fail("a breach of exactly one tolerance gave burden %.6f, expected the severity 0.5" % Bloc.burden(state, ns))

	# And twice the tolerance must not give twice the severity -- the per-rule
	# term is clamped, or one rule breached absurdly would swamp every other.
	state.bloc["rules"]["probe_full"] = _rule(
		"deficit_pct_gdp", "<=", ns.deficit_pct_gdp - 24.0, 6.0, 0.5
	)
	if absf(Bloc.burden(state, ns) - 0.5) > 1.0e-9:
		_fail("a breach of four tolerances gave burden %.6f; the per-rule term is not clamped" % Bloc.burden(state, ns))

	# The ">=" direction, which is a different branch and has been wrong before in
	# every codebase that has had one.
	state.bloc["rules"] = {}
	state.bloc["rules"]["probe_floor"] = _rule(
		"spending_defence", ">=", float(ns.spending_pct_gdp["defence"]) + 2.0, 2.0, 0.4
	)
	if absf(Bloc.burden(state, ns) - 0.4) > 1.0e-9:
		_fail("a floor rule breached by one tolerance gave burden %.6f, expected 0.4" % Bloc.burden(state, ns))


## GBR and CHE are not members. Every bloc quantity must be exactly zero for them
## by construction, not by a filter someone could forget -- the same structural
## argument U5b made for a non-simulated country being unclickable.
func _check_a_non_member_carries_nothing() -> void:
	var state = _fresh(OUTSIDER)
	var ns = state.player()

	state.bloc["rules"]["probe"] = _rule("deficit_pct_gdp", "<=", -50.0, 1.0, 1.0)
	if Bloc.burden(state, ns) != 0.0:
		_fail("%s is not a member but carries burden %.6f" % [OUTSIDER, Bloc.burden(state, ns)])

	Bloc.tick_month(state, _loader)
	if ns.bloc_transfer_pct_gdp != 0.0:
		_fail("%s is not a member but is charged %.17f%% of GDP" % [OUTSIDER, ns.bloc_transfer_pct_gdp])
	if ns.bloc_base_transfer_pct_gdp != 0.0:
		_fail("%s is not a member but has a standing contribution" % OUTSIDER)

	if Bloc.cast_vote(state, Bloc.VOTE_FOR):
		_fail("%s is not a member but was allowed to vote" % OUTSIDER)


## The net position is derived from prosperity and is a fact about the STARTING
## world, copied once. Two properties, both load-bearing: it is inside
## start_deficit_pct_gdp (so an inherited contribution is politically free until
## the player moves it), and richer pays more.
func _check_transfers_are_derived_and_signed() -> void:
	var positions := Bloc.net_positions(_loader)

	for id in _loader.nations.keys():
		if not _loader.nations[id].eu_member and float(positions.get(id, 0.0)) != 0.0:
			_fail("%s is not a member but has a derived net position" % id)

	# Luxembourg's GDP per capita is far above the bloc mean and Spain's is far
	# below, so the ordering is the whole claim of the formula.
	if float(positions["LUX"]) <= float(positions["FRA"]):
		_fail("LUX pays %.3f and FRA pays %.3f -- the prosperity term is not working" % [
			float(positions["LUX"]), float(positions["FRA"])
		])
	if float(positions["ESP"]) >= float(positions["FRA"]):
		_fail("ESP pays %.3f and FRA pays %.3f -- the prosperity term has the wrong sign" % [
			float(positions["ESP"]), float(positions["FRA"])
		])
	# A clamp that binds is the failure this project keeps rediscovering. Nothing
	# in the shipped roster may sit on either bound.
	for id in positions.keys():
		var v: float = float(positions[id])
		if v != 0.0 and (v <= K.CONTRIBUTION_MIN_PCT_GDP or v >= K.CONTRIBUTION_MAX_PCT_GDP):
			_fail("%s's net position %.4f is ON a contribution clamp" % [id, v])

	# In the start baseline, which is what makes it politically free until moved.
	var state = _fresh()
	var ns = state.player()
	if is_zero_approx(ns.bloc_base_transfer_pct_gdp):
		_fail("France's standing contribution is zero")
	if not is_equal_approx(ns.start_deficit_pct_gdp, ns.deficit_pct_gdp):
		_fail("the standing contribution is not inside start_deficit_pct_gdp: start %.6f vs live %.6f" % [
			ns.start_deficit_pct_gdp, ns.deficit_pct_gdp
		])
	if not is_zero_approx(float(Opinion.issue_satisfaction(ns)["public_finances"])):
		_fail("the standing contribution is visible to voters at new-game")


## The whole loop: a proposal reaches the council, the council divides, and what
## carries binds the player. Including the part the done-when actually asks for --
## the player can be OUTVOTED and is bound by what passes.
func _check_the_council_divides_and_binds() -> void:
	var state = _fresh()

	var opened := -1
	var resolved := -1
	for i in range(K.PROPOSAL_INTERVAL_MONTHS + K.VOTE_DELAY_MONTHS + 2):
		Bloc.tick_month(state, _loader)
		if opened < 0 and not Bloc.pending(state).is_empty():
			opened = i
		if resolved < 0 and not Bloc.last_vote(state).is_empty():
			resolved = i
	if opened < 0:
		_fail("no proposal reached the council in %d months" % (K.PROPOSAL_INTERVAL_MONTHS + K.VOTE_DELAY_MONTHS + 2))
		return
	if resolved < 0:
		_fail("a proposal opened at month %d but the council never divided" % opened)
		return
	if resolved - opened != K.VOTE_DELAY_MONTHS:
		_fail("the council divided %d months after opening, expected VOTE_DELAY_MONTHS %d" % [
			resolved - opened, K.VOTE_DELAY_MONTHS
		])

	# Outvoted, and bound. recovery_facility carries on the other eight alone, so
	# a player voting against it still ends up with it in force -- which is the
	# "one member among many" half of the done-when, asserted rather than claimed.
	var outvoted = _fresh()
	var carried := _force_vote(outvoted, "recovery_facility", Bloc.VOTE_AGAINST)
	if not carried:
		_fail("recovery_facility did not carry over France's objection -- the player is never outvoted, so the council is a legislature they control")
	elif not (outvoted.bloc["rules"] as Dictionary).has("recovery_facility"):
		_fail("recovery_facility carried but did not enter the register")

	# And the other direction: a proposal the council will not have, whatever the
	# player does. common_defence_floor sits where a defence commitment actually
	# sits in ideology space, and the other eight will not carry it.
	var lost = _fresh()
	if _force_vote(lost, "common_defence_floor", Bloc.VOTE_FOR):
		_fail("common_defence_floor carried on France's vote -- nothing is out of the player's reach, so they are not one member among many")


## Abstention has to be a third option, not a slower way of voting no.
##
## The first version of this test asserted the opposite and caught a real hole:
## with the threshold taken against the council's WHOLE strength, abstaining and
## opposing leave `seats_for` identical and so always produce the same outcome --
## abstention was mechanically indistinguishable from opposition. Taking it
## against the seats actually CAST is what separates them, and this is the
## assertion that stops that regressing.
func _check_an_abstention_is_not_a_no() -> void:
	var for_state = _fresh()
	var abstain_state = _fresh()
	var against_state = _fresh()

	# Which proposal demonstrates this is not fixed content, and must not be. V1.3d
	# hardcoded stability_pact here; V1.3e's appraisal changed which proposals the
	# player is pivotal on, and a test naming one is a test about the content rather
	# than about the mechanism. Scanned instead -- and the scan finding NOTHING is
	# itself the finding, because a third vote option no shipped proposal can
	# exercise is a decorative verb.
	var subject := ""
	for p in _loader.bloc_proposals:
		var a = _fresh()
		var b = _fresh()
		if _force_vote(a, p.id, Bloc.VOTE_ABSTAIN) != _force_vote(b, p.id, Bloc.VOTE_AGAINST):
			subject = p.id
			break
	if subject == "":
		_fail("no shipped proposal has an outcome that differs between abstaining and opposing -- constructive abstention is unreachable, which is the decorative-verb failure however correct the arithmetic is")
		return

	var carried_for := _force_vote(for_state, subject, Bloc.VOTE_FOR)
	var carried_abstain := _force_vote(abstain_state, subject, Bloc.VOTE_ABSTAIN)
	var carried_against := _force_vote(against_state, subject, Bloc.VOTE_AGAINST)

	# Abstaining removes the player from the denominator, so it can only ever make
	# passage EASIER than opposing. Both orderings are asserted, because a model
	# that had them the other way round would still differ.
	if carried_against and not carried_abstain:
		_fail("%s carried when France opposed it but not when France abstained -- the denominator is moving the wrong way" % subject)
	if not carried_for and carried_abstain:
		_fail("%s carried on France's abstention but not on its support" % subject)

	# And the tallies say why: abstaining leaves the player out of BOTH numerators,
	# where opposing adds their whole weight to one of them.
	var abstained: Dictionary = abstain_state.bloc["last_vote"]
	var opposed: Dictionary = against_state.bloc["last_vote"]
	var player_seats: int = _loader.eu.ep_seats(PLAYER)
	if int(opposed["seats_against"]) - int(abstained["seats_against"]) != player_seats:
		_fail("opposing added %d seats to the against tally, expected France's %d" % [
			int(opposed["seats_against"]) - int(abstained["seats_against"]), player_seats
		])
	if int(abstained["seats_for"]) != int(opposed["seats_for"]):
		_fail("abstaining changed the for tally, which no player choice but voting for should")


## The bloc's collective external tariff, and the item docs/coercion-model.md
## parked here by name: the first reader of V1.3c's directed register from outside
## src/sim/coercion.gd. It must use the SAME key a player's own tariff uses, or
## nothing in coercion.gd or trade.gd reads it.
func _check_the_external_measure_uses_the_directed_key() -> void:
	var state = _fresh()
	_force_vote(state, "common_external_tariff", Bloc.VOTE_FOR)
	if not (state.bloc["rules"] as Dictionary).has("common_external_tariff"):
		_fail("could not carry common_external_tariff to test the register")
		return

	var members := Bloc.members(state, _loader)
	for member_id in members:
		for outsider_id in [OUTSIDER, "CHE"]:
			if not state.measures.has(Relations.directed_key(member_id, outsider_id)):
				_fail("no measure on %s>%s after a common external tariff" % [member_id, outsider_id])
			# And nothing the other way, or the bloc has tariffed itself.
			if state.measures.has(Relations.directed_key(outsider_id, member_id)):
				_fail("a common external tariff wrote %s>%s, the wrong direction" % [outsider_id, member_id])

	for a in members:
		for b in members:
			if a != b and state.measures.has(Relations.directed_key(a, b)):
				_fail("a common external tariff put a measure on %s>%s, inside the bloc" % [a, b])


## The twelfth issue, and the three properties the V1.3d call rests on: it is in
## ISSUE_KEYS, every bloc weights it (an issue fewer than six blocs weigh never
## clears the poll-noise floor in the headline figure -- docs/diplomacy-model.md),
## and it reaches issue_salience, which bloc_offset structurally cannot.
func _check_the_europe_issue_is_the_only_new_one() -> void:
	if not OK.ISSUE_KEYS.has("europe"):
		_fail("europe is not in ISSUE_KEYS")
		return
	# 12 at V1.3d, 13 at V1.6b, 15 at V1.6d. The count is pinned rather than left open so
	# a session adding a key has to come here and say so -- five sessions answered the
	# thirteenth-key question NO and the sixth answered it YES, which is exactly the
	# decision this assertion exists to make visible. V1.6d is the first to answer it
	# TWICE AT ONCE, and the first to answer YES at a measured cost in the UNSAFE
	# direction: the S10 ratio drifts -0.739 % for the pair, paid because a tax has no
	# content object anywhere else to hang a price on and a tax with no price is free
	# money. The full argument is beside ISSUE_KEYS in opinion_constants.gd.
	if OK.ISSUE_KEYS.size() != 15:
		_fail("ISSUE_KEYS has %d entries; V1.3d added europe, V1.6b inflation, and V1.6d capital gains and wealth" % OK.ISSUE_KEYS.size())
	if not OK.ISSUE_LABEL.has("europe"):
		_fail("europe has no ISSUE_LABEL, so the polling panel would print a raw key")

	for bloc in OK.BLOC_KEYS:
		if not (OK.BLOC_SALIENCE_BASE[bloc] as Dictionary).has("europe"):
			_fail("%s has no europe salience row -- a split price never clears the noise floor" % bloc)

	# The reason the issue exists at all: it reaches the agenda list. A price paid
	# through bloc_offset would not, and that is the whole argument.
	var state = _fresh()
	var ns = state.player()
	state.bloc["rules"]["probe"] = _rule("deficit_pct_gdp", "<=", ns.deficit_pct_gdp - 6.0, 6.0, 1.0)
	Bloc.tick_month(state, _loader)
	Opinion.tick_month(state)
	if float(ns.issue_salience.get("europe", 0.0)) <= 0.0:
		_fail("europe carries no share of the national agenda with a rule defied outright")

	# And it climbs. SALIENCE_GAIN is the mechanism bloc_offset does not have, so a
	# rule biting must make the country argue about Europe MORE than at rest.
	var quiet = _fresh()
	Opinion.tick_month(quiet)
	if float(ns.issue_salience["europe"]) <= float(quiet.player().issue_salience["europe"]):
		_fail("defying a rule did not raise europe's share of the agenda: %.4f against a resting %.4f" % [
			float(ns.issue_salience["europe"]), float(quiet.player().issue_salience["europe"])
		])


## V1.3d's DECLARED STOPGAP, DISCHARGED at V1.3e -- and this is the rewrite.
##
## Until V1.3e this test asserted the opposite: that gutting Germany's economy left
## its vote at exactly the value it had before, because the council read
## coalition_position and nothing else. That assertion went red the moment
## src/sim/foreign_policy.gd landed, which is what it was written to do.
##
## What is asserted now is the inverse and it is stronger: a member's vote MUST
## move when the books it is voting on move, and it must move in the right
## DIRECTION. A test that only checked "something changed" would pass on a model
## that read the economy and drew the wrong conclusion from it.
func _check_the_council_reads_its_own_books() -> void:
	var state = _fresh()
	var proposal = null
	for p in _loader.bloc_proposals:
		if p.id == "stability_pact":
			proposal = p
			break
	if proposal == null:
		_fail("no stability_pact to test the council's appraisal with")
		return

	# stability_pact constrains deficit_pct_gdp. Put Germany comfortably inside it,
	# then far outside it, and the vote must fall.
	var deu = state.nations["DEU"]
	deu.deficit_pct_gdp = 0.0
	var compliant := Bloc.support(state, deu, proposal)

	deu.deficit_pct_gdp = 60.0
	var in_breach := Bloc.support(state, deu, proposal)

	if not (in_breach < compliant):
		_fail("a member deep in breach of a deficit rule does not like it LESS than a member inside it (%.6f in breach vs %.6f compliant) -- the council is not reading its own books" % [in_breach, compliant])

	# And the reason the panel prints has to agree with the arithmetic, or the
	# player is told one thing while the model does another.
	var reason := Bloc.vote_reason(state, deu, proposal)
	if reason != ForeignPolicy.VOTE_REASON_ALREADY_IN_BREACH:
		_fail("a member at 60%% deficit voting on a deficit rule gave reason '%s', not '%s'" % [reason, ForeignPolicy.VOTE_REASON_ALREADY_IN_BREACH])

	# The other half of the stopgap: a fund a member PAYS for and one it DRAWS ON
	# were identical under the old rule if they sat at the same point in ideology
	# space. They must not be now.
	var payer = null
	var drawer = null
	for p in _loader.bloc_proposals:
		if p.transfer_pct_gdp > 0.0 and payer == null:
			payer = p
		if p.transfer_pct_gdp < 0.0 and drawer == null:
			drawer = p
	if payer == null or drawer == null:
		_fail("no paying and drawing proposal pair to test the transfer sign with")
		return
	if not (Bloc.support(state, deu, drawer) > Bloc.support(state, deu, payer)):
		_fail("a member likes a fund it pays into (%.3f) at least as much as one it draws on (%.3f)" % [
			Bloc.support(state, deu, payer), Bloc.support(state, deu, drawer),
		])


## The council must not have become unanimous, which is the failure mode replacing
## a priors-based vote with a books-based one invites: if every member's books
## point the same way, a division is a formality with extra steps.
##
## tools/foreign_policy_probe.gd table (c) is where the balance is set; this only
## pins that SOME proposal in the shipped content still splits the council.
func _check_the_council_still_divides() -> void:
	var state = _fresh()
	var split := false
	for p in _loader.bloc_proposals:
		var seen_for := false
		var seen_against := false
		for id in Bloc.members(state, _loader):
			if Bloc.support(state, state.nations[id], p) >= K.SUPPORT_THRESHOLD:
				seen_for = true
			else:
				seen_against = true
		if seen_for and seen_against:
			split = true
			break
	if not split:
		_fail("no proposal in the shipped content divides the council -- every member votes the same way on all of them")


# --- helpers -------------------------------------------------------------------

func _rule(field: String, op: String, value: float, tolerance: float, severity: float) -> Dictionary:
	return {
		"name": "Probe Rule", "field": field, "op": op, "value": value,
		"tolerance": tolerance, "severity": severity, "transfer_pct_gdp": 0.0,
		"since_year": 2026, "since_month": 1,
	}


## Put one named proposal before the council, cast the player's vote, and let it
## divide. Returns whether it carried. Written directly into `pending` rather than
## waited for, because the agenda is a rotation and waiting for a specific
## proposal would make every assertion depend on the file order.
func _force_vote(state, proposal_id: String, choice: String) -> bool:
	var proposal = null
	for p in _loader.bloc_proposals:
		if p.id == proposal_id:
			proposal = p
			break
	if proposal == null:
		_fail("no proposal '%s'" % proposal_id)
		return false

	state.bloc["pending"] = {
		"proposal_id": proposal.id, "name": proposal.proposal_name,
		"summary": proposal.summary, "months_left": 1,
		"player_vote": Bloc.VOTE_ABSTAIN,
		"opened_year": state.year, "opened_month": state.month,
	}
	if not Bloc.cast_vote(state, choice):
		_fail("cast_vote(%s) was refused" % choice)
	Bloc.tick_month(state, _loader)
	return bool((state.bloc["last_vote"] as Dictionary).get("passed", false))


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_bloc: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
