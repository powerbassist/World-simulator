extends RefCounted

## The Assembly's seats by party, as a tooltip over a forecast bar -- V5.3 screen 4 (the rulings
## on the laws pictures: "the hemicycle leaves the screen and stays on the forecast bar's hover").
## The bar is where a vote is read, so the chamber it is read in is one hover away instead of a
## third of the tab on every visit. The drawing is PanelCharts' SEATS, built outside the tree.

const PanelCharts = preload("res://src/ui/panel_charts.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")


## A plate holding the chamber; the panel is the Bills tab (its state and loader). `counts` is the
## bar's own forecast, {yes, undecided, no}, written above the chamber because the hover replaces the
## figures the bar shows on its segments.
static func build(panel, counts := {}) -> Control:
	var plate := PanelContainer.new()
	plate.theme_type_variation = UiTheme.PLATE
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	plate.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", PanelKit.SECTION_SEPARATION)
	margin.add_child(column)
	if not counts.is_empty():
		PanelKit.line(column, Strings.t("For %d · against %d · undecided %d") % [int(counts["yes"]), int(counts["no"]), int(counts["undecided"])], PanelKit.Tone.PLAIN)
	var charts := PanelCharts.new(panel, PanelCharts.SEATS)
	column.add_child(charts)
	charts.draw_now()
	return plate
