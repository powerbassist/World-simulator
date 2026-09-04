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
const Tax = preload("res://src/sim/tax.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

const PROJECTION_MONTHS := 24

## V1.6d. The brackets lever, keyed apart from the ten rate-and-spending keys because
## it is not one of them: it sets no rate, has no base share and collects nothing.
## Budget.commit() takes it as a third top-level key on `pending` for the same reason.
const PROGRESSIVITY_KEY := "tax_progressivity"

const LEVER_LABELS := {
	"income": "Income tax",
	"corporate": "Corporate tax",
	"vat": "VAT",
	"capital_gains": "Capital gains tax",
	"wealth": "Wealth tax",
	PROGRESSIVITY_KEY: "Income brackets",
	"health": "Health",
	"education": "Education",
	"defence": "Defence",
	"pensions": "Pensions",
	"infrastructure": "Infrastructure",
}
## V1.6d: `wealth` is 3.0 and not 70, and the number is not authored here -- it reads
## economy_constants.WEALTH_RATE_MAX_PCT, so the model bound and the control cannot
## drift apart, and tests/test_tax.gd asserts the identity. A point of wealth rate is
## eight points of income tax in revenue, because that base is a stock; a slider running
## to 70 would be a slider whose top four fifths is a joke.
const LEVER_MAX := {
	"income": 70.0,
	"corporate": 70.0,
	"vat": 40.0,
	"capital_gains": 60.0,
	"wealth": C.WEALTH_RATE_MAX_PCT,
	PROGRESSIVITY_KEY: TaxK.PROGRESSIVITY_MAX,
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
	# V1.6e, beside the subsidy line and on the same argument a FIFTH time: money
	# leaving the budget that the player set with no slider on this panel. It differs
	# from the subsidy line in the one way that matters to a player reading this
	# screen -- a subsidy's effect arrives inside a year and a sector programme's
	# takes most of a term, so this is a line that will sit here costing money for
	# several years before the growth it bought is visible in the rows below.
	# Reads "—" while no programme stands, which is every game that has not used
	# the verb.
	["investment", "  of which investment"],
	# V1.6f, beside the investment line and on the same argument a SIXTH time -- and
	# with the one difference this panel exists to show: every line above it is a
	# STANDING rate the player can lower, and this one runs for a fixed term and then
	# STOPS. A president reading this screen is looking at a bulge in the deficit with
	# a known end date, which is the whole of what makes a project a commitment rather
	# than a policy. Reads "—" while nothing is under construction, which is every
	# game that has not used the verb.
	["projects", "  of which public works"],
	# V1.7a, beside the public-works line and on the same argument a SEVENTH time: money
	# leaving the budget that the player set with no slider on this panel. It differs
	# from every line above it in WHEN it appears -- it can only exist inside the months
	# before an election, and it stops on a date the player cannot move. A president
	# reading this screen in the run-up is looking at the one line here they will not be
	# paying next year whatever they decide. Reads "-" outside a run-up and while nothing
	# is in the field, which is most of every game.
	["campaign", "  of which the campaign"],
	# V2.8, and the argument is the campaign row's one more time: a build in
	# progress and every running station are on the spending total with no slider
	# on this panel, so the row is the only place the player can see WHAT the
	# fleet costs. Unlike the campaign it does not stop on a date -- it stops when
	# the player closes a station, which is why the off switch is a verb.
	["energy", "  of which energy"],
	["deficit", "Deficit"],
	["debt", "Debt"],
	# V1.6d. NOT a budget figure, and it is on this panel anyway because this is where
	# the three instruments that move it live -- brackets, the capital-gains rate and
	# the wealth rate. It is the one consequence of a distributional budget no other
	# line here can show: docs/unrest-model.md's grievance reads it, and until V1.6d
	# nothing the player did moved it at all.
	#
	# NEVER SILENT, which is the dependency ratio's and the credit rating's rule
	# rather than the delivery lines': every game has an inequality index from the
	# first frame, so a line that appeared only once it moved would hide the level the
	# offset is measured against.
	["gini", "Inequality (Gini)"],
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
## True once the player has moved a slider, so mark_dirty() stops re-syncing
## _pending from live state and their half-finished budget survives a month tick.
var _edited := false
var _sliders := {}
var _lever_values := {}
## key -> [now text, proposed text] for the CURRENT refresh, cleared and refilled
## each time. It held a pair of live Labels until V2.1b; the table is a
## PanelKit.ledger() rebuilt from FIGURE_ROWS now, which is what makes the two
## value columns one measurement -- and it is what turns _set_figure()'s unknown
## key from a silent return into an error. See that function.
var _figures := {}
var _figures_box: VBoxContainer
var _title: Label
var _dirty := true
var _close_button: Button

## The verb this panel exists for. Built once in _ready() and alive for the
## session, so it is held rather than re-found. See primary_action().
var _commit_button: Button


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

	PanelKit.line(box, "Levers (tax rates %, spending % of GDP)", PanelKit.Tone.PLAIN)

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
		# A tenth of a point is the right grain for a lever running to seventy and much
		# too coarse for one running to three: at 0.1 the wealth slider offers thirty
		# positions in total and Switzerland's real rate lands between two of them.
		slider.step = 0.01 if key == "wealth" or key == PROGRESSIVITY_KEY else 0.1
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
	_figures_box = VBoxContainer.new()
	_figures_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return _figures_box


## The now/proposed table, rebuilt from FIGURE_ROWS and whatever _refresh() has
## just written into _figures.
##
## V1.6f as a primitive: the three columns were three hand-set
## custom_minimum_size.x values, and one extra clause on one row ran the proposed
## column past the window edge with the number right the whole time. A ledger is
## one grid, so the columns cannot size apart.
func _fill_figures() -> void:
	for child in _figures_box.get_children():
		child.queue_free()

	var rows: Array = [["", "now", "proposed"]]
	for row in FIGURE_ROWS:
		var key: String = row[0]
		if key == "":
			rows.append([row[1], "", ""])
			continue
		var pair: Array = _figures.get(key, [PanelKit.MISSING, PanelKit.MISSING])
		rows.append([row[1], pair[0], pair[1]])
	PanelKit.ledger(_figures_box, rows)


func _build_buttons() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	_commit_button = Button.new()
	_commit_button.text = "Commit"
	_commit_button.pressed.connect(_on_commit)
	row.add_child(_commit_button)

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
	# Directly after the five rates and before the spending lines, because it is a
	# property OF the income tax rather than a sixth tax -- the panel reads in the order
	# docs/tiers/v1.md section 6 states the target in, "five taxes, plus brackets within
	# income".
	keys.append(PROGRESSIVITY_KEY)
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
		PROGRESSIVITY_KEY: ns.tax_progressivity,
	}
	for key in _lever_keys():
		var slider: HSlider = _sliders[key]
		slider.set_block_signals(true)
		slider.value = _pending_value(key)
		slider.set_block_signals(false)
	_edited = false
	_dirty = true


func _on_commit() -> void:
	var before := Trends.snapshot_now(_state)
	Budget.commit(_state, _pending)
	_on_revert()
	committed.emit(before)


func _on_lever_changed(value: float, key: String) -> void:
	if key == PROGRESSIVITY_KEY:
		_pending[PROGRESSIVITY_KEY] = value
	elif C.TAX_KEYS.has(key):
		_pending["tax_rates_pct"][key] = value
	else:
		_pending["spending_pct_gdp"][key] = value
	# The player has touched a slider, so _pending is now THEIRS and mark_dirty()
	# must stop re-syncing it from under them. Cleared by _on_revert(), which both
	# the Revert button and a commit go through.
	_edited = true
	_dirty = true


func _pending_value(key: String) -> float:
	if key == PROGRESSIVITY_KEY:
		return float(_pending.get(PROGRESSIVITY_KEY, TaxK.PROGRESSIVITY_BASE))
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
##
## RE-SYNCS _pending WHEN THE PLAYER HAS NOT EDITED IT, which is docs/tax-model.md
## section 11's bug. _pending was captured in setup() and refreshed only by a revert
## or a commit, so a rate moved by anything else -- Legislature.apply_effects(), which
## is also the applier for event choices and summit choices -- left this panel
## advertising the pre-change rates as the player's own proposal, and pressing Commit
## wrote them back and silently undid the law. The `_edited` gate is what section 11
## was waiting on: a half-finished edit is the player's and is never overwritten, and
## an untouched panel simply tracks the state.
func mark_dirty() -> void:
	if not _edited and _state != null:
		_on_revert()
	_dirty = true


## One decimal and a percent sign is right for a rate running to seventy and wrong for
## both levers V1.6d added: the wealth lever's whole span is three points, so one
## decimal prints thirty distinct values across it and the second decimal is where the
## choice lives, and the bracket index is not a percentage of anything at all. V1.6b's
## own screenshot bug -- a format copied from the neighbouring row -- one session on,
## avoided rather than repeated.
## Two decimals, chosen against the reachable range rather than copied from the row
## above: tax_constants.GINI_POLICY_MAX_PT bounds the whole policy offset at 8.60 points,
## but the grain a player moves it in is a bracket notch, which is hundredths. One
## decimal would print the same figure for two different budgets.
func _gini_text(snap: Dictionary) -> String:
	if not snap.has("gini_effective"):
		return "—"
	return "%.2f" % float(snap["gini_effective"])


func _lever_text(key: String) -> String:
	var value := _pending_value(key)
	if key == PROGRESSIVITY_KEY:
		return "%.2f" % value
	if key == "wealth":
		return "%.2f%%" % value
	return "%.1f%%" % value


func _refresh() -> void:
	_figures.clear()
	for key in _lever_keys():
		_lever_values[key].text = _lever_text(key)

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
	_set_figure("investment", _investment_text(now), _investment_text(proposed))
	_set_figure("projects", _projects_text(now), _projects_text(proposed))
	_set_figure("campaign", _campaign_text(now), _campaign_text(proposed))
	_set_figure("energy", _energy_text(now), _energy_text(proposed))
	_set_figure("deficit", _pct_and_eur(now, "deficit_pct_gdp"), _pct_and_eur(proposed, "deficit_pct_gdp"))
	_set_figure("debt", "%.1f%% GDP" % now["debt_to_gdp_pct"], "%.1f%% GDP" % proposed["debt_to_gdp_pct"])
	# NOT `.get(key, 0.0)`, and the screenshot pass is why. The first version defaulted,
	# the key was missing from Budget.snapshot() entirely, and the row printed a confident
	# "0.00" against a live index of about 31 -- a defensive default reading as a
	# plausible figure, which is _set_figure()'s own silent-return failure at V1.4c in a
	# new place. An em dash is what a missing figure looks like everywhere else on this
	# panel, and it is what a missing figure should look like here.
	_set_figure("gini", _gini_text(now), _gini_text(proposed))

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

	_fill_figures()


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


## The same em dash a fifth time. Unsigned like the two lines above it: an
## investment programme only ever costs, and what it buys is trend growth rather
## than money.
##
## THE MISSING-KEY BRANCH IS SEPARATE FROM THE ZERO BRANCH, and V1.6d is why. That
## session's row read a missing snapshot key with `.get(key, 0.0)` and printed a
## confident "0.00" against a live figure. Both branches print an em dash here, so
## the display is the same either way -- what is not the same is that a key vanishing
## from Budget.snapshot() cannot be quietly absorbed into "nothing is running".
func _investment_text(snap: Dictionary) -> String:
	if not snap.has("investment_bill_pct_gdp"):
		return "—"
	if is_zero_approx(float(snap["investment_bill_pct_gdp"])):
		return "—"
	return _pct_and_eur(snap, "investment_bill_pct_gdp")


## *** THE COUNT OF LIVE BUILDS WAS HERE AND THE FIFTEENTH SCREENSHOT PASS TOOK IT OUT,
## WHICH IS THIS SESSION'S ONE UI BUG AND IT WAS THIS FILE'S. *** The first version
## printed "0.19% (6 bn) (1 building)", and that cell is WIDER THAN ANY OTHER ON THE
## PANEL -- twenty-four characters against "46.10% (1473 bn)"'s sixteen. Both value
## columns size to their widest row, so one extra clause on one row pushed the whole
## `proposed` column past the window edge and put the panel on a horizontal scroll bar
## it had never needed. Nothing was wrong with the number; the frame simply showed a
## budget the player could not read without dragging.
##
## The count belongs on Public Works, which is where it now is, and that is this row's
## own comment used as a rule rather than as a decoration: three surfaces for one
## register only works if each says a DIFFERENT thing. The budget says what is being
## paid, the diary says when it lands, and Public Works says what and how many.
##
## The same em dash a sixth time, and the missing-key branch is separate for V1.6d's
## reason exactly as the line above it. Unsigned like the three lines above: building
## something only ever costs, and what it buys is trend growth rather than money.
func _projects_text(snap: Dictionary) -> String:
	if not snap.has("project_bill_pct_gdp"):
		return "—"
	if is_zero_approx(float(snap["project_bill_pct_gdp"])):
		return "—"
	return _pct_and_eur(snap, "project_bill_pct_gdp")


## The same em dash a seventh time, and the missing-key branch is separate for V1.6d's
## reason exactly as the two above it. Unsigned like them: a campaign only ever costs,
## and what it buys is turnout rather than money.
## The fleet's bill, silent at zero like the campaign's: a country that has
## ordered nothing is not paying anything, and a permanent "energy 0.000" row
## under a total it does not move would be a number with no consequence attached.
func _energy_text(snap: Dictionary) -> String:
	if not snap.has("energy_bill_pct_gdp"):
		return "—"
	if is_zero_approx(float(snap["energy_bill_pct_gdp"])):
		return "—"
	return _pct_and_eur(snap, "energy_bill_pct_gdp")


func _campaign_text(snap: Dictionary) -> String:
	if not snap.has("campaign_bill_pct_gdp"):
		return "—"
	if is_zero_approx(float(snap["campaign_bill_pct_gdp"])):
		return "—"
	return _pct_and_eur(snap, "campaign_bill_pct_gdp")


## The same em dash an eighth time, on the revenue side. Unsigned: a holding pays or
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


## Writes one row of the now/proposed table for this refresh.
##
## AN UNKNOWN KEY IS AN ERROR, and that is V2.1b rather than a tidy-up. This
## returned silently on a key with no FIGURE_ROWS entry, so V1.3g's
## `_set_figure("deployments", ...)` wrote into nothing for three sessions and
## V1.4a then documented a line that was not on the panel. It is V1.6d's rule --
## a default that hides a missing key is worse than a crash -- pointed at the
## writer instead of at the reader.
func _set_figure(key: String, now_text: String, pending_text: String) -> void:
	if not _figure_keys().has(key):
		push_error("budget_panel: '%s' has no FIGURE_ROWS entry, so nothing on the panel says it" % key)
		return
	_figures[key] = [now_text, pending_text]


func _figure_keys() -> Array:
	var out: Array = []
	for row in FIGURE_ROWS:
		if row[0] != "":
			out.append(row[0])
	return out


## The control this panel exists to let the player press -- V2.1a's fold contract,
## declared here at V2.1b.
##
## Commit rather than Revert, on the rule that this is the FIRST verb rather than
## the most important one: they sit in that order in _build_buttons(), and a panel
## whose first verb has scrolled off is already a panel whose verbs are hidden.
func primary_action() -> Control:
	return _commit_button
