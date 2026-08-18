extends SceneTree

## V1.5c's headless sweep. Every constant in src/sim/unrest_constants.gd is set from a
## table below rather than guessed and defended afterwards.
##
## THE BANDS AND THE TIEBREAKERS ARE BOTH PRE-COMMITTED, and this session inherits three
## corrections to that discipline rather than one. V1.4c: fix the tiebreaker, not only
## the band. V1.5a: a tiebreaker must strictly ORDER the survivors, checked by asking
## what it would say if every row passed. V1.5b: its answer must also NOT MOVE when the
## candidate grid is widened, because two one-sided bands let the RANGE choose. Every
## row below is marked for the one-sided failure IN ADVANCE, and every chosen value is
## re-read against a widened grid before it is believed.
##
##   (P1) SPEED     UNREST_CONVERGENCE. TWO-SIDED BY CONSTRUCTION, which is what makes
##                  it the safe one: the half-life must be SHORTER than
##                  society_constants.QUALITY_CONVERGENCE's ~34 months (a grievance is
##                  not a hospital) and LONGER than opinion_constants.INERTIA_RATE's
##                  ~2.4 months (else this is approval with a delay, which
##                  opinion_constants.gd's own comment forbids as "two lags in series").
##                  TIEBREAKER: nearest the geometric mean of the two bracketing
##                  half-lives. Deliberately NOT "nearest CAPABILITY_CONVERGENCE" --
##                  that worked for QUALITY_CONVERGENCE because a service and an army
##                  converge alike, and here it would reproduce 0.02 against a model
##                  reason that anger is faster. Interior to any bracketing grid, so it
##                  is stable under widening by construction.
##
##   (P2) FIRE      UNREST_THRESHOLD_PCT. (i) fires at least once under `austerity`
##                  inside 168 months; (ii) fires EXACTLY ZERO times under `hands_off`
##                  and under `managed`. Clause (ii) was added because (i) alone is a
##                  one-sided minimum -- V1.5b's failure -- and it does three jobs at
##                  once: it closes the interval, it is the reachability guard the
##                  balance re-run needs, and it is the cleanest statement of *a
##                  well-governed France does not have a general strike*.
##                  TIEBREAKER: the largest passing candidate still clearing (i) with at
##                  least two fires. Interior to the interval.
##
##   (P3) SHOCK     UNREST_IMPULSE_SCALE. Legible on the WORKERS bloc approval row past
##                  +-3.0 -- the bloc row and not the headline, because society_probe.gd
##                  table (c) established a single issue cannot reliably carry a
##                  headline price and demography_probe.gd moved to a bloc row for the
##                  same reason.
##                  TIEBREAKER: V1.5a's two-part selector, the only one on this
##                  project's record that has ever picked exactly one row -- legible AND
##                  the saturated value leaves UNREST_IMPULSE_MAX_PCT strictly slack.
##                  Part two is checked BEFORE the sweep to confirm it excludes
##                  candidates; a part every candidate satisfies is a bound and not a
##                  selector, which is CORRUPTION_DELIVERY_BETA's failure at V1.5a.
##
##   (P4) CLOSE     UNREST_SETTLEMENT_BETA. (i) readable on the workers row past +-3.0;
##                  (ii) CLOSABLE -- a saturated settlement holds unrest at or below
##                  where it started under a budget that would otherwise cross the
##                  threshold. That is demography_probe.gd's band (ii) verbatim, and it
##                  is here for its reason: without a closer, unrest is the permanent
##                  monotone charge docs/defence-model.md names.
##                  BOTH BANDS ARE ONE-SIDED MINIMUMS, so V1.5b's forced correction is
##                  applied IN ADVANCE rather than discovered: the SMALLEST passing
##                  candidate ships.
##
##   (P5) INEQUAL   *** KILL SWITCH ***. INEQUALITY_BETA. The measured Gini drift must
##                  move the date of the first act at some candidate. If it cannot, the
##                  constant is DELETED and inequality ships as a readout src/sim/ does
##                  not read -- DEPENDENCY_ELASTICITY["health"]'s treatment at V1.5b,
##                  where an entry was deleted rather than shipped at a value that looks
##                  alive in a constants file and is invisible in play.
##                  Measured on GERMANY: the roster's slopes run from NLD -0.417 to DEU
##                  +0.329 and France's own is -0.113, so for the default nation this
##                  term CALMS. A term that cannot be seen where it is largest cannot be
##                  seen anywhere.
##
##   (P6) LOOP B    Not a sweep, and the measurement this session would most regret
##                  omitting. strike -> approval -> Discipline.unpopularity() ->
##                  cabinet.gd's resignation -> VACANT_EFFECTIVENESS ->
##                  Society.quality_target() -> health/pensions satisfaction -> unrest.
##                  Nothing closes that without a player reshuffle, and it runs straight
##                  through the model widening V1.5a recorded and kept on the evidence
##                  that zero outcomes moved. V1.5c is the session that supplies the
##                  push. If unrest_pct sits on UNREST_MAX under `austerity` with no
##                  reshuffle, the clamp is setting the number and the MODEL is wrong.
##
##   (P7) SATURATE  Also not a sweep. jobs satisfaction is clamped at -1 by
##                  JOBS_SCALE_PP = 3.0, and a hardship term reading a saturated
##                  satisfaction cannot tell bad from catastrophic. Printed because the
##                  escalation labels read the STOCK rather than the instantaneous term,
##                  and this is the evidence the stock still discriminates where the
##                  term does not.
##
##   (P8) CLAMPS    Every bound measured slack, docs/defence-model.md's bill-clamp
##                  discipline.
##
## Not a test. Excluded from tools/run_tests.sh by design, so run it explicitly:
##   godot --headless --script res://tools/unrest_probe.gd

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const K = preload("res://src/sim/unrest_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const SK = preload("res://src/sim/society_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")

const START_YEAR := 2026
const TERM_MONTHS := 60
const RUN_MONTHS := 168
const NOISE_FLOOR := 3.0

## balance_probe.gd's own deltas, copied rather than imported because tools/ files do
## not preload each other and the three that matter here are the three the bands name.
const REGIMES := {
	"hands_off": {},
	"managed": {
		"spending_pct_gdp": {"defence": -1.4},
		"tax_rates_pct": {"vat": 3.0},
	},
	"austerity": {
		"spending_pct_gdp": {
			"health": -2.5, "education": -2.0, "defence": -1.0,
			"pensions": -3.5, "infrastructure": -2.0,
		},
		"tax_rates_pct": {"income": 6.0, "corporate": 5.0, "vat": 4.0},
	},
	"spendthrift": {
		"spending_pct_gdp": {
			"health": 3.0, "education": 2.5, "defence": 1.5,
			"pensions": 3.5, "infrastructure": 2.5,
		},
		"tax_rates_pct": {"income": -6.0, "corporate": -7.0, "vat": -4.0},
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
	"ruinous": {
		"spending_pct_gdp": {
			"health": 19.0, "education": 14.5, "defence": 18.0,
			"pensions": 15.5, "infrastructure": 16.5,
		},
		"tax_rates_pct": {"income": -20.0, "corporate": -25.0, "vat": -20.0},
	},
}

## Swept at 0.01 resolution across the whole band rather than on a doubling ladder, and
## that is V1.5b's diagnostic applied to REFINEMENT rather than to widening. The first
## grid was [0.02, 0.04, 0.06, 0.08, 0.12, 0.16, 0.24] and the tiebreaker chose 0.08 --
## which is 0.78 months from the target. Refining the grid puts 0.07 at 0.46 months,
## so the SPACING was choosing the constant exactly as V1.5b's range was. A
## nearest-to-X tiebreaker is only as good as the resolution it is offered.
const CONVERGENCE_CANDIDATES := [
	0.02, 0.03, 0.04, 0.05, 0.06, 0.07, 0.08, 0.09, 0.10, 0.12, 0.16, 0.24, 0.32,
]
const THRESHOLD_CANDIDATES := [
	15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0, 52.0, 55.0, 58.0, 60.0, 70.0,
]
const IMPULSE_CANDIDATES := [0.5, 1.0, 2.0, 3.0, 4.0, 6.0]
const SETTLEMENT_CANDIDATES := [
	4.0, 5.0, 6.0, 7.0, 7.5, 8.0, 9.0, 10.0, 12.0, 15.0, 17.0, 20.0, 30.0, 60.0,
]

## Refined at 0.25 across the interesting range, table (b)'s lesson applied in advance:
## a coarse ladder lets the SPACING choose a nearest-passing answer.
const INEQUALITY_CANDIDATES := [
	0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.75, 1.0, 1.5, 2.0, 4.0, 8.0,
]
const OPINION_CANDIDATES := [0.05, 0.10, 0.12, 0.13, 0.14, 0.15, 0.20, 0.30, 0.50]

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	_table_a_reachability()
	_table_b_speed()
	_table_c_threshold()
	_table_d_impulse()
	_table_e_settlement()
	_table_f_inequality()
	_table_g_loop_b()
	_table_h_clamps()
	quit(0)


# --- Harness -------------------------------------------------------------------

func _new_state(nation_id: String):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	return state


func _commit(state, delta: Dictionary) -> void:
	if delta.is_empty():
		return
	var ns = state.player()
	var pending := {}
	if delta.has("tax_rates_pct"):
		var rates := {}
		for key in delta["tax_rates_pct"]:
			rates[key] = clampf(
				float(ns.start_tax_rates_pct.get(key, 0.0)) + float(delta["tax_rates_pct"][key]),
				0.0, 100.0
			)
		pending["tax_rates_pct"] = rates
	if delta.has("spending_pct_gdp"):
		var lines := {}
		for key in delta["spending_pct_gdp"]:
			lines[key] = maxf(
				float(ns.start_spending_pct_gdp.get(key, 0.0)) + float(delta["spending_pct_gdp"][key]),
				0.0
			)
		pending["spending_pct_gdp"] = lines
	Budget.commit(state, pending)


## main.gd's order, Unrest last. `reshuffle` is what P6 turns off.
func _step(state, months_in: int) -> void:
	var year: int = START_YEAR + int((months_in) / 12)
	var month: int = (months_in % 12) + 1
	state.year = year
	state.month = month
	Economy.tick_month(state)
	Budget.tick_month(state)
	# V1.6b. See src/ui/main.gd for why this sits after Economy and before Opinion.
	Inflation.tick_month(state)
	Opinion.tick_month(state)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, _loader)


## The UNFORCED grievance path: the real tick with the agent suppressed, by holding the
## cooldown above zero every month.
##
## Sound rather than approximate for both of P2's bands, and that is why the threshold
## can be swept offline. An act costs output, output costs jobs, and jobs raise
## grievance -- so the real path is everywhere AT OR ABOVE this one. A threshold this
## path crosses is therefore crossed by the real model too, and a threshold this path
## never reaches is never reached by the real model either, because with no act there is
## no feedback to add. Lower bound on (i), exact on (ii).
func _unforced_path(nation_id: String, delta: Dictionary, months: int) -> Array:
	var state = _new_state(nation_id)
	_commit(state, delta)
	var path: Array = []
	for i in range(months):
		state.player().unrest_cooldown_months = 9999
		_step(state, i)
		path.append(float(state.player().unrest_pct))
	return path


## How many acts a threshold and a cooldown would produce over a recorded path.
func _acts_over(path: Array, threshold: float, cooldown: int) -> int:
	var acts := 0
	var wait := 0
	for value in path:
		if wait > 0:
			wait -= 1
			continue
		if float(value) >= threshold:
			acts += 1
			wait = cooldown
	return acts


func _peak(path: Array) -> float:
	var top := 0.0
	for v in path:
		top = maxf(top, float(v))
	return top


# --- (a) P2's reachability guard, and the table the balance re-run depends on ---

## Printed FIRST because everything after it is meaningless if no reachable budget ever
## crosses the threshold: all twenty-four balance regimes would come back bit-identical
## and their bit-identity would say nothing about this channel. That is U6a's finding
## about the day loop -- thirteen regimes that could not see a day-resolution dispatch
## -- and it is measured here rather than assumed.
func _table_a_reachability() -> void:
	print("\n=== (a) P2 reachability: unforced grievance path per existing regime, FRA, %d months ===" % RUN_MONTHS)
	print("shipped threshold %.1f. `hands_off` and `managed` MUST read 0 acts." % K.UNREST_THRESHOLD_PCT)
	print("%-14s %10s %10s %8s" % ["regime", "peak", "final", "acts"])
	var names: Array = REGIMES.keys()
	names.sort()
	for name in names:
		var path := _unforced_path("FRA", REGIMES[name], RUN_MONTHS)
		print("%-14s %10.2f %10.2f %8d" % [
			name, _peak(path), float(path[path.size() - 1]),
			_acts_over(path, K.UNREST_THRESHOLD_PCT, K.UNREST_COOLDOWN_MONTHS),
		])


# --- (b) P1: UNREST_CONVERGENCE -------------------------------------------------

func _half_life(rate: float) -> float:
	if rate <= 0.0 or rate >= 1.0:
		return INF
	return log(0.5) / log(1.0 - rate)


func _table_b_speed() -> void:
	var slow := _half_life(SK.QUALITY_CONVERGENCE)
	var fast := _half_life(OK.INERTIA_RATE)
	var target := sqrt(slow * fast)
	print("\n=== (b) P1: UNREST_CONVERGENCE ===")
	print("band: half-life strictly between %.2f mo (INERTIA_RATE) and %.2f mo (QUALITY_CONVERGENCE)" % [fast, slow])
	print("tiebreaker: nearest their geometric mean, %.2f mo" % target)
	print("%-10s %12s %8s %12s" % ["rate", "half-life", "band", "|dist|"])
	for rate in CONVERGENCE_CANDIDATES:
		var hl := _half_life(rate)
		var inside: bool = hl > fast and hl < slow
		print("%-10.3f %12.2f %8s %12.2f" % [rate, hl, "PASS" if inside else "fail", absf(hl - target)])


# --- (c) P2: UNREST_THRESHOLD_PCT ----------------------------------------------

func _table_c_threshold() -> void:
	print("\n=== (c) P2: UNREST_THRESHOLD_PCT, acts over %d months at cooldown %d ===" % [
		RUN_MONTHS, K.UNREST_COOLDOWN_MONTHS,
	])
	print("band (i) austerity >= 1 AND spend_zero >= 1; band (ii) hands_off == 0 AND managed == 0")
	print("tiebreaker: largest passing candidate still clearing (i) with >= 2 acts")
	print("BAND (i) WAS WIDENED AFTER THE FIRST SWEEP, and the reason is a finding rather")
	print("than a retune. Against austerity alone the tiebreaker chose 52.0 -- which passes")
	print("V1.5a's ordering check and V1.5b's widening check and is still wrong, because the")
	print("interval's ceiling is set by ONE regime's measured peak (52.82), so `largest")
	print("passing` means `that peak, minus 0.8`. At 52.0 a budget that ZEROES EVERY")
	print("SPENDING LINE produces no industrial action at all, which is not a model anyone")
	print("would defend. That is a criterion the bands should have contained and did not --")
	print("V1.3f's AGENDA_ACT_MIN, where a pre-committed sweep measured a state that could")
	print("not answer the question. The selector is unchanged.")
	var austerity := _unforced_path("FRA", REGIMES["austerity"], RUN_MONTHS)
	var quiet := _unforced_path("FRA", REGIMES["hands_off"], RUN_MONTHS)
	var managed := _unforced_path("FRA", REGIMES["managed"], RUN_MONTHS)
	var zeroed := _unforced_path("FRA", REGIMES["spend_zero"], RUN_MONTHS)
	print("%-10s %10s %10s %10s %10s %8s" % ["threshold", "austerity", "spend_zero", "hands_off", "managed", "band"])
	for t in THRESHOLD_CANDIDATES:
		var a := _acts_over(austerity, t, K.UNREST_COOLDOWN_MONTHS)
		var z := _acts_over(zeroed, t, K.UNREST_COOLDOWN_MONTHS)
		var h := _acts_over(quiet, t, K.UNREST_COOLDOWN_MONTHS)
		var m := _acts_over(managed, t, K.UNREST_COOLDOWN_MONTHS)
		var pass_band: bool = a >= 1 and z >= 1 and h == 0 and m == 0
		print("%-10.1f %10d %10d %10d %10d %8s" % [t, a, z, h, m, "PASS" if pass_band else "fail"])

	print("\n-- cooldown, at the shipped threshold: acts per 60-month term under austerity --")
	print("band (i) > 1 act per term, else the escalation labels are dead content")
	print("%-10s %10s %10s" % ["cooldown", "168mo", "per term"])
	for cd in [3, 6, 9, 12, 18, 24, 36]:
		var acts := _acts_over(austerity, K.UNREST_THRESHOLD_PCT, cd)
		print("%-10d %10d %10.2f" % [cd, acts, float(acts) * float(TERM_MONTHS) / float(RUN_MONTHS)])


# --- (d) P3: UNREST_IMPULSE_SCALE ----------------------------------------------

## Mirrors Unrest._tick_nation() with the impulse scale as a parameter. The duplication
## is deliberate and bounded: it is the only way to sweep a constant the tick reads
## directly, and demography_probe.gd swept MIGRATION_SHARE_BETA by scaling its INPUT for
## the same reason. If this ever disagrees with unrest.gd, unrest.gd is right.
func _run_with_impulse(nation_id: String, injected: float, scale: float, months: int) -> Dictionary:
	var state = _new_state(nation_id)
	var peak_impulse := 0.0
	var cooldown := 0
	for i in range(months):
		var ns = state.player()
		# The whole isolation: the grievance is HELD at a fixed level rather than
		# earned, so the two runs differ in the impulse and in nothing else.
		ns.unrest_pct = injected
		var acted: bool = injected >= K.UNREST_THRESHOLD_PCT and cooldown <= 0
		ns.unrest_cooldown_months = 9999
		_step(state, i)
		ns.unrest_pct = injected
		if cooldown > 0:
			cooldown -= 1
		if acted:
			ns.unrest_impulse_pct = clampf(
				float(ns.unrest_impulse_pct) - scale * clampf(injected / K.UNREST_MAX, 0.0, 1.0),
				-K.UNREST_IMPULSE_MAX_PCT, K.UNREST_IMPULSE_MAX_PCT
			)
			cooldown = K.UNREST_COOLDOWN_MONTHS
		peak_impulse = maxf(peak_impulse, absf(float(ns.unrest_impulse_pct)))
	return {"state": state, "peak_impulse": peak_impulse}


## MEASURED ON THE ISOLATED PATH, and the first version was not.
##
## It swept the scale under `austerity`, and every candidate failed by a margin that
## made no sense -- the workers row moved 0.14 points between scale 0 and scale 6. The
## reason is society_probe.gd table (c)'s exactly, in a new place: under austerity the
## workers row is already at 28 against a neutral 50 and `jobs` is already near its
## clamp, so the channel being banded was not observable on that path. THE BAND WAS
## MEASURED WHERE THE THING BEING MEASURED CANNOT BE SEEN, three sessions running.
##
## The isolated path holds the grievance at a fixed level under `hands_off`, so every
## other issue is identical between the runs and the only difference is the act.
func _table_d_impulse() -> void:
	var injected: float = K.UNREST_MAX
	print("\n=== (d) P3: UNREST_IMPULSE_SCALE, ISOLATED, grievance held at %.0f, %d months ===" % [injected, RUN_MONTHS])
	print("band: workers bloc approval row moves past +-%.1f against the same run at scale 0" % NOISE_FLOOR)
	print("tiebreaker: legible AND the saturated impulse leaves UNREST_IMPULSE_MAX_PCT = %.2f slack" % K.UNREST_IMPULSE_MAX_PCT)
	var base := _run_with_impulse("FRA", injected, 0.0, RUN_MONTHS)
	var base_ns = base["state"].player()
	var base_row: float = float(base_ns.bloc_approval["workers"])
	var base_gdp: float = float(base_ns.gdp_eur_bn)
	var base_unemp: float = float(base_ns.unemployment_pct)
	print("reference (scale 0.0): workers row %.2f, GDP %.1f, unemployment %.2f" % [
		base_row, base_gdp, base_unemp,
	])
	print("%-8s %10s %8s %10s %9s %11s %9s %7s" % [
		"scale", "workers", "d appr", "d GDP %", "d unemp", "peak imp.", "clamp", "band",
	])
	for scale in IMPULSE_CANDIDATES:
		var run := _run_with_impulse("FRA", injected, scale, RUN_MONTHS)
		var ns = run["state"].player()
		var row: float = float(ns.bloc_approval["workers"])
		var peak: float = float(run["peak_impulse"])
		var slack: bool = peak < K.UNREST_IMPULSE_MAX_PCT - 0.0001
		var d_gdp: float = 100.0 * (float(ns.gdp_eur_bn) - base_gdp) / base_gdp
		print("%-8.2f %10.2f %8.2f %10.2f %9.2f %11.3f %9s %7s" % [
			scale, row, row - base_row, d_gdp, float(ns.unemployment_pct) - base_unemp,
			peak, "slack" if slack else "BINDS",
			"PASS" if absf(row - base_row) >= NOISE_FLOOR and slack else "fail",
		])
	print("The APPROVAL column is the pre-committed band. The GDP and unemployment columns")
	print("are printed beside it because the band's own premise -- that an output price")
	print("reaches approval through `growth` and `jobs` -- is the thing under test, and a")
	print("channel can be large in the economy and small in the polls. Read them together.")
	_table_d2_opinion()


## (d2) UNREST_OPINION_SCALE, the constant table (d) forced into existence.
##
## Swept by scaling the INPUT -- holding the grievance at a level chosen so the shipped
## scale produces the candidate load -- demography_probe.gd's trick, so there is no
## second copy of the tick to drift out of step.
func _table_d2_opinion() -> void:
	var reachable := 52.0
	print("
=== (d2) UNREST_OPINION_SCALE, austerity, %d months ===" % TERM_MONTHS)
	print("band: workers bloc approval row past +-%.1f at a REACHABLE grievance (~%.0f)," % [NOISE_FLOOR, reachable])
	print("not at the clamp. tiebreaker: legible AND the combined score leaves opinion.gd's")
	print("own +-1.0 clamp slack at the reachable worst case.")
	var base := _run_with_opinion(0.0, TERM_MONTHS)
	print("reference (scale 0.0): workers row %.2f" % float(base["row"]))
	print("%-10s %12s %10s %12s %10s %8s" % ["scale", "workers", "delta", "|score|", "clamp", "band"])
	for scale in OPINION_CANDIDATES:
		var run := _run_with_opinion(scale, TERM_MONTHS)
		var delta: float = float(run["row"]) - float(base["row"])
		var slack: bool = float(run["worst_score"]) < 1.0 - 0.0001
		print("%-10.2f %12.2f %10.2f %12.4f %10s %8s" % [
			scale, float(run["row"]), delta, float(run["worst_score"]),
			"slack" if slack else "BINDS",
			"PASS" if absf(delta) >= NOISE_FLOOR and slack else "fail",
		])


## The candidate scale, applied by overwriting the load Unrest just wrote. Cheaper and
## safer than a second copy of _tick_nation(): the stock is the real one.
func _run_with_opinion(scale: float, months: int) -> Dictionary:
	var state = _new_state("FRA")
	_commit(state, REGIMES["austerity"])
	var worst := 0.0
	for i in range(months):
		_step(state, i)
		var ns = state.player()
		if K.UNREST_OPINION_SCALE > 0.0:
			ns.unrest_opinion_load = float(ns.unrest_opinion_load) * scale / K.UNREST_OPINION_SCALE
		var sat: Dictionary = Opinion.issue_satisfaction(ns)
		var weights: Dictionary = Opinion.salience_weights(OK.BLOC_SALIENCE_BASE["workers"], sat, OK.SALIENCE_GAIN)
		var score := 0.0
		for issue in weights:
			score += float(weights[issue]) * float(sat.get(issue, 0.0))
		worst = maxf(worst, absf(score + float(ns.bloc_offset.get("workers", 0.0)) - float(ns.unrest_opinion_load)))
	return {"row": float(state.player().bloc_approval["workers"]), "worst_score": worst}


# --- (e) P4: UNREST_SETTLEMENT_BETA --------------------------------------------

## Swept by scaling the STANCE, demography_probe.gd's trick: the shipped beta times an
## effective stance equals the candidate beta times a saturated one. No duplicated tick.
func _effective_stance(beta: float) -> float:
	if K.SETTLEMENT_BETA <= 0.0:
		return 0.0
	return beta * K.SETTLEMENT_STANCE_MAX / K.SETTLEMENT_BETA


## THE FIRST BAND WAS REPLACED, AND THE REPLACEMENT IS TWO-SIDED.
##
## Band (i) was originally "readable on the workers row", the same shape table (d) uses.
## It failed at every candidate for table (d)'s reason and for one of its own: this
## channel's price is OUTPUT ONLY, so a settlement reaches approval through
## unrest -> output -> jobs, which is the saturated path -- while the part of a
## settlement a voter actually sees immediately is the law's own authored `bloc_offset`,
## which this constant has nothing to do with. Banding a constant on a channel it does
## not own is a measurement of the wrong quantity, not a failing constant.
##
## What replaced it closes the interval properly, which the original pair could not:
##   (i)  CLOSABLE -- a SATURATED stance holds unrest BELOW THE THRESHOLD under a budget
##        that would otherwise cross it. [minimum]
##        Written first as demography_probe.gd's "at or below where it started", lifted
##        verbatim, AND IT DID NOT TRANSFER: a dependency ratio rises forever, so holding
##        it flat is the only interesting question, where unrest converges on a bounded
##        target. "Back to its own start" then demands a beta big enough to zero a live
##        grievance (~60) while (ii) demands one under ~29, and the interval is EMPTY --
##        an artefact of the borrowed band, not a fact about settlements. For a bounded
##        stock, closable means STOPS THE STRIKES.
##   (ii) NOT IMMUNISING -- ONE authored settlement law (0.45 of the stance) must NOT
##        hold unrest under the threshold for a whole term. A single law that ends the
##        mechanic forever is the strictly-dominated shape this project has now named
##        six times, arriving as a free permanent cure. [maximum]
## Two-sided, so "smallest passing" is a real selector rather than the bottom row of
## whatever grid was swept.
func _table_e_settlement() -> void:
	const ONE_LAW := 0.45
	print("\n=== (e) P4: UNREST_SETTLEMENT_BETA, austerity, %d months ===" % TERM_MONTHS)
	print("band (i) CLOSABLE -- saturated stance holds unrest below the threshold (%.1f)" % K.UNREST_THRESHOLD_PCT)
	print("band (ii) NOT IMMUNISING -- one authored law (%.2f of the stance) must not do it alone" % ONE_LAW)
	print("selector: SMALLEST passing candidate, pre-committed because (i) is a minimum")

	var quiet = _new_state("FRA")
	_commit(quiet, REGIMES["austerity"])
	for i in range(TERM_MONTHS):
		_step(quiet, i)
	var quiet_unrest: float = float(quiet.player().unrest_pct)
	print("reference (no settlement): unrest %.2f after %d months" % [quiet_unrest, TERM_MONTHS])
	print("%-10s %12s %10s %12s %10s %8s" % ["beta", "saturated", "closable", "one law", "not immune", "band"])

	for beta in SETTLEMENT_CANDIDATES:
		var saturated: float = _hold_stance("FRA", _effective_stance(beta), TERM_MONTHS)
		var one_law: float = _hold_stance("FRA", _effective_stance(beta) * ONE_LAW / K.SETTLEMENT_STANCE_MAX, TERM_MONTHS)
		var closable: bool = saturated < K.UNREST_THRESHOLD_PCT
		var not_immune: bool = one_law >= K.UNREST_THRESHOLD_PCT
		print("%-10.1f %12.2f %10s %12.2f %10s %8s" % [
			beta, saturated, "yes" if closable else "no", one_law,
			"yes" if not_immune else "NO", "PASS" if closable and not_immune else "fail",
		])


## Unrest after `months` of austerity with the stance held. Started from 0.0, so
## "closable" means the stance held it at its own start exactly.
func _hold_stance(nation_id: String, stance: float, months: int) -> float:
	var state = _new_state(nation_id)
	_commit(state, REGIMES["austerity"])
	for i in range(months):
		state.player().settlement_stance = stance
		_step(state, i)
	return float(state.player().unrest_pct)


# --- (f) P5: INEQUALITY_BETA, the kill switch ----------------------------------

## Swept by scaling the SLOPE, table (e)'s trick again. Measured on Germany, whose
## +0.329 pt/yr is the roster's widest rise among the three playable nations.
func _first_act_month(nation_id: String, delta: Dictionary, slope_scale: float) -> int:
	var state = _new_state(nation_id)
	_commit(state, delta)
	state.player().gini_index_per_yr = float(state.player().gini_index_per_yr) * slope_scale
	for i in range(RUN_MONTHS):
		_step(state, i)
		if not state.unrest_acts.is_empty():
			return i + 1
	return -1


func _table_f_inequality() -> void:
	print("\n=== (f) P5 KILL SWITCH: INEQUALITY_BETA, DEU under austerity ===")
	print("band: the measured drift must move the date of the first act. If it cannot at")
	print("any candidate, the constant is DELETED and inequality ships as a readout.")
	var deu = _new_state("DEU")
	print("DEU gini %.2f, slope %+.3f pt/yr, %d-month drift %+.2f" % [
		deu.player().gini_index, deu.player().gini_index_per_yr,
		RUN_MONTHS, deu.player().gini_index_per_yr * float(RUN_MONTHS) / 12.0,
	])
	print("%-10s %14s %14s" % ["beta", "first act", "vs flat gini"])
	var flat := _first_act_month("DEU", REGIMES["austerity"], 0.0)
	for beta in INEQUALITY_CANDIDATES:
		if K.INEQUALITY_BETA <= 0.0:
			break
		var scale: float = beta / K.INEQUALITY_BETA
		var month := _first_act_month("DEU", REGIMES["austerity"], scale)
		print("%-10.2f %14s %14s" % [
			beta, "never" if month < 0 else str(month), "same" if month == flat else "MOVED",
		])
	print("flat-gini reference: %s" % ("never" if flat < 0 else str(flat)))


# --- (g) P6: Loop B, and the measurement this session would most regret omitting --

func _table_g_loop_b() -> void:
	print("\n=== (g) P6: the cabinet loop, austerity, no reshuffle, %d months ===" % RUN_MONTHS)
	print("strike -> approval -> unpopularity -> resignation -> VACANT_EFFECTIVENESS ->")
	print("quality target -> health/pensions satisfaction -> unrest. Nothing closes it")
	print("without a player reshuffle. If unrest_pct SITS ON UNREST_MAX, the model is wrong.")
	var state = _new_state("FRA")
	_commit(state, REGIMES["austerity"])
	var months_at_max := 0
	var peak := 0.0
	for i in range(RUN_MONTHS):
		_step(state, i)
		var u: float = float(state.player().unrest_pct)
		peak = maxf(peak, u)
		if u >= K.UNREST_MAX - 0.0001:
			months_at_max += 1
	var vacant := 0
	for key in state.player().cabinet_effectiveness:
		if float(state.player().cabinet_effectiveness[key]) < 1.0:
			vacant += 1
	print("peak unrest %.2f against UNREST_MAX %.1f; months pinned at the clamp: %d" % [
		peak, K.UNREST_MAX, months_at_max,
	])
	print("acts recorded %d; degraded portfolios at the end %d; unpopularity %.3f" % [
		state.unrest_acts.size(), vacant, Discipline.unpopularity(state.player()),
	])
	print("verdict: %s" % ("MODEL WRONG -- the clamp is setting the number" if months_at_max > 0 else "bounded, the clamp never binds"))


# --- (g2) P7: does the hardship term saturate? ----------------------------------

func _table_h_clamps() -> void:
	print("\n=== (h) P7: does `jobs` saturate where the escalation needs to discriminate? ===")
	print("JOBS_SCALE_PP = %.1f, and _scaled() clamps at -1. The labels read the STOCK, so" % OK.JOBS_SCALE_PP)
	print("what matters is that the STOCK still spans the tiers where the term does not.")
	print("%-14s %10s %10s %10s %10s" % ["regime", "jobs sat", "hardship", "unrest", "label"])
	for name in ["austerity", "spend_zero", "ruinous"]:
		var state = _new_state("FRA")
		_commit(state, REGIMES[name])
		for i in range(RUN_MONTHS):
			_step(state, i)
		var ns = state.player()
		var sat: Dictionary = Opinion.issue_satisfaction(ns)
		print("%-14s %10.3f %10.3f %10.2f %10s" % [
			name, float(sat["jobs"]), Unrest.hardship(sat), float(ns.unrest_pct),
			Unrest.act_label(float(ns.unrest_pct)),
		])

	print("
-- which labels the model can actually produce, real tick, per regime --")
	print("tiers divide %.1f..%.1f evenly over %d labels: a label no budget reaches is" % [
		K.UNREST_THRESHOLD_PCT, K.UNREST_MAX, K.ACT_LABELS.size(),
	])
	print("dead content, which is docs/trade-model.md's `refused_by_partner` failure.")
	var seen := {}
	print("%-14s %10s %16s" % ["regime", "peak", "peak label"])
	var regime_names: Array = REGIMES.keys()
	regime_names.sort()
	for name in regime_names:
		var state = _new_state("FRA")
		_commit(state, REGIMES[name])
		var top := 0.0
		for i in range(RUN_MONTHS):
			_step(state, i)
			top = maxf(top, float(state.player().unrest_pct))
		var label := Unrest.act_label(top)
		if top >= K.UNREST_THRESHOLD_PCT:
			seen[label] = true
		print("%-14s %10.2f %16s" % [name, top, label if top >= K.UNREST_THRESHOLD_PCT else "-"])
	var unreachable: Array = []
	for label in K.ACT_LABELS:
		if not seen.has(label):
			unreachable.append(label)
	print("labels no regime reaches: %s" % ("none" if unreachable.is_empty() else str(unreachable)))

	print("\n=== (h) P8: every clamp, measured slack over %d months ===" % RUN_MONTHS)
	var worst_unrest := 0.0
	var worst_impulse := 0.0
	var worst_stance := 0.0
	for name in REGIMES.keys():
		var state = _new_state("FRA")
		_commit(state, REGIMES[name])
		for i in range(RUN_MONTHS):
			state.player().settlement_stance = -K.SETTLEMENT_STANCE_MAX
			_step(state, i)
			worst_unrest = maxf(worst_unrest, float(state.player().unrest_pct))
			worst_impulse = maxf(worst_impulse, absf(float(state.player().unrest_impulse_pct)))
			worst_stance = maxf(worst_stance, absf(float(state.player().settlement_stance)))
	print("%-28s %10s %10s" % ["quantity", "reached", "clamp"])
	print("%-28s %10.4f %10.4f" % ["unrest_pct", worst_unrest, K.UNREST_MAX])
	print("%-28s %10.4f %10.4f" % ["unrest_impulse_pct", worst_impulse, K.UNREST_IMPULSE_MAX_PCT])
	print("%-28s %10.4f %10.4f" % ["settlement_stance", worst_stance, K.SETTLEMENT_STANCE_MAX])
