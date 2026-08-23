extends SceneTree

## Headless test: godot --headless --script res://tests/test_credit.gd
## Non-zero exit on any failure.
##
## V1.6c. The bond yield and the credit rating. Behavioural checks plus five
## architectural ones read off the source -- docs/people-model.md's,
## docs/calendar-model.md's, docs/cycle-model.md's and docs/inflation-model.md's idiom.
##
## The architectural five are what stop a later session quietly undoing the session's
## decisions: the spread is EXACTLY zero at new game (so the re-baseline stays bounded),
## the module is STATELESS (so the rating stays one read of the yield rather than a
## second machine), there is NO deficit term (so the sweep's deletion is not reinstated
## by symmetry), the DIVIDEND_YIELD identity holds (so V1.4c's obligation stays
## discharged on a rate rather than on a GDP share), and the yield reaches the BUDGET and
## never the ECONOMY.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Credit = preload("res://src/sim/credit.gd")
const K = preload("res://src/sim/credit_constants.gd")
const C = preload("res://src/sim/economy_constants.gd")
const CompaniesK = preload("res://src/sim/companies_constants.gd")

const MONTHS := 168
const START_YEAR := 2026

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_zero_at_new_game()
	_check_the_anchor_is_still_the_anchor()
	_check_debt_moves_the_yield_both_ways()
	_check_unrest_moves_the_yield()
	_check_the_scenario_override_starts_flat()
	_check_the_rating_is_a_read_of_the_yield()
	_check_the_rating_bands_are_ordered()
	_check_the_clamp_is_slack_on_a_quiet_run()
	_check_the_floor_stops_the_sign_inversion()
	_check_no_deficit_term()
	_check_stateless()
	_check_preloads()
	_check_single_reader()
	_check_the_dividend_identity()

	_finish()


## EXACTLY 0.0 for all ten, and exact equality rather than is_zero_approx() because this
## is the session's central claim rather than an approximation. Every balance number this
## project has ever measured is quoted against a flat DEBT_REAL_RATE_PCT of 2.0, and the
## spread reading zero at the epoch is what lets all of them keep their meaning.
## V1.4a's inert-channel property, and inflation's and the cycle's before it.
func _check_zero_at_new_game() -> void:
	var state = _new_state("FRA")
	for ns in state.nations.values():
		if Credit.spread_pct(ns) != 0.0:
			_fail("%s starts with a non-zero spread (%s) -- the register is not inert" % [
				ns.id, Credit.spread_pct(ns)
			])
		if Credit.yield_pct(ns) != C.DEBT_REAL_RATE_PCT:
			_fail("%s starts borrowing at %s against an anchor of %s" % [
				ns.id, Credit.yield_pct(ns), C.DEBT_REAL_RATE_PCT
			])
		if Credit.debt_gap_pct(ns) != 0.0:
			_fail("%s starts with a non-zero debt gap (%s)" % [ns.id, Credit.debt_gap_pct(ns)])


## The debt service the budget computes on frame 1 must be exactly what the pre-V1.6c
## model computed, which is the same claim from the other side and the one a balance
## re-run actually depends on.
func _check_the_anchor_is_still_the_anchor() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var expected: float = C.DEBT_REAL_RATE_PCT * ns.debt_eur_bn / ns.gdp_eur_bn
	if absf(ns.debt_service_pct_gdp - expected) > 1e-12:
		_fail("frame-1 debt service is %s where the flat anchor gives %s" % [
			ns.debt_service_pct_gdp, expected
		])


## SIGNED, and both directions are checked because the negative branch is what makes
## governing well a reward rather than merely not a punishment. It is also the branch a
## later session is most likely to clamp away by accident.
func _check_debt_moves_the_yield_both_ways() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var base := Credit.yield_pct(ns)

	ns.debt_eur_bn += 0.30 * ns.gdp_eur_bn
	var up := Credit.yield_pct(ns)
	if up <= base:
		_fail("30 points more debt did not raise the yield: %s against %s" % [up, base])
	var expected_up: float = base + K.YIELD_DEBT_BETA * 30.0
	if absf(up - expected_up) > 1e-6:
		_fail("the debt slope is not linear: %s against an expected %s" % [up, expected_up])

	ns.debt_eur_bn -= 0.60 * ns.gdp_eur_bn
	var down := Credit.yield_pct(ns)
	if down >= base:
		_fail("30 points less debt did not lower the yield: %s against %s" % [down, base])


func _check_unrest_moves_the_yield() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var base := Credit.yield_pct(ns)
	ns.unrest_pct = 50.0
	var raised := Credit.yield_pct(ns)
	var expected: float = base + K.YIELD_UNREST_BETA * 50.0
	if absf(raised - expected) > 1e-6:
		_fail("50 points of grievance gave a yield of %s against an expected %s" % [
			raised, expected
		])


## A scenario handing the player an inherited debt must start at a ZERO spread, because
## a France that has always carried 140 % of GDP is not a France that has just run it up.
## src/core/game_state.gd sets start_debt_to_gdp_pct from the OVERRIDDEN figure, and this
## is what stops a later session reading it off the nation file instead.
func _check_the_scenario_override_starts_flat() -> void:
	var scenario_id := ""
	for id in _loader.scenarios.keys():
		if _loader.scenarios[id].has_debt_to_gdp_pct:
			scenario_id = id
			break
	if scenario_id == "":
		# Not a failure: no shipped scenario overrides the debt today. The check below
		# is the one that matters and it is done by hand instead, so the property is
		# still pinned if the content changes either way.
		var state = _new_state("FRA")
		var ns = state.player()
		ns.debt_eur_bn = 1.40 * ns.gdp_eur_bn
		ns.start_debt_to_gdp_pct = 140.0
		if Credit.spread_pct(ns) != 0.0:
			_fail("a hand-built inherited debt does not read as a zero spread")
		return
	var scenario_state = GameState.new_game(_loader, "FRA", scenario_id)
	if Credit.spread_pct(scenario_state.player()) != 0.0:
		_fail("scenario %s starts in breach of a market it never borrowed from" % scenario_id)


func _check_the_rating_is_a_read_of_the_yield() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	if Credit.rating(ns) != _expected_rating(Credit.yield_pct(ns)):
		_fail("the rating at the anchor is %s, not the band the yield falls in" % Credit.rating(ns))
	# Every nation opens on the same letter, because every nation opens at the anchor.
	# That is the register saying something about the PLAYER rather than about content.
	for other in state.nations.values():
		if Credit.rating(other) != Credit.rating(ns):
			_fail("%s opens on %s where FRA opens on %s -- the letter is reading content" % [
				other.id, Credit.rating(other), Credit.rating(ns)
			])
	ns.debt_eur_bn *= 4.0
	if Credit.rating(ns) == _expected_rating(C.DEBT_REAL_RATE_PCT):
		_fail("quadrupling the debt did not move the rating off its opening band")


## Ceilings ascending, and the last one infinite. A table out of order silently returns
## the wrong letter for every yield above the first inversion, which is the kind of thing
## a content edit does and nothing else notices.
func _check_the_rating_bands_are_ordered() -> void:
	var previous := -INF
	for band in K.RATING_BANDS:
		var ceiling: float = float(band[0])
		if ceiling <= previous:
			_fail("RATING_BANDS is not ascending: %s after %s" % [ceiling, previous])
		previous = ceiling
	if not is_inf(float(K.RATING_BANDS[K.RATING_BANDS.size() - 1][0])):
		_fail("the last rating band must be open-ended, or a high enough yield has no letter")


## The clamp is a guard rail, so a quiet fourteen-year run must not touch either end.
## tools/credit_probe.gd table (h) measures the slack over the whole regime set; this is
## the cheap standing version of the same claim.
func _check_the_clamp_is_slack_on_a_quiet_run() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	for i in range(MONTHS):
		_advance(state)
		Economy.tick_month(state)
		Budget.tick_month(state)
		var y := Credit.yield_pct(ns)
		if y >= K.YIELD_MAX or y <= K.YIELD_MIN:
			_fail("a do-nothing run reached a clamp at month %d (%s)" % [i + 1, y])
			return


## THE FLOOR EXISTS TO STOP A SIGN INVERSION, not because of an opinion about how low
## real rates go. Budget.recompute() computes `yield * debt_eur_bn / gdp_eur_bn`, and a
## player who runs surpluses long enough drives the debt stock NEGATIVE -- so a negative
## yield on a negative stock would have a treasury with net assets PAYING interest on
## them. A later session lowering YIELD_MIN below zero turns this red.
func _check_the_floor_stops_the_sign_inversion() -> void:
	if K.YIELD_MIN < 0.0:
		_fail("YIELD_MIN is %s: a negative rate on a negative debt stock inverts the sign of the debt service line" % K.YIELD_MIN)
	var state = _new_state("FRA")
	var ns = state.player()
	ns.debt_eur_bn = -0.50 * ns.gdp_eur_bn
	Budget.recompute(state, ns)
	if ns.debt_service_pct_gdp > 0.0:
		_fail("a nation holding net assets is billed %s points of GDP in debt service" % ns.debt_service_pct_gdp)


## THE ROW ASKED FOR A DEFICIT TERM AND THE SWEEP DELETED IT. tools/credit_probe.gd
## table (d): the three clauses are mutually inconsistent, and table (j) then measured
## corr(debt gap, deficit gap) at 0.9948 against an accepted standard of 0.3185. A later
## session reinstating it by symmetry with the row turns this red and has to come and say
## why -- and it would be reinstating this session's only positive feedback loop with it,
## because debt service is INSIDE the deficit.
func _check_no_deficit_term() -> void:
	var source := FileAccess.get_file_as_string("res://src/sim/credit_constants.gd")
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.begins_with("const ") and stripped.contains("DEFICIT"):
			_fail("credit_constants.gd declares %s -- the deficit term was deleted by the sweep" % stripped)

	# And the behavioural half, which is what the constant's absence is FOR: moving the
	# deficit alone must not move the yield by anything.
	var state = _new_state("FRA")
	var ns = state.player()
	var before := Credit.yield_pct(ns)
	ns.deficit_pct_gdp += 5.0
	if Credit.yield_pct(ns) != before:
		_fail("five points of deficit moved the yield -- the deleted term is back")


## STATELESS, which is what keeps the rating one extra read of the yield rather than the
## second machine the V1.6 decomposition names as this session's split trigger. No tick,
## no accumulator, and nothing on NationState that credit.gd writes.
func _check_stateless() -> void:
	var source := FileAccess.get_file_as_string("res://src/sim/credit.gd")
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.begins_with("static func tick_month") or stripped.begins_with("func tick_month"):
			_fail("credit.gd has grown a tick_month() -- that is the decomposition's split trigger")
		if stripped.contains("ns.") and stripped.contains(" = ") and not stripped.contains("=="):
			_fail("credit.gd assigns to NationState: %s" % stripped)


func _check_preloads() -> void:
	var source := FileAccess.get_file_as_string("res://src/sim/credit.gd")
	var found: Array[String] = []
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.begins_with("const ") and stripped.contains("preload("):
			found.append(stripped)
	if found.size() != 2:
		_fail("credit.gd's preloads are %s -- it must be a leaf on its own constants and the anchor" % [found])
		return
	if not found[0].contains("credit_constants.gd") or not found[1].contains("economy_constants.gd"):
		_fail("credit.gd's preloads are %s -- expected credit_constants then economy_constants" % [found])


## THE YIELD REACHES THE BUDGET AND NEVER THE ECONOMY. debt_service_pct_gdp is not one of
## the five player-set spending lines, so Budget.commit() never writes it into
## demand_impulse_pct and economy.gd's growth sum gains no ninth addend. A session that
## wanted a growth channel would have to add one here, and this check makes it come and
## say so.
func _check_single_reader() -> void:
	var readers: Array[String] = []
	for path in _sim_files():
		if path == "res://src/sim/credit.gd" or path == "res://src/sim/budget.gd":
			continue
		var source := FileAccess.get_file_as_string(path)
		for line in source.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#") or stripped.begins_with("##"):
				continue
			if stripped.contains("Credit."):
				readers.append("%s: %s" % [path, stripped])
	if not readers.is_empty():
		_fail("the yield is read inside src/sim/ outside budget.gd: %s" % [readers])


## V1.4c'S OBLIGATION, PINNED AS AN IDENTITY RATHER THAN A COMMENT. V1.4c set the
## dividend yield ON PRICE exactly equal to DEBT_REAL_RATE_PCT so nationalisation was not
## free on both axes; V1.6c makes the BORROWING rate float and holds the dividend fixed a
## measured premium above the anchor. A later session moving either side turns this red.
func _check_the_dividend_identity() -> void:
	var on_price: float = CompaniesK.DIVIDEND_YIELD / CompaniesK.PRICE_TO_OUTPUT * 100.0
	var expected: float = C.DEBT_REAL_RATE_PCT + CompaniesK.EQUITY_PREMIUM_PCT
	if absf(on_price - expected) > 1e-9:
		_fail("the dividend yield on price is %s against an anchor-plus-premium of %s" % [
			on_price, expected
		])
	if CompaniesK.EQUITY_PREMIUM_PCT <= 0.0:
		_fail("EQUITY_PREMIUM_PCT is %s -- the kill switch fired and the model says there is no premium, which contradicts the identity above" % CompaniesK.EQUITY_PREMIUM_PCT)


func _expected_rating(y: float) -> String:
	for band in K.RATING_BANDS:
		if y <= float(band[0]):
			return String(band[1])
	return ""


func _sim_files() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open("res://src/sim")
	if dir == null:
		_fail("could not open res://src/sim")
		return out
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append("res://src/sim/" + name)
	return out


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _new_state(nation_id: String):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	return state


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_credit: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr(message)
	printerr("test_credit: %d check(s) failed" % _failures.size())
	quit(1)
