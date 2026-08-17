extends PanelContainer

## The budget screen. Eight levers, the books as they stand, the books as
## proposed, and a two-year projection of both.
##
## Reads simulation state and never writes it. The single exception is the
## Commit button, which sends player intent back as one explicit command —
## Budget.commit(). Pending slider positions live here, not in the simulation.
## See engine-decision.md Rule 2.
##
## The control tree is built in code rather than authored as a .tscn: it is a
## generated grid of eight identical rows, which a scene file would describe
## worse and more verbosely than the loop below.

const Budget = preload("res://src/sim/budget.gd")
const C = preload("res://src/sim/economy_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const CycleK = preload("res://src/sim/cycle_constants.gd")

const PROJECTION_MONTHS := 24

const LEVER_LABELS := {
	"income": "Income tax",
	"corporate": "Corporate tax",
	"vat": "VAT",
	"health": "Health",
	"education": "Education",
	"defence": "Defence",
	"pensions": "Pensions",
	"infrastructure": "Infrastructure",
}
const LEVER_MAX := {
	"income": 70.0,
	"corporate": 70.0,
	"vat": 40.0,
	"health": 30.0,
	"education": 30.0,
	"defence": 30.0,
	"pensions": 30.0,
	"infrastructure": 30.0,
}

const FIGURE_ROWS := [
	["revenue", "Revenue"],
	# Indented under Revenue the way debt service is under Spending, because it is
	# a component and not a fourth headline. A line of its own rather than folded
	# into `other`: V1.3c's tariffs are a revenue source the player CHOSE, and one
	# they cannot see on the panel is the decorative-axis failure
	# docs/scenario-model.md records, with a different label. Reads "—" while
	# nothing is imposed, which is every game that has not used the verb.
	["tariffs", "  of which tariffs"],
	# V1.4c, beside the tariff line and on the same argument: a revenue source the
	# player chose, which no slider on this panel sets. It differs from tariffs in
	# that it arrives from a decision taken on a different screen entirely, so a
	# budget that quietly widened its revenue after a nationalisation would be the
	# unnamed-reason failure the four indented lines here all exist to prevent.
	# Reads "—" while the state holds nothing, which is every game that has not used
	# the verb.
	["dividends", "  of which dividends"],
	["spending", "Spending"],
	["debt_service", "  of which debt service"],
	# V1.3d, indented under Spending for the same reason tariffs are indented under
	# Revenue, and on the same argument: a member's contribution, whatever the
	# rules in force move it by, and the penalties for defying them are all money
	# leaving the budget, and the player did not set any of it with a slider.
	# Reads "—" for a non-member, which is exactly 0.0 by construction.
	["bloc_transfer", "  of which the Union"],
	# V1.3g, beside the Union line and on the same argument a third time: money
	# leaving the budget that the player set with no slider. It differs from both
	# lines above in the way that matters most here -- an OBLIGED deployment is
	# spending the player did not choose AT ALL, so a panel that did not show it
	# would leave a deficit moving for a reason nothing on screen names.
	# Reads "—" while nothing is deployed, which is every game that has not allied.
	#
	# THIS ROW WAS MISSING UNTIL V1.4c, and its comment was here without it. V1.3g
	# wrote `_set_figure("deployments", ...)` and no ["deployments", ...] entry, and
	# _set_figure() returns silently on an unknown key -- so the deployment bill has
	# never appeared on this panel, and V1.4a then wrote "beside the deployment line"
	# about a line that was not there. V1.3g's own screenshot pass could not catch it:
	# the tool bug it did find made that figure an em dash anyway.
	["deployments", "  of which deployments"],
	# V1.4a, beside the deployment line and on the same argument a fourth time:
	# money leaving the budget that the player set with no slider. Without it a
	# subsidy signed on the Companies panel would widen the deficit here with
	# nothing on this screen naming the reason -- which is the failure this row and
	# the three above it all exist to prevent.
	# Reads "—" while nothing is subsidised, which is every game that has not used
	# the verb.
	["subsidies", "  of which subsidies"],
	["deficit", "Deficit"],
	["debt", "Debt"],
	["", ""],
	# V1.6a: the three projection rows now read as a RANGE. See _forecast_text().
	["proj_growth", "GDP growth, in 24 months"],
	["proj_unemployment", "Unemployment, in 24 months"],
	["proj_debt", "Debt ratio, in 24 months"],
]

## Carries the state Trends.snapshot_now() took the instant before Budget.commit()
## ran -- U4's decision-effects baseline. Taken here, not in main.gd, because by
## the time main.gd hears this signal the commit has already happened.
signal committed(before: Dictionary)

var _state
var _loader
var _pending := {"tax_rates_pct": {}, "spending_pct_gdp": {}}
var _sliders := {}
var _lever_values := {}
var _figures := {}
var _title: Label
var _dirty := true
var _close_button: Button


func _ready() -> void:
	# Placement is the owner's job — main.gd drops this into a CenterContainer.
	# S4 called set_anchors_preset(PRESET_CENTER) here, which moves the anchors and
	# leaves the offsets at zero, so the panel actually sat in the top-left corner
	# on top of the HUD. Never noticed, because it had only ever been tested
	# headlessly.
	custom_minimum_size = Vector2(820, 520)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title = Label.new()
	root.add_child(_title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	columns.add_child(_build_levers())
	columns.add_child(_build_figures())

	root.add_child(_build_buttons())


func _build_levers() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var heading := Label.new()
	heading.text = "Levers (tax rates %, spending % of GDP)"
	box.add_child(heading)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)

	for key in _lever_keys():
		var name_label := Label.new()
		name_label.text = LEVER_LABELS[key]
		name_label.custom_minimum_size.x = 130
		grid.add_child(name_label)

		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = float(LEVER_MAX[key])
		slider.step = 0.1
		slider.custom_minimum_size.x = 220
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_lever_changed.bind(key))
		grid.add_child(slider)
		_sliders[key] = slider

		var value_label := Label.new()
		value_label.custom_minimum_size.x = 60
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value_label)
		_lever_values[key] = value_label

	return box


func _build_figures() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 16)
	box.add_child(grid)

	for header in ["", "now", "proposed"]:
		var label := Label.new()
		label.text = header
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if header != "" else HORIZONTAL_ALIGNMENT_LEFT
		label.custom_minimum_size.x = 200 if header == "" else 110
		grid.add_child(label)

	for row in FIGURE_ROWS:
		var name_label := Label.new()
		name_label.text = row[1]
		grid.add_child(name_label)

		var now_label := Label.new()
		now_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(now_label)

		var pending_label := Label.new()
		pending_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(pending_label)

		if row[0] != "":
			_figures[row[0]] = [now_label, pending_label]

	return box


func _build_buttons() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	var commit := Button.new()
	commit.text = "Commit"
	commit.pressed.connect(_on_commit)
	row.add_child(commit)

	var revert := Button.new()
	revert.text = "Revert"
	revert.pressed.connect(_on_revert)
	row.add_child(revert)

	_close_button = Button.new()
	_close_button.text = "Close (B)"
	_close_button.pressed.connect(func(): hide())
	row.add_child(_close_button)

	return row


## Docked-tab mode, for the dashboard: the rail already selects a different tab
## to leave this one, so a "Close" button that just hides the panel inside its
## own tab would show a blank tab. Same idiom as save_load_panel.hide_save_row().
func hide_close_button() -> void:
	_close_button.hide()


func _lever_keys() -> Array:
	var keys: Array = []
	keys.append_array(C.TAX_KEYS)
	keys.append_array(C.SPENDING_KEYS)
	return keys


## `loader` since V1.3b: Budget.project() needs it to drift relations the way the
## real game does, or the projected path and the played one disagree.
func setup(state, loader) -> void:
	_state = state
	_loader = loader
	var ns = _state.player()
	_title.text = "BUDGET — %s" % ns.id
	_on_revert()


func _on_revert() -> void:
	var ns = _state.player()
	_pending = {
		"tax_rates_pct": ns.tax_rates_pct.duplicate(true),
		"spending_pct_gdp": ns.spending_pct_gdp.duplicate(true),
	}
	for key in _lever_keys():
		var slider: HSlider = _sliders[key]
		slider.set_block_signals(true)
		slider.value = _pending_value(key)
		slider.set_block_signals(false)
	_dirty = true


func _on_commit() -> void:
	var before := Trends.snapshot_now(_state)
	Budget.commit(_state, _pending)
	_on_revert()
	committed.emit(before)


func _on_lever_changed(value: float, key: String) -> void:
	if C.TAX_KEYS.has(key):
		_pending["tax_rates_pct"][key] = value
	else:
		_pending["spending_pct_gdp"][key] = value
	_dirty = true


func _pending_value(key: String) -> float:
	if C.TAX_KEYS.has(key):
		return float(_pending["tax_rates_pct"].get(key, 0.0))
	return float(_pending["spending_pct_gdp"].get(key, 0.0))


## Sliders fire many times during a drag, and every refresh runs two 24-month
## projections. Coalesce to at most one refresh per frame.
func _process(_delta: float) -> void:
	if not _dirty or not visible or _state == null:
		return
	_dirty = false
	_refresh()


## Called by the owner after each simulated month, so an open panel does not show
## last month's figures.
func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	for key in _lever_keys():
		_lever_values[key].text = "%.1f%%" % _pending_value(key)

	# preview() with nothing pending rather than snapshot(), and V1.3c is why.
	# snapshot() reads ns.revenue_pct_gdp as Budget.tick_month() last left it, so a
	# tariff imposed THIS month showed an em dash under Revenue until the clock
	# moved -- the panel telling the player their new revenue source collects
	# nothing. preview() recomputes the books on a deep copy, so the "now" column is
	# the live position without this panel writing a byte of sim state, which rule 2
	# forbids. Found by tests/test_budget_panel.gd, not by looking.
	var now := Budget.preview(_state, {})
	var proposed := Budget.preview(_state, _pending)
	var now_path := Budget.project(_state, {}, PROJECTION_MONTHS, _loader)
	var proposed_path := Budget.project(_state, _pending, PROJECTION_MONTHS, _loader)

	_set_figure("revenue", _pct_and_eur(now, "total_revenue_pct_gdp"), _pct_and_eur(proposed, "total_revenue_pct_gdp"))
	_set_figure("tariffs", _tariff_text(now), _tariff_text(proposed))
	_set_figure("dividends", _dividend_text(now), _dividend_text(proposed))
	_set_figure("spending", _pct_and_eur(now, "total_spending_pct_gdp"), _pct_and_eur(proposed, "total_spending_pct_gdp"))
	_set_figure("debt_service", _pct_and_eur(now, "debt_service_pct_gdp"), _pct_and_eur(proposed, "debt_service_pct_gdp"))
	_set_figure("bloc_transfer", _bloc_text(now), _bloc_text(proposed))
	_set_figure("deployments", _deployment_text(now), _deployment_text(proposed))
	_set_figure("subsidies", _subsidy_text(now), _subsidy_text(proposed))
	_set_figure("deficit", _pct_and_eur(now, "deficit_pct_gdp"), _pct_and_eur(proposed, "deficit_pct_gdp"))
	_set_figure("debt", "%.1f%% GDP" % now["debt_to_gdp_pct"], "%.1f%% GDP" % proposed["debt_to_gdp_pct"])

	var last_now: Dictionary = now_path[-1]
	var last_proposed: Dictionary = proposed_path[-1]
	var band := _forecast_half_width()
	_set_figure("proj_growth",
		_forecast_text(float(last_now["growth_annual_pct"]), band, 2),
		_forecast_text(float(last_proposed["growth_annual_pct"]), band, 2))
	_set_figure("proj_unemployment",
		_forecast_text(float(last_now["unemployment_pct"]), band * C.OKUN, 2),
		_forecast_text(float(last_proposed["unemployment_pct"]), band * C.OKUN, 2))
	# The debt ratio gets a band too, and the screenshot pass is what asked for it: one
	# point figure between two ranges read as a row somebody forgot rather than as a
	# stock behaving differently. The half-width is the same uncertainty carried through
	# the DENOMINATOR -- `band` points of growth a year for two years moves GDP by about
	# that much twice over, and the ratio with it -- so it is derived from the same
	# number rather than being a second guess.
	var years: float = float(PROJECTION_MONTHS) / 12.0
	_set_figure("proj_debt",
		_forecast_text(float(last_now["debt_to_gdp_pct"]), band * years * float(last_now["debt_to_gdp_pct"]) / 100.0, 1),
		_forecast_text(float(last_proposed["debt_to_gdp_pct"]), band * years * float(last_proposed["debt_to_gdp_pct"]) / 100.0, 1))


## V1.6a. A PROJECTION IS EXACT AND A FORECAST IS NOT, and these three rows print the
## second while the model computes the first.
##
## Budget.project() runs the real model on a copy, so the number it returns is what will
## happen to the last digit -- tests/test_budget.gd asserts it to 1e-9, and V1.6a's
## business cycle reproduces there exactly because it is a pure function of the clock.
## Printing that to two decimals would hand the player a perfect two-year forecast of a
## recession they are supposed to be judged on not having prevented, which is
## docs/tiers/v1.md section 6's mechanic thrown away at the last surface.
##
## src/ui/poll_noise.gd already solved this problem from the other side and its
## reasoning transfers word for word: an approval figure is a PUBLISHED POLL and must
## not be readable exactly, so the model never stores a fuzzed number and the panel
## fuzzes it the moment it renders one. A government growth forecast is a published
## figure in exactly the same sense.
##
## It is a RANGE rather than a nudged point, and that is the one place this departs from
## poll_noise. A nudge invents an error with a sign the model has no basis for; a band
## states the uncertainty and contains the truth. It also costs no hash at all -- the
## half-width is derived, so there is nothing to keep stable across repaints and nothing
## to serialise, which are the two properties poll_noise.gd needed its hash for.
##
## THE SAME HALF-WIDTH IS APPLIED TO BOTH COLUMNS, and that is what keeps this panel
## usable. Its whole job is now-against-proposed, so an independent error on each side
## would fuzz the comparison the player is actually making. One band means the
## DIFFERENCE between the two columns stays exact while the LEVEL is honest about being
## a forecast -- which is also true of real forecasters, whose bias moves both scenarios
## together.
func _forecast_half_width() -> float:
	var ns = _state.player()
	if ns == null:
		return 0.0
	# One standard deviation of the cycle's own contribution to growth. Derived from
	# the constant and the nation's measured volatility rather than chosen, so a
	# quieter country gets a tighter band without a second number to tune.
	return CycleK.CYCLE_AMPLITUDE_PCT * float(ns.cycle_amplitude_rel)


## "1.05 to 1.62%". An en dash would read as a minus sign against a negative growth
## figure, which is exactly the forecast the player most needs to read correctly.
func _forecast_text(value: float, half_width: float, places: int) -> String:
	if half_width <= 0.0:
		return "%.*f%%" % [places, value]
	return "%.*f to %.*f%%" % [places, value - half_width, places, value + half_width]


## An em dash rather than "0.00%" while nothing is imposed. The two say different
## things: a zero invites the player to wonder what they did wrong, where a dash
## says the line is not in play. Every game that has never used the verb reads the
## dash, which is most of them.
## The same em dash for the same reason, with one difference the tariff line does
## not have: this figure is SIGNED. A net receiver -- or a member drawing on a
## programme the council adopted -- shows a negative, and "+" is forced so the
## direction is readable without comparing it against the line above.
func _bloc_text(snap: Dictionary) -> String:
	var pct: float = float(snap.get("bloc_transfer_pct_gdp", 0.0))
	if is_zero_approx(pct):
		return "—"
	return "%+.2f%% GDP" % pct


## The same em dash again. Unsigned, unlike the Union line: a deployment only ever
## costs, and there is no receiving side of one.
func _deployment_text(snap: Dictionary) -> String:
	var pct: float = float(snap.get("deployment_bill_pct_gdp", 0.0))
	if is_zero_approx(pct):
		return "—"
	return _pct_and_eur(snap, "deployment_bill_pct_gdp")


## The same em dash a fourth time. Unsigned like the deployment line: a subsidy only
## ever costs, and the money the firm makes with it is private.
func _subsidy_text(snap: Dictionary) -> String:
	var pct: float = float(snap.get("subsidy_bill_pct_gdp", 0.0))
	if is_zero_approx(pct):
		return "—"
	return _pct_and_eur(snap, "subsidy_bill_pct_gdp")


## The same em dash a fifth time, on the revenue side. Unsigned: a holding pays or
## the state does not have one, and a firm that loses money still hands over nothing
## rather than billing the treasury -- there is no margin quantity here for it to
## lose, which is docs/companies-model.md section 13's call showing up on a panel.
func _dividend_text(snap: Dictionary) -> String:
	var pct: float = float(snap.get("dividend_revenue_pct_gdp", 0.0))
	if is_zero_approx(pct):
		return "—"
	return _pct_and_eur(snap, "dividend_revenue_pct_gdp")


func _tariff_text(snap: Dictionary) -> String:
	var pct: float = float(snap.get("tariff_revenue_pct_gdp", 0.0))
	if is_zero_approx(pct):
		return "—"
	return _pct_and_eur(snap, "tariff_revenue_pct_gdp")


func _pct_and_eur(snap: Dictionary, key: String) -> String:
	var pct: float = snap[key]
	return "%.2f%%  (%.0f bn)" % [pct, pct / 100.0 * float(snap["gdp_eur_bn"])]


func _set_figure(key: String, now_text: String, pending_text: String) -> void:
	if not _figures.has(key):
		return
	_figures[key][0].text = now_text
	_figures[key][1].text = pending_text
