extends PanelContainer

## The tax code -- V4.2 T5. The tier's own sentence is why this surface exists
## and why budget_panel.gd no longer carries these rows: tax comes out of the
## Budget panel into its own place. Five authored rates and the brackets lever.
## The player-composed tax (V4.2 T4's "Propose a tax" flow and its born-key
## rows) retired at V5.3 e, in favour of the tax library.
##
## THE SCAN IS OFF THE REGISTER. The rows are the nation's tax kinds in force
## (V5.3 e, data/taxes/), in library order. Rows are BUILT from the scan and not from a const:
## at _ready() no state exists to scan, so the grid fills on the first refresh
## after setup().
##
## Reads simulation state and never writes it. The single exception is the
## Commit button, which sends player intent back as an explicit command --
## the finance bill's tabling. Pending slider
## positions live here, not in the simulation. The commit reuses the budget
## panel's verb and its per-key lever maxima; the brief asked for the house
## idioms, not a second way to move a rate.

## Commit tables the rates into the finance bill (docs/design/finance-bill.md).
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const Strings = preload("res://src/ui/strings.gd")
const Trends = preload("res://src/ui/trends.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")

## The one lever that is not a key in `tax_rates_pct`: it sets no rate, has
## no base and collects nothing -- budget_panel's PROGRESSIVITY_KEY comment,
## moved with the lever. It rides `pending` as a top-level scalar for the
## same reason it always did.
const PROGRESSIVITY_KEY := "tax_progressivity"

## Display names for today's five, keyed by live key -- presence is the register's
## question, this table only answers "what is it called". A kind the table lacks
## shows its library row's name (V5.3 e).
const KEY_LABELS := {
	"income": "Income tax",  # i18n: msgid
	"corporate": "Corporate tax",  # i18n: msgid
	"vat": "VAT",
	"capital_gains": "Capital gains tax",  # i18n: msgid
	"wealth": "Wealth tax",  # i18n: msgid
	PROGRESSIVITY_KEY: "Income brackets",  # i18n: msgid
}

## The brackets lever's ceiling. A tax kind's is its library row's `rate_range_pct`
## (V5.3 e): the slider, the loader's range check and the finance bill read one bound.
const LEVER_MAX := {
	PROGRESSIVITY_KEY: TaxK.PROGRESSIVITY_MAX,
}

signal committed(before: Dictionary, pending: Dictionary)

var _state
var _loader
var _pending := {"tax_rates_pct": {}, PROGRESSIVITY_KEY: TaxK.PROGRESSIVITY_BASE}
var _edited_keys := {}
var _sliders := {}
var _lever_values := {}
var _title: Label
var _rates_grid: GridContainer
var _dirty := true
var _close_button: Button
var _commit_button: Button
var _withdraw_button: Button
## V5.3 a + b (docs/design/v5.3-ab.md 4.1): each row's yield on the books as they
## stand and its balance effect once moved, and the strip that says what Commit
## books -- read in the tab where the rate is made. `_effects` is the panel's own
## figure per key (EffectsStrip.COMMIT for the strip), read by tests/test_effects_strip.gd
## beside the text each cell prints (band B1). `_now_books` is the books with
## nothing pending, kept across a drag (a drag cannot move them) and dropped on
## anything that can.
var _strip: EffectsStrip
var _effect_labels := {}
var _yield_labels := {}
var _effects := {}
var _fx_cache := {}
var _now_books := {}
## The Budget window and the window manager, wired by main.gd: the Budget's draft
## is one line under this tab's strip, with a Go there (the mirror of the
## Budget's line about this tab's draft). Null until wired; every read guards it.
var budget_panel = null
var windows = null


func _ready() -> void:
	custom_minimum_size = Vector2(720, 480)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title = Label.new()
	root.add_child(_title)
	_strip = EffectsStrip.new()
	_strip.go_pressed.connect(func() -> void:
		if windows != null:
			windows.open("budget"))
	# Its figure beside its caption: the rows below are a third of the window wide.
	_strip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	root.add_child(_strip)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	_rates_grid = GridContainer.new()
	_rates_grid.columns = 5
	_rates_grid.add_theme_constant_override("h_separation", 12)
	body.add_child(_rates_grid)
	for text in ["", "", tr("rate"), tr("yield, bn"), tr("change")]:
		var head := Label.new()
		head.text = text
		head.theme_type_variation = PanelKit.UiTheme.CAPTION
		head.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rates_grid.add_child(head)

	root.add_child(_build_buttons())


## One row per live key, built on demand. Called from every path that reads a
## slider, because no state exists at _ready() to build the rows from.
func _ensure_rows() -> void:
	for key in _lever_keys():
		if _sliders.has(key):
			continue
		var name_label := Label.new()
		name_label.text = _label_for(String(key))
		name_label.custom_minimum_size.x = 150
		_rates_grid.add_child(name_label)

		var slider := HSlider.new()
		slider.min_value = _lever_min(String(key))
		slider.max_value = _lever_max(String(key))
		# The budget panel's grain rule, moved with the sliders: a tenth of a
		# point over a seventy-point span, hundredths where the whole span is
		# a few points (wealth's stock-scale rate, the bracket index).
		slider.step = 0.01 if String(key) == "wealth" or String(key) == PROGRESSIVITY_KEY else 0.1
		slider.custom_minimum_size.x = 220
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(_on_lever_changed.bind(String(key)))
		_rates_grid.add_child(slider)
		_sliders[key] = slider

		# THE RATE AS A NUMBER, the ask this panel exists to answer: the live
		# figure printed beside its slider, where budget's old grid carried
		# it too -- the number is the point of the row, not a tooltip on it.
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 60
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_rates_grid.add_child(value_label)
		_lever_values[key] = value_label
		_yield_labels[key] = EffectsStrip.cell(_rates_grid)
		_effect_labels[key] = EffectsStrip.cell(_rates_grid)


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

	# QA's T1 on #331: the tabled finance bill taken back before its vote, answered like
	# Commit. Here alone: the Budget sits at the size cap, and screen 4 shows the bill.
	# Shown only while a finance bill is tabled (_refresh), so it is never a dead verb.
	_withdraw_button = Button.new()
	_withdraw_button.text = tr("Withdraw the bill")
	_withdraw_button.pressed.connect(func(): committed.emit(Trends.snapshot_now(_state), FinanceBill.withdraw(_state)))
	row.add_child(_withdraw_button)

	_close_button = Button.new()
	_close_button.text = tr("Close (X)")
	_close_button.pressed.connect(func(): hide())
	row.add_child(_close_button)

	return row


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	var ns = _state.player()
	_title.text = tr("TAX CODE — %s") % ns.id
	_on_revert()


## The register, in reading order: the authored five the nation carries.
func _lever_keys() -> Array:
	var ns = _state.player()
	var keys: Array = []
	if ns != null:
		keys.append_array(TaxLibrary.in_force(ns))
	keys.append(PROGRESSIVITY_KEY)
	return keys


## A tax kind's floor is its band's low end, as its ceiling is the high end: a lever that
## reached below it would draft a rate the finance bill refuses (`range`, #339) and keep
## the refused draft on the levers. The brackets index keeps its floor of 0.
func _lever_min(key: String) -> float:
	if LEVER_MAX.has(key):
		return 0.0
	return float(_state.player().tax_library[key]["rate_range_pct"][0])


func _lever_max(key: String) -> float:
	if LEVER_MAX.has(key):
		return float(LEVER_MAX[key])
	return float(_state.player().tax_library[key]["rate_range_pct"][1])


func _label_for(key: String) -> String:
	if not KEY_LABELS.has(key):
		return Strings.row_name("taxes", _state.player().tax_library[key])
	return tr(String(KEY_LABELS[key]))


func _on_revert() -> void:
	var ns = _state.player()
	# Guarded because this is on the generic mark_all_dirty() sweep -- every
	# other panel guards the same way.
	if ns == null:
		return
	_pending = {
		"tax_rates_pct": ns.tax_rates_pct.duplicate(true),
		PROGRESSIVITY_KEY: ns.tax_progressivity,
	}
	_ensure_rows()
	for key in _lever_keys():
		var slider: HSlider = _sliders[key]
		slider.set_block_signals(true)
		slider.max_value = _lever_max(String(key))
		slider.value = _pending_value(String(key))
		slider.set_block_signals(false)
	_edited_keys.clear()
	_now_books = {}
	_dirty = true


func _on_commit() -> void:
	var before := Trends.snapshot_now(_state)
	var tabling := FinanceBill.table(_state, _loader, FinanceBill.from_pending(_state.player(), _pending))
	# A refusal (a law holds the month's slot) keeps the draft on the levers.
	if bool(tabling.get("tabled", false)):
		_on_revert()
	committed.emit(before, tabling)


## What this tab's Commit would book, or nothing while no rate stands away from
## its live value -- read by the Budget for its line about this draft (V4.2's
## ultra pass 2 merged it into the Budget's columns; V5.3 a + b made it a line).
func draft() -> Dictionary:
	for key in _edited_keys:
		if _pending_value(String(key)) != _live(String(key)):
			return pending_tax()
	return {}


func _live(key: String) -> float:
	var ns = _state.player()
	return float(ns.tax_progressivity) if key == PROGRESSIVITY_KEY else float(ns.tax_rates_pct.get(key, 0.0))


## The uncommitted tax intent, EDITED KEYS ONLY, mirroring what the player
## actually moved: Budget.commit() splices per key and an untouched lever's
## pending value is just the live rate restated. Read-only; the commit is still
## this panel's own verb.
func pending_tax() -> Dictionary:
	var out := {"tax_rates_pct": {}}
	for key in _edited_keys:
		if String(key) == PROGRESSIVITY_KEY:
			out["tax_progressivity"] = _pending_value(PROGRESSIVITY_KEY)
		else:
			out["tax_rates_pct"][key] = _pending_value(String(key))
	return out


func _on_lever_changed(value: float, key: String) -> void:
	if key == PROGRESSIVITY_KEY:
		_pending[PROGRESSIVITY_KEY] = value
	else:
		_pending["tax_rates_pct"][key] = value
	_edited_keys[key] = true
	_dirty = true


func _pending_value(key: String) -> float:
	if key == PROGRESSIVITY_KEY:
		return float(_pending.get(PROGRESSIVITY_KEY, TaxK.PROGRESSIVITY_BASE))
	return float(_pending["tax_rates_pct"].get(key, 0.0))


## Sliders fire many times during a drag; coalesce to one refresh per frame,
## the budget panel's own discipline.
func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_resync_untouched()
	_now_books = {}
	_dirty = true


## The budget panel's per-lever gate, moved with the levers: a law, an event
## or a summit can move a rate under the player's feet, and a lever the
## player has NOT edited simply tracks the state -- one that has is theirs
## and is never overwritten.
func _resync_untouched() -> void:
	if _state == null:
		return
	var ns = _state.player()
	if ns == null or _rates_grid == null:
		return
	_ensure_rows()
	for key in _lever_keys():
		if _edited_keys.has(key):
			continue
		var live: float = float(ns.tax_progressivity) if String(key) == PROGRESSIVITY_KEY \
			else float(ns.tax_rates_pct.get(key, 0.0))
		if String(key) == PROGRESSIVITY_KEY:
			_pending[PROGRESSIVITY_KEY] = live
		else:
			_pending["tax_rates_pct"][key] = live
		var slider: HSlider = _sliders[key]
		slider.set_block_signals(true)
		slider.value = live
		slider.set_block_signals(false)


## THE RATE AS A NUMBER, not a rate as a decoration: the print is the bare
## figure, which is what "the rate" means -- the player reads it against the
## slider's position, not against a unit the label's caption already states.
func _lever_text(key: String) -> String:
	var value := _pending_value(key)
	if key == "wealth" or key == PROGRESSIVITY_KEY:
		return PanelKit.Num.f(value, 2)
	return PanelKit.Num.f(value, 1)


func _refresh() -> void:
	_ensure_rows()
	_withdraw_button.visible = FinanceBill.FinanceBillLaw.tabled(_state.player()) != null
	for key in _lever_keys():
		_lever_values[key].text = _lever_text(String(key))
	if _now_books.is_empty():
		_now_books = EffectsStrip.books(_state, {})
	for key in _lever_keys():
		_yield_labels[key].text = EffectsStrip.yield_text(_now_books, String(key))
	# Each moved rate priced alone, and the strip on what Commit books (the edited
	# keys: an untouched row's pending is its live rate restated).
	# A rate dragged back to its live value is not a move: no cell, no strip.
	var alone := {}
	for key in _edited_keys:
		if _pending_value(String(key)) == _live(String(key)):
			continue
		alone[key] = {"tax_rates_pct": {}}
		if String(key) == PROGRESSIVITY_KEY:
			alone[key][PROGRESSIVITY_KEY] = _pending_value(PROGRESSIVITY_KEY)
		else:
			alone[key]["tax_rates_pct"][key] = _pending_value(String(key))
	if not alone.is_empty():
		alone[EffectsStrip.COMMIT] = pending_tax()
	var spending_draft: Dictionary = budget_panel.draft() if budget_panel != null else {}
	if not spending_draft.is_empty():
		alone[EffectsStrip.ELSEWHERE] = spending_draft
	_effects = EffectsStrip.per_key(_fx_cache, _state, _now_books, alone, alone.get(EffectsStrip.COMMIT, {}), {})
	EffectsStrip.paint(_effect_labels, _effects)
	_strip.show_effects(float(_effects.get(EffectsStrip.COMMIT, 0.0)), "", "", _effects.has(EffectsStrip.COMMIT),
		tr("Spending changes not yet committed: %s a year, in the Budget") % EffectsStrip.money_text(_effects[EffectsStrip.ELSEWHERE])
		if _effects.has(EffectsStrip.ELSEWHERE) else "", float(_effects.get(EffectsStrip.ELSEWHERE, 0.0)))


## The control this panel exists to let the player press -- V2.1a's fold
## contract, declared here at birth. Commit is the first verb in build order,
## the budget panel's own rule.
func primary_action() -> Control:
	return _commit_button
