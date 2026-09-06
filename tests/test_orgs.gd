extends SceneTree

## Headless test: godot --headless --script res://tests/test_orgs.gd
## Non-zero exit on any failure.
##
## V3.2, the org register. Model: docs/orgs-model.md.
##
## PART 1 (Task 1) -- the content type and the loader:
##   - The four authored orgs load cleanly and the register is sorted.
##   - eu carries the values the two co-member constants held before the
##     register existed; its member set and seats equal what
##     data/eu_parliament.json used to hold.
##   - A malformed org file is a loud load error, never a silent partial.
##   - Every proposal names a loaded org, and the per-org agendas preserve
##     flat-file order -- the agenda IS file order, and a reorder here would
##     be a silent change to what every council votes on and when.
##
## PART 2 (Tasks 2-3) -- membership as live state, the generalised machine,
## and the composition rule. Ported from tests/test_bloc.gd, whose
## load-bearing assertion -- the council reads its own books, by mutation --
## carries over with the same teeth.
##
## PART 3 (Task 7) -- accession and withdrawal.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Org = preload("res://src/core/org.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const K = preload("res://src/sim/bloc_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Relations = preload("res://src/core/relations.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")

const PLAYER := "FRA"
const OUTSIDER := "GBR"
const EU_ORG := "eu"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_register_loads()
	_check_eu_absorbed_the_old_sources()
	_check_malformed_orgs_refused()
	_check_proposals_name_orgs()

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
	_check_composition_across_orgs()
	_finish()


func _fresh(nation_id := PLAYER):
	return GameState.new_game(_loader, nation_id)


func _burden(state, ns) -> float:
	return Orgs.burden(state, ns, Orgs.council_ids(state))


func _fail(msg: String) -> void:
	_failures.append(msg)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_orgs: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("  FAIL: %s" % f)
	printerr("test_orgs: %d failure(s)" % _failures.size())
	quit(1)


# --- Part 1 -----------------------------------------------------------------------

func _check_register_loads() -> void:
	var ids: Array = []
	for org in _loader.orgs:
		ids.append(org.id)
	_ok(ids == ["eu", "eurozone", "nato", "schengen"], "register ids sorted, got %s" % [ids])
	for org in _loader.orgs:
		_ok(org.name != "", "%s carries a name" % org.id)
		for member_id in org.members.keys():
			_ok(_loader.nations.has(member_id), "%s member '%s' is on the roster" % [org.id, member_id])
	var parl := 0
	for org in _loader.orgs:
		if not org.parliament.is_empty():
			parl += 1
	_ok(parl == 1, "exactly one org carries a parliament, got %d" % parl)


func _check_eu_absorbed_the_old_sources() -> void:
	var eu = _loader.orgs_by_id.get("eu", null)
	_ok(eu != null, "eu is loaded")
	if eu == null:
		return

	# The member set data/eu_parliament.json held, seats included.
	var expected := {
		"FRA": 81, "DEU": 96, "ITA": 76, "ESP": 61,
		"NLD": 31, "BEL": 22, "AUT": 20, "LUX": 6,
	}
	_ok(eu.members.size() == expected.size(), "eu carries 8 members, got %d" % eu.members.size())
	for id in expected.keys():
		_ok(eu.is_member(id), "eu has %s" % id)
		_ok(eu.ep_seats(id) == expected[id], "eu %s holds %d seats, got %d" % [id, expected[id], eu.ep_seats(id)])
	_ok(not eu.is_member("GBR") and not eu.is_member("CHE"), "eu excludes the two neighbours")
	_ok(int(eu.parliament.get("next_election", {}).get("year", 0)) == 2029, "eu EP clock reads 2029")
	_ok(eu.council and eu.net_transfers, "eu carries the council and the transfer machinery")

	# The two co-member prices, moved UNCHANGED from the constants. These were
	# measured values, not authored ones -- a drift here is a silent re-tune of
	# every resting relation and every gravity weight in the game.
	_ok(is_equal_approx(eu.relations_bonus, 15.0), "eu relations_bonus is the old EU_CO_MEMBER_BONUS")
	_ok(is_equal_approx(eu.trade_bonus, 0.50), "eu trade_bonus is the old EU_TRADE_BONUS")

	# The register's real content: who is in what, and the one cross-cutting
	# fact the hardcoded object could not hold -- GBR is NATO, CHE is Schengen,
	# AUT is EU but not NATO.
	var nato = _loader.orgs_by_id["nato"]
	var schengen = _loader.orgs_by_id["schengen"]
	_ok(nato.is_member("GBR") and not schengen.is_member("GBR"), "GBR is NATO and not Schengen")
	_ok(schengen.is_member("CHE") and not _loader.orgs_by_id["eurozone"].is_member("CHE"), "CHE is Schengen, not the euro")
	_ok(not nato.is_member("AUT"), "AUT stays out of NATO")


func _check_malformed_orgs_refused() -> void:
	var errs: Array[String] = []
	var bad = Org.from_dict({"id": "", "members": {}}, "bad.json", errs)
	_ok(bad.id == "" and not errs.is_empty(), "an org with no id is refused")

	errs = []
	Org.from_dict({"id": "x", "members": {"FRA": {}}}, "bad2.json", errs)
	_ok(not errs.is_empty(), "an org with a member but no name is refused")

	errs = []
	Org.from_dict({"id": "x", "name": "X", "members": {"FRA": { "ep_seats": 5 }}, "parliament": {"next_election": {"year": 2029, "month": 6}, "term_years": 5}}, "bad3.json", errs)
	_ok(errs.is_empty(), "a parliament org whose members carry seats is accepted")

	errs = []
	Org.from_dict({"id": "x", "name": "X", "members": {"FRA": {}}}, "bad4.json", errs)
	_ok(errs.is_empty(), "a non-parliament org with bare member entries is accepted")

	errs = []
	Org.from_dict({"id": "x", "name": "X", "members": {"FRA": {}}, "parliament": {"next_election": {"year": 2029, "month": 6}, "term_years": 5}}, "bad5.json", errs)
	_ok(not errs.is_empty(), "a parliament org whose members lack seats is refused")

	errs = []
	Org.from_dict({"id": "x", "name": "X", "members": {"FRA": {}}, "trade_bonus": 5.0}, "bad6.json", errs)
	_ok(not errs.is_empty(), "a trade_bonus above the bound is refused")


func _check_proposals_name_orgs() -> void:
	var per_org := {}
	for p in _loader.bloc_proposals:
		_ok(p.org_id != "", "proposal '%s' names an org" % p.id)
		_ok(_loader.orgs_by_id.has(p.org_id), "proposal '%s' names a LOADED org" % p.id)
		per_org[p.org_id] = int(per_org.get(p.org_id, 0)) + 1
	_ok(int(per_org.get(EU_ORG, 0)) == 7, "eu carries 7 proposals before track (b) moves the floor, got %d" % int(per_org.get(EU_ORG, 0)))

	# File order IS the agenda. The eu list must be fiscal.json's proposals then
	# union_policy.json's, in authored order -- a reorder would silently change
	# what every council brings forward and when, which is exactly the class of
	# change the bit-identity run is watching for.
	var eu_agenda: Array = _loader.org_proposals.get(EU_ORG, [])
	var eu_ids: Array = []
	for p in eu_agenda:
		eu_ids.append(p.id)
	_ok(eu_ids == ["stability_pact", "debt_reduction_rule", "minimum_corporate_rate", "cohesion_fund", "recovery_facility", "common_defence_floor", "common_external_tariff"],
		"eu agenda preserves flat-file order, got %s" % [eu_ids])


# --- Part 2 -----------------------------------------------------------------------

## Everything about every org must be EXACTLY zero at new-game, not approximately.
## That is what makes the europe issue exactly zero like every other satisfaction,
## and it is half of what makes the balance re-run readable: a regime that never
## touches a council must produce a burden of literally 0.0 rather than a
## rounding artefact.
func _check_new_game_is_exactly_quiet() -> void:
	var state = _fresh()
	for org_id in Orgs.council_ids(state):
		var register: Dictionary = state.orgs[org_id]
		_ok((register.get("rules", {}) as Dictionary).is_empty(), "a new game starts with no rules in force on %s" % org_id)
		_ok((register.get("pending", {}) as Dictionary).is_empty(), "a new game starts with nothing before %s" % org_id)
	_ok(state.accessions.is_empty(), "a new game starts with no membership fight running")

	for ns in state.nations.values():
		_ok(ns.bloc_burden == 0.0, "%s starts with burden %.17f, not exactly 0.0" % [ns.id, ns.bloc_burden])
		_ok(ns.start_bloc_burden == 0.0, "%s starts with start_bloc_burden %.17f, not exactly 0.0" % [ns.id, ns.start_bloc_burden])
		# Membership itself is live data now: every eu member must carry the id,
		# sorted, and nobody else may.
		var expected_member: bool = _loader.orgs_by_id[EU_ORG].is_member(ns.id)
		_ok(ns.orgs.has(EU_ORG) == expected_member, "%s's membership of eu disagrees with the register" % ns.id)
		var sorted_copy: Array = ns.orgs.duplicate()
		sorted_copy.sort()
		_ok(ns.orgs == sorted_copy, "%s's membership list is not sorted" % ns.id)

	var sat := Opinion.issue_satisfaction(state.player())
	_ok(sat["europe"] == 0.0, "the europe issue starts at %.17f, not exactly 0.0" % float(sat["europe"]))


## The severities of every org's authored rules must sum to AT MOST BURDEN_MAX,
## and the eu's to EXACTLY it. Not decoration: V1.3d's probe had them summing to
## 1.35 against a ceiling of 1.0, so the clamp removed 0.35 of real burden. Per
## org the same assertion; across orgs the TOTAL clamp can now contact, which is
## the composition bound recorded in orgs-model.md -- a second rule-carrying org
## re-opens that measurement.
func _check_severities_sum_to_the_ceiling() -> void:
	for org in _loader.orgs:
		if not org.council:
			continue
		var total := 0.0
		var constraining := 0
		for p in _loader.org_proposals.get(org.id, []):
			if p.constraint.is_empty():
				continue
			constraining += 1
			total += float(p.constraint["severity"])
		_ok(constraining <= K.MAX_RULES_IN_FORCE, "%s: %d proposals carry a constraint but only %d can bind at once" % [
			org.id, constraining, K.MAX_RULES_IN_FORCE
		])
		if org.id == EU_ORG:
			_ok(absf(total - K.BURDEN_MAX) <= 1.0e-9,
				"eu rule severities sum to %.6f, not BURDEN_MAX %.2f -- either the clamp bites before total defiance, or total defiance does not reach it" % [
				total, K.BURDEN_MAX
			])
		_ok(total <= K.BURDEN_MAX + 1.0e-9, "%s rule severities sum to %.6f, above BURDEN_MAX %.2f" % [org.id, total, K.BURDEN_MAX])


## The burden is the breach, scaled by tolerance and severity, and it is zero for
## a member that complies. A complying player pays in the policy they could not
## run, which lands on the spending lines rather than here.
func _check_burden_reads_the_breach() -> void:
	var state = _fresh()
	var ns = state.player()

	# A rule the player is comfortably inside.
	state.orgs[EU_ORG]["rules"]["probe_slack"] = _rule("deficit_pct_gdp", "<=", 99.0, 6.0, 0.5)
	_ok(_burden(state, ns) == 0.0, "a rule the player complies with produced a burden of %.6f" % _burden(state, ns))

	# The same rule, tightened until the player is exactly one tolerance outside:
	# the burden must then be exactly the rule's severity, which is what makes
	# `tolerance` mean "the breach at which this rule counts in full".
	state.orgs[EU_ORG]["rules"] = {}
	state.orgs[EU_ORG]["rules"]["probe_full"] = _rule(
		"deficit_pct_gdp", "<=", ns.deficit_pct_gdp - 6.0, 6.0, 0.5
	)
	_ok(absf(_burden(state, ns) - 0.5) <= 1.0e-9,
		"a breach of exactly one tolerance gave burden %.6f, expected the severity 0.5" % _burden(state, ns))

	# And twice the tolerance must not give twice the severity -- the per-rule
	# term is clamped, or one rule breached absurdly would swamp every other.
	state.orgs[EU_ORG]["rules"]["probe_full"] = _rule(
		"deficit_pct_gdp", "<=", ns.deficit_pct_gdp - 24.0, 6.0, 0.5
	)
	_ok(absf(_burden(state, ns) - 0.5) <= 1.0e-9,
		"a breach of four tolerances gave burden %.6f; the per-rule term is not clamped" % _burden(state, ns))

	# The ">=" direction, which is a different branch and has been wrong before in
	# every codebase that has had one.
	state.orgs[EU_ORG]["rules"] = {}
	state.orgs[EU_ORG]["rules"]["probe_floor"] = _rule(
		"spending_defence", ">=", float(ns.spending_pct_gdp["defence"]) + 2.0, 2.0, 0.4
	)
	_ok(absf(_burden(state, ns) - 0.4) <= 1.0e-9,
		"a floor rule breached by one tolerance gave burden %.6f, expected 0.4" % _burden(state, ns))


## GBR and CHE are not eu members. Every eu quantity must be exactly zero for
## them by construction, not by a filter someone could forget -- the same
## structural argument U5b made for a non-simulated country being unclickable.
## (CHE IS a Schengen member, so "member of the org" is the gate, not a name.)
func _check_a_non_member_carries_nothing() -> void:
	var state = _fresh(OUTSIDER)
	var ns = state.player()

	state.orgs[EU_ORG]["rules"]["probe"] = _rule("deficit_pct_gdp", "<=", -50.0, 1.0, 1.0)
	_ok(_burden(state, ns) == 0.0, "%s is not a member but carries burden %.6f" % [OUTSIDER, _burden(state, ns)])

	Orgs.tick_month(state, _loader)
	_ok(ns.bloc_transfer_pct_gdp == 0.0, "%s is not a member but is charged %.17f%% of GDP" % [OUTSIDER, ns.bloc_transfer_pct_gdp])
	_ok(not ns.org_base_transfer_pct_gdp.has(EU_ORG), "%s is not a member but has a standing eu contribution" % OUTSIDER)

	_ok(not Orgs.cast_vote(state, EU_ORG, Orgs.VOTE_FOR), "%s is not a member but was allowed to vote" % OUTSIDER)


## The net position is derived from prosperity and is a fact about the STARTING
## world, copied once. Two properties, both load-bearing: it is inside
## start_deficit_pct_gdp (so an inherited contribution is politically free until
## the player moves it), and richer pays more.
func _check_transfers_are_derived_and_signed() -> void:
	var positions := Orgs.net_positions(_loader, EU_ORG)
	var eu_org = _loader.orgs_by_id[EU_ORG]

	for id in _loader.nations.keys():
		if not eu_org.is_member(id) and float(positions.get(id, 0.0)) != 0.0:
			_fail("%s is not a member but has a derived net position" % id)

	# Luxembourg's GDP per capita is far above the bloc mean and Spain's is far
	# below, so the ordering is the whole claim of the formula.
	_ok(float(positions["LUX"]) > float(positions["FRA"]),
		"LUX pays %.3f and FRA pays %.3f -- the prosperity term is not working" % [
		float(positions["LUX"]), float(positions["FRA"])
	])
	_ok(float(positions["ESP"]) < float(positions["FRA"]),
		"ESP pays %.3f and FRA pays %.3f -- the prosperity term has the wrong sign" % [
		float(positions["ESP"]), float(positions["FRA"])
	])
	# A clamp that binds is the failure this project keeps rediscovering. Nothing
	# in the shipped roster may sit on either bound.
	for id in positions.keys():
		var v: float = float(positions[id])
		_ok(not (v != 0.0 and (v <= K.CONTRIBUTION_MIN_PCT_GDP or v >= K.CONTRIBUTION_MAX_PCT_GDP)),
			"%s's net position %.4f is ON a contribution clamp" % [id, v])

	# In the start baseline, which is what makes it politically free until moved.
	var state = _fresh()
	var ns = state.player()
	_ok(not is_zero_approx(float(ns.org_base_transfer_pct_gdp.get(EU_ORG, 0.0))),
		"France's standing eu contribution is zero")
	_ok(is_equal_approx(ns.start_deficit_pct_gdp, ns.deficit_pct_gdp),
		"the standing contribution is not inside start_deficit_pct_gdp: start %.6f vs live %.6f" % [
		ns.start_deficit_pct_gdp, ns.deficit_pct_gdp
	])
	_ok(is_zero_approx(float(Opinion.issue_satisfaction(ns)["public_finances"])),
		"the standing contribution is visible to voters at new-game")


## The whole loop: a proposal reaches the council, the council divides, and what
## carries binds the player. Including the part the done-when actually asks for --
## the player can be OUTVOTED and is bound by what passes.
func _check_the_council_divides_and_binds() -> void:
	var state = _fresh()

	var opened := -1
	var resolved := -1
	for i in range(K.PROPOSAL_INTERVAL_MONTHS + K.VOTE_DELAY_MONTHS + 2):
		Orgs.tick_month(state, _loader)
		if opened < 0 and not (Orgs.pending(state, EU_ORG) as Dictionary).is_empty():
			opened = i
		if resolved < 0 and not (Orgs.last_vote(state, EU_ORG) as Dictionary).is_empty():
			resolved = i
	if opened < 0:
		_fail("no proposal reached the council in %d months" % (K.PROPOSAL_INTERVAL_MONTHS + K.VOTE_DELAY_MONTHS + 2))
		return
	if resolved < 0:
		_fail("a proposal opened at month %d but the council never divided" % opened)
		return
	_ok(resolved - opened == K.VOTE_DELAY_MONTHS,
		"the council divided %d months after opening, expected VOTE_DELAY_MONTHS %d" % [
		resolved - opened, K.VOTE_DELAY_MONTHS
	])

	# Outvoted, and bound. recovery_facility carries on the others alone, so a
	# player voting against it still ends up with it in force -- which is the
	# "one member among many" half of the done-when, asserted rather than claimed.
	var outvoted = _fresh()
	var carried := _force_vote(outvoted, "recovery_facility", Orgs.VOTE_AGAINST)
	if not carried:
		_fail("recovery_facility did not carry over France's objection -- the player is never outvoted, so the council is a legislature they control")
	elif not ((outvoted.orgs[EU_ORG]["rules"] as Dictionary).has("recovery_facility")):
		_fail("recovery_facility carried but did not enter the register")

	# And the other direction: a proposal the council will not have, whatever the
	# player does. common_defence_floor sits where a defence commitment actually
	# sits in ideology space, and the other members will not carry it.
	var lost = _fresh()
	if _force_vote(lost, "common_defence_floor", Orgs.VOTE_FOR):
		_fail("common_defence_floor carried on France's vote -- nothing is out of the player's reach, so they are not one member among many")


## Abstention has to be a third option, not a slower way of voting no.
##
## The first version of the original test asserted the opposite and caught a real
## hole: with the threshold taken against the council's WHOLE strength, abstaining
## and opposing leave `seats_for` identical and so always produce the same
## outcome. Taking it against the seats actually CAST is what separates them, and
## this is the assertion that stops that regressing.
func _check_an_abstention_is_not_a_no() -> void:
	var for_state = _fresh()
	var abstain_state = _fresh()
	var against_state = _fresh()

	# Which proposal demonstrates this is not fixed content, and must not be.
	# Scanned -- and the scan finding NOTHING is itself the finding, because a
	# third vote option no shipped proposal can exercise is a decorative verb.
	var subject := ""
	for p in _loader.org_proposals.get(EU_ORG, []):
		var a = _fresh()
		var b = _fresh()
		if _force_vote(a, p.id, Orgs.VOTE_ABSTAIN) != _force_vote(b, p.id, Orgs.VOTE_AGAINST):
			subject = p.id
			break
	if subject == "":
		_fail("no shipped proposal has an outcome that differs between abstaining and opposing -- constructive abstention is unreachable, which is the decorative-verb failure however correct the arithmetic is")
		return

	var carried_for := _force_vote(for_state, subject, Orgs.VOTE_FOR)
	var carried_abstain := _force_vote(abstain_state, subject, Orgs.VOTE_ABSTAIN)
	var carried_against := _force_vote(against_state, subject, Orgs.VOTE_AGAINST)

	# Abstaining removes the player from the denominator, so it can only ever make
	# passage EASIER than opposing. Both orderings are asserted, because a model
	# that had them the other way round would still differ.
	if carried_against and not carried_abstain:
		_fail("%s carried when France opposed it but not when France abstained -- the denominator is moving the wrong way" % subject)
	if not carried_for and carried_abstain:
		_fail("%s carried on France's abstention but not on its support" % subject)

	# And the tallies say why: abstaining leaves the player out of BOTH numerators,
	# where opposing adds their whole weight to one of them.
	var abstained: Dictionary = Orgs.last_vote(abstain_state, EU_ORG)
	var opposed: Dictionary = Orgs.last_vote(against_state, EU_ORG)
	var player_seats: int = _loader.orgs_by_id[EU_ORG].ep_seats(PLAYER)
	_ok(int(opposed["seats_against"]) - int(abstained["seats_against"]) == player_seats,
		"opposing added %d seats to the against tally, expected France's %d" % [
		int(opposed["seats_against"]) - int(abstained["seats_against"]), player_seats
	])
	_ok(int(abstained["seats_for"]) == int(opposed["seats_for"]),
		"abstaining changed the for tally, which no player choice but voting for should")


## An org's collective external tariff, and the item docs/coercion-model.md
## parked here by name: the first reader of V1.3c's directed register from outside
## src/sim/coercion.gd. It must use the SAME key a player's own tariff uses, or
## nothing in coercion.gd or trade.gd reads it.
func _check_the_external_measure_uses_the_directed_key() -> void:
	var state = _fresh()
	_force_vote(state, "common_external_tariff", Orgs.VOTE_FOR)
	if not ((state.orgs[EU_ORG]["rules"] as Dictionary).has("common_external_tariff")):
		_fail("could not carry common_external_tariff to test the register")
		return

	var members := Orgs.members(state, EU_ORG)
	for member_id in members:
		for outsider_id in [OUTSIDER, "CHE"]:
			if not state.measures.has(Relations.directed_key(member_id, outsider_id)):
				_fail("no measure on %s>%s after a common external tariff" % [member_id, outsider_id])
			else:
				var terms: Dictionary = state.measures[Relations.directed_key(member_id, outsider_id)]
				if String(terms.get("org", "")) != EU_ORG:
					_fail("the measure on %s>%s does not name its adopting org" % [member_id, outsider_id])
			# And nothing the other way, or the org has tariffed itself.
			if state.measures.has(Relations.directed_key(outsider_id, member_id)):
				_fail("a common external tariff wrote %s>%s, the wrong direction" % [outsider_id, member_id])

	for a in members:
		for b in members:
			if a != b and state.measures.has(Relations.directed_key(a, b)):
				_fail("a common external tariff put a measure on %s>%s, inside the org" % [a, b])


func _check_the_europe_issue_is_the_only_new_one() -> void:
	if not OK.ISSUE_KEYS.has("europe"):
		_fail("europe is not in ISSUE_KEYS")
		return
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
	state.orgs[EU_ORG]["rules"]["probe"] = _rule("deficit_pct_gdp", "<=", ns.deficit_pct_gdp - 6.0, 6.0, 1.0)
	Orgs.tick_month(state, _loader)
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


## V1.3d's DECLARED STOPGAP, DISCHARGED at V1.3e -- carried over at V3.2.
##
## A member's vote MUST move when the books it is voting on move, and it must
## move in the right DIRECTION. A test that only checked "something changed"
## would pass on a model that read the economy and drew the wrong conclusion.
func _check_the_council_reads_its_own_books() -> void:
	var state = _fresh()
	var proposal = null
	for p in _loader.org_proposals.get(EU_ORG, []):
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
	var compliant := Orgs.support(state, deu, proposal)

	deu.deficit_pct_gdp = 60.0
	var in_breach := Orgs.support(state, deu, proposal)

	if not (in_breach < compliant):
		_fail("a member deep in breach of a deficit rule does not like it LESS than a member inside it (%.6f in breach vs %.6f compliant) -- the council is not reading its own books" % [in_breach, compliant])

	# And the reason the panel prints has to agree with the arithmetic, or the
	# player is told one thing while the model does another.
	var reason := Orgs.vote_reason(state, deu, proposal)
	if reason != ForeignPolicy.VOTE_REASON_ALREADY_IN_BREACH:
		_fail("a member at 60%% deficit voting on a deficit rule gave reason '%s', not '%s'" % [reason, ForeignPolicy.VOTE_REASON_ALREADY_IN_BREACH])

	# The other half of the stopgap: a fund a member PAYS for and one it DRAWS ON
	# were identical under the old rule if they sat at the same point in ideology
	# space. They must not be now.
	var payer = null
	var drawer = null
	for p in _loader.org_proposals.get(EU_ORG, []):
		if p.transfer_pct_gdp > 0.0 and payer == null:
			payer = p
		if p.transfer_pct_gdp < 0.0 and drawer == null:
			drawer = p
	if payer == null or drawer == null:
		_fail("no paying and drawing proposal pair to test the transfer sign with")
		return
	if not (Orgs.support(state, deu, drawer) > Orgs.support(state, deu, payer)):
		_fail("a member likes a fund it pays into (%.3f) at least as much as one it draws on (%.3f)" % [
			Orgs.support(state, deu, payer), Orgs.support(state, deu, drawer),
		])


## The council must not have become unanimous, which is the failure mode replacing
## a priors-based vote with a books-based one invites.
func _check_the_council_still_divides() -> void:
	var state = _fresh()
	var split := false
	for p in _loader.org_proposals.get(EU_ORG, []):
		var seen_for := false
		var seen_against := false
		for id in Orgs.members(state, EU_ORG):
			if Orgs.support(state, state.nations[id], p) >= K.SUPPORT_THRESHOLD:
				seen_for = true
			else:
				seen_against = true
		if seen_for and seen_against:
			split = true
			break
	if not split:
		_fail("no proposal in the shipped content divides the council -- every member votes the same way on all of them")


## THE COMPOSITION RULE, asserted rather than argued. A second synthetic council
## org on a real game state, both it and the eu carrying rules the player defies:
##   - each org charges its own fine on its own clamped burden;
##   - the OPINION price is one number, the SUM across orgs (clamp contacted only
##     at total defiance, which is the bound orgs-model.md records -- the session
##     that authors a second rule-carrying org owes that measurement, V1.3d's
##     rescale precedent one level up);
##   - a membership's standing base reaches the budget line with no code change,
##     because membership is the only gate -- which is what makes a won accession
##     worth having.
func _check_composition_across_orgs() -> void:
	var state = _fresh()
	var ns = state.player()

	# Membership is live data, so the machine reads a hand-appended id exactly as
	# it would read a won fight.
	state.orgs["test_org"] = {
		"rules": {}, "pending": {}, "last_vote": {}, "next_index": 0,
		"months_to_next": K.PROPOSAL_INTERVAL_MONTHS,
	}
	state.org_effects["test_org"] = {"relations_bonus": 0.0, "trade_bonus": 0.0}
	ns.orgs.append("test_org")
	ns.orgs.sort()
	ns.org_base_transfer_pct_gdp["test_org"] = 0.10

	state.orgs[EU_ORG]["rules"] = {}
	state.orgs[EU_ORG]["rules"]["probe_eu"] = _rule("deficit_pct_gdp", "<=", ns.deficit_pct_gdp - 6.0, 6.0, 0.5)
	state.orgs["test_org"]["rules"]["probe_to"] = _rule("spending_defence", ">=", float(ns.spending_pct_gdp["defence"]) + 2.0, 2.0, 0.5)

	var eu_only := Orgs.org_burden(state, ns, EU_ORG)
	var to_only := Orgs.org_burden(state, ns, "test_org")
	_ok(absf(eu_only - 0.5) <= 1.0e-9 and absf(to_only - 0.5) <= 1.0e-9,
		"per-org burdens read %.6f and %.6f, expected 0.5 each" % [eu_only, to_only])
	_ok(absf(_burden(state, ns) - 1.0) <= 1.0e-9,
		"the total opinion price read %.6f, expected both orgs' contributions summed" % _burden(state, ns))

	Orgs.tick_month(state, _loader)
	var parts := Orgs.transfer_breakdown(state, ns)
	var per_org: Dictionary = parts["orgs"]
	_ok(float(per_org[EU_ORG]["fine"]) > 0.0 and float(per_org["test_org"]["fine"]) > 0.0,
		"each org must charge its own fine on its own burden")
	_ok(is_equal_approx(float(parts["total"]), ns.bloc_transfer_pct_gdp),
		"transfer_breakdown total %.6f does not sum to the live line %.6f" % [
		float(parts["total"]), ns.bloc_transfer_pct_gdp
	])
	_ok(float(parts["total"]) > float(per_org[EU_ORG]["base"]),
		"the second org's charges did not reach the budget line")


# --- helpers -------------------------------------------------------------------

func _rule(field: String, op: String, value: float, tolerance: float, severity: float) -> Dictionary:
	return {
		"name": "Probe Rule", "field": field, "op": op, "value": value,
		"tolerance": tolerance, "severity": severity, "transfer_pct_gdp": 0.0,
		"since_year": 2026, "since_month": 1,
	}


## Put one named proposal before its council, cast the player's vote, and let it
## divide. Returns whether it carried. Written directly into `pending` rather
## than waited for, because the agenda is a rotation and waiting for a specific
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
	if not state.orgs.has(proposal.org_id):
		_fail("org '%s' holds no register on this state" % proposal.org_id)
		return false

	state.orgs[proposal.org_id]["pending"] = {
		"proposal_id": proposal.id, "name": proposal.proposal_name,
		"summary": proposal.summary, "months_left": 1,
		"player_vote": Orgs.VOTE_ABSTAIN,
		"opened_year": state.year, "opened_month": state.month,
	}
	if not Orgs.cast_vote(state, proposal.org_id, choice):
		_fail("cast_vote(%s) was refused" % choice)
	Orgs.tick_month(state, _loader)
	return bool((Orgs.last_vote(state, proposal.org_id) as Dictionary).get("passed", false))
