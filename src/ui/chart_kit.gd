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
const ChartDots = preload("res://src/ui/chart_dots.gd")
const ChartRange = preload("res://src/ui/chart_range.gd")
const ChartBars = preload("res://src/ui/chart_bars.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const ChartHemicycle = preload("res://src/ui/chart_hemicycle.gd")
const ChartDiverge = preload("res://src/ui/chart_diverge.gd")
const ChartWaterfall = preload("res://src/ui/chart_waterfall.gd")

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
## feeds the hover only. `opts` as line()'s: `zero` draws the zero line (a sign that
## matters, the top bar's money), `min_span` the narrowest range.
static func spark(parent: Control, values: PackedFloat64Array, months: Array, unit := "", opts := {}) -> Control:
	var chart := ChartLine.new()
	var o := opts.duplicate()
	o["unit"] = unit
	o["spark"] = true
	chart.setup([{"label": "", "values": values}], months, o)
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


## The assembly as a hemicycle, one dot per seat (V5.2 b+ R6): the parts are
## parties in their fixed order, folded past seven as a stack is, with the same
## `opts` (markers, colors, unit, places) and the same legend under it.
static func hemicycle(parent: Control, title: String, parts: Array, opts := {}) -> VBoxContainer:
	var box := _titled(parent, title)
	var folded := ChartStack.fold(parts, Strings.t("Others"))
	var chart := ChartHemicycle.new()
	chart.setup(folded, opts)
	box.add_child(chart)
	_legend(box, folded, true, String(opts.get("unit", "")), int(opts.get("places", -1)), opts.get("colors", ChartStyle.SERIES))
	return box


## One signed bar per row around a zero line (chart_diverge.gd): `rows` are [{label, value,
## text}], `text` the signed figure printed beside the bar, so the number is always read and
## the colour only repeats it. Every row shares one span (the largest magnitude, or `opts.span`),
## so the bars compare down the column. A row of zero keeps its place and prints its zero.
static func diverging(parent: Control, title: String, rows: Array, opts := {}) -> VBoxContainer:
	var box := _titled(parent, title)
	var span := float(opts.get("span", 0.0))
	for row in rows:
		span = maxf(span, absf(float(row["value"])))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 2)
	for row in rows:
		grid.add_child(_caption(String(row["label"])))  # i18n: row-ok chart data, the caller passes shown text
		var bar := ChartDiverge.new()
		bar.setup(float(row["value"]), span)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(bar)
		var figure := _caption(String(row["text"]))  # i18n: row-ok chart data, the caller passes shown text
		figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		figure.custom_minimum_size.x = 44.0 * UiTheme.text_scale()
		grid.add_child(figure)
	box.add_child(grid)
	return box


## V5.3 c' (the bureau audit's item 4): before and after per row on one axis (chart_dots.gd
## says what each mark means). `rows` are [{id, label, before, after, moved, selected}];
## `opts`: `reference` (a hairline), `band` (Vector2 lo, hi: the attention zone), `places`.
## The chart is the box's meta "chart"; its `picked(id)` answers a click on a row.
static func dots(parent: Control, title: String, rows: Array, opts := {}) -> VBoxContainer:
	var box := _titled(parent, title)
	var chart := ChartDots.new()
	chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(chart)
	chart.setup(rows, opts)
	box.set_meta("chart", chart)
	return box


## V5.3 c' (the bureau audit's item 5): a range with its estimate's tick, the three printed.
## Not `range`: that would shadow GDScript's global range() in this file.
static func range_bar(parent: Control, title: String, lo: float, estimate: float, hi: float, opts := {}) -> VBoxContainer:
	var box := _titled(parent, title)
	var chart := ChartRange.new()
	box.add_child(chart)
	chart.setup(lo, estimate, hi, opts)
	box.set_meta("chart", chart)
	return box


## A total walked change by change (chart_waterfall.gd): today, each signed step from the running total, the total after.
static func waterfall(parent: Control, title: String, start: Dictionary, steps: Array, end: Dictionary, opts := {}) -> VBoxContainer:
	var box := _titled(parent, title)
	var chart := ChartWaterfall.new()
	box.add_child(chart)
	chart.setup(start, steps, end, opts)
	box.set_meta("chart", chart)
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
