extends SceneTree

## Headless test: godot --headless --script res://tests/test_council.gd
## Non-zero exit on any failure.
##
## V4.5a, the contested council. Model: docs/orgs-model.md, "V4.5 -- the
## council, contested". Every check that needs content the shipped register
## does not carry yet (a presidency, a sponsor, a unanimity class) sets it on
## the loaded objects and RESTORES it in the same function -- the loader is
## shared across checks and a leaked field would make a later check measure
## a register nobody authored.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Org = preload("res://src/core/org.gd")
const BlocProposal = preload("res://src/core/bloc_proposal.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Council = preload("res://src/sim/council.gd")
const Ratification = preload("res://src/sim/ratification.gd")
const K = preload("res://src/sim/bloc_constants.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const RK = preload("res://src/core/relations.gd")

const PLAYER := "FRA"
const EU_ORG := "eu"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_constants_cohere()
	_check_org_fields_parse()
	_check_org_fields_refused()
	_check_proposal_fields_parse()
	_check_sponsor_must_be_a_member()
	_check_chair_is_the_calendar()
	_check_chair_skips_a_leaver()
	_check_decision_inherits_the_org()
	_check_drive_reads_the_head_of_government()
	_check_swing_signs_the_ask()
	_check_no_presidency_keeps_the_rotation()
	_check_an_ai_chair_opens_what_it_wants()
	_check_a_human_chair_sets_the_agenda()
	_check_tabling_costs_the_chair()
	_check_one_no_vetoes_a_treaty()
	_check_abstention_does_not_veto()
	_check_a_sponsor_lobbies_the_near_miss()
	_check_no_sponsor_lobbies_nobody()
	_check_the_sponsor_minds_the_vote()
	_check_a_favour_turns_a_member()
	_check_bargains_are_refused_honestly()
	_check_aid_pays_for_a_year()
	_check_a_vote_trade_comes_due()
	_check_a_treaty_waits_for_home()
	_check_ratified_is_adopted()
	_check_rejected_falls_for_all()
	_check_the_window_closes()
	_check_the_treaty_is_a_bill()
	_finish()


func _fresh(nation_id := PLAYER):
	return GameState.new_game(_loader, nation_id)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_fail(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_council: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("  FAIL: %s" % f)
	printerr("test_council: %d failure(s)" % _failures.size())
	quit(1)


# --- Part 0: the constants ---------------------------------------------------------

func _check_constants_cohere() -> void:
	# council.gd cannot preload orgs.gd, so it spells the ask itself; the two
	# spellings must be one.
	_ok(CouncilK.ASK_FOR == Orgs.VOTE_FOR, "ASK_FOR '%s' != Orgs.VOTE_FOR '%s'" % [CouncilK.ASK_FOR, Orgs.VOTE_FOR])
	_ok(CouncilK.ASK_AGAINST == Orgs.VOTE_AGAINST, "ASK_AGAINST '%s' != Orgs.VOTE_AGAINST '%s'" % [CouncilK.ASK_AGAINST, Orgs.VOTE_AGAINST])
	# Two treaties must never ratify in one council at once: the window closes
	# before the next proposal can even open.
	_ok(CouncilK.RATIFY_WINDOW_MONTHS < K.PROPOSAL_INTERVAL_MONTHS,
		"RATIFY_WINDOW_MONTHS %d must be below PROPOSAL_INTERVAL_MONTHS %d" % [CouncilK.RATIFY_WINDOW_MONTHS, K.PROPOSAL_INTERVAL_MONTHS])
	# A full-drive sponsor must be able to turn a member sitting at zero (the
	# honest "indifferent" anchor), or lobbying never moves an undecided member.
	_ok(CouncilK.LOBBY_SWING_PER_DRIVE > K.SUPPORT_THRESHOLD + CouncilK.LOBBY_MARGIN,
		"a full-drive sponsor cannot turn an indifferent member")
	# The currencies are ordered by price: favour < aid < vote trade.
	_ok(CouncilK.FAVOUR_SWING < CouncilK.AID_SWING and CouncilK.AID_SWING < CouncilK.IOU_SWING,
		"bargain swings are not ordered favour < aid < vote_trade")


# --- Part 1: content fields --------------------------------------------------------

func _org_dict(extra: Dictionary) -> Dictionary:
	var d := {
		"id": "probe_org", "name": "Probe Org", "council": true,
		"members": {"FRA": {"seats": 10}, "DEU": {"seats": 10}, "ITA": {"seats": 10}},
	}
	d.merge(extra, true)
	return d


func _check_org_fields_parse() -> void:
	var errors: Array[String] = []
	var plain = Org.from_dict(_org_dict({}), "probe.json", errors)
	_ok(errors.is_empty(), "a plain org refused: %s" % [errors])
	_ok(plain.decision_rule == CouncilK.DECISION_QMR, "an org with no decision_rule reads '%s', expected qmr" % plain.decision_rule)
	_ok(plain.presidency.is_empty(), "an org with no presidency carries one")

	errors = []
	var chaired = Org.from_dict(_org_dict({
		"decision_rule": "unanimity",
		"presidency": {"order": ["ITA", "FRA", "DEU"], "months": 6, "anchor": {"year": 2025, "month": 7}},
	}), "probe.json", errors)
	_ok(errors.is_empty(), "a chaired org refused: %s" % [errors])
	_ok(chaired.decision_rule == CouncilK.DECISION_UNANIMITY, "decision_rule did not parse")
	_ok(int(chaired.presidency.get("months", 0)) == 6, "presidency.months did not parse")
	_ok(int(chaired.presidency.get("anchor_index", -1)) == 2025 * 12 + 6, "presidency anchor_index is %d, expected %d" % [int(chaired.presidency.get("anchor_index", -1)), 2025 * 12 + 6])
	_ok((chaired.presidency.get("order", []) as Array) == ["ITA", "FRA", "DEU"], "presidency.order did not keep authored order")


func _check_org_fields_refused() -> void:
	var bad := [
		{"decision_rule": "consensus"},
		{"presidency": {"order": [], "months": 6, "anchor": {"year": 2025, "month": 1}}},
		{"presidency": {"order": ["FRA", "GBR"], "months": 6, "anchor": {"year": 2025, "month": 1}}},
		{"presidency": {"order": ["FRA", "FRA"], "months": 6, "anchor": {"year": 2025, "month": 1}}},
		{"presidency": {"order": ["FRA"], "months": 0, "anchor": {"year": 2025, "month": 1}}},
		{"presidency": {"order": ["FRA"], "months": 25, "anchor": {"year": 2025, "month": 1}}},
		{"presidency": {"order": ["FRA"], "months": 6, "anchor": {"year": 2025, "month": 13}}},
	]
	for extra in bad:
		var errors: Array[String] = []
		Org.from_dict(_org_dict(extra), "probe.json", errors)
		_ok(not errors.is_empty(), "malformed org field accepted silently: %s" % [extra])


func _proposal_dict(extra: Dictionary) -> Dictionary:
	var d := {
		"id": "probe_p", "org": EU_ORG, "name": "Probe", "summary": "",
		"position": {"economic": 0.0, "social": 0.0}, "transfer_pct_gdp": 0.05,
	}
	d.merge(extra, true)
	return d


func _check_proposal_fields_parse() -> void:
	var org_ids: Array = _loader.orgs_by_id.keys()
	var errors: Array[String] = []
	var plain = BlocProposal.from_dict(_proposal_dict({}), "probe.json", errors, org_ids)
	_ok(errors.is_empty(), "a plain proposal refused: %s" % [errors])
	_ok(plain.decision == "" and plain.sponsor == "", "a plain proposal carries a decision or a sponsor")

	errors = []
	var full = BlocProposal.from_dict(_proposal_dict({"decision": "unanimity", "sponsor": "DEU"}), "probe.json", errors, org_ids)
	_ok(errors.is_empty(), "a sponsored unanimity proposal refused: %s" % [errors])
	_ok(full.decision == CouncilK.DECISION_UNANIMITY and full.sponsor == "DEU", "decision/sponsor did not parse")

	errors = []
	BlocProposal.from_dict(_proposal_dict({"decision": "majority"}), "probe.json", errors, org_ids)
	_ok(not errors.is_empty(), "an unknown decision class was accepted")
	errors = []
	BlocProposal.from_dict(_proposal_dict({"sponsor": 7}), "probe.json", errors, org_ids)
	_ok(not errors.is_empty(), "a non-string sponsor was accepted")


func _check_sponsor_must_be_a_member() -> void:
	var p = _loader.bloc_proposals[0]
	var kept: String = p.sponsor
	var kept_errors: Array[String] = []
	kept_errors.append_array(_loader.errors)
	p.sponsor = "GBR"  # outside the eu by the authored register
	_loader.errors.clear()
	_loader._validate_bloc_proposals()
	_ok(not _loader.errors.is_empty(), "a sponsor outside the proposal's org was accepted")
	p.sponsor = kept
	_loader.errors.clear()
	_loader.errors.append_array(kept_errors)


# --- Part 2: the pure reads -------------------------------------------------------

## Sets a presidency on the loaded eu for the duration of `body`, restoring it
## after. Every Part-3+ check that needs a chair uses this.
func _with_presidency(order: Array, months: int, anchor_year: int, anchor_month: int) -> Dictionary:
	var org = _loader.orgs_by_id[EU_ORG]
	var kept: Dictionary = org.presidency
	org.presidency = {"order": order, "months": months, "anchor_index": anchor_year * 12 + (anchor_month - 1)}
	return kept


func _restore_presidency(kept: Dictionary) -> void:
	_loader.orgs_by_id[EU_ORG].presidency = kept


func _check_chair_is_the_calendar() -> void:
	var kept := _with_presidency(["ITA", "FRA", "DEU"], 6, 2025, 1)
	var state = _fresh()
	state.year = 2025
	state.month = 1
	_ok(Council.presiding_nation(state, _loader, EU_ORG) == "ITA", "Jan 2025 chair is '%s', expected ITA" % Council.presiding_nation(state, _loader, EU_ORG))
	state.month = 6
	_ok(Council.presiding_nation(state, _loader, EU_ORG) == "ITA", "Jun 2025 chair moved early")
	state.month = 7
	_ok(Council.presiding_nation(state, _loader, EU_ORG) == "FRA", "Jul 2025 chair is '%s', expected FRA" % Council.presiding_nation(state, _loader, EU_ORG))
	state.year = 2026
	state.month = 7
	_ok(Council.presiding_nation(state, _loader, EU_ORG) == "ITA", "the rotation did not wrap after three terms")
	# Before the anchor the rotation runs backwards honestly (posmod), not into a
	# negative index.
	state.year = 2024
	state.month = 12
	_ok(Council.presiding_nation(state, _loader, EU_ORG) == "DEU", "Dec 2024 chair is '%s', expected DEU" % Council.presiding_nation(state, _loader, EU_ORG))
	_restore_presidency(kept)
	_ok(Council.presiding_nation(_fresh(), _loader, EU_ORG) == "", "an org with no presidency has a chair")


func _check_chair_skips_a_leaver() -> void:
	var kept := _with_presidency(["ITA", "FRA", "DEU"], 6, 2025, 1)
	var state = _fresh()
	state.year = 2025
	state.month = 1
	state.nations["ITA"].orgs.erase(EU_ORG)
	_ok(Council.presiding_nation(state, _loader, EU_ORG) == "FRA", "a withdrawn chair was not skipped to the next member")
	_restore_presidency(kept)


func _check_decision_inherits_the_org() -> void:
	var p = _loader.org_proposals[EU_ORG][0]
	var org = _loader.orgs_by_id[EU_ORG]
	_ok(Council.decision_of(_loader, p) == CouncilK.DECISION_QMR, "a shipped proposal reads a decision other than qmr")
	var kept_rule: String = org.decision_rule
	org.decision_rule = CouncilK.DECISION_UNANIMITY
	_ok(Council.decision_of(_loader, p) == CouncilK.DECISION_UNANIMITY, "a proposal with no decision did not inherit its org's rule")
	p.decision = CouncilK.DECISION_QMR
	_ok(Council.decision_of(_loader, p) == CouncilK.DECISION_QMR, "a proposal's own decision did not override its org's")
	p.decision = ""
	org.decision_rule = kept_rule


func _check_drive_reads_the_head_of_government() -> void:
	var state = _fresh()
	var deu = state.nations["DEU"]
	var person = _loader.person_by_id.get(String(deu.pm_person_id), null)
	if person == null:
		_fail("DEU has no resolvable head of government at new-game (pm_person_id '%s') -- the sponsor face would always be the default" % deu.pm_person_id)
		return
	_ok(is_equal_approx(Council.drive(state, _loader, "DEU"), float(person.ambition)),
		"DEU drive %.3f != its head of government's ambition %.3f" % [Council.drive(state, _loader, "DEU"), float(person.ambition)])
	deu.pm_person_id = "nobody_at_all"
	_ok(is_equal_approx(Council.drive(state, _loader, "DEU"), CouncilK.SPONSOR_DRIVE_DEFAULT), "an unresolvable face did not fall back to the default drive")


func _check_swing_signs_the_ask() -> void:
	var pending := {
		"lobbied": {"DEU": 0.10},
		"bargains": {
			"DEU": {"currency": CouncilK.CURRENCY_FAVOUR, "ask": CouncilK.ASK_AGAINST, "swing": 0.15},
			"ITA": {"currency": CouncilK.CURRENCY_AID, "ask": CouncilK.ASK_FOR, "swing": 0.20},
		},
	}
	_ok(is_equal_approx(Council.swing(pending, "DEU"), -0.05), "DEU swing %.3f, expected 0.10 lobbied - 0.15 asked against" % Council.swing(pending, "DEU"))
	_ok(is_equal_approx(Council.swing(pending, "ITA"), 0.20), "ITA swing %.3f, expected +0.20" % Council.swing(pending, "ITA"))
	_ok(Council.swing({}, "DEU") == 0.0, "an empty pending produced a swing")


# --- Part 3: the agenda -----------------------------------------------------------

## Tick until this org opens a proposal; return its id ("" if none in `limit`).
func _tick_until_open(state, org_id: String, limit := K.PROPOSAL_INTERVAL_MONTHS + 2) -> String:
	for i in limit:
		Orgs.tick_month(state, _loader)
		var p: Dictionary = Orgs.pending(state, org_id)
		if not p.is_empty():
			return String(p["proposal_id"])
	return ""


func _check_no_presidency_keeps_the_rotation() -> void:
	# The inertness clause on the agenda: with no presidency the first proposal
	# opened is the authored list's first, exactly as V4.4 opened it.
	var state = _fresh()
	var first := _tick_until_open(state, EU_ORG)
	var expected: String = _loader.org_proposals[EU_ORG][0].id
	_ok(first == expected, "with no presidency the eu opened '%s', expected rotation's '%s'" % [first, expected])
	_ok(String(Orgs.pending(state, EU_ORG).get("sponsor", "x")) == "", "an unsponsored proposal opened with a sponsor")


func _check_an_ai_chair_opens_what_it_wants() -> void:
	var state = _fresh()
	# Chair DEU for the whole run (one-member order is a legal rotation).
	var kept := _with_presidency(["DEU"], 6, 2000, 1)
	var best = null
	var best_s := -INF
	for p in _loader.org_proposals[EU_ORG]:
		var s: float = Orgs.support(state, state.nations["DEU"], p)
		if s > best_s:
			best_s = s
			best = p
	var opened := _tick_until_open(state, EU_ORG)
	_ok(opened == best.id, "DEU chair opened '%s', expected its most-supported '%s'" % [opened, best.id])
	_restore_presidency(kept)


func _check_a_human_chair_sets_the_agenda() -> void:
	var kept := _with_presidency([PLAYER], 6, 2000, 1)
	var state = _fresh()
	var choice: String = _loader.org_proposals[EU_ORG][2].id
	_ok(Orgs.set_agenda(state, _loader, EU_ORG, choice), "set_agenda refused while the player chairs")
	_ok(_tick_until_open(state, EU_ORG) == choice, "the chair's choice was not what opened")
	_ok(String(state.orgs[EU_ORG]["agenda_choice"]) == "", "the agenda choice was not consumed")
	_restore_presidency(kept)

	var kept2 := _with_presidency(["DEU"], 6, 2000, 1)
	var other = _fresh()
	_ok(not Orgs.set_agenda(other, _loader, EU_ORG, choice), "set_agenda accepted while DEU chairs")
	_ok(not Orgs.set_agenda(other, _loader, "no_such_org", choice), "set_agenda accepted an unknown org")
	_restore_presidency(kept2)


func _check_tabling_costs_the_chair() -> void:
	var kept := _with_presidency(["DEU"], 6, 2000, 1)
	var state = _fresh()
	var choice: String = _loader.org_proposals[EU_ORG][3].id
	var before: float = RK.score(state, PLAYER, "DEU")
	_ok(Orgs.table_proposal(state, _loader, EU_ORG, choice), "table_proposal refused")
	_ok(is_equal_approx(RK.score(state, PLAYER, "DEU"), before - CouncilK.TABLE_RELATIONS_COST),
		"tabling cost %.2f relations with the chair, expected %.2f" % [before - RK.score(state, PLAYER, "DEU"), CouncilK.TABLE_RELATIONS_COST])
	_ok(not Orgs.table_proposal(state, _loader, EU_ORG, _loader.org_proposals[EU_ORG][4].id), "a second tabling was accepted while one is queued")
	_ok(_tick_until_open(state, EU_ORG) == choice, "the tabled proposal did not open first")
	_ok(String(Orgs.pending(state, EU_ORG).get("sponsor", "")) == PLAYER, "a tabled proposal is not sponsored by whoever tabled it")
	_restore_presidency(kept)

	# No chair, nobody to ask.
	var unchaired = _fresh()
	_ok(not Orgs.table_proposal(unchaired, _loader, EU_ORG, choice), "tabling accepted in a council with no presidency")


# --- Part 4: unanimity -------------------------------------------------------------

## test_orgs.gd's _force_vote, with `decision` set on the proposal for the call.
## `all_for` swings every AI member to FOR (a lobbied 1.0 each, which _vote_of
## adds through Council.swing) so a unanimity check never depends on whether all 26 others happen to back the fixture at
## EU-27 -- bloc-model's "carried by every member" was measured at nine.
func _force(state, proposal_id: String, choice: String, decision := "", all_for := false) -> bool:
	var proposal = Orgs.proposal_by_id(_loader, EU_ORG, proposal_id)
	if proposal == null:
		_fail("no eu proposal '%s'" % proposal_id)
		return false
	var kept: String = proposal.decision
	proposal.decision = decision
	var lobbied := {}
	if all_for:
		for id in Orgs.members(state, EU_ORG):
			if id != PLAYER:
				lobbied[id] = 1.0
	state.orgs[EU_ORG]["pending"] = {
		"proposal_id": proposal.id, "name": proposal.proposal_name,
		"summary": proposal.summary, "months_left": 1,
		"player_vote": Orgs.VOTE_ABSTAIN, "sponsor": Council.live_sponsor(state, proposal),
		"lobbied": lobbied,
		"opened_year": state.year, "opened_month": state.month,
	}
	if not Orgs.cast_vote(state, EU_ORG, choice):
		_fail("cast_vote(%s) refused" % choice)
	Orgs.tick_month(state, _loader)
	proposal.decision = kept
	return bool((Orgs.last_vote(state, EU_ORG) as Dictionary).get("passed", false))


func _check_one_no_vetoes_a_treaty() -> void:
	# recovery_facility is carried by every member (bloc-model §6): under QMR the
	# player is outvoted; under unanimity the player's no is a veto.
	var qmr = _fresh()
	_ok(_force(qmr, "recovery_facility", Orgs.VOTE_AGAINST), "recovery_facility fell under qmr -- the fixture moved")
	var una = _fresh()
	_ok(not _force(una, "recovery_facility", Orgs.VOTE_AGAINST, CouncilK.DECISION_UNANIMITY, true), "the player's no did not veto a unanimity proposal")
	var last: Dictionary = Orgs.last_vote(una, EU_ORG)
	_ok((last.get("vetoed_by", []) as Array) == [PLAYER], "vetoed_by is %s, expected [FRA]" % [last.get("vetoed_by", [])])
	_ok(String(last.get("decision", "")) == CouncilK.DECISION_UNANIMITY, "last_vote does not record its decision class")


func _check_abstention_does_not_veto() -> void:
	var una = _fresh()
	_ok(_force(una, "recovery_facility", Orgs.VOTE_ABSTAIN, CouncilK.DECISION_UNANIMITY, true),
		"an abstention blocked a unanimity proposal every other member backs -- constructive abstention is gone")


# --- Part 5: sponsors --------------------------------------------------------------

func _check_a_sponsor_lobbies_the_near_miss() -> void:
	var state = _fresh()
	# Build supports for every AI member, then pick one we can place in reach by
	# construction: the lobby turns members short by <= drive * LOBBY_SWING_PER_DRIVE.
	var supports := {"ITA": K.SUPPORT_THRESHOLD - 0.05, "ESP": K.SUPPORT_THRESHOLD - 0.90, "NLD": K.SUPPORT_THRESHOLD + 0.30}
	var before_ita: float = RK.score(state, "DEU", "ITA")
	var lobbied: Dictionary = Council.lobby(state, _loader, "DEU", supports)
	var cap: float = Council.drive(state, _loader, "DEU") * CouncilK.LOBBY_SWING_PER_DRIVE
	if cap < 0.05 + CouncilK.LOBBY_MARGIN:
		_fail("DEU's drive %.2f cannot close a 0.05 gap -- pick a fixture inside its reach" % Council.drive(state, _loader, "DEU"))
		return
	_ok(lobbied.has("ITA"), "the sponsor did not lobby a member 0.05 short")
	_ok(not lobbied.has("ESP"), "the sponsor lobbied a member far out of reach")
	_ok(not lobbied.has("NLD"), "the sponsor lobbied a member already for it")
	var swing_ita: float = float(lobbied.get("ITA", 0.0))
	_ok(supports["ITA"] + swing_ita >= K.SUPPORT_THRESHOLD, "the lobby's swing did not turn ITA")
	_ok(is_equal_approx(before_ita - RK.score(state, "DEU", "ITA"), swing_ita * CouncilK.LOBBY_RELATIONS_PER_SWING),
		"lobbying ITA cost DEU %.3f relations, expected %.3f" % [before_ita - RK.score(state, "DEU", "ITA"), swing_ita * CouncilK.LOBBY_RELATIONS_PER_SWING])
	# A human sponsor bargains by hand, never by this automatic path.
	_ok(Council.lobby(state, _loader, PLAYER, supports).is_empty(), "the player's nation lobbied automatically")


func _check_no_sponsor_lobbies_nobody() -> void:
	var state = _fresh()
	_tick_until_open(state, EU_ORG)
	_ok(not (Orgs.pending(state, EU_ORG) as Dictionary).has("lobbied")
		or ((Orgs.pending(state, EU_ORG) as Dictionary)["lobbied"] as Dictionary).is_empty(),
		"an unsponsored proposal opened with lobbying")


func _check_the_sponsor_minds_the_vote() -> void:
	var p = Orgs.proposal_by_id(_loader, EU_ORG, "recovery_facility")
	var kept: String = p.sponsor
	p.sponsor = "DEU"
	var d: float
	var backed = _fresh()
	d = Council.drive(backed, _loader, "DEU")
	var b0: float = RK.score(backed, PLAYER, "DEU")
	_force_sponsored(backed, p, Orgs.VOTE_FOR)
	_ok(is_equal_approx(RK.score(backed, PLAYER, "DEU") - b0, CouncilK.SPONSOR_THANKS * d),
		"backing DEU's proposal moved FRA-DEU by %.3f, expected +%.3f" % [RK.score(backed, PLAYER, "DEU") - b0, CouncilK.SPONSOR_THANKS * d])
	var opposed = _fresh()
	var o0: float = RK.score(opposed, PLAYER, "DEU")
	_force_sponsored(opposed, p, Orgs.VOTE_AGAINST)
	_ok(is_equal_approx(o0 - RK.score(opposed, PLAYER, "DEU"), CouncilK.SPONSOR_SNUB * d),
		"opposing DEU's proposal moved FRA-DEU by %.3f, expected -%.3f" % [RK.score(opposed, PLAYER, "DEU") - o0, CouncilK.SPONSOR_SNUB * d])
	var abstained = _fresh()
	var a0: float = RK.score(abstained, PLAYER, "DEU")
	_force_sponsored(abstained, p, Orgs.VOTE_ABSTAIN)
	_ok(RK.score(abstained, PLAYER, "DEU") == a0, "abstaining on DEU's proposal moved relations")
	p.sponsor = kept


## Opens `p` with its sponsor recorded, casts, divides. Relations drift is
## Diplomacy's (not ticked here), so a delta is exactly the sponsor's answer.
func _force_sponsored(state, p, choice: String) -> void:
	state.orgs[EU_ORG]["pending"] = {
		"proposal_id": p.id, "name": p.proposal_name, "summary": p.summary,
		"months_left": 1, "player_vote": Orgs.VOTE_ABSTAIN,
		"sponsor": Council.live_sponsor(state, p),
		"opened_year": state.year, "opened_month": state.month,
	}
	Orgs.cast_vote(state, EU_ORG, choice)
	Orgs.tick_month(state, _loader)


# --- Part 6: bargains --------------------------------------------------------------

## Open `proposal_id` in the eu with the player's vote cast, WITHOUT dividing.
func _open(state, proposal_id: String, sponsor := "") -> void:
	var p = Orgs.proposal_by_id(_loader, EU_ORG, proposal_id)
	state.orgs[EU_ORG]["pending"] = {
		"proposal_id": p.id, "name": p.proposal_name, "summary": p.summary,
		"months_left": 1, "player_vote": Orgs.VOTE_ABSTAIN, "sponsor": sponsor,
		"opened_year": state.year, "opened_month": state.month,
	}


## A member whose bare appraisal of `proposal_id` sits below the threshold by
## less than `swing` -- one a bargain of that size turns. "" if none.
func _turnable(state, proposal_id: String, swing: float) -> String:
	var p = Orgs.proposal_by_id(_loader, EU_ORG, proposal_id)
	for id in Orgs.members(state, EU_ORG):
		if id == PLAYER:
			continue
		var s: float = Orgs.support(state, state.nations[id], p)
		if s < K.SUPPORT_THRESHOLD and s + swing >= K.SUPPORT_THRESHOLD:
			return id
	return ""


func _check_a_favour_turns_a_member() -> void:
	var state = _fresh()
	var subject := ""
	var target := ""
	for p in _loader.org_proposals[EU_ORG]:
		target = _turnable(state, p.id, CouncilK.FAVOUR_SWING)
		if target != "" and RK.score(state, PLAYER, target) >= CouncilK.FAVOUR_MIN_RELATIONS:
			subject = p.id
			break
	if subject == "":
		_fail("no eu member is within a favour's reach on any shipped proposal -- the cheapest currency is decorative")
		return
	_open(state, subject)
	var r0: float = RK.score(state, PLAYER, target)
	_ok(Council.bargain(state, EU_ORG, target, CouncilK.CURRENCY_FAVOUR, CouncilK.ASK_FOR), "a favour was refused")
	_ok(is_equal_approx(r0 - RK.score(state, PLAYER, target), CouncilK.FAVOUR_RELATIONS_COST), "a favour cost the wrong relations")
	Orgs.tick_month(state, _loader)
	var last: Dictionary = Orgs.last_vote(state, EU_ORG)
	_ok(String((last.get("votes", {}) as Dictionary).get(target, "")) == Orgs.VOTE_FOR, "%s did not vote as the favour asked" % target)
	_ok(String((last.get("reasons", {}) as Dictionary).get(target, "")) == CouncilK.REASON_BARGAINED, "the division does not name the bargain that turned %s" % target)


func _check_bargains_are_refused_honestly() -> void:
	var state = _fresh()
	var subject: String = _loader.org_proposals[EU_ORG][0].id
	_ok(not Council.bargain(state, EU_ORG, "DEU", CouncilK.CURRENCY_FAVOUR, CouncilK.ASK_FOR), "a bargain with nothing pending was accepted")
	_open(state, subject)
	_ok(not Council.bargain(state, EU_ORG, "DEU", "posting", CouncilK.ASK_FOR), "a refused currency was accepted")
	_ok(not Council.bargain(state, EU_ORG, "DEU", CouncilK.CURRENCY_FAVOUR, "abstain"), "an ask other than for/against was accepted")
	_ok(not Council.bargain(state, EU_ORG, PLAYER, CouncilK.CURRENCY_FAVOUR, CouncilK.ASK_FOR), "the player bargained with itself")
	_ok(not Council.bargain(state, EU_ORG, "GBR", CouncilK.CURRENCY_FAVOUR, CouncilK.ASK_FOR), "a bargain with a non-member was accepted")
	RK.adjust(state, PLAYER, "DEU", -100.0, 0.0, 100.0)
	_ok(not Council.bargain(state, EU_ORG, "DEU", CouncilK.CURRENCY_FAVOUR, CouncilK.ASK_FOR), "a favour below FAVOUR_MIN_RELATIONS was accepted")
	_ok(Council.bargain(state, EU_ORG, "ITA", CouncilK.CURRENCY_AID, CouncilK.ASK_FOR), "aid was refused")
	_ok(not Council.bargain(state, EU_ORG, "ITA", CouncilK.CURRENCY_FAVOUR, CouncilK.ASK_FOR), "a second bargain with one member in one division was accepted")


func _check_aid_pays_for_a_year() -> void:
	var state = _fresh()
	var ns = state.player()
	Orgs.tick_month(state, _loader)
	var base: float = ns.bloc_transfer_pct_gdp
	_open(state, _loader.org_proposals[EU_ORG][0].id)
	state.orgs[EU_ORG]["pending"]["months_left"] = 99  # keep it open; we measure the line, not the vote
	Council.bargain(state, EU_ORG, "ITA", CouncilK.CURRENCY_AID, CouncilK.ASK_FOR)
	var paid := 0
	for i in CouncilK.AID_MONTHS + 3:
		Orgs.tick_month(state, _loader)
		if ns.bloc_transfer_pct_gdp > base + CouncilK.AID_PCT_GDP * 0.5:
			paid += 1
	_ok(paid == CouncilK.AID_MONTHS, "aid was paid %d months, expected exactly %d" % [paid, CouncilK.AID_MONTHS])


func _check_a_vote_trade_comes_due() -> void:
	var p = Orgs.proposal_by_id(_loader, EU_ORG, "recovery_facility")
	var kept: String = p.sponsor
	p.sponsor = "ITA"

	# Paid: the IOU is cleared and costs nothing.
	var paid = _fresh()
	_open(paid, _loader.org_proposals[EU_ORG][0].id)
	Council.bargain(paid, EU_ORG, "ITA", CouncilK.CURRENCY_VOTE_TRADE, CouncilK.ASK_FOR)
	Orgs.tick_month(paid, _loader)
	_ok((paid.orgs[EU_ORG]["debts"] as Array).size() == 1, "a vote trade did not record a debt")
	_force_sponsored(paid, p, Orgs.VOTE_FOR)
	_ok((paid.orgs[EU_ORG]["debts"] as Array).is_empty(), "backing the creditor's proposal did not clear the debt")

	# Betrayed: cleared, and the betrayal is priced on top of the sponsor's snub.
	var betrayed = _fresh()
	_open(betrayed, _loader.org_proposals[EU_ORG][0].id)
	Council.bargain(betrayed, EU_ORG, "ITA", CouncilK.CURRENCY_VOTE_TRADE, CouncilK.ASK_FOR)
	Orgs.tick_month(betrayed, _loader)
	var r0: float = RK.score(betrayed, PLAYER, "ITA")
	_force_sponsored(betrayed, p, Orgs.VOTE_AGAINST)
	var expected: float = CouncilK.IOU_BETRAYAL + CouncilK.SPONSOR_SNUB * Council.drive(betrayed, _loader, "ITA")
	_ok(is_equal_approx(r0 - RK.score(betrayed, PLAYER, "ITA"), expected),
		"betraying the IOU cost %.3f, expected %.3f" % [r0 - RK.score(betrayed, PLAYER, "ITA"), expected])
	_ok((betrayed.orgs[EU_ORG]["debts"] as Array).is_empty(), "a betrayed debt was not cleared")

	# Lapsed: an unpaid IOU expires silently.
	var lapsed = _fresh()
	_open(lapsed, _loader.org_proposals[EU_ORG][0].id)
	Council.bargain(lapsed, EU_ORG, "ITA", CouncilK.CURRENCY_VOTE_TRADE, CouncilK.ASK_FOR)
	for i in CouncilK.IOU_EXPIRY_MONTHS + 1:
		Council.tick_register(lapsed, EU_ORG)
	_ok((lapsed.orgs[EU_ORG]["debts"] as Array).is_empty(), "an IOU outlived IOU_EXPIRY_MONTHS")
	p.sponsor = kept


# --- Part 7: ratification at home ---------------------------------------------------

func _carry_treaty(state) -> void:
	_force(state, "recovery_facility", Orgs.VOTE_FOR, CouncilK.DECISION_UNANIMITY, true)


func _check_a_treaty_waits_for_home() -> void:
	var state = _fresh()
	_carry_treaty(state)
	var r: Dictionary = state.orgs[EU_ORG]["ratifying"]
	_ok(String(r.get("proposal_id", "")) == "recovery_facility", "a carried unanimity proposal did not go to ratification")
	_ok(not (state.orgs[EU_ORG]["rules"] as Dictionary).has("recovery_facility"), "a treaty was adopted before it was ratified")
	_ok(String((r.get("nations", {}) as Dictionary).get(PLAYER, "")) == CouncilK.RATIFY_PENDING, "the player is not asked to ratify")
	_ok(String(Orgs.last_vote(state, EU_ORG).get("ratification", "")) == "pending", "last_vote does not say ratification is pending")
	# QMR binds directly -- no ratification.
	var qmr = _fresh()
	_force(qmr, "recovery_facility", Orgs.VOTE_FOR)
	_ok((qmr.orgs[EU_ORG]["ratifying"] as Dictionary).is_empty(), "a qmr proposal went to ratification")
	_ok((qmr.orgs[EU_ORG]["rules"] as Dictionary).has("recovery_facility"), "a carried qmr proposal was not adopted")


func _check_ratified_is_adopted() -> void:
	var state = _fresh()
	_carry_treaty(state)
	Orgs.record_ratification(state, _loader, EU_ORG, PLAYER, true)
	_ok((state.orgs[EU_ORG]["rules"] as Dictionary).has("recovery_facility"), "a ratified treaty was not adopted")
	_ok((state.orgs[EU_ORG]["ratifying"] as Dictionary).is_empty(), "ratification did not close")
	_ok(String(Orgs.last_vote(state, EU_ORG).get("ratification", "")) == "ratified", "last_vote does not record the ratification")


func _check_rejected_falls_for_all() -> void:
	var p = Orgs.proposal_by_id(_loader, EU_ORG, "recovery_facility")
	var kept: String = p.sponsor
	p.sponsor = "DEU"
	var state = _fresh()
	_carry_treaty(state)
	var d0: float = RK.score(state, PLAYER, "DEU")
	var i0: float = RK.score(state, PLAYER, "ITA")
	Orgs.record_ratification(state, _loader, EU_ORG, PLAYER, false)
	_ok(not (state.orgs[EU_ORG]["rules"] as Dictionary).has("recovery_facility"), "a rejected treaty was adopted")
	_ok((state.orgs[EU_ORG]["ratifying"] as Dictionary).is_empty(), "a rejected treaty is still ratifying")
	_ok(String(Orgs.last_vote(state, EU_ORG).get("ratification", "")) == "failed", "last_vote does not record the failure")
	var drive: float = Council.drive(state, _loader, "DEU")
	_ok(is_equal_approx(d0 - RK.score(state, PLAYER, "DEU"), CouncilK.RATIFY_FAIL_SPONSOR * drive), "the sponsor's price for a killed treaty is wrong")
	_ok(is_equal_approx(i0 - RK.score(state, PLAYER, "ITA"), CouncilK.RATIFY_FAIL_MEMBER), "a bystander's price for a killed treaty is wrong")
	p.sponsor = kept


func _check_the_window_closes() -> void:
	var state = _fresh()
	_carry_treaty(state)
	for i in CouncilK.RATIFY_WINDOW_MONTHS:
		Orgs.tick_month(state, _loader)
	_ok((state.orgs[EU_ORG]["ratifying"] as Dictionary).is_empty(), "the ratification window did not close")
	_ok(not (state.orgs[EU_ORG]["rules"] as Dictionary).has("recovery_facility"), "an unratified treaty was adopted when the window closed")


func _check_the_treaty_is_a_bill() -> void:
	var state = _fresh()
	_carry_treaty(state)
	var forecast: Dictionary = Ratification.forecast(state, _loader, EU_ORG)
	_ok(forecast.has("yes_seats") and forecast.has("party_votes"), "the ratification forecast is not Legislature.resolve_vote()'s result")
	_ok(String(forecast.get("law_id", "")) == "treaty:recovery_facility", "the treaty bill's id is '%s'" % forecast.get("law_id", ""))
	var result: Dictionary = Ratification.submit(state, _loader, EU_ORG)
	_ok(bool(result.get("passed", false)) == bool(forecast.get("passed", false)) or result.has("upper_passed"),
		"submit() disagreed with its own forecast with no upper chamber in the way")
	_ok((state.orgs[EU_ORG]["ratifying"] as Dictionary).is_empty(), "submit() did not settle the ratification")
	_ok(bool(Ratification.submit(state, _loader, EU_ORG).get("refused", false)), "a second submit with nothing ratifying was not refused")
