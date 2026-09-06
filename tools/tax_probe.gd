extends SceneTree

## V1.6d's headless sweep. Every constant in src/sim/tax_constants.gd and every new
## entry in opinion_constants.TAX_SCALE_PP_BY_KEY is set from a table below rather than
## guessed and defended afterwards.
##
## Run: godot --headless --script res://tools/tax_probe.gd
##
## *** STEP 0 RAN BEFORE ANY BAND WAS WRITTEN, AND THE ANSWER INVERTED THE PREDICTION. ***
## docs/credit-model.md section 2 found the World Bank government-finance branch too thin
## to use, so this session was told to expect the same and to check BEFORE planning a
## measured base share. Checked, over 1990-2024 for all ten:
##
##     GC.TAX.TOTL.GD.ZS   tax revenue                   10 of 10, 30-35 rows each
##     GC.TAX.YPKG.RV.ZS   income, profits AND cap gains 10 of 10, 30-35 rows each
##     GC.TAX.GSRV.RV.ZS   goods and services            10 of 10, 30-35 rows each
##     GC.TAX.PRPT.*       property                      NO ROWS AT ALL
##
## COVERAGE IS NOT THE PROBLEM, WHICH IS THE OPPOSITE OF WHAT (c) FOUND. What rules the
## branch out is universe and granularity, and either alone would be enough:
##
##   1. `GC.*` is CENTRAL government. Measured latest tax/GDP: FRA 22.78, DEU 10.89, CHE
##      9.45 -- against the general-government fiscal.tax_revenue_pct_gdp of 46.1, 39.3
##      and 27.8 the nation files carry. docs/data-sources.md rejected exactly this at S1
##      in exactly these words, so the fetch CONFIRMS a standing rejection rather than
##      discovering one.
##   2. `GC.TAX.YPKG.*` puts income, profits and capital gains in ONE BUCKET. It is
##      precisely the split this session exists to create, so it cannot supply it.
##   3. There is no wealth or property series at all.
##
## So both new TAX_BASE_SHARE entries are AUTHORED -- which is not a regression, because
## all three that were already there are authored model parameters too. No new download
## and no new docs/data-sources.md line.
##
## THE BANDS AND THE TIEBREAKERS ARE BOTH PRE-COMMITTED. Six corrections to that
## discipline are inherited rather than rediscovered. V1.4c: fix the tiebreaker, not only
## the band. V1.5a: a tiebreaker must strictly ORDER the survivors. V1.5b: its answer must
## not MOVE when the grid is widened. V1.5c: a nearest-to-X tiebreaker is only as good as
## the grid's RESOLUTION. V1.5d: when the model edge is a smooth crossing, NEITHER edge
## selects and the interior governs. V1.6c: check each term against the MODEL'S OWN
## BOUNDARY before the band, because a band is a test of size and not of legitimacy.
##
##   (P1) BRACKETS   PROGRESSIVITY_BASE_BETA. What a steeper income schedule costs in
##                   revenue, which is the whole of brackets' fiscal price and the reason
##                   docs/tiers/v1.md section 6's "without a fourth revenue channel" is
##                   met rather than argued around.
##                   BOUNDARY CHECK FIRST: is this a second writer of income revenue? No
##                   -- it is a coefficient INSIDE the one income line, and table (b)
##                   prints the revenue dictionary to show no line was added. A term that
##                   failed this would be deleted whatever its band said.
##                   (i)  LEGIBLE: taking the brackets to PROGRESSIVITY_MAX costs >= 0.50
##                        points of GDP of income revenue -- about one point of income
##                        tax, so the bracket lever is a real fiscal trade-off and not a
##                        free redistribution;
##                   (ii) NOT DOMINANT: the same move costs <= 2.50 points of GDP, a
##                        quarter of what France's income tax collects. Above that the
##                        bracket lever is a bigger tax change than the tax slider, which
##                        makes the slider the decoration.
##                   TIEBREAKER: the response is exactly LINEAR in the beta (table (b)
##                   prints the closed form), so the model edge is a crossing rather than
##                   a plateau and V1.5d's extension applies -- the INTERIOR governs,
##                   midpoint of the passing interval.
##
##   (P2) THE GINI   GINI_PROGRESSIVITY_BETA and GINI_RATE_BETA's two entries.
##                   *** THESE ARE FITTED, NOT BANDED, AND V1.6a IS WHY: a band edge moves
##                   when the grid is widened or refined, a fit converges. Where something
##                   outside the model measures the same quantity, prefer the fit. ***
##                   Something does: tools/import_data.py already carries every nation's
##                   measured Gini slope off SI.POV.GINI, and docs/unrest-model.md's
##                   INEQUALITY_BETA was set against it.
##                   THE FIT: a REACHABLE redistributive budget -- brackets +0.5, capital
##                   gains +10 points, wealth +0.5 points, which is a left-wing programme
##                   and not the maximum -- moves the effective index by as much as the
##                   WIDEST measured roster drift moves it over one five-year term. A
##                   president's own tax policy over a term is worth about what the
##                   country's structural drift is worth over the same term at its
##                   fastest. Table (c) prints the target and the solve.
##                   THE SPLIT between the three instruments is EQUAL THIRDS of that
##                   target, and it is an authoring choice stated rather than derived:
##                   nothing in the data ranks brackets against a wealth tax, and any
##                   other split would be a claim the measurement cannot support.
##                   *** KILL SWITCH, fixed before the sweep: the offset must move the
##                   DATE OF THE FIRST STRIKE on INEQUALITY_BETA's own channel. If no
##                   reachable budget moves it, the offset is a readout src/sim/ does not
##                   read, and it is DELETED and said out loud -- V1.5b's treatment of
##                   DEPENDENCY_ELASTICITY["health"]. Table (d). ***
##                   MEASURED ON AN ISOLATED PATH, and the first version was not: it
##                   committed real budgets, which move the deficit and two tax
##                   satisfactions as well, and both reach hardship() far harder than this
##                   channel does -- the flat-bracket row came back CALMER than the quiet
##                   one because flattening narrows the deficit. V1.5a's QUALITY_SCALE_PP
##                   failure, caught inside the probe written to avoid it.
##
##   (P3) THE CLAMP  GINI_POLICY_MAX_PT. A GUARD RAIL AND EXPLICITLY NOT A SELECTOR, which
##                   V1.5a's CORRUPTION_DELIVERY_BETA failure and V1.6c's clause (i) both
##                   say to declare in advance. It must sit strictly ABOVE the largest
##                   stack a player can reach, or the clamp and not the model is setting
##                   the number -- docs/defence-model.md's and docs/companies-model.md's
##                   treatment of their own. Table (e) reports the peak against it.
##                   THE FIRST VALUE WAS HALF THE ROSTER'S MEASURED GINI SPAN AND IT BOUND,
##                   which table (e) caught. It is the WHOLE span instead: a president may
##                   not move their own country's index further than the most equal nation
##                   in this game is from the least. Still measured, still not a selector.
##
##   (P4) SCALES     TAX_SCALE_PP_BY_KEY for `wealth` and `capital_gains`.
##                   BOUNDARY CHECK FIRST: opinion.gd prices every tax in POINTS OF RATE,
##                   and the wealth base is a stock at 4.00x GDP against income's 0.50
##                   flow. One shared scale is a units error, not a tuning choice.
##                   (i)  READABLE: a reachable move of each tax clears the +-3.0
##                        poll-noise floor in overall_approval_pct;
##                   (ii) NOT PREMATURELY SATURATED: the issue must not be pinned at -1.0
##                        at HALF the reachable move. Written in the binding form V1.6b's
##                        correction demands rather than the loose one it caught.
##                   TIEBREAKER: two-sided on two model criteria, so V1.5c's midpoint rule.
##                   *** THAT BAND WAS SWEPT AND COULD NOT SELECT, WHICH IS THIS ROW'S
##                   FINDING AND IS RECORDED RATHER THAN TIDIED. *** Clause (i) passed at
##                   every candidate with the IDENTICAL approval move, because the whole
##                   reachable move saturates the satisfaction at every scale in the grid
##                   -- so (i) was measuring the clamp. Clause (ii) then reduces to the
##                   arithmetic `candidate >= reach / 2`, which is a rearranged inequality
##                   and not a measurement. V1.5a's two failures at once, in one row.
##                   WHAT SHIPS IS A FIT, on V1.6a's rule, against the model's own accepted
##                   standard the way V1.6b settled its collinearity test: TAX_SCALE_PP's
##                   8.0 is a fixed FRACTION of income's own reachable upward span, and
##                   each new tax takes the same fraction of its own. It converges because
##                   the ratio is a property of constants already fixed for other reasons.
##
##   (P5) THE KEYS   *** THE ISSUE_KEYS QUESTION, ASKED TWICE AT ONCE, WHICH IS A FIRST.
##                   *** V1.3d's four tests plus the fifth V1.4b forced, per key, and the
##                   S10 ratio drift measured for each key alone and for both together.
##                   The prior for `tax_wealth` is BAD and structurally so: its natural
##                   profile is business-heavy, and `business` carries public_finances at
##                   0.34, which is exactly why `ownership` drifted -1.46 % at V1.4c.
##                   ACCEPT above V1.3d's measured +0.39 %; REFUSE below V1.4c's -1.46 %.
##                   PRE-COMMITTED FALLBACK: a tax key with no issue key is a satisfaction
##                   nothing reads, so a failing tax is CUT FROM TAX_KEYS rather than
##                   shipped keyless -- and if `tax_wealth` is the one that fails, section
##                   6's five-tax target is not met and the row is told so. Table (g).
##
##   (P6) TRIGGER    *** ESCALATION TRIGGER, named in advance. *** opinion_constants.
##                   DEFICIT_SCALE_PP is 6.0 and was measured at S10 for a THREE-TAX world,
##                   and docs/credit-model.md's clause (ii) already refused a channel that
##                   used half its span. Two new taxes widen the reachable revenue swing
##                   and want a share of the same six points. PRE-COMMITTED RESPONSE:
##                   RECORD IT, do not retune -- retuning that constant re-baselines every
##                   opinion constant measured since S5. It becomes a model question only
##                   if the widening exceeds the span itself, and then it is named as one.
##                   Table (h).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Tax = preload("res://src/sim/tax.gd")
const K = preload("res://src/sim/tax_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const Companies = preload("res://src/sim/companies.gd")
const Media = preload("res://src/sim/media.gd")

const START_YEAR := 2026
const RUN_MONTHS := 168

## The reachable redistributive budget the fit is anchored on. A left-wing programme a
## player would actually commit, NOT the maximum -- V1.6c's clause (i) correction, where
## a clause satisfied only by the most extreme row is a bound and not a selector.
const REACHABLE_BRACKETS := 0.5
const REACHABLE_CAPITAL_GAINS := 10.0
const REACHABLE_WEALTH := 0.5

## The five player-set spending lines as one group. S10's finding was a RATIO between this
## group and public_finances, not an absolute weight.
const SPENDING_ISSUES := ["health", "education", "defence", "pensions", "infrastructure"]

## The budget table (d) runs every row under, identically. docs/unrest-model.md's own
## reachable case is *govern well, win, then provoke*; this is the provoking half, and it
## is applied to the control as well so it cancels.
const PROVOCATIVE := {
	"spending_pct_gdp": {"health": 7.0, "pensions": 10.0, "education": 3.0},
	"tax_rates_pct": {"vat": 26.0, "income": 27.0},
}

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	_table_a_reachability()
	_table_b_bracket_revenue_price()
	_table_c_the_gini_fit()
	_table_d_kill_switch()
	_table_e_the_clamp()
	_table_f_the_scales()
	_table_g_the_issue_keys()
	_table_h_the_deficit_span()

	quit(0)


# --- (a) reachability ----------------------------------------------------------------

## RUNS FIRST, and it is the table five consecutive sessions wished they had run first.
## Every band below is measured against what the levers reach, so what they reach is
## established before anything is banded.
func _table_a_reachability() -> void:
	_heading("(a) WHAT THE THREE NEW LEVERS REACH")
	print("France, at new game, one commit. `span` is the lever's whole range; `revenue`")
	print("is what that tax collects at the top of it, in points of GDP.")
	print("")
	print("%-16s %10s %10s %12s %12s" % ["lever", "start", "max", "rev at max", "rev at start"])
	print("-".repeat(64))

	for key in ["capital_gains", "wealth"]:
		var start_state = _new_state("FRA")
		var top_state = _new_state("FRA")
		var top: float = C.WEALTH_RATE_MAX_PCT if key == "wealth" else 60.0
		Budget.commit(top_state, {"tax_rates_pct": {key: top}})
		print("%-16s %10.2f %10.2f %12.4f %12.4f" % [
			key,
			float(start_state.player().start_tax_rates_pct[key]),
			top,
			float(top_state.player().revenue_pct_gdp[key]),
			float(start_state.player().revenue_pct_gdp[key]),
		])

	var flat = _new_state("FRA")
	var steep = _new_state("FRA")
	Budget.commit(flat, {"tax_progressivity": K.PROGRESSIVITY_MIN})
	Budget.commit(steep, {"tax_progressivity": K.PROGRESSIVITY_MAX})
	print("%-16s %10.2f %10.2f %12.4f %12.4f" % [
		"brackets (income)", K.PROGRESSIVITY_BASE, K.PROGRESSIVITY_MAX,
		float(steep.player().revenue_pct_gdp["income"]),
		float(flat.player().revenue_pct_gdp["income"]),
	])
	print("-".repeat(64))
	print("")
	print("The roster's own measured Gini spread, which every band on the offset is read")
	print("against -- it is the only external scale this quantity has:")
	var lo := 999.0
	var hi := -999.0
	var widest := 0.0
	for nation_id in _loader.nations:
		var n = _loader.nations[nation_id]
		var g: float = float(n.inequality["gini_index"])
		var slope: float = float(n.inequality["gini_index_per_yr"])
		lo = minf(lo, g)
		hi = maxf(hi, g)
		widest = maxf(widest, absf(slope))
	print("  levels %.1f to %.1f, a span of %.1f points" % [lo, hi, hi - lo])
	print("  widest measured slope %.3f points a year, so %.3f over a five-year term" % [
		widest, widest * 5.0,
	])


# --- (b) the bracket revenue price ---------------------------------------------------

func _table_b_bracket_revenue_price() -> void:
	_heading("(b) P1 -- PROGRESSIVITY_BASE_BETA, the bracket lever's revenue price")

	print("BOUNDARY CHECK, before the band. The factor multiplies the income LINE inside")
	print("revenue_lines(); it adds no line and touches no other tax. France's revenue")
	print("dictionary after taking the brackets to the ceiling:")
	var state = _new_state("FRA")
	Budget.commit(state, {"tax_progressivity": K.PROGRESSIVITY_MAX})
	var keys: Array = []
	for k in state.player().revenue_pct_gdp:
		keys.append(str(k))
	keys.sort()
	print("  %s" % [keys])
	print("")

	# Closed form and therefore INVARIANT TO THE SHIPPED CONSTANT, which is V1.6b's own
	# correction: its first table rescaled the measured headline from the shipped value
	# and the passing interval MOVED when that value moved. The income line at deviation
	# d is `income_at_zero * (1 - beta * d)`, so the cost is exactly `income * beta * d`
	# whatever beta happens to be compiled in today.
	var base = _new_state("FRA")
	var income_at_zero: float = float(base.player().revenue_pct_gdp["income"])
	var d: float = K.PROGRESSIVITY_MAX - K.PROGRESSIVITY_BASE
	print("France's income tax collects %.4f points of GDP at its own schedule, and the" % income_at_zero)
	print("bracket lever's whole upward span is %.2f. Cost is exactly income x beta x d." % d)
	print("")
	print("%-10s %14s %10s %10s" % ["beta", "cost at max", "(i)>=0.50", "(ii)<=2.50"])
	print("-".repeat(48))
	var passing: Array[float] = []
	for i in range(1, 21):
		var beta: float = float(i) * 0.05
		var cost: float = income_at_zero * beta * d
		var i_ok: bool = cost >= 0.50
		var ii_ok: bool = cost <= 2.50
		if i_ok and ii_ok:
			passing.append(beta)
		print("%-10.2f %14.4f %10s %10s" % [beta, cost, _yn(i_ok), _yn(ii_ok)])
	print("-".repeat(48))
	if passing.is_empty():
		print("NO CANDIDATE PASSES -- the band is wrong or the channel cannot carry the price.")
	else:
		var mid: float = (passing[0] + passing[passing.size() - 1]) / 2.0
		print("passing interval [%.2f, %.2f], midpoint %.3f" % [passing[0], passing[passing.size() - 1], mid])
		print("shipped PROGRESSIVITY_BASE_BETA = %.2f" % K.PROGRESSIVITY_BASE_BETA)


# --- (c) the Gini fit ----------------------------------------------------------------

func _table_c_the_gini_fit() -> void:
	_heading("(c) P2 -- the three Gini betas, FITTED rather than banded")

	var widest := 0.0
	var widest_id := ""
	for nation_id in _loader.nations:
		var slope: float = float(_loader.nations[nation_id].inequality["gini_index_per_yr"])
		if absf(slope) > widest:
			widest = absf(slope)
			widest_id = nation_id
	var target: float = widest * 5.0

	print("THE ANCHOR is the widest measured roster drift over one five-year term:")
	print("  %s at %.3f points a year -> %.3f points over a term" % [widest_id, widest, target])
	print("")
	print("THE REACHABLE BUDGET the fit is taken at -- a left-wing programme, not the")
	print("maximum, because a clause satisfied only by the most extreme row is a bound and")
	print("not a selector (docs/credit-model.md clause (i)):")
	print("  brackets +%.2f, capital gains +%.1f points, wealth +%.2f points" % [
		REACHABLE_BRACKETS, REACHABLE_CAPITAL_GAINS, REACHABLE_WEALTH,
	])
	print("")
	print("THE SPLIT is equal thirds of the target, stated as an authoring choice: nothing")
	print("in the data ranks brackets against a wealth tax, so any other split would be a")
	print("claim the measurement cannot support.")
	print("")
	var third: float = target / 3.0
	print("%-26s %12s %14s %12s" % ["instrument", "reach", "solved beta", "shipped"])
	print("-".repeat(68))
	print("%-26s %12.2f %14.4f %12.4f" % [
		"GINI_PROGRESSIVITY_BETA", REACHABLE_BRACKETS, third / REACHABLE_BRACKETS,
		K.GINI_PROGRESSIVITY_BETA,
	])
	print("%-26s %12.2f %14.4f %12.4f" % [
		"GINI_RATE_BETA capital_gains", REACHABLE_CAPITAL_GAINS,
		third / REACHABLE_CAPITAL_GAINS, float(K.GINI_RATE_BETA["capital_gains"]),
	])
	print("%-26s %12.2f %14.4f %12.4f" % [
		"GINI_RATE_BETA wealth", REACHABLE_WEALTH, third / REACHABLE_WEALTH,
		float(K.GINI_RATE_BETA["wealth"]),
	])
	print("-".repeat(68))
	print("")

	var state = _new_state("FRA")
	Budget.commit(state, _reachable_budget())
	print("At the SHIPPED constants the reachable budget moves the index by %.4f points" % absf(Tax.gini_policy_offset(state.player())))
	print("against a target of %.4f. A fit CONVERGES where a band edge moves, so the" % target)
	print("shipped values are iterated until these two agree.")


# --- (d) the kill switch -------------------------------------------------------------

## *** THE KILL SWITCH. *** The offset must move something a player can see, and the one
## channel it has is docs/unrest-model.md's INEQUALITY_BETA -- exactly the channel V1.5c
## set its own kill switch against, which is the right one to reuse rather than invent.
##
## MEASURED ON A REACHABLE PATH, and the path is the thing V1.5c's own probe got wrong:
## its regimes provoked at month 1, lost the 2027 election, and the run stopped at month
## 16 before a stock converging at 0.07 had matured. So this measures a government that
## governs and then redistributes, on balance_probe.gd's `managed_then_*` shape.
func _table_d_kill_switch() -> void:
	_heading("(d) P2 KILL SWITCH -- does the offset move the date of the first strike?")

	print("Germany, whose measured Gini slope is the roster's widest riser and which is")
	print("the nation docs/unrest-model.md set INEQUALITY_BETA on, for the same reason: a")
	print("term that cannot be seen where it is largest cannot be seen anywhere.")
	print("")
	print("%-30s %14s %14s" % ["budget", "first act", "peak grievance"])
	print("-".repeat(60))

	# *** MEASURED ON AN ISOLATED PATH, AND THE FIRST VERSION WAS NOT. *** It committed
	# the real budgets and compared them, which cannot observe this channel at all: a
	# budget that moves the Gini also moves the deficit and two tax satisfactions, and
	# both reach hardship() far harder than the offset does. The flat-bracket row came
	# back CALMER than the quiet one -- flattening raises income revenue, which narrows
	# the deficit, which lifts `public_finances`. V1.5a's QUALITY_SCALE_PP failure
	# exactly: a band measured on a path that could not see the thing it was banding.
	#
	# So the offset is applied to the index DIRECTLY, with every budget line, every rate
	# and the schedule untouched, which makes every other issue bit-identical between the
	# runs and leaves this channel as the only difference.
	#
	# The grievance is also driven up to where an act is actually reachable, because
	# V1.5c's own probe measured a government the electorate had already thrown out and
	# read zero acts for fourteen years. A quiet Germany peaks well under the threshold,
	# so the question "does the offset move the DATE" is unanswerable there and the
	# honest form is the one below: how far the offset shifts the grievance, and whether
	# that shift crosses the threshold on a run that is otherwise near it.
	var offsets := {
		"quiet (offset 0.0)": 0.0,
		"regressive, reachable": _offset_of({"tax_progressivity": K.PROGRESSIVITY_MIN}),
		"redistributive, reachable": _offset_of(_reachable_budget()),
		"redistributive, every lever": _offset_of({
			"tax_progressivity": K.PROGRESSIVITY_MAX,
			"tax_rates_pct": {"capital_gains": 45.0, "wealth": C.WEALTH_RATE_MAX_PCT},
		}),
	}
	for label in offsets:
		var result := _run_isolated("DEU", float(offsets[label]), PROVOCATIVE)
		print("%-30s %14s %14.2f" % [
			label,
			("never" if int(result["month"]) < 0 else str(int(result["month"]))),
			float(result["peak"]),
		])
	print("-".repeat(60))
	print("")
	print("threshold %.1f, INEQUALITY_BETA %.2f" % [
		UnrestK.UNREST_THRESHOLD_PCT, UnrestK.INEQUALITY_BETA,
	])
	print("")
	print("The kill switch clears if the offset moves the peak grievance at all. If the")
	print("rows are identical the offset is a readout src/sim/ does not read, and the")
	print("three betas are DELETED -- V1.5b's treatment of DEPENDENCY_ELASTICITY.")


# --- (e) the clamp -------------------------------------------------------------------

func _table_e_the_clamp() -> void:
	_heading("(e) P3 -- GINI_POLICY_MAX_PT, a guard rail and not a selector")

	# Computed from the betas and the lever spans rather than read off a clamped call,
	# because reading the clamped value cannot tell you whether it bound.
	var unclamped: float = (
		K.GINI_PROGRESSIVITY_BETA * (K.PROGRESSIVITY_MAX - K.PROGRESSIVITY_BASE)
		+ float(K.GINI_RATE_BETA["capital_gains"]) * 60.0
		+ float(K.GINI_RATE_BETA["wealth"]) * C.WEALTH_RATE_MAX_PCT
	)
	var reachable = _new_state("FRA")
	Budget.commit(reachable, _reachable_budget())

	print("%-40s %12s" % ["", "points"])
	print("-".repeat(54))
	print("%-40s %12.4f" % ["reachable redistributive budget", absf(Tax.gini_policy_offset(reachable.player()))])
	print("%-40s %12.4f" % ["every lever at its ceiling, UNCLAMPED", unclamped])
	print("%-40s %12.4f" % ["GINI_POLICY_MAX_PT", K.GINI_POLICY_MAX_PT])
	print("-".repeat(54))
	print("")
	var reachable_offset: float = absf(Tax.gini_policy_offset(reachable.player()))
	if reachable_offset >= K.GINI_POLICY_MAX_PT:
		print("*** THE CLAMP BINDS ON REACHABLE PLAY. The clamp and not the model is")
		print("setting the number -- docs/defence-model.md's and docs/companies-model.md's")
		print("named failure. Either the clamp rises above the stack or the betas fall. ***")
	else:
		print("SLACK ON REACHABLE PLAY: %.4f against %.4f, a factor of %.1f." % [
			reachable_offset, K.GINI_POLICY_MAX_PT, K.GINI_POLICY_MAX_PT / reachable_offset,
		])
		print("")
		print("The ABSOLUTE CORNER -- every one of the three levers at its ceiling at once,")
		print("which is a tax revolution and not a budget -- reaches %.4f and is therefore" % unclamped)
		print("%s. That is what a guard rail is for and it is the same" % (
			"clamped" if unclamped > K.GINI_POLICY_MAX_PT else "still inside"
		))
		print("relationship IMPULSE_MAX_PCT has to the largest budget a player can commit.")
		print("The clamp says a president may not move their own country's inequality")
		print("further than the most equal nation in this game is from the least, and at")
		print("the corner the model would say otherwise, so the clamp is doing real work")
		print("rather than standing in for a number nobody chose.")


# --- (f) the two scales --------------------------------------------------------------

func _table_f_the_scales() -> void:
	_heading("(f) P4 -- TAX_SCALE_PP_BY_KEY for wealth and capital gains")

	print("BOUNDARY CHECK, before the band. opinion.gd prices every tax in POINTS OF RATE,")
	print("and TAX_BASE_SHARE puts wealth's base at %.2f against income's %.2f -- a stock" % [
		float(C.TAX_BASE_SHARE["wealth"]), float(C.TAX_BASE_SHARE["income"]),
	])
	print("against a flow. One shared scale is a units error and not a tuning choice, so")
	print("the question is which value and never whether.")
	print("")
	print("*** THE PRE-COMMITTED BAND COULD NOT SELECT, AND THAT IS THIS ROW'S FINDING. ***")
	print("It asked (i) that a reachable move clear the +-3.0 poll floor and (ii) that the")
	print("issue not be saturated at HALF the reachable move. Swept, clause (i) passed at")
	print("EVERY candidate with the identical approval move -- because the satisfaction is")
	print("clamped to [-1, +1] and the whole reachable move saturates it at every scale in")
	print("the grid, so (i) was measuring the clamp. Clause (ii) then reduces to the")
	print("arithmetic statement `candidate >= reach / 2`, which is not a measurement at")
	print("all. A test that could not fail beside a test that is a rearranged inequality:")
	print("V1.5a's CORRUPTION_DELIVERY_BETA failure and its QUALITY_SCALE_PP failure at")
	print("once, in one row.")
	print("")
	print("WHAT SHIPS INSTEAD IS A FIT, on V1.6a's rule -- a band edge moves when the grid")
	print("is widened, a fit converges -- and the thing fitted against is the model's OWN")
	print("accepted standard rather than something outside it, which is how V1.6b settled")
	print("its collinearity test. TAX_SCALE_PP is 8.0 for a tax whose lever runs from")
	print("France's own 20.0 to 70.0, so S5's accepted saturating move is this fraction of")
	print("the reachable upward span:")
	print("")
	var income_span: float = 70.0 - 20.0
	var ratio: float = OK.TAX_SCALE_PP / income_span
	print("  %.1f / %.1f = %.4f" % [OK.TAX_SCALE_PP, income_span, ratio])
	print("")
	print("%-16s %10s %10s %12s %12s %10s" % [
		"tax", "start", "ceiling", "span up", "fitted", "shipped",
	])
	print("-".repeat(74))
	for key in ["capital_gains", "wealth"]:
		var ceiling: float = C.WEALTH_RATE_MAX_PCT if key == "wealth" else 60.0
		var start_rate: float = float(_new_state("FRA").player().start_tax_rates_pct[key])
		var span: float = ceiling - start_rate
		print("%-16s %10.2f %10.2f %12.2f %12.4f %10.3f" % [
			key, start_rate, ceiling, span, span * ratio,
			float(OK.TAX_SCALE_PP_BY_KEY.get(key, OK.TAX_SCALE_PP)),
		])
	print("-".repeat(74))
	print("")
	print("It converges: the ratio is a property of two constants S5 and V1.6d already")
	print("fixed for other reasons, so refining or widening any grid cannot move it. And")
	print("it says the right thing -- a saturating move is the same FRACTION of what the")
	print("player can actually do, whatever scale the tax is written on.")
	print("")
	print("The three S5 measured take no entry, so the constant S5 measured still")
	print("describes them exactly:")
	for key in ["income", "corporate", "vat"]:
		print("  %-12s override present: %s" % [key, OK.TAX_SCALE_PP_BY_KEY.has(key)])


# --- (g) the two issue keys ----------------------------------------------------------

func _table_g_the_issue_keys() -> void:
	_heading("(g) P5 -- the ISSUE_KEYS question, asked TWICE at once")

	print("S10's finding was a RATIO: public_finances against the five spending lines.")
	print("V1.3d accepted +0.39 % for `europe`, V1.4c refused -1.46 % for `ownership`,")
	print("and V1.6b accepted +0.766 % for `inflation`. Measured at rest, size-weighted,")
	print("which is what the polling panel's agenda list and elections.gd's attribution()")
	print("both read.")
	print("")
	print("%-34s %10s %10s %10s" % ["rows present", "pub.fin", "spending", "ratio"])
	print("-".repeat(66))

	var variants := {
		"neither (the V1.6c model)": ["tax_capital_gains", "tax_wealth"],
		"capital gains only": ["tax_wealth"],
		"wealth only": ["tax_capital_gains"],
		"both (shipped)": [],
	}
	var base_ratio := 0.0
	for label in variants:
		var agenda := _national_agenda(variants[label])
		var pf: float = float(agenda.get("public_finances", 0.0))
		var sp := 0.0
		for issue in SPENDING_ISSUES:
			sp += float(agenda.get(issue, 0.0))
		var ratio: float = pf / sp
		if label == "neither (the V1.6c model)":
			base_ratio = ratio
		print("%-34s %10.4f %10.4f %10.4f" % [label, pf, sp, ratio])
	print("-".repeat(66))
	print("")
	for label in variants:
		if label == "neither (the V1.6c model)":
			continue
		var agenda := _national_agenda(variants[label])
		var pf: float = float(agenda.get("public_finances", 0.0))
		var sp := 0.0
		for issue in SPENDING_ISSUES:
			sp += float(agenda.get(issue, 0.0))
		print("  %-34s drift %+.3f pct" % [label, 100.0 * ((pf / sp) / base_ratio - 1.0)])
	print("")
	print("ACCEPT above +0.39 pct, REFUSE below -1.46 pct. A key that fails takes its")
	print("TAX_KEYS entry with it -- a tax with no issue key is a satisfaction nothing")
	print("reads, and a tax with no political price at all is free money.")
	print("")
	print("")
	print("CONTROL, on V1.6b's own device: the same two keys at a FLAT weight across all")
	print("six blocs. If the flat control drifts far less, the cause is the PROFILE the")
	print("rows are authored with and not the two extra keys as such -- and the profile is")
	print("content, which V1.3d fixed rather than reaching for a constant.")
	print("")
	var flat_agenda := _national_agenda_flat(0.06)
	var flat_pf: float = float(flat_agenda.get("public_finances", 0.0))
	var flat_sp := 0.0
	for issue in SPENDING_ISSUES:
		flat_sp += float(flat_agenda.get(issue, 0.0))
	print("  flat 0.06 on both keys, all six blocs   drift %+.3f pct" % (
		100.0 * ((flat_pf / flat_sp) / base_ratio - 1.0)
	))
	print("")

	var both := _national_agenda([])
	print("Agenda share taken by each new key: capital gains %.4f, wealth %.4f, against" % [
		float(both.get("tax_capital_gains", 0.0)), float(both.get("tax_wealth", 0.0)),
	])
	print("tax_corporate at %.4f and defence at %.4f." % [
		float(both.get("tax_corporate", 0.0)), float(both.get("defence", 0.0)),
	])


# --- (h) the deficit span ------------------------------------------------------------

func _table_h_the_deficit_span() -> void:
	_heading("(h) P6 ESCALATION TRIGGER -- what the two new taxes do to DEFICIT_SCALE_PP")

	print("DEFICIT_SCALE_PP is %.1f and was measured at S10 for a THREE-tax world." % OK.DEFICIT_SCALE_PP)
	print("docs/credit-model.md's clause (ii) already refused a channel that used half of")
	print("it. The question is how much of that span the two new taxes can move on their")
	print("own, in points of GDP of deficit.")
	print("")

	var floor_state = _new_state("FRA")
	var ceil_state = _new_state("FRA")
	Budget.commit(floor_state, {"tax_rates_pct": {"capital_gains": 0.0, "wealth": 0.0}})
	Budget.commit(ceil_state, {"tax_rates_pct": {
		"capital_gains": 60.0, "wealth": C.WEALTH_RATE_MAX_PCT,
	}})
	var swing: float = (
		floor_state.player().deficit_pct_gdp - ceil_state.player().deficit_pct_gdp
	)
	print("%-46s %10.4f" % ["deficit with both taxes abolished", floor_state.player().deficit_pct_gdp])
	print("%-46s %10.4f" % ["deficit with both at their ceiling", ceil_state.player().deficit_pct_gdp])
	print("%-46s %10.4f" % ["the whole new swing", swing])
	print("%-46s %10.4f" % ["as a share of DEFICIT_SCALE_PP", swing / OK.DEFICIT_SCALE_PP])
	print("")
	if swing > OK.DEFICIT_SCALE_PP:
		print("*** THE TRIGGER HAS FIRED: two taxes alone move the deficit further than the")
		print("whole span the issue is scaled over, so public_finances saturates on them")
		print("alone. This is a MODEL question and the session must name it. ***")
	else:
		print("Recorded, not retuned. Retuning DEFICIT_SCALE_PP re-baselines every opinion")
		print("constant measured since S5, and the pre-committed response to anything short")
		print("of exceeding the span is to write the number down.")


# --- helpers -------------------------------------------------------------------------

func _reachable_budget() -> Dictionary:
	return {
		"tax_progressivity": K.PROGRESSIVITY_BASE + REACHABLE_BRACKETS,
		"tax_rates_pct": {
			"capital_gains": 30.0 + REACHABLE_CAPITAL_GAINS,
			"wealth": REACHABLE_WEALTH,
		},
	}


## The size-weighted national agenda at rest, with `omit` removed from every bloc's base
## row -- which is how a key's absence is emulated without editing the constants file.
func _national_agenda(omit: Array) -> Dictionary:
	var zero_sat := {}
	for issue in OK.ISSUE_KEYS:
		zero_sat[issue] = 0.0

	var national := {}
	for bloc in OK.BLOC_KEYS:
		var row: Dictionary = (OK.BLOC_SALIENCE_BASE[bloc] as Dictionary).duplicate()
		for key in omit:
			row.erase(key)
		var weights: Dictionary = Opinion.salience_weights(row, zero_sat, OK.SALIENCE_GAIN)
		var size: float = float(OK.BLOC_SIZE[bloc])
		for issue in weights:
			national[issue] = float(national.get(issue, 0.0)) + size * float(weights[issue])
	return national


## Runs a nation forward under one budget and reports when the unions first act. The full
## tick list rather than a hand-rolled subset, because a hand-rolled month loop is what
## V1.6a found had been running the projection at a frozen clock for eleven sessions.
## The Gini policy offset a given budget would produce, without running anything.
func _offset_of(pending: Dictionary) -> float:
	var state = _new_state("DEU")
	Budget.commit(state, pending)
	return Tax.gini_policy_offset(state.player())


## The same agenda with the two new keys replaced by one flat weight on every bloc --
## V1.6b's control, which is what separates "the profile is wrong" from "a fourteenth key
## is wrong".
func _national_agenda_flat(weight: float) -> Dictionary:
	var zero_sat := {}
	for issue in OK.ISSUE_KEYS:
		zero_sat[issue] = 0.0

	var national := {}
	for bloc in OK.BLOC_KEYS:
		var row: Dictionary = (OK.BLOC_SALIENCE_BASE[bloc] as Dictionary).duplicate()
		row["tax_capital_gains"] = weight
		row["tax_wealth"] = weight
		var weights: Dictionary = Opinion.salience_weights(row, zero_sat, OK.SALIENCE_GAIN)
		var size: float = float(OK.BLOC_SIZE[bloc])
		for issue in weights:
			national[issue] = float(national.get(issue, 0.0)) + size * float(weights[issue])
	return national


## Runs a nation forward with `offset` applied to the inequality index and NOTHING else
## touched, so every other issue is bit-identical between two calls and this channel is
## the only difference between them.
func _run_isolated(nation_id: String, offset: float, provocation: Dictionary) -> Dictionary:
	var state = _new_state(nation_id)
	# The SAME provocation in every row, so it cancels between them and the offset stays
	# the only difference -- while lifting the grievance to where an act is reachable at
	# all. Without it every row reads "never" and the kill switch's own wording, which
	# asks about the DATE of the first strike, has nothing to measure. That a quiet
	# country never strikes is V1.5c's finding, not a defect here.
	if not provocation.is_empty():
		Budget.commit(state, provocation)
	state.player().gini_index += offset
	var first := -1
	var peak := 0.0
	for month in range(RUN_MONTHS):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Orgs.tick_month(state, _loader)
		Diplomacy.tick_month(state, _loader)
		Defence.tick_month(state)
		Companies.tick_month(state, _loader)
		Demography.tick_month(state)
		Society.tick_month(state)
		Unrest.tick_month(state)
		Inflation.tick_month(state)
		Media.tick_month(state, _loader)
		Opinion.tick_month(state)
		peak = maxf(peak, float(state.player().unrest_pct))
		if first < 0 and not state.unrest_acts.is_empty():
			first = month
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
	return {"month": first, "peak": peak}


func _new_state(nation_id: String):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	return state


func _yn(ok: bool) -> String:
	return "yes" if ok else "no"


func _heading(text: String) -> void:
	print("")
	print("=".repeat(78))
	print(text)
	print("=".repeat(78))
	print("")
