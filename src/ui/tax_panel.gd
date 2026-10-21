extends PanelContainer

## The tax code -- V4.2 T5. The tier's own sentence is why this surface exists
## and why budget_panel.gd no longer carries these rows: tax comes out of the
## Budget panel into its own place. Five authored rates, the brackets lever,
## every key the composition machine has BORN, and the one flow that births a
## new one.
##
## THE SCAN IS OFF THE REGISTER. The rows are `ns.tax_rates_pct`'s keys --
## authored five plus any composed key, in that order -- and nothing else: a
## hand-written key list is this repo's banned failure class, because the key
## a list does not know is a rate the player can move nowhere. The labels are
## the only table here: display names keyed BY live keys, with a composed
## key's name read off the params register its birth wrote. Rows are BUILT
## from the scan and not from a const: at _ready() no state exists to scan,
## so the grid fills on the first refresh after setup() and a key born
## mid-session appears on the next dirty sweep, never by an edit here.
##
## Reads simulation state and never writes it. The single exception is the
## Commit button and the draft button, which send player intent back as
## explicit commands -- Budget.commit() and Statute.draft(). Pending slider
## positions live here, not in the simulation. The commit reuses the budget
## panel's verb and its per-key lever maxima; the brief asked for the house
## idioms, not a second way to move a rate.

const Budget = preload("res://src/sim/budget.gd")
const C = preload("res://src/sim/economy_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const TaxK = preload("res://src/sim/tax_constants.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Statute = preload("res://src/sim/statute.gd")
const SK = preload("res://src/sim/statute_constants.gd")

## The one lever that is not a key in `tax_rates_pct`: it sets no rate, has
## no base and collects nothing -- budget_panel's PROGRESSIVITY_KEY comment,
## moved with the lever. It rides `pending` as a top-level scalar for the
## same reason it always did.
const PROGRESSIVITY_KEY := "tax_progressivity"

## Display names for the AUTHORED keys, keyed by live key -- presence is the
## register's question, this table only answers "what is it called". A
## composed key is named by the params register instead (see _label_for()).
const KEY_LABELS := {
	"income": "Income tax",  # i18n: msgid
	"corporate": "Corporate tax",  # i18n: msgid
	"vat": "VAT",
	"capital_gains": "Capital gains tax",  # i18n: msgid
	"wealth": "Wealth tax",  # i18n: msgid
	PROGRESSIVITY_KEY: "Income brackets",  # i18n: msgid
}

## Per-key slider ceilings -- the budget panel's LEVER_MAX rows for the tax
## side, moved with the levers. `wealth` reads the model bound, so the control
## and economy_constants cannot drift apart (tests/test_tax.gd asserts that
## identity). A COMPOSED key has no authored row: its ceiling is MATCHED TO ITS
## BASE in _lever_max() -- the model prices the PRODUCT base_share x rate, and
## the birth gate admits only pairs under NEW_TAX_YIELD_CEILING, so the slider
## may not offer a product the ceiling's own rationale declares unpriceable.
const LEVER_MAX := {
	"income": 70.0,
	"corporate": 70.0,
	"vat": 40.0,
	"capital_gains": 60.0,
	"wealth": C.WEALTH_RATE_MAX_PCT,
	PROGRESSIVITY_KEY: TaxK.PROGRESSIVITY_MAX,
}

signal committed(before: Dictionary, pending: Dictionary)

## The compose flow's product, opened by main.gd in the briefing: the parked
## draft (ns.draft_bills' own entry) and the id it will carry as a law.
signal brief_requested_draft(entry: Dictionary, draft_id: String)

var _state
var _loader
var _pending := {"tax_rates_pct": {}, PROGRESSIVITY_KEY: TaxK.PROGRESSIVITY_BASE}
var _edited_keys := {}
var _sliders := {}
var _lever_values := {}
var _title: Label
var _rates_grid: GridContainer
var _bases_box: VBoxContainer
var _dirty := true
var _close_button: Button
var _commit_button: Button

# The compose flow's controls, built once in _ready() and hidden until asked
# for. The brief's own boundary: the GENERAL compose window is not this task --
# a name, a key, the three tax params, the same birth gates, ONE draft button.
var _compose_box: VBoxContainer
var _draft_name: LineEdit
var _draft_key: LineEdit
var _base_slider: HSlider
var _erosion_slider: HSlider
var _rate_slider: HSlider
var _yield_label: Label
var _refusal: Label


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

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)

	PanelKit.line(body, tr("Rates (%, and brackets within income)"), PanelKit.Tone.PLAIN)
	_rates_grid = GridContainer.new()
	_rates_grid.columns = 3
	_rates_grid.add_theme_constant_override("h_separation", 12)
	body.add_child(_rates_grid)

	_bases_box = VBoxContainer.new()
	_bases_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(_bases_box)

	body.add_child(_build_compose())

	root.add_child(_build_buttons())


## One row per live key, built on demand. Called from every path that reads a
## slider, because the register can grow under the panel (a birth law passes
## mid-session) and a key with no row is a rate the player cannot move.
func _ensure_rows() -> void:
	for key in _lever_keys():
		if _sliders.has(key):
			continue
		var name_label := Label.new()
		name_label.text = _label_for(String(key))
		name_label.custom_minimum_size.x = 150
		_rates_grid.add_child(name_label)

		var slider := HSlider.new()
		slider.min_value = 0.0
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


func _build_compose() -> Control:
	var outer := VBoxContainer.new()
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var open_row := HBoxContainer.new()
	outer.add_child(open_row)
	var open_btn := Button.new()
	open_btn.text = tr("Propose a tax")
	open_btn.pressed.connect(func():
		_compose_box.visible = not _compose_box.visible
		_refusal.hide())
	open_row.add_child(open_btn)

	_compose_box = VBoxContainer.new()
	_compose_box.add_theme_constant_override("separation", 8)
	_compose_box.hide()
	outer.add_child(_compose_box)

	PanelKit.line(_compose_box, tr("A new key is born by a bill: name it, set its base and its birth rate, and draft. When the drafting completes the bill waits on your Propose in the Legislature -- the key prices nothing until the act carries."), PanelKit.Tone.PLAIN)

	var fields := HBoxContainer.new()
	fields.add_theme_constant_override("separation", 12)
	_compose_box.add_child(fields)
	_draft_name = LineEdit.new()
	_draft_name.placeholder_text = tr("Name (e.g. The Carbon Levy)")
	_draft_name.custom_minimum_size.x = 240
	fields.add_child(_draft_name)
	_draft_key = LineEdit.new()
	_draft_key.placeholder_text = tr("key (e.g. carbon)")
	_draft_key.custom_minimum_size.x = 160
	fields.add_child(_draft_key)

	var params := GridContainer.new()
	params.columns = 3
	params.add_theme_constant_override("h_separation", 12)
	_compose_box.add_child(params)
	_base_slider = _param_slider(params, tr("Base (% of GDP)"), 0.0, SK.NEW_TAX_BASE_SHARE_MAX, 0.01, 0.5)
	_erosion_slider = _param_slider(params, tr("Erosion"), 0.0, SK.NEW_TAX_EROSION_MAX, 0.01, 0.4)
	_rate_slider = _param_slider(params, tr("Birth rate (%)"), 0.0, SK.NEW_TAX_RATE_MAX, 0.1, 10.0)
	for slider: HSlider in [_base_slider, _erosion_slider, _rate_slider]:
		slider.value_changed.connect(_on_param_changed)

	# The product the revenue formula actually reads is base x rate, and the
	# birth gate refuses past NEW_TAX_YIELD_CEILING -- showing the product
	# while the player aims is the difference between a refusal and a choice.
	_yield_label = Label.new()
	_compose_box.add_child(_yield_label)

	var draft_row := HBoxContainer.new()
	draft_row.alignment = BoxContainer.ALIGNMENT_END
	_compose_box.add_child(draft_row)
	var draft_btn := Button.new()
	draft_btn.text = tr("Draft the bill")
	draft_btn.pressed.connect(_on_draft)
	draft_row.add_child(draft_btn)

	_refusal = Label.new()
	_refusal.hide()
	outer.add_child(_refusal)

	_on_param_changed(0.0)
	return outer


func _param_slider(grid: GridContainer, label: String, min_v: float, max_v: float, step: float, initial: float) -> HSlider:
	var caption := Label.new()
	caption.text = label
	caption.custom_minimum_size.x = 150
	grid.add_child(caption)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = initial
	slider.custom_minimum_size.x = 220
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_child(slider)
	var value := Label.new()
	value.custom_minimum_size.x = 60
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grid.add_child(value)
	slider.set_meta("value_label", value)
	return slider


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


## The register, in reading order: the authored five always, then any key the
## machine has born, in the register's own order. NO HAND-WRITTEN LIST: the
## register is the whole roster of rows, which is what makes a composed key
## appear the tick its bill passes rather than the session a list learns it.
func _lever_keys() -> Array:
	var ns = _state.player()
	var keys: Array = []
	if ns != null:
		for key in C.TAX_KEYS:
			if ns.tax_rates_pct.has(key):
				keys.append(key)
		for key in ns.tax_rates_pct:
			if not keys.has(key):
				keys.append(key)
	keys.append(PROGRESSIVITY_KEY)
	return keys


func _lever_max(key: String) -> float:
	if LEVER_MAX.has(key):
		return float(LEVER_MAX[key])
	# THE BORN KEY'S OWN CEILING (the ultra pass-6 finding): the slider max is
	# matched to the key's base, because the yield the revenue model prices is
	# the PRODUCT base_share x rate and the birth gate admits only pairs under
	# NEW_TAX_YIELD_CEILING. A 100-point slider on a base-4.0 key offered
	# exactly the product the ceiling exists to refuse -- two clicks from a
	# legal birth to a 400 %-of-GDP yield. minf keeps NEW_TAX_RATE_MAX as the
	# absolute cap, so a LOW-base birth keeps its full range (12.0 / 0.06 = 200
	# caps at 100); the 0.01 floor is divide-by-zero armour for a payload with
	# no base behind it, not a tuned bound.
	var ns = _state.player()
	if ns == null:
		return SK.NEW_TAX_RATE_MAX
	var params: Dictionary = ns.custom_taxes.get(key, {})
	return minf(SK.NEW_TAX_RATE_MAX, SK.NEW_TAX_YIELD_CEILING / maxf(float(params.get("base_share", 0.0)), 0.01))


func _label_for(key: String) -> String:
	if KEY_LABELS.has(key):
		return tr(String(KEY_LABELS[key]))
	var ns = _state.player()
	var params: Dictionary = ns.custom_taxes.get(key, {})
	return String(params.get("name", key))


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
	_dirty = true


func _on_commit() -> void:
	var before := Trends.snapshot_now(_state)
	var pending := _pending.duplicate()
	Budget.commit(_state, _pending)
	_on_revert()
	committed.emit(before, pending)


## The uncommitted tax intent, for the budget panel's now-vs-proposed columns
## and 24-month projection to price -- the ultra pass-2 wiring (without it the
## budget panel's proposed column asserted "no change" while the player's
## largest revenue lever sat half-drafted on X). EDITED KEYS ONLY, mirroring
## what the player actually moved: Budget.commit() splices per key and an
## untouched lever's pending value is just the live rate restated, so an empty
## return is the harmless case -- the merge writes nothing. Read-only; the
## commit is still this panel's own verb.
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
	for key in _lever_keys():
		_lever_values[key].text = _lever_text(String(key))
	_fill_bases()


## What a born key sits on and how its curve behaves -- the params register's
## own numbers, so a composed rate row is readable without the bill that
## birthed it. Rebuilt per refresh, so a key that appears mid-session needs
## no wiring here -- the scan above is the only roster this panel keeps.
func _fill_bases() -> void:
	for child in _bases_box.get_children():
		child.queue_free()
	var ns = _state.player()
	var customs: Array = []
	for key in ns.tax_rates_pct:
		if ns.custom_taxes.has(key):
			customs.append(key)
	if customs.is_empty():
		return
	PanelKit.heading(_bases_box, tr("Born keys"))
	for key in customs:
		var params: Dictionary = ns.custom_taxes[key]
		PanelKit.line(_bases_box, tr("%s — base %s%% of GDP, erosion %s, born at %s. Its rate sits in the grid above.") % [
			String(params.get("name", key)), PanelKit.Num.f(float(params.get("base_share", 0.0)), 2),
			PanelKit.Num.f(float(params.get("erosion", 0.0)), 2), PanelKit.Num.f(float(params.get("ref_pct", 0.0)), 1)], PanelKit.Tone.DIM)


func _on_param_changed(_value: float) -> void:
	_set_param_text(_base_slider)
	_set_param_text(_erosion_slider)
	_set_param_text(_rate_slider)
	_yield_label.text = tr("Would yield %s%% of GDP at birth (the most the model prices: %s).") % [
		PanelKit.Num.f(_base_slider.value * _rate_slider.value, 2), PanelKit.Num.f(SK.NEW_TAX_YIELD_CEILING, 1)]


func _set_param_text(slider: HSlider) -> void:
	var value: Label = slider.get_meta("value_label")
	value.text = PanelKit.Num.f(slider.value, 2)


## The birth. The gates are Statute.draft()'s -- this panel adds none, shows
## every refusal the machine returns, and on acceptance opens the briefing on
## the parked draft (its price and its drafting months are what the player
## just bought with the press).
func _on_draft() -> void:
	var ns = _state.player()
	var spec := {
		"name": _draft_name.text.strip_edges(),
		"position": {"economic": 0.0, "social": 0.0},
		"channels": {},
		"new_tax": {
			"key": _draft_key.text.strip_edges(),
			"name": _draft_name.text.strip_edges(),
			"base_share": _base_slider.value,
			"erosion": _erosion_slider.value,
			"rate": _rate_slider.value,
		},
	}
	var result: Dictionary = Statute.draft(_state, ns, _loader, spec)
	if not bool(result.get("ok", false)):
		_refusal.text = String(result.get("refusal", tr("Refused.")))
		_refusal.show()
		return
	_refusal.hide()
	brief_requested_draft.emit(ns.draft_bills[String(result["draft_id"])], String(result["draft_id"]))


## The control this panel exists to let the player press -- V2.1a's fold
## contract, declared here at birth. Commit is the first verb in build order,
## the budget panel's own rule.
func primary_action() -> Control:
	return _commit_button
