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
