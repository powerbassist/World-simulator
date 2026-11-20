extends RefCounted

## The register opened from a region warning (V5.3 c' register slice 2; the picture A's
## "Opened from the warning of January"): a bar under the lede with the warning's answers
## AS THE SIM OFFERS THEM (UnitWarnings.answers): build the type's band_units there -- its
## debt net of the Union and its running cost said under the button -- or leave it.
## Picture A's third button, "Give it priority", has no sim verb, so it is not drawn.
##
## Build here tables that programme through the sheet's own press (the very rule tabling
## meets, and its refusal said the same way); Leave it puts the bar away.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const UnitWarnings = preload("res://src/sim/unit_warnings.gd")


## `warning` is {type, region, month}; `panel` the register (its rows, its press).
static func bar(panel, parent: Control, state, loader, warning: Dictionary) -> void:
	var type_id := String(warning["type"])
	var region := String(warning["region"])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.set_meta("warning_bar", true)
	parent.add_child(box)
	PanelKit.plain_line(box, Strings.t("Opened from the warning of %s: among the regions furthest behind.") % DateText.month_long(int(warning["month"])),
		PanelKit.Tone.DIM)
	var answers: Array = UnitWarnings.answers(state, state.player(), loader, type_id, region)
	var build: Dictionary = answers[1]
	var running := 0.0
	for line in build.get("spending_pct_gdp", {}):
		running += float(build["spending_pct_gdp"][line])
	var band_units := int(loader.unit_types[type_id]["band_units"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	box.add_child(row)
	_answer(row, Strings.t("Build here"), Strings.tn("%d unit: %s bn of debt net of the Union, then %s %% of GDP a year.",
		"%d units: %s bn of debt net of the Union, then %s %% of GDP a year.", band_units) % [band_units,
		Num.f(float(build["debt_eur_bn"]), 2), Num.f(running, 3)], "warning_build", func() -> void:
			panel.place(region, band_units)
			panel.clear_warning()
			panel.table_programme())
	_answer(row, Strings.t("Leave it"), Strings.t("Nothing is spent; the region stays behind."), "warning_leave", func() -> void:
		panel.clear_warning())


static func _answer(parent: Control, label: String, says: String, meta: String, act: Callable) -> void:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(col)
	var flow := PanelKit.buttons(col)
	var button := PanelKit.sized(Button.new())
	button.text = label
	button.set_meta(meta, true)
	button.pressed.connect(act)
	flow.add_child(button)
	PanelKit.plain_line(col, says, PanelKit.Tone.DIM)
