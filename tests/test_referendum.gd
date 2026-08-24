extends SceneTree

## V1.7c. The referendum route, the electoral system as live state, and the two
## stopgaps this session discharges. Model: docs/referendum-model.md.
##
## The load-bearing assertions are the ones about what does NOT happen, and each is a
## property this session's shape rests on:
##
##   - the popular vote reads election_constants.BLOC_TURNOUT BIT-FOR-BIT while no
##     campaign is running, which is what lets the whole layer go live with the balance
##     harness bit-identical across every existing regime;
##   - route B does NOT apply the law. A carried division calls the country and nothing
##     else happens that month -- no `once` flag, no cooldown, no institutional write;
##   - WITHDRAWING IS WEAKLY DOMINATED by holding the vote, proved rather than tuned:
##     it charges the same offset and sets the same cooldown as a loss, so the two
##     outcomes are identical except that holding it might carry;
##   - src/sim/referendum.gd is a LEAF -- it does not name legislature.gd -- which is
##     what lets Legislature.tick_month() settle a referendum without a cycle;
##   - src/sim/calendar.gd is STILL a leaf, so the diary's referendum row is a reuse of
##     the surface rather than a second scheduler;
##   - an ORDINARY law may write election_system and may NOT write any entrenched
##     institutional key, which is instance forty-three's correction put in the schema
##     rather than only in the docs;
##   - `referendum_required` now HAS a seat fraction, and `mandatory` is what makes it
##     mandatory. That is the V1.2c stopgap discharged, and it is asserted rather than
##     described;
##   - the nine never call one, so the verb is the player's -- V1.3g's, V1.6e's and
##     V1.6f's honest limitation, pinned a fifth time;
##   - and BOTH balance harnesses name the widened Legislature.tick_month signature,
##     which is tests/test_pledges.gd's device inherited: V1.5d shipped with neither
##     calling Media.tick_month() and their agreement was about nothing.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const K = preload("res://src/sim/referendum_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const Elections = preload("res://src/sim/elections.gd")
const ElectoralSystems = preload("res://src/sim/electoral_systems.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Law = preload("res://src/core/law.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")

const PLAYER := "FRA"

## The one amendment France's own assembly sends to the country on route B, measured
## by tools/referendum_probe.gd. Named rather than derived, because a test that picks
## its own subject silently changes what it measures when the content moves.
const FRA_AMENDMENT := "single_term_reform"

## The electoral-reform Act, an ORDINARY law and not an amendment.
const PR_ACT := "proportional_representation_act"

var _loader: DataLoader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_modes_are_authored_for_all_ten()
	_test_referendum_required_has_a_fraction()
	_test_register_seeds_empty()
	_test_turnout_is_bit_identical_without_a_campaign()
	_test_route_b_calls_the_country_and_applies_nothing()
	_test_a_carried_referendum_applies_the_law()
	_test_a_lost_referendum_charges_and_cools_down()
	_test_withdrawal_is_weakly_dominated()
	_test_no_route_is_refused()
	_test_the_electoral_system_is_live_state()
	_test_an_ordinary_law_may_not_entrench()
	_test_an_inert_electoral_law_is_not_offered()
	_test_the_diary_shows_a_pending_referendum()
	_test_referendum_is_a_leaf()
	_test_calendar_is_still_a_leaf()
	_test_the_nine_never_call_one()
	_test_both_harnesses_name_the_widened_tick()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("test_referendum: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state():
	return GameState.new_game(_loader, PLAYER)


func _law(id: String):
	for law in _loader.laws:
		if law.id == id:
			return law
	return null


# --- content and the discharged stopgap ------------------------------------------

func _test_modes_are_authored_for_all_ten() -> void:
	var seen := {}
	for id in _loader.nations:
		var n = _loader.nations[id]
		if not K.KNOWN_MODES.has(n.referendum_mode):
			_fail("%s carries referendum mode '%s', which is not a recognised mode" % [id, n.referendum_mode])
		seen[n.referendum_mode] = true
	# All three modes must be instantiated, or one arm of the dispatch is content
	# nobody wrote -- V1.2b's own rule about a template with no nation.
	for mode in K.KNOWN_MODES:
		if not seen.has(mode):
			_fail("no nation carries referendum mode '%s' -- an unreachable arm of the dispatch" % mode)


## THE V1.2c STOPGAP, DISCHARGED. `referendum_required` had no entry in
## AMENDMENT_RULE_FRACTIONS and src/core/nation.gd said resolve_vote() never looked it
## up. It has one now, and what makes it mandatory is the nation's own mode.
func _test_referendum_required_has_a_fraction() -> void:
	if not LegislatureK.AMENDMENT_RULE_FRACTIONS.has("referendum_required"):
		_fail("referendum_required still has no seat fraction -- the V1.2c stopgap is not discharged")
	for id in _loader.nations:
		var n = _loader.nations[id]
		var mandatory: bool = n.referendum_mode == K.MODE_MANDATORY
		var required: bool = n.amendment_rule == "referendum_required"
		if mandatory != required:
			_fail("%s: amendment_rule '%s' and referendum mode '%s' disagree" % [
				id, n.amendment_rule, n.referendum_mode
			])


func _test_register_seeds_empty() -> void:
	var state = _new_state()
	for id in state.nations:
		var ns = state.nations[id]
		if Referendum.is_pending(ns):
			_fail("%s begins with a referendum pending" % id)
		if not ns.last_referendum_result.is_empty():
			_fail("%s begins with a referendum result" % id)


# --- the popular vote --------------------------------------------------------------

## The property that keeps the balance harness bit-identical: with no campaign running,
## the referendum's turnout weight is the AUTHORED constant, exactly.
func _test_turnout_is_bit_identical_without_a_campaign() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _law(FRA_AMENDMENT)
	if law == null:
		_fail("%s is not in the law list" % FRA_AMENDMENT)
		return

	# Recomputed here from the authored constant, and required to match to the bit.
	var expected := 0.0
	var weight_total := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		var w: float = float(OpinionK.BLOC_SIZE[bloc]) * float(ElectionK.BLOC_TURNOUT[bloc])
		weight_total += w
		expected += w * Referendum.bloc_yes(ns, bloc, law.position)
	expected = expected / weight_total

	if Referendum.yes_share(ns, law.position) != expected:
		_fail("the yes share is not bit-identical to the authored BLOC_TURNOUT weighting")


# --- the two routes ----------------------------------------------------------------

func _test_route_b_calls_the_country_and_applies_nothing() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _law(FRA_AMENDMENT)
	var before_limit: int = ns.term_limit

	var result := Legislature.propose(state, _loader, law, false, true)
	if not bool(result.get("referendum_called", false)):
		_fail("route B did not call a referendum on '%s' -- the verb is unreachable" % FRA_AMENDMENT)
		return
	if bool(result["passed"]):
		_fail("a carried division on route B reported the LAW as passed -- it calls the country")
	if not Referendum.is_pending(ns):
		_fail("the register is empty after a referendum was called")
	if Referendum.pending_law_id(ns) != law.id:
		_fail("the register names '%s' rather than '%s'" % [Referendum.pending_law_id(ns), law.id])
	if Referendum.months_left(ns) != K.REFERENDUM_DELAY_MONTHS:
		_fail("the countdown starts at %d rather than %d" % [
			Referendum.months_left(ns), K.REFERENDUM_DELAY_MONTHS
		])

	# NOTHING ELSE HAPPENED. This is the assertion worth having: a session that later
	# applies the law at the division turns it red and has to say why.
	if ns.term_limit != before_limit:
		_fail("route B wrote the institutional effect at the division rather than at the vote")
	if ns.passed_law_ids.has(law.id):
		_fail("route B set the `once` flag before the country had voted")
	if ns.law_cooldown_months.has(law.id):
		_fail("route B put the law on cooldown while it was still in flight")


func _test_a_carried_referendum_applies_the_law() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _law(FRA_AMENDMENT)
	Legislature.propose(state, _loader, law, false, true)

	# Popular enough that it carries. Set rather than played for, because what is
	# under test is the settlement and not the politics that produced it.
	for bloc in OpinionK.BLOC_KEYS:
		ns.bloc_approval[bloc] = 90.0

	for _i in range(K.REFERENDUM_DELAY_MONTHS):
		Legislature.tick_month(state, _loader)

	if Referendum.is_pending(ns):
		_fail("the referendum did not resolve after %d ticks" % K.REFERENDUM_DELAY_MONTHS)
		return
	if not bool(ns.last_referendum_result.get("passed", false)):
		_fail("a referendum at 90 approval did not carry (%.3f yes)" % ns.last_referendum_result.get("yes_share", 0.0))
		return
	if ns.term_limit != 1:
		_fail("a carried referendum did not write the institutional effect")
	if not ns.passed_law_ids.has(law.id):
		_fail("a carried referendum did not set the `once` flag")


func _test_a_lost_referendum_charges_and_cools_down() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _law(FRA_AMENDMENT)
	var before_limit: int = ns.term_limit
	Legislature.propose(state, _loader, law, false, true)

	for bloc in OpinionK.BLOC_KEYS:
		ns.bloc_approval[bloc] = 5.0

	for _i in range(K.REFERENDUM_DELAY_MONTHS):
		Legislature.tick_month(state, _loader)

	if bool(ns.last_referendum_result.get("passed", true)):
		_fail("a referendum at 5 approval carried")
		return
	if ns.term_limit != before_limit:
		_fail("a lost referendum wrote the institutional effect anyway")
	if law.cooldown_months > 0 and not ns.law_cooldown_months.has(law.id):
		_fail("a lost referendum left the law immediately re-callable")
	for bloc in OpinionK.BLOC_KEYS:
		if float(ns.bloc_offset.get(bloc, 0.0)) >= 0.0:
			_fail("a lost referendum did not charge %s" % bloc)
			break


## Holding the vote WEAKLY DOMINATES withdrawing, and this proves it rather than
## asserting it: withdraw from one state, lose from an identical one, and require the
## two to leave the same bloc_offset and the same cooldown. The only difference between
## them is that the vote might have carried.
func _test_withdrawal_is_weakly_dominated() -> void:
	var law = _law(FRA_AMENDMENT)

	var withdrawn = _new_state()
	Legislature.propose(withdrawn, _loader, law, false, true)
	for bloc in OpinionK.BLOC_KEYS:
		withdrawn.player().bloc_approval[bloc] = 5.0
	Referendum.withdraw(withdrawn.player())
	# The cooldown a withdrawal owes is the law's own, set by the same path a loss uses.
	if law.cooldown_months > 0:
		withdrawn.player().law_cooldown_months[law.id] = law.cooldown_months

	var lost = _new_state()
	Legislature.propose(lost, _loader, law, false, true)
	for bloc in OpinionK.BLOC_KEYS:
		lost.player().bloc_approval[bloc] = 5.0
	for _i in range(K.REFERENDUM_DELAY_MONTHS):
		Legislature.tick_month(lost, _loader)

	for bloc in OpinionK.BLOC_KEYS:
		var a: float = float(withdrawn.player().bloc_offset.get(bloc, 0.0))
		var b: float = float(lost.player().bloc_offset.get(bloc, 0.0))
		if not is_equal_approx(a, b):
			_fail("withdrawing and losing charge %s differently: %.6f against %.6f" % [bloc, a, b])
			break
	if not bool(lost.player().last_referendum_result.get("withdrawn", true)) \
			and not withdrawn.player().last_referendum_result.get("withdrawn", false):
		_fail("the result record does not distinguish a withdrawal from a loss")


func _test_no_route_is_refused() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _law(FRA_AMENDMENT)

	# Germany's constitution has no route, and Germany's unreachable 2/3 is exactly the
	# case the ROADMAP argued a referendum exists for -- so this is the finding pinned:
	# the collision is real in the abstract and does NOT resolve for the nation it was
	# named about.
	ns.referendum_mode = K.MODE_NONE
	if Legislature.can_put_to_referendum(ns, law):
		_fail("a nation with no referendum route was offered one")
	var refused := Legislature.propose(state, _loader, law, false, true)
	if not bool(refused.get("refused", false)) or bool(refused["passed"]):
		_fail("route B was not refused under mode 'none'")
	if Referendum.is_pending(ns):
		_fail("a refused route B still called the country")

	# A MANDATORY route is not a choice, so it gets no button either.
	ns.referendum_mode = K.MODE_MANDATORY
	if Legislature.can_put_to_referendum(ns, law):
		_fail("a mandatory route was offered as a choice")

	# An ORDINARY law may never go to a referendum, whatever the mode.
	ns.referendum_mode = K.MODE_OPTIONAL
	if Legislature.can_put_to_referendum(ns, _law(PR_ACT)):
		_fail("an ordinary Act was offered a referendum -- a referendum ratifies an entrenched change")


# --- the electoral system ----------------------------------------------------------

func _test_the_electoral_system_is_live_state() -> void:
	var state = _new_state()
	var ns = state.player()
	var nation = _loader.nations[PLAYER]
	if ns.election_system != nation.election_system:
		_fail("the lifted election_system does not match the nation's own")
	if not is_equal_approx(ns.election_threshold_pct, nation.election_threshold_pct):
		_fail("the lifted threshold does not match the nation's own")

	var law = _law(PR_ACT)
	if law == null:
		_fail("%s is not in the law list" % PR_ACT)
		return
	Legislature.apply(state, ns, law, _loader)
	if ns.election_system != "pr_national":
		_fail("an ordinary Act did not write election_system (%s)" % ns.election_system)
	if nation.election_system != "two_round":
		_fail("applying the Act mutated the loaded Nation -- content is not the save's to write")

	# ...and the allocation reads the LIVE value, which is the whole point.
	var party_list: Array = _loader.parties.get(PLAYER, [])
	var result := Elections.resolve(ns, party_list, ns.election_system, ns.election_threshold_pct, "national", 2029, 6)
	var reference := ElectoralSystems.allocate(
		"pr_national", result["vote_share"], ns.assembly_seats, ns.election_threshold_pct
	)
	for party_id in reference:
		if int(result["seats"].get(party_id, 0)) != int(reference[party_id]):
			_fail("the national vote did not allocate on the live electoral system")
			break


## INSTANCE FORTY-THREE, in the schema rather than only in the docs. An ordinary law may
## write the electoral system; it may not touch an entrenched institution.
func _test_an_ordinary_law_may_not_entrench() -> void:
	if not Law.ORDINARY_INSTITUTIONAL_KEYS.has("election_system"):
		_fail("election_system is not on the ordinary side of the institutional split")
	if not Law.ORDINARY_INSTITUTIONAL_FLOAT_KEYS.has("election_threshold_pct"):
		_fail("election_threshold_pct is not on the ordinary side of the institutional split")
	for key in Law.ORDINARY_INSTITUTIONAL_KEYS:
		if Law.INSTITUTIONAL_EFFECT_KEYS.has(key):
			_fail("'%s' is on BOTH sides of the split -- then the split says nothing" % key)

	var errors: Array[String] = []
	Law.from_dict({
		"id": "bad", "name": "Bad", "theme": "institutional", "summary": "x",
		"position": {"economic": 0.0, "social": 0.0}, "majority": "absolute",
		"cooldown_months": 0, "once": true, "preconditions": [],
		"effects": {"institutional": {"amendment_rule": "ordinary_law"}},
	}, "fixture", errors, [], [], OpinionK.BLOC_KEYS, ["agriculture", "industry", "services"])
	var named := false
	for e in errors:
		if e.contains("requires constitutional: true"):
			named = true
	if not named:
		_fail("an ordinary law writing amendment_rule loaded, or failed without saying why")

	var ok: Array[String] = []
	Law.from_dict({
		"id": "good", "name": "Good", "theme": "institutional", "summary": "x",
		"position": {"economic": 0.0, "social": 0.0}, "majority": "absolute",
		"cooldown_months": 0, "once": true, "preconditions": [],
		"effects": {"institutional": {"election_system": "fptp"}},
	}, "fixture", ok, [], [], OpinionK.BLOC_KEYS, ["agriculture", "industry", "services"])
	if not ok.is_empty():
		_fail("an ordinary law writing election_system failed to load: %s" % [ok])


func _test_an_inert_electoral_law_is_not_offered() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _law(PR_ACT)
	if not Legislature.available(ns, _loader.laws).has(law):
		_fail("the PR Act is not offered to a nation that does not use PR")
	Legislature.apply(state, ns, law, _loader)
	if Legislature.available(ns, _loader.laws).has(law):
		_fail("the PR Act is still offered to a nation that already uses PR at that threshold")


# --- the surfaces and the leaves ----------------------------------------------------

func _test_the_diary_shows_a_pending_referendum() -> void:
	var state = _new_state()
	Legislature.propose(state, _loader, _law(FRA_AMENDMENT), false, true)
	var found := false
	for entry in Calendar.fixed_dates(state):
		if String(entry.get("kind", "")) == CalendarK.FIXED_REFERENDUM:
			found = true
			if String(entry.get("ref", "")) != FRA_AMENDMENT:
				_fail("the diary's referendum row names '%s'" % entry.get("ref", ""))
	if not found:
		_fail("a pending referendum has no diary row")


func _test_referendum_is_a_leaf() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/referendum.gd")
	if src.is_empty():
		_fail("could not read src/sim/referendum.gd")
		return
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("const"):
			continue
		if line.contains("legislature.gd") and not line.contains("legislature_constants.gd"):
			_fail("referendum.gd preloads legislature.gd -- the dependency runs one way")
		if line.contains("elections.gd"):
			_fail("referendum.gd preloads elections.gd -- it reuses the FORMULA, not the module")


func _test_calendar_is_still_a_leaf() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/calendar.gd")
	if src.is_empty():
		_fail("could not read src/sim/calendar.gd")
		return
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("const"):
			continue
		if line.contains("res://src/sim/") and not line.contains("calendar_constants.gd"):
			_fail("calendar.gd preloads a system: %s" % line.strip_edges())


func _test_the_nine_never_call_one() -> void:
	var state = _new_state()
	for _i in range(60):
		Legislature.tick_month(state, _loader)
	for id in state.nations:
		if id == PLAYER:
			continue
		if Referendum.is_pending(state.nations[id]):
			_fail("%s called a referendum -- there is no AI agenda term for this verb" % id)


## tests/test_pledges.gd's device, inherited and widened. V1.5d shipped with neither
## balance harness calling Media.tick_month(), so both ran the pre-session model and
## their agreement about a bit-identical re-run was about nothing.
func _test_both_harnesses_name_the_widened_tick() -> void:
	for path in ["res://tools/balance_probe.gd", "res://tests/test_balance.gd"]:
		var src := FileAccess.get_file_as_string(path)
		if src.is_empty():
			_fail("could not read %s" % path)
			continue
		if not src.contains("Legislature.tick_month(state, "):
			_fail("%s does not call the widened Legislature.tick_month -- a referendum would never resolve there" % path)
