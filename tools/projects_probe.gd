extends SceneTree

## V1.6f's headless sweep. Every number in data/project-actions/ and the one guard
## rail in src/sim/projects_constants.gd is set from a table below rather than guessed
## and defended afterwards.
##
## Run: godot --headless --script res://tools/projects_probe.gd
##
## *** THE BANDS AND THE TIEBREAKERS ARE BOTH PRE-COMMITTED. *** Eight corrections to
## that discipline are inherited rather than rediscovered:
##
##   V1.4c  fix the TIEBREAKER as well as the band.
##   V1.5a  a tiebreaker must strictly ORDER the survivors; a clause that passes at
##          every candidate is a BOUND, not a selector.
##   V1.5b  its answer must not MOVE when the candidate range is widened. A value
##          sitting at an endpoint of the swept range is a suspect, not a result.
##   V1.5c  a nearest-to-X tiebreaker is only as good as the grid's RESOLUTION.
##   V1.5d  when the model edge is a smooth CROSSING rather than a plateau, neither
##          edge selects and the interior governs.
##   V1.6a  where something outside the model measures the same quantity, prefer a FIT
##          to a band: a band edge moves under widening, a fit converges.
##   V1.6c  check each term against the MODEL'S OWN BOUNDARY before the band, because
##          a band is a test of size and not of legitimacy.
##   V1.6d  a band that passes at every candidate with the identical measurement is
##          measuring a CLAMP. Say so and replace it.
##
## *** AND V1.6e's, WHICH THIS SESSION IS MOST EXPOSED TO: where an edge is closed
## form, SOLVE IT. The first run of that probe reported the widest passing GRID ROW as
## the interval inside two tables whose whole claim was that no grid could move them.
## Every edge below is arithmetic over the loaded content; the grid is a legibility
## column and never a selector. ***
##
## ============================================================================
## THE BOUNDARY CHECKS, SETTLED BEFORE ANY BAND WAS WRITTEN
## ============================================================================
##
##   (B1) IS GameState.appointments THIS SCHEDULER UNDER ANOTHER NAME? NO, and the
##        argument is in src/sim/projects.gd's header: a deferred COMMAND that fires
##        once and cancels for free is not a COMMITMENT that bills monthly and can be
##        abandoned part-built. What is reused is the SURFACE -- Calendar.fixed_dates()
##        gains a row -- and it cost no preload, because the register counts MONTHS
##        REMAINING, the idiom every other countdown in this project already uses.
##        Table (a) measures the reuse rather than asserting it.
##
##   (B2) IS THE PAYOFF A SECOND economy_constants.INFRA_BETA? NO, and it is not a
##        third quantity reaching trend either. Against src/core/law.gd's criterion --
##        same act, same landing site AND same units -- it matches on the landing site
##        alone. And ns.law_potential_target_pct is already a permanent accumulator on
##        that target, so this is the SIXTH writer of an existing machine rather than a
##        new one. Table (b) measures that the two are distinguishable in the model and
##        not only in the prose.
##
##   (B3) IS "SLOW" ALREADY SPENT? YES, HALF OF IT, AND IT CHANGED WHAT (P2) IS BANDED
##        ON. economy_constants.SHIFT_ADJUST is a five-year lag on that target, so a
##        build of N months and then a five-year lag are two answers to
##        docs/brainstorm/mechanics-economy.md's one word "slow". A band on the build
##        alone would have measured half the wait. Table (c) bands the DELIVERED
##        FRACTION from commit instead.
##
##   (B4) IS THERE AN EMPLOYMENT TERM TO PRICE? NO, AND NOT BY PROHIBITION -- V1.6e's
##        finding one step further out. The payoff raises TREND,
##        Economy._update_unemployment() reads Okun on `growth - trend`, and structural
##        unemployment reads only the income-tax wedge, the law offset and the firm
##        layer. There is nothing to band; tests/test_projects.gd pins it
##        bit-identically. Table (e) prints it beside the growth move anyway, because a
##        claim worth pinning is worth showing.
##
##   (B5) COST AS A STOCK OR A FLOW? A FLOW. V1.4c writes debt_eur_bn directly because
##        buying equity swaps cash for a SELLABLE asset; building a road is spending,
##        so it is a computed budget line -- the fifth -- and it stops when the work
##        does. Table (d) prints the peak against the headroom.
##
## ============================================================================
## THE PARAMETERS -- AND ALL THREE ARE CONTENT
## ============================================================================
## src/sim/projects_constants.gd ships NO cost, speed or strength constant, so what is
## banded here is the AUTHORED LADDER. That is V1.4b's position, where not one
## correction was to the model, and it is forced rather than chosen: with no constant
## turning one of the three numbers into the other two, a project's duration, price and
## payoff are three independent facts and only the content can state them.
##
##   (P1) COST      the per-project cost_pct_gdp ladder.
##                  *** THE ONE THING THIS SESSION WAS TOLD TO MEASURE BEFORE ASSUMING
##                  THERE WAS ROOM. *** docs/tax-model.md section 7 measured V1.6d's
##                  two new taxes at 4.62 points of opinion_constants.DEFICIT_SCALE_PP's
##                  six-point span and investment_constants.INVESTMENT_COST_PCT_GDP is
##                  0.8161, so the headroom for a FIFTH computed budget line is
##                  6.0 - 4.62 - 0.8161 = 0.5639 points. Not V1.6e's 1.38, and not
##                  companies_constants.SUBSIDY_BILL_MAX_PCT_GDP's 2.50.
##                  (i)  LEGIBLE: the cheapest project costs >= 0.10 points of GDP, a
##                       fifth of an income-tax point. Below that the line cannot be
##                       read beside the investment bill it sits next to on the budget.
##                  (ii) FITS: the largest stack the CONTENT'S OWN `project_count` gate
##                       permits stays inside 0.5639.
##                  TIEBREAKER: none, and that is the point -- a ladder is not one
##                  number, so the two clauses are BOUNDS on a set of authored values
##                  and the table reports whether the shipped ladder is inside them.
##                  V1.5a's rule read from the other side: a clause that cannot order
##                  candidates must not pretend to select one.
##
##   (P2) SPEED     the per-project build_months ladder, banded on DELIVERED FRACTION
##                  from commit rather than on build length -- see (B3).
##                  f(t) = 0 for t < build, else 1 - (1 - SHIFT_ADJUST/12)^(t - build).
##                  (i)  COLLECTABLE: the SHORTEST project delivers >= 0.30 of its
##                       payoff within one presidential term of commitment (60 months).
##                       A commitment no president can ever show anything for is
##                       docs/scenario-model.md's decorative axis.
##                  (ii) A BEQUEST: the LONGEST delivers EXACTLY 0.00 within one term
##                       and >= 0.25 within two (120 months). The first half is what
##                       makes the largest project a decision about the country rather
##                       than about the next election; the second is what stops it
##                       being unreachable.
##                  TIEBREAKER: none, for (P1)'s reason. Closed form throughout.
##
##   (P3) STRENGTH  the per-project potential_growth_pct ladder.
##                  (i)  LEGIBLE: the LARGEST project's payoff clears what a reachable
##                       infrastructure budget already buys through INFRA_BETA -- one
##                       point of GDP is 0.15 %/yr. Below that the verb is worth less
##                       than moving a slider that already exists, which is V1.6e's
##                       clause (i) inherited whole.
##                  (ii) NOT DOMINANT: the WHOLE LADDER accumulated leaves room in the
##                       budget it shares. economy_constants.SHIFT_MAX_PCT is 1.0 and
##                       INFRA_BETA on a reachable two-point rise is 0.30, so the sum
##                       of every payoff must stay <= 0.70 or a player who builds
##                       everything cannot also use the slider. V1.3b's "openness and
##                       public investment compete for the same +-1.0 budget", one
##                       writer later.
##
## *** THE DOMINANCE CHECK, WHICH IS THE CONTENT TEST V1.6e's PRICE CORRECTION TURNED
## INTO A STANDING ONE. *** That session found a flat bill buying a 63:1 spread -- the
## strictly-dominated shape, for the first time in a price. Here price and payoff are
## both authored, so nothing structural prevents it and only a check can: table (f)
## reports every ordered pair, and a project that costs less IN TOTAL, builds faster
## AND pays more than another makes that other one content nobody should ever choose.
## The intended shape is the opposite: cost per unit of payoff FALLS with size, and
## what buys the discount is a wait longer than the office.
##
## *** KILL SWITCH, fixed before the sweep. *** The largest reachable project must move
## `growth_annual_pct` by at least 0.15 %/yr, sustained, on an ISOLATED path -- the
## accumulator displaced with every budget line untouched, so the deficit and every tax
## satisfaction are bit-identical between the rows and cancel. V1.5a's QUALITY_SCALE_PP
## failure, which V1.6d hit again inside the probe written to avoid it. If nothing
## reachable clears it, the ladder is NOT raised until it does -- that is tuning against
## an arithmetic impossibility, refused at V1.5b, V1.6a and V1.6b -- the bound is
## RECORDED and said out loud.
##
## *** ESCALATION TRIGGER 1 (B3). *** If no build length in
## [MIN_BUILD_MONTHS, MAX_BUILD_MONTHS] can deliver 0.30 inside one term, the finding is
## that SHIFT_ADJUST'S OWN LAG IS BINDING and the response is to shorten the BUILD --
## never SHIFT_ADJUST, which re-baselines every economy constant measured since S4.
##
## *** ESCALATION TRIGGER 2. *** If no ladder is both legible under (P1)(i) and inside
## the 0.5639 headroom under (P1)(ii), the finding is that the deficit issue is OUT OF
## SPAN and the response is V1.6d's and V1.6e's: record it, do not retune
## DEFICIT_SCALE_PP, which re-baselines every opinion constant measured since S5.
##
## *** GUARD RAIL, declared not a selector. *** PROJECT_POTENTIAL_MAX_PCT is reported
## against the reachable peak in table (g). If the peak sits ON it, the clamp and not
## the content is setting the number -- docs/economy-model.md's IMPULSE_MAX finding,
## which this project has now caught six times.
##
## *** REACHABILITY, which V1.3f got wrong and V1.5c's probe inherited. *** A project
## that only completes after the government that started it has been thrown out is a
## measurement of nothing. Table (i) prints, for each project, whether it completes
## inside one term, inside two, and inside the harness at all.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Orgs = preload("res://src/sim/orgs.gd")
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
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const K = preload("res://src/sim/projects_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")

const PLAYER := "FRA"
const START_YEAR := 2026
const RUN_MONTHS := 168

## One presidential term and two, in months. Every legibility band in this file is
## written against one of the two, because that is the horizon a player can act on.
const TERM_MONTHS := 60
const TWO_TERMS_MONTHS := 120

## V1.6d's measured tax swing (docs/tax-model.md section 7) and V1.6e's shipped cost.
## Quoted rather than recomputed: each is a published measurement of another session's
## model, and recomputing one here would be a number with two writers.
const TAX_SWING_PTS := 4.62
const INVESTMENT_COST_PTS := 0.8161

const KILL_SWITCH_GROWTH_PTS := 0.15
const INFRA_REACHABLE_PCT := 0.15
const POLL_FLOOR_PTS := 3.0

## (P1)(i), (P2)(i), (P2)(ii), (P3)(ii): the pre-committed edges, in one place so the
## table cannot quietly disagree with the header.
const COST_LEGIBLE_MIN := 0.10
const DELIVERED_ONE_TERM_MIN := 0.30
const DELIVERED_TWO_TERMS_MIN := 0.25
const LADDER_SUM_MAX := 0.70

## Legibility columns only, never selectors. V1.6e's third correction.
const BUILD_CANDIDATES := [24, 30, 36, 42, 48, 54, 60, 72, 84, 96, 108, 120]

## Uniform scalings of the authored cost ladder, for table (d). A legibility column
## in the same sense: what selects is the largest that fits, and the run either way
## is a measurement rather than a grid read -- the quantity being measured (the peak
## deficit under a compounding debt) has no closed form, which is exactly why the
## arithmetic version of this clause was wrong.
const COST_SCALES := [0.40, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.90, 1.00]

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	print("=== V1.6f infrastructure projects probe ===")
	print("shipped: PROJECT_POTENTIAL_MAX_PCT %.2f  build [%d, %d]  cost ceiling %.2f  payoff ceiling %.2f" % [
		K.PROJECT_POTENTIAL_MAX_PCT, K.MIN_BUILD_MONTHS, K.MAX_BUILD_MONTHS,
		K.MAX_PROJECT_COST_PCT_GDP, K.MAX_PROJECT_POTENTIAL_PCT,
	])
	print("headroom: DEFICIT_SCALE_PP %.2f - taxes %.2f - investment %.4f = %.4f" % [
		OpinionK.DEFICIT_SCALE_PP, TAX_SWING_PTS, INVESTMENT_COST_PTS, _headroom(),
	])
	_table_a_scheduler()
	_table_b_landing_site()
	_table_c_speed()
	_table_d_cost()
	_table_e_kill_switch()
	_table_f_dominance()
	_table_g_guard_rails()
	_table_h_political_price()
	_table_i_reachability()
	quit(0)


# --- (a) B1: the scheduler that was not written ---------------------------------

## Measured rather than asserted, because "we reused the diary" is exactly the kind of
## claim that is true in the plan and false in the code. Two things are checked: that a
## project under construction reaches Calendar.fixed_dates() with the right date, and
## that it does so with src/sim/calendar.gd still preloading nothing.
func _table_a_scheduler() -> void:
	print("\n(a) B1 -- the register is months-remaining, so the diary needed no scheduler")
	var state = _new_state()
	var ns = state.player()
	var pid := _smallest()
	_start(state, ns, pid)
	var build := int(_terms(pid).get("build_months", 0))

	var rows := Calendar.fixed_dates(state)
	var found := {}
	for row in rows:
		if String(row.get("kind", "")) == CalendarK.FIXED_PROJECT:
			found = row
	if found.is_empty():
		print("    *** the diary does not show a project under construction. B1's reuse is not real.")
		return

	var want := START_YEAR * 12 + (1 - 1) + build
	var got := int(found["year"]) * 12 + (int(found["month"]) - 1)
	print("    %s: build %d months -> diary says %02d/%d, expected %02d/%d  %s" % [
		pid, build, int(found["month"]), int(found["year"]),
		want % 12 + 1, want / 12, _yn(got == want),
	])

	# And the completed project must NOT appear: a diary is about what is coming.
	for i in range(build + 1):
		Projects.tick_month(state, _loader)
	var still := 0
	for row in Calendar.fixed_dates(state):
		if String(row.get("kind", "")) == CalendarK.FIXED_PROJECT:
			still += 1
	print("    after completion the diary lists %d project rows (want 0)  %s" % [still, _yn(still == 0)])

	var src := FileAccess.get_file_as_string("res://src/sim/calendar.gd")
	var preloads := 0
	for line in src.split("\n"):
		if line.begins_with("const ") and line.contains("preload("):
			preloads += 1
	print("    src/sim/calendar.gd preloads %d file(s) -- want 1, its own constants  %s" % [
		preloads, _yn(preloads == 1),
	])


# --- (b) B2: not a second INFRA_BETA, and not a third trend term ------------------

## The prose argument is src/core/law.gd's criterion. What a table can add is that the
## two are distinguishable IN THE MODEL: the spending line produces its shift through a
## delta against the nation's own start and can be reversed by moving the slider back,
## where a completed project's addend cannot be reversed at all. Measured by running
## both to the same national trend move and then taking each lever away.
func _table_b_landing_site() -> void:
	print("\n(b) B2 -- the payoff is the SIXTH writer of an existing target, not a new quantity")
	print("    %-34s %10s %10s %10s" % ["", "trend@60", "lever off", "trend@120"])

	var infra := _run_infra(0.30 / C.INFRA_BETA)
	print("    %-34s %10.4f %10s %10.4f" % [
		"infrastructure line +2.0 pts", infra["trend_at_term"], "reversible", infra["trend_after_cut"],
	])
	var proj := _run_project(_largest(), TWO_TERMS_MONTHS, 1.0)
	print("    %-34s %10.4f %10s %10.4f" % [
		"largest project, completed", proj["trend_at_term"], "permanent", proj["trend_annual_pct"],
	])
	print("    same landing site, different act, different units -> 1 of law.gd's 3. Not a pair.")

	# And the sharper half: nothing new reaches Economy.trend_pct().
	# CODE ONLY. The first version of this check read the whole file and came back
	# "yes" against a module that touches neither -- it was matching this file's own
	# header, which names both in prose. A check a COMMENT can fail is a check that
	# will be quietly broken by whoever writes the next comment.
	var touches := _code_mentions("res://src/sim/projects.gd", ["trend_pct", "sector_output"])
	print("    src/sim/projects.gd CODE reads trend_pct() or sector_output: %s (want no)" % _yn(touches))
	var control := _run_isolated(0.0, TWO_TERMS_MONTHS)
	print("    control trend at 120 months: %.4f" % control["trend_annual_pct"])


# --- (c) P2: the build ladder, banded on DELIVERED FRACTION ----------------------

## (B3)'s correction in table form. f(t) is closed form, so the grid below is printed
## for legibility and the edges are solved.
func _table_c_speed() -> void:
	print("\n(c) P2 -- delivered fraction from COMMIT, because SHIFT_ADJUST is half the wait")
	print("    SHIFT_ADJUST %.2f/yr -> t50 %.1f months, t90 %.1f months AFTER completion" % [
		C.SHIFT_ADJUST, _months_to(0.50), _months_to(0.90),
	])
	print("    %-10s %10s %10s %10s" % ["build", "f(60)", "f(120)", "f(168)"])
	for b in BUILD_CANDIDATES:
		print("    %-10d %10.3f %10.3f %10.3f" % [
			b, _delivered(int(b), TERM_MONTHS), _delivered(int(b), TWO_TERMS_MONTHS),
			_delivered(int(b), RUN_MONTHS),
		])

	# The exact edges. (i) is the longest build still delivering 0.30 inside a term;
	# (ii) is the shortest build delivering nothing inside one.
	var edge_i := _build_for_delivered(TERM_MONTHS, DELIVERED_ONE_TERM_MIN)
	var edge_ii := TERM_MONTHS
	var edge_iii := _build_for_delivered(TWO_TERMS_MONTHS, DELIVERED_TWO_TERMS_MIN)
	print("    solved: (i) shortest project must build in <= %.1f months" % edge_i)
	print("            (ii) longest must build in > %d and <= %.1f months" % [edge_ii, edge_iii])
	if edge_i < float(K.MIN_BUILD_MONTHS):
		print("    *** ESCALATION TRIGGER 1 FIRES: no legal build length delivers %.2f inside a term." % DELIVERED_ONE_TERM_MIN)
		print("        SHIFT_ADJUST's own lag is binding. Shorten the build; never SHIFT_ADJUST.")

	print("    shipped ladder:")
	print("    %-22s %8s %10s %10s %8s" % ["project", "build", "f(60)", "f(120)", "ok"])
	var shortest := _smallest()
	var longest := _largest()
	for pid in _project_ids():
		var b := int(_terms(pid).get("build_months", 0))
		var f60 := _delivered(b, TERM_MONTHS)
		var f120 := _delivered(b, TWO_TERMS_MONTHS)
		var ok := true
		if pid == shortest:
			ok = f60 >= DELIVERED_ONE_TERM_MIN
		if pid == longest:
			ok = is_zero_approx(f60) and f120 >= DELIVERED_TWO_TERMS_MIN
		print("    %-22s %8d %10.3f %10.3f %8s" % [pid, b, f60, f120, _yn(ok)])


# --- (d) P1: the cost ladder against what V1.6d and V1.6e left ------------------

func _table_d_cost() -> void:
	print("\n(d) P1 -- the cost ladder against the headroom, closed form")
	var gate := _concurrency_gate()
	var stack := _largest_stack(gate)
	print("    content gates `project_count` at <= %d, so at most %d run at once" % [gate, gate + 1])
	print("    %-22s %12s" % ["project", "cost %GDP/yr"])
	for pid in _project_ids():
		print("    %-22s %12.3f" % [pid, float(_terms(pid).get("cost_pct_gdp", 0.0))])
	print("    cheapest %.3f >= %.2f (i) %s" % [_min_cost(), COST_LEGIBLE_MIN, _yn(_min_cost() >= COST_LEGIBLE_MIN)])
	print("    largest permitted stack %.4f <= %.4f (ii) %s" % [stack, _headroom(), _yn(stack <= _headroom())])
	if _min_cost() < COST_LEGIBLE_MIN or stack > _headroom():
		print("    *** ESCALATION TRIGGER 2 FIRES: no ladder is both legible and inside the span.")
		print("        Record it. Do NOT retune DEFICIT_SCALE_PP.")

	# Measured once against the real model, so a second-order effect cannot hide inside
	# the arithmetic -- V1.6e's own confirmation step.
	# THE PEAK, not the figure at the end of the run. The first version printed the
	# deficit at month 120, by which time both projects in the stack have COMPLETED and
	# stopped billing -- 0.2647 against a bill of 0.5200, so the table reported the
	# debt service on a programme that had finished and called it the cost of running
	# one. A bill that STOPS is exactly what makes this lever different from every
	# other line on the budget, and it is what makes an end-of-run reading wrong.
	var loud := _run_stack_peak(gate, TWO_TERMS_MONTHS)
	print("    measured: peak deficit widening %.4f pts while the stack builds" % [
		loud["peak_deficit_gap"],
	])
	print("              and %.4f pts at ten years, both finished -- debt service alone" % [
		loud["end_deficit_gap"],
	])

	# *** AND THAT IS WHY CLAUSE (ii) IS BANDED ON THE MEASURED PEAK AND NOT ON THE
	# ARITHMETIC STACK. *** The bill is 0.5200 and the deficit moves 0.7615: a build
	# that runs for eight years BORROWS for eight years, so what reaches
	# `public_finances` is the bill plus V1.6c's interest on everything borrowed so
	# far. Every previous computed line in this game is a standing rate against a
	# roughly standing debt, so bill and deficit moved together and the distinction
	# never mattered; a line that runs for a fixed term and stops is the first one
	# where it does. V1.6c's own finding, arriving from the other side.
	#
	# The response is a MEASURED SCALE for the ladder rather than an authored one. The
	# shape of the ladder -- the ratios between the five, which is what makes a big
	# project cheaper per point and slower to collect -- is content; its overall SIZE
	# is whatever fits, and only a run can say what that is.
	print("    scale       stack     peak deficit   fits %.4f" % _headroom())
	var best := 0.0
	for scale in COST_SCALES:
		var row := _run_stack_scaled(gate, TWO_TERMS_MONTHS, float(scale))
		var fits: bool = row["peak_deficit_gap"] <= _headroom()
		if fits:
			best = maxf(best, float(scale))
		print("    %-11.3f %9.4f %14.4f   %s" % [
			scale, _largest_stack(gate) * float(scale), row["peak_deficit_gap"], _yn(fits),
		])
	print("    largest UNIFORM scale that fits: %.3f -> cheapest project %.4f (floor %.2f)" % [
		best, _min_cost() * best, COST_LEGIBLE_MIN,
	])

	# *** AND THE UNIFORM SCALE IS THE WRONG PARAMETER, WHICH IS THE SECOND CORRECTION
	# THIS TABLE FORCED. *** The first version of this sweep declared escalation
	# trigger 2 on the strength of it -- 0.700 fits and takes the cheapest project to
	# 0.084, under the 0.10 floor, so "no scale is both legible and inside the span".
	# True, and it is a statement about the sweep rather than about the model: clause
	# (i) binds the CHEAPEST project and clause (ii) binds the DEAREST PAIR, so one
	# multiplier cannot satisfy both by construction and the free variable is the
	# ladder's SPREAD. A grid that can only move a set rigidly reports "impossible" for
	# anything that needs the set reshaped -- V1.5b's "the range was choosing the
	# constant" with the range one dimension short.
	#
	# The response is linear in the stack to four figures across the sweep, so the edge
	# is SOLVED rather than read off the grid, which is V1.6e's standard.
	var lo := _run_stack_scaled(gate, TWO_TERMS_MONTHS, COST_SCALES[0])
	var hi := _run_stack_scaled(gate, TWO_TERMS_MONTHS, COST_SCALES[-1])
	var stack_lo: float = _largest_stack(gate) * float(COST_SCALES[0])
	var stack_hi: float = _largest_stack(gate) * float(COST_SCALES[-1])
	var slope: float = (hi["peak_deficit_gap"] - lo["peak_deficit_gap"]) / (stack_hi - stack_lo)
	var intercept: float = lo["peak_deficit_gap"] - slope * stack_lo
	var max_stack: float = (_headroom() - intercept) / slope
	print("    solved: peak deficit = %.4f * stack %+.4f, so the stack may reach %.4f" % [
		slope, intercept, max_stack,
	])
	print("    every point of project bill costs %.2f points of deficit at the peak --" % slope)
	print("    the bill itself plus V1.6c's interest on years of borrowing behind it.")
	print("    shipped stack %.4f <= %.4f  %s" % [
		_largest_stack(gate), max_stack, _yn(_largest_stack(gate) <= max_stack),
	])
	if max_stack < COST_LEGIBLE_MIN * float(gate + 1):
		print("    *** ESCALATION TRIGGER 2 FIRES: even a ladder of minimum-legible projects")
		print("        cannot fit the gate inside the span. Record it. Do NOT retune")
		print("        DEFICIT_SCALE_PP, which re-baselines every opinion constant since S5.")


# --- (e) the kill switch, on an isolated path ------------------------------------

## ISOLATED: the accumulator is displaced directly and no budget line moves, so the
## deficit and every tax satisfaction are identical between the rows and cancel. The
## bill is deliberately NOT charged here -- this measures what the payoff is worth, not
## what it cost, which is the separation V1.5a's failure was about.
func _table_e_kill_switch() -> void:
	print("\n(e) KILL SWITCH -- growth move at the largest reachable project, isolated path")
	var quiet := _run_isolated(0.0, TWO_TERMS_MONTHS)
	print("    %-26s %10s %10s %10s %12s" % ["payoff", "growth", "trend", "unemp", "vs quiet"])
	print("    %-26s %10.4f %10.4f %10.4f %12s" % [
		"none (control)", quiet["growth_annual_pct"], quiet["trend_annual_pct"],
		quiet["unemployment_pct"], "--",
	])
	var cleared := false
	for pid in _project_ids():
		var payoff := float(_terms(pid).get("potential_growth_pct", 0.0))
		var row := _run_isolated(payoff, TWO_TERMS_MONTHS)
		var d: float = row["growth_annual_pct"] - quiet["growth_annual_pct"]
		if d >= KILL_SWITCH_GROWTH_PTS:
			cleared = true
		print("    %-26s %10.4f %10.4f %10.4f %12.4f" % [
			pid, row["growth_annual_pct"], row["trend_annual_pct"], row["unemployment_pct"], d,
		])
	print("    clears %.2f %%/yr: %s (isolated, as pre-committed)" % [KILL_SWITCH_GROWTH_PTS, _yn(cleared)])
	if not cleared:
		print("    *** KILL SWITCH FIRED. Record the bound; do not raise the ladder to clear it.")

	# THE ISOLATED PATH HOLDS THE PAYOFF FROM MONTH ZERO, which is a project already
	# finished, so it measures what the payoff is WORTH and not what a player gets.
	# The switch is judged on it, as pre-committed -- but printing only that column
	# would be V1.3f's measuring-the-wrong-state inside the table written to avoid it,
	# so the reachable path is beside it: the project actually started at month 0,
	# billed every month it builds, over the whole harness.
	var real_quiet := _run_project("", RUN_MONTHS, 1.0)
	var iso_quiet := _run_isolated(0.0, RUN_MONTHS)
	print("    %-26s %10s %10s %12s %12s" % ["real path, 168 months", "growth", "trend", "vs quiet", "of isolated"])
	for pid in _project_ids():
		var row := _run_project(pid, RUN_MONTHS, 1.0)
		var d2: float = row["growth_annual_pct"] - real_quiet["growth_annual_pct"]
		var iso := _run_isolated(float(_terms(pid).get("potential_growth_pct", 0.0)), RUN_MONTHS)
		var iso_d: float = iso["growth_annual_pct"] - iso_quiet["growth_annual_pct"]
		print("    %-26s %10.4f %10.4f %12.4f %12s" % [
			pid, row["growth_annual_pct"], row["trend_annual_pct"], d2,
			("%.0f %%" % (100.0 * d2 / iso_d)) if absf(iso_d) > 0.0 else "--",
		])

	# B4, shown rather than only pinned.
	var big := _run_isolated(float(_terms(_largest()).get("potential_growth_pct", 0.0)), TWO_TERMS_MONTHS)
	print("    B4: structural unemployment quiet %.6f vs built %.6f -- identical: %s" % [
		quiet["structural_unemployment_pct"], big["structural_unemployment_pct"],
		_yn(quiet["structural_unemployment_pct"] == big["structural_unemployment_pct"]),
	])

	# P3's two clauses.
	var max_payoff := _max_payoff()
	var sum_payoff := _sum_payoff()
	print("    P3 (i) largest payoff %.4f >= INFRA_BETA's reachable %.2f  %s" % [
		max_payoff, INFRA_REACHABLE_PCT, _yn(max_payoff >= INFRA_REACHABLE_PCT),
	])
	print("    P3 (ii) whole ladder %.4f <= %.2f, leaving the slider its %.2f  %s" % [
		sum_payoff, LADDER_SUM_MAX, C.SHIFT_MAX_PCT - LADDER_SUM_MAX,
		_yn(sum_payoff <= LADDER_SUM_MAX),
	])


# --- (f) the dominance check -----------------------------------------------------

## V1.6e's price correction as a standing test. A project is strictly dominated if
## another costs less IN TOTAL over its build, finishes sooner AND pays more. The
## intended shape is that cost per unit of payoff FALLS with size and the discount is
## bought with time, so no pair should dominate and the last column should be monotone.
func _table_f_dominance() -> void:
	print("\n(f) DOMINANCE -- nothing may be cheaper, faster AND better than something else")
	print("    %-22s %8s %10s %10s %14s" % ["project", "build", "total cost", "payoff", "cost/payoff"])
	for pid in _project_ids():
		print("    %-22s %8d %10.4f %10.4f %14.3f" % [
			pid, int(_terms(pid).get("build_months", 0)), _total_cost(pid),
			float(_terms(pid).get("potential_growth_pct", 0.0)), _cost_per_payoff(pid),
		])

	var dominated := 0
	for a in _project_ids():
		for b in _project_ids():
			if a == b:
				continue
			var ta := _terms(a)
			var tb := _terms(b)
			if (
				_total_cost(a) < _total_cost(b)
				and int(ta.get("build_months", 0)) < int(tb.get("build_months", 0))
				and float(ta.get("potential_growth_pct", 0.0)) > float(tb.get("potential_growth_pct", 0.0))
			):
				print("    *** %s STRICTLY DOMINATES %s -- cheaper, faster and better." % [a, b])
				dominated += 1
	print("    dominated pairs: %d (want 0)  %s" % [dominated, _yn(dominated == 0)])

	var monotone := true
	var ids := _project_ids()
	for i in range(ids.size() - 1):
		if _cost_per_payoff(String(ids[i])) > _cost_per_payoff(String(ids[i + 1])):
			monotone = false
	print("    cost per unit of payoff falls as the project grows: %s" % _yn(monotone))


# --- (g) the guard rails ----------------------------------------------------------

func _table_g_guard_rails() -> void:
	print("\n(g) GUARD RAILS -- declared, not selectors")
	var peak := _sum_payoff()
	print("    PROJECT_POTENTIAL_MAX_PCT %.2f against the reachable peak %.4f -- %s" % [
		K.PROJECT_POTENTIAL_MAX_PCT, peak,
		"SLACK" if peak < K.PROJECT_POTENTIAL_MAX_PCT else "*** BINDING, the clamp is setting the number",
	])
	var everything := _run_everything()
	print("    SHIFT_MAX_PCT %.2f against potential_shift_pct after building everything: %.4f -- %s" % [
		C.SHIFT_MAX_PCT, everything["potential_shift_pct"],
		"SLACK" if everything["potential_shift_pct"] < C.SHIFT_MAX_PCT else "*** BINDING",
	])
	print("    peak project bill %.4f against the headroom %.4f" % [
		everything["peak_bill"], _headroom(),
	])


# --- (h) the political price ------------------------------------------------------

## The seventeenth ISSUE_KEYS question is answered NO on test 1 alone -- this ships a
## content object with an authored bloc_offset, which is exactly what every YES lacked.
## The S10 ratio is deliberately not swept, on V1.5a's ground. What must be checked is
## that the authored price is LEGIBLE, because an authored price nothing can read would
## put the question back.
func _table_h_political_price() -> void:
	print("\n(h) the authored price, twelve months after the act")
	var base := _run_opinion(null)
	print("    %-26s %10s   %s" % ["action", "headline", "worst bloc"])
	for a in _loader.project_actions:
		var row := _run_opinion(a.id)
		# AN ABANDON IS MEASURED AGAINST A PRESIDENT WHO STARTED AND CARRIED ON, not
		# against one who never began. The first version compared it to the quiet run,
		# so every abandon row read the NET of a start and a cancellation taken in the
		# same month -- about -0.02 of offset, under the floor, and IDENTICAL across
		# five projects that are not alike, which is what gave it away. That measures a
		# president who changed their mind inside thirty days; what the content is
		# priced for is a government walking away from work in progress.
		var against := base
		if _op_of(a) == "abandon":
			against = _run_opinion_started(_pid_of(a))
		var worst := ""
		var worst_move := 0.0
		for bloc in OpinionK.BLOC_KEYS:
			var move: float = float(row["blocs"][bloc]) - float(against["blocs"][bloc])
			if absf(move) > absf(worst_move):
				worst_move = move
				worst = bloc
		print("    %-26s %10.2f   %s %+.2f  %s" % [
			a.id, row["overall"] - against["overall"], worst, worst_move,
			"clears" if absf(worst_move) >= POLL_FLOOR_PTS else "under the floor",
		])
	print("    +-%.1f is the poll-noise floor. Clearing on the per-bloc rows and not on" % POLL_FLOOR_PTS)
	print("    the headline is V1.3a's finding used as designed: a policy that divides")
	print("    the country should not move the average.")


# --- (i) reachability -------------------------------------------------------------

## V1.3f's error and V1.5c's blind spot: a probe whose loop has no elections will
## happily measure a government that would have been thrown out. This table does not
## fix that -- tools/balance_probe.gd does -- but it says which projects a president
## could ever collect on.
func _table_i_reachability() -> void:
	print("\n(i) REACHABILITY -- who can collect")
	print("    %-22s %10s %12s %12s" % ["project", "build", "in one term", "in two"])
	for pid in _project_ids():
		var b := int(_terms(pid).get("build_months", 0))
		print("    %-22s %10d %12s %12s" % [
			pid, b, _yn(b <= TERM_MONTHS), _yn(b <= TWO_TERMS_MONTHS),
		])
	print("    a project finishing outside two terms is a bequest by design; one that")
	print("    finishes outside the %d-month harness is unmeasurable and there are none." % RUN_MONTHS)


# --- helpers -----------------------------------------------------------------------

func _headroom() -> float:
	return OpinionK.DEFICIT_SCALE_PP - TAX_SWING_PTS - INVESTMENT_COST_PTS


## Fraction of a completed project's payoff that has arrived `t` months after COMMIT.
## Closed form: the target steps at `build` and the lag closes SHIFT_ADJUST/12 of the
## remaining gap each month.
func _delivered(build: int, t: int) -> float:
	if t <= build:
		return 0.0
	return 1.0 - pow(1.0 - C.SHIFT_ADJUST / 12.0, float(t - build))


## Months after completion to reach a given fraction. ln(1-f) / ln(1 - rate/12).
func _months_to(fraction: float) -> float:
	return log(1.0 - fraction) / log(1.0 - C.SHIFT_ADJUST / 12.0)


## The longest build that still delivers `fraction` by `t` months after commit. Solved,
## not searched -- V1.6e's third correction.
func _build_for_delivered(t: int, fraction: float) -> float:
	return float(t) - _months_to(fraction)


func _project_ids() -> Array:
	var out: Array = []
	for a in _loader.project_actions:
		var terms: Dictionary = a.effects.get("project", {})
		if String(terms.get("op", "")) == "start":
			out.append(String(terms.get("project_id", "")))
	out.sort_custom(func(x, y): return _total_cost(String(x)) > _total_cost(String(y)))
	return out


func _terms(project_id: String) -> Dictionary:
	return Projects.terms_of(_loader, project_id)


func _total_cost(project_id: String) -> float:
	var t := _terms(project_id)
	return float(t.get("cost_pct_gdp", 0.0)) * float(t.get("build_months", 0)) / 12.0


func _cost_per_payoff(project_id: String) -> float:
	var payoff := float(_terms(project_id).get("potential_growth_pct", 0.0))
	return _total_cost(project_id) / payoff if payoff > 0.0 else INF


func _largest() -> String:
	return String(_project_ids()[0])


func _smallest() -> String:
	var ids := _project_ids()
	return String(ids[-1])


func _min_cost() -> float:
	var lo := INF
	for pid in _project_ids():
		lo = minf(lo, float(_terms(pid).get("cost_pct_gdp", 0.0)))
	return lo


func _max_payoff() -> float:
	var hi := 0.0
	for pid in _project_ids():
		hi = maxf(hi, float(_terms(pid).get("potential_growth_pct", 0.0)))
	return hi


func _sum_payoff() -> float:
	var total := 0.0
	for pid in _project_ids():
		total += float(_terms(pid).get("potential_growth_pct", 0.0))
	return total


## What the CONTENT permits to run at once, read off the `project_count` preconditions
## rather than assumed -- the ceiling is content, which is why projects_constants.gd
## ships no concurrency constant.
func _concurrency_gate() -> int:
	var gate := 0
	for a in _loader.project_actions:
		if String(a.effects.get("project", {}).get("op", "")) != "start":
			continue
		for cond in a.preconditions:
			if String(cond["field"]) == "project_count" and String(cond["op"]) == "<=":
				gate = maxi(gate, int(cond["value"]))
	return gate


## The dearest set the gate permits: gate + 1 projects running together.
func _largest_stack(gate: int) -> float:
	var costs: Array = []
	for pid in _project_ids():
		costs.append(float(_terms(pid).get("cost_pct_gdp", 0.0)))
	costs.sort()
	costs.reverse()
	var total := 0.0
	for i in range(mini(gate + 1, costs.size())):
		total += float(costs[i])
	return total


func _action_for(project_id: String, want_op: String):
	for a in _loader.project_actions:
		var terms: Dictionary = a.effects.get("project", {})
		if String(terms.get("project_id", "")) == project_id and String(terms.get("op", "")) == want_op:
			return a
	return null


func _start(state, ns, project_id: String) -> void:
	Projects.execute(state, ns, _loader.project_actions, _action_for(project_id, "start"))


func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = START_YEAR
	state.month = 1
	return state


## One month, in main.gd's order. `payoff` displaces ns.project_potential_target_pct
## for the economy read and is restored afterwards, which is how a candidate is
## emulated EXACTLY rather than rescaled from the shipped figure -- V1.6b's correction,
## inherited through V1.6e.
func _tick(state, ns, payoff: float) -> void:
	var truth: float = ns.project_potential_target_pct
	if payoff != 0.0:
		ns.project_potential_target_pct = payoff

	Economy.tick_month(state)

	if payoff != 0.0:
		ns.project_potential_target_pct = truth

	Budget.tick_month(state)
	Orgs.tick_month(state, _loader)
	Inflation.tick_month(state)
	Media.tick_month(state, _loader)
	Opinion.tick_month(state)
	Defence.tick_month(state)
	Companies.tick_month(state, _loader)
	Investment.tick_month(state)
	Projects.tick_month(state, _loader)
	Demography.tick_month(state)
	Society.tick_month(state)
	Unrest.tick_month(state)
	Cabinet.tick_month(state, _loader)


## The isolated path: no verb, no bill, the accumulator held at a candidate value for
## every month. What the payoff is worth, with nothing else moving.
func _run_isolated(payoff: float, months: int) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	for i in range(months):
		state.month = (i + 1) % 12 + 1
		state.year = START_YEAR + int((i + 1) / 12)
		_tick(state, ns, payoff)
	return _read(ns)


## The real path: one project actually started, billed and completed.
func _run_project(project_id: String, months: int, _unused: float) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	if project_id != "":
		_start(state, ns, project_id)
	var trend_at_term := 0.0
	for i in range(months):
		state.month = (i + 1) % 12 + 1
		state.year = START_YEAR + int((i + 1) / 12)
		_tick(state, ns, 0.0)
		if i + 1 == TERM_MONTHS:
			trend_at_term = ns.trend_annual_pct
	var out := _read(ns)
	out["trend_at_term"] = trend_at_term
	return out


## The same stack, run beside a control, tracking the widest the deficit ever gets.
func _run_stack_peak(gate: int, months: int) -> Dictionary:
	var control = _new_state()
	var cns = control.player()
	var state = _new_state()
	var ns = state.player()
	var started := 0
	for pid in _project_ids():
		if started > gate:
			break
		_start(state, ns, pid)
		started += 1
	var peak := 0.0
	for i in range(months):
		var mm := (i + 1) % 12 + 1
		var yy := START_YEAR + int((i + 1) / 12)
		state.month = mm
		state.year = yy
		control.month = mm
		control.year = yy
		_tick(state, ns, 0.0)
		_tick(control, cns, 0.0)
		peak = maxf(peak, ns.deficit_pct_gdp - cns.deficit_pct_gdp)
	var out := _read(ns)
	out["peak_deficit_gap"] = peak
	out["end_deficit_gap"] = ns.deficit_pct_gdp - cns.deficit_pct_gdp
	return out


## The same stack with every authored cost multiplied by `scale`, for table (d)'s
## measured band. The loaded content is displaced and restored, which is V1.6b's
## exact-emulation rule applied to content rather than to a constant: rescaling a
## measured figure afterwards would make the passing interval move with the shipped
## ladder, which is the error that table was written to avoid.
func _run_stack_scaled(gate: int, months: int, scale: float) -> Dictionary:
	var truth := {}
	for a in _loader.project_actions:
		var terms: Dictionary = a.effects.get("project", {})
		if terms.has("cost_pct_gdp"):
			truth[a.id] = float(terms["cost_pct_gdp"])
			terms["cost_pct_gdp"] = float(terms["cost_pct_gdp"]) * scale
	var out := _run_stack_peak(gate, months)
	for a in _loader.project_actions:
		var terms2: Dictionary = a.effects.get("project", {})
		if truth.has(a.id):
			terms2["cost_pct_gdp"] = float(truth[a.id])
	return out


## Everything, in gate-sized waves, over the whole harness -- the reachable peak the
## guard rails are reported against.
func _run_everything() -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	var peak_bill := 0.0
	var pending := _project_ids()
	for i in range(RUN_MONTHS):
		for pid in pending.duplicate():
			var a = _action_for(String(pid), "start")
			if a != null and Projects.available(state, ns, _loader.project_actions).has(a):
				Projects.execute(state, ns, _loader.project_actions, a)
				pending.erase(pid)
		state.month = (i + 1) % 12 + 1
		state.year = START_YEAR + int((i + 1) / 12)
		_tick(state, ns, 0.0)
		peak_bill = maxf(peak_bill, ns.project_bill_pct_gdp)
	var out := _read(ns)
	out["peak_bill"] = peak_bill
	out["potential_shift_pct"] = ns.potential_shift_pct
	out["built"] = Projects.completed(ns).size()
	return out


## The infrastructure spending line raised by `points`, for table (b)'s comparison --
## raised for one term, then put back, which is the reversibility a project does not
## have.
func _run_infra(points: float) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	ns.spending_pct_gdp["infrastructure"] = float(ns.spending_pct_gdp["infrastructure"]) + points
	var trend_at_term := 0.0
	for i in range(TWO_TERMS_MONTHS):
		state.month = (i + 1) % 12 + 1
		state.year = START_YEAR + int((i + 1) / 12)
		_tick(state, ns, 0.0)
		if i + 1 == TERM_MONTHS:
			trend_at_term = ns.trend_annual_pct
			ns.spending_pct_gdp["infrastructure"] = float(ns.start_spending_pct_gdp["infrastructure"])
	var out := _read(ns)
	out["trend_at_term"] = trend_at_term
	out["trend_after_cut"] = ns.trend_annual_pct
	return out


## Twelve months with one action taken at month 0, for the price table. Short on
## purpose: an authored offset is a step and INERTIA_RATE lands most of it inside a
## quarter, so a longer run measures the economy the project bought rather than the
## price it was charged. V1.6e's table (i).
func _run_opinion(action_id) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	if action_id != null:
		var a = _find(String(action_id))
		# An abandon is only legal against a build in progress, so its price is measured
		# from a state where one exists -- otherwise execute() refuses and the row would
		# read 0.00 for a reason that is not about the content.
		var pid := String(a.effects.get("project", {}).get("project_id", ""))
		if String(a.effects.get("project", {}).get("op", "")) == "abandon":
			_start(state, ns, pid)
		Projects.execute(state, ns, _loader.project_actions, a)
	for i in range(12):
		state.month = (i + 1) % 12 + 1
		state.year = START_YEAR + int((i + 1) / 12)
		_tick(state, ns, 0.0)
	var blocs := {}
	for bloc in OpinionK.BLOC_KEYS:
		blocs[bloc] = float(ns.bloc_approval.get(bloc, 0.0))
	return {"overall": ns.overall_approval_pct, "blocs": blocs}


## The same twelve months, but with the project STARTED and left alone -- the control
## an abandon must be read against. See table (h).
func _run_opinion_started(project_id: String) -> Dictionary:
	var state = _new_state()
	var ns = state.player()
	_start(state, ns, project_id)
	for i in range(12):
		state.month = (i + 1) % 12 + 1
		state.year = START_YEAR + int((i + 1) / 12)
		_tick(state, ns, 0.0)
	var blocs := {}
	for bloc in OpinionK.BLOC_KEYS:
		blocs[bloc] = float(ns.bloc_approval.get(bloc, 0.0))
	return {"overall": ns.overall_approval_pct, "blocs": blocs}


func _op_of(a) -> String:
	return String(a.effects.get("project", {}).get("op", ""))


func _pid_of(a) -> String:
	return String(a.effects.get("project", {}).get("project_id", ""))


## True if the file names any of `names` OUTSIDE a comment. Comments are stripped
## because a header that argues about a function is not a call to it.
func _code_mentions(path: String, names: Array) -> bool:
	var src := FileAccess.get_file_as_string(path)
	for line in src.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		for n in names:
			if line.contains(String(n)):
				return true
	return false


func _find(action_id: String):
	for a in _loader.project_actions:
		if a.id == action_id:
			return a
	return null


func _read(ns) -> Dictionary:
	return {
		"gdp_eur_bn": ns.gdp_eur_bn,
		"trend_annual_pct": ns.trend_annual_pct,
		"growth_annual_pct": ns.growth_annual_pct,
		"unemployment_pct": ns.unemployment_pct,
		"structural_unemployment_pct": ns.structural_unemployment_pct,
		"deficit_pct_gdp": ns.deficit_pct_gdp,
		"overall_approval_pct": ns.overall_approval_pct,
		"project_bill_pct_gdp": ns.project_bill_pct_gdp,
		"project_potential_target_pct": ns.project_potential_target_pct,
	}


func _yn(ok: bool) -> String:
	return "yes" if ok else "no"
