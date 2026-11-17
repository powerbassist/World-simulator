extends SceneTree

## Headless test: godot --headless --script res://tests/test_top_bar_tiles.gd
## Non-zero exit on any failure.
##
## Gate 3, G3-10 (the author: "info top bar lacks useful data, i dont know if i got positive
## or negative flux"), and his pick of the top bar pictures, "A : tuiles avec courbes": every
## standing figure is a tile -- its value, its change over Trends' window in words with a
## glyph and a tone, and an 18-month curve where history carries one; the money figure is
## euros a month named "Deficit" or "Surplus"; unrest and the majority are meters against
## their thresholds. Built the way main.gd builds the bar (the script, _ready, the theme).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const Government = preload("res://src/sim/government.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
const StripSeries = preload("res://src/ui/strip_series.gd")
const TopBar = preload("res://src/ui/top_bar.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")

var _failures: Array[String] = []
var _loader
var _bar
var _frame := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_bar = load("res://src/ui/top_bar.gd").new()
	_bar.theme = UiTheme.build()
	root.add_child(_bar)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_check_the_money_is_euros_a_month_in_words()
	_check_no_history_draws_no_curve()
	_check_the_curves_and_the_changes()
	_check_the_meters()
	_check_the_tiles_fit_their_slot()
	_finish()
	return true


func _state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2027
	state.month = 7
	return state


## 18 months of history, the deficit (% of GDP) going from `from` to `to`, unemployment
## from 7.5 to 7.0: the sim's own snapshot, so the series read real keys.
func _with_history(state, from: float, to: float):
	var ns = state.player()
	for i in StripSeries.MONTHS:
		var t := float(i) / float(StripSeries.MONTHS - 1)
		ns.deficit_pct_gdp = lerpf(from, to, t)
		ns.unemployment_pct = lerpf(7.5, 7.0, t)
		state.append_history(Budget.snapshot(state))
	return state


func _check_the_money_is_euros_a_month_in_words() -> void:
	var state = _state()
	var ns = state.player()
	ns.deficit_pct_gdp = 5.3
	_bar.refresh(state, null, _loader)
	var want := Num.f(5.3 / 100.0 * ns.gdp_eur_bn / 12.0, 1)
	var value := String(_bar._figure_values["deficit"].text)
	if not value.begins_with(want) or not ("bn" in value and "€" in value):
		_fail("the money figure reads '%s', not %s bn € a month" % [value, want])
	if String(_bar._figure_captions["deficit"].text) != "DEFICIT, THIS MONTH":
		_fail("a deficit is captioned '%s'" % _bar._figure_captions["deficit"].text)
	ns.deficit_pct_gdp = -1.2
	_bar.refresh(state, null, _loader)
	if String(_bar._figure_captions["deficit"].text) != "SURPLUS, THIS MONTH":
		_fail("a surplus is captioned '%s'" % _bar._figure_captions["deficit"].text)
	var shown := String(_bar._figure_values["deficit"].text)
	if shown.begins_with("-") or shown.begins_with("−") or shown.begins_with("+"):
		_fail("the money figure carries a sign the word already says: '%s'" % shown)


func _check_no_history_draws_no_curve() -> void:
	_bar.refresh(_state(), null, _loader)
	for id in StripSeries.IDS:
		var spark: Control = _bar.spark_of(id)
		if spark != null and spark.visible:
			_fail("%s: a curve is drawn with no history" % id)


func _check_the_curves_and_the_changes() -> void:
	var state = _with_history(_state(), 4.4, 5.3)
	_bar.refresh(state, null, _loader)
	for id in StripSeries.IDS:
		var spark: Control = _bar.spark_of(id)
		if spark == null or not spark.visible:
			_fail("%s: 18 months of history and no curve" % id)
		elif StripSeries.values(id, state).size() != StripSeries.MONTHS:
			_fail("%s: the curve holds %d months, not %d" % [id, StripSeries.values(id, state).size(), StripSeries.MONTHS])
	var money: Label = _bar._changes["deficit"]
	if not money.visible or not ("worse" in money.text and "bn" in money.text and "▼" in money.text):
		_fail("a growing deficit's change reads '%s' (visible %s), not ▼ … bn worse" % [money.text, money.visible])
	elif money.theme_type_variation != UiTheme.BAD_TEXT:
		_fail("a growing deficit's change is not in the bad tone")
	var jobs: Label = _bar._changes["unemployment"]
	if not jobs.visible or not ("better" in jobs.text and "▼" in jobs.text):
		_fail("falling unemployment's change reads '%s', not ▼ … better" % jobs.text)
	elif jobs.theme_type_variation != UiTheme.GOOD_TEXT:
		_fail("falling unemployment's change is not in the good tone")


func _check_the_meters() -> void:
	var state = _state()
	var ns = state.player()
	ns.unrest_pct = 9.0
	_bar.refresh(state, null, _loader)
	var unrest = _bar.meter_of("unrest")
	if unrest == null or not unrest.visible:
		_fail("unrest has no meter")
	elif unrest.value != 9.0 or unrest.top != 100.0 or unrest.mark != UnrestK.UNREST_THRESHOLD_PCT:
		_fail("the unrest meter reads %s of %s marked at %s" % [unrest.value, unrest.top, unrest.mark])
	var seats = _bar.meter_of("assembly")
	if seats == null or not seats.visible:
		_fail("the majority has no meter")
	elif seats.value != float(ns.coalition_seats) or seats.top != float(ns.assembly_seats) \
			or seats.mark != float(Government.majority_seats(ns) + 1):
		_fail("the majority meter reads %s of %s marked at %s" % [seats.value, seats.top, seats.mark])


## The tiles stand in the strip's slot at the largest text size too.
func _check_the_tiles_fit_their_slot() -> void:
	var state = _with_history(_state(), 4.4, 5.3)
	for scale in [1.0, 1.3]:
		UiTheme.set_text_scale(scale)
		_bar.theme = UiTheme.build()
		_bar.refresh(state, null, _loader)
		var h: float = _bar.get_combined_minimum_size().y
		if h > TopBar.BAR_HEIGHT:
			_fail("at text %d %% the tiles need %.0f px; the slot is %d" % [roundi(scale * 100), h, TopBar.BAR_HEIGHT])
	UiTheme.set_text_scale(1.0)
	_bar.theme = UiTheme.build()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	for f in _failures:
		printerr("FAIL: %s" % f)
	if _failures.is_empty():
		print("test_top_bar_tiles: passed")
	quit(1 if not _failures.is_empty() else 0)
