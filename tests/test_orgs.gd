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
##
## PART 4 (V3.5 Task 7) -- the climate accord: a fifth org on the register, a
## derived ceiling, a division the player can turn.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Org = preload("res://src/core/org.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Council = preload("res://src/sim/council.gd")
const K = preload("res://src/sim/bloc_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Relations = preload("res://src/core/relations.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const Trade = preload("res://src/sim/trade.gd")

const PLAYER := "FRA"
const OUTSIDER := "GBR"
const EU_ORG := "eu"
const ACCORD := "climate_accord"
const CEILING := "emissions_ceiling"
const SOLIDARITY := "climate_solidarity_clause"

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
	_check_the_rules_read_emissions()
	_check_a_non_member_carries_nothing()
	_check_transfers_are_derived_and_signed()
	_check_the_council_divides_and_binds()
	_check_an_abstention_is_not_a_no()
	_check_the_external_measure_uses_the_directed_key()
	_check_the_europe_issue_is_the_only_new_one()
	_check_the_council_reads_its_own_books()
	_check_the_council_still_divides()
	_check_composition_across_orgs()
	_check_membership_fight()
	_check_climate_accord_register()
	_check_climate_accord_player_is_pivotal_on_the_ceiling()
	_check_climate_accord_positions_are_winnable()
	_check_climate_accord_is_zero_priced()
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
	# V3.5: the climate accord is a fifth org, and the register stays sorted.
	_ok(ids == ["climate_accord", "eu", "eurozone", "nato", "schengen"], "register ids sorted, got %s" % [ids])
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
		"BGR": 17, "HRV": 12, "CYP": 6, "CZE": 21,
		"DNK": 15, "EST": 7, "FIN": 15, "GRC": 21,
		"HUN": 21, "IRL": 14, "LTU": 11, "LVA": 9,
		"MLT": 6, "POL": 53, "PRT": 21, "ROU": 33,
		"SVK": 15, "SVN": 9, "SWE": 21,
	}
	_ok(eu.members.size() == expected.size(), "eu carries 27 members, got %d" % eu.members.size())
	# The real 2024-29 allocation sums to exactly 720, and the test is where
	# that arithmetic is pinned rather than trusted.
	var total_seats := 0
	for id in expected.keys():
		total_seats += expected[id]
	_ok(total_seats == 720, "eu EP seats sum to 720, got %d" % total_seats)
	for id in expected.keys():
		_ok(eu.is_member(id), "eu has %s" % id)
		_ok(eu.seats(id) == expected[id], "eu %s holds %d seats, got %d" % [id, expected[id], eu.seats(id)])
	_ok(not eu.is_member("GBR") and not eu.is_member("CHE"), "eu excludes the two non-EU neighbours")
	# V3.3, and the review caught the author missing three founding members:
	# FIN, IRL and PRT were absent from eurozone.json until the pre-merge pass.
	var ez = _loader.orgs_by_id.get("eurozone", null)
	_ok(ez != null and ez.members.size() == 20, "eurozone carries 20 members, got %d" % (ez.members.size() if ez else -1))
	if ez != null:
		_ok(ez.is_member("FIN") and ez.is_member("IRL") and ez.is_member("PRT"), "eurozone carries the founding members FIN IRL PRT")
		_ok(not ez.is_member("DNK") and not ez.is_member("SWE"), "eurozone excludes DNK and SWE")
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
	if nato.council:
		var seat_sum := 0
		for m in nato.members.keys():
			seat_sum += nato.seats(m)
		_ok(seat_sum > 0 and nato.seats("GBR") > nato.seats("BEL"), "NATO's council carries weighted seats")


func _check_malformed_orgs_refused() -> void:
	var errs: Array[String] = []
	var bad = Org.from_dict({"id": "", "members": {}}, "bad.json", errs)
	_ok(bad.id == "" and not errs.is_empty(), "an org with no id is refused")

	errs = []
	Org.from_dict({"id": "x", "members": {"FRA": {}}}, "bad2.json", errs)
	_ok(not errs.is_empty(), "an org with a member but no name is refused")

	errs = []
	Org.from_dict({"id": "x", "name": "X", "members": {"FRA": { "seats": 5 }}, "parliament": {"next_election": {"year": 2029, "month": 6}, "term_years": 5}}, "bad3.json", errs)
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
	_ok(int(per_org.get(EU_ORG, 0)) == 20, "eu carries 20 proposals (V4.5b's book; the floor moved to NATO at V3.2), got %d" % int(per_org.get(EU_ORG, 0)))
	_ok(int(per_org.get("nato", 0)) == 6, "nato carries the moved floor and V4.5b's five, got %d" % int(per_org.get("nato", 0)))
	_ok(int(per_org.get(ACCORD, 0)) == 8, "the accord carries its two proposals and V4.5b's six, got %d" % int(per_org.get(ACCORD, 0)))

	# File order IS the agenda. The eu list must be fiscal.json's proposals then
	# union_policy.json's, in authored order -- a reorder would silently change
	# what every council brings forward and when, which is exactly the class of
	# change the bit-identity run is watching for.
	var eu_agenda: Array = _loader.org_proposals.get(EU_ORG, [])
	var eu_ids: Array = []
	for p in eu_agenda:
		eu_ids.append(p.id)
	_ok(eu_ids == ["stability_pact", "debt_reduction_rule", "own_resource_digital", "minimum_corporate_rate", "vat_floor", "joint_borrowing_facility", "corporate_rate_high_floor", "expenditure_ceiling", "eurozone_fiscal_capacity", "fiscal_compact_strict", "cohesion_fund", "recovery_facility", "common_external_tariff", "defence_industry_fund", "carbon_border_adjustment", "investment_floor", "enlargement_preaccession_fund", "steel_safeguard", "migration_solidarity_pact", "cap_reform"],
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


## The burden can never pass BURDEN_MAX inside one org: the council admits at
## most MAX_RULES_IN_FORCE constraint rules at once, so the binding sum is the
## largest MAX_RULES_IN_FORCE severities of that org's constraint proposals.
## Required <= BURDEN_MAX for every org (V1.3d's "sum to exactly the ceiling"
## held while each org had <= 4 constraint proposals; V4.5b1's content broke
## that shape and this is the rule it was standing in for). The CROSS-org raw
## total is NOT bounded here -- that is the one clamp, measured by
## tools/council_probe.gd table C5 and recorded in docs/orgs-model.md.
func _check_severities_sum_to_the_ceiling() -> void:
	for org_id in _loader.org_proposals.keys():
		var sev: Array = []
		for p in _loader.org_proposals[org_id]:
			if not p.constraint.is_empty():
				sev.append(float(p.constraint["severity"]))
		sev.sort()
		sev.reverse()
		var top := 0.0
		for i in mini(sev.size(), K.MAX_RULES_IN_FORCE):
			top += float(sev[i])
		_ok(top <= K.BURDEN_MAX + 1e-9, "org %s: its %d heaviest constraint severities sum to %.3f, past BURDEN_MAX %.2f" % [
			org_id, mini(sev.size(), K.MAX_RULES_IN_FORCE), top, K.BURDEN_MAX])


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


## V3.5: a council rule can read the nation's emissions. The two nations ARE the
## division the constraint exists to make -- France at the measured 4.0 t/capita
## breaches NOTHING against an 8.0 t ceiling (the rule is not a tax on ordinary
## life), while Luxembourg at 10.56 t is in real breach, and the breach is the
## over-run itself so the contribution lands at severity x over/tolerance.
func _check_the_rules_read_emissions() -> void:
	var state = _fresh()
	var rule := _rule("co2e_per_capita_t", "<=", 8.0, 4.0, 0.33)

	var fra := Orgs.rule_breach(state, state.player(), EU_ORG, rule)
	_ok(float(fra["breach"]) == 0.0 and float(fra["contribution"]) == 0.0,
		"France at %.2f t CO2e per capita read breach %.4f against an 8.0 t rule" % [
		state.player().co2e_per_capita_t, float(fra["breach"])
	])

	# LUX is a eu member (Part 1 pins the register), so the membership gate lets
	# the rule reach it -- a non-member would read 0.0 for the wrong reason.
	var lux = state.nations["LUX"]
	var breach := Orgs.rule_breach(state, lux, EU_ORG, rule)
	var over: float = lux.co2e_per_capita_t - 8.0
	_ok(over > 0.0, "the fixture is useless: LUX at %.2f t does not breach 8.0" % lux.co2e_per_capita_t)
	_ok(float(breach["breach"]) > 0.0 and is_equal_approx(float(breach["breach"]), over),
		"LUX's breach read %.4f, expected the over-run %.4f off the live field" % [
		float(breach["breach"]), over
	])
	_ok(is_equal_approx(float(breach["contribution"]), 0.33 * over / 4.0),
		"LUX's contribution read %.6f, expected severity x over/tolerance" % float(breach["contribution"]))


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

	# Outvoted, and bound. debt_reduction_rule carries on the others alone, so a
	# player voting against it still ends up with it in force -- which is the
	# "one member among many" half of the done-when, asserted rather than claimed.
	# V4.5b: recovery_facility was the subject until it became a unanimity
	# treaty, where France's "against" is a veto; a qualified-majority row has
	# to carry this assertion.
	var outvoted = _fresh()
	var carried := _force_vote(outvoted, "debt_reduction_rule", Orgs.VOTE_AGAINST)
	if not carried:
		_fail("debt_reduction_rule did not carry over France's objection -- the player is never outvoted, so the council is a legislature they control")
	elif not ((outvoted.orgs[EU_ORG]["rules"] as Dictionary).has("debt_reduction_rule")):
		_fail("debt_reduction_rule carried but did not enter the register")

	# And the other direction: a proposal the council will not have, whatever the
	# player does. minimum_corporate_rate is a unanimity treaty two low-rate
	# members veto (V4.5b; common_defence_floor held this place until NATO's
	# consensus rule and its sponsor's lobbying made it France's to decide).
	var lost = _fresh()
	if _force_vote(lost, "minimum_corporate_rate", Orgs.VOTE_FOR):
		_fail("minimum_corporate_rate carried on France's vote -- nothing is out of the player's reach, so they are not one member among many")


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
	var player_seats: int = _loader.orgs_by_id[EU_ORG].seats(PLAYER)
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

	# V5.0d: the tag travels through a save. It is the ONLY thing a membership flip
	# reads to lift exactly the org's own measures, so a load that dropped it left
	# the common external tariff on a new member, and on every outsider a leaver
	# used to tariff, for the rest of the run.
	var back = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	for directed in state.measures.keys():
		var tag := String((state.measures[directed] as Dictionary).get("org", ""))
		if tag != "" and String((back.measures.get(directed, {}) as Dictionary).get("org", "")) != tag:
			_fail("the measure on %s lost its adopting org '%s' through a save" % [directed, tag])
			break


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


# --- Part 3: the fights -----------------------------------------------------------

## The whole accession/withdrawal machine, driven through the REAL referendum
## machinery: begin puts the question to the country, the campaign runs its
## authored months, the resolve is consumed once, and only a PASSED vote starts
## the negotiation countdown that ends in membership actually flipping.
func _check_membership_fight() -> void:
	var state = _fresh()
	var ns = state.player()

	# Refusals, each one the machine's own answer.
	var refused = Orgs.begin_accession(state, _loader, ns, EU_ORG)
	if bool(refused.get("ok", false)):
		_fail("begin_accession succeeded for a nation already in the eu")
	var ai = state.nations["DEU"]
	refused = Orgs.begin_accession(state, _loader, ai, EU_ORG)
	if bool(refused.get("ok", false)):
		_fail("begin_accession succeeded for a nation with no human at the desk")

	# France leaves the EU: begin, campaign, resolve, negotiate, flip.
	refused = Orgs.begin_withdrawal(state, _loader, ns, EU_ORG)
	if not bool(refused.get("ok", false)):
		_fail("begin_withdrawal refused: %s" % String(refused.get("reason", "")))
		return
	if not ns.referendum_pending.is_empty():
		pass
	else:
		_fail("begin_withdrawal announced no referendum")
	if state.accessions.size() != 1:
		_fail("begin_withdrawal did not open a fight")
	var second = Orgs.begin_withdrawal(state, _loader, ns, "nato")
	if bool(second.get("ok", false)):
		_fail("a second fight began while the first was running")

	# Run the referendum out -- the campaign is the machine's own 11 months --
	# by resolving directly, which is exactly what Legislature.tick_month calls.
	var resolved := {}
	for i in range(13):
		resolved = Referendum.resolve_due(ns)
		if not resolved.is_empty():
			break
	if resolved.is_empty() or not bool(resolved.get("passed", false)):
		# The withdrawal position sits well against the status quo; if the
		# electorate still refuses it the content is unfightable and the test
		# says so rather than papering over it.
		_fail("the withdrawal referendum did not pass (yes_share %.3f) -- authored position too weak to fight with" % float(resolved.get("yes_share", 0.0)))
		return

	# The resolve is consumed on the next Orgs.tick_month, which converts the
	# fight to its negotiation countdown.
	Orgs.tick_month(state, _loader)
	if state.accessions.is_empty() or String(state.accessions[0].get("phase", "")) != "negotiation":
		_fail("a passed referendum did not start the negotiation countdown")
		return

	# An AI nation's act must not begin a fight while the player's runs.
	# The negotiation runs the authored 24 months: membership must hold for
	# exactly that long and flip on the tick that expires it, not one before.
	var flipped_month := -1
	for i in range(30):
		Orgs.tick_month(state, _loader)
		if not ns.orgs.has(EU_ORG):
			flipped_month = i
			break
	if flipped_month < 0:
		_fail("membership did not flip after the negotiation elapsed")
		return
	if flipped_month < 23:
		_fail("membership flipped before the authored negotiation elapsed (month %d)" % flipped_month)
	if ns.next_ep_election_year != 0:
		_fail("leaving the parliament org did not surrender the EP clock")
	if not state.accessions.is_empty():
		_fail("the finished fight was not removed from the register")

	# A won withdrawal must not strand the net-position table at the old mean:
	# the eu's members' bases are re-derived, and the ex-member carries none.
	if ns.org_base_transfer_pct_gdp.has(EU_ORG):
		_fail("the ex-member still carries a standing eu contribution")
	# Every remaining member's line must move against ITS OWN pre-exit value:
	# the mean the formula divides by changed when France walked out. Compared
	# per member, not against one reference member -- the first version
	# compared every member against DEU's fresh value, which any member other
	# than DEU trips whether or not the re-derive did anything.
	var fresh = _fresh()
	var moved := false
	for member_id in ["DEU", "ITA", "ESP", "NLD", "BEL", "AUT", "LUX"]:
		if not is_equal_approx(
			float(state.nations[member_id].org_base_transfer_pct_gdp.get(EU_ORG, 0.0)),
			float(fresh.nations[member_id].org_base_transfer_pct_gdp.get(EU_ORG, 0.0))):
			moved = true
			break
	if not moved:
		_fail("no remaining member's contribution was re-derived after a member left")

	# The seat weight died with the membership, and the EP clock surrendered.
	if ns.org_seats.has(EU_ORG):
		_fail("the ex-member still carries a seat weight")

	# AND BACK AGAIN: the review's second-class-member finding. FRA re-accedes,
	# and on the flip it must enter with the org's authored accession_seats, a
	# future EP clock, a live base contribution -- and the eu's collective
	# measures aimed at it must lift.
	var base_before: float = float(_fresh().nations["DEU"].org_base_transfer_pct_gdp.get(EU_ORG, 0.0))
	# Stage the measures the org aims at the future member, the way
	# _apply_external_measure writes them.
	state.measures[Relations.directed_key("DEU", PLAYER)] = {
		"action_id": "common_external_tariff", "action_name": "Common External Tariff",
		"kind": "tariff", "severity": 0.35,
		"since_year": state.year, "since_month": state.month,
		"org": EU_ORG, "retaliated": true,
	}
	var rejoin = Orgs.begin_accession(state, _loader, ns, EU_ORG)
	if not bool(rejoin.get("ok", false)):
		_fail("re-accession refused: %s" % String(rejoin.get("reason", "")))
		return
	var res := {}
	for i in range(13):
		res = Referendum.resolve_due(ns)
		if not res.is_empty():
			break
	if res.is_empty() or not bool(res.get("passed", false)):
		_fail("the re-accession referendum did not pass (yes_share %.3f)" % float(res.get("yes_share", 0.0)))
		return
	Orgs.tick_month(state, _loader)
	var flips := -1
	for i in range(30):
		Orgs.tick_month(state, _loader)
		if ns.orgs.has(EU_ORG):
			flips = i
			break
	if flips < 0:
		_fail("re-accession membership did not flip")
		return
	if int(ns.org_seats.get(EU_ORG, 0)) != _loader.orgs_by_id[EU_ORG].accession_seats:
		_fail("the joiner's seat weight is %s, expected the org's authored accession_seats %d" % [
			str(ns.org_seats.get(EU_ORG, 0)), _loader.orgs_by_id[EU_ORG].accession_seats
		])
	if Orgs.live_seats(state, EU_ORG, PLAYER) != _loader.orgs_by_id[EU_ORG].accession_seats:
		_fail("live_seats does not read the joiner's written weight")
	if ns.next_ep_election_year <= state.year:
		_fail("the joiner's EP clock reads %d, not rolled into the future" % ns.next_ep_election_year)
	if float(ns.org_base_transfer_pct_gdp.get(EU_ORG, 0.0)) <= 0.0:
		_fail("the joiner pays no standing contribution -- a free ride on the club it fought to join")
	if state.measures.has(Relations.directed_key("DEU", PLAYER)):
		_fail("the eu's collective measure survived the target's accession -- a tariff on a fellow member, permanently")

	# And a LOST referendum ends the fight with membership where it was. The
	# question is forced to fail by overwriting the pending position with one
	# the whole country opposes -- the machine reads whatever resolve_due hands
	# back, which is the contract under test.
	var state2 = _fresh()
	var ns2 = state2.player()
	var acc = Orgs.begin_withdrawal(state2, _loader, ns2, EU_ORG)
	if not bool(acc.get("ok", false)):
		_fail("a fresh withdrawal begin was refused: %s" % String(acc.get("reason", "")))
		return
	ns2.referendum_pending["position"] = {"economic": 0.45, "social": 0.55}
	ns2.referendum_pending["months_left"] = 1
	var lost := {}
	for i in range(3):
		lost = Referendum.resolve_due(ns2)
		if not lost.is_empty():
			break
	if lost.is_empty() or bool(lost.get("passed", false)):
		_fail("the forced-lost referendum did not fail -- the test's own fixture is broken")
		return
	Orgs.tick_month(state2, _loader)
	Orgs.tick_month(state2, _loader)
	if not state2.accessions.is_empty():
		_fail("a lost referendum did not end the fight")
	if not ns2.orgs.has(EU_ORG):
		_fail("a lost referendum changed membership")


# --- Part 4: the climate accord (V3.5, Task 7) -------------------------------------

## The register test: five orgs now, and the accord's own content. The seat
## table is round(population / 1e6) over the EU-27, measured off the committed
## nation files, and it sums to exactly 452 -- the test is where that arithmetic
## is pinned rather than trusted, the eu-720 precedent. The LIVE membership is
## the EU-27's, because the founding register IS the eu's minus GBR and CHE:
## asserted against Orgs.members() so the two reads cannot drift apart.
func _check_climate_accord_register() -> void:
	var accord = _loader.orgs_by_id.get(ACCORD, null)
	_ok(accord != null, "climate_accord is loaded")
	if accord == null:
		return
	_ok(accord.name != "" and accord.summary != "", "the accord carries a name and a summary")
	_ok(accord.council and not accord.net_transfers, "the accord holds a council and no transfer machinery")
	_ok(accord.parliament.is_empty(), "the accord carries no parliament -- eu keeps the register's only one")
	_ok(is_equal_approx(accord.relations_bonus, 0.0) and is_equal_approx(accord.trade_bonus, 0.0),
		"the accord ships zero-priced on the eurozone/schengen precedent")
	_ok(accord.accession_seats == 17, "a joiner enters with the EU-27 mean weight 17, got %d" % accord.accession_seats)
	_ok(accord.accession_months == 18 and accord.withdrawal_months == 24,
		"the accord's fights run 18 and 24 months, got %d and %d" % [accord.accession_months, accord.withdrawal_months])

	_ok(accord.members.size() == 27, "the accord carries 27 founding members, got %d" % accord.members.size())
	var seat_sum := 0
	for m in accord.members.keys():
		seat_sum += accord.seats(m)
	_ok(seat_sum == 452, "the accord's seats sum to 452, got %d" % seat_sum)
	_ok(not accord.is_member("GBR") and not accord.is_member("CHE"), "GBR and CHE stay outside the accord")

	var eu = _loader.orgs_by_id[EU_ORG]
	for id in eu.members.keys():
		_ok(accord.is_member(id), "the accord's founding register is the EU-27: %s missing" % id)
	for id in accord.members.keys():
		_ok(eu.is_member(id), "the accord lists %s, who is not in the eu -- the founding rule is the eu minus two" % id)

	# The council register initializes with every other council's, and the LIVE
	# membership agrees with the eu's live membership -- the founding rule read
	# from state, not from content.
	var state = _fresh()
	_ok(Orgs.council_ids(state).has(ACCORD), "the accord's council register initializes on a new game")
	_ok(Orgs.members(state, ACCORD) == Orgs.members(state, EU_ORG),
		"the accord's live membership is not the eu's live membership")
	for id in [OUTSIDER, "CHE"]:
		_ok(not Orgs.is_member(state, ACCORD, id), "%s is a live member of the accord" % id)
	_ok(Orgs.live_seats(state, ACCORD, PLAYER) == 69, "France weighs 69 in the accord's council")

	# The agenda is file order, the same pin the eu's list carries.
	var agenda: Array = _loader.org_proposals.get(ACCORD, [])
	var agenda_ids: Array = []
	for p in agenda:
		agenda_ids.append(p.id)
	_ok(agenda_ids == [CEILING, SOLIDARITY, "climate_border_levy", "ceiling_tightened", "just_transition_fund", "green_investment_floor", "adaptation_fund", "net_zero_glidepath"], "the accord's agenda preserves flat-file order, got %s" % [agenda_ids])
	for p in agenda:
		if p.id == CEILING:
			var c: Dictionary = p.constraint
			_ok(not c.is_empty() and String(c.get("field", "")) == "co2e_per_capita_t",
				"the ceiling constrains co2e_per_capita_t")
			_ok(String(c.get("op", "")) == "<=" and is_equal_approx(float(c.get("value", 0.0)), 5.5),
				"the ceiling's value is the derived 5.5, got %s" % str(c.get("value")))
			_ok(is_equal_approx(float(c.get("severity", 0.0)), 0.33), "the ceiling's severity is 0.33")
		if p.id == SOLIDARITY:
			_ok((p.constraint as Dictionary).is_empty(), "the solidarity clause constrains nobody's policy")
			_ok(is_equal_approx(p.transfer_pct_gdp, 0.04), "the solidarity clause moves 0.04%% of GDP, got %s" % str(p.transfer_pct_gdp))
			_ok(p.external_measure.is_empty(), "the solidarity clause sets no external measure")


## THE PLAYER-PIVOTAL TEST. V3.3's own finding: a 27-seat council made
## constructive abstention unreachable on EVERY proposal until the position was
## re-authored. The player's 69 of 452 seats must sit inside the ceiling's
## pivotal band -- her abstention carries it, her opposition blocks it, her
## backing passes it -- measured on the real division, not asserted from the
## seats. tools/climate_probe.gd table (b) is the instrument that placed it;
## the band arithmetic: with 383 seats among the others, the ceiling carries on
## an abstention while others_for sits in [211, 248] (0.55 x 383 = 210.65, and
## 0.55 x 452 = 248.6 blocks it once France's 69 join the opposition).
func _check_climate_accord_player_is_pivotal_on_the_ceiling() -> void:
	var carried := {}
	var tallies := {}
	for choice in [Orgs.VOTE_FOR, Orgs.VOTE_ABSTAIN, Orgs.VOTE_AGAINST]:
		var s = _fresh()
		carried[choice] = _force_vote(s, CEILING, choice)
		tallies[choice] = Orgs.last_vote(s, ACCORD)
		if (tallies[choice] as Dictionary).is_empty():
			_fail("the ceiling never divided on the player's %s" % choice)
			return

	_ok(carried[Orgs.VOTE_FOR], "the ceiling failed on the player's backing -- the position overshot the pivotal band")
	_ok(carried[Orgs.VOTE_ABSTAIN], "the ceiling failed on the player's abstention -- constructive abstention is unreachable on the accord's first page")
	_ok(not carried[Orgs.VOTE_AGAINST], "the ceiling carried against the player's opposition -- her 69 seats do not block it")

	# And the three tallies are three different tallies, which is the
	# constructive-abstention arithmetic asserted at the number level: opposing
	# adds her whole weight to the against column, abstaining adds her to
	# neither, backing adds it to the for column.
	var for_t: Dictionary = tallies[Orgs.VOTE_FOR]
	var ab_t: Dictionary = tallies[Orgs.VOTE_ABSTAIN]
	var ag_t: Dictionary = tallies[Orgs.VOTE_AGAINST]
	_ok(int(ag_t["seats_against"]) - int(ab_t["seats_against"]) == 69,
		"opposing added %d seats to the against tally, expected France's 69" % (int(ag_t["seats_against"]) - int(ab_t["seats_against"])))
	_ok(int(ab_t["seats_for"]) == int(ag_t["seats_for"]),
		"abstaining changed the for tally, which no player choice but backing should")
	_ok(int(for_t["seats_for"]) - int(ab_t["seats_for"]) == 69,
		"backing added %d seats to the for tally, expected France's 69" % (int(for_t["seats_for"]) - int(ab_t["seats_for"])))

	# The other page is NOT the player's: the solidarity clause is a coalition's
	# question -- it lands where her choice changes nothing, which is the
	# contrast that makes the ceiling's pivotal band mean something. Recorded
	# tallies in tools/climate_probe.gd table (b2).
	var solid := {}
	for choice in [Orgs.VOTE_FOR, Orgs.VOTE_ABSTAIN, Orgs.VOTE_AGAINST]:
		var s = _fresh()
		solid[choice] = _force_vote(s, SOLIDARITY, choice)
	_ok(solid[Orgs.VOTE_FOR] == solid[Orgs.VOTE_ABSTAIN] and solid[Orgs.VOTE_ABSTAIN] == solid[Orgs.VOTE_AGAINST],
		"the player's choice changes the solidarity clause's outcome -- the council is not a coalition's question")


## The 0.510-0.523-at-rest band every fight content ships inside: winnable by a
## president the country does not hate, losable by one it does (V3.2's
## accession/withdrawal discipline, now on the accord's own way in). Swept by
## tools/climate_probe.gd table (c) BEFORE the numbers went into the file; this
## asserts the file the sweep produced. The fixture guards are the test's
## honesty: the sweep measured a NEUTRAL-approval new-game, so a re-measure on a
## state that is no longer that fails loudly here rather than vacuously.
func _check_climate_accord_positions_are_winnable() -> void:
	var accord = _loader.orgs_by_id[ACCORD]
	_ok(not (accord.accession_position as Dictionary).is_empty(), "the accord carries no accession_position to fight with")
	_ok(not (accord.withdrawal_position as Dictionary).is_empty(), "the accord carries no withdrawal_position -- a door nobody can open from inside is not a fight")

	for outsider in [OUTSIDER, "CHE"]:
		var state = _fresh(outsider)
		var ns = state.player()

		# Fixture viability, the LUX-emissions shape: the sweep measured a
		# NEUTRAL-approval new-game, so assert the state still is one. A future
		# change to the seeding turns these red instead of turning the band
		# assertion below into a lie.
		for bloc in OK.BLOC_KEYS:
			_ok(is_equal_approx(float(ns.bloc_approval.get(bloc, 0.0)), float(OK.APPROVAL_NEUTRAL)),
				"the %s fixture is not a neutral-approval new-game: %s reads %s" % [
				outsider, bloc, str(ns.bloc_approval.get(bloc, 0.0))])

		var in_share: float = Referendum.yes_share(ns, accord.accession_position)
		_ok(in_share >= 0.510 and in_share <= 0.523,
			"%s's accession to the accord reads yes_share %.4f at rest, outside [0.510, 0.523] -- the door is locked or already open" % [outsider, in_share])
		var out_share: float = Referendum.yes_share(ns, accord.withdrawal_position)
		_ok(out_share >= 0.510 and out_share <= 0.523,
			"%s's withdrawal from the accord reads yes_share %.4f at rest, outside [0.510, 0.523]" % [outsider, out_share])


## Zero-priced honesty, and the pin T8's bit-identity prediction leans on: the
## accord carries no relations_bonus and no trade_bonus, so a shared-bonus sum
## over it is exactly 0.0 and stripping the accord from the register moves NO
## pair. Not approximately -- the eu's 15.0 and 0.50 ride the same sum, so any
## accidental price here would move every FRA-DEU relation and weight.
func _check_climate_accord_is_zero_priced() -> void:
	var state = _fresh()
	var accord = _loader.orgs_by_id[ACCORD]
	var effects: Dictionary = state.org_effects.get(ACCORD, {})
	_ok(is_equal_approx(float(effects.get("relations_bonus", -1.0)), 0.0)
		and is_equal_approx(float(effects.get("trade_bonus", -1.0)), 0.0),
		"the accord's effects snapshot carries a price")

	# Fixture viability: the pair must actually share the accord before we
	# measure its absence, or the identity below is vacuous.
	_ok(state.nations[PLAYER].orgs.has(ACCORD) and state.nations["DEU"].orgs.has(ACCORD),
		"FRA and DEU do not both hold the accord -- the fixture is broken")

	var rel_before: float = Org.shared_bonus(state, PLAYER, "DEU", "relations_bonus")
	var trade_before: float = Org.shared_bonus(state, PLAYER, "DEU", "trade_bonus")
	var weights_before: Dictionary = Trade.weights(state, PLAYER)
	var w_before: float = float(weights_before["DEU"])

	# Membership is live data, so removing the accord from the two orgs lists is
	# exactly what the machine reads as "a register without the accord".
	state.nations[PLAYER].orgs.erase(ACCORD)
	state.nations["DEU"].orgs.erase(ACCORD)

	_ok(Org.shared_bonus(state, PLAYER, "DEU", "relations_bonus") == rel_before,
		"stripping the accord moved FRA-DEU resting relations by %.17f" % [
		Org.shared_bonus(state, PLAYER, "DEU", "relations_bonus") - rel_before])
	_ok(Org.shared_bonus(state, PLAYER, "DEU", "trade_bonus") == trade_before,
		"stripping the accord moved the FRA-DEU shared trade bonus by %.17f" % [
		Org.shared_bonus(state, PLAYER, "DEU", "trade_bonus") - trade_before])
	var weights_after: Dictionary = Trade.weights(state, PLAYER)
	_ok(float(weights_after["DEU"]) == w_before,
		"stripping the accord moved the FRA-DEU trade weight by %.17f" % (float(weights_after["DEU"]) - w_before))


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

	# V4.5b: opened as orgs.gd's _tick_council() opens one -- the live sponsor
	# rides in the pending entry and lobbies the AI members at once. Every
	# shipped proposal has a sponsor now, so a bare division is a council the
	# game never runs, and the pivotal-band assertions below would measure it.
	var sponsor: String = Council.live_sponsor(state, proposal)
	state.orgs[proposal.org_id]["pending"] = {
		"proposal_id": proposal.id, "name": proposal.proposal_name,
		"summary": proposal.summary, "months_left": 1,
		"player_vote": Orgs.VOTE_ABSTAIN,
		"opened_year": state.year, "opened_month": state.month,
		"sponsor": sponsor,
	}
	if sponsor != "" and not state.nations[sponsor].has_budget:
		var supports := {}
		for id in Orgs.members(state, proposal.org_id):
			if not state.nations[id].has_budget:
				supports[id] = Orgs.support(state, state.nations[id], proposal)
		state.orgs[proposal.org_id]["pending"]["lobbied"] = Council.lobby(state, _loader, sponsor, supports)
	if not Orgs.cast_vote(state, proposal.org_id, choice):
		_fail("cast_vote(%s) was refused" % choice)
	Orgs.tick_month(state, _loader)
	return bool((Orgs.last_vote(state, proposal.org_id) as Dictionary).get("passed", false))
