extends SceneTree

## V1.6c's headless sweep. Every constant in src/sim/credit_constants.gd is set from a
## table below rather than guessed and defended afterwards.
##
## *** STEP 0 RAN BEFORE ANY BAND WAS WRITTEN, AND IT IS WHY THERE ARE BANDS AT ALL. ***
## V1.6a fitted its amplitude and V1.6b measured three of five constants off the World
## Bank, so this session looked for a sovereign-rate series on the same licence-clean
## loop first. Both candidates were fetched over 1990-2024 for all ten nations:
##
##     FR.INR.RINR       real interest rate      4 of 10 -- CHE 2008-24, GBR 1990-2014,
##                                               ITA 1990-2024, NLD 1999-2013.
##                                               FRA, DEU, ESP, BEL, LUX, AUT: ZERO rows
##     GC.DOD.TOTL.GD.ZS central government debt 7 of 10, but DEU 1 year, ITA 2, LUX 4,
##                                               NLD 5
##
## The windows are disjoint, so there is no cross-section at any date, and FRANCE has
## nothing at all. OECD IRLTLT01 carries it and docs/data-sources.md already rejected the
## IMF WEO on redistribution terms. So the slopes are SWEPT, and that is a checked result
## rather than the reach for a band this project keeps warning itself about.
##
## THE BANDS AND THE TIEBREAKERS ARE BOTH PRE-COMMITTED. Five corrections to that
## discipline are inherited rather than rediscovered. V1.4c: fix the tiebreaker, not only
## the band. V1.5a: a tiebreaker must strictly ORDER the survivors. V1.5b: its answer must
## not MOVE when the grid is widened, because two one-sided bands let the range choose.
## V1.5c: a nearest-to-X tiebreaker is only as good as the grid's RESOLUTION. V1.5d: when
## the model edge is a smooth crossing rather than a plateau, NEITHER edge selects and the
## interior governs. Every row below is marked in advance for which of these it risks.
##
##   (P1) DEBT     YIELD_DEBT_BETA. *** THE BANDS BELOW ARE THE SECOND SET, AND TABLE
##                 (a) IS WHY -- WHICH IS THE PROCESS WORKING RATHER THAN A LAPSE. *** The
##                 first set asked that a debt-widening regime move the yield by 0.25
##                 points over fourteen years and that the service move 0.30 points of GDP
##                 over a term. Table (a) ran first, as this file requires, and showed both
##                 clauses are satisfied by EVERY candidate down to 0.005 -- because a
##                 spendthrift regime does not widen the debt, it SPIRALS: it reaches the
##                 YIELD_MAX clamp and a debt ratio past 1400 % of GDP. A band measured on
##                 a saturated run measures the clamp. Recorded rather than quietly
##                 replaced, because *the reachable path* is the thing five consecutive
##                 sessions have got wrong and this is the sixth.
##                 The reachable path is `hands_off` -- a president who does nothing -- and
##                 it already widens the debt, so no synthetic regime is needed:
##                 (i)   under `hands_off` the debt service moves >= 0.30 points of GDP
##                       over a five-year term. A twentieth of opinion_constants.
##                       DEFICIT_SCALE_PP's six-point span, so `public_finances` can
##                       express it;
##                 (ii)  under `hands_off` over fourteen years it moves <= 3.00 points of
##                       GDP -- HALF of DEFICIT_SCALE_PP, so the bond market cannot on its
##                       own saturate the one issue that prices it. This is the CLOSER, and
##                       it is what (i) needs: (i) alone is a one-sided minimum, which is
##                       V1.5b's failure;
##                 (iii) a WELL-GOVERNED run is not punished: under `managed` the yield
##                       stays within 0.50 points of the anchor over fourteen years;
##                 (iv)  NO RUNAWAY ON A PATH A PLAYER CAN REACH: the peak yield under
##                       `managed_then_spendthrift` stays strictly inside YIELD_MAX.
##                 TIEBREAKER: the response is smooth in the beta, so the model edge is a
##                 crossing rather than a plateau and V1.5d's extension applies -- the
##                 INTERIOR governs, midpoint of the passing interval.
##                 CROSS-CHECK, NOT A SELECTOR: the empirical literature puts a sovereign
##                 spread at 2-5 basis points per point of debt-to-GDP, i.e. 0.02-0.05.
##
##   (P2) DEFICIT  YIELD_DEFICIT_BETA. A deficit two points wider than the player's own
##                 start moves the yield by >= 0.10 points inside a year, so the
##                 TRAJECTORY is visible before the STOCK is -- which is the only thing
##                 that keeps this term from being P1 written twice.
##                 ONE-SIDED MINIMUM, flagged in advance: V1.5b's correction says the
##                 smallest passing candidate ships, and it is applied unless the ratio
##                 tiebreaker below closes the interval first.
##                 TIEBREAKER: the deficit term must not exceed the debt term once the
##                 stock has integrated twelve months of that deficit.
##
##   (P3) UNREST   YIELD_UNREST_BETA. Measured on `hands_off` for P1's reason -- the
##                 reference has to be a path a government survives.
##                 (i)  at the reachable grievance peak tools/unrest_probe.gd measured --
##                      48.74 under `managed_then_austerity` -- the term moves
##                      debt_service_pct_gdp by >= 0.30 points of GDP, P1 (i)'s floor;
##                 (ii) it does NOT exceed the debt term on the same run. A bond market
##                      pricing strikes above solvency is describing something else, and
##                      without (ii) the band is another one-sided minimum.
##                 TIEBREAKER: the interior of the two-sided interval.
##
##   (P4) INFLATE  *** THE CONSTANT THIS SESSION EXPECTS TO DELETE, AND THE PREDICTION IS
##                 WRITTEN HERE BEFORE THE SWEEP RUNS. *** A fourth spread term on
##                 inflation's deviation. docs/inflation-model.md section 7 puts the whole
##                 reachable inflation deviation at 0.145 points, so at any honest slope
##                 this moves the yield under 0.05 and debt service under 0.06 points of
##                 GDP. Same band as P3 (i) and (ii).
##                 *** IT IS NOT ELIGIBLE FOR V1.6b'S STRUCTURAL EXCEPTION. *** That
##                 exception kept INFLATION_OUTPUT_BETA through a failed visibility band
##                 because it is the only thing making the inflation loop negative
##                 feedback. Cutting THIS term breaks no loop and changes no sign, so if
##                 the band fails the constant is DELETED rather than kept --
##                 V1.3e's treatment of AGREEMENT_ACCEPT_MIN. Recorded in advance so the
##                 exception cannot be reached for after the fact.
##                 AND THERE IS A SECOND GROUND THE BAND CANNOT SEE, which is why table
##                 (f) prints both. economy_constants.DEBT_REAL_RATE_PCT is a REAL rate,
##                 and inflation raises a NOMINAL one. A term here is the Fisher effect,
##                 which is precisely the nominal layer docs/inflation-model.md section 1
##                 cut -- so it would smuggle back in through the yield exactly what V1.6b
##                 refused four channels of. What survives in real terms is an inflation
##                 RISK premium, and that is about VOLATILITY rather than level, against
##                 which this model's own realised inflation sd is 0.040 where the measured
##                 series is 1.14 (inflation-model table (e)). The honest answer therefore
##                 does not depend on the band at all, and that is the finding: A BAND CAN
##                 PASS A TERM THE MODEL'S OWN BOUNDARY FORBIDS.
##
##   (P5) PREMIUM  *** KILL SWITCH ***. companies_constants.EQUITY_PREMIUM_PCT, which is
##                 V1.4c's inherited obligation. V1.4c set the dividend yield on price
##                 EXACTLY equal to DEBT_REAL_RATE_PCT so nationalisation was not free on
##                 both axes; V1.6a then refuted the procyclical half, because a dividend
##                 expressed as a share of GDP cancels. A RATE is the one quantity in this
##                 model that is not a share of GDP, so the premium lands as the dividend
##                 yield sitting a fixed distance above an anchor the BORROWING rate now
##                 floats past.
##                 (i)  NOT FREE: some reachable regime drives the spread ABOVE the
##                      premium, so a badly-run player loses on the flow;
##                 (ii) NOT POINTLESS: at `managed` the extra revenue is readable on the
##                      dividend line, >= 0.05 points of GDP at a reachable holding --
##                      docs/companies-model.md table (m)'s own band.
##                 TIEBREAKER: the crossing point -- the spread at which the two rates
##                 meet IS the premium, exactly -- must land INSIDE reachable play rather
##                 than at its edge; among survivors, the one putting it nearest the
##                 middle.
##                 IF NO CANDIDATE PASSES BOTH, the premium is 0.0 and the model says out
##                 loud that there is no channel for one. That is the bullet's own
##                 permitted second answer and it is written down BEFORE the sweep so it
##                 cannot become a rationalisation afterwards.
##
##   (P6) CLAMPS   Not a sweep. YIELD_MIN/YIELD_MAX slack, and the analytic loop gain the
##                 deficit term closes. A clamp nobody has measured is a clamp that might
##                 be setting the model.
##
##   (P7) RATING   Not a sweep. Is every RATING_BANDS row REACHED by some regime? A band
##                 nothing can reach is a decorative row.
##
##   (P8) FLOOR    Not a sweep, and the question the handoff asked out loud: does a yield
##                 reading inflation lift docs/inflation-model.md's channel back over the
##                 GDP-axis floor? Predicted NO, structurally -- debt_service_pct_gdp is
##                 not a player-set line, so Budget.commit() never writes it into
##                 demand_impulse_pct and there is no ninth addend in economy.gd's growth
##                 sum. Measured anyway, on the OPINION path, because that is where the
##                 money actually goes.
##
##   (P9) FIT      Not a sweep. The debt and deficit terms measured for collinearity as a
##                 FIT against an accepted pair, which is V1.6b's discipline: a band edge
##                 moves under widening, a comparison does not.
##
## TABLE (a) RUNS FIRST and nothing is swept until it has been read. Sweeping a price
## against a floor the channel cannot reach is society_probe.gd table (c)'s error, and it
## has now recurred in five consecutive sessions.
##
## AND THE PROBE'S OWN BLIND SPOT IS NAMED RATHER THAN INHERITED. This loop holds no
## election, so a government it runs for fourteen years may be one the electorate would
## have thrown out in 2027 -- which is exactly the error V1.3f made and unrest_probe.gd
## repeated. The response is a regime rather than a disclaimer:
## `managed_then_spendthrift` governs well, survives the first election, and only then
## runs the debt up. The reachable bands are read off THAT row, and the balance re-run's
## own reachability column is the cross-check.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Media = preload("res://src/sim/media.gd")
const Demography = preload("res://src/sim/demography.gd")
const Society = preload("res://src/sim/society.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const CompaniesK = preload("res://src/sim/companies_constants.gd")
const Credit = preload("res://src/sim/credit.gd")
const K = preload("res://src/sim/credit_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")

const START_YEAR := 2026
const RUN_MONTHS := 168  # fourteen years
const TERM_MONTHS := 60

## The switch plus one full term. Past this the electorate has removed a government
## running a spendthrift budget whatever the bond market does, so a yield reached
## after it is a yield reached by nobody -- docs/unrest-model.md's reachability
## finding, applied to a clamp rather than to an act.
const REACHABLE_MONTHS := 84

## balance_probe.gd's own deltas, copied rather than imported because tools/ files do not
## preload each other -- unrest_probe.gd's note, and the same eight rows plus one.
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

## THE REACHABLE debt-widening path, and it is a regime rather than a note because
## unrest_probe.gd's blind spot is this probe's too: a spendthrift budget committed in
## month 1 loses the 2027 election, so a fourteen-year run of it measures a government
## that does not exist. Govern well, win, then spend -- balance_probe.gd's
## `managed_then_austerity` shape, in the other fiscal direction.
const SWITCH_MONTH := 24

## Widened past the empirical range at both ends deliberately, so the cross-check has
## something to be a cross-check ON, and refined at 0.005 through the interesting part --
## V1.5c's resolution finding applied in advance.
const DEBT_CANDIDATES := [
	0.0005, 0.0020, 0.0040, 0.0060, 0.0080,
	0.0085, 0.0090, 0.0095, 0.0100, 0.0105, 0.0110, 0.0115, 0.0120, 0.0125, 0.0130,
	0.0135, 0.0140, 0.0145, 0.0150, 0.0155, 0.0160, 0.0165, 0.0170, 0.0175, 0.0180,
	0.0185, 0.0190, 0.0195, 0.0200, 0.0210,
	0.0300, 0.0600, 0.1200,
]
const DEFICIT_CANDIDATES := [
	0.01, 0.02, 0.03, 0.04, 0.045, 0.05, 0.055, 0.06, 0.07, 0.08, 0.09, 0.10,
	0.11, 0.12, 0.13, 0.14, 0.145, 0.15, 0.16, 0.20, 0.30, 0.50,
]
const UNREST_CANDIDATES := [
	0.0010, 0.0020, 0.0030, 0.0034, 0.0040, 0.0050, 0.0060, 0.0070, 0.0080, 0.0090,
	0.0095, 0.0100, 0.0110, 0.0120, 0.0130, 0.0140, 0.0150, 0.0155, 0.0160, 0.0170,
	0.0200, 0.0300, 0.0500, 0.0800,
]
const INFLATION_CANDIDATES := [0.1, 0.2, 0.3, 0.5, 1.0, 2.0, 4.0]
const PREMIUM_CANDIDATES := [
	0.00, 0.25, 0.50, 0.75, 0.90, 1.00, 1.05, 1.10, 1.20, 1.30, 1.40, 1.50,
	1.75, 2.00, 2.50, 3.00, 4.00, 6.00,
]

## The deficit entry survives here at 0.0 and NOWHERE ELSE: table (d) sweeps a term the
## model does not carry, which is the whole point of that table, so the mirror has to be
## able to express one. src/sim/credit.gd has no such constant.
const SHIPPED := {
	"debt": K.YIELD_DEBT_BETA,
	"deficit": 0.0,
	"unrest": K.YIELD_UNREST_BETA,
	"inflation": 0.0,
}

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	_table_zero_mirror()
	_table_a_reachability()
	_table_b_floor()
	_table_c_debt()
	_table_d_deficit()
	_table_e_unrest()
	_table_f_inflation()
	_table_g_premium()
	_table_h_clamps()
	_table_i_ratings()
	_table_j_fit()

	quit()


# --- (0) the mirror agrees with budget.gd ---------------------------------------

## EVERY SWEEP BELOW RUNS THROUGH A MIRROR OF Budget.tick_month(), because a probe cannot
## change a `const` at runtime and V1.6b's second correction was that a table which
## rescales the shipped output is not independent of the shipped value. The mirror
## recomputes the yield from the same pre-recompute inputs credit.gd reads, then corrects
## the one line the yield enters -- it enters linearly, at exactly one site.
##
## This table is what makes that mirror worth trusting: run it at the SHIPPED betas and it
## must reproduce Budget.tick_month() to 1e-9 over fourteen years. If it disagrees,
## budget.gd is right and this file is wrong -- unrest_probe.gd's rule, made checkable
## rather than stated.
func _table_zero_mirror() -> void:
	print("\n=== (0) the mirror reproduces budget.gd at the shipped values ===")
	var worst := 0.0
	var worst_where := ""
	for name in ["hands_off", "managed", "ruinous"]:
		var real := _run(name, SHIPPED, RUN_MONTHS, false)
		var mirrored := _run(name, SHIPPED, RUN_MONTHS, true)
		for key in ["debt_to_gdp_pct", "deficit_pct_gdp", "debt_service_pct_gdp", "gdp_eur_bn"]:
			var d: float = absf(float(real[key]) - float(mirrored[key]))
			if d > worst:
				worst = d
				worst_where = "%s.%s" % [name, key]
	print("  worst disagreement over 168 months: %.12f  (%s)" % [worst, worst_where])
	print("  %s" % ("PASS -- the sweeps below measure the real model" if worst < 1e-9
		else "*** FAIL -- budget.gd is right and this mirror is wrong ***"))


# --- (a) reachability ------------------------------------------------------------

## RUNS FIRST. What the yield can actually reach, decomposed into its terms, before a
## single band is applied to anything.
func _table_a_reachability() -> void:
	print("\n=== (a) what the yield reaches, at the shipped betas ===")
	print("     REACHABILITY IS NAMED, NOT ASSUMED: this loop holds no election, so a")
	print("     regime marked (*) is one the electorate would have removed in 2027.")
	print("     The bands below are read off `managed_then_spendthrift`, which governs")
	print("     well, survives, and only then runs the debt up.")
	print("%-26s %8s %8s %8s %9s %9s %9s %7s" % [
		"regime", "yield", "peak", "spread", "debt gap", "d service", "unrest", "rating",
	])
	for name in _regime_names():
		var r := _run(name, SHIPPED, RUN_MONTHS, true)
		print("%-26s %8.3f %8.3f %8.3f %9.1f %9.3f %9.2f %7s" % [
			name + (" (*)" if _provocative(name) else ""),
			r["yield_pct"], r["peak_yield"], r["spread_pct"], r["debt_gap"],
			r["service_move"], r["peak_unrest"], r["rating"],
		])


# --- (b) P8: does the yield rescue inflation's GDP-axis floor? --------------------

## Predicted NO before it ran, and the reason is structural rather than numeric:
## debt_service_pct_gdp is not one of the five player-set spending lines, so
## Budget.commit() never writes it into demand_impulse_pct and economy.gd's growth sum
## gains no ninth addend. The yield reaches the BUDGET and never the ECONOMY.
##
## Measured anyway on the opinion path, because that is where the money does go, and
## because "predicted no" is what a session says when it has not looked.
func _table_b_floor() -> void:
	print("\n=== (b) P8: does a yield reading inflation lift V1.6b\'s GDP-axis floor? ===")
	print("     ON `managed`, NOT ON THE WIDENER, and the correction is V1.3f\'s error")
	print("     avoided rather than repeated: under a spiralling budget approval is")
	print("     already pinned, so every candidate would have read a difference of")
	print("     exactly zero and the table would have measured saturation.")
	var base := _run("managed", SHIPPED, RUN_MONTHS, true)
	print("     peak inflation deviation on this path: %+.4f points" % base["peak_inflation_dev"])
	print("%-10s %10s %12s %14s %14s" % [
		"beta", "d yield", "d service", "d GDP %", "d approval",
	])
	for beta in INFLATION_CANDIDATES:
		var betas := SHIPPED.duplicate()
		betas["inflation"] = beta
		var r := _run("managed", betas, RUN_MONTHS, true)
		print("%-10.2f %10.4f %12.4f %14.4f %14.4f" % [
			beta,
			r["yield_pct"] - base["yield_pct"],
			r["debt_service_pct_gdp"] - base["debt_service_pct_gdp"],
			100.0 * (r["gdp_eur_bn"] - base["gdp_eur_bn"]) / base["gdp_eur_bn"],
			r["overall_approval_pct"] - base["overall_approval_pct"],
		])
	print("     d GDP is EXACTLY 0 by construction unless the growth sum gained an addend.")


# --- (c) P1: YIELD_DEBT_BETA -----------------------------------------------------

func _table_c_debt() -> void:
	print("\n=== (c) P1: YIELD_DEBT_BETA ===")
	print("     the SECOND band set -- table (a) refuted the first. See this file\'s header.")
	print("")
	print("     AND EVERY FIGURE HERE IS AGAINST A CONTROL WITH THE DEBT TERM ZEROED,")
	print("     which is the THIRD correction this row needed. The first band set measured")
	print("     a spiralling regime; the second measured `hands_off` and passed at a beta")
	print("     of 0.0005, because a debt ratio walking 110 -> 200 moves the service line")
	print("     by 1.8 points at the ANCHOR RATE with no channel at all. A band on a raw")
	print("     move measures the model that was already there. This is the same control")
	print("     tests/test_trade.gd needed at V1.6a, one session later.")
	print("")
	print("     (i) `hands_off`: the DEBT TERM moves service >= 0.30 points of GDP over a")
	print("         5-year term")
	print("     (ii) it moves it <= 3.00 over 14y   <- the closer")
	print("     (iii) `managed` stays within 0.50 of the anchor over 14y")
	print("     (iv) `managed_then_spendthrift` peak yield stays inside YIELD_MAX over the")
	print("          REACHABLE horizon -- 84 months, the switch plus one full term, after")
	print("          which the electorate has removed this government whatever it does")
	print("%-8s %10s %10s %10s %10s %5s %5s %5s %5s %5s" % [
		"beta", "svc 5y", "svc 14y", "managed", "peak wide",
		"(i)", "(ii)", "(iii)", "(iv)", "pass",
	])
	var zero := SHIPPED.duplicate()
	zero["debt"] = 0.0
	var control_term := _run("hands_off", zero, TERM_MONTHS, true)
	var control_long := _run("hands_off", zero, RUN_MONTHS, true)
	var passing: Array = []
	for beta in DEBT_CANDIDATES:
		var betas := SHIPPED.duplicate()
		betas["debt"] = beta
		var term := _run("hands_off", betas, TERM_MONTHS, true)
		var long := _run("hands_off", betas, RUN_MONTHS, true)
		var good := _run("managed", betas, RUN_MONTHS, true)
		var wide := _run("managed_then_spendthrift", betas, REACHABLE_MONTHS, true)
		var svc5: float = float(term["service_move"]) - float(control_term["service_move"])
		var svc14: float = float(long["service_move"]) - float(control_long["service_move"])
		var managed_move: float = absf(float(good["yield_pct"]) - C.DEBT_REAL_RATE_PCT)
		var peak_wide: float = float(wide["peak_yield"])
		var i_ok: bool = absf(svc5) >= 0.30
		var ii_ok: bool = absf(svc14) <= 3.00
		var iii_ok: bool = managed_move <= 0.50
		var iv_ok: bool = peak_wide < K.YIELD_MAX
		var ok: bool = i_ok and ii_ok and iii_ok and iv_ok
		if ok:
			passing.append(beta)
		print("%-8.4f %10.3f %10.3f %10.3f %10.3f %5s %5s %5s %5s %5s" % [
			beta, svc5, svc14, managed_move, peak_wide,
			_yn(i_ok), _yn(ii_ok), _yn(iii_ok), _yn(iv_ok), _yn(ok),
		])
	_report_interval(passing, "YIELD_DEBT_BETA", "midpoint of the interval (V1.5d: a smooth crossing, so neither edge selects)")
	print("     cross-check, NOT a selector: the empirical range is 0.02-0.05.")


# --- (d) P2: YIELD_DEFICIT_BETA --------------------------------------------------

## Isolated rather than run through a regime, and the isolation is what makes the band
## mean what it says: the claim is about the TRAJECTORY being visible before the STOCK,
## so the debt gap is held at zero and only the deficit moves.
func _table_d_deficit() -> void:
	print("\n=== (d) P2: YIELD_DEFICIT_BETA ===")
	print("     THREE CLAUSES, AND THE FIRST TWO ARE ARITHMETIC RATHER THAN MEASUREMENT --")
	print("     said out loud because a table of inequalities dressed as a sweep is the")
	print("     bound-not-a-selector failure V1.5a recorded. Clause (iii) is the measured")
	print("     one and it uses table (c)\'s control: the DEFICIT TERM zeroed, so what is")
	print("     read is this channel and not the debt stock it rides on.")
	print("     (i)  a deficit 2.0 points wider moves the yield >= 0.10 inside a year")
	print("     (ii) the term stays under the debt term after twelve months of that")
	print("          same deficit, which is what stops the derivative outweighing the level")
	print("     (iii) under `hands_off` the deficit term moves debt service by >= 0.30")
	print("          points of GDP over a five-year term -- P1 (i)\'s floor")
	print("%-8s %12s %12s %12s %6s %6s %6s %6s" % [
		"beta", "from defc", "vs debt", "svc 5y", "(i)", "(ii)", "(iii)", "pass",
	])
	# SHIPPED already carries no deficit term, so the control is the shipped model --
	# which is what makes svc5 below this candidate term's own contribution and nothing
	# else. Written as a duplicate anyway so the isolation is visible rather than implied.
	var zero := SHIPPED.duplicate()
	zero["deficit"] = 0.0
	var control := _run("hands_off", zero, TERM_MONTHS, true)
	var ceiling: float = K.YIELD_DEBT_BETA * 2.0 * 12.0
	var passing: Array = []
	for beta in DEFICIT_CANDIDATES:
		var betas := SHIPPED.duplicate()
		betas["deficit"] = beta
		var term := _run("hands_off", betas, TERM_MONTHS, true)
		var from_deficit: float = beta * 2.0
		var svc5: float = float(term["service_move"]) - float(control["service_move"])
		var i_ok: bool = from_deficit >= 0.10
		var ii_ok: bool = from_deficit <= ceiling
		var iii_ok: bool = absf(svc5) >= 0.30
		var ok: bool = i_ok and ii_ok and iii_ok
		if ok:
			passing.append(beta)
		print("%-8.3f %12.4f %12.4f %12.4f %6s %6s %6s %6s" % [
			beta, from_deficit, ceiling, svc5, _yn(i_ok), _yn(ii_ok), _yn(iii_ok), _yn(ok),
		])
	if passing.is_empty():
		print("")
		print("     *** ZERO CANDIDATES PASS, AND THAT IS THE ROW\'S ANSWER RATHER THAN A")
		print("     FAILED SWEEP. *** The three clauses are mutually inconsistent: (iii)")
		print("     needs a slope above 0.20 and (ii) refuses anything above 0.145. Wherever")
		print("     the deficit term is legible it outweighs the level it exists to lead,")
		print("     and wherever it does not it is under the floor. So the row DOES name one")
		print("     quantity twice, confirmed by measurement rather than by argument.")
		print("     DELETED, not left at zero -- V1.3e\'s AGREEMENT_ACCEPT_MIN -- and not")
		print("     eligible for V1.6b\'s structural exception, because cutting it breaks no")
		print("     loop. It takes this session\'s only positive feedback with it.")
	else:
		_report_interval(passing, "YIELD_DEFICIT_BETA", "interior of the interval -- the ratio clause closes it, so V1.5d governs")


# --- (e) P3: YIELD_UNREST_BETA ---------------------------------------------------

func _table_e_unrest() -> void:
	print("\n=== (e) P3: YIELD_UNREST_BETA ===")
	print("     reference run is `hands_off`, for P1\'s reason: a band measured on a")
	print("     spiralling regime is measured against a debt term of forty points")
	print("     (i) at unrest_probe\'s reachable peak 48.74 the term moves >= 0.30")
	print("         points of GDP of debt service;  (ii) it stays under the debt term")
	print("%-8s %12s %12s %12s %6s %6s %6s" % [
		"beta", "yield term", "service", "debt term", "(i)", "(ii)", "pass",
	])
	var peak := 48.74
	var passing: Array = []
	var ref := _run("hands_off", SHIPPED, RUN_MONTHS, true)
	var ratio: float = float(ref["debt_to_gdp_pct"]) / 100.0
	var debt_term: float = K.YIELD_DEBT_BETA * float(ref["debt_gap"])
	print("     `hands_off` ends at %.1f %% of GDP with a debt term of %.3f points" % [
		float(ref["debt_to_gdp_pct"]), debt_term,
	])
	for beta in UNREST_CANDIDATES:
		var term: float = beta * peak
		var service: float = term * ratio
		var i_ok: bool = service >= 0.30
		var ii_ok: bool = term <= debt_term
		var ok: bool = i_ok and ii_ok
		if ok:
			passing.append(beta)
		print("%-8.3f %12.4f %12.4f %12.4f %6s %6s %6s" % [
			beta, term, service, debt_term, _yn(i_ok), _yn(ii_ok), _yn(ok),
		])
	_report_interval(passing, "YIELD_UNREST_BETA", "interior of the two-sided interval")
	# BOTH CLAUSES ARE CLOSED FORM given the two measured inputs, so the crossings are
	# printed rather than bracketed by whatever the grid happened to contain. That is
	# V1.5c's resolution finding taken to its conclusion: if the edge can be solved, a
	# grid is a worse answer than the solution.
	var exact_lo: float = 0.30 / (peak * ratio)
	var exact_hi: float = debt_term / peak
	print("     exact crossings [%.5f, %.5f], midpoint %.5f" % [
		exact_lo, exact_hi, 0.5 * (exact_lo + exact_hi),
	])


# --- (f) P4: the constant this session expects to delete --------------------------

func _table_f_inflation() -> void:
	print("\n=== (f) P4: YIELD_INFLATION_BETA -- expected to FAIL and be DELETED ===")
	print("     P3\'s band, on `hands_off`, at the PEAK reachable inflation deviation")
	var base := _run("hands_off", SHIPPED, RUN_MONTHS, true)
	var dev: float = float(base["peak_inflation_dev"])
	var ratio: float = float(base["debt_to_gdp_pct"]) / 100.0
	var debt_term: float = K.YIELD_DEBT_BETA * float(base["debt_gap"])
	print("     peak reachable inflation deviation: %+.4f points" % dev)
	print("%-8s %12s %12s %12s %6s %6s %6s" % [
		"beta", "yield term", "service", "debt term", "(i)", "(ii)", "pass",
	])
	var passing: Array = []
	for beta in INFLATION_CANDIDATES:
		var term: float = beta * absf(dev)
		var service: float = term * ratio
		var i_ok: bool = service >= 0.30
		var ii_ok: bool = term <= debt_term
		var ok: bool = i_ok and ii_ok
		if ok:
			passing.append(beta)
		print("%-8.2f %12.4f %12.4f %12.4f %6s %6s %6s" % [
			beta, term, service, debt_term, _yn(i_ok), _yn(ii_ok), _yn(ok),
		])
	if passing.is_empty():
		print("     ZERO candidates pass the band.")
	else:
		print("     %d candidates pass the band, from %.2f up." % [passing.size(), float(passing[0])])
	print("")
	print("     *** DELETED ANYWAY, AND THE BAND IS NOT WHAT DECIDES. ***")
	print("     DEBT_REAL_RATE_PCT is a REAL rate and inflation raises a NOMINAL one, so")
	print("     a term here is the Fisher effect -- the nominal layer docs/inflation-")
	print("     model.md section 1 cut, smuggled back in through the yield. What survives")
	print("     in real terms is an inflation RISK premium, which is about VOLATILITY:")
	print("     this model\'s realised inflation sd is 0.040 against a measured 1.14.")
	print("     A BAND CAN PASS A TERM THE MODEL\'S OWN BOUNDARY FORBIDS, and that is the")
	print("     finding rather than the sweep result. V1.6b\'s structural exception is")
	print("     refused in advance in this file\'s header and is not reached for here.")


# --- (g) P5: the equity premium, and the kill switch ------------------------------

## THE CROSSING IS EXACT RATHER THAN SIMULATED, and that is worth saying because it looks
## like a shortcut. The state gains on the flow while the dividend yield on price exceeds
## the borrowing rate; the dividend yield on price is DEBT_REAL_RATE_PCT +
## EQUITY_PREMIUM_PCT by construction and the borrowing rate is DEBT_REAL_RATE_PCT +
## spread. So the two meet exactly where `spread == EQUITY_PREMIUM_PCT`, with no
## nationalisation to simulate. What DOES need measuring is the size of the reachable
## dividend line, so band (ii) is about a real holding rather than an assumed one.
func _table_g_premium() -> void:
	print("\n=== (g) P5 KILL SWITCH: companies_constants.EQUITY_PREMIUM_PCT ===")
	print("     V1.4c\'s inherited obligation. The crossing is where spread == premium,")
	print("     exactly and with no nationalisation to simulate: the dividend yield on")
	print("     price is DEBT_REAL_RATE_PCT + premium by construction and the borrowing")
	print("     rate is DEBT_REAL_RATE_PCT + spread.")
	print("")
	print("     *** CLAUSE (i) IS TIGHTENED FROM WHAT THIS FILE PRE-COMMITTED, AND THE")
	print("     REASON IS RECORDED RATHER THAN THE CHANGE HIDDEN. *** It read *some")
	print("     reachable regime drives the spread above the premium*, and the only regime")
	print("     that does at a high premium is `managed_then_spendthrift`, which survives")
	print("     exactly one term. A clause satisfied by the most extreme row in the set is")
	print("     a bound and not a selector -- V1.5a\'s CORRUPTION_DELIVERY_BETA failure. It")
	print("     now names `hands_off`, the most reachable path there is, and the claim it")
	print("     makes is the one worth making: DOING NOTHING FOR LONG ENOUGH TURNS A")
	print("     NATIONALISATION INTO A LOSS.")

	var holding := _reachable_holding()
	print("")
	print("     reachable holding: %s at state_share 1.0 pays %.4f points of GDP" % [
		holding["name"], holding["line_pct_gdp"],
	])

	var reach := {}
	for name in _regime_names():
		if _provocative(name):
			continue
		reach[name] = float(_run(name, SHIPPED, RUN_MONTHS, true)["peak_yield"]) - C.DEBT_REAL_RATE_PCT
	var names: Array = reach.keys()
	names.sort()
	print("     peak spread reached, reachable regimes only:")
	for name in names:
		print("       %-28s %+.4f" % [name, float(reach[name])])

	var hands_off_peak: float = float(reach.get("hands_off", 0.0))
	print("")
	print("%-8s %14s %14s %6s %6s %6s" % [
		"premium", "extra revenue", "hands_off pk", "(i)", "(ii)", "pass",
	])
	var passing: Array = []
	for premium in PREMIUM_CANDIDATES:
		var extra: float = float(holding["line_pct_gdp"]) * premium / C.DEBT_REAL_RATE_PCT
		var i_ok: bool = hands_off_peak > premium
		var ii_ok: bool = extra >= 0.05
		var ok: bool = i_ok and ii_ok
		if ok:
			passing.append(premium)
		print("%-8.2f %14.4f %14.4f %6s %6s %6s" % [
			premium, extra, hands_off_peak, _yn(i_ok), _yn(ii_ok), _yn(ok),
		])
	if passing.is_empty():
		print("     *** KILL SWITCH FIRES. *** No candidate is both non-free and")
		print("     non-pointless, so EQUITY_PREMIUM_PCT is 0.0 and the model records that")
		print("     there is no channel for an equity premium. Written before the sweep.")
	else:
		_report_interval(passing, "EQUITY_PREMIUM_PCT", "interior of the interval: (i) and (ii) close it from opposite sides")
		# Closed form for the same reason table (e) prints one.
		var exact_lo: float = 0.05 * C.DEBT_REAL_RATE_PCT / float(holding["line_pct_gdp"])
		print("     exact crossings [%.5f, %.5f], midpoint %.5f" % [
			exact_lo, hands_off_peak, 0.5 * (exact_lo + hands_off_peak),
		])


# --- (h) P6: clamps and the loop gain --------------------------------------------

func _table_h_clamps() -> void:
	print("\n=== (h) P6: guard-rail slack, and the loop the lag closes ===")
	print("     REACHABLE regimes only for the verdict, with the rest printed beneath:")
	print("     a spiralling budget the electorate removes in 2027 sitting on a clamp is")
	print("     not the clamp setting the model, it is a country that has defaulted.")
	var worst_hi := -INF
	var worst_lo := INF
	var where_hi := ""
	var where_lo := ""
	var unreachable: Array = []
	for name in _regime_names():
		var r := _run(name, SHIPPED, RUN_MONTHS, true)
		# PEAK and TROUGH over the whole run rather than the end value, which is the
		# correction table (a) forced here too: a regime that spikes and comes back looks
		# slack at month 168 and sat on the clamp for a decade.
		var hi: float = float(r["peak_yield"])
		var lo: float = float(r["trough_yield"])
		if _provocative(name):
			unreachable.append("%s %.2f..%.2f" % [name, lo, hi])
			continue
		if hi > worst_hi:
			worst_hi = hi
			where_hi = name
		if lo < worst_lo:
			worst_lo = lo
			where_lo = name
	print("  highest unclamped yield, reachable: %.3f (%s) against YIELD_MAX %.1f" % [
		worst_hi, where_hi, K.YIELD_MAX,
	])
	print("  lowest  unclamped yield, reachable: %.3f (%s) against YIELD_MIN %.1f" % [
		worst_lo, where_lo, K.YIELD_MIN,
	])
	print("  %s" % ("both SLACK -- the model sets the number, not the clamp"
		if worst_hi < K.YIELD_MAX and worst_lo > K.YIELD_MIN
		else "*** a reachable run sits ON a clamp: the clamp is setting the model ***"))
	print("  unreachable, for the record: %s" % ", ".join(PackedStringArray(unreachable)))
	print("")
	print("  ONE loop, because table (d) deleted the other one. The deficit term would")
	print("  have closed inside a month -- debt service is INSIDE the deficit -- and it is")
	print("  gone. What is left closes over a year through the stock, which")
	print("  Budget.tick_month() advances only after Budget.recompute() has read it:")
	for ratio in [110.0, 180.0, 250.0]:
		print("    at %6.0f%% of GDP: debt gain %.4f per year against 1.0" % [
			ratio, K.YIELD_DEBT_BETA * ratio / 100.0,
		])
	print("  Both are bounded by the ratio, so the loop is stable while the debt is:")
	print("  it is explosive only above debt = 100 / beta, which is %.0f %% of GDP for" % (100.0 / K.YIELD_DEBT_BETA))
	print("  the debt term. Reachable play does not go there; a spiral is a real thing")
	print("  and the model is allowed to contain one at the far end of an unreachable run.")


# --- (i) P7: are the rating bands reachable? --------------------------------------

func _table_i_ratings() -> void:
	print("\n=== (i) P7: is every RATING_BANDS row reached by some regime? ===")
	print("     EVERY MONTH of every regime, not two sampled horizons. The first version")
	print("     read month 60 and month 168 and reported `AA` unreached, when what it had")
	print("     found was that no regime happens to END there -- a rating a run passes")
	print("     through is a rating the player sees.")
	var seen := {}
	for name in _regime_names():
		var visited: Dictionary = _ratings_visited(name)
		for label in visited.keys():
			if not seen.has(label):
				seen[label] = "%s @%sm" % [name, visited[label]]
	for band in K.RATING_BANDS:
		var label := String(band[1])
		print("  %-5s ceiling %6s  %s" % [
			label,
			"inf" if is_inf(float(band[0])) else "%.2f" % float(band[0]),
			seen.get(label, "*** NOT REACHED -- decorative row ***"),
		])


# --- (j) P9: the debt and deficit terms as a fit ----------------------------------

## V1.6b's discipline: measured against a pair the model has ALREADY accepted as distinct
## rather than against a band, because a band edge moves under widening and a comparison
## does not. If these two are more collinear than `jobs` and `growth`, the row's two
## inputs are one input and the model says so.
func _table_j_fit() -> void:
	print("\n=== (j) P9: are the debt and the deficit one quantity written twice? ===")
	print("     ON THE RAW GAPS, not on the terms: table (d) deleted the deficit beta, so")
	print("     a correlation of the weighted terms would be a correlation with zero. The")
	print("     question was always about the INPUTS, and a correlation is scale-free.")
	var debts: Array = []
	var deficits: Array = []
	for name in _regime_names():
		_run(name, SHIPPED, RUN_MONTHS, true, debts, deficits)
	var c: float = _corr(debts, deficits)
	print("  corr(debt gap, deficit gap) over every month of every regime: %.4f" % c)
	print("  accepted standard, docs/inflation-model.md section 6:")
	print("    |corr(sat.jobs, sat.growth)| = 0.3185, already carried as distinct")
	print("  %s" % ("DISTINCT by the model's own standard -- the deletion in table (d) is"
		+ " about LEGIBILITY and not about collinearity" if absf(c) <= 0.3185
		else "MORE collinear than an accepted pair, which corroborates table (d)"))


# --- the mirror ------------------------------------------------------------------

## main.gd's chain, with Budget.tick_month() replaced by a mirror that takes the candidate
## betas. `use_mirror` false runs the real thing, which is what table (0) compares against.
##
## The duplication is deliberate and bounded: it is the only way to sweep a constant
## Budget.recompute() reads directly, and unrest_probe.gd's _run_with_impulse() and
## demography_probe.gd's input scaling exist for the same reason. If it ever disagrees with
## budget.gd, budget.gd is right.
func _run(
	regime: String, betas: Dictionary, months: int, use_mirror: bool,
	out_debt_terms: Array = [], out_deficit_terms: Array = []
) -> Dictionary:
	var state = GameState.new_game(_loader, "FRA")
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()
	var start_service: float = float(ns.debt_service_pct_gdp)

	var switched := false
	if regime == "managed_then_spendthrift":
		_commit(state, REGIMES["managed"])
	else:
		_commit(state, REGIMES[regime])

	var peak_unrest := 0.0
	var peak_yield := -INF
	var trough_yield := INF
	var peak_inflation_dev := 0.0
	for i in range(months):
		var month: int = (i + 1) % 12 + 1
		state.year = START_YEAR + int((i + 1) / 12)
		state.month = month

		if regime == "managed_then_spendthrift" and not switched and i + 1 == SWITCH_MONTH:
			_commit(state, REGIMES["spendthrift"])
			switched = true

		Economy.tick_month(state)
		if use_mirror:
			_budget_tick_with(state, ns, betas, out_debt_terms, out_deficit_terms)
		else:
			Budget.tick_month(state)
		Bloc.tick_month(state, _loader)
		Inflation.tick_month(state)
		Media.tick_month(state, _loader)
		Opinion.tick_month(state)
		Defence.tick_month(state)
		Companies.tick_month(state, _loader)
		Demography.tick_month(state)
		Society.tick_month(state)
		Unrest.tick_month(state)
		peak_unrest = maxf(peak_unrest, float(ns.unrest_pct))
		Cabinet.tick_month(state, _loader)
		var y_now := _yield_with(ns, betas)
		peak_yield = maxf(peak_yield, y_now)
		trough_yield = minf(trough_yield, y_now)
		if absf(Inflation.inflation_deviation(ns)) > absf(peak_inflation_dev):
			peak_inflation_dev = Inflation.inflation_deviation(ns)

	return {
		"yield_pct": _yield_with(ns, betas),
		"spread_pct": _spread_with(ns, betas),
		"rating": _rating_of(_yield_with(ns, betas)),
		"debt_gap": ns.debt_to_gdp_pct() - ns.start_debt_to_gdp_pct,
		"deficit_gap": ns.deficit_pct_gdp - ns.start_deficit_pct_gdp,
		"debt_to_gdp_pct": ns.debt_to_gdp_pct(),
		"deficit_pct_gdp": ns.deficit_pct_gdp,
		"debt_service_pct_gdp": ns.debt_service_pct_gdp,
		"start_service": start_service,
		"gdp_eur_bn": ns.gdp_eur_bn,
		"overall_approval_pct": ns.overall_approval_pct,
		"inflation_dev": Inflation.inflation_deviation(ns),
		"peak_inflation_dev": peak_inflation_dev,
		"peak_yield": peak_yield,
		"trough_yield": trough_yield,
		"service_move": ns.debt_service_pct_gdp - start_service,
		"peak_unrest": peak_unrest,
	}


## Budget.tick_month() with the candidate betas. The yield enters Budget.recompute() at
## exactly one site and LINEARLY, so correcting that one line after the fact reproduces
## what recompute() would have written -- which is what makes this exact rather than
## approximate. The pre-recompute read of deficit_pct_gdp is deliberate and is the whole
## of the one-month lag: recompute() reads the same stale figure a few lines later.
func _budget_tick_with(
	state, ns, betas: Dictionary, out_debt_terms: Array, out_deficit_terms: Array
) -> void:
	# The RAW gaps, for table (j): a correlation is scale-free, and after table (d) the
	# deficit beta is zero, so weighted terms would correlate a series with a constant.
	out_debt_terms.append(ns.debt_to_gdp_pct() - ns.start_debt_to_gdp_pct)
	out_deficit_terms.append(ns.deficit_pct_gdp - ns.start_deficit_pct_gdp)

	var y := _yield_with(ns, betas)
	Budget.recompute(state, ns)
	if ns.gdp_eur_bn > 0.0:
		var candidate: float = y * ns.debt_eur_bn / ns.gdp_eur_bn
		var d: float = candidate - ns.debt_service_pct_gdp
		ns.debt_service_pct_gdp = candidate
		ns.total_spending_pct_gdp += d
		ns.deficit_pct_gdp += d
	ns.debt_eur_bn += ns.deficit_pct_gdp / 100.0 * ns.gdp_eur_bn / 12.0


func _spread_with(ns, betas: Dictionary) -> float:
	return (
		float(betas["debt"]) * (ns.debt_to_gdp_pct() - ns.start_debt_to_gdp_pct)
		+ float(betas["deficit"]) * (ns.deficit_pct_gdp - ns.start_deficit_pct_gdp)
		+ float(betas["unrest"]) * float(ns.unrest_pct)
		+ float(betas.get("inflation", 0.0)) * Inflation.inflation_deviation(ns)
	)


func _yield_with(ns, betas: Dictionary) -> float:
	return clampf(C.DEBT_REAL_RATE_PCT + _spread_with(ns, betas), K.YIELD_MIN, K.YIELD_MAX)


func _rating_of(y: float) -> String:
	for band in K.RATING_BANDS:
		if y <= float(band[0]):
			return String(band[1])
	return String(K.RATING_BANDS[K.RATING_BANDS.size() - 1][1])


# --- helpers ---------------------------------------------------------------------

## Every rating a regime passes through, mapped to the first month it appeared. A second
## loop rather than a field on _run()'s return, because this is the only table that wants
## it and threading a per-month record through every other caller would cost more than it
## saves.
func _ratings_visited(regime: String) -> Dictionary:
	var state = GameState.new_game(_loader, "FRA")
	state.year = START_YEAR
	state.month = 1
	var ns = state.player()
	var switched := false
	_commit(state, REGIMES["managed"] if regime == "managed_then_spendthrift" else REGIMES[regime])
	var out := {}
	for i in range(RUN_MONTHS):
		state.year = START_YEAR + int((i + 1) / 12)
		state.month = (i + 1) % 12 + 1
		if regime == "managed_then_spendthrift" and not switched and i + 1 == SWITCH_MONTH:
			_commit(state, REGIMES["spendthrift"])
			switched = true
		Economy.tick_month(state)
		Budget.tick_month(state)
		Bloc.tick_month(state, _loader)
		Inflation.tick_month(state)
		Media.tick_month(state, _loader)
		Opinion.tick_month(state)
		Defence.tick_month(state)
		Companies.tick_month(state, _loader)
		Demography.tick_month(state)
		Society.tick_month(state)
		Unrest.tick_month(state)
		Cabinet.tick_month(state, _loader)
		var label := Credit.rating(ns)
		if not out.has(label):
			out[label] = i + 1
	return out


func _regime_names() -> Array:
	var names: Array = REGIMES.keys()
	names.sort()
	names.append("managed_then_spendthrift")
	return names


## The regimes docs/unrest-model.md's own reachability finding marks: a budget this
## provocative committed in month 1 loses the 2027 election, so a fourteen-year run of it
## measures a government that does not exist.
func _provocative(name: String) -> bool:
	return name in ["ruinous", "spendthrift", "spend_zero", "tax_max", "austerity"]


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


## The largest firm France actually has, taken into full public ownership, so band (ii)
## is measured against a holding that exists rather than an assumed one.
func _reachable_holding() -> Dictionary:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var firms: Array = Companies.firms_of(_loader, "FRA")
	if firms.is_empty():
		return {"name": "(none)", "line_pct_gdp": 0.0}
	var best = firms[0]
	var best_out := 0.0
	for company in firms:
		var out: float = Companies.output_eur_bn(ns, company)
		if out > best_out:
			best_out = out
			best = company
	ns.companies[best.id]["state_share"] = 1.0
	# RESCALED BACK TO THE ANCHOR, and that is V1.6b's independence lesson rather than a
	# flourish: this table CHOOSES EQUITY_PREMIUM_PCT, and DIVIDEND_YIELD is derived from
	# it, so reading the live line would make the passing interval move every time the
	# shipped constant moved. The line is exactly linear in DIVIDEND_YIELD, so dividing
	# out the shipped yield-on-price and multiplying by the anchor is exact.
	var live: float = Companies.dividend_revenue_pct_gdp(ns, _loader)
	var shipped_on_price: float = CompaniesK.DIVIDEND_YIELD / CompaniesK.PRICE_TO_OUTPUT * 100.0
	return {
		"name": best.company_name,
		"line_pct_gdp": live * C.DEBT_REAL_RATE_PCT / shipped_on_price,
	}


func _report_interval(passing: Array, label: String, rule: String) -> void:
	if passing.is_empty():
		print("     NO candidate passes -- %s cannot be set by this band." % label)
		return
	var lo: float = float(passing[0])
	var hi: float = float(passing[passing.size() - 1])
	print("     passing interval [%.4f, %.4f], %d rows" % [lo, hi, passing.size()])
	print("     tiebreaker: %s" % rule)
	if passing.size() > 1 and (lo == float(_grid_lo(label)) or hi == float(_grid_hi(label))):
		print("     *** an endpoint of the SWEPT RANGE passes: V1.5b's diagnostic says")
		print("         that is a suspect, not a result. Widen and re-run. ***")


func _grid_lo(label: String) -> float:
	match label:
		"YIELD_DEBT_BETA": return float(DEBT_CANDIDATES[0])
		"YIELD_DEFICIT_BETA": return float(DEFICIT_CANDIDATES[0])
		"YIELD_UNREST_BETA": return float(UNREST_CANDIDATES[0])
		"EQUITY_PREMIUM_PCT": return float(PREMIUM_CANDIDATES[0])
	return NAN


func _grid_hi(label: String) -> float:
	match label:
		"YIELD_DEBT_BETA": return float(DEBT_CANDIDATES[DEBT_CANDIDATES.size() - 1])
		"YIELD_DEFICIT_BETA": return float(DEFICIT_CANDIDATES[DEFICIT_CANDIDATES.size() - 1])
		"YIELD_UNREST_BETA": return float(UNREST_CANDIDATES[UNREST_CANDIDATES.size() - 1])
		"EQUITY_PREMIUM_PCT": return float(PREMIUM_CANDIDATES[PREMIUM_CANDIDATES.size() - 1])
	return NAN


func _corr(a: Array, b: Array) -> float:
	var n: int = mini(a.size(), b.size())
	if n < 2:
		return NAN
	var ma := 0.0
	var mb := 0.0
	for i in range(n):
		ma += float(a[i])
		mb += float(b[i])
	ma /= n
	mb /= n
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in range(n):
		var da: float = float(a[i]) - ma
		var db: float = float(b[i]) - mb
		sab += da * db
		saa += da * da
		sbb += db * db
	if saa <= 0.0 or sbb <= 0.0:
		return NAN
	return sab / sqrt(saa * sbb)


func _yn(ok: bool) -> String:
	return "yes" if ok else "no"
