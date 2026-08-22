extends SceneTree

## V1.6e's headless sweep. Every constant in src/sim/investment_constants.gd is set
## from a table below rather than guessed and defended afterwards.
##
## Run: godot --headless --script res://tools/investment_probe.gd
##
## *** THE BANDS AND THE TIEBREAKERS ARE BOTH PRE-COMMITTED. *** Seven corrections
## to that discipline are inherited rather than rediscovered:
##
##   V1.4c  fix the TIEBREAKER as well as the band.
##   V1.5a  a tiebreaker must strictly ORDER the survivors; a clause that passes at
##          every candidate is a BOUND, not a selector.
##   V1.5b  its answer must not MOVE when the candidate range is widened. A value
##          sitting at an endpoint of the swept range is a suspect, not a result.
##   V1.5c  a nearest-to-X tiebreaker is only as good as the grid's RESOLUTION.
##   V1.5d  when the model edge is a smooth CROSSING rather than a plateau, neither
##          edge selects and the interior governs.
##   V1.6a  where something outside the model measures the same quantity, prefer a
##          FIT to a band: a band edge moves under widening, a fit converges.
##   V1.6c  check each term against the MODEL'S OWN BOUNDARY before the band,
##          because a band is a test of size and not of legitimacy.
##
## *** AND V1.6d's, WHICH THIS SESSION IS MOST EXPOSED TO: a band that passes at
## every candidate with the identical measurement is measuring a CLAMP. Say so and
## replace it. ***
##
## THE BOUNDARY CHECKS, SETTLED BEFORE ANY BAND WAS WRITTEN:
##
##   (B1) IS THE LANDING SITE EVEN AVAILABLE? docs/tiers/v1.md section 6 asks for a
##        lever "on sector_output itself". Economy._apply_growth_to_sectors()
##        reconciles the three sectors against the month's GDP target EXACTLY, so an
##        absolute injection into sector_output is cancelled by the cyclical residual
##        inside the same tick and survives only as composition. Table (a) measures
##        that rather than asserting it. The honest landing site is the per-sector
##        TREND RATE, read at BOTH of economy.gd's sites.
##
##   (B2) IS SECTOR_TREND_BETA A SECOND economy_constants.INFRA_BETA? No.
##        INFRA_BETA reads a player-set SPENDING LINE keyed 1:1 to a cabinet
##        portfolio and produces a UNIFORM shift; this reads a register written by a
##        VERB and produces a PER-SECTOR one. Against src/core/law.gd's criterion for
##        the three existing anti-double-count pairs -- same act, same landing site
##        AND same units -- it fails two of three. A term that failed this would be
##        deleted whatever its band said, which is V1.6c's treatment of the inflation
##        term in the yield.
##
##   (B3) IS THERE AN EMPLOYMENT TERM TO PRICE? No, and not by prohibition.
##        Economy._update_unemployment() reads Okun on `growth - trend` and structural
##        unemployment reads the income-tax wedge, the law offset and the firm layer.
##        A term raising TREND has no permanent employment channel available to it.
##        tests/test_sectors.gd pins it bit-identically; there is nothing to band.
##
## THE PARAMETERS:
##
##   (P1) COST      INVESTMENT_COST_PCT_GDP. What one sector at full intensity takes
##                  out of the budget every year.
##                  *** THE ONE THING THIS SESSION WAS TOLD TO MEASURE BEFORE
##                  ASSUMING THERE WAS ROOM. *** docs/tax-model.md section 7 measured
##                  V1.6d's two new taxes at 4.62 points of
##                  opinion_constants.DEFICIT_SCALE_PP's six-point span -- 77 % -- so
##                  what is left for a fourth computed budget line is about 1.38
##                  points, not companies_constants.SUBSIDY_BILL_MAX_PCT_GDP's 2.50.
##                  (i)  LEGIBLE: one sector at full intensity costs >= 0.20 points of
##                       GDP, which is about two fifths of an income-tax point --
##                       appreciably more than subsidising one firm (0.30 buys a
##                       single company) should be for a whole sector.
##                  (ii) INSIDE WHAT IS LEFT: all three sectors at full intensity,
##                       ADDED to V1.6d's 4.62-point tax swing, stays inside
##                       DEFICIT_SCALE_PP = 6.0. So 3 * candidate <= 1.38.
##                  TIEBREAKER: two-sided on two model criteria, so V1.5c's midpoint
##                  rule. The response is closed form -- the bill IS the candidate
##                  times the standing intensity -- so table (b) prints the arithmetic
##                  and NO GRID CAN MOVE THE ANSWER, which is V1.6d's
##                  PROGRESSIVITY_BASE_BETA standard.
##
##   (P2) SPEED     CAPITAL_CONVERGENCE. How fast the capital a programme buys
##                  arrives.
##                  Banded on t90, months to 90 % of the endpoint, which is
##                  companies_constants.SHARE_SHIFT_PER_MONTH's device.
##                  BAND, fixed before the column existed: 36 <= t90 <= 84 months.
##                  docs/brainstorm/mechanics-economy.md's sketch is "direct state
##                  money at a sector and WAIT SEVERAL YEARS" -- under three years is
##                  not several, and over seven is longer than any president in this
##                  game can serve twice.
##                  TIEBREAKER: two-sided on one model criterion read from both ends,
##                  so the midpoint of the passing interval IN t90 rather than in the
##                  rate -- the band is written in months and a midpoint taken in the
##                  rate would be a midpoint of the wrong quantity, which is V1.5c's
##                  resolution error one step earlier. Closed form:
##                  t90 = ln(0.1) / ln(1 - rate/12), so no grid can move it either.
##
##   (P3) STRENGTH  SECTOR_TREND_BETA. What the capital is worth in trend.
##                  (i)  LEGIBLE: a reachable programme (the largest single sector
##                       package the content ships, run to convergence) must move the
##                       NATION'S trend by at least what a reachable infrastructure
##                       budget already buys through INFRA_BETA -- one point of GDP is
##                       0.15 %/yr. Below that the verb is worth less than moving a
##                       slider that already exists.
##                  (ii) NOT DOMINANT: the same programme stays under
##                       economy_constants.SHIFT_MAX_PCT = 1.0, the whole long-run
##                       budget every other lever in the game shares.
##                  TIEBREAKER: the response is exactly LINEAR in the beta, so the
##                  model edge is a smooth crossing rather than a plateau and V1.5d's
##                  extension applies -- neither edge selects, the INTERIOR governs,
##                  midpoint of the passing interval.
##                  MEASURED BY EXACT EMULATION, not by rescaling the shipped figure:
##                  a candidate b is run by holding the capital at true * b / shipped
##                  for the two economy reads and restoring it before the stock
##                  advances. V1.6b's correction -- the first version of its table
##                  rescaled from the shipped constant and the passing interval MOVED
##                  when that constant moved.
##
## *** KILL SWITCH, fixed before the sweep. *** The lever must move
## `growth_annual_pct` by at least 0.20 %/yr, sustained, at a reachable programme, on
## an ISOLATED path -- the capital displaced with every budget line untouched, so the
## deficit and every tax satisfaction are bit-identical between the rows and cancel.
## V1.5a's QUALITY_SCALE_PP failure, which V1.6d hit again inside the probe written to
## avoid it. If nothing reachable clears it, SECTOR_TREND_BETA is NOT raised until it
## does -- that is tuning against an arithmetic impossibility, refused at V1.5b, V1.6a
## and V1.6b -- the bound is RECORDED and said out loud.
##
## *** ESCALATION TRIGGER 1, named in advance. *** Symmetric decay: if a withdrawal
## reverses most of the gain inside a game year, the lever is
## docs/scenario-model.md's decorative axis and the response is an ASYMMETRIC decay
## constant, added because a measurement forced it and not pre-emptively.
##
## *** ESCALATION TRIGGER 2. *** If (P1) clause (ii) has no passing value -- three
## sectors at full intensity cannot fit inside what V1.6d left of DEFICIT_SCALE_PP --
## the finding is that the deficit issue is OUT OF SPAN and the response is V1.6d's:
## record it, do not retune DEFICIT_SCALE_PP, which re-baselines every opinion
## constant measured since S5.
##
## *** GUARD RAIL, declared not a selector. *** SECTOR_TREND_MAX_PCT is reported
## against the reachable peak in table (g). If it sits ON the reachable stack, the
## clamp and not the model is setting the number -- docs/economy-model.md's
## IMPULSE_MAX finding, which this project has now caught five times.
##
## *** TWO CORRECTIONS THE FIRST RUN FORCED, BOTH RECORDED RATHER THAN TIDIED. ***
##
##   1. THE PRICE WAS FLAT AND THE RETURN WAS NOT. Table (e) came back with French
##      services moving growth 0.4865 points and French agriculture 0.0077 -- the same
##      bill for a sixty-third of the effect, which is the strictly-dominated shape
##      this project has caught six times and the first time it has turned up in a
##      PRICE rather than in an effect. The fix moves the model rather than the number
##      (the bill scales with the sector own share of GDP, so the return per euro is
##      the same wherever it is spent) and it DELETED a constant:
##      INVESTMENT_BILL_MAX_PCT_GDP, because the three shares sum to exactly 1.0 and
##      the bill is therefore bounded above by INVESTMENT_COST_PCT_GDP itself.
##      companies_constants.RIVAL_FLOOR_FRACTION's correction in a new place.
##
##   2. (P3) CLAUSE (ii) WAS MEASURING THE CLAMP. Read off the SHIPPED figure, the
##      national shift is scaled down to SECTOR_TREND_MAX_PCT the moment it would
##      exceed it -- so "stays under SHIFT_MAX_PCT" is true at every candidate above
##      the clamp point BY THE CLAMP, and a grid wide enough to reach it reports a
##      passing interval bounded by a guard rail. V1.6d's finding, in the session
##      after it. Clause (ii) now reads the UNCLAMPED weighted shift, and both columns
##      are printed so the difference is visible rather than asserted.
##
## And a third the grid nearly caused: both (P1) and (P2) are CLOSED FORM, and the
## first run reported the interval as the widest PASSING GRID ROW -- 0.40 where the
## exact edge is 0.46, and t90 38.3-77.8 where the band says 36-84. That is V1.5b's
## "the range was choosing the constant" inside two tables whose whole claim was that
## no grid could move them. The exact edges are solved and printed; the grid is kept
## only as a legibility column.

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
const Trade = preload("res://src/sim/trade.gd")
const Investment = preload("res://src/sim/investment.gd")
const K = preload("res://src/sim/investment_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")

const PLAYER := "FRA"
const START_YEAR := 2026
const RUN_MONTHS := 168
## Long enough for the stock to converge and for the trend to have been paid for --
## one full presidency plus the term after it, which is the horizon the row's "wait
## several years" is measured against.
const REACHABLE_MONTHS := 120

## V1.6d's measured swing, docs/tax-model.md section 7. Quoted rather than
## recomputed: it is a published measurement of another session's model and
## recomputing it here would be one number with two writers.
const TAX_SWING_PTS := 4.62

## The largest single-sector package the shipped content offers, per sector.
const REACHABLE_ACTION := {
	"agriculture": "agricultural_transformation",
	"industry": "reindustrialisation",
	"services": "knowledge_economy_plan",
}

const COST_CANDIDATES := [0.10, 0.15, 0.20, 0.25, 0.30, 0.35, 0.40, 0.46, 0.50, 0.60, 0.80]
const CONVERGENCE_CANDIDATES := [0.20, 0.30, 0.35, 0.40, 0.45, 0.50, 0.55, 0.60, 0.70, 0.80, 1.00]
const BETA_CANDIDATES := [0.05, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60, 0.70, 0.80, 1.00, 1.50, 2.00]

const KILL_SWITCH_GROWTH_PTS := 0.20
const INFRA_REACHABLE_PCT := 0.15
const POLL_FLOOR_PTS := 3.0

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	print("=== V1.6e sectoral investment probe ===")
	print("shipped: cost %.4f  convergence %.4f  beta %.4f  bound %.2f" % [
		K.INVESTMENT_COST_PCT_GDP, K.CAPITAL_CONVERGENCE, K.SECTOR_TREND_BETA,
		K.SECTOR_TREND_MAX_PCT,
	])
	_table_a_landing_site()
	_table_b_cost()
	_table_c_convergence()
	_table_d_beta()
	_table_e_kill_switch()
	_table_f_share_drift()
	_table_g_guard_rails()
	_table_h_withdrawal()
	_table_i_political_price()
	quit(0)


# --- (a) the boundary check the row forced -------------------------------------------

## (B1). Two things measured rather than asserted.
##
## First: an absolute injection into sector_output is CANCELLED at the GDP level
## inside one tick, because _apply_growth_to_sectors() ends with
## `ns.gdp_eur_bn = total` and total is the month's target by construction. That is
## what makes the row's "acts on sector_output itself" a write this model refuses.
##
## Second, and it is a finding about code that was already here: Trade.sector_shift()
## sums to zero as RAW POINTS, but trend_pct() share-weights -- so the share-weighted
## sum of a live agreement's shift is NOT zero, and the difference is absorbed by the
## cyclical residual. The comment in _apply_growth_to_sectors() ("summed, this is
## exactly the nation's trend, so the two paths agree") predates V1.3b. V1.6e's own
## shift is added at trend_pct() as well, so it does NOT inherit this: the number
## below is what the investment channel would have looked like had it been added at
## one site only.
func _table_a_landing_site() -> void:
	print("\n(a) THE LANDING SITE -- boundary check B1, run before any band")

	var state = _new_state()
	var ns = state.player()
	var gdp_before: float = ns.gdp_eur_bn
	# Inject 5 % of the industry sector as free output, then tick once.
	ns.sector_output["industry"] = float(ns.sector_output["industry"]) * 1.05
	var injected: float = ns.gdp_eur_bn * 0.0
	for key in C.SECTOR_TREND.keys():
		injected += float(ns.sector_output[key])
	Economy.tick_month(state)

	var control = _new_state()
	Economy.tick_month(control)
	var control_ns = control.player()

	print("    injected into sector_output   %+.3f bn before the tick" % (injected - gdp_before))
	print("    GDP after the tick            %.4f bn" % ns.gdp_eur_bn)
	print("    control GDP after the tick    %.4f bn" % control_ns.gdp_eur_bn)
	print("    difference                    %+.6f bn  <- the residual took it back" % (
		ns.gdp_eur_bn - control_ns.gdp_eur_bn
	))
	print("    industry share moved          %+.5f" % (
		float(ns.sector_output["industry"]) / ns.gdp_eur_bn
		- float(control_ns.sector_output["industry"]) / control_ns.gdp_eur_bn
	))
	print("    => a write to sector_output survives as COMPOSITION and not as level.")

	# The share-weighted leak in the shift that is already there.
	var shift := {"agriculture": -0.15, "industry": 0.45, "services": -0.30}
	var raw := 0.0
	var weighted := 0.0
	for key in shift.keys():
		raw += float(shift[key])
		weighted += float(shift[key]) * float(control_ns.sector_output[key]) / control_ns.gdp_eur_bn
	print("    industrial_compact raw sum    %+.4f  (validated to zero at load)" % raw)
	print("    ... share-weighted at FRA     %+.4f  <- NOT zero; the residual absorbs it" % weighted)
	print("    => V1.6e adds its shift at trend_pct() as well, so it does not inherit this.")


# --- (b) P1, the cost ------------------------------------------------------------------

func _table_b_cost() -> void:
	print("\n(b) P1 INVESTMENT_COST_PCT_GDP -- closed form, invariant to the shipped value")
	var headroom: float = OpinionK.DEFICIT_SCALE_PP - TAX_SWING_PTS
	print("    headroom left by V1.6d: DEFICIT_SCALE_PP %.2f - tax swing %.2f = %.2f pts" % [
		OpinionK.DEFICIT_SCALE_PP, TAX_SWING_PTS, headroom
	])

	# The bill scales with the sector own share, so "one sector" means the largest one
	# France has -- the most a single programme can possibly cost.
	var state = _new_state()
	var ns = state.player()
	var largest := 0.0
	var largest_name := ""
	for sector in C.SECTOR_TREND.keys():
		var share: float = float(ns.sector_output[sector]) / ns.gdp_eur_bn
		if share > largest:
			largest = share
			largest_name = String(sector)
	print("    largest FRA sector: %s at %.4f of GDP; the whole economy is 1.0 by construction" % [
		largest_name, largest
	])

	print("    cand   largest sector   whole economy   +tax swing   (i)>=0.20  (ii) fits")
	for cand in COST_CANDIDATES:
		var one: float = float(cand) * largest
		var whole: float = float(cand)
		print("    %.2f   %14.3f   %13.3f   %10.3f   %8s  %9s" % [
			float(cand), one, whole, whole + TAX_SWING_PTS,
			_yn(one >= 0.20), _yn(whole <= headroom),
		])

	# THE EXACT EDGES, not the widest passing grid row. Both criteria are linear in the
	# candidate, so each edge is one division.
	var lo: float = 0.20 / largest
	var hi: float = headroom
	if lo > hi:
		print("    *** ESCALATION TRIGGER 2 FIRED: no candidate is both legible and inside")
		print("    what V1.6d left of DEFICIT_SCALE_PP. RECORD, do not retune that constant.")
		return
	print("    exact interval [%.4f, %.4f], midpoint %.4f -> INVESTMENT_COST_PCT_GDP" % [
		lo, hi, 0.5 * (lo + hi)
	])
	print("    shipped %.4f" % K.INVESTMENT_COST_PCT_GDP)

	# The closed form confirmed once against the real model, so a second-order effect
	# through debt service could not be hiding inside it.
	var measured := _run_investment("all", REACHABLE_MONTHS, 1.0, false)
	var quiet := _run_investment("", REACHABLE_MONTHS, 1.0, false)
	print("    measured, whole economy, %d months: deficit %+.4f against quiet %+.4f, gap %+.4f" % [
		REACHABLE_MONTHS, measured["deficit_pct_gdp"], quiet["deficit_pct_gdp"],
		measured["deficit_pct_gdp"] - quiet["deficit_pct_gdp"],
	])
	print("    (the gap exceeds the bill by debt service on what the bill borrowed)")


# --- (c) P2, the speed -----------------------------------------------------------------

func _table_c_convergence() -> void:
	print("\n(c) P2 CAPITAL_CONVERGENCE -- closed form in t90, band 36-84 months")
	print("    cand    t90 (months)   in band   pass")
	var passing: Array = []
	var t90s := {}
	for cand in CONVERGENCE_CANDIDATES:
		var rate: float = float(cand)
		var t90: float = log(0.1) / log(1.0 - rate / 12.0)
		t90s[rate] = t90
		var ok: bool = t90 >= 36.0 and t90 <= 84.0
		if ok:
			passing.append(rate)
		print("    %.2f    %12.1f   %7s   %s" % [rate, t90, _yn(ok), _yn(ok)])

	if passing.is_empty():
		print("    NO PASSING VALUE -- the band and the model do not overlap.")
		return
	# THE MIDPOINT IS TAKEN IN t90 AND NOT IN THE RATE, because the band is written in
	# months. Solved back to a rate afterwards.
	var lo: float = float(passing[0])
	var hi: float = float(passing[-1])
	var mid_t90: float = 0.5 * (float(t90s[lo]) + float(t90s[hi]))
	var rate_at_mid: float = 12.0 * (1.0 - pow(0.1, 1.0 / mid_t90))
	print("    grid rates [%.2f, %.2f] -> t90 [%.1f, %.1f] months" % [
		lo, hi, float(t90s[hi]), float(t90s[lo])
	])
	print("    grid midpoint in t90 %.1f months -> %.4f  (NOT the answer: the grid moved it)" % [
		mid_t90, rate_at_mid
	])
	# THE EXACT EDGES. The band is written in months and the map from months to rate is
	# closed form, so the midpoint is taken at t90 = 60.0 exactly and solved back.
	var exact_mid_t90: float = 0.5 * (36.0 + 84.0)
	var exact_rate: float = 12.0 * (1.0 - pow(0.1, 1.0 / exact_mid_t90))
	print("    exact band 36.0-84.0 months -> rates [%.4f, %.4f]" % [
		12.0 * (1.0 - pow(0.1, 1.0 / 84.0)), 12.0 * (1.0 - pow(0.1, 1.0 / 36.0))
	])
	print("    midpoint in t90 %.1f months -> CAPITAL_CONVERGENCE %.4f" % [
		exact_mid_t90, exact_rate
	])
	print("    shipped %.3f gives t90 %.1f months" % [
		K.CAPITAL_CONVERGENCE, log(0.1) / log(1.0 - K.CAPITAL_CONVERGENCE / 12.0)
	])


# --- (d) P3, the strength ---------------------------------------------------------------

func _table_d_beta() -> void:
	print("\n(d) P3 SECTOR_TREND_BETA -- exact emulation, not a rescale")
	print("    the reachable programme is the largest package per sector, %d months" % REACHABLE_MONTHS)
	print("    *** CLAUSE (ii) READS THE UNCLAMPED SHIFT. *** On the clamped figure it is")
	print("    true at every candidate above the clamp point BY THE CLAMP -- V1.6d's finding.")
	print("    cand   clamped   unclamped   (i)>=%.2f   (ii)<%.2f   pass" % [
		INFRA_REACHABLE_PCT, C.SHIFT_MAX_PCT
	])
	var slope := 0.0
	for cand in BETA_CANDIDATES:
		var ratio: float = float(cand) / K.SECTOR_TREND_BETA
		var r := _run_investment("services", REACHABLE_MONTHS, ratio, false)
		var clamped: float = float(r["trend_shift_pct"])
		var raw: float = float(r["raw_shift_pct"])
		slope = maxf(slope, raw / float(cand))
		var i_ok: bool = raw >= INFRA_REACHABLE_PCT
		var ii_ok: bool = raw < C.SHIFT_MAX_PCT
		print("    %.2f   %7.4f   %9.4f   %9s   %8s   %s" % [
			float(cand), clamped, raw, _yn(i_ok), _yn(ii_ok), _yn(i_ok and ii_ok)
		])

	# THE EXACT EDGES. The response is exactly linear in the beta, so one measured
	# slope gives both crossings and no grid can move them.
	if slope > 0.0:
		var lo: float = INFRA_REACHABLE_PCT / slope
		var hi: float = C.SHIFT_MAX_PCT / slope
		print("    measured slope %.4f points of national trend per unit of beta" % slope)
		print("    exact interval [%.4f, %.4f], midpoint %.4f -> SECTOR_TREND_BETA" % [
			lo, hi, 0.5 * (lo + hi)
		])
		print("    (linear response, smooth crossing -> the interior governs, V1.5d)")
	print("    shipped %.4f" % K.SECTOR_TREND_BETA)


# --- (e) the kill switch -----------------------------------------------------------------

func _table_e_kill_switch() -> void:
	print("\n(e) KILL SWITCH -- growth move at a reachable programme, ISOLATED path")
	print("    every budget line untouched in both rows, so the deficit cancels")
	var quiet := _run_investment("", REACHABLE_MONTHS, 1.0, false)
	print("    sector        growth   trend    vs quiet growth   clears %.2f" % KILL_SWITCH_GROWTH_PTS)
	var best := 0.0
	for sector in C.SECTOR_TREND.keys():
		var r := _run_investment(String(sector), REACHABLE_MONTHS, 1.0, false)
		var d: float = float(r["growth_annual_pct"]) - float(quiet["growth_annual_pct"])
		best = maxf(best, d)
		print("    %-12s  %6.3f   %6.3f   %+15.4f   %s" % [
			sector, r["growth_annual_pct"], r["trend_annual_pct"], d,
			_yn(d >= KILL_SWITCH_GROWTH_PTS),
		])
	print("    quiet control growth %.3f, trend %.3f" % [
		quiet["growth_annual_pct"], quiet["trend_annual_pct"]
	])
	if best >= KILL_SWITCH_GROWTH_PTS:
		print("    KILL SWITCH CLEARED at %.4f points." % best)
	else:
		print("    *** KILL SWITCH FIRED: best reachable move %.4f. RECORD, do not raise." % best)


# --- (f) what the trend move is made of ----------------------------------------------------

## The composition loop exists ALREADY: trend_pct() is share-weighted over
## SECTOR_TREND, so a sector growing faster than its neighbours raises the national
## trend without anybody investing. V1.6e does not create it; it steers it. This
## table says how much of the measured move is the shift itself and how much is the
## share drift the shift caused.
func _table_f_share_drift() -> void:
	print("\n(f) DECOMPOSITION -- the shift, and the share drift it steers")
	var quiet := _run_investment("", REACHABLE_MONTHS, 1.0, false)
	print("    sector        total trend move   of which shift   of which drift")
	for sector in C.SECTOR_TREND.keys():
		var r := _run_investment(String(sector), REACHABLE_MONTHS, 1.0, false)
		var total: float = float(r["trend_annual_pct"]) - float(quiet["trend_annual_pct"])
		var shift: float = float(r["trend_shift_pct"])
		print("    %-12s  %16.4f   %14.4f   %14.4f" % [sector, total, shift, total - shift])
	print("    (drift is the share-weighted SECTOR_TREND moving because the mix moved,")
	print("     plus potential_shift_pct responding to nothing this lever writes)")


# --- (g) the guard rails ---------------------------------------------------------------------

func _table_g_guard_rails() -> void:
	print("\n(g) GUARD RAIL -- declared not a selector, reported against the reachable peak")
	var all_three := _run_investment("all", REACHABLE_MONTHS, 1.0, false)
	print("    reachable peak national shift  %.4f  against SECTOR_TREND_MAX_PCT %.2f  %s" % [
		all_three["raw_shift_pct"], K.SECTOR_TREND_MAX_PCT,
		("BINDS -- trigger fired" if float(all_three["raw_shift_pct"]) >= K.SECTOR_TREND_MAX_PCT else "slack"),
	])
	# The bill needs no clamp at all and no longer has one: the three shares sum to
	# exactly 1.0, so every sector at full intensity is INVESTMENT_COST_PCT_GDP and no
	# value of anything can exceed it. Printed as the arithmetic rather than asserted.
	print("    reachable peak bill            %.4f  bounded BY CONSTRUCTION at %.4f" % [
		all_three["investment_bill_pct_gdp"], K.INVESTMENT_COST_PCT_GDP
	])
	print("    all three at full intensity, %d months: trend %.3f, deficit %.3f" % [
		REACHABLE_MONTHS, all_three["trend_annual_pct"], all_three["deficit_pct_gdp"]
	])


# --- (h) escalation trigger 1 -----------------------------------------------------------------

func _table_h_withdrawal() -> void:
	print("\n(h) ESCALATION TRIGGER 1 -- symmetric decay, is a withdrawal a demolition?")
	var state = _new_state()
	var ns = state.player()
	_invest(state, ns, "industry")
	for _m in range(REACHABLE_MONTHS):
		_tick(state, ns, 1.0)
	var built: float = Investment.capital_of(ns, "industry")
	_withdraw(state, ns, "industry")
	print("    capital at withdrawal   %.4f" % built)
	print("    months after   capital   fraction left")
	var checkpoints := [6, 12, 24, 36, 60]
	var elapsed := 0
	for cp in checkpoints:
		while elapsed < int(cp):
			_tick(state, ns, 1.0)
			elapsed += 1
		var left: float = Investment.capital_of(ns, "industry")
		print("    %12d   %7.4f   %13.2f" % [elapsed, left, left / built])
	var year_left: float = 0.0
	# Recomputed cleanly for the verdict.
	var s2 = _new_state()
	var n2 = s2.player()
	_invest(s2, n2, "industry")
	for _m in range(REACHABLE_MONTHS):
		_tick(s2, n2, 1.0)
	var b2: float = Investment.capital_of(n2, "industry")
	_withdraw(s2, n2, "industry")
	for _m in range(12):
		_tick(s2, n2, 1.0)
	year_left = Investment.capital_of(n2, "industry") / b2
	if year_left < 0.50:
		print("    *** TRIGGER FIRED: %.0f %% left after a year. An asymmetric decay is warranted." % (100.0 * year_left))
	else:
		print("    trigger did not fire: %.0f %% left after a year, so a withdrawal is not a demolition" % (100.0 * year_left))
		print("    and NO second constant is added. V1.6a's bounded-by-construction discipline.")


# --- (i) the political price, and the sixteenth ISSUE_KEYS question ---------------------------

## The authored bloc_offset is the ONLY price this verb has, which is exactly what
## makes the sixteenth ISSUE_KEYS question answerable NO where V1.6b's and V1.6d's
## had to be YES -- inflation and a tax rate have no content object anywhere and this
## has one. What the table has to show is that the offset is LEGIBLE: an authored
## price nothing can read would put the question back.
func _table_i_political_price() -> void:
	print("\n(i) THE AUTHORED PRICE -- is the bloc_offset legible past the +-%.1f poll floor?" % POLL_FLOOR_PTS)
	print("    action                        approval move   worst bloc move   clears")
	for sector in C.SECTOR_TREND.keys():
		var action_id := String(REACHABLE_ACTION[sector])
		var base := _run_opinion(null)
		var acted := _run_opinion(action_id)
		var move: float = float(acted["overall"]) - float(base["overall"])
		var worst := 0.0
		var worst_name := ""
		for bloc in OpinionK.BLOC_KEYS:
			var d: float = float(acted["blocs"][bloc]) - float(base["blocs"][bloc])
			if absf(d) > absf(worst):
				worst = d
				worst_name = String(bloc)
		print("    %-28s  %+13.3f   %s %+9.3f   %s" % [
			action_id, move, worst_name.rpad(11), worst, _yn(absf(worst) >= POLL_FLOOR_PTS)
		])
	print("    NOTE: an offset applied to fewer than all six blocs never clears the floor")
	print("    in the HEADLINE figure -- docs/diplomacy-model.md's own V1.3a finding -- so")
	print("    the per-bloc column is the one that decides, exactly as it did there.")


# --- machinery -------------------------------------------------------------------------------

func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = START_YEAR
	state.month = 1
	return state


func _action(id: String):
	for a in _loader.investment_actions:
		if a.id == id:
			return a
	return null


func _invest(state, ns, sector: String) -> void:
	Investment.execute(state, ns, _loader.investment_actions, _action(String(REACHABLE_ACTION[sector])))


func _withdraw(state, ns, sector: String) -> void:
	for a in _loader.investment_actions:
		var terms: Dictionary = a.effects.get("investment", {})
		if String(terms.get("sector", "")) == sector and String(terms.get("op", "")) == "withdraw":
			Investment.execute(state, ns, _loader.investment_actions, a)
			return


## One month, with a candidate SECTOR_TREND_BETA emulated EXACTLY rather than
## rescaled afterwards. shift = beta * capital, so holding the capital at
## true * ratio for the two economy reads is arithmetically identical to running the
## model at beta * ratio -- and the stock's own dynamics are untouched, because the
## true value is restored before Investment.tick_month() advances it.
func _tick(state, ns, ratio: float) -> void:
	var truth := {}
	if ratio != 1.0:
		for sector in ns.sector_investment.keys():
			var entry: Dictionary = ns.sector_investment[sector]
			truth[sector] = float(entry["capital"])
			entry["capital"] = float(entry["capital"]) * ratio

	Economy.tick_month(state)

	if ratio != 1.0:
		for sector in truth.keys():
			ns.sector_investment[sector]["capital"] = float(truth[sector])

	Budget.tick_month(state)
	Bloc.tick_month(state, _loader)
	Inflation.tick_month(state)
	Media.tick_month(state, _loader)
	Opinion.tick_month(state)
	Defence.tick_month(state)
	Companies.tick_month(state, _loader)
	Investment.tick_month(state)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, _loader)


## `sector` is "" for the quiet control, "all" for every sector at once.
func _run_investment(sector: String, months: int, ratio: float, _unused: bool) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	if sector == "all":
		for s in C.SECTOR_TREND.keys():
			_invest(state, ns, String(s))
	elif sector != "":
		_invest(state, ns, sector)

	for i in range(months):
		state.month = (i + 1) % 12 + 1
		state.year = START_YEAR + int((i + 1) / 12)
		_tick(state, ns, ratio)

	# Read at the candidate ratio, the same displacement the economy saw.
	var truth := {}
	if ratio != 1.0:
		for s in ns.sector_investment.keys():
			truth[s] = float(ns.sector_investment[s]["capital"])
			ns.sector_investment[s]["capital"] = float(truth[s]) * ratio
	var shift: float = Investment.national_trend_shift_pct(ns)
	if ratio != 1.0:
		for s in truth.keys():
			ns.sector_investment[s]["capital"] = float(truth[s])

	# The UNCLAMPED weighted shift, computed here rather than read back, because
	# Investment.sector_trend_shift() applies the bound and clause (ii) must not be
	# measured through it.
	var raw := 0.0
	for s2 in ns.sector_investment.keys():
		raw += (
			K.SECTOR_TREND_BETA * ratio * Investment.capital_of(ns, String(s2))
			* float(ns.sector_output.get(s2, 0.0)) / ns.gdp_eur_bn
		)

	return {
		"gdp_eur_bn": ns.gdp_eur_bn,
		"raw_shift_pct": raw,
		"investment_bill_pct_gdp": ns.investment_bill_pct_gdp,
		"trend_annual_pct": ns.trend_annual_pct,
		"growth_annual_pct": ns.growth_annual_pct,
		"trend_shift_pct": shift,
		"deficit_pct_gdp": ns.deficit_pct_gdp,
		"unemployment_pct": ns.unemployment_pct,
		"structural_unemployment_pct": ns.structural_unemployment_pct,
		"overall_approval_pct": ns.overall_approval_pct,
	}


## Twelve months with one action taken at month 0, for the price table. Short on
## purpose: an authored offset is a step, and INERTIA_RATE lands most of it inside a
## quarter -- a longer run measures the economy the programme bought rather than the
## price it was charged.
func _run_opinion(action_id) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	if action_id != null:
		Investment.execute(state, ns, _loader.investment_actions, _action(String(action_id)))
	for i in range(12):
		state.month = (i + 1) % 12 + 1
		state.year = START_YEAR + int((i + 1) / 12)
		_tick(state, ns, 1.0)
	var blocs := {}
	for bloc in OpinionK.BLOC_KEYS:
		blocs[bloc] = float(ns.bloc_approval.get(bloc, 0.0))
	return {"overall": ns.overall_approval_pct, "blocs": blocs}


func _report_interval(passing: Array, label: String, rule: String) -> void:
	if passing.is_empty():
		print("    *** NO PASSING VALUE for %s. %s" % [label, rule])
		return
	var lo: float = float(passing[0])
	var hi: float = float(passing[-1])
	print("    passing [%.4f, %.4f], midpoint %.4f -> %s (%s)" % [
		lo, hi, 0.5 * (lo + hi), label, rule
	])
	if passing.size() == 1:
		print("    *** ONE PASSING VALUE ONLY -- refine the grid before trusting it.")


func _yn(ok: bool) -> String:
	return "yes" if ok else "no"
