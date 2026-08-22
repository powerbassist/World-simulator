extends SceneTree

## V1.6e. Sectoral investment: the capital stock, the trend channel, the computed
## bill and the verb. Model: docs/sector-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen, and
## each is a property this session's shape rests on:
##
##   - the trend shift reads EXACTLY 0.0 -- not approximately -- for a fourteen-year
##     run in which nobody invests, which is what lets the whole layer go live with
##     the balance harness bit-identical across every existing regime;
##   - the level effect SURVIVES Economy._apply_growth_to_sectors()'s exact
##     reconciliation. That is the session's central structural claim: the row asked
##     for a write to `sector_output`, which the residual cancels inside the same
##     tick, and the shift is read at trend_pct() as well precisely so it does not
##     suffer the same fate. A test that only checked the mix would pass on a lever
##     that bought nothing;
##   - structural unemployment is BIT-IDENTICAL between an investing run and a quiet
##     one. The row states "no employment term" as a prohibition; it is a
##     consequence, and this is where that is pinned;
##   - the bill is priced on the standing INTENSITY and not on the accumulated
##     capital, so a withdrawal stops the money the same month while the capital
##     keeps working;
##   - a `business` law cannot reach this register and this verb cannot reach
##     `regulation_burden` or any firm's `share` -- V1.4's three single writers
##     survive a fourth register arriving beside them.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Investment = preload("res://src/sim/investment.gd")
const K = preload("res://src/sim/investment_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Companies = preload("res://src/sim/companies.gd")
const Legislature = preload("res://src/sim/legislature.gd")

const PLAYER := "FRA"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_test_content_loads()
	_test_every_sector_is_reachable_by_content()
	_test_register_seeds_empty()
	_test_uninvested_shift_is_exactly_zero()
	_test_a_long_run_stays_exactly_zero()
	_test_capital_converges_on_the_intensity()
	_test_the_bill_reaches_the_budget()
	_test_the_level_effect_survives_the_residual()
	_test_the_two_read_sites_agree()
	_test_structural_unemployment_is_untouched()
	_test_the_module_writes_nothing_on_the_employment_path()
	_test_withdraw_stops_the_bill_and_keeps_the_capital()
	_test_the_national_bound_scales_the_whole_set()
	_test_verb_refuses_when_unavailable()
	_test_the_nine_never_invest()
	_test_no_law_ever_moves_the_register()
	_test_investment_never_moves_a_share_or_a_burden()
	_test_the_module_is_a_leaf()
	_test_it_reaches_the_WHOLE_sector()
	_finish()


func _finish() -> void:
	if _failures.is_empty():
		print("test_sectors: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _new_state():
	return GameState.new_game(_loader, PLAYER)


func _action(id: String):
	for a in _loader.investment_actions:
		if a.id == id:
			return a
	return null


## One month of everything this layer touches, in main.gd's order.
func _tick(state) -> void:
	Economy.tick_month(state)
	Budget.tick_month(state)
	Investment.tick_month(state)


# --- Content ---------------------------------------------------------------------

func _test_content_loads() -> void:
	if _loader.investment_actions.is_empty():
		_fail("no investment actions loaded")
	for id in ["farm_modernisation", "reindustrialisation", "end_services_programme"]:
		if _action(id) == null:
			_fail("investment action '%s' is missing" % id)

	for a in _loader.investment_actions:
		var terms: Dictionary = a.effects.get("investment", {})
		if not EK.SECTOR_TREND.has(String(terms.get("sector", ""))):
			_fail("%s names sector '%s', which is not one of the three" % [
				a.id, str(terms.get("sector", ""))
			])
		# The paired-setter rule the op table encodes: a clearer names no dial.
		if String(terms.get("op", "")) == "withdraw" and terms.has("intensity"):
			_fail("%s is a withdraw and carries an intensity" % a.id)


## THE SECTOR IS AUTHORED RATHER THAN PASSED AS A TARGET, so "every sector can be
## invested in" is a property of the CONTENT and not of the code -- exactly the kind
## of claim a shipped file can quietly stop satisfying. A sector with a programme
## and no way to end it would be worse: a permanent monotone charge, which is
## docs/defence-model.md's named failure.
func _test_every_sector_is_reachable_by_content() -> void:
	for sector in EK.SECTOR_TREND.keys():
		var invests := 0
		var withdraws := 0
		for a in _loader.investment_actions:
			var terms: Dictionary = a.effects.get("investment", {})
			if String(terms.get("sector", "")) != String(sector):
				continue
			if String(terms.get("op", "")) == "invest":
				invests += 1
			elif String(terms.get("op", "")) == "withdraw":
				withdraws += 1
		if invests < 1:
			_fail("sector '%s' has no investment action" % sector)
		if withdraws < 1:
			_fail("sector '%s' can be invested in and never ended" % sector)


# --- The inert case ----------------------------------------------------------------

func _test_register_seeds_empty() -> void:
	var state = _new_state()
	for id in state.nations.keys():
		var ns = state.nations[id]
		for sector in EK.SECTOR_TREND.keys():
			if Investment.intensity_of(ns, String(sector)) != 0.0:
				_fail("%s seeded %s with a standing programme" % [id, sector])
			if Investment.capital_of(ns, String(sector)) != 0.0:
				_fail("%s seeded %s with capital" % [id, sector])


## EXACT equality, not is_zero_approx(), and the distinction is the point: this is
## what makes the balance re-run's bit-identity provable rather than likely.
## docs/companies-model.md's own property, one block later.
func _test_uninvested_shift_is_exactly_zero() -> void:
	var state = _new_state()
	Investment.tick_month(state)
	for id in state.nations.keys():
		var ns = state.nations[id]
		if Investment.national_trend_shift_pct(ns) != 0.0:
			_fail("%s has a trend shift with nothing invested" % id)
		for sector in EK.SECTOR_TREND.keys():
			if float(Investment.sector_trend_shift(ns).get(sector, 0.0)) != 0.0:
				_fail("%s %s has a shift with nothing invested" % [id, sector])
		if ns.investment_bill_pct_gdp != 0.0:
			_fail("%s is billed with nothing invested" % id)


func _test_a_long_run_stays_exactly_zero() -> void:
	var state = _new_state()
	for _m in range(168):
		_tick(state)
	for id in state.nations.keys():
		var ns = state.nations[id]
		if Investment.national_trend_shift_pct(ns) != 0.0 or ns.investment_bill_pct_gdp != 0.0:
			_fail("%s moved over fourteen years with nobody investing" % id)


# --- The stock and the bill ----------------------------------------------------------

func _test_capital_converges_on_the_intensity() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	var action = _action("reindustrialisation")
	Investment.execute(state, ns, _loader.investment_actions, action)

	if not is_equal_approx(Investment.intensity_of(ns, "industry"), 1.0):
		_fail("a full-intensity programme did not set the intensity")
	if Investment.capital_of(ns, "industry") != 0.0:
		_fail("capital moved in the month the programme was signed")

	var previous := 0.0
	for _m in range(120):
		_tick(state)
		var capital := Investment.capital_of(ns, "industry")
		if capital < previous:
			_fail("capital fell while the programme was running")
		if capital > 1.0:
			_fail("capital passed its own normalised ceiling: %.4f" % capital)
		previous = capital

	# Bounded BY CONSTRUCTION at 1.0 rather than by a clamp, so ten years of full
	# intensity gets close and never over.
	if previous < 0.90:
		_fail("ten years of full intensity reached only %.4f of the endpoint" % previous)

	# The other two sectors are untouched: a programme is per sector, and a register
	# that leaked across sectors would make WHICH SECTOR meaningless.
	for sector in ["agriculture", "services"]:
		if Investment.capital_of(ns, sector) != 0.0:
			_fail("investing in industry built capital in %s" % sector)


func _test_the_bill_reaches_the_budget() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Investment.execute(state, ns, _loader.investment_actions, _action("reindustrialisation"))

	var before: float = ns.total_spending_pct_gdp
	Investment.tick_month(state)
	Budget.recompute(state, ns)

	# THE BILL SCALES WITH THE SECTOR'S OWN SHARE OF GDP, which is the probe's model
	# correction: a flat fee bought sixty-three times more in services than in
	# agriculture for the same money. Asserted against the arithmetic rather than
	# against a remembered number, so a later session changing the scaling has to come
	# and say why.
	var share: float = float(ns.sector_output["industry"]) / ns.gdp_eur_bn
	if not is_equal_approx(ns.investment_bill_pct_gdp, K.INVESTMENT_COST_PCT_GDP * share):
		_fail("a full-intensity industry programme billed %.4f against %.4f" % [
			ns.investment_bill_pct_gdp, K.INVESTMENT_COST_PCT_GDP * share
		])
	if ns.total_spending_pct_gdp <= before:
		_fail("the investment bill did not reach total spending")

	# BOUNDED BY CONSTRUCTION, which is why INVESTMENT_BILL_MAX_PCT_GDP was deleted
	# rather than left unused. The three sector shares sum to exactly 1.0 by
	# Economy._apply_growth_to_sectors()'s reconciliation, so every sector at full
	# intensity is one economy's worth and no clamp is reachable.
	var everything = _new_state()
	var ens = everything.nations[PLAYER]
	for sector in EK.SECTOR_TREND.keys():
		ens.sector_investment[sector]["intensity"] = 1.0
	Investment.tick_month(everything)
	if ens.investment_bill_pct_gdp > K.INVESTMENT_COST_PCT_GDP + 1e-9:
		_fail("the whole-economy bill %.6f exceeded its constructed bound %.6f" % [
			ens.investment_bill_pct_gdp, K.INVESTMENT_COST_PCT_GDP
		])
	if absf(ens.investment_bill_pct_gdp - K.INVESTMENT_COST_PCT_GDP) > 1e-9:
		_fail("the whole-economy bill %.6f is not exactly the cost constant" % ens.investment_bill_pct_gdp)


# --- The channel ---------------------------------------------------------------------

## THE SESSION'S CENTRAL STRUCTURAL CLAIM. _apply_growth_to_sectors() reconciles the
## three sectors against the month's GDP target exactly, so a per-sector rate that
## did not also reach trend_pct() would be cancelled by the cyclical residual inside
## the same tick and buy nothing at all. Measured against a control that differs in
## the programme and in nothing else.
func _test_the_level_effect_survives_the_residual() -> void:
	var quiet = _new_state()
	var investing = _new_state()
	var ns = investing.nations[PLAYER]
	Investment.execute(investing, ns, _loader.investment_actions, _action("reindustrialisation"))

	for _m in range(120):
		_tick(quiet)
		_tick(investing)

	var quiet_ns = quiet.nations[PLAYER]
	if ns.gdp_eur_bn <= quiet_ns.gdp_eur_bn:
		_fail("ten years of full industrial investment bought no GDP: %.2f against %.2f" % [
			ns.gdp_eur_bn, quiet_ns.gdp_eur_bn
		])
	# It moves POTENTIAL, where V1.6a's cycle deliberately does not. A term that
	# raised output around an unchanged potential would be a business cycle with a
	# budget line.
	if ns.potential_gdp_eur_bn <= quiet_ns.potential_gdp_eur_bn:
		_fail("investment did not raise potential")
	if ns.trend_annual_pct <= quiet_ns.trend_annual_pct:
		_fail("investment did not raise trend")


## The two read sites must agree, because `after_trend` is compared against a GDP
## target built from trend_pct(). If they drifted, the residual would silently
## absorb the difference and the composition the player sees would not be the one
## the programme bought -- data/diplomatic-actions/agreements.json's own note, from
## the other direction.
func _test_the_two_read_sites_agree() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Investment.execute(state, ns, _loader.investment_actions, _action("knowledge_economy_plan"))
	for _m in range(60):
		_tick(state)

	var shifts := Investment.sector_trend_shift(ns)
	var weighted := 0.0
	for sector in shifts.keys():
		weighted += float(shifts[sector]) * float(ns.sector_output.get(sector, 0.0)) / ns.gdp_eur_bn
	if absf(weighted - Investment.national_trend_shift_pct(ns)) > 1e-12:
		_fail("the per-sector shifts and the national shift disagree")

	# And the national figure is genuinely inside the trend the economy is running.
	var without: float = 0.0
	for key in EK.SECTOR_TREND.keys():
		without += float(ns.sector_output.get(key, 0.0)) / ns.gdp_eur_bn * float(EK.SECTOR_TREND[key])
	without += ns.potential_shift_pct
	if absf(Economy.trend_pct(ns) - (without + weighted)) > 1e-12:
		_fail("trend_pct() does not carry the investment shift")


## THE ROW SAYS "NO EMPLOYMENT TERM" AND THIS IS WHERE THAT IS PINNED. Okun reads
## `growth - trend`, so a term raising both leaves the gap where it was in the long
## run; structural unemployment reads the income-tax wedge, the law offset and the
## firm layer, none of which this module touches. Bit-identical, not approximately.
func _test_structural_unemployment_is_untouched() -> void:
	var quiet = _new_state()
	var investing = _new_state()
	var ns = investing.nations[PLAYER]
	Investment.execute(investing, ns, _loader.investment_actions, _action("reindustrialisation"))

	for _m in range(120):
		_tick(quiet)
		_tick(investing)

	if ns.structural_unemployment_pct != quiet.nations[PLAYER].structural_unemployment_pct:
		_fail("investment moved structural unemployment: %.9f against %.9f" % [
			ns.structural_unemployment_pct, quiet.nations[PLAYER].structural_unemployment_pct
		])
	if ns.firm_jobs_offset_pct != quiet.nations[PLAYER].firm_jobs_offset_pct:
		_fail("investment moved the firm jobs offset")


## Read the file, so a later session adding a jobs term has to come and say why
## rather than doing it quietly. tests/test_tax.gd's and tests/test_people.gd's
## device.
func _test_the_module_writes_nothing_on_the_employment_path() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/investment.gd")
	if src.is_empty():
		_fail("could not read src/sim/investment.gd")
		return
	for forbidden in [
		"unemployment_pct =", "structural_unemployment", "headcount", "labour_force",
		"firm_jobs_offset_pct =",
	]:
		if src.contains(forbidden):
			_fail("investment.gd reaches the employment path via '%s'" % forbidden)


func _test_withdraw_stops_the_bill_and_keeps_the_capital() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	Investment.execute(state, ns, _loader.investment_actions, _action("industrial_renewal"))
	for _m in range(60):
		_tick(state)

	var built := Investment.capital_of(ns, "industry")
	if built <= 0.0:
		_fail("five years of investment built nothing")

	Investment.execute(state, ns, _loader.investment_actions, _action("end_industrial_programme"))
	Investment.tick_month(state)

	# THE BILL IS PRICED ON THE INTENSITY AND NOT ON THE CAPITAL, so it stops the same
	# month. A bill on the stock would keep charging for something already built.
	if ns.investment_bill_pct_gdp != 0.0:
		_fail("the bill survived the withdrawal: %.4f" % ns.investment_bill_pct_gdp)
	# And the capital does not: a withdrawal is not a demolition. Twelve months on it
	# must still be doing most of its work, or the lever is decorative --
	# docs/scenario-model.md's failure.
	for _m in range(12):
		_tick(state)
	var left := Investment.capital_of(ns, "industry")
	if left <= 0.0:
		_fail("capital vanished the moment the money stopped")
	if left / built < 0.50:
		_fail("a year after withdrawal only %.0f %% of the capital is left" % (100.0 * left / built))


## The bound is applied by SCALING the whole set rather than clipping one entry, so
## the two read sites cannot disagree while it binds. Driven from a displaced state
## because no reachable programme reaches it -- which is what a guard rail is.
func _test_the_national_bound_scales_the_whole_set() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	for sector in EK.SECTOR_TREND.keys():
		ns.sector_investment[sector] = {"intensity": 1.0, "capital": 99.0}

	var shifts := Investment.sector_trend_shift(ns)
	var weighted := 0.0
	for sector in shifts.keys():
		weighted += float(shifts[sector]) * float(ns.sector_output.get(sector, 0.0)) / ns.gdp_eur_bn
	if weighted > K.SECTOR_TREND_MAX_PCT + 1e-9:
		_fail("the national bound did not hold: %.4f" % weighted)
	if absf(weighted - Investment.national_trend_shift_pct(ns)) > 1e-12:
		_fail("the two read sites disagree while the bound binds")
	# Scaled, not clipped: the mix is preserved, so the ratio between two sectors'
	# shifts is what the capital says it is.
	var ratio: float = float(shifts["industry"]) / float(shifts["services"])
	if absf(ratio - 1.0) > 1e-9:
		_fail("equal capital produced unequal shifts under the bound")


# --- The verb ------------------------------------------------------------------------

func _test_verb_refuses_when_unavailable() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	# `end_industrial_programme` requires a programme to end.
	var result := Investment.execute(
		state, ns, _loader.investment_actions, _action("end_industrial_programme")
	)
	if result.get("applied", false) or not result.get("refused", false):
		_fail("a withdrawal with nothing running was applied")

	Investment.execute(state, ns, _loader.investment_actions, _action("industrial_renewal"))
	# And a second programme on the same sector is gated by `investment_active`.
	var again := Investment.execute(
		state, ns, _loader.investment_actions, _action("reindustrialisation")
	)
	if again.get("applied", false):
		_fail("a second programme was signed on a sector that already had one")
	if not is_equal_approx(Investment.intensity_of(ns, "industry"), 0.55):
		_fail("the refused action moved the register anyway")


## The nine have no agenda term for this verb and V1.6e ships none, which is what
## keeps the balance re-run bit-identical. Recorded as a limitation in
## docs/sector-model.md and pinned here.
func _test_the_nine_never_invest() -> void:
	var state = _new_state()
	for _m in range(168):
		_tick(state)
	for id in state.nations.keys():
		if id == PLAYER:
			continue
		for sector in EK.SECTOR_TREND.keys():
			if Investment.intensity_of(state.nations[id], String(sector)) != 0.0:
				_fail("%s invested in %s unprompted" % [id, sector])


# --- The four single writers ------------------------------------------------------------

## V1.4's three registers each have exactly one writer, and a fourth register
## arriving beside them must not become a second writer of any of them. Twenty
## rounds of every `business` law in the file, then the whole investment register
## must be exactly where it started.
func _test_no_law_ever_moves_the_register() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]
	for _round in range(20):
		for law in _loader.laws:
			Legislature.apply(state, ns, law, _loader)
	for sector in EK.SECTOR_TREND.keys():
		if Investment.intensity_of(ns, String(sector)) != 0.0:
			_fail("a law started an investment programme in %s" % sector)
		if Investment.capital_of(ns, String(sector)) != 0.0:
			_fail("a law built capital in %s" % sector)


func _test_investment_never_moves_a_share_or_a_burden() -> void:
	var state = _new_state()
	var ns = state.nations[PLAYER]

	var shares_before := {}
	for company in _loader.companies.get(PLAYER, []):
		shares_before[company.id] = Companies.share_of(ns, company.id)
	var burdens_before: Dictionary = ns.regulation_burden.duplicate(true)

	for a in _loader.investment_actions:
		Investment.execute(state, ns, _loader.investment_actions, a)
	for _m in range(60):
		_tick(state)

	for company in _loader.companies.get(PLAYER, []):
		if Companies.share_of(ns, company.id) != float(shares_before[company.id]):
			_fail("investment moved %s's share" % company.id)
	for sector in ns.regulation_burden.keys():
		if float(ns.regulation_burden[sector]) != float(burdens_before.get(sector, 0.0)):
			_fail("investment moved the regulation burden on %s" % sector)


## A leaf, asserted by reading the file. src/sim/investment.gd may preload its own
## constants and economy_constants.gd and nothing else in src/sim/ -- the property
## src/sim/calendar.gd's own test pins, and the reason this module can be called
## from economy.gd without a cycle.
func _test_the_module_is_a_leaf() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/investment.gd")
	if src.is_empty():
		_fail("could not read src/sim/investment.gd")
		return
	var allowed := [
		"res://src/sim/investment_constants.gd", "res://src/sim/economy_constants.gd",
	]
	for line in src.split("\n"):
		if not line.begins_with("const ") or not line.contains("preload("):
			continue
		var path := line.get_slice("\"", 1)
		if not allowed.has(path):
			_fail("investment.gd preloads '%s', which would stop it being a leaf" % path)


## THE LINE docs/tiers/v1.md SECTION 6 SAYS THIS BULLET MUST NOT CROSS, asserted rather
## than left to prose. V1.4b's regulation reaches only the NAMED partition -- a sector a
## quarter named is a quarter as regulable, because companies.gd walks the register --
## and that bound is one of the two things separating a sector burden from this lever.
##
## This one reads `ns.sector_output` and nothing else, so it reaches the unnamed residual
## too and a nation with no data/companies/ file can still be invested in. Measured by
## emptying the firm register outright: the trend shift must not move by a bit.
func _test_it_reaches_the_WHOLE_sector() -> void:
	var named = _new_state()
	var unnamed = _new_state()
	for state in [named, unnamed]:
		var n = state.nations[PLAYER]
		Investment.execute(state, n, _loader.investment_actions, _action("reindustrialisation"))
	# The whole firm register removed, which is what seven of the ten nations already look
	# like and what V1.4b's burden would be a quarter as strong against.
	unnamed.nations[PLAYER].companies = {}

	for _m in range(60):
		_tick(named)
		_tick(unnamed)

	var a: float = Investment.national_trend_shift_pct(named.nations[PLAYER])
	var b: float = Investment.national_trend_shift_pct(unnamed.nations[PLAYER])
	if a != b:
		_fail("the trend shift reads the firm register: %.9f named against %.9f unnamed" % [a, b])
	if is_zero_approx(a):
		_fail("both runs moved nothing, so this check is not measuring what it says")
