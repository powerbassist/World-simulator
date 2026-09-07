extends SceneTree

## Media probe: godot --headless --script res://tools/media_probe.gd
##
## V1.5d's evidence generator, and the bands and tiebreakers below were fixed
## BEFORE any sweep ran -- society_probe.gd's discipline, extended by
## demography_probe.gd and unrest_probe.gd, whose four distinct tiebreaker
## failures are recorded in docs/decision-log.md. A constant this file cannot
## justify is DELETED rather than left unused.
##
## Pass a table name to run one: --headless --script ... -- travel
##
## ---------------------------------------------------------------------------
## STEP 0 -- the two feasibility tables, run BEFORE a line of src/ was written.
## ---------------------------------------------------------------------------
##
## (A) TRAVEL, and it carries a KILL SWITCH whose response is pre-committed.
##
##     The framing deviation is driven by the distance between an outlet's
##     authored position and the government's own `coalition_position`, so the
##     channel is only alive to the extent that coalition_position MOVES.
##     opinion-model.md records that France held a majority through every
##     election of a full fourteen-year run, which is a reason to doubt it does.
##
##     The chain: dev <= sum(reach) * d_dist / MAX_POSITION_DISTANCE, and table
##     (B) below establishes that a gain change of about 5.0 is what buys a
##     readable bloc row. With sum(reach) < 1.0 and MAX_POSITION_DISTANCE
##     2.828, a travel of 0.05-0.30 puts FRAMING_BETA in the HUNDREDS.
##
##     PRE-COMMITTED RESPONSE, so that this is not decided after seeing the
##     number: if the measured travel cannot produce a readable bloc row at a
##     sane FRAMING_BETA, the alignment term is DELETED rather than tuned up --
##     demography_probe.gd's treatment of DEPENDENCY_ELASTICITY["health"], taken
##     in advance instead of after the sweep -- and press_freedom backlash
##     becomes the sole driver of the deviation: censorship makes the surviving
##     press hostile.
##
## (B) FEASIBILITY, and it is arithmetic rather than a simulation.
##
##     salience_weights() renormalises onto the simplex, so raising a bloc's
##     gain CONCENTRATES its weight rather than growing it. Partitioning a
##     bloc's issues into bad B (severity v_i = -sat_i) and non-bad P:
##
##         A  = sum_P b_i          R  = A + sum_B b_i
##         P1 = sum_P b_i*sat_i    M1 = sum_B b_i*v_i    M2 = sum_B b_i*v_i^2
##
##         score(G) = (P1 - M1 - G*M2) / (R + G*M1)
##
##     A Moebius transform in G, and three consequences settle the session's
##     whole risk profile:
##
##       1. Monotone DECREASING in G, always. d/dG has numerator
##          -(M2*R + M1*(P1-M1)), and Cauchy-Schwarz gives M1^2 <= B0*M2, so it
##          is at most -(M2*A + M1*P1) <= 0. A hostile press can only ever lower
##          a bloc's score, which is also why a FRIENDLY press has no channel:
##          severity is clampf(-sat, 0, 1), so good news is already at zero.
##       2. It SATURATES at -M2/M1. That is a hard ceiling computable with no
##          simulation at all, so a bloc whose APPROVAL_SPAN*(score(5) -
##          asymptote) is under the +-3.0 readable floor CANNOT clear a band at
##          any FRAMING_BETA. Tuning against it would be the arithmetic
##          impossibility unrest-model.md section 4 and defence-model.md's
##          DEPLOYMENT_OPINION_CHOSEN both name.
##       3. It is EXACTLY INERT under a uniform satisfaction vector, including
##          the uniform-zero vector of a new game -- for sat >= 0 every severity
##          is 0, and for a common sat < 0 the factor (1 + G*v) cancels in the
##          normalisation. The channel's size is a function of the DISPERSION of
##          severities, not their level.
##
##     The clamp column is not decoration. opinion.gd clamps
##     `score + law_offset - unrest_opinion_load` to [-1, +1] before scaling, so
##     in exactly the crisis state a band would be measured in, that clamp can
##     bind and swallow the whole framing term.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const K = preload("res://src/sim/opinion_constants.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Companies = preload("res://src/sim/companies.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const Media = preload("res://src/sim/media.gd")
const MK = preload("res://src/sim/media_constants.gd")

const MONTHS := 168
const START_YEAR := 2026

## The three nations data/outlets/ will be authored for. The other seven get no
## file, which is what makes their framing deviation exactly 0.0 forever --
## companies-model.md's empty-register property, inherited whole.
const NATIONS := ["FRA", "DEU", "GBR"]

## Copied from balance_probe.gd rather than imported: that file `extends
## SceneTree` and preloading it would instantiate a second probe. The deltas are
## percentage points against each nation's OWN starting rates, so they mean the
## same thing for all three -- V1.2a's nation-relative regime shape.
const REGIMES := {
	"hands_off": {},
	"spendthrift": {
		"spending_pct_gdp": {
			"health": 3.0, "education": 2.5, "defence": 1.5,
			"pensions": 3.5, "infrastructure": 2.5,
		},
		"tax_rates_pct": {"income": -6.0, "corporate": -7.0, "vat": -4.0},
	},
	"austerity": {
		"spending_pct_gdp": {
			"health": -2.5, "education": -2.0, "defence": -1.0,
			"pensions": -3.5, "infrastructure": -2.0,
		},
		"tax_rates_pct": {"income": 6.0, "corporate": 5.0, "vat": 4.0},
	},
	"managed": {
		"spending_pct_gdp": {"defence": -1.4},
		"tax_rates_pct": {"vat": 3.0},
	},
	"tinkering": {
		"spending_pct_gdp": {
			"education": 1.0, "pensions": -1.0, "infrastructure": 1.5,
		},
		"tax_rates_pct": {"income": 1.0, "corporate": -1.0, "vat": 1.0},
	},
	"tax_max": {"tax_rates_pct": {"income": 40.0, "corporate": 25.0, "vat": 15.0}},
	"spend_zero": {
		"spending_pct_gdp": {
			"health": -11.0, "education": -5.5, "defence": -2.0,
			"pensions": -14.5, "infrastructure": -3.5,
		},
	},
}

## Table (B) is measured on the three regimes that actually make a country
## unhappy in DISPERSED ways. `managed` is included as the control: a
## well-governed run must show the channel near-inert, or framing is a second
## approval number with a different label -- v1.md section 5's own warning about
## unrest, which applies unchanged here.
const HOSTILE := ["austerity", "spend_zero", "tax_max", "managed"]

## Where a `a>b` switch regime changes budget. TWENTY, which is balance_probe.gd's own
## `managed_then_austerity` figure and not a number chosen here: it lands just past the
## 2027 verdict, so the run reaches it only by having WON, and it leaves the whole of the
## next two terms for a grievance converging at UNREST_CONVERGENCE to mature in.
##
## Sixty was tried first and was wrong in a way worth recording -- it leaves 108 months,
## the player then has to survive the 2032 election on an austerity budget, and the run
## stops before the stock matures. TWO HARNESSES THAT DISAGREE ABOUT WHAT IS REACHABLE
## is the exact failure V1.5c spent a session on, so this file takes balance_probe.gd's
## number rather than inventing its own.
const SWITCH_MONTH := 20

## Which press stance table (E) measures the gain floor at. Set from the command line so
## the difference between the ordinary press and a deliberately saturated FREE one is a
## measurement rather than an assumption -- the sweep in table (C) reported its clamp
## column at 0.0 and would have missed that +1.0 doubles the spread.
static var PRESS_FOR_CLAMP := 0.0

## sqrt(2^2 + 2^2). The diameter of the two-axis ideology space every position in
## this project lives in. Geometry, not a tuning -- the same reason
## foreign_policy.gd keeps its own copy rather than sharing one.
const MAX_POSITION_DISTANCE := 2.8284271247461903


func _init() -> void:
	var which := ""
	var argv := OS.get_cmdline_user_args()
	if argv.size() > 0:
		which = String(argv[0])

	if which == "" or which == "travel":
		_table_travel()
	if which == "" or which == "feasibility":
		_table_feasibility()
	if which == "" or which == "framing":
		_sweep_framing_beta()
	if which == "" or which == "press":
		_sweep_press_unrest_beta()
	if which == "" or which == "clamps":
		PRESS_FOR_CLAMP = 0.0
		print("
--- at the ordinary press (press_freedom = 0.0) ---")
		_table_clamps()
		PRESS_FOR_CLAMP = MK.PRESS_FREEDOM_MAX
		print("
--- at a SATURATED FREE press (press_freedom = +1.0) ---")
		_table_clamps()

	quit(0)


# ---------------------------------------------------------------------------
# (C) FRAMING_BETA
# ---------------------------------------------------------------------------

## Band, both edges MODEL criteria:
##   (i)  under `tax_max`, the worst bloc row must move past +-3.0 against a control run
##        with framing switched off -- the isolated path, so every other issue is
##        bit-identical between the two and the only difference is the gain.
##   (ii) under `managed` -- a WELL-GOVERNED run -- the headline must NOT move past
##        +-3.0. Step 0's table (B) measured FRA workers alone reaching 3.92 there, so
##        this is a real ceiling: framing strong enough to destroy a good run is the
##        second-approval-number failure docs/tiers/v1.md section 5 warns about.
## Tiebreaker: the MIDPOINT of the passing interval, because both edges are model
## criteria and neither is a guard rail -- unrest-model.md section 10 (e)'s rule.
##
## The candidate is applied by RESCALING the gain Media.tick_month() just wrote rather
## than by re-implementing the model in this file:
##
##     gain(b) = SALIENCE_GAIN + (gain_shipped - SALIENCE_GAIN) * b / FRAMING_BETA
##
## which is exact because the gain is linear in the beta everywhere the FRAMING_GAIN_MIN
## clamp is slack -- and the clamp column below reports whether it was. That is
## unrest_probe.gd's own trick for SETTLEMENT_BETA, and the reason it matters is that a
## second copy of the model in tools/ is a copy that can drift.
func _sweep_framing_beta() -> void:
	print("\n=== (C) FRAMING_BETA ===")
	print("band (i)  worst bloc row past +-3.0 under `managed>tax_max`  [model criterion]")
	print("band (ii) headline moves at MOST 3.0 under `managed`        [model criterion]")
	print("tiebreaker: MIDPOINT of the passing interval -- both edges are model criteria\n")
	print("%8s %10s %10s %10s %8s %s" % [
		"beta", "(i) row", "(ii) hdln", "worst row", "clamp", "band",
	])

	var passing: Array[float] = []
	for beta in [3.00, 3.02, 3.10, 4.00, 4.50, 5.00, 6.00, 6.20, 6.40, 6.60, 6.80, 7.00]:
		var hostile := _framing_delta("FRA", "managed>tax_max", beta)
		var quiet := _framing_delta("FRA", "managed", beta)
		var ok_i: bool = float(hostile["row"]) >= 3.0
		var ok_ii: bool = float(quiet["headline"]) <= 3.0
		var clamped: bool = bool(hostile["clamped"]) or bool(quiet["clamped"])
		if ok_i and ok_ii and not clamped:
			passing.append(beta)
		print("%8.2f %10.2f %10.2f %10.2f %8s %s" % [
			beta, hostile["row"], quiet["headline"], quiet["row"],
			"BINDS" if clamped else "slack",
			"PASS" if (ok_i and ok_ii and not clamped) else "fail",
		])

	if passing.is_empty():
		print("\nNO CANDIDATE PASSES -- the constant is DELETED and framing ships as a readout.")
		return
	var mid: float = (passing[0] + passing[passing.size() - 1]) / 2.0
	var best: float = passing[0]
	for beta in passing:
		if absf(beta - mid) < absf(best - mid):
			best = beta
	print("\npassing interval [%.2f, %.2f], midpoint %.2f -> nearest candidate %.2f" % [
		passing[0], passing[passing.size() - 1], mid, best,
	])
	print("shipped FRAMING_BETA = %.2f" % MK.FRAMING_BETA)


## One regime, run twice: once with framing live at the candidate beta and once with it
## switched off entirely. Everything else is bit-identical between the two, so the whole
## difference IS the channel -- society_probe.gd's isolated path, which exists because a
## band measured on a path that also moves the deficit measures the deficit.
func _framing_delta(nation_id: String, regime_name: String, beta: float) -> Dictionary:
	var live := _framing_run(nation_id, regime_name, beta, true)
	var dead := _framing_run(nation_id, regime_name, 0.0, false)

	var months: int = mini(int(live["months"]), int(dead["months"]))
	var worst_row := 0.0
	var worst_headline := 0.0
	for i in range(months):
		var a: Dictionary = live["rows"][i]
		var b: Dictionary = dead["rows"][i]
		for bloc in K.BLOC_KEYS:
			worst_row = maxf(worst_row, absf(float(a[bloc]) - float(b[bloc])))
		worst_headline = maxf(
			worst_headline, absf(float(live["headline"][i]) - float(dead["headline"][i]))
		)
	return {
		"row": worst_row, "headline": worst_headline, "clamped": live["clamped"],
	}


func _framing_run(nation_id: String, regime_name: String, beta: float, framed: bool) -> Dictionary:
	var loader := DataLoader.new()
	loader.load_all()
	var state = GameState.new_game(loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()

	# V1.5c's reachability lesson, applied to this band rather than inherited as a
	# sentence. Under `tax_max` France loses the 2027 election and the run stops at
	# month 16, so a band measured there measures a government already on its way out --
	# which is the error unrest_probe.gd made and balance_probe.gd caught. `switch`
	# regimes govern well, WIN, and only then provoke, which is the reachable hostile
	# state a real player produces.
	var first: String = regime_name
	var switch_to := ""
	if regime_name.contains(">"):
		var parts := regime_name.split(">")
		first = parts[0]
		switch_to = parts[1]

	var pending := _resolve_pending(ns, REGIMES[first])
	if not pending.is_empty():
		Budget.commit(state, pending)

	var rows: Array[Dictionary] = []
	var headline: Array[float] = []
	var clamped := false
	var year := START_YEAR
	var month := 1

	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		if switch_to != "" and i == SWITCH_MONTH:
			Budget.commit(state, _resolve_pending(ns, REGIMES[switch_to]))

		_tick_to_media(state, loader)
		for id in state.nations:
			var n = state.nations[id]
			var gains := {}
			for bloc in K.BLOC_KEYS:
				var shipped: float = float(n.framing_gain.get(bloc, K.SALIENCE_GAIN))
				var scaled: float = K.SALIENCE_GAIN
				if framed and MK.FRAMING_BETA > 0.0:
					scaled = K.SALIENCE_GAIN + (shipped - K.SALIENCE_GAIN) * beta / MK.FRAMING_BETA
				if scaled <= MK.FRAMING_GAIN_MIN:
					clamped = true
					scaled = MK.FRAMING_GAIN_MIN
				gains[bloc] = scaled
			n.framing_gain = gains

		_tick_after_media(state, loader, ns, year, month)

		var row := {}
		for bloc in K.BLOC_KEYS:
			row[bloc] = float(ns.bloc_approval.get(bloc, 0.0))
		rows.append(row)
		headline.append(float(ns.overall_approval_pct))

		if not ns.in_government:
			break

	return {"rows": rows, "headline": headline, "months": rows.size(), "clamped": clamped}


# ---------------------------------------------------------------------------
# (D) PRESS_UNREST_BETA
# ---------------------------------------------------------------------------

## Band, both edges MODEL criteria:
##   (i)  a saturated censorship must MOVE THE DATE of the first unrest act -- the band
##        INEQUALITY_BETA is measured against, reused unchanged because it is the same
##        question asked of a different term.
##   (ii) it must NOT on its own push `hands_off` over UNREST_THRESHOLD_PCT. Band (i) is
##        a one-sided minimum and unrest-model.md's table (b) is exactly what happens
##        when such a band has no ceiling: a country with nothing else wrong must not
##        strike merely because the press was restricted.
## Tiebreaker: MIDPOINT of the passing interval.
##
## ISOLATED FROM FRAMING. press_freedom feeds both channels, so this sweep overwrites
## framing_gain back to the flat baseline every month -- otherwise the censorship that
## raises grievance also flattens the press, and the table would be measuring two things
## and attributing them to one.
func _sweep_press_unrest_beta() -> void:
	print("\n=== (D) PRESS_UNREST_BETA ===")
	print("band (i)  saturated censorship moves the date of the first act  [model criterion]")
	print("          measured on `managed>austerity`: govern well, WIN, then provoke")
	print("band (ii) `hands_off` + censorship alone stays under %.1f       [model criterion]" % UnrestK.UNREST_THRESHOLD_PCT)
	print("tiebreaker: MIDPOINT of the passing interval")
	print("isolated: framing_gain is held flat, so this measures the unrest term alone\n")

	var base_act := _press_run("managed>austerity", 0.0)
	print("control (no censorship): first act month %s, peak %.2f; hands_off peak %.2f" % [
		str(base_act["first_act"]), float(base_act["peak"]),
		float(_press_run("hands_off", 0.0)["peak"]),
	])
	print("%8s %12s %12s %10s %s" % ["beta", "first act", "vs control", "hands_off", "band"])

	var passing: Array[float] = []
	for beta in [1.0, 2.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0, 40.0]:
		var hostile := _press_run("managed>austerity", beta)
		var calm := _press_run("hands_off", beta)
		var moved: bool = int(hostile["first_act"]) != int(base_act["first_act"])
		var quiet: bool = float(calm["peak"]) < UnrestK.UNREST_THRESHOLD_PCT
		if moved and quiet:
			passing.append(beta)
		print("%8.1f %12s %12s %10.2f %s" % [
			beta, str(hostile["first_act"]),
			"MOVED" if moved else "same", calm["peak"],
			"PASS" if (moved and quiet) else "fail",
		])

	if passing.is_empty():
		print("\nNO CANDIDATE PASSES -- the constant is DELETED and press freedom keeps one price.")
		return
	var mid: float = (passing[0] + passing[passing.size() - 1]) / 2.0
	var best: float = passing[0]
	for beta in passing:
		if absf(beta - mid) < absf(best - mid):
			best = beta
	print("\npassing interval [%.1f, %.1f], midpoint %.1f -> nearest candidate %.1f" % [
		passing[0], passing[passing.size() - 1], mid, best,
	])
	print("shipped PRESS_UNREST_BETA = %.1f" % UnrestK.PRESS_UNREST_BETA)


## The candidate is applied by scaling the STANCE so that the shipped beta times the
## scaled stance equals the candidate beta times a saturated one -- unrest_probe.gd's
## _effective_stance() trick, and for its reason: no duplicated tick.
func _press_run(regime_name: String, beta: float) -> Dictionary:
	var loader := DataLoader.new()
	loader.load_all()
	var state = GameState.new_game(loader, "FRA")
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()

	# The same reachability fix band (i) of table (C) needed, and it was needed here
	# HARDER: measured from month 1, `austerity` loses the 2027 election and the run stops
	# at month 16, so the CONTROL never fires an act at all and "moves the date" degenerates
	# into "an act happens". That is V1.5c's own finding -- twenty-five balance regimes
	# reporting zero acts because the government was already gone -- reproduced inside the
	# probe written after it.
	var first: String = regime_name
	var switch_to := ""
	if regime_name.contains(">"):
		var parts := regime_name.split(">")
		first = parts[0]
		switch_to = parts[1]

	var pending := _resolve_pending(ns, REGIMES[first])
	if not pending.is_empty():
		Budget.commit(state, pending)

	var stance := 0.0
	if UnrestK.PRESS_UNREST_BETA > 0.0:
		stance = -beta * MK.PRESS_FREEDOM_MAX / UnrestK.PRESS_UNREST_BETA

	var first_act := -1
	var peak := 0.0
	var year := START_YEAR
	var month := 1

	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month
		ns.press_freedom = stance
		if switch_to != "" and i == SWITCH_MONTH:
			Budget.commit(state, _resolve_pending(ns, REGIMES[switch_to]))

		_tick_to_media(state, loader)
		# Held flat, so the censorship above reaches unrest and NOT the salience gain.
		for id in state.nations:
			var gains := {}
			for bloc in K.BLOC_KEYS:
				gains[bloc] = K.SALIENCE_GAIN
			state.nations[id].framing_gain = gains

		_tick_after_media(state, loader, ns, year, month)

		peak = maxf(peak, float(ns.unrest_pct))
		if first_act < 0 and state.unrest_acts.size() > 0:
			first_act = i + 1
		if not ns.in_government:
			break

	return {"first_act": first_act, "peak": peak}


# ---------------------------------------------------------------------------
# (E) Every clamp measured
# ---------------------------------------------------------------------------

func _table_clamps() -> void:
	print("\n=== (E) every clamp this session touches ===")
	var loader := DataLoader.new()
	loader.load_all()
	var state = GameState.new_game(loader, "FRA")
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()

	var lowest := 1000.0
	var highest := 0.0
	var pending := _resolve_pending(ns, REGIMES["austerity"])
	Budget.commit(state, pending)

	var year := START_YEAR
	var month := 1
	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month
		# The widest reachable press: a maximally FREE press doubles the spread, which is
		# where the floor is nearest.
		ns.press_freedom = PRESS_FOR_CLAMP
		_tick_to_media(state, loader)
		_tick_after_media(state, loader, ns, year, month)
		for bloc in K.BLOC_KEYS:
			var g: float = float(ns.framing_gain.get(bloc, K.SALIENCE_GAIN))
			lowest = minf(lowest, g)
			highest = maxf(highest, g)
		if not ns.in_government:
			break

	print("%-24s %10s %10s %s" % ["quantity", "reached", "clamp", "verdict"])
	print("%-24s %10.3f %10.3f %s" % [
		"framing_gain (floor)", lowest, MK.FRAMING_GAIN_MIN,
		"slack" if lowest > MK.FRAMING_GAIN_MIN else "BINDS",
	])
	print("%-24s %10.3f %10s %s" % [
		"framing_gain (ceiling)", highest, "none",
		"no ceiling: salience_weights() renormalises, so a large gain concentrates",
	])
	print("%-24s %10.3f %10.3f %s" % [
		"press_freedom", MK.PRESS_FREEDOM_MAX, MK.PRESS_FREEDOM_MAX,
		"reached: three authored laws, repeatable on 24- and 36-month cooldowns",
	])


# ---------------------------------------------------------------------------
# (A) Travel
# ---------------------------------------------------------------------------

func _table_travel() -> void:
	print("\n=== (A) coalition_position travel, %d months ===" % MONTHS)
	print("A run ENDS when the player loses office, so these are travels that are")
	print("actually reachable -- unrest_probe.gd's own blind spot, avoided by")
	print("running the harness that has elections.\n")
	print("%-6s %-14s %8s %8s %8s %8s %6s" % [
		"nation", "regime", "max|d|", "mean|d|", "end|d|", "reforms", "months",
	])

	var worst := 0.0
	for nation_id in NATIONS:
		for regime_name in REGIMES:
			var r := _run_travel(nation_id, regime_name, REGIMES[regime_name])
			worst = maxf(worst, float(r["max"]))
			print("%-6s %-14s %8.4f %8.4f %8.4f %8d %6d" % [
				nation_id, regime_name, r["max"], r["mean"], r["end"],
				r["reforms"], r["months"],
			])

	print("\nworst travel across all runs: %.4f" % worst)
	print("beta needed for a gain swing of 5.0 at sum(reach)=1.0:  %.1f" % (
		5.0 / maxf(worst / MAX_POSITION_DISTANCE, 1e-9)
	))
	print("(the divisor is dev = sum(reach) * travel / MAX_POSITION_DISTANCE,")
	print(" taken at its most generous: every outlet in a bloc, all of them moving)")


func _run_travel(nation_id: String, regime_name: String, delta: Dictionary) -> Dictionary:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return {}

	var state = GameState.new_game(loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()

	var start_pos: Dictionary = ns.coalition_position.duplicate()
	var pending := _resolve_pending(ns, delta)
	if not pending.is_empty():
		Budget.commit(state, pending)

	var max_d := 0.0
	var sum_d := 0.0
	var reforms := 0
	var last_pos: Dictionary = start_pos.duplicate()
	var months := 0

	var year := START_YEAR
	var month := 1
	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month

		_tick(state, loader, ns, year, month)
		months += 1

		var d := _distance(ns.coalition_position, start_pos)
		max_d = maxf(max_d, d)
		sum_d += d
		if _distance(ns.coalition_position, last_pos) > 1e-9:
			reforms += 1
			last_pos = ns.coalition_position.duplicate()

		if not ns.in_government:
			break

	return {
		"max": max_d,
		"mean": sum_d / maxf(float(months), 1.0),
		"end": _distance(ns.coalition_position, start_pos),
		"reforms": reforms,
		"months": months,
	}


# ---------------------------------------------------------------------------
# (B) Feasibility
# ---------------------------------------------------------------------------

func _table_feasibility() -> void:
	print("\n=== (B) salience feasibility -- the ceiling no FRAMING_BETA can pass ===")
	print("score(5) is today's model. asym = -M2/M1 is score(G) as G -> infinity.")
	print("headroom = APPROVAL_SPAN * (score(5) - asym): the ENTIRE approval movement")
	print("available to this channel on this bloc, at any beta whatsoever.")
	print("clamp binds when score + law_offset - unrest_load is already outside [-1,+1],")
	print("in which case opinion.gd swallows the term before it is scaled.\n")

	for regime_name in HOSTILE:
		for nation_id in NATIONS:
			_feasibility_run(nation_id, regime_name, REGIMES[regime_name])


func _feasibility_run(nation_id: String, regime_name: String, delta: Dictionary) -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		printerr("loader errors: %s" % [loader.errors])
		quit(1)
		return

	var state = GameState.new_game(loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()

	var pending := _resolve_pending(ns, delta)
	if not pending.is_empty():
		Budget.commit(state, pending)

	# Measured at the WORST reachable month rather than at the end: a run that
	# ends in month 16 because the player lost has its worst state somewhere
	# inside, and measuring the final month would report the state of a
	# government that is already gone. unrest_probe.gd's error, avoided.
	var worst_sat := {}
	var worst_bloc_score := 1.0
	var worst_month := 0
	var year := START_YEAR
	var month := 1
	var months := 0

	for i in range(MONTHS):
		month += 1
		if month > 12:
			month = 1
			year += 1
		state.year = year
		state.month = month
		_tick(state, loader, ns, year, month)
		months += 1

		var sat := Opinion.issue_satisfaction(ns)
		var s := _score(K.BLOC_SALIENCE_BASE["workers"], sat, K.SALIENCE_GAIN)
		if s < worst_bloc_score:
			worst_bloc_score = s
			worst_sat = sat.duplicate()
			worst_month = months

		if not ns.in_government:
			break

	if worst_sat.is_empty():
		print("  %s %s: no reachable month" % [nation_id, regime_name])
		return

	print("--- %s %s (worst at month %d of %d) ---" % [
		nation_id, regime_name, worst_month, months,
	])
	print("%-11s %8s %8s %9s %8s %7s %s" % [
		"bloc", "score(5)", "asym", "headroom", "size", "hdln", "clamp",
	])

	for bloc in K.BLOC_KEYS:
		var base: Dictionary = K.BLOC_SALIENCE_BASE[bloc]
		var s5 := _score(base, worst_sat, K.SALIENCE_GAIN)
		var asym := _asymptote(base, worst_sat)
		var headroom: float = K.APPROVAL_SPAN * (s5 - asym)
		var law_offset: float = float(ns.bloc_offset.get(bloc, 0.0))
		var combined: float = s5 + law_offset - float(ns.unrest_opinion_load)
		print("%-11s %8.4f %8.4f %9.2f %8.2f %7.2f %s" % [
			bloc, s5, asym, headroom, float(K.BLOC_SIZE[bloc]),
			headroom * float(K.BLOC_SIZE[bloc]),
			"BINDS" if absf(combined) >= 1.0 else "slack",
		])


## score(G) = sum_i w_i*sat_i with w_i = b_i*(1 + G*severity_i) renormalised.
## Written out rather than calling Opinion.salience_weights() so that the sweep
## can vary G without src/ having grown an argument yet -- step 0 runs before a
## line of src/ is touched, which is the whole point of it.
func _score(base: Dictionary, sat: Dictionary, gain: float) -> float:
	var total := 0.0
	var acc := 0.0
	for issue in base:
		var s: float = float(sat.get(issue, 0.0))
		var severity: float = clampf(-s, 0.0, 1.0)
		var w: float = float(base[issue]) * (1.0 + gain * severity)
		total += w
		acc += w * s
	if total <= 0.0:
		return 0.0
	return acc / total


## The G -> infinity limit, -M2/M1. Returns score(SALIENCE_GAIN) when the bloc
## has no bad news at all, because in that state the gain has no channel and the
## honest headroom is exactly zero rather than undefined.
func _asymptote(base: Dictionary, sat: Dictionary) -> float:
	var m1 := 0.0
	var m2 := 0.0
	for issue in base:
		var s: float = float(sat.get(issue, 0.0))
		var v: float = clampf(-s, 0.0, 1.0)
		if v <= 0.0:
			continue
		m1 += float(base[issue]) * v
		m2 += float(base[issue]) * v * v
	if m1 <= 0.0:
		return _score(base, sat, K.SALIENCE_GAIN)
	return -m2 / m1


# ---------------------------------------------------------------------------
# Shared harness
# ---------------------------------------------------------------------------

## main.gd's monthly sequence, in main.gd's order. Kept in one function so both
## tables run the same simulation -- two harnesses that disagree is exactly the
## failure V1.5c spent a session on.
func _tick(state, loader, ns, year: int, month: int) -> void:
	_tick_to_media(state, loader)
	_tick_after_media(state, loader, ns, year, month)


## Economy through Media, in main.gd's order. Split from the rest so a sweep can write a
## candidate gain into the ONE seam that matters -- between Media, which writes the gain,
## and Opinion, which is its only reader.
func _tick_to_media(state, loader) -> void:
	Economy.tick_month(state)
	Budget.tick_month(state)
	Orgs.tick_month(state, loader)
	# V1.6b. See src/ui/main.gd for why this sits after Economy and before Opinion.
	Inflation.tick_month(state)
	Media.tick_month(state, loader)


## Opinion onward, in main.gd's order.
func _tick_after_media(state, loader, ns, year: int, month: int) -> void:
	Opinion.tick_month(state)
	var entry := Budget.snapshot(state)
	entry.merge(Opinion.snapshot(state))
	state.append_history(entry)
	Discipline.tick_month(state, loader)
	Legislature.tick_month(state, loader)
	Dissolution.tick_month(state)
	Diplomacy.tick_month(state, loader)
	Defence.tick_month(state)
	Companies.tick_month(state, loader)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, loader)

	state.day = 0
	for d in range(_days_in_month(month, year)):
		state.day = d + 1
	Calendar.tick_month(state)

	Elections.tick_month(state, loader)


func _resolve_pending(ns, delta: Dictionary) -> Dictionary:
	var pending := {}
	if delta.has("tax_rates_pct"):
		var rates := {}
		for key in delta["tax_rates_pct"]:
			var start: float = float(ns.start_tax_rates_pct.get(key, 0.0))
			rates[key] = clampf(start + float(delta["tax_rates_pct"][key]), 0.0, 100.0)
		pending["tax_rates_pct"] = rates
	if delta.has("spending_pct_gdp"):
		var spending := {}
		for key in delta["spending_pct_gdp"]:
			var start: float = float(ns.start_spending_pct_gdp.get(key, 0.0))
			spending[key] = clampf(start + float(delta["spending_pct_gdp"][key]), 0.0, 100.0)
		pending["spending_pct_gdp"] = spending
	return pending


func _distance(a: Dictionary, b: Dictionary) -> float:
	var de: float = float(a.get("economic", 0.0)) - float(b.get("economic", 0.0))
	var ds: float = float(a.get("social", 0.0)) - float(b.get("social", 0.0))
	return sqrt(de * de + ds * ds)


func _days_in_month(month: int, year: int) -> int:
	match month:
		1, 3, 5, 7, 8, 10, 12:
			return 31
		4, 6, 9, 11:
			return 30
		_:
			var leap := (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
			return 29 if leap else 28
