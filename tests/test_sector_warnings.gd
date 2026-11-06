extends SceneTree

## V5.3 a + b, band B7's sector source (docs/design/v5.3-ab.md 3.1 and section 7, the
## parent's option (c)): every sector quantity moves monthly with real money per head
## and with its need, a held line slips into its bad band on its own, the warning
## arrives once per crossing, and the figures keep a ten-year trend. The drift stays
## out of the channels (Sectors.factor), which is why it moves no balance figure.
##
## Rates, elasticities and the band are written here as literals on purpose: a fixture
## built from the constant it pins cannot catch a retune of that constant.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Sectors = preload("res://src/sim/sectors.gd")
const SectorWarnings = preload("res://src/sim/sector_warnings.gd")
const Society = preload("res://src/sim/society.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")

var _loader
var _failures: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_a_new_game_reads_its_start_figures()
	_test_the_first_month_takes_the_base_and_only_the_player_ticks()
	_test_a_save_from_before_the_base_reads_no_money_drift()
	_test_money_per_head_moves_a_figure()
	_test_the_need_moves_a_figure_by_its_rate()
	_test_the_data_carries_the_sourced_rates()
	_test_the_drift_stays_out_of_the_channels()
	_test_a_held_line_crosses_at_the_month_the_arithmetic_says()
	_test_a_better_figure_never_warns()
	_test_one_arrival_per_crossing_then_the_rearm()
	_test_the_reason_names_the_cut_or_the_need()
	_test_the_trend_is_capped_and_oldest_first()
	_test_the_restore_figure_brings_it_back_to_the_start()
	_test_the_registers_survive_a_save()
	_test_the_game_month_runs_it()
	_finish()


func _state(nation := "FRA"):
	var state = GameState.new_game(_loader, nation)
	state.year = 2027
	state.month = 1
	return state


## One month of this system alone, with the clock moved as the game moves it. GDP and
## the population stay put, so only the need drifts.
func _tick(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1
	SectorWarnings.tick_month(state, _loader)


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _test_a_new_game_reads_its_start_figures() -> void:
	var state = _state()
	var ns = state.player()
	for line in _loader.domains:
		for s in Sectors.sectors_of(_loader, String(line)):
			var id := String(s["id"])
			if Sectors.quantity(ns, _loader, String(line), id) != float(s["start"]["FRA"]["quantity"]):
				_fail("a new game's %s is not its start figure" % id)
			if SectorWarnings.warning(ns, _loader, String(line), id) != "":
				_fail("a new game warns on %s" % id)
			if not SectorWarnings.trend(ns, id).is_empty():
				_fail("a new game already has a trend for %s" % id)


func _test_the_first_month_takes_the_base_and_only_the_player_ticks() -> void:
	var state = _state()
	var ns = state.player()
	var other = state.nations["DEU"]
	_tick(state)
	if not is_equal_approx(float(ns.sector_drift["base_gdp_per_head"]), float(ns.gdp_eur_bn) / float(ns.population)):
		_fail("the first month did not take the base: %s" % ns.sector_drift["base_gdp_per_head"])
	if int(ns.sector_drift["need_months"]) != 1:
		_fail("one month reads %s months of need" % ns.sector_drift["need_months"])
	var base := float(ns.sector_drift["base_gdp_per_head"])
	ns.gdp_eur_bn *= 1.5
	_tick(state)
	if float(ns.sector_drift["base_gdp_per_head"]) != base:
		_fail("a later month moved the base: %s -> %s" % [base, ns.sector_drift["base_gdp_per_head"]])
	if not other.sector_drift.is_empty():
		_fail("another nation ticked: %s" % [other.sector_drift])


func _test_a_save_from_before_the_base_reads_no_money_drift() -> void:
	var state = _state()
	var ns = state.player()
	ns.gdp_eur_bn *= 1.5
	if Sectors.quantity(ns, _loader, "defence", "personnel") != 100.0:
		_fail("no base yet, and GDP moved the figure: %s" % Sectors.quantity(ns, _loader, "defence", "personnel"))


func _test_money_per_head_moves_a_figure() -> void:
	var state = _state()
	var ns = state.player()
	_tick(state)
	# Defence has no need drift, so this is the money alone: 100 x 1.10 ^ 0.9.
	ns.gdp_eur_bn *= 1.10
	_near(Sectors.quantity(ns, _loader, "defence", "personnel"), 100.0 * pow(1.10, 0.9), "10 % more GDP")
	ns.population *= 1.10
	_near(Sectors.quantity(ns, _loader, "defence", "personnel"), 100.0, "as many more people as euros")
	# Lower is better: more money per head, fewer pupils per teacher.
	ns.population /= 1.10
	var need: float = pow(1.0 - 0.0087, 1.0 / 12.0)
	_near(Sectors.quantity(ns, _loader, "education", "schools"), 17.9 * pow(1.10 / need, -0.5), "pupils per teacher")


func _test_the_need_moves_a_figure_by_its_rate() -> void:
	var state = _state()
	var ns = state.player()
	ns.sector_drift["need_months"] = 120
	# FRA's health need per head +2.40 % a year, for ten years, at elasticity 0.6.
	_near(Sectors.quantity(ns, _loader, "health", "hospitals"), 5.34 * pow(pow(1.024, 10.0), -0.6), "ten years of hospital need")
	# FRA's schools need per head -0.87 % a year: a smaller cohort, fewer pupils per teacher.
	_near(Sectors.quantity(ns, _loader, "education", "schools"), 17.9 * pow(pow(1.0 - 0.0087, 10.0), 0.5), "ten years of a smaller cohort")
	_near(Sectors.quantity(ns, _loader, "defence", "personnel"), 100.0, "defence has no need drift")


## Content's table (.superpowers/sdd/v5.3-sector-sources.md, "Sector need drift"), less
## the total population rate: a figure per inhabitant reads a need per inhabitant.
func _test_the_data_carries_the_sourced_rates() -> void:
	var want := {
		"hospitals": {"FRA": 2.40, "DEU": 1.19, "POL": 3.43, "GBR": 2.02},
		"primary_care": {"FRA": 2.40, "DEU": 1.19, "POL": 3.43, "GBR": 2.02},
		"prevention": {"FRA": 2.40, "DEU": 1.19, "POL": 3.43, "GBR": 2.02},
		"schools": {"FRA": -0.87, "DEU": 0.22, "POL": -1.49, "GBR": -1.64},
		"universities": {"FRA": -0.60, "DEU": 0.44, "POL": 0.93, "GBR": 0.24},
		"basic_pension": {"FRA": 1.29, "DEU": 1.57, "POL": 1.12, "GBR": 1.59},
		"minimum_income": {"FRA": 1.29, "DEU": 1.57, "POL": 1.12, "GBR": 1.59},
	}
	for line in _loader.domains:
		for s in Sectors.sectors_of(_loader, String(line)):
			var id := String(s["id"])
			for nation in ["FRA", "DEU", "POL", "GBR"]:
				var got := float(s["start"][nation]["need_drift_pct_year"])
				var rates: Dictionary = want.get(id, {})
				if got != float(rates.get(nation, 0.0)):
					_fail("%s %s need drift reads %s" % [nation, id, got])
				if got != 0.0 and String(s["start"][nation]["need_source"]) == "":
					_fail("%s %s carries a rate with no source" % [nation, id])


func _test_the_drift_stays_out_of_the_channels() -> void:
	var state = _state()
	var ns = state.player()
	var health := Society.quality_target(ns, "health")
	var pensions := Society.quality_target(ns, "pensions")
	for i in 60:
		_tick(state)
	ns.gdp_eur_bn *= 0.8
	if Sectors.factor(ns, "health") != 1.0 or Sectors.factor(ns, "pensions") != 1.0:
		_fail("the drift reached the factor: %s %s" % [Sectors.factor(ns, "health"), Sectors.factor(ns, "pensions")])
	if Society.quality_target(ns, "health") != health or Society.quality_target(ns, "pensions") != pensions:
		_fail("the drift reached a channel")


## FRA's hospitals, GDP per head held: the figure is 0.05 under its start once
## 1.024 ^ (0.6 m / 12) >= 1 / 0.95, that is m >= 43.25.
func _test_a_held_line_crosses_at_the_month_the_arithmetic_says() -> void:
	var state = _state()
	var ns = state.player()
	for m in range(1, 44):
		_tick(state)
		if not SectorWarnings.arrivals(ns, _loader, _now(state)).is_empty():
			_fail("something arrived at month %d: %s" % [m, SectorWarnings.arrivals(ns, _loader, _now(state))])
		if SectorWarnings.warning(ns, _loader, "health", "hospitals") != "":
			_fail("hospitals warned at month %d, before the band" % m)
	_tick(state)
	if SectorWarnings.warning(ns, _loader, "health", "hospitals") == "":
		_fail("hospitals did not warn at month 44: %s" % Sectors.quantity(ns, _loader, "health", "hospitals"))
	if not _arrived(state, "hospitals"):
		_fail("hospitals did not arrive at month 44: %s" % [SectorWarnings.arrivals(ns, _loader, _now(state))])


func _test_a_better_figure_never_warns() -> void:
	var state = _state()
	var ns = state.player()
	for i in 240:
		_tick(state)
	# Twenty years of a smaller cohort: pupils per teacher only fell.
	if SectorWarnings.warning(ns, _loader, "education", "schools") != "" or (ns.sector_drift["warnings"] as Dictionary).has("schools"):
		_fail("a figure better than its start warned: %s" % Sectors.quantity(ns, _loader, "education", "schools"))


func _test_one_arrival_per_crossing_then_the_rearm() -> void:
	var state = _state()
	var ns = state.player()
	for i in 44:
		_tick(state)
	if not _arrived(state, "hospitals"):
		_fail("the crossing did not arrive")
	_tick(state)
	if _arrived(state, "hospitals"):
		_fail("a second month in the band arrived again")
	# The player restores the line: the figure leaves the band.
	var cut := float(ns.spending_pct_gdp["health"])
	ns.spending_pct_gdp["health"] = cut * 1.2
	_tick(state)
	if String(SectorWarnings.warning(ns, _loader, "health", "hospitals")) != "" or int(ns.sector_drift["warnings"]["hospitals"]["left"]) != _now(state):
		_fail("the figure did not leave the band: %s" % [ns.sector_drift["warnings"]["hospitals"]])
	# Back in the band inside the 12-month rearm: the mark shows, no second arrival.
	ns.spending_pct_gdp["health"] = cut
	for i in 11:
		_tick(state)
		if _arrived(state, "hospitals"):
			_fail("a re-entry %d months after leaving arrived inside the rearm" % (i + 1))
	if SectorWarnings.warning(ns, _loader, "health", "hospitals") == "":
		_fail("in the band inside the rearm, the mark did not show")
	_tick(state)
	if not _arrived(state, "hospitals"):
		_fail("still in the band after the rearm, nothing arrived: %s" % [ns.sector_drift["warnings"]["hospitals"]])


func _test_the_reason_names_the_cut_or_the_need() -> void:
	var state = _state()
	var ns = state.player()
	ns.spending_pct_gdp["health"] = float(ns.spending_pct_gdp["health"]) * 0.8
	if SectorWarnings.warning(ns, _loader, "health", "hospitals") != SectorWarnings.REASON_CUT:
		_fail("a cut line read: %s" % SectorWarnings.warning(ns, _loader, "health", "hospitals"))
	var drifted = _state().player()
	drifted.sector_drift["need_months"] = 120
	if SectorWarnings.warning(drifted, _loader, "health", "hospitals") != SectorWarnings.REASON_NEED:
		_fail("a held line read: %s" % SectorWarnings.warning(drifted, _loader, "health", "hospitals"))


func _test_the_trend_is_capped_and_oldest_first() -> void:
	var state = _state()
	var ns = state.player()
	var first := 0.0
	for i in 130:
		_tick(state)
		if i == 10:
			first = Sectors.quantity(ns, _loader, "health", "hospitals")
	var trend: Array = SectorWarnings.trend(ns, "hospitals")
	if trend.size() != 120:
		_fail("the trend holds %d months, not ten years" % trend.size())
		return
	if float(trend[-1]) != Sectors.quantity(ns, _loader, "health", "hospitals"):
		_fail("the trend's last month %s is not this month's figure" % trend[-1])
	# 130 ticks, 120 kept: the oldest left is tick 11, which is index 10 above.
	if float(trend[0]) != first:
		_fail("the trend's oldest %s is not the 11th month's %s" % [trend[0], first])
	if float(trend[0]) <= float(trend[-1]):
		_fail("a falling figure's trend is not oldest first: %s .. %s" % [trend[0], trend[-1]])
	trend[0] = -1.0
	if float(SectorWarnings.trend(ns, "hospitals")[0]) == -1.0:
		_fail("trend() hands out the register itself")


func _test_the_restore_figure_brings_it_back_to_the_start() -> void:
	var state = _state()
	var ns = state.player()
	ns.sector_drift["need_months"] = 120
	var points := SectorWarnings.restore_pct_gdp(ns, _loader, "health", "hospitals")
	if points <= 0.0:
		_fail("ten years of need cost no money to restore: %s" % points)
	ns.spending_pct_gdp["health"] = float(ns.spending_pct_gdp["health"]) + points
	_near(Sectors.quantity(ns, _loader, "health", "hospitals"), 5.34, "the restored line")
	if SectorWarnings.restore_pct_gdp(ns, _loader, "health", "hospitals") > 1e-9:
		_fail("a restored sector still asks for money")


func _test_the_registers_survive_a_save() -> void:
	var state = _state()
	var ns = state.player()
	for i in 50:
		_tick(state)
	var loaded = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict(), "", false, true)))
	var back = loaded.player()
	if Sectors.quantity(back, _loader, "health", "hospitals") != Sectors.quantity(ns, _loader, "health", "hospitals"):
		_fail("a save moved the figure: %s -> %s" % [Sectors.quantity(ns, _loader, "health", "hospitals"), Sectors.quantity(back, _loader, "health", "hospitals")])
	if SectorWarnings.trend(back, "hospitals") != SectorWarnings.trend(ns, "hospitals"):
		_fail("a save moved the trend")
	if int(back.sector_drift["warnings"]["hospitals"]["entered"]) != int(ns.sector_drift["warnings"]["hospitals"]["entered"]):
		_fail("a save moved the warning's month")
	# The next month carries on: no second arrival for the band it was already in.
	loaded.month = state.month
	_tick(loaded)
	if _arrived(loaded, "hospitals"):
		_fail("a load re-fired a warning it was already holding")
	if int(back.sector_drift["need_months"]) != 51:
		_fail("the need's clock did not carry on through a save: %s" % back.sector_drift["need_months"])


func _test_the_game_month_runs_it() -> void:
	var state = _state()
	var ns = state.player()
	state.month = 2
	WorldMonth.tick_month(state, _loader)
	if int(ns.sector_drift.get("need_months", 0)) != 1 or float(ns.sector_drift.get("base_gdp_per_head", 0.0)) <= 0.0:
		_fail("the game's month did not run the sector drift: %s" % [ns.sector_drift])
	if SectorWarnings.trend(ns, "hospitals").size() != 1:
		_fail("the game's month did not sample the trend")


func _arrived(state, sector_id: String) -> bool:
	for row in SectorWarnings.arrivals(state.player(), _loader, _now(state)):
		if String(row["id"]) == sector_id:
			return true
	return false


func _near(got: float, want: float, what: String) -> void:
	if absf(got - want) > 1e-9 * maxf(absf(want), 1.0):
		_fail("%s: got %s, want %s" % [what, got, want])


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_sector_warnings")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
