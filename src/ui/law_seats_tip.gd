extends RefCounted

## The Assembly's seats by party, as a tooltip over a forecast bar -- V5.3 screen 4 (the rulings
## on the laws pictures: "the hemicycle leaves the screen and stays on the forecast bar's hover").
## The bar is where a vote is read, so the chamber it is read in is one hover away instead of a
## third of the tab on every visit. The drawing is PanelCharts' SEATS, built outside the tree.

const PanelCharts = preload("res://src/ui/panel_charts.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")


## A plate holding the chamber; the panel is the Bills tab (its state and loader).
static func build(panel) -> Control:
	var plate := PanelContainer.new()
	plate.theme_type_variation = UiTheme.PLATE
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	plate.add_child(margin)
	var charts := PanelCharts.new(panel, PanelCharts.SEATS)
	margin.add_child(charts)
	charts.draw_now()
	return plate
