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
	["spending", "Spending"],
	["debt_service", "  of which debt service"],
	["deficit", "Deficit"],
	["debt", "Debt"],
	["", ""],
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
	_set_figure("spending", _pct_and_eur(now, "total_spending_pct_gdp"), _pct_and_eur(proposed, "total_spending_pct_gdp"))
	_set_figure("debt_service", _pct_and_eur(now, "debt_service_pct_gdp"), _pct_and_eur(proposed, "debt_service_pct_gdp"))
	_set_figure("deficit", _pct_and_eur(now, "deficit_pct_gdp"), _pct_and_eur(proposed, "deficit_pct_gdp"))
	_set_figure("debt", "%.1f%% GDP" % now["debt_to_gdp_pct"], "%.1f%% GDP" % proposed["debt_to_gdp_pct"])

	var last_now: Dictionary = now_path[-1]
	var last_proposed: Dictionary = proposed_path[-1]
	_set_figure("proj_growth", "%.2f%%" % last_now["growth_annual_pct"], "%.2f%%" % last_proposed["growth_annual_pct"])
	_set_figure("proj_unemployment", "%.2f%%" % last_now["unemployment_pct"], "%.2f%%" % last_proposed["unemployment_pct"])
	_set_figure("proj_debt", "%.1f%%" % last_now["debt_to_gdp_pct"], "%.1f%%" % last_proposed["debt_to_gdp_pct"])


## An em dash rather than "0.00%" while nothing is imposed. The two say different
## things: a zero invites the player to wonder what they did wrong, where a dash
## says the line is not in play. Every game that has never used the verb reads the
## dash, which is most of them.
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
