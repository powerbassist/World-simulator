extends SceneTree

## Cabinet probe: godot --headless --script res://tools/cabinet_probe.gd
##
## V1.1d's measurement, taken BEFORE the cabinet schema was written -- the same
## discipline dissolution_probe.gd set for V1.1c. Two pre-commitments, both
## fixed in docs/superpowers/specs and the session plan before this file was
## run, so the numbers below can falsify them rather than confirm a guess:
##
## (a) Does a competence-driven effectiveness channel move approval enough to
##     matter? Threshold: >= 2.0 points at end of term, best vs worst legal
##     assignment, under the `managed` budget from balance_probe.gd.
##
## (b) Is resignation reachable? A shorted coalition partner must cross the
##     resignation signal at least once across 168 months under at least one
##     regime; an entitled partner under `managed` must never cross it.
##
## Not a test, not shipped -- see balance_probe.gd's own note for why this
## class of file lives in tools/ and stays out of run_tests.sh. No cabinet.gd
## exists yet: (a) duplicates opinion.gd's tick locally with an effectiveness
## override, the same way dissolution_probe.gd set bloc_approval directly
## rather than call a module that didn't exist yet; (b) calls the REAL
## Discipline and Government modules, since both already exist and the
## quantities loyalty needs (discipline, cohesion, unpopularity) are theirs.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const EK = preload("res://src/sim/election_constants.gd")
const GK = preload("res://src/sim/government_constants.gd")

const MONTHS := 168
const START_YEAR := 2026

## The `managed` regime from balance_probe.gd, duplicated rather than imported
## -- tools/ files are independent probes, each disposable on its own, and
## balance_probe.gd's REGIMES dict is not part of any module's public surface.
##
## Found running section (a): MANAGED moves only `defence` away from France's
## own starting values (health, education, pensions and infrastructure sit
## EXACTLY at their starting values). Effectiveness multiplies a spending
## line's delta from start -- so on four of five lines it multiplies zero.
## MANAGED was S10-tuned to be near-frictionless governance, which makes it
## the wrong budget to probe a channel that only ever acts on a change. Kept
## here for reference; GOVERNING below is what section (a) actually sweeps.
const MANAGED := {
	"spending_pct_gdp": {
		"health": 11.0, "education": 5.5, "defence": 0.6,
		"pensions": 14.5, "infrastructure": 3.5,
	},
	"tax_rates_pct": {"income": 21.0, "corporate": 25.0, "vat": 23.0},
}

## A representative governing budget: moderate deltas on all five lines, none
## of them at a balance-probe extreme. This is what section (a) actually
## exercises, because "does competence matter" is a question about a player
## who touches spending, not one who leaves it at its starting values.
const GOVERNING := {
	"spending_pct_gdp": {
		"health": 12.5, "education": 6.5, "defence": 1.0,
		"pensions": 15.5, "infrastructure": 4.5,
	},
	"tax_rates_pct": {"income": 21.0, "corporate": 25.0, "vat": 23.0},
}
const AUSTERITY := {
	"spending_pct_gdp": {
		"health": 8.5, "education": 3.5, "defence": 1.0,
		"pensions": 11.0, "infrastructure": 1.5,
	},
	"tax_rates_pct": {"income": 26.0, "corporate": 30.0, "vat": 24.0},
}

## Candidate constants for cabinet_constants.gd, probed here before being
## written there. effectiveness = 1 + COMPETENCE_SPAN * (competence - NEUTRAL),
## so at competence 0/1 against a neutral of 0.5 the span below produces
## exactly the BEST/WORST pair swept in section (a).
const COMPETENCE_SPAN := 0.75
const COMPETENCE_NEUTRAL := 0.5
const EFFECTIVENESS_BEST := 1.0 + COMPETENCE_SPAN * (1.0 - COMPETENCE_NEUTRAL)   # 1.3
const EFFECTIVENESS_WORST := 1.0 + COMPETENCE_SPAN * (0.0 - COMPETENCE_NEUTRAL)  # 0.7

const SHORTFALL_PENALTY := 0.5
const RESIGNATION_THRESHOLD := 0.20


func _init() -> void:
	print("=== Section (a): does competence matter? ===")
	var best := _run_effectiveness(EFFECTIVENESS_BEST)
	var worst := _run_effectiveness(EFFECTIVENESS_WORST)
	var spread: float = best - worst
	print("  effectiveness BEST  (%.2f): approval at month %d = %.2f" % [EFFECTIVENESS_BEST, MONTHS, best])
	print("  effectiveness WORST (%.2f): approval at month %d = %.2f" % [EFFECTIVENESS_WORST, MONTHS, worst])
	print("  spread: %.2f points" % spread)
	if spread >= 2.0:
		print("  >= 2.0: channel matters. Proceed with COMPETENCE_SPAN = %.2f." % COMPETENCE_SPAN)
	else:
		print("  < 2.0: channel is decorative at this span. Widen COMPETENCE_SPAN before writing the schema.")

	print("")
	print("=== Section (b): is resignation reachable? ===")
	var managed_signals := _run_resignation_signals("managed", MANAGED)
	var austerity_signals := _run_resignation_signals("austerity", AUSTERITY)

	var managed_entitled_max: float = managed_signals["entitled_max"]
	var managed_shorted_max: float = managed_signals["shorted_max"]
	var austerity_entitled_max: float = austerity_signals["entitled_max"]
	var austerity_shorted_max: float = austerity_signals["shorted_max"]

	print("  managed:   entitled max signal = %.3f, shorted max signal = %.3f" % [managed_entitled_max, managed_shorted_max])
	print("  austerity: entitled max signal = %.3f, shorted max signal = %.3f" % [austerity_entitled_max, austerity_shorted_max])
	print("  RESIGNATION_THRESHOLD candidate: %.2f" % RESIGNATION_THRESHOLD)

	var entitled_safe: bool = managed_entitled_max < RESIGNATION_THRESHOLD
	var shorted_fires: bool = (
		managed_shorted_max >= RESIGNATION_THRESHOLD
		or austerity_shorted_max >= RESIGNATION_THRESHOLD
	)
	if entitled_safe and shorted_fires:
		print("  PASS: shorted crosses the threshold, entitled under managed never does.")
	else:
		print("  FAIL: threshold or SHORTFALL_PENALTY needs retuning before the schema is written.")

	quit(0)


## Duplicates opinion.gd's _tick_nation, with the five SPENDING_KEYS' delta
## multiplied by a single effectiveness figure -- standing in for
## Cabinet.effectiveness() before that function exists. Everything else
## (jobs, growth, taxes, public_finances, salience, inertia) is untouched, so
## the ONLY thing this measures is the spending channel's own sensitivity.
func _run_effectiveness(effectiveness: float) -> float:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return 0.0

	var state = GameState.new_game(loader, "FRA")
	state.year = START_YEAR
	state.month = 1
	Budget.commit(state, GOVERNING)

	var ns = state.player()
	var year := START_YEAR
	var month := 1
	for _i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		Economy.tick_month(state)
		Budget.tick_month(state)
		_opinion_tick_with_effectiveness(ns, effectiveness)
		Discipline.tick_month(state, loader)
		Legislature.tick_month(state)
		Dissolution.tick_month(state)
		Elections.tick_month(state, loader)

	return ns.overall_approval_pct


## Local reimplementation of Opinion._tick_nation(). Kept in lockstep with
## opinion.gd by tests/test_cabinet.gd once effectiveness() is a real function
## there -- this copy is disposable probe scaffolding, not a second
## implementation to maintain.
func _opinion_tick_with_effectiveness(ns, effectiveness: float) -> void:
	var sat := Opinion.issue_satisfaction(ns)
	for key in C.SPENDING_KEYS:
		var d_spend: float = (
			float(ns.spending_pct_gdp.get(key, 0.0))
			- float(ns.start_spending_pct_gdp.get(key, 0.0))
		)
		sat[key] = clampf(d_spend * effectiveness / K.SPEND_SCALE_PP, -1.0, 1.0)

	var national := {}
	for issue in K.ISSUE_KEYS:
		national[issue] = 0.0

	for bloc in K.BLOC_KEYS:
		var weights := Opinion.salience_weights(K.BLOC_SALIENCE_BASE[bloc], sat)
		var score := 0.0
		for issue in weights:
			score += float(weights[issue]) * float(sat.get(issue, 0.0))

		var law_offset: float = float(ns.law_bloc_offset.get(bloc, 0.0))
		var target: float = K.APPROVAL_NEUTRAL + K.APPROVAL_SPAN * clampf(score + law_offset, -1.0, 1.0)
		var approval := float(ns.bloc_approval.get(bloc, K.APPROVAL_NEUTRAL))
		approval += (target - approval) * K.INERTIA_RATE
		ns.bloc_approval[bloc] = clampf(approval, K.APPROVAL_MIN, K.APPROVAL_MAX)

		var size := float(K.BLOC_SIZE[bloc])
		for issue in weights:
			national[issue] = float(national[issue]) + size * float(weights[issue])

	ns.issue_salience = national
	ns.overall_approval_pct = Opinion.overall_approval(ns)


## Runs the REAL tick (no local reimplementation needed -- Discipline and
## Government already exist) and tracks, every month, the resignation signal
## for the coalition party furthest from the government's agreed position --
## the partner most likely to be shorted a portfolio in practice. Returns the
## worst (max) signal reached under an entitled reading and under a shorted
## reading, so the threshold check above compares like against like.
func _run_resignation_signals(regime_name: String, pending: Dictionary) -> Dictionary:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return {}

	var state = GameState.new_game(loader, "FRA")
	state.year = START_YEAR
	state.month = 1
	Budget.commit(state, pending)

	var ns = state.player()
	var party_list: Array = loader.parties.get("FRA", [])
	var by_id := {}
	for party in party_list:
		by_id[party.id] = party

	var entitled_max := 0.0
	var shorted_max := 0.0

	var year := START_YEAR
	var month := 1
	for _i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		Discipline.tick_month(state, loader)
		Legislature.tick_month(state)
		Dissolution.tick_month(state)
		Elections.tick_month(state, loader)

		var unpop := Discipline.unpopularity(ns)
		if unpop <= 0.0 or ns.coalition_party_ids.is_empty():
			continue

		# The partner furthest from the agreed position -- the one whose
		# cohesion is worst and so whose loyalty has the least room to spare.
		var worst_dist := -1.0
		var worst_party = null
		for pid in ns.coalition_party_ids:
			if not by_id.has(pid):
				continue
			var pos: Dictionary = EK.SLOT_POSITION.get(by_id[pid].ideology_slot, {"economic": 0.0, "social": 0.0})
			var d_econ: float = float(ns.coalition_position["economic"]) - float(pos["economic"])
			var d_soc: float = float(ns.coalition_position["social"]) - float(pos["social"])
			var dist := sqrt(d_econ * d_econ + d_soc * d_soc)
			if dist > worst_dist:
				worst_dist = dist
				worst_party = by_id[pid]

		if worst_party == null:
			continue

		var cohesion: float = exp(-pow(worst_dist / GK.COALITION_SIGMA, 2.0))
		var discipline := Discipline.of(ns, worst_party)

		var loyalty_entitled: float = clampf(discipline * cohesion, 0.0, 1.0)
		var loyalty_shorted: float = clampf(discipline * cohesion - SHORTFALL_PENALTY, 0.0, 1.0)

		entitled_max = maxf(entitled_max, unpop * (1.0 - loyalty_entitled))
		shorted_max = maxf(shorted_max, unpop * (1.0 - loyalty_shorted))

	return {"entitled_max": entitled_max, "shorted_max": shorted_max}
