extends SceneTree

## The V3.5 climate block's instrument:
## godot --headless --script res://tools/climate_probe.gd
##
## measure_austerity_peak.gd's precedent: the committed tool a later session can
## re-run rather than re-derive. Tables, in the order they were needed:
##
##   (a) THE DERIVED CEILING. The constraint's value is not authored -- it is the
##       EU-27 population-weighted mean of the nations' measured
##       co2e_per_capita_t at new-game, rounded to 0.5, the placement discipline
##       CONTRIBUTION_MAX_PCT_GDP's re-derivation set. This table recomputes it
##       from the committed files and prints MATCH or MISMATCH against the value
##       the loaded proposal carries; on a mismatch THE PROBE'S NUMBER WINS and
##       the file has to be corrected.
##
##   (b) THE REAL DIVISION. The ceiling's tally three ways -- France for,
##       abstaining, against -- over a live new-game state, with every member's
##       vote and vote_reason key. The player's 69 of 452 seats were placed
##       inside the pivotal band by the sweep at the bottom of this file; this
##       table proves the shipped position landed there. The solidarity clause
##       is divided the same way and is authored OUTSIDE the band: a coalition's
##       question, not France's.
##
##   (c) THE WAY IN. GBR and CHE accession (and withdrawal) positions swept on
##       Referendum.yes_share() to the 0.510-0.523-at-rest band, V3.2's
##       discipline: winnable by a president the country does not hate, losable
##       by one it does. Swept BEFORE the numbers went into the file.
##
##   (d) THE OWED MEASUREMENT. orgs-model.md's named bound: "a nation defying
##       every eu rule gains no opinion price from defying a second org's rule
##       ... the session that authors a second rule-carrying org owes the
##       re-measurement". The accord is that org. One real rule per org in
##       force, France breaching all three past the full tolerance: per-org
##       Orgs.org_burden, the summed RAW total, and BURDEN_MAX. The clamp
##       contact -- or its absence at one rule per org -- is the finding.
##       Table (d2) puts every authored rule of all three orgs in force, which
##       is total defiance of the whole register.
##
##   (s) THE SWEEPS THAT PLACED THE CONTENT, kept so the placement is
##       reproducible: (s1) the ceiling's tolerance x position grid read as
##       other-members-for seats, the pivotal band marked; (s2) the solidarity
##       clause's position grid; (s3) the accession grid for GBR and CHE. The
##       sweep tallies CANDIDATE proposals built through
##       BlocProposal.from_dict() and scored through Orgs.support() -- the real
##       vote machinery on synthetic questions; the candidates are never
##       committed content.
##
## Before the accord's content loads, the sweep tables seed a synthetic live
## register (membership + seats + an empty council register) by the
## tests/test_orgs.gd "test_org" idiom -- membership is live data, and appending
## an id is what a won fight does. With content loaded the seed never runs.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const BK = preload("res://src/sim/bloc_constants.gd")
const BlocProposal = preload("res://src/core/bloc_proposal.gd")
const Referendum = preload("res://src/sim/referendum.gd")
const OK = preload("res://src/sim/opinion_constants.gd")

const PLAYER := "FRA"
const EU_ORG := "eu"
const ACCORD := "climate_accord"
const CEILING := "emissions_ceiling"
const SOLIDARITY := "climate_solidarity_clause"

## The pivotal band in OTHER MEMBERS' for-seats. France holds 69 of 452; the
## others hold 383. The ceiling carries on an abstention while
## others_for >= 0.55 x 383 = 210.65, and blocks once her 69 join the
## opposition while others_for < 0.55 x 452 = 248.6.
const BAND_MIN := 211
const BAND_MAX := 248

const SWEEP_STEP := 0.1

## Table (c)'s own step. Finer than the tally sweeps because a yes_share contour
## is narrow near the band edges -- at 0.1 the right-of-centre region held ONE
## in-band cell, which is a placement made on a cliff rather than a plateau.
const POSITION_STEP := 0.05


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	var state = GameState.new_game(loader, PLAYER)
	var accord = loader.orgs_by_id.get(ACCORD, null)
	if accord == null:
		# Content not loaded yet: seed the synthetic register the sweeps tally
		# against, so the instrument runs ahead of its own content -- the split
		# tools/orgs_probe.gd documents for exactly this ordering.
		print("## climate_accord not loaded -- seeding a synthetic live register for the sweeps")
		_seed_synthetic(loader, state)

	_table_a(loader)
	_table_b(loader)
	_table_c(loader, accord)
	_table_d(loader)
	_ceiling_sweep(loader, state)
	_solidarity_sweep(loader, state)
	quit(0)


## The sweep's pre-content seed. NOT the content path: the seats are derived
## here by the NATO rule from live population, and nothing this writes is
## serialised -- the state is the probe's own.
func _seed_synthetic(loader, state) -> void:
	state.orgs[ACCORD] = {
		"rules": {}, "pending": {}, "last_vote": {}, "next_index": 0,
		"months_to_next": BK.PROPOSAL_INTERVAL_MONTHS,
	}
	state.org_effects[ACCORD] = {"relations_bonus": 0.0, "trade_bonus": 0.0}
	for id in loader.orgs_by_id[EU_ORG].members.keys():
		var ns = state.nations[id]
		if not ns.orgs.has(ACCORD):
			ns.orgs.append(ACCORD)
			ns.orgs.sort()
		ns.org_seats[ACCORD] = int(round(float(loader.nations[id].population) / 1000000.0))


func _accord_seats(loader, id: String) -> int:
	var accord = loader.orgs_by_id.get(ACCORD, null)
	if accord != null and accord.is_member(id):
		return accord.seats(id)
	var eu = loader.orgs_by_id[EU_ORG]
	if eu.is_member(id):
		return int(round(float(loader.nations[id].population) / 1000000.0))
	return 0


# --- (a) the derived ceiling --------------------------------------------------------

func _table_a(loader) -> void:
	print("\n########## (a) start per-capita emissions, and the derived ceiling ##########")
	var eu = loader.orgs_by_id[EU_ORG]
	var accord = loader.orgs_by_id.get(ACCORD, null)

	var ids: Array = loader.nations.keys()
	ids.sort()
	var mean_num := 0.0
	var mean_den := 0.0
	for id in eu.members.keys():
		mean_num += float(loader.nations[id].co2e_per_capita_t) * float(loader.nations[id].population)
		mean_den += float(loader.nations[id].population)
	var mean: float = mean_num / mean_den
	var ceiling: float = round(mean * 2.0) / 2.0

	print("%-5s %7s %11s %7s %8s" % ["id", "t/cap", "population", "seats", "inside?"])
	print("-".repeat(44))
	var inside := 0
	for id in ids:
		var n = loader.nations[id]
		var is_eu: bool = eu.is_member(id)
		var mark := ""
		if is_eu:
			var yes: bool = float(n.co2e_per_capita_t) <= ceiling
			mark = "yes" if yes else "BREACH"
			if yes:
				inside += 1
		print("%-5s %7.2f %11d %7s %8s" % [
			id, float(n.co2e_per_capita_t), int(n.population),
			str(_accord_seats(loader, id)) if is_eu else "--", mark,
		])
	print("-".repeat(44))
	print("EU-27 population-weighted mean: %.6f t/capita" % mean)
	print("Rounded to 0.5: %.1f t -- the ceiling the proposal carries" % ceiling)
	print("Members inside at start: %d of 27 (the division is real before anyone builds anything)" % inside)

	if accord != null:
		for p in loader.org_proposals.get(ACCORD, []):
			if p.id != CEILING:
				continue
			var authored: float = float(p.constraint.get("value", 0.0))
			var verdict := "MATCH" if is_equal_approx(authored, ceiling) else "MISMATCH -- the probe's number wins; correct the file"
			print("Loaded proposal carries %.1f: %s" % [authored, verdict])
	else:
		print("No loaded proposal to compare against (content not authored yet).")


# --- (b) the real division ----------------------------------------------------------

func _table_b(loader) -> void:
	print("\n\n########## (b) the real divisions, three ways ##########")
	_division(loader, CEILING)
	_division(loader, SOLIDARITY)


func _division(loader, proposal_id: String) -> void:
	var tally := {}
	var reasons := {}
	var votes := {}
	for choice in [Orgs.VOTE_FOR, Orgs.VOTE_ABSTAIN, Orgs.VOTE_AGAINST]:
		var state = GameState.new_game(loader, PLAYER)
		if not state.orgs.has(ACCORD):
			print("\n%s: no %s register -- content not loaded, skipping" % [proposal_id, ACCORD])
			return
		state.orgs[ACCORD]["pending"] = {
			"proposal_id": proposal_id, "name": proposal_id, "summary": "",
			"months_left": 1, "player_vote": Orgs.VOTE_ABSTAIN,
			"opened_year": state.year, "opened_month": state.month,
		}
		Orgs.cast_vote(state, ACCORD, choice)
		Orgs.tick_month(state, loader)
		var lv: Dictionary = Orgs.last_vote(state, ACCORD)
		tally[choice] = lv
		reasons[choice] = lv.get("reasons", {})
		votes[choice] = lv.get("votes", {})

	print("\n%s:" % proposal_id)
	for choice in [Orgs.VOTE_FOR, Orgs.VOTE_ABSTAIN, Orgs.VOTE_AGAINST]:
		var lv: Dictionary = tally[choice]
		print("  player %-8s -> for %3d against %3d cast %3d  %s" % [
			choice, int(lv.get("seats_for", 0)), int(lv.get("seats_against", 0)),
			int(lv.get("seats_for", 0)) + int(lv.get("seats_against", 0)),
			"PASSED" if bool(lv.get("passed", false)) else "failed",
		])
	var pivotal: bool = bool((tally[Orgs.VOTE_FOR] as Dictionary).get("passed", false)) \
		!= bool((tally[Orgs.VOTE_AGAINST] as Dictionary).get("passed", false))
	print("  player pivotal: %s" % ("YES" if pivotal else "no"))

	# The member table. A member's vote and reason do not depend on how France
	# casts -- the three vote columns say so and the reason is read off the
	# abstained division's own record (the books they voted on).
	print("  %-5s %5s  %-22s %s" % ["id", "seats", "vote (for/abst/against)", "reason key"])
	print("  " + "-".repeat(58))
	var abstain_votes: Dictionary = votes[Orgs.VOTE_ABSTAIN]
	var ordered: Array = abstain_votes.keys()
	ordered.sort()
	for id in ordered:
		var v1 := String((votes[Orgs.VOTE_FOR] as Dictionary).get(id, "?"))
		var v2 := String(abstain_votes.get(id, "?"))
		var v3 := String((votes[Orgs.VOTE_AGAINST] as Dictionary).get(id, "?"))
		print("  %-5s %5d  %-22s %s%s" % [
			id, _accord_seats(loader, id), "%s/%s/%s" % [v1, v2, v3],
			String((reasons[Orgs.VOTE_ABSTAIN] as Dictionary).get(id, "")),
			"   <- the player casts" if id == PLAYER else "",
		])


# --- (c) the way in -----------------------------------------------------------------

func _table_c(loader, accord) -> void:
	print("\n\n########## (c) GBR and CHE accession, swept on Referendum.yes_share ##########")

	# The instrument: a neutral-approval new-game. The guard is the test's:
	# the sweep measured THIS state, so a re-run on another is a different table.
	var gbr_state = GameState.new_game(loader, "GBR")
	var che_state = GameState.new_game(loader, "CHE")
	for pair in [[gbr_state.player(), "GBR"], [che_state.player(), "CHE"]]:
		var ns = pair[0]
		for bloc in OK.BLOC_KEYS:
			if not is_equal_approx(float(ns.bloc_approval.get(bloc, 0.0)), float(OK.APPROVAL_NEUTRAL)):
				print("  GUARD: %s's %s approval reads %s, not neutral -- the sweep's premise is gone" % [
					pair[1], bloc, str(ns.bloc_approval.get(bloc, 0.0))])

	var gbr = gbr_state.player()
	var che = che_state.player()

	print("  two-axis grid at %.2f steps; printing the 0.510-0.523 band only" % POSITION_STEP)
	print("  %5s %7s %9s %9s" % ["econ", "social", "GBR yes", "CHE yes"])
	print("  " + "-".repeat(34))
	var econ := -1.0
	while econ <= 1.001:
		var social := -1.0
		while social <= 1.001:
			var position := {"economic": econ, "social": social}
			var g: float = Referendum.yes_share(gbr, position)
			if g >= 0.510 and g <= 0.523:
				print("  %5.2f %7.2f %9.4f %9.4f" % [econ, social, g, Referendum.yes_share(che, position)])
			social += POSITION_STEP
		econ += POSITION_STEP
	print("  " + "-".repeat(34))

	if accord != null:
		for key in ["accession_position", "withdrawal_position"]:
			var position: Dictionary = accord.get(key)
			if (position as Dictionary).is_empty():
				print("  authored %s: EMPTY" % key)
				continue
			print("  authored %s %s -> GBR %.4f  CHE %.4f" % [
				key, _pos_str(position), Referendum.yes_share(gbr, position), Referendum.yes_share(che, position),
			])
	else:
		print("  no loaded org to read the authored positions from yet.")


func _pos_str(position: Dictionary) -> String:
	return "(%.2f, %.2f)" % [float(position.get("economic", 0.0)), float(position.get("social", 0.0))]


# --- (d) the owed measurement: the cross-org burden clamp ---------------------------

func _table_d(loader) -> void:
	print("\n\n########## (d) the cross-org burden clamp contact ##########")
	print("orgs-model.md's named bound, measured: one real rule per org in force --")
	print("eu stability_pact, nato common_defence_floor, %s %s --" % [ACCORD, CEILING])
	print("France breaching all three past the full tolerance.")
	_clamp_table(loader, false)

	print("\n-- (d2) total defiance: EVERY authored rule of all three orgs in force --")
	_clamp_table(loader, true)


func _clamp_table(loader, every_rule: bool) -> void:
	var state = GameState.new_game(loader, PLAYER)
	if not state.orgs.has(ACCORD):
		print("  no %s register -- content not loaded, skipping" % ACCORD)
		return
	var ns = state.player()

	# Hand-adopt the real proposals' terms, orgs_probe's _adopt idiom: the probe
	# writes the register a passed division would have written.
	for org_id in ["eu", "nato", ACCORD]:
		for p in loader.org_proposals.get(org_id, []):
			if p.constraint.is_empty():
				continue
			if not every_rule and p.id != _one_rule_of(org_id):
				continue
			state.orgs[org_id]["rules"][p.id] = {
				"name": p.proposal_name, "field": String(p.constraint["field"]),
				"op": String(p.constraint["op"]), "value": float(p.constraint["value"]),
				"tolerance": float(p.constraint["tolerance"]), "severity": float(p.constraint["severity"]),
				"transfer_pct_gdp": p.transfer_pct_gdp,
				"since_year": state.year, "since_month": state.month,
			}

	# Maximal defiance: every constrained field driven past its rule's full
	# tolerance, so each rule contributes its whole severity. The corporate rate
	# is a FLOOR rule -- the breach is driving it to zero, not to the sky.
	ns.deficit_pct_gdp = 30.0
	ns.debt_eur_bn = float(ns.gdp_eur_bn) * 2.0
	ns.tax_rates_pct["corporate"] = 0.0
	ns.spending_pct_gdp["defence"] = 0.0
	ns.co2e_per_capita_t = 50.0

	var raw := 0.0
	print("  %-14s %-24s %9s %11s" % ["org", "rule", "severity", "contribution"])
	print("  " + "-".repeat(64))
	for org_id in ["eu", "nato", ACCORD]:
		var ids: Array = (state.orgs[org_id]["rules"] as Dictionary).keys()
		ids.sort()
		for rule_id in ids:
			var rule: Dictionary = state.orgs[org_id]["rules"][rule_id]
			var scored: Dictionary = Orgs.rule_breach(state, ns, org_id, rule)
			raw += float(scored["contribution"])
			print("  %-14s %-24s %9.2f %11.4f" % [
				org_id, String(rule_id), float(rule.get("severity", 0.0)), float(scored["contribution"]),
			])
	print("  " + "-".repeat(64))
	for org_id in ["eu", "nato", ACCORD]:
		print("  Orgs.org_burden(%s) = %.6f  (per-org clamp at %.2f)" % [org_id, Orgs.org_burden(state, ns, org_id), BK.BURDEN_MAX])
	print("  RAW summed burden (before any clamp): %.6f" % raw)
	print("  Orgs.burden (the one opinion price, clamped): %.6f" % Orgs.burden(state, ns, Orgs.council_ids(state)))
	if raw > BK.BURDEN_MAX:
		print("  THE CLAMP CONTACTS: raw %.4f exceeds BURDEN_MAX %.2f by %.4f -- a defier of the whole register loses %.1f%% of the opinion price to the ceiling." % [
			raw, BK.BURDEN_MAX, raw - BK.BURDEN_MAX, 100.0 * (raw - BK.BURDEN_MAX) / raw,
		])
	else:
		print("  The clamp does NOT contact: raw %.4f sits %.4f under BURDEN_MAX %.2f -- at this authored set no rule is ever free to break and none is ever priced at zero." % [
			raw, BK.BURDEN_MAX - raw, BK.BURDEN_MAX,
		])


func _one_rule_of(org_id: String) -> String:
	match org_id:
		"eu": return "stability_pact"
		"nato": return "common_defence_floor"
		_: return CEILING


# --- (s) the sweeps that placed the content -----------------------------------------

func _candidate(loader, id: String, position: Dictionary, constraint: Dictionary, transfer := 0.0):
	var errors: Array[String] = []
	var d := {
		"id": id, "org": ACCORD, "name": "sweep", "summary": "sweep",
		"position": position,
	}
	if not constraint.is_empty():
		d["constraint"] = constraint
	if transfer != 0.0:
		d["transfer_pct_gdp"] = transfer
	var org_ids: Array = loader.orgs_by_id.keys()
	if not org_ids.has(ACCORD):
		org_ids.append(ACCORD)
	var p = BlocProposal.from_dict(d, "climate_probe_sweep.json", errors, org_ids)
	if not errors.is_empty():
		printerr("sweep candidate refused: %s" % [errors])
		return null
	return p


## Others-for seats for one candidate question: the members' real votes, France
## excluded -- exactly the number the pivotal band is written against.
func _others_for(state, proposal) -> int:
	var seats := 0
	for id in Orgs.members(state, ACCORD):
		if id == state.player_nation_id:
			continue
		if Orgs.support(state, state.nations[id], proposal) >= BK.SUPPORT_THRESHOLD:
			seats += Orgs.live_seats(state, ACCORD, id)
	return seats


func _ceiling_sweep(loader, state) -> void:
	print("\n\n########## (s1) ceiling sweep: others-for seats by tolerance x position ##########")
	var tolerances := [2.0, 3.0, 4.0, 6.0, 8.0]
	for tol in tolerances:
		print("\n  tolerance %.1f (* = pivotal band [%d, %d])" % [float(tol), BAND_MIN, BAND_MAX])
		_print_grid(func(econ: float, social: float):
			return _candidate(loader, "sweep_c", {"economic": econ, "social": social},
				{"field": "co2e_per_capita_t", "op": "<=", "value": 5.5, "tolerance": float(tol), "severity": 0.33}),
			state)


func _solidarity_sweep(loader, state) -> void:
	print("\n\n########## (s2) solidarity sweep: others-for seats by position ##########")
	print("  transfer_pct_gdp fixed at 0.04. Authored OUTSIDE the pivotal band on")
	print("  purpose: it is a coalition's question, so its column must read the same")
	print("  outcome whatever France does.")
	_print_grid(func(econ: float, social: float):
		return _candidate(loader, "sweep_s", {"economic": econ, "social": social}, {}, 0.04),
		state)


func _print_grid(candidate_fn: Callable, state) -> void:
	var header := "          "
	var social := -0.6
	while social <= 0.601:
		header += "%6.1f" % social
		social += SWEEP_STEP
	print(header)
	var econ := -0.8
	while econ <= 0.801:
		var row := "  econ %+.1f " % econ
		var social2 := -0.6
		while social2 <= 0.601:
			var p = candidate_fn.call(econ, social2)
			var seats := _others_for(state, p) if p != null else -1
			var mark := "*" if (seats >= BAND_MIN and seats <= BAND_MAX) else " "
			row += "%5d%s" % [seats, mark]
			social2 += SWEEP_STEP
		print(row)
		econ += SWEEP_STEP
