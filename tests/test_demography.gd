extends SceneTree

## V1.5b. The age structure as measured content, the dependency ratio it derives, the
## denominator that ratio puts under V1.5a's quality stock, and migration as the one
## verb able to close it. Model: docs/demography-model.md.
##
## The load-bearing assertions are the ones about what does NOT happen, and each is a
## failure this project has hit before or a rule it inherited:
##
##   - the dependency factor is EXACTLY 1.0 at new game for all ten, exact equality
##     and not is_zero_approx, which is V1.4a's standard and what makes the balance
##     re-run's prediction checkable rather than a hope;
##   - the three shares sum to EXACTLY 1.0 always, because working is a residual --
##     the property _apply_growth_to_sectors() buys the same way, and the reason
##     data/nations/ authors two shares and not three;
##   - src/sim/demography.gd never writes ns.migration_stance, asserted by reading the
##     file, which is what keeps the channel's single writer single;
##   - the ten pyramids genuinely DIFFER, which is the decomposition's own stated
##     fear (ten identical age structures would be V1.3e's clustered
##     `coalition_position` finding a block later) turned into a check;
##   - migration is reachable in BOTH directions through a law, because a
##     one-directional lever would leave ageing as the permanent monotone charge
##     docs/defence-model.md names;
##   - and demography.gd preloads nothing but its own constants -- the strictest leaf
##     in the project.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Demography = preload("res://src/sim/demography.gd")
const K = preload("res://src/sim/demography_constants.gd")
const Society = preload("res://src/sim/society.gd")
const SK = preload("res://src/sim/society_constants.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const OK = preload("res://src/sim/opinion_constants.gd")

const PLAYER := "FRA"
const RUN_MONTHS := 168

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_factor_is_exactly_one_at_new_game()
	_test_shares_always_sum_to_one()
	_test_the_ten_pyramids_differ()
	_test_the_ratio_rises_on_its_own()
	_test_quality_divides_by_the_ratio()
	_test_a_line_without_an_elasticity_is_untouched()
	_test_migration_closes_what_ageing_opens()
	_test_migration_is_signed_both_ways()
	_test_the_stance_has_one_writer()
	_test_demography_is_a_leaf()
	_test_bloc_size_is_still_authored()
	_test_labour_force_replaces_the_flat_constant()
	_test_content_loads()
	_finish()


func _new_state():
	return GameState.new_game(_loader, PLAYER)


# --- The structure ------------------------------------------------------------

## EXACT equality, not is_zero_approx. The whole layer is inert until the clock runs,
## and that claim is what the balance re-run's prediction rests on -- an approximate
## check would hide a seeded transient of exactly the kind defence.gd's
## equilibrium-not-zero comment exists to prevent.
func _test_factor_is_exactly_one_at_new_game() -> void:
	var state = _new_state()
	for id in state.nations:
		var ns = state.nations[id]
		if Demography.dependency_factor(ns) != 1.0:
			_fail("%s starts at dependency factor %s rather than exactly 1.0" % [
				id, str(Demography.dependency_factor(ns))
			])
		if ns.start_old_share != ns.old_share:
			_fail("%s start_old_share was not captured at the seeded value" % id)


## Working share is the RESIDUAL, so a conservation bug is structurally impossible
## rather than prevented by a check somebody has to remember to run. This asserts the
## structure rather than the arithmetic: if a later session stores a working share,
## the two answers can diverge and this goes red.
func _test_shares_always_sum_to_one() -> void:
	var state = _new_state()
	state.player().migration_stance = -K.MIGRATION_STANCE_MAX
	for month in RUN_MONTHS:
		Demography.tick_month(state)
		for id in state.nations:
			var ns = state.nations[id]
			var total: float = ns.young_share + ns.old_share + Demography.working_share(ns)
			if not is_equal_approx(total, 1.0):
				_fail("%s shares sum to %s in month %d, not 1.0" % [id, str(total), month])
				return


## The decomposition deferred this session partly because ten AUTHORED age structures
## would all look alike -- V1.3e's clustered `coalition_position` finding a block
## later. They are measured instead, so the check is that they actually differ, on the
## level AND on the slope, because a roster identical in either would make the
## dependency ratio content nobody can act on.
func _test_the_ten_pyramids_differ() -> void:
	var state = _new_state()
	var ratios: Array[float] = []
	var slopes: Array[float] = []
	for id in state.nations:
		ratios.append(Demography.dependency_ratio(state.nations[id]))
		slopes.append(state.nations[id].old_share_per_yr)
	ratios.sort()
	slopes.sort()

	# A 1.2x spread would be a rounding difference; the measured roster is 1.72x on the
	# level (LUX 0.225 to ITA 0.388) and wider still on the slope.
	if ratios[0] <= 0.0 or ratios[ratios.size() - 1] / ratios[0] < 1.3:
		_fail("the ten dependency ratios span only %sx -- the roster is effectively one pyramid" % [
			str(ratios[ratios.size() - 1] / maxf(ratios[0], 0.0001))
		])
	if is_equal_approx(slopes[0], slopes[slopes.size() - 1]):
		_fail("every nation ages at the same rate -- the slope is not measured")


## Ageing is unavoidable, which is the row's word for it, and it is what makes the
## migration lever load-bearing rather than decorative.
func _test_the_ratio_rises_on_its_own() -> void:
	var state = _new_state()
	var before: float = Demography.dependency_ratio(state.player())
	for month in RUN_MONTHS:
		Demography.tick_month(state)
	if Demography.dependency_ratio(state.player()) <= before:
		_fail("France's dependency ratio did not rise over fourteen years with no player action")
	if not is_zero_approx(state.player().migration_stance):
		_fail("a quiet run acquired a migration stance -- the lever has a second writer")


# --- The denominator ----------------------------------------------------------

## The session's whole mechanism, in one assertion: the same spending rate buys less
## as the country ages. docs/tiers/v1.md section 5 asks for ageing to drive a COST and
## spending_pct_gdp is a player-set RATE, so this is the only place a cost can appear.
##
## The spending line is never written, and that omission is the test -- V1.5a's
## corruption assertion, which is the same shape one register over.
func _test_quality_divides_by_the_ratio() -> void:
	var state = _new_state()
	var ns = state.player()
	var spend_before: float = float(ns.spending_pct_gdp["pensions"])
	var target_before: float = Society.quality_target(ns, "pensions")

	# Society as well as Demography, and in main.gd's order. The target falls as soon
	# as the ratio moves, but the STOCK only follows if the thing that steps it runs --
	# and the stock is what opinion.gd reads.
	for month in RUN_MONTHS:
		Demography.tick_month(state)
		Society.tick_month(state)

	if float(ns.spending_pct_gdp["pensions"]) != spend_before:
		_fail("the pensions spending line moved -- this test cannot attribute anything")
	if Society.quality_target(ns, "pensions") >= target_before:
		_fail("ageing did not lower the pensions target at unchanged spending -- the denominator reaches nothing")

	# And it reaches the player through the issue V1.5a wired, with zero lines changed
	# in opinion.gd -- which is what QUALITY_KEYS being a registry was for.
	if Society.quality_deviation(ns, "pensions") >= 0.0:
		_fail("the pensions stock did not fall, so nothing reaches the pensions issue")


## DEPENDENCY_ELASTICITY is a registry, sparse: a line with no entry divides by
## exactly 1.0. Without this the four lines that are not age-graded would quietly pick
## up a demographic term, which is the collision V1.4b named and V1.5a inherited.
func _test_a_line_without_an_elasticity_is_untouched() -> void:
	var state = _new_state()
	var ns = state.player()
	for month in RUN_MONTHS:
		Demography.tick_month(state)
	for key in ["education", "defence", "infrastructure"]:
		if Society.dependency_divisor(ns, key) != 1.0:
			_fail("'%s' has no DEPENDENCY_ELASTICITY entry but divides by %s" % [
				key, str(Society.dependency_divisor(ns, key))
			])
	if SK.DEPENDENCY_ELASTICITY.get("pensions", 0.0) != 1.0:
		_fail("the pensions elasticity is not 1.0 -- spend per dependent is definitional, not tuned")


# --- The lever ----------------------------------------------------------------

## The band MIGRATION_STANCE_MAX's argument rests on, stated as a property rather than
## left in a probe table: a saturated OPEN stance must hold the dependency ratio at or
## below where it started. A lever that only damps leaves ageing as the permanent
## monotone charge docs/defence-model.md names, and no constant value fixes that.
func _test_migration_closes_what_ageing_opens() -> void:
	var state = _new_state()
	var ns = state.player()
	var before: float = Demography.dependency_ratio(ns)
	ns.migration_stance = K.MIGRATION_STANCE_MAX
	for month in 60:
		Demography.tick_month(state)
	if Demography.dependency_ratio(ns) > before:
		_fail("a saturated migration stance did not hold France's dependency ratio flat over one term (%s -> %s) -- ageing is a charge no verb can close" % [
			str(before), str(Demography.dependency_ratio(ns))
		])


## Signed both ways. V1.4b's deregulation argument, plus the one V1.4b did not need:
## a one-directional stance makes the open half unreachable and the ratchet permanent.
func _test_migration_is_signed_both_ways() -> void:
	var open_state = _new_state()
	var shut_state = _new_state()
	open_state.player().migration_stance = 0.5
	shut_state.player().migration_stance = -0.5
	for month in 60:
		Demography.tick_month(open_state)
		Demography.tick_month(shut_state)
	if Demography.dependency_ratio(open_state.player()) >= Demography.dependency_ratio(shut_state.player()):
		_fail("opening and tightening did not move the ratio in opposite directions")
	if Demography.migration_drift(shut_state.player()) >= 0.0:
		_fail("a negative stance did not produce a negative drift")


## `migration_stance` has exactly ONE writer and it is Legislature.apply(). Asserted by
## reading the file, the idiom docs/people-model.md and docs/calendar-model.md both use
## for a property no runtime check expresses -- demography.gd only ever reads it.
func _test_the_stance_has_one_writer() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/demography.gd")
	if src == "":
		_fail("could not read src/sim/demography.gd")
		return
	for line in src.split("\n"):
		var stripped: String = line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.contains("migration_stance =") or stripped.contains("migration_stance +="):
			_fail("demography.gd writes ns.migration_stance -- the channel's single writer is Legislature.apply(), and this is the second")

	# And the channel is reachable through a law rather than only through a test. One
	# law at a time on a fresh state, NOT all of them onto one: the content is
	# deliberately signed in both directions, so applying the whole set nets to
	# roughly nothing and a test that summed them would pass on an empty channel.
	var found := 0
	for law in _loader.laws:
		if not law.effects.has("society"):
			continue
		if not (law.effects["society"] as Dictionary).has("migration"):
			continue
		found += 1
		var state = _new_state()
		var ns = state.player()
		Legislature.apply(state, ns, law, _loader)
		if is_zero_approx(ns.migration_stance):
			_fail("law '%s' names a migration figure but left the stance at zero" % law.id)
	if found == 0:
		_fail("no law in data/laws/ carries effects.society.migration -- the lever has no content")


## The strictest leaf in the project: its own constants and NOTHING else. society.gd
## preloads cabinet.gd; this preloads nobody, which is what lets game_state.gd,
## budget.gd, companies.gd and society.gd all reach it without a chain.
func _test_demography_is_a_leaf() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/demography.gd")
	if src == "":
		_fail("could not read src/sim/demography.gd")
		return
	for line in src.split("\n"):
		if not line.strip_edges().begins_with("const"):
			continue
		if not line.contains("preload("):
			continue
		if not line.contains("res://src/sim/demography_constants.gd"):
			_fail("demography.gd preloads something outside its own constants: %s" % line.strip_edges())


# --- What it replaced ---------------------------------------------------------

## companies_constants.LABOUR_FORCE_SHARE was one flat 0.45 for all ten and is deleted.
## Its own comment called it "the measured participation-times-working-age figure for
## the roster" -- true for France to three digits, and wrong for the roster. This pins
## that the replacement actually varies, so the deletion bought something.
func _test_labour_force_replaces_the_flat_constant() -> void:
	var state = _new_state()
	var shares: Array[float] = []
	for id in state.nations:
		var ns = state.nations[id]
		if ns.population <= 0.0:
			_fail("%s has no population" % id)
			continue
		shares.append(Demography.labour_force(ns) / float(ns.population))
	shares.sort()
	if shares.is_empty() or is_equal_approx(shares[0], shares[shares.size() - 1]):
		_fail("every nation's labour-force share is the same -- the flat constant was replaced by another flat constant")

	# And the deleted constant is really gone, so a later session cannot read a number
	# nothing maintains -- AGREEMENT_ACCEPT_MIN's treatment at V1.3e.
	var src := FileAccess.get_file_as_string("res://src/sim/companies_constants.gd")
	for line in src.split("\n"):
		if line.strip_edges().begins_with("const LABOUR_FORCE_SHARE"):
			_fail("LABOUR_FORCE_SHARE is still declared")


## V1.5b's recorded collision, pinned rather than left in a comment.
## opinion_constants.BLOC_SIZE["pensioners"] is authored and static; the measured 65+
## share is live and drifts. They are the same quantity with two writers, which is the
## failure this project names most often -- and the refusal to unify them is deliberate,
## because BLOC_SIZE is read by elections.gd twice, cabinet.gd, opinion.gd and
## polling_panel.gd, so a live share moves election RESULTS and re-baselines every
## opinion constant ever measured.
##
## This fails if a later session makes it live WITHOUT coming to say why -- the device
## tests/test_save_load.gd uses for SAVE_VERSION, applied to a constant.
func _test_bloc_size_is_still_authored() -> void:
	var state = _new_state()
	var ns = state.player()
	if is_equal_approx(float(OK.BLOC_SIZE["pensioners"]), ns.old_share):
		_fail("BLOC_SIZE['pensioners'] now equals the measured 65+ share -- if that is deliberate, say why beside BLOC_SIZE and delete this check")

	# And the disagreement is real rather than theoretical, which is what makes the
	# recorded consequence worth recording: it WIDENS over a run.
	var before: float = absf(float(OK.BLOC_SIZE["pensioners"]) - ns.old_share)
	for month in RUN_MONTHS:
		Demography.tick_month(state)
	if absf(float(OK.BLOC_SIZE["pensioners"]) - ns.old_share) <= before:
		_fail("the electorate/population disagreement did not widen over fourteen years, so the note beside BLOC_SIZE is wrong")


func _test_content_loads() -> void:
	var opens := false
	var tightens := false
	for law in _loader.laws:
		if not law.effects.has("society"):
			continue
		var society: Dictionary = law.effects["society"]
		if not society.has("migration"):
			continue
		if float(society["migration"]) > 0.0:
			opens = true
		if float(society["migration"]) < 0.0:
			tightens = true
	if not opens:
		_fail("no law opens migration -- the half that closes the ratchet is unreachable in play")
	if not tightens:
		_fail("no law tightens migration")

	# Every nation carries the imported block, so the layer is well defined for the
	# whole roster rather than for the three playable ones -- tests/test_defence.gd's
	# has_budget argument in a new place.
	for id in _loader.nations:
		var n = _loader.nations[id]
		if n.cohorts.is_empty():
			_fail("%s has no imported.cohorts" % id)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_demography: all checks passed")
	else:
		for f in _failures:
			print("FAIL: %s" % f)
		print("test_demography: %d failure(s)" % _failures.size())
	quit(1 if _failures.size() > 0 else 0)
