extends SceneTree

## Headless test: godot --headless --script res://tests/test_economy.gd
## Non-zero exit on any failure.
##
## The ten-year stability check. docs/economy-model.md argues that nothing in the
## model can diverge; this is the evidence for that argument. Five budgets,
## including deliberately absurd ones, 120 months each, every field of every
## nation checked every month.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const C = preload("res://src/sim/economy_constants.gd")

const MONTHS := 120

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_run_scenario("default budget", {})
	_run_scenario("all taxes at zero", {"tax_rates_pct": {"income": 0.0, "corporate": 0.0, "vat": 0.0}})
	_run_scenario("all taxes at 100%", {"tax_rates_pct": {"income": 100.0, "corporate": 100.0, "vat": 100.0}})
	_run_scenario("all spending at zero", {"spending_pct_gdp": _uniform_spending(0.0)})
	_run_scenario("all spending at 40% of GDP each", {"spending_pct_gdp": _uniform_spending(40.0)})

	_check_gap_closes()
	_check_sector_drift()

	_finish()


func _uniform_spending(value: float) -> Dictionary:
	var d := {}
	for key in C.SPENDING_KEYS:
		d[key] = value
	return d


func _run_scenario(label: String, pending: Dictionary) -> void:
	var state = GameState.new_game(_loader, "FRA")
	if not state.errors.is_empty():
		_failures.append("%s: new_game reported %s" % [label, state.errors])
		return

	if not pending.is_empty():
		Budget.commit(state, pending)

	for month in range(MONTHS):
		Economy.tick_month(state)
		Budget.tick_month(state)
		for ns in state.nations.values():
			_check_nation(label, month + 1, ns)
		# One bad month is enough; 120 x 10 copies of the same message is not.
		if not _failures.is_empty():
			return


func _check_nation(label: String, month: int, ns) -> void:
	var where := "%s, month %d, %s" % [label, month, ns.id]

	_finite(where, "gdp_eur_bn", ns.gdp_eur_bn)
	_finite(where, "potential_gdp_eur_bn", ns.potential_gdp_eur_bn)
	_finite(where, "population", ns.population)
	_finite(where, "unemployment_pct", ns.unemployment_pct)
	_finite(where, "structural_unemployment_pct", ns.structural_unemployment_pct)
	_finite(where, "growth_annual_pct", ns.growth_annual_pct)
	_finite(where, "trend_annual_pct", ns.trend_annual_pct)
	_finite(where, "potential_shift_pct", ns.potential_shift_pct)
	_finite(where, "demand_impulse_pct", ns.demand_impulse_pct)
	_finite(where, "debt_eur_bn", ns.debt_eur_bn)
	_finite(where, "debt_service_pct_gdp", ns.debt_service_pct_gdp)
	_finite(where, "deficit_pct_gdp", ns.deficit_pct_gdp)
	_finite(where, "total_revenue_pct_gdp", ns.total_revenue_pct_gdp)
	_finite(where, "total_spending_pct_gdp", ns.total_spending_pct_gdp)

	if ns.gdp_eur_bn <= 0.0:
		_fail("%s: gdp_eur_bn is %s, expected positive" % [where, ns.gdp_eur_bn])
	if ns.potential_gdp_eur_bn <= 0.0:
		_fail("%s: potential_gdp_eur_bn is %s, expected positive" % [where, ns.potential_gdp_eur_bn])
	if ns.population <= 0.0:
		_fail("%s: population is %s, expected positive" % [where, ns.population])
	if ns.unemployment_pct < 0.0 or ns.unemployment_pct > 100.0:
		_fail("%s: unemployment_pct is %s, expected [0, 100]" % [where, ns.unemployment_pct])
	if ns.growth_annual_pct < C.GROWTH_MIN_PCT - 0.001 or ns.growth_annual_pct > C.GROWTH_MAX_PCT + 0.001:
		_fail("%s: growth_annual_pct is %s, outside the clamp" % [where, ns.growth_annual_pct])
	if absf(ns.potential_shift_pct) > C.SHIFT_MAX_PCT + 0.001:
		_fail("%s: potential_shift_pct is %s, outside the clamp" % [where, ns.potential_shift_pct])

	# A finite but absurd debt is still a bug. EUR 1e9 bn is a quadrillion euro.
	if absf(ns.debt_eur_bn) > 1.0e9:
		_fail("%s: debt_eur_bn is %s, which is not a number a decade can reach" % [where, ns.debt_eur_bn])

	var sector_total := 0.0
	for key in C.SECTOR_TREND.keys():
		var v := float(ns.sector_output.get(key, NAN))
		_finite(where, "sector_output.%s" % key, v)
		if v < 0.0:
			_fail("%s: sector_output.%s is %s, expected non-negative" % [where, key, v])
		sector_total += v

	# The economy tick distributes the cyclical part as a residual against the
	# GDP target, so this invariant must hold to floating-point precision.
	if absf(sector_total - ns.gdp_eur_bn) > 1.0e-6 * maxf(ns.gdp_eur_bn, 1.0):
		_fail("%s: sectors sum to %s but gdp_eur_bn is %s" % [where, sector_total, ns.gdp_eur_bn])


## Stability stated as a property rather than as a bound: shock the economy once,
## stop touching it, and the output gap must come back to zero on its own.
func _check_gap_closes() -> void:
	var state = GameState.new_game(_loader, "FRA")
	# Defence only: it has no potential-growth channel, so the gap is the sole
	# thing being tested rather than a permanent shift to trend.
	Budget.commit(state, {"spending_pct_gdp": {"defence": 12.0}})

	var gaps: Array[float] = []
	for _month in range(MONTHS):
		Economy.tick_month(state)
		Budget.tick_month(state)
		gaps.append(Economy.output_gap_pct(state.player()))

	var peak: float = gaps.max()
	var peak_at: int = gaps.find(peak)
	if peak < 1.0:
		_fail("gap-closes: a 10pp-of-GDP spending shock only opened a %.3f%% output gap" % peak)

	# Two independent statements: it comes back down, and it keeps coming down.
	# Monotone decay after the peak is the property; the absolute bound is the
	# sanity check that ten years is long enough to see it.
	for i in range(peak_at + 1, gaps.size()):
		if gaps[i] > gaps[i - 1] + 1.0e-9:
			_fail("gap-closes: gap rose from %.4f%% to %.4f%% at month %d, after peaking at month %d" % [
				gaps[i - 1], gaps[i], i + 1, peak_at + 1
			])
			break

	if absf(gaps[-1]) > 1.0:
		_fail("gap-closes: gap peaked at %.3f%% and is still %.3f%% after ten years" % [peak, gaps[-1]])


## Sector shares should drift toward services over a decade, because services
## carry the highest trend. If they drift the other way the two-part growth
## distribution has been broken.
func _check_sector_drift() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var services_before: float = float(ns.sector_output["services"]) / ns.gdp_eur_bn

	for _month in range(MONTHS):
		Economy.tick_month(state)
		Budget.tick_month(state)

	var services_after: float = float(ns.sector_output["services"]) / ns.gdp_eur_bn
	if services_after <= services_before:
		_fail("sector drift: services share went %.4f -> %.4f, expected it to rise" % [services_before, services_after])


func _finite(where: String, field: String, value: float) -> void:
	if is_nan(value):
		_fail("%s: %s is NaN" % [where, field])
	elif is_inf(value):
		_fail("%s: %s is infinite" % [where, field])


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_economy: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
