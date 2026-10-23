extends RefCounted

## The chart kit -- V5.2-0a, the author's gate-2 ask: "i think i need graph, diagrams,
## to make data more digest". Builders for a line over time, horizontal bars and a
## stacked share, each one small Control that draws itself (chart_line.gd,
## chart_bars.gd, chart_stack.gd). Built on the `dataviz` method: the data is the
## only loud thing -- 2px lines, thin bars, hairline grid, text in the text tokens
## and never in a series colour, a legend only when there are two series or more.
##
## A chart never stands alone: the panel's own rows keep every value it draws, so
## a hover tooltip enhances and never gates (the method's "table view").

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const ChartLine = preload("res://src/ui/chart_line.gd")
const ChartBars = preload("res://src/ui/chart_bars.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")

## A line over time under a MICRO title. `series` is [{label, values}] with
## `values` a PackedFloat64Array aligned with `months` ([[year, month], ...]).
## `opts`: `unit` (appended to every figure), `fixed` (a Vector2 range, e.g. one
## shared by small multiples so they compare), `zero` (include and mark the zero
## line: a sign matters), `min_span` (the narrowest range drawn, in the figure's
## units; 1 by default).
## Fewer than two months draws no line and says why.
static func line(parent: Control, title: String, series: Array, months: Array, opts := {}) -> VBoxContainer:
	var box := _titled(parent, title)
	var chart := ChartLine.new()
	chart.setup(series, months, opts)
	box.add_child(chart)
	if not chart.has_line():
		box.add_child(_caption(Strings.t("Fills in as the months pass.")))
	_legend(box, series)
	return box


## A sparkline: the trend beside a figure the caller already prints. `months`
## feeds the hover only.
static func spark(parent: Control, values: PackedFloat64Array, months: Array, unit := "") -> Control:
	var chart := ChartLine.new()
	chart.setup([{"label": "", "values": values}], months, {"unit": unit, "spark": true})
	parent.add_child(chart)
	return chart


## Horizontal bars from a zero baseline, one hue: rows are [{label, value}].
static func bars(parent: Control, title: String, rows: Array, opts := {}) -> VBoxContainer:
	var box := _titled(parent, title)
	var chart := ChartBars.new()
	chart.setup(rows, opts)
	box.add_child(chart)
	return box


## One bar split into its parts, in the caller's fixed order (the colour follows
## the part, never its rank). Past seven parts the tail folds into "Others", the
## eighth slot. `opts.marker` (a 0-1 share) draws a tick across it -- a majority --
## and `opts.markers` several; `opts.colors` gives each part its colour when the
## order is not the parts' identity order (the colour still follows the entity);
## `opts.places` fixes the decimals of every value (0 for a count).
static func stack(parent: Control, title: String, parts: Array, opts := {}) -> VBoxContainer:
	var box := _titled(parent, title)
	var folded := ChartStack.fold(parts, Strings.t("Others"))
	var chart := ChartStack.new()
	chart.setup(folded, opts)
	box.add_child(chart)
	_legend(box, folded, true, String(opts.get("unit", "")), int(opts.get("places", -1)), opts.get("colors", ChartStyle.SERIES))
	return box


static func _titled(parent: Control, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var head := Label.new()
	head.theme_type_variation = UiTheme.MICRO
	head.text = title
	box.add_child(head)
	parent.add_child(box)
	return box


static func _caption(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = UiTheme.CAPTION
	label.text = text
	return label


## Swatch and label per entry, the label in a text token. A single line needs none
## (the title names it); a stack always has one, with each part's value, because
## its segments carry no labels of their own.
static func _legend(box: VBoxContainer, entries: Array, always := false, unit := "", places := -1, colors: Array = ChartStyle.SERIES) -> void:
	if entries.size() < 2 and not always:
		return
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 14)
	flow.add_theme_constant_override("v_separation", 2)
	flow.name = "Legend"
	for i in entries.size():
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 5)
		var swatch := ColorRect.new()
		swatch.color = colors[mini(i, colors.size() - 1)]
		swatch.custom_minimum_size = Vector2(ChartStyle.SWATCH, ChartStyle.SWATCH)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		item.add_child(swatch)
		var text := String(entries[i]["label"])  # i18n: row-ok chart data, the caller passes shown text
		if entries[i].has("value") and always:
			text = "%s  %s%s" % [text, ChartStyle.figure(float(entries[i]["value"]), places), unit]
		var label := _caption(text)
		item.add_child(label)
		flow.add_child(item)
	box.add_child(flow)
