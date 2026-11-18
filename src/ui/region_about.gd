extends RefCounted

## The Regions tab's folded "About these figures" (region_panel.gd's toggle opens it): what the
## register names of the nation's people and output, and how the regions link. Both residuals
## are derived, so these rows cannot disagree with the table above them. Its own file because
## region_panel.gd is near its size ceiling (tools/check_size.py).

const PanelKit = preload("res://src/ui/panel_kit.gd")
const Region = preload("res://src/core/region.gd")
const Migration = preload("res://src/sim/migration.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")


static func rows(body: VBoxContainer, state, ns, regions: Array) -> void:
	var named := 0.0
	var named_gdp := 0.0
	for region in regions:
		named += Migration.region_share(ns, region.id)
		named_gdp += region.gdp_share
	# maxf: the named shares are a live partition the flow moves every month, and
	# a nation whose register names all of itself can land a hair past 1.0.
	PanelKit.row(body, Strings.t("Named share of the population"), "%s%%" % Num.f(named * 100.0, 1))
	PanelKit.row(body, Strings.t("Unnamed — extra-regio and overseas"), "%s%%" % Num.f(maxf(0.0, 1.0 - named) * 100.0, 1))
	PanelKit.row(body, Strings.t("Named share of output"), "%s%%" % Num.f(named_gdp * 100.0, 1))
	PanelKit.row(body, Strings.t("Unnamed output — extra-regio"), "%s%%" % Num.f(Region.national_gdp_residual(regions) * 100.0, 1))
	# V2.7, never silent: every region has a place on the graph, read off the edges
	# because the line also says which links are water.
	var land := 0
	var sea := 0
	var degrees := {}
	for region in regions:
		degrees[region.id] = 0
	for edge in (state.region_graph.get("edges", []) as Array):
		var a := String(edge[0])
		var b := String(edge[1])
		if not degrees.has(a) and not degrees.has(b):
			continue
		if String(edge[3]) == "sea":
			sea += 1
		else:
			land += 1
		for end in [a, b]:
			if degrees.has(end):
				degrees[end] = int(degrees[end]) + 1
	var least = null
	for region in regions:
		if least == null or int(degrees[region.id]) < int(degrees[least.id]):
			least = region
	PanelKit.row(body, Strings.t("Links between regions"), Strings.t("%d by land · %d by sea") % [land, sea])
	if least != null:
		PanelKit.row(body, Strings.t("Least connected"), "%s (%d)" % [least.region_name, int(degrees[least.id])])

