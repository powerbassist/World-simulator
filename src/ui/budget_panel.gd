extends PanelContainer

## The budget screen. Five spending levers, the books as they stand, the
## books as proposed, and a two-year projection of both. V4.2 T5 moved the
## tax levers out: tax comes out of the Budget panel into its own surface --
## the Tax Code window (X), which carries the rates, the brackets and the
## born keys, on the cluster grammar that a surface is the domain of its
## decision. This panel keeps the spending side of the same books.
##
## Reads simulation state and never writes it. The single exception is the
## Commit button, which sends player intent back as one explicit command —
## Budget.commit(). Pending slider positions live here, not in the simulation.
## See engine-decision.md Rule 2.
##
## The control tree is built in code rather than authored as a .tscn: it is a
## generated grid of identical rows, which a scene file would describe
## worse and more verbosely than the loop below.

const Budget = preload("res://src/sim/budget.gd")
const C = preload("res://src/sim/economy_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const PanelCharts = preload("res://src/ui/panel_charts.gd")
const Forecast = preload("res://src/ui/budget_forecast.gd")
const Ledger = preload("res://src/ui/budget_ledger.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")

const PROJECTION_MONTHS := 24

const LEVER_LABELS := {
	"health": "Health",  # i18n: msgid
	"education": "Education",  # i18n: msgid
	"defence": "Defence",  # i18n: msgid
	"pensions": "Pensions",  # i18n: msgid
	"infrastructure": "Infrastructure",  # i18n: msgid
}
const LEVER_MAX := {
	"health": 30.0,
	"education": 30.0,
	"defence": 30.0,
	"pensions": 30.0,
	"infrastructure": 30.0,
}
## How far a lever reaches either side of its committed value, in points of GDP
## (QA's pre-gate drag moved Health 5.3 points in 38 px; the author approved five
## either side). V5.1-d1b3, the parent's call on QA's #69 finding: the track keeps
## the line's whole range, so the knob reads as the LEVEL -- the first build gave the
## slider only the span, and Education 5.5 and Pensions 14.5 sat in one place. The
## span's ends are marked on the track, and a drag past one stops there with a cue.
## A move bigger than five is a second commit; the span re-centres on each one.
const LEVER_SPAN := 5.0
## How long a span end shows the stop it just made.
const CUE_MS := 700


## Carries the state Trends.snapshot_now() took the instant before Budget.commit()
## ran -- U4's decision-effects baseline. Taken here, not in main.gd, because by
## the time main.gd hears this signal the commit has already happened.
signal committed(before: Dictionary, pending: Dictionary)

var _state
var _loader
## The Tax Code window, wired by main.gd beside the other panel-to-panel
## references. V4.2 ultra pass 2 merged its uncommitted edits into this panel's
## proposed column and projection; since V5.3 a + b (the parent's call on #247)
## every figure here is what THIS tab's Commit books, and the Tax Code's draft is
## one separate line under the strip, with a Go to that tab. A sibling reference,
## not state; null until wired, and every read guards it.
var tax_panel = null
## The window manager, for that line's Go; null until main.gd wires it.
var windows = null
var _pending := {"spending_pct_gdp": {}}
## The lever keys the player has actually moved. PER KEY rather than one boolean:
## a boolean latches -- nudge one slider, close the window without committing, and
## every OTHER lever stopped tracking live state for the rest of the run, which is
## docs/tax-model.md section 11's bug surviving in the fix for it. Keyed, an
## untouched lever re-syncs while the player's own edit is never overwritten.
## Cleared by _on_revert(), which both the Revert button and a commit go through.
var _edited_keys := {}
var _sliders := {}
## Per lever: the value its span is centred on, and when its last stop's cue ends.
var _span_at := {}
var _cue_until := {}
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
## V5.1-0a. The 24-month forecast, computed off the frame (budget_forecast.gd);
## and the "now" books, reused on the refreshes a lever move asks for -- a lever
## cannot move "now", and one preview is ~19 ms of a dragged frame. Any other
## refresh (a commit, a month, a state written behind the panel) recomputes it.
var _forecast := Forecast.new()
var _now_preview := {}
var _lever_moved := false

## The verb this panel exists for. Built once in _ready() and alive for the
## session, so it is held rather than re-found. See primary_action().
var _commit_button: Button
## V5.3 a + b (docs/design/v5.3-ab.md 4.1): each moved lever's balance effect, in
## the cell beside its value, and the strip that says what Commit books. `_effects`
## is the panel's own figure, keyed by lever (EffectsStrip.COMMIT for the strip), read by
## tests/test_effects_strip.gd beside the text the cell prints (band B1).
var _strip: EffectsStrip
var _effect_labels := {}
var _effects := {}
var _fx_cache := {}


func _ready() -> void:
	# Placement is the owner's job — main.gd drops this into a CenterContainer.
	# S4 called set_anchors_preset(PRESET_CENTER) here, which moves the anchors and
	# leaves the offsets at zero, so the panel actually sat in the top-left corner
	# on top of the HUD. Never noticed, because it had only ever been tested
	# headlessly.
	custom_minimum_size = Vector2(820, 520)

	var root := PanelKit.padded(self, 16, 12)

	_title = Label.new()
	root.add_child(_title)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(columns)

	columns.add_child(_build_levers())
	columns.add_child(_build_figures())

	root.add_child(PanelCharts.new(self, PanelCharts.BUDGET))
	root.add_child(_build_buttons())
	add_child(_forecast)
	_forecast.settled.connect(func(): _dirty = true)


func _build_levers() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	PanelKit.heading(box, tr("Spending, % of GDP"))

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	box.add_child(grid)

	for key in _lever_keys():
		var name_label := Label.new()
		name_label.text = tr(LEVER_LABELS[key])
		name_label.custom_minimum_size.x = 130
		grid.add_child(name_label)

		var slider := HSlider.new()
		# A tenth of a point everywhere: the spending levers all run to
		# thirty, where one decimal prints three hundred distinct positions.
		# (The fine-grained rows moved to the Tax Code window with the rates.)
		slider.max_value = float(LEVER_MAX[key])
		slider.step = 0.1
		# 200, not 220: G11's caption size took the window's last 20 px under +35%
		# pseudo, and since d1b3 the span, not the track's width, guards a drag.
		# 140 since V5.3 a + b: the change column took 89 px of the band, and the
		# track still fills the window it is docked in -- this is its floor only.
		slider.custom_minimum_size.x = 140
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.draw.connect(_draw_span.bind(key))
		slider.value_changed.connect(_on_lever_changed.bind(key))
		# V5.3-0 RF3: a lever acts on the balance (the briefing's budget Go).
		grid.add_child(preload("res://src/ui/acts_on.gd").tag(slider, ["deficit", "balance"]))
		_sliders[key] = slider

		var value_label := Label.new()
		value_label.custom_minimum_size.x = 60
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value_label)
		_lever_values[key] = value_label
		# V5.3 a + b: the lever's balance effect on a line of its own under the
		# track, at the value's edge -- a fourth column took the window past its
		# band under +35% pseudo, and this column has height to spare.
		grid.add_child(Control.new())
		_effect_labels[key] = EffectsStrip.cell(grid)
		_effect_labels[key].size_flags_horizontal = Control.SIZE_SHRINK_END
		grid.add_child(Control.new())

	return box


## The strip first, then the table: the balance a commit books is the first figure
## the right-hand column reads (spec 4.1, "the balance row's change ... comes first").
func _build_figures() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip = EffectsStrip.new()
	_strip.go_pressed.connect(func() -> void:
		if windows != null:
			windows.open("tax"))
	column.add_child(_strip)
	_figures_box = VBoxContainer.new()
	column.add_child(_figures_box)
	return column


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

	var rows: Array = [["", "now", "proposed", tr("change")]]
	for row in Ledger.FIGURE_ROWS:
		var key: String = row[0]
		if key == "":
			rows.append([tr(row[1]), "", ""])
			continue
		var cells: Array = _figures.get(key, [PanelKit.MISSING, PanelKit.MISSING])
		rows.append([tr(row[1])] + cells)
	PanelKit.ledger(_figures_box, rows)


func _build_buttons() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	_commit_button = Button.new()
	_commit_button.text = tr("Commit")
	_commit_button.pressed.connect(_on_commit)
	row.add_child(_commit_button)

	var revert := Button.new()
	revert.text = tr("Revert")
	revert.pressed.connect(_on_revert)
	row.add_child(revert)

	_close_button = Button.new()
	_close_button.text = tr("Close (B)")
	_close_button.pressed.connect(func(): hide())
	row.add_child(_close_button)

	return row


## Docked-tab mode, for the dashboard: the rail already selects a different tab
## to leave this one, so a "Close" button that just hides the panel inside its
## own tab would show a blank tab. Same idiom as save_load_panel.hide_save_row().
func hide_close_button() -> void:
	_close_button.hide()


func _lever_keys() -> Array:
	# The five spending keys only, since V4.2 T5: the tax side (five rates,
	# the brackets lever, the born keys) lives on the Tax Code window now.
	var keys: Array = []
	keys.append_array(C.SPENDING_KEYS)
	return keys


## `loader` since V1.3b: Budget.project() needs it to drift relations the way the
## real game does, or the projected path and the played one disagree.
func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_forecast.setup(state, loader, PROJECTION_MONTHS)
	var ns = _state.player()
	_title.text = tr("BUDGET — %s") % _loader.nation_name(ns.id)
	_on_revert()


func _on_revert(state_moved := false) -> void:
	var ns = _state.player()
	# Guarded because this is on the generic mark_all_dirty() sweep now, not just on
	# setup() and two button presses -- every other panel guards the same way.
	if ns == null:
		return
	_pending = {"spending_pct_gdp": ns.spending_pct_gdp.duplicate(true)}
	for key in _lever_keys():
		_set_lever(key, _pending_value(key))
	_edited_keys.clear()
	# mark_dirty() for a commit (V5.1-0a review pass 1): the forecast keeps its
	# projection until told the state moved. A plain Revert moved none, so the
	# forecast on screen stands -- re-projecting it was ~5 s of work (D14, V5.1-d2).
	if state_moved: mark_dirty()
	_dirty = true


func _on_commit() -> void:
	var before := Trends.snapshot_now(_state)
	# Captured before the commit: _on_revert() clears the levers, and the card
	# the shell pushes should name what was actually committed, not the
	# reverted zero.
	var pending := _pending.duplicate()
	Budget.commit(_state, _pending)
	_on_revert(true)
	committed.emit(before, pending)


func _on_lever_changed(value: float, key: String) -> void:
	var span := lever_span(key)
	if value < span.x or value > span.y:
		_set_lever(key, clampf(value, span.x, span.y), false)
		value = _sliders[key].value
		_cue_until[key] = Time.get_ticks_msec() + CUE_MS
		get_tree().create_timer(CUE_MS / 1000.0).timeout.connect(_sliders[key].queue_redraw)
	_pending["spending_pct_gdp"][key] = value
	# This lever is now the player's; mark_dirty() must stop re-syncing THIS one.
	_edited_keys[key] = true
	_lever_moved = true
	_dirty = true


func _pending_value(key: String) -> float:
	return float(_pending["spending_pct_gdp"].get(key, 0.0))


## Sliders fire many times during a drag, and every refresh runs two 24-month
## projections. Coalesce to at most one refresh per frame.
##
## is_visible_in_tree(), not `visible`: the panel's own flag stays true inside a
## CLOSED window, and the month's sweep marks every panel dirty, so the two
## projections (~12 s at 41 nations) ran every month with the window shut --
## the V5.0 play gate's 11-second month end. Hidden, the panel stays dirty and
## redraws when its window opens.
func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
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
## wrote them back and silently undid the law. The PER-LEVER gate is what section 11
## was waiting on: a lever the player has moved is theirs and is never overwritten,
## and every lever they have not simply tracks the state.
func mark_dirty() -> void:
	_resync_untouched()
	_forecast.state_changed()
	_now_preview = {}
	_dirty = true


## Pull every lever the player has NOT moved back into line with live state, and
## leave the ones they have alone. This is what stops a law, an event choice or a
## summit choice -- all three go through Legislature.apply_effects() -- from leaving
## this panel advertising pre-change rates as the player's own proposal, which
## pressing Commit would then write back and silently undo.
func _resync_untouched() -> void:
	if _state == null:
		return
	var ns = _state.player()
	if ns == null or _sliders.is_empty():
		return
	for key in _lever_keys():
		if _edited_keys.has(key):
			continue
		var live: float = float(ns.spending_pct_gdp.get(key, 0.0))
		_pending["spending_pct_gdp"][key] = live
		_set_lever(key, live)


## A lever set from the state, without firing its edit: its span re-centred on the
## value (LEVER_SPAN), never past 0 or the line's ceiling.
func _set_lever(key: String, value: float, recentre := true) -> void:
	var slider: HSlider = _sliders[key]
	if recentre:
		_span_at[key] = value
	slider.set_block_signals(true)
	slider.value = value
	slider.set_block_signals(false)
	slider.queue_redraw()


## [low, high] a lever may reach this commit: LEVER_SPAN either side of its value
## when last set from the state, inside 0 and the line's ceiling.
func lever_span(key: String) -> Vector2:
	var at: float = float(_span_at.get(key, 0.0))
	return Vector2(maxf(0.0, at - LEVER_SPAN), minf(float(LEVER_MAX[key]), at + LEVER_SPAN))


func lever_cued(key: String) -> bool:
	return Time.get_ticks_msec() < int(_cue_until.get(key, 0))


## The span's two ends, hairlines across the track: a caption tone, the attention
## tone for CUE_MS after a drag stopped at one.
func _draw_span(key: String) -> void:
	var slider: HSlider = _sliders[key]
	var tone: Color = PanelKit.UiTheme.WARN if lever_cued(key) else PanelKit.UiTheme.TEXT_DIM
	for v in [lever_span(key).x, lever_span(key).y]:
		var x: float = slider.size.x * v / slider.max_value
		slider.draw_line(Vector2(x, 0.0), Vector2(x, slider.size.y), tone, 1.0)


func _lever_text(key: String) -> String:
	return "%s%%" % PanelKit.Num.f(_pending_value(key), 1)


## The two finance tabs, each told of the other and of the window manager (for
## the draft line's Go): one call, so main.gd wires the pair in one line.
func pair(tax, window_manager) -> void:
	tax_panel = tax
	tax.budget_panel = self
	windows = window_manager
	tax.windows = window_manager


## What this tab's Commit would book, or nothing while no lever stands away from
## its live value -- read by the Tax Code for its line about this draft.
func draft() -> Dictionary:
	var ns = _state.player() if _state != null else null
	for key in _edited_keys:
		if ns != null and _pending_value(key) != float(ns.spending_pct_gdp.get(key, 0.0)):
			return _pending
	return {}


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
	#
	# NO TAX MERGE since V5.3 a + b (the parent's call on #247, band B1): V4.2's
	# ultra pass 2 merged the Tax Code's draft into these columns, so the proposed
	# and change columns showed what this tab's Commit does NOT book. The draft is
	# still never silent -- it is its own line under the strip, priced alone.
	var pending: Dictionary = _pending
	if _now_preview.is_empty() or not _lever_moved:
		_now_preview = Budget.preview(_state, {})
	_lever_moved = false
	var now: Dictionary = _now_preview
	# Nothing edited: nothing is proposed, and the column repeats "now".
	var edited: bool = not _edited_keys.is_empty()
	var proposed: Dictionary = Budget.preview(_state, pending) if edited else now

	_set_figure("revenue", Ledger.pct_and_eur(now, "total_revenue_pct_gdp"), Ledger.pct_and_eur(proposed, "total_revenue_pct_gdp"))
	_set_figure("tariffs", Ledger.line_text(now, "tariff_revenue_pct_gdp"), Ledger.line_text(proposed, "tariff_revenue_pct_gdp"))
	_set_figure("dividends", Ledger.line_text(now, "dividend_revenue_pct_gdp"), Ledger.line_text(proposed, "dividend_revenue_pct_gdp"))
	_set_figure("spending", Ledger.pct_and_eur(now, "total_spending_pct_gdp"), Ledger.pct_and_eur(proposed, "total_spending_pct_gdp"))
	_set_figure("debt_service", Ledger.pct_and_eur(now, "debt_service_pct_gdp"), Ledger.pct_and_eur(proposed, "debt_service_pct_gdp"))
	_set_figure("bloc_transfer", Ledger.bloc_text(now), Ledger.bloc_text(proposed))
	_set_figure("deployments", Ledger.line_text(now, "deployment_bill_pct_gdp"), Ledger.line_text(proposed, "deployment_bill_pct_gdp"))
	_set_figure("subsidies", Ledger.line_text(now, "subsidy_bill_pct_gdp"), Ledger.line_text(proposed, "subsidy_bill_pct_gdp"))
	_set_figure("investment", Ledger.bill_text(now, "investment_bill_pct_gdp"), Ledger.bill_text(proposed, "investment_bill_pct_gdp"))
	_set_figure("projects", Ledger.bill_text(now, "project_bill_pct_gdp"), Ledger.bill_text(proposed, "project_bill_pct_gdp"))
	_set_figure("energy", Ledger.bill_text(now, "energy_bill_pct_gdp"), Ledger.bill_text(proposed, "energy_bill_pct_gdp"))
	_set_figure("deficit", Ledger.pct_and_eur(now, "deficit_pct_gdp"), Ledger.pct_and_eur(proposed, "deficit_pct_gdp"))
	_set_figure("debt", tr("%s%% GDP") % PanelKit.Num.f(now["debt_to_gdp_pct"], 1), tr("%s%% GDP") % PanelKit.Num.f(proposed["debt_to_gdp_pct"], 1))
	# NOT `.get(key, 0.0)`, and the screenshot pass is why. The first version defaulted,
	# the key was missing from Budget.snapshot() entirely, and the row printed a confident
	# "0.00" against a live index of about 31 -- a defensive default reading as a
	# plausible figure, which is _set_figure()'s own silent-return failure at V1.4c in a
	# new place. An em dash is what a missing figure looks like everywhere else on this
	# panel, and it is what a missing figure should look like here.
	_set_figure("gini", Ledger.gini_text(now), Ledger.gini_text(proposed))

	# V5.1-0a: the forecast follows the levers rather than freezing them.
	_forecast.want(pending, edited)
	var rows: Dictionary = _forecast.rows(_state.player())
	for key in rows.keys():
		_set_figure(key, rows[key][0], rows[key][1])

	# V5.3 a + b: each moved lever priced alone -- the live budget with that one
	# line moved -- the strip on what Commit books, and the Tax Code's draft alone.
	var ns = _state.player()
	# A lever dragged back to its live value is not a move: no cell, no strip.
	var alone := {}
	for key in _edited_keys:
		if _pending_value(key) == float(ns.spending_pct_gdp.get(key, 0.0)):
			continue
		alone[key] = {"spending_pct_gdp": ns.spending_pct_gdp.duplicate()}
		alone[key]["spending_pct_gdp"][key] = _pending_value(key)
	if not alone.is_empty():
		alone[EffectsStrip.COMMIT] = _pending
	var tax_draft: Dictionary = tax_panel.draft() if tax_panel != null else {}
	if not tax_draft.is_empty():
		alone[EffectsStrip.ELSEWHERE] = tax_draft
	_effects = EffectsStrip.per_key(_fx_cache, _state, now, alone, pending, proposed)
	EffectsStrip.paint(_effect_labels, _effects)
	_strip.show_effects(float(_effects.get(EffectsStrip.COMMIT, 0.0)), "", "", _effects.has(EffectsStrip.COMMIT),
		tr("Tax changes not yet committed: %s a year, in the Tax Code") % EffectsStrip.money_text(_effects[EffectsStrip.ELSEWHERE])
		if _effects.has(EffectsStrip.ELSEWHERE) else "", float(_effects.get(EffectsStrip.ELSEWHERE, 0.0)))
	Ledger.add_changes(_figures, now, proposed)
	_fill_figures()


## Writes one row of the now/proposed table for this refresh.
##
## AN UNKNOWN KEY IS AN ERROR, and that is V2.1b rather than a tidy-up. This
## returned silently on a key with no FIGURE_ROWS entry, so V1.3g's
## `_set_figure("deployments", ...)` wrote into nothing for three sessions and
## V1.4a then documented a line that was not on the panel. It is V1.6d's rule --
## a default that hides a missing key is worse than a crash -- pointed at the
## writer instead of at the reader.
func _set_figure(key: String, now_text: String, pending_text: String) -> void:
	if not Ledger.figure_keys().has(key):
		push_error("budget_panel: '%s' has no FIGURE_ROWS entry, so nothing on the panel says it" % key)
		return
	_figures[key] = [now_text, pending_text]



## The control this panel exists to let the player press -- V2.1a's fold contract,
## declared here at V2.1b.
##
## Commit rather than Revert, on the rule that this is the FIRST verb rather than
## the most important one: they sit in that order in _build_buttons(), and a panel
## whose first verb has scrolled off is already a panel whose verbs are hidden.
func primary_action() -> Control:
	return _commit_button
