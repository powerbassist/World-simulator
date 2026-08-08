extends SceneTree

## V1.5b's measurement pass: the age structure, the denominator it puts under V1.5a's
## quality stock, and the migration lever that is the only verb able to close what
## ageing opens.
##
## EVERY BAND AND EVERY TIEBREAKER BELOW WAS FIXED BEFORE THE SWEEP RAN, and each one
## also states WHAT IT WOULD SAY IF EVERY CANDIDATE PASSED. That last clause is
## docs/decision-log.md's V1.5a rule, which this project reached by failing it twice in
## one session: a tiebreaker that is a tautology fires for every candidate, and a
## tiebreaker that is a bound constrains the range without ordering it. So:
##
##   (T1) MIGRATION_SHARE_BETA -- the session's ONE tuned constant.
##        BAND (i): a saturated stance held one 60-month term moves the `pensioners`
##          bloc approval row past the ±3.0 poll_noise floor. The BLOC ROW and not the
##          headline, because tools/society_probe.gd table (c) already established that
##          a single spending issue cannot reliably carry a headline price.
##        BAND (ii): a saturated OPEN stance holds the dependency ratio at or below
##          where it started, over the same term, for at least the median nation. A
##          lever that only damps leaves ageing as the permanent monotone charge
##          docs/defence-model.md names, and no value of this constant fixes that.
##        TIEBREAKER: strictly less legible on the pensions row than a saturated
##          corruption register is on health's -- their COMMON LANDING SITE, and the
##          only genuinely commensurable pair in the project. Take the LARGEST passing
##          candidate.
##        IF EVERY CANDIDATE PASSES: a strict ordering against a measured quantity
##          still selects a maximum, so this cannot fail the way V1.5a's two did. If it
##          still admits more than one row, the pre-committed second-order rule is that
##          the value must leave MIGRATION_STANCE_MAX slack at the passes reachable in
##          168 months.
##
##   (T2) DEPENDENCY_ELASTICITY["health"].
##        BAND: with the pensions entry held at 0.0 and every spending line untouched,
##          ageing alone over 60 months moves the `health` issue's widest bloc row past
##          ±3.0.
##        TIEBREAKER: strictly below 0.5 against the pensions entry's 1.0. Health costs
##          are age-graded but not per-pensioner, and a value near 1.0 is not a
##          distinguishable claim -- it is the pensions story at a different volume.
##        IF EVERY CANDIDATE PASSES: **DELETE THE ENTRY** and ship {"pensions": 1.0}
##          alone. This is the only band here whose all-pass answer is deletion rather
##          than selection, which is exactly why it is written down in advance --
##          AGREEMENT_ACCEPT_MIN's treatment at V1.3e, SUPPORT_SIGMA's, U6a's day budget.
##
##   (T3) The labour-force re-measure. NOT a band: companies_constants.LABOUR_FORCE_SHARE
##        is deleted, so V1.4a's measured 0.229/0.010 jobs spread moves whether or not
##        anyone likes the new figures. The pre-committed REQUIRED PROPERTY is that the
##        ORDERING survives -- if subsidising a retailer over a bank stops moving ~20x
##        what one industrial firm over another does, this is a model change and must be
##        reported as one rather than filed as a re-measure.
##
## ISOLATION IS ASSERTED AND PRINTED, NOT ASSUMED. V1.5a's headline band was measured on
## a path that could not observe what it banded -- raising a spending line necessarily
## widens the deficit -- so every table below that claims to isolate a channel prints a
## `!!` line if any other channel moved between its two runs.
##
## Not a test. Excluded from tools/run_tests.sh by design, so run it explicitly:
##   godot --headless --script res://tools/demography_probe.gd

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Demography = preload("res://src/sim/demography.gd")
const K = preload("res://src/sim/demography_constants.gd")
const Society = preload("res://src/sim/society.gd")
const SK = preload("res://src/sim/society_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const CompaniesK = preload("res://src/sim/companies_constants.gd")
const OK = preload("res://src/sim/opinion_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Legislature = preload("res://src/sim/legislature.gd")

const PLAYABLE := ["FRA", "DEU", "GBR"]
const TERM_MONTHS := 60
const RUN_MONTHS := 168

## Fractions of the population per year, at a saturated stance. Bracketed around the
## measured ageing slope itself -- France's old share rises 0.00366 a year -- because a
## lever able to hold the ratio flat has to live in the same decimal place.
##
## WIDENED AFTER THE FIRST SWEEP, and the reason is a correction to the method rather
## than to the range: the first grid stopped at 0.010, which was the only passing row
## AND the largest candidate, so the range and not the rule was choosing. Both bands
## are one-sided minimums, so a grid whose top row passes can never show whether it is
## the answer or the ceiling. See the tiebreaker correction below.
const BETA_CANDIDATES := [0.006, 0.008, 0.009, 0.010, 0.012, 0.016]

## Strictly below the pensions entry's 1.0, per the tiebreaker.
const ELASTICITY_CANDIDATES := [0.15, 0.35, 0.60, 1.00]

const NOISE_FLOOR := 3.0

var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		printerr("data did not load cleanly: %s" % [_loader.errors])
		quit(1)
		return

	_table_a_census()
	_table_b_drift()
	_table_t1_migration()
	_table_t2_health_elasticity()
	_table_t3_labour_force()
	_table_e_clamps()
	quit(0)


func _new_state(nation_id: String):
	return GameState.new_game(_loader, nation_id)


## main.gd's order, Demography immediately before Society.
func _step(state) -> void:
	Economy.tick_month(state)
	Budget.tick_month(state)
	Opinion.tick_month(state)
	Demography.tick_month(state)
	Society.tick_month(state)
	Cabinet.tick_month(state, _loader)


# --- (a) The census, and the session's actual finding --------------------------

## Not a sweep. This is the table that decides the shape of the whole session, and it
## is the answer to the decomposition's own stated reason for deferring V1.5b: "ten
## authored age structures with no dataset behind them would be the clustered
## coalition_position finding a block later".
##
## They are not authored. World Bank publishes all three series for all ten over
## 2015-2024, and tools/import_data.py was already downloading that window.
func _table_a_census() -> void:
	print("")
	print("(a) THE TEN PYRAMIDS, MEASURED -- the premise the deferral rested on")
	print("%-5s %8s %8s %8s %10s %10s %10s" % [
		"id", "young", "old", "working", "dep.ratio", "labour/pop", "pop %/yr"
	])
	var state = _new_state("FRA")
	var ids: Array = state.nations.keys()
	ids.sort()
	var ratios: Array[float] = []
	var labour: Array[float] = []
	for id in ids:
		var ns = state.nations[id]
		var ratio: float = Demography.dependency_ratio(ns)
		var share: float = Demography.labour_force(ns) / float(ns.population)
		ratios.append(ratio)
		labour.append(share)
		print("%-5s %8.4f %8.4f %8.4f %10.4f %10.4f %10.3f" % [
			id, ns.young_share, ns.old_share, Demography.working_share(ns),
			ratio, share, ns.pop_growth_pct,
		])
	ratios.sort()
	labour.sort()
	print("     dependency spread %.2fx   labour-share spread %.2fx (the deleted flat constant was 0.45)" % [
		ratios[ratios.size() - 1] / ratios[0], labour[labour.size() - 1] / labour[0],
	])


## The drift over a real horizon, with no player and no lever. This is what "an
## unavoidable curve" means in numbers, and it is what T1 has to be able to close.
func _table_b_drift() -> void:
	print("")
	print("(b) FOURTEEN YEARS OF AGEING, no player action")
	print("%-5s %10s %10s %10s %10s" % ["id", "ratio t0", "ratio t168", "factor", "labour/pop"])
	var state = _new_state("FRA")
	var ids: Array = state.nations.keys()
	ids.sort()
	var before := {}
	for id in ids:
		before[id] = Demography.dependency_ratio(state.nations[id])
	for month in RUN_MONTHS:
		_step(state)
	for id in ids:
		var ns = state.nations[id]
		print("%-5s %10.4f %10.4f %10.4f %10.4f" % [
			id, before[id], Demography.dependency_ratio(ns),
			Demography.dependency_factor(ns),
			Demography.labour_force(ns) / float(ns.population),
		])


# --- (T1) MIGRATION_SHARE_BETA -------------------------------------------------

## Swept by scaling the STANCE rather than by editing the constant, which is exact
## rather than approximate: migration_drift() is `BETA * stance / 12`, strictly linear
## in the product, so a candidate beta at saturation is the shipped beta at a stance of
## `candidate * MAX / shipped`. Everything downstream -- the clamps, the quality stock,
## the whole opinion model -- then runs for real.
##
## That is NOT the move society_probe.gd criticised in its own earlier draft. Rescaling
## an OUTPUT by shipped/candidate assumes the answer; rescaling an INPUT through an
## exactly linear term runs the real model.
func _effective_stance(beta: float) -> float:
	return beta * K.MIGRATION_STANCE_MAX / K.MIGRATION_SHARE_BETA


func _table_t1_migration() -> void:
	print("")
	print("(T1) MIGRATION_SHARE_BETA -- band (i) readable, band (ii) closable")
	print("%8s %12s %12s %12s %10s %8s" % [
		"beta", "pensioners", "headline", "ratio t0", "ratio t60", "verdict"
	])

	var rows: Array = []
	for beta in BETA_CANDIDATES:
		var quiet = _new_state("FRA")
		var loud = _new_state("FRA")
		# Tightening is the direction that shows up on a bloc row: it makes the country
		# age faster, which is the price the lever charges when it is used the popular
		# way. Band (ii) below reads the OPEN direction, which is the one that has to
		# close the ratchet.
		loud.player().migration_stance = -_effective_stance(beta)

		for month in TERM_MONTHS:
			_step(quiet)
			_step(loud)

		_assert_isolated("T1 beta=%s" % str(beta), quiet.player(), loud.player())

		var pensioners: float = (
			float(loud.player().bloc_approval["pensioners"])
			- float(quiet.player().bloc_approval["pensioners"])
		)
		var headline: float = (
			loud.player().overall_approval_pct - quiet.player().overall_approval_pct
		)

		# Band (ii), on a separate pair of runs: can the OPEN direction hold the ratio?
		var open_state = _new_state("FRA")
		var start_ratio: float = Demography.dependency_ratio(open_state.player())
		open_state.player().migration_stance = _effective_stance(beta)
		for month in TERM_MONTHS:
			_step(open_state)
		var end_ratio: float = Demography.dependency_ratio(open_state.player())

		var readable: bool = absf(pensioners) >= NOISE_FLOOR
		var closable: bool = end_ratio <= start_ratio
		var verdict := "PASS" if readable and closable else (
			"fail(i)" if not readable else "fail(ii)"
		)
		rows.append({"beta": beta, "pensioners": pensioners, "pass": readable and closable})
		print("%8.4f %12.2f %12.2f %12.4f %10.4f %8s" % [
			beta, pensioners, headline, start_ratio, end_ratio, verdict
		])

	# THE PRE-COMMITTED TIEBREAKER WAS ITSELF A BOUND, AND THIS IS WHERE IT SHOWED.
	#
	# It said: strictly less legible than a saturated corruption register on its own
	# widest bloc row, then take the LARGEST passing candidate. The reference is real
	# and it does bound the range -- but both bands above are one-sided MINIMUMS, so
	# every candidate above the threshold passes and "largest" simply returns the top
	# row of whatever grid was swept. The first grid stopped at 0.010; 0.010 was chosen;
	# widening the grid moves the answer. That is a range choosing a constant.
	#
	# docs/decision-log.md's V1.5a rule caught the two failures it was written for and
	# did NOT catch this one, so the rule is extended rather than merely obeyed: a
	# tiebreaker must strictly order the surviving rows AND its answer must not move
	# when the candidate range is widened. Check it by widening the grid, not by
	# reading the rule.
	#
	# THE CORRECTED SELECTOR, and it is forced rather than chosen: when both bands are
	# minimums, the SMALLEST passing candidate is the least-invasive lever that does the
	# job, and it is stable under widening. The corruption reference stays, demoted to
	# what it always was -- a ceiling.
	var corruption_row: float = _saturated_corruption_bloc_row()
	print("     ceiling reference: a saturated corruption register moves its widest bloc row %.2f" % corruption_row)
	var chosen := 0.0
	for row in rows:
		if not row["pass"]:
			continue
		if absf(row["pensioners"]) >= absf(corruption_row):
			print("     beta %.4f is not strictly below the corruption ceiling -- rejected" % row["beta"])
			continue
		if chosen == 0.0 or float(row["beta"]) < chosen:
			chosen = float(row["beta"])
	print("     SELECTOR CHOOSES: %.4f (SMALLEST passing candidate -- stable under widening)" % chosen)
	print("     shipped: %.4f" % K.MIGRATION_SHARE_BETA)


## A saturated corruption register on its own widest bloc row, under the CURRENT model
## -- V1.5a measured -3.29 before `pensions` carried a stock, and the two now interact
## through the same quality machinery.
func _saturated_corruption_bloc_row() -> float:
	var quiet = _new_state("FRA")
	var loud = _new_state("FRA")
	loud.player().corruption = SK.CORRUPTION_MAX
	for month in TERM_MONTHS:
		_step(quiet)
		_step(loud)
	var widest := 0.0
	for bloc in OK.BLOC_KEYS:
		var d: float = (
			float(loud.player().bloc_approval[bloc]) - float(quiet.player().bloc_approval[bloc])
		)
		if absf(d) > absf(widest):
			widest = d
	return widest


# --- (T2) DEPENDENCY_ELASTICITY["health"] --------------------------------------

## Isolated by holding the PENSIONS entry out of the comparison entirely: both runs
## carry the same pensions elasticity, so the pensions channel is bit-identical between
## them and every difference is health's. Without that the two quality lines contaminate
## each other through the shared headline, which is V1.5a's own defect repeated in the
## session written to avoid it.
##
## The health stock is driven at the candidate elasticity by overriding it after each
## Society tick. The stock is a first-order lag on a target, so recomputing the target
## at a different exponent and stepping it with the shipped step function is the real
## recursion at a different constant, not a rescaled output -- and everything that READS
## the stock, which is the whole of opinion.gd, runs untouched.
func _table_t2_health_elasticity() -> void:
	print("")
	print("(T2) DEPENDENCY_ELASTICITY['health'] -- all-pass answer is DELETE")
	print("%10s %14s %12s %10s %8s" % [
		"elasticity", "widest bloc", "headline", "ratio", "verdict"
	])

	var passing: Array[float] = []
	for e in ELASTICITY_CANDIDATES:
		var flat = _run_with_health_elasticity(0.0)
		var aged = _run_with_health_elasticity(e)
		_assert_isolated("T2 e=%s" % str(e), flat.player(), aged.player())

		var widest := 0.0
		for bloc in OK.BLOC_KEYS:
			var d: float = (
				float(aged.player().bloc_approval[bloc]) - float(flat.player().bloc_approval[bloc])
			)
			if absf(d) > absf(widest):
				widest = d
		var headline: float = (
			aged.player().overall_approval_pct - flat.player().overall_approval_pct
		)
		var ok: bool = absf(widest) >= NOISE_FLOOR and e < 0.5
		if ok:
			passing.append(e)
		print("%10.2f %14.2f %12.2f %10.4f %8s" % [
			e, widest, headline, Demography.dependency_factor(aged.player()),
			"PASS" if ok else ("fail band" if absf(widest) < NOISE_FLOOR else "fail tie"),
		])

	if passing.size() == ELASTICITY_CANDIDATES.size():
		print("     EVERY CANDIDATE PASSED -- the pre-committed answer is DELETE the health entry")
	elif passing.is_empty():
		print("     NO CANDIDATE PASSED -- KILL SWITCH: the entry is DELETED, not shipped at a decorative value")
	else:
		print("     passing: %s -- smallest satisfying the strict ratio ships: %.2f" % [
			str(passing), passing[0]
		])
	print("     shipped: %.2f" % float(SK.DEPENDENCY_ELASTICITY.get("health", 0.0)))


## One 60-month run in which the `health` stock is driven at `elasticity` rather than at
## the shipped one. Every other line, including `pensions`, runs the shipped model.
func _run_with_health_elasticity(elasticity: float):
	var state = _new_state("FRA")
	for month in TERM_MONTHS:
		_step(state)
		var ns = state.player()
		var factor: float = Demography.dependency_factor(ns)
		var target: float = clampf(
			float(ns.spending_pct_gdp.get("health", 0.0))
			* Cabinet.effectiveness(ns, "health")
			* Society.delivery_factor(ns)
			/ pow(factor, elasticity),
			SK.QUALITY_MIN, SK.QUALITY_MAX
		)
		ns.service_quality["health"] = Society.quality_step(
			float(ns.service_quality.get("health", 0.0)), target
		)
	return state


# --- (T3) The labour-force re-measure ------------------------------------------

## NOT a band. LABOUR_FORCE_SHARE is deleted, so V1.4a's figures move regardless; the
## pre-committed question is only whether the ORDERING survives. If it does this is a
## re-measure to be written into docs/companies-model.md; if it does not, it is a model
## change and has to be reported as one.
func _table_t3_labour_force() -> void:
	print("")
	print("(T3) THE JOBS SPREAD RE-MEASURED -- LABOUR_FORCE_SHARE 0.45 was one number for ten nations")
	print("%-5s %14s %14s %10s" % ["id", "old denominator", "new denominator", "ratio"])
	var state = _new_state("FRA")
	var ids: Array = state.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations[id]
		var old_denominator: float = float(ns.population) * 0.45
		var new_denominator: float = Demography.labour_force(ns)
		print("%-5s %14.0f %14.0f %10.4f" % [
			id, old_denominator, new_denominator, new_denominator / old_denominator
		])
	print("     a jobs figure measured at the old denominator is multiplied by 1/ratio")


# --- (e) Clamp slack -----------------------------------------------------------

## Measured rather than assumed, docs/defence-model.md's bill-clamp discipline. A clamp
## that binds in reachable play is the thing setting the number, which this project has
## now named five times.
func _table_e_clamps() -> void:
	print("")
	print("(e) CLAMP SLACK over 168 months at a saturated stance, both directions")
	var worst_young := 0.0
	var worst_old := 0.0
	var worst_working := 1.0
	var worst_factor := 1.0
	for nation_id in PLAYABLE:
		for direction in [1.0, -1.0]:
			var state = _new_state(nation_id)
			state.player().migration_stance = direction * K.MIGRATION_STANCE_MAX
			for month in RUN_MONTHS:
				_step(state)
				for id in state.nations:
					var ns = state.nations[id]
					worst_young = maxf(worst_young, ns.young_share)
					worst_old = maxf(worst_old, ns.old_share)
					worst_working = minf(worst_working, Demography.working_share(ns))
					worst_factor = maxf(worst_factor, Demography.dependency_factor(ns))
	print("     share ceiling      %.4f against SHARE_MAX %.4f" % [maxf(worst_young, worst_old), K.SHARE_MAX])
	print("     working floor      %.4f against WORKING_SHARE_MIN %.4f" % [worst_working, K.WORKING_SHARE_MIN])
	print("     factor ceiling     %.4f against DEPENDENCY_FACTOR_MAX %.4f" % [worst_factor, K.DEPENDENCY_FACTOR_MAX])


# --- Isolation -----------------------------------------------------------------

## Prints a `!!` line if anything OTHER than the channel under test moved between the
## two runs. V1.5a's headline band was measured through a path that necessarily widened
## the deficit, so "the quality channel alone" was never observable on it -- the failure
## this function exists to make visible rather than to trust a comment about.
func _assert_isolated(label: String, quiet, loud) -> void:
	var problems: Array[String] = []
	for key in quiet.spending_pct_gdp:
		if not is_equal_approx(
			float(quiet.spending_pct_gdp[key]), float(loud.spending_pct_gdp[key])
		):
			problems.append("spending.%s" % key)
	if not is_equal_approx(quiet.deficit_pct_gdp, loud.deficit_pct_gdp):
		problems.append("deficit_pct_gdp")
	if not is_equal_approx(quiet.bloc_burden, loud.bloc_burden):
		problems.append("bloc_burden")
	# Structurally 0.0 with no subsidy and no `business` law -- VERIFIED rather than
	# assumed, because that assumption is exactly the shape of the bug.
	if not (is_zero_approx(quiet.firm_jobs_offset_pct) and is_zero_approx(loud.firm_jobs_offset_pct)):
		problems.append("firm_jobs_offset_pct")
	if not problems.is_empty():
		print("     !! %s is NOT isolated -- also moved: %s" % [label, str(problems)])
