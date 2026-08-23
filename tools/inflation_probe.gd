extends SceneTree

## V1.6b's headless sweep: godot --headless --script res://tools/inflation_probe.gd
##
## Every constant in src/sim/inflation_constants.gd is set from a table below rather
## than guessed and defended afterwards. THREE OF THE FIVE ARE NOT SWEPT AT ALL: the
## per-nation anchor, INFLATION_CONVERGENCE and INFLATION_UNEMP_BETA are measured off
## `FP.CPI.TOTL.ZG` in tools/import_data.py, which is V1.6a's instrument choice
## inherited rather than rediscovered. What is swept here is the two prices, because no
## dataset says what a voter feels or what a distortion costs.
##
## THE BANDS AND THE TIEBREAKERS ARE PRE-COMMITTED, and this session inherits SIX
## corrections to that discipline rather than five. V1.4c: fix the tiebreaker, not only
## the band. V1.5a: a tiebreaker must strictly ORDER the survivors. V1.5b: its answer
## must not MOVE when the grid is widened, and a value sitting at an endpoint of the
## swept range is a suspect rather than a result. V1.5c: nor when the grid is REFINED,
## and when the interval is bounded by two model criteria take the midpoint, and a
## guard rail does not select at all. V1.5d: before applying any edge-selecting rule,
## ask whether the response near that edge is LUMPY or SMOOTH -- smallest-passing and
## largest-passing are only meaningful on a shelf. And V1.6a, which is the one this
## session is most exposed to:
##
##     *** A BAND EDGE MOVES UNDER WIDENING OR REFINEMENT; A FIT CONVERGES. Where the
##     model over-determines a quantity, measure it and check the fit, and do not
##     manufacture a band for something the data already answers. ***
##
## TABLE (a) RUNS FIRST AND NOTHING IS SWEPT UNTIL IT HAS BEEN READ. It measures what
## deviation this channel can actually REACH under a budget a player would plausibly
## commit. Sweeping a price against the +-3.0 poll-noise floor without knowing that
## first is society_probe.gd table (c)'s error -- measuring a band on a path that
## cannot observe it -- and some form of it has now recurred in four consecutive
## sessions. The reachable figure is small by construction: INFLATION_UNEMP_BETA is
## 0.25 and a reachable unemployment gap is a couple of points.
##
##   (P1) PRICE    INFLATION_SCALE_PP -- points of inflation above the nation's own
##                 start that saturate the thirteenth issue.
##                 DECLARED (i) READABLE: on the ISOLATED path -- the stock displaced
##                     with every budget line untouched, so every other issue is
##                     bit-identical between the two runs -- the issue must move
##                     overall_approval_pct past the +-3.0 poll-noise floor at the
##                     deviation table (a) says is reachable.
##                 DECLARED (ii) NOT PREMATURELY SATURATED: the issue must not read
##                     +-1.0 at HALF the reachable deviation. DEFICIT_SCALE_PP's
##                     recorded failure -- at 3.0 a deficit two points over and one
##                     twenty points over read identically to a voter.
##                     *** DECLARED TOO WEAK, and the correction is recorded rather than
##                     tidied away: as written it passes 0.10, which saturates at the
##                     FULL reachable deviation -- admitting the exact failure it was
##                     written to prevent. The binding form is saturation at the PEAK.
##                     V1.4c's rule applied to a band that was loose rather than aimed
##                     at the wrong observable. Interval [0.15, 0.35], midpoint 0.25. ***
##                 TIEBREAKER: expected SMOOTH in advance (the satisfaction is linear in
##                     the deviation up to a clamp), so on V1.5d's rule neither edge
##                     selects and the INTERIOR governs: the midpoint of the passing
##                     interval. The lumpy-or-smooth verdict is read off the response
##                     column BEFORE the rule is applied, not after being surprised.
##
##   (P2) COST     INFLATION_OUTPUT_BETA -- points of annual growth lost per point of
##                 inflation above the anchor.
##                 DECLARED (i) GUARD, NOT A SELECTOR (V1.5c): the loop gain must stay
##                     below 1.0. It is analytic -- INFLATION_UNEMP_BETA * OKUN /
##                     UNEMP_REVERT * beta -- so this band is checked against the
##                     measured gain rather than used to choose, and the SLACK is
##                     reported the way defence.gd's and companies.gd's clamps are.
##                 DECLARED (ii) SUBORDINATE TO THE CYCLE: over a fourteen-year run the
##                     GDP lost to this channel must not exceed what V1.6a's cycle moves
##                     on its own. A cost of inflation louder than the business cycle
##                     that causes it would be this block describing itself backwards.
##                 DECLARED (iii) VISIBLE: it must move GDP by more than 0.25 % over a
##                     term under a reachable inflationary budget, or the channel is
##                     decorative and should be DELETED rather than shipped small --
##                     U6a's day budget and V1.3e's AGREEMENT_ACCEPT_MIN.
##                 TIEBREAKER: (ii) and (iii) bound it from two sides on two model
##                     criteria, which is V1.5c's midpoint case exactly.
##                 *** OUTCOME: (iii) FAILS AT EVERY HONEST CANDIDATE and the band's own
##                     prescription is refused in both halves. It needs beta >= 2.0 --
##                     one point of inflation costing two points of annual growth, more
##                     per point than the whole business cycle -- because table (a) puts
##                     the reachable deviation at 0.145 points. Not raised (that is
##                     tuning a measured slope's consequence until it is visible, which
##                     V1.5b and V1.6a each refused) and not deleted (the term is
##                     STRUCTURAL: it is the only thing making the loop negative
##                     feedback). Shipped at an honest 0.30 with the bound recorded, on
##                     docs/defence-model.md's unliftable-deployment precedent. (ii) was
##                     never a selector either -- GDP lost reaches the cycle's 3.367 %
##                     only near beta 100, so it is a BOUND, V1.5c's case again. ***
##
## Two further tables answer questions no band can:
##
##   (c) COLLINEARITY, the ISSUE_KEYS question's test 4, measured as a FIT rather than
##       a band on V1.6a's rule: |corr(sat.inflation, sat.growth)| must not exceed
##       |corr(sat.jobs, sat.growth)| ON THE SAME RUN -- the entanglement the model
##       already accepts between two keys Okun's law links mechanically.
##   (d) THE REALISED-SD CROSS-CHECK. With the anchor, the slope and the persistence
##       all measured, the model's own realised inflation standard deviation is
##       OVER-DETERMINED and can be compared with the measured one. Nothing else in
##       this file would catch a units error in the annual-to-monthly conversion.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const K = preload("res://src/sim/inflation_constants.gd")

const MONTHS := 168
const TERM_MONTHS := 60
const START_YEAR := 2026

## The budgets table (a) measures against. `hot` is the reachable inflationary case --
## a real stimulus a player might run -- and `cold` its mirror. `extreme` is included
## to show the reachable figure is bounded by the MODEL and not by the choice of budget.
const BUDGETS := {
	"quiet": {},
	"hot": {
		"spending_pct_gdp": {"health": 2.0, "infrastructure": 1.5, "education": 1.0},
		"tax_rates_pct": {"income": -3.0, "vat": -2.0},
	},
	"cold": {
		"spending_pct_gdp": {"health": -2.0, "infrastructure": -1.5, "education": -1.0},
		"tax_rates_pct": {"income": 3.0, "vat": 2.0},
	},
	"extreme": {
		"spending_pct_gdp": {
			"health": 19.0, "education": 14.5, "defence": 18.0,
			"pensions": 15.5, "infrastructure": 16.5,
		},
		"tax_rates_pct": {"income": -20.0, "corporate": -25.0, "vat": -20.0},
	},
}

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	var reachable := _table_a_reachable()
	_table_b_scale(reachable)
	_table_c_cost(reachable)
	_table_d_collinearity()
	_table_e_realised_sd()
	_table_f_s10_ratio()
	quit(0)


## (a) WHAT THIS CHANNEL CAN REACH. Run first, and every band below is stated against
## its answer rather than against a number picked in advance.
func _table_a_reachable() -> float:
	print("\n(a) reachable inflation deviation, by budget, France, %d months" % MONTHS)
	print("%-10s %10s %10s %10s %10s" % ["budget", "peak dev", "trough dev", "peak u gap", "end GDP %"])
	var best := 0.0
	for name in BUDGETS:
		var state = _new_state()
		var ns = state.player()
		var base_gdp: float = ns.gdp_eur_bn
		_commit(state, BUDGETS[name])
		var peak := 0.0
		var trough := 0.0
		var peak_gap := 0.0
		for i in range(MONTHS):
			_step(state, i)
			var dev: float = Inflation.inflation_deviation(ns)
			peak = maxf(peak, dev)
			trough = minf(trough, dev)
			peak_gap = maxf(peak_gap, absf(
				ns.structural_unemployment_pct - ns.unemployment_pct
			))
		print("%-10s %10.3f %10.3f %10.3f %10.2f" % [
			name, peak, trough, peak_gap, 100.0 * (ns.gdp_eur_bn / base_gdp - 1.0)
		])
		if name != "extreme":
			best = maxf(best, maxf(peak, absf(trough)))
	print("  reachable deviation (excluding `extreme`): %.3f points" % best)
	print("  -> every band below is stated against THIS figure, not against one chosen first")
	return best


## (b) INFLATION_SCALE_PP, on the ISOLATED path: the stock is displaced by hand with
## every budget line untouched, so the deficit, every tax and every other issue are
## bit-identical between the two runs and the only difference is this issue.
## society_probe.gd's and unrest_probe.gd's device.
func _table_b_scale(reachable: float) -> void:
	print("\n(b) INFLATION_SCALE_PP -- isolated path, displacement %.3f (table (a))" % reachable)
	print("%-10s %12s %12s %10s %8s %8s" % [
		"scale", "headline dev", "sat at peak", "sat at 1/2", "(i)", "(ii)"
	])
	var passing: Array[float] = []
	for scale in [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 1.00]:
		# EXACT, not extrapolated. The model runs at the SHIPPED scale and the constant
		# cannot be changed at runtime, so the candidate is emulated by displacing the
		# stock to whatever produces the SAME satisfaction the candidate would:
		# sat = -dev/scale, so displacing by reachable * shipped / candidate is
		# arithmetically identical, saturation included.
		#
		# The first version rescaled the measured headline linearly instead, and it was
		# wrong in a way worth recording: approval is not linear in satisfaction --
		# SALIENCE_GAIN amplifies bad news -- and, worse, the rescale was anchored on
		# the shipped value, so THE PASSING INTERVAL MOVED WHEN THE SHIPPED CONSTANT
		# MOVED. That is V1.5b's "the range was choosing the constant" wearing a
		# different hat, and it was caught only because the constant was set once and
		# the probe re-run.
		var emulated: float = reachable * OpinionK.INFLATION_SCALE_PP / scale
		var quiet := _isolated_headline(0.0)
		var moved := _isolated_headline(emulated)
		var scaled_dev: float = moved - quiet
		var sat_peak: float = clampf(-reachable / scale, -1.0, 1.0)
		var sat_half: float = clampf(-0.5 * reachable / scale, -1.0, 1.0)
		var band_i: bool = absf(scaled_dev) > 3.0
		# The BINDING form, per the header: saturation at the PEAK, not at half of it.
		var band_ii: bool = absf(sat_peak) < 1.0
		if band_i and band_ii:
			passing.append(scale)
		print("%-10.2f %12.3f %12.3f %10.3f %8s %8s" % [
			scale, scaled_dev, sat_peak, sat_half,
			"PASS" if band_i else "fail", "PASS" if band_ii else "fail"
		])
	_report_interval("INFLATION_SCALE_PP", passing, OpinionK.INFLATION_SCALE_PP)


## (c) INFLATION_OUTPUT_BETA. Band (i) is a GUARD checked against the analytic loop
## gain rather than a selector; (ii) and (iii) bound it from two sides.
func _table_c_cost(reachable: float) -> void:
	var analytic_unit: float = (
		K.INFLATION_UNEMP_BETA * EconomyK.OKUN / EconomyK.UNEMP_REVERT
	)
	print("\n(c) INFLATION_OUTPUT_BETA -- loop gain = %.4f x beta (analytic)" % analytic_unit)
	var cycle_gdp: float = _cycle_only_gdp_swing()
	print("    V1.6a's cycle alone moves GDP %.3f %% over %d months -- band (ii)'s ceiling"
		% [cycle_gdp, MONTHS])
	print("%-10s %10s %12s %10s %8s %8s %8s" % [
		"beta", "loop gain", "GDP lost %", "term GDP %", "(i)", "(ii)", "(iii)"
	])
	var passing: Array[float] = []
	for beta in [0.05, 0.10, 0.20, 0.30, 0.50, 0.80, 1.20, 1.60, 2.00, 3.00, 5.00, 8.00]:
		var lost: float = _gdp_cost_of(beta, MONTHS)
		var term: float = _gdp_cost_of(beta, TERM_MONTHS)
		var gain: float = analytic_unit * beta
		var band_i: bool = gain < 1.0
		var band_ii: bool = absf(lost) <= cycle_gdp
		var band_iii: bool = absf(term) > 0.25
		if band_i and band_ii and band_iii:
			passing.append(beta)
		print("%-10.2f %10.4f %12.3f %10.3f %8s %8s %8s" % [
			beta, gain, lost, term,
			"PASS" if band_i else "FAIL", "PASS" if band_ii else "fail",
			"PASS" if band_iii else "fail"
		])
	print("  guard slack at the shipped %.2f: loop gain %.4f against 1.0" % [
		K.INFLATION_OUTPUT_BETA, analytic_unit * K.INFLATION_OUTPUT_BETA
	])
	_report_interval("INFLATION_OUTPUT_BETA", passing, K.INFLATION_OUTPUT_BETA)


## (d) THE ISSUE_KEYS QUESTION'S TEST 4, as a fit against the model's own accepted
## standard rather than a band. `jobs` and `growth` are two keys Okun's law links
## mechanically and the model accepts them as distinct; if inflation is no more
## entangled with `growth` than that, the model's own standard says it is distinct too.
func _table_d_collinearity() -> void:
	print("\n(d) collinearity -- test 4 of the ISSUE_KEYS question")
	var state = _new_state()
	var ns = state.player()
	_commit(state, BUDGETS["hot"])
	var infl: Array[float] = []
	var grow: Array[float] = []
	var jobs: Array[float] = []
	for i in range(MONTHS):
		_step(state, i)
		var sat := Opinion.issue_satisfaction(ns)
		infl.append(float(sat["inflation"]))
		grow.append(float(sat["growth"]))
		jobs.append(float(sat["jobs"]))
	var c_infl: float = absf(_corr(infl, grow))
	var c_jobs: float = absf(_corr(jobs, grow))
	print("  |corr(inflation, growth)| = %.4f" % c_infl)
	print("  |corr(jobs,      growth)| = %.4f   <- the standard the model already accepts" % c_jobs)
	print("  |corr(inflation, jobs)|   = %.4f" % absf(_corr(infl, jobs)))
	if c_infl <= c_jobs:
		print("  VERDICT: PASS -- less entangled than a pair already in the model")
	else:
		print("  VERDICT: FAIL -- more entangled than jobs/growth; the thirteenth key is a re-split")


## (e) THE CROSS-CHECK NOTHING ELSE WOULD CATCH. Anchor, slope and persistence are all
## measured, so the realised standard deviation is over-determined. France's measured
## figure is 1.14 and Spain's 2.03; the model runs quieter because the harness has no
## oil shock, but a factor-of-ten miss here would mean the annual-to-monthly conversion
## in INFLATION_CONVERGENCE is wrong.
func _table_e_realised_sd() -> void:
	print("\n(e) realised inflation sd, %d months, no player action" % MONTHS)
	print("%-6s %10s %10s %10s" % ["nation", "anchor", "model sd", "mean"])
	var state = _new_state()
	var series := {}
	for id in state.nations:
		series[id] = [] as Array[float]
	for i in range(MONTHS):
		_step(state, i)
		for id in state.nations:
			(series[id] as Array[float]).append(float(state.nations[id].inflation_pct))
	for id in ["FRA", "DEU", "ESP", "CHE", "LUX"]:
		var xs: Array[float] = series[id]
		var m: float = _mean(xs)
		print("%-6s %10.3f %10.3f %10.3f" % [
			id, state.nations[id].inflation_anchor_pct, _sd(xs), m
		])
	print("  measured (World Bank 1990-2024): FRA sd 1.14, ESP 2.03 -- the model is")
	print("  quieter because this harness has no supply shock, which is section 8's")


## (f) The S10 ratio drift, the number that took `europe` at +0.39 % and refused
## `ownership` at -1.46 %. Computed off the weight table directly rather than from a
## run, because it is a property of the simplex and not of any particular game.
func _table_f_s10_ratio() -> void:
	print("\n(f) S10 ratio drift -- public_finances against the five spending lines")
	var with_key: float = _s10_ratio(true)
	var without: float = _s10_ratio(false)
	print("  without inflation %.6f" % without)
	print("  with    inflation %.6f" % with_key)
	print("  drift %+.3f %%   (V1.3d took +0.39 %%, V1.4c refused -1.46 %%)" % [
		100.0 * (with_key - without) / without
	])


# --- helpers -----------------------------------------------------------------------

## The isolated path spells its own tick sequence out rather than calling _step(),
## because the displacement has to land BETWEEN Inflation and Opinion: after
## Inflation.tick_month() (which would otherwise overwrite it from the lag) and before
## Opinion reads it. The first version displaced after _step() and then ticked Opinion
## AGAIN, so opinion ran twice a month and the response was inflated by an inertia
## nobody chose -- the probe correcting itself, which is the fifteenth session running.
func _isolated_headline(displacement: float) -> float:
	var state = _new_state()
	var ns = state.player()
	for i in range(TERM_MONTHS):
		state.year = START_YEAR + int(i / 12)
		state.month = (i % 12) + 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		Inflation.tick_month(state)
		ns.inflation_pct = ns.start_inflation_pct + displacement
		Opinion.tick_month(state)
		Demography.tick_month(state)
		Society.tick_month(state)
		Unrest.tick_month(state)
		Cabinet.tick_month(state, _loader)
	return ns.overall_approval_pct


func _gdp_cost_of(beta: float, months: int) -> float:
	var state = _new_state()
	var ns = state.player()
	_commit(state, BUDGETS["hot"])
	var base: float = ns.gdp_eur_bn
	for i in range(months):
		_step(state, i)
		# Rescale the shipped impulse to the candidate, which is exact because the cost
		# is linear in the constant -- cycle_probe.gd's _scale_amplitude() device.
		ns.inflation_impulse_pct *= beta / K.INFLATION_OUTPUT_BETA
	var with_cost: float = ns.gdp_eur_bn

	var control = _new_state()
	var cn = control.player()
	var cbase: float = cn.gdp_eur_bn
	_commit(control, BUDGETS["hot"])
	for i in range(months):
		_step(control, i)
		cn.inflation_impulse_pct = 0.0
	return 100.0 * ((with_cost / base) - (cn.gdp_eur_bn / cbase))


func _cycle_only_gdp_swing() -> float:
	var state = _new_state()
	var ns = state.player()
	var lo := 0.0
	var hi := 0.0
	var base: float = ns.gdp_eur_bn
	var potential: float = ns.potential_gdp_eur_bn
	for i in range(MONTHS):
		_step(state, i)
		var off: float = 100.0 * (
			(ns.gdp_eur_bn / base) - (ns.potential_gdp_eur_bn / potential)
		)
		lo = minf(lo, off)
		hi = maxf(hi, off)
	return hi - lo


func _s10_ratio(include_inflation: bool) -> float:
	var spend := ["health", "education", "defence", "pensions", "infrastructure"]
	var pf := 0.0
	var sp := 0.0
	for bloc in OpinionK.BLOC_KEYS:
		var row: Dictionary = OpinionK.BLOC_SALIENCE_BASE[bloc]
		var total := 0.0
		for key in row:
			if key == "inflation" and not include_inflation:
				continue
			total += float(row[key])
		var size: float = float(OpinionK.BLOC_SIZE[bloc])
		pf += size * float(row.get("public_finances", 0.0)) / total
		for key in spend:
			sp += size * float(row.get(key, 0.0)) / total
	return pf / sp


## V1.5d's rule: on a SMOOTH response neither edge selects and the interior governs.
## Printed rather than applied silently, so the lumpy-or-smooth judgement is visible.
func _report_interval(name: String, passing: Array[float], shipped: float) -> void:
	if passing.is_empty():
		print("  %s: NO CANDIDATE PASSES -- the band is unreachable and must be recorded, not widened" % name)
		return
	var lo: float = passing[0]
	var hi: float = passing[passing.size() - 1]
	print("  %s passes on [%.2f, %.2f]; smooth response -> interior governs, midpoint %.3f" % [
		name, lo, hi, 0.5 * (lo + hi)
	])
	print("  shipped: %.2f" % shipped)


func _corr(xs: Array[float], ys: Array[float]) -> float:
	var mx: float = _mean(xs)
	var my: float = _mean(ys)
	var sxy := 0.0
	var sxx := 0.0
	var syy := 0.0
	for i in range(xs.size()):
		sxy += (xs[i] - mx) * (ys[i] - my)
		sxx += (xs[i] - mx) * (xs[i] - mx)
		syy += (ys[i] - my) * (ys[i] - my)
	if sxx <= 0.0 or syy <= 0.0:
		return 0.0
	return sxy / sqrt(sxx * syy)


func _mean(xs: Array[float]) -> float:
	var t := 0.0
	for x in xs:
		t += x
	return t / float(xs.size())


func _sd(xs: Array[float]) -> float:
	var m: float = _mean(xs)
	var t := 0.0
	for x in xs:
		t += (x - m) * (x - m)
	return sqrt(t / float(xs.size()))


func _commit(state, regime: Dictionary) -> void:
	if regime.is_empty():
		return
	var ns = state.player()
	var pending := {}
	if regime.has("tax_rates_pct"):
		var taxes := {}
		for key in regime["tax_rates_pct"]:
			taxes[key] = maxf(
				0.0,
				float(ns.start_tax_rates_pct[key]) + float(regime["tax_rates_pct"][key])
			)
		pending["tax_rates_pct"] = taxes
	if regime.has("spending_pct_gdp"):
		var lines := {}
		for key in regime["spending_pct_gdp"]:
			lines[key] = maxf(
				0.0,
				float(ns.start_spending_pct_gdp[key])
				+ float(regime["spending_pct_gdp"][key])
			)
		pending["spending_pct_gdp"] = lines
	Budget.commit(state, pending)


## src/ui/main.gd's order minus the political layer -- unrest_probe.gd's loop and its
## limitation: no elections, no lose condition.
func _step(state, months_in: int) -> void:
	state.year = START_YEAR + int(months_in / 12)
	state.month = (months_in % 12) + 1
	Economy.tick_month(state)
	Budget.tick_month(state)
	Inflation.tick_month(state)
	Opinion.tick_month(state)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, _loader)


func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = START_YEAR
	state.month = 1
	return state
