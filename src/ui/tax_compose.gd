extends VBoxContainer

## The Tax Code's compose flow -- V4.2 T5's one flow that births a new key, moved
## out of tax_panel.gd at V5.3 a + b (the panel sat at its size ratchet and its
## rows needed the room for their yields and effects). A name, a key, the three
## tax params, the same birth gates, ONE draft button; the gates are
## Statute.draft()'s, and the accepted draft goes out on the panel's own
## brief_requested_draft, which main.gd wires.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Statute = preload("res://src/sim/statute.gd")
const SK = preload("res://src/sim/statute_constants.gd")

## The Tax Code panel this flow drafts for: its state, its loader, its signal.
var _panel
# The compose flow's controls, built once at construction and hidden until asked
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


func _init(panel = null) -> void:
	_panel = panel
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var open_row := HBoxContainer.new()
	add_child(open_row)
	var open_btn := Button.new()
	open_btn.text = tr("Propose a tax")
	open_btn.pressed.connect(func():
		_compose_box.visible = not _compose_box.visible
		_refusal.hide())
	open_row.add_child(open_btn)

	_compose_box = VBoxContainer.new()
	_compose_box.add_theme_constant_override("separation", 8)
	_compose_box.hide()
	add_child(_compose_box)

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
	add_child(_refusal)

	_on_param_changed(0.0)


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
	var ns = _panel._state.player()
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
	var result: Dictionary = Statute.draft(_panel._state, ns, _panel._loader, spec)
	if not bool(result.get("ok", false)):
		_refusal.text = String(result.get("refusal", tr("Refused.")))
		_refusal.show()
		return
	_refusal.hide()
	_panel.brief_requested_draft.emit(ns.draft_bills[String(result["draft_id"])], String(result["draft_id"]))
