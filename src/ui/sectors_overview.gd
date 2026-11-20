extends RefCounted

## The Sectors overview's shape -- the rework pass's C ("the economy's shape", the author's
## pick after the G3 line "sector overview is a joke"). One look says which sector carries
## the economy and which lags: the share of output as bars, growth a year as a dot plot
## against the economy's own line, then one card per sector (output, share, jobs at named
## firms, an 18-month curve, the biggest employers, Open). The verbs live on each sector's
## tab; this file only reads.
##
## Every figure is a reader's: SectorRead.head (Economy.sector_trend_pct against the
## nation's trend), GameState.history's `sectors` for the curve, Companies.headcount for
## the employers, SectorNeeds for the "decision" chip. The picture's own card outline in the
## accent is not built: a plate never wears the accent (test_ui_theme); the waiting sector
## is told by its chip and by its bar in the accent instead.

const Companies = preload("res://src/sim/companies.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const SectorRead = preload("res://src/ui/sector_read.gd")
const SectorNeeds = preload("res://src/ui/sector_needs.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const ChartSeries = preload("res://src/ui/chart_series.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const CompanyVerb = preload("res://src/ui/company_verb.gd")

## Months on a card's curve (the picture's 18).
const CURVE_MONTHS := 18
## The curve's height, in px at text size 100.
const CURVE_HEIGHT := 32.0
## Employers ranked on a card (the picture's four).
const EMPLOYERS := 4
## The chip glyph on a sector under the economy's pace and on a waiting card.
const GLYPH := "warning"  # i18n: ok an icon file name
## The lead: the largest sector by share, then the one furthest under the nation's trend.
const LEAD := "%s make %s %% of output; %s grows slowest against the economy."  # i18n: msgid
const VERDICT_CHIPS := {
	"behind": UiTheme.CHIP_BAD, "slower": UiTheme.CHIP_WARN, "pace": UiTheme.CHIP_GOOD, "ahead": UiTheme.CHIP_GOOD,
}


## Builds the shape under `parent`; returns the lead sentence (the panel's title carries it).
## `open_tab` is called with a sector tab's window id.
static func build(parent: Control, state, loader, ns, open_tab: Callable) -> String:
	var sectors: Array = EK.SECTOR_TREND.keys()
	var heads := {}
	var total := 0.0
	for s in sectors:
		heads[s] = SectorRead.head(state, loader, ns, String(s))
		total += float(heads[s]["output"])
	var waiting: Dictionary = SectorNeeds.counts(state, loader, ns)

	var charts := HBoxContainer.new()
	charts.add_theme_constant_override("separation", 32)
	parent.add_child(charts)
	var share_rows := []
	var dot_rows := []
	var highlight := -1
	for i in sectors.size():
		var s := String(sectors[i])
		var share := 100.0 * float(heads[s]["output"]) / total if total > 0.0 else 0.0
		share_rows.append({"label": Labels.sector(s), "value": share})
		var waits := int(waiting.get(SectorNeeds.tab_of(s), 0)) > 0
		if waits and highlight < 0:
			highlight = i
		var trend := float(heads[s]["trend"])
		dot_rows.append({"id": s, "label": Labels.sector(s), "before": trend, "after": trend, "moved": false, "selected": waits})
	var share_box := ChartKit.bars(charts, Strings.t("Share of output"), share_rows, {"unit": " %", "highlight": highlight})
	share_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_box.get_child(1).set_meta("overview", "share")
	var growth := VBoxContainer.new()
	growth.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	charts.add_child(growth)
	var dots := ChartKit.dots(growth, Strings.t("Growth a year, against the economy (%s %%)") % Num.fs(float(ns.trend_annual_pct), 1),
		dot_rows, {"reference": float(ns.trend_annual_pct), "places": 1})
	(dots.get_meta("chart") as Control).set_meta("overview", "growth")
	var verdicts := HFlowContainer.new()
	verdicts.add_theme_constant_override("h_separation", 8)
	growth.add_child(verdicts)
	for s in sectors:
		var verdict := String(heads[s]["verdict"])
		var chip := PanelKit.chip(verdicts, "%s: %s" % [Labels.sector(String(s)), SectorRead.verdict_words(verdict)],
			VERDICT_CHIPS.get(verdict, UiTheme.CHIP), GLYPH if verdict in ["behind", "slower"] else "")
		_unwrapped(chip)

	var cards := HBoxContainer.new()
	cards.add_theme_constant_override("separation", 12)
	parent.add_child(cards)
	var history: Array = ChartSeries.last(state, CURVE_MONTHS)
	for s in sectors:
		_card(cards, loader, ns, String(s), heads[s], int(waiting.get(SectorNeeds.tab_of(String(s)), 0)), history, open_tab)
	return _lead(sectors, heads, share_rows)


static func _card(parent: Control, loader, ns, sector: String, head: Dictionary, waiting: int, history: Array, open_tab: Callable) -> void:
	var plate := PanelContainer.new()
	plate.theme_type_variation = UiTheme.PLATE
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.set_meta("sector_card", sector)
	parent.add_child(plate)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	plate.add_child(box)

	var top := HBoxContainer.new()
	box.add_child(top)
	var name := Label.new()
	name.theme_type_variation = UiTheme.LEAD
	name.text = Labels.sector(sector)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name)
	if waiting > 0:
		var chip := PanelKit.chip(top, Strings.tn("%d decision", "%d decisions", waiting) % waiting, UiTheme.CHIP_WARN, GLYPH)
		chip.size_flags_horizontal = Control.SIZE_SHRINK_END
		chip.set_meta("decision_chip", sector)
		_unwrapped(chip)

	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 20)
	box.add_child(figures)
	PanelKit.figure(figures, Strings.t("%s bn") % Num.f(float(head["output"]), 0),
		Strings.t("%s %% of GDP") % Num.f(float(head["of_gdp"]), 1))
	PanelKit.figure(figures, CompanyVerb.thousands(float(head["jobs"])), Strings.t("jobs at named firms"))
	for figure in figures.get_children():  # the captions wrap at the card's width, not the figure's
		(figure as Control).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var values := PackedFloat64Array()
	for e in history:
		var outputs = e.get("sectors", null)
		if outputs is Dictionary and (outputs as Dictionary).has(sector):
			values.append(float(outputs[sector]))
	# Its own row under the figures: beside them it took the captions' width and folded them.
	var curve := ChartKit.spark(box, values, ChartSeries.months(history))
	curve.custom_minimum_size.y = CURVE_HEIGHT * UiTheme.text_scale()
	curve.set_meta("sector_curve", sector)

	var firms: Array = Companies.firms_in_sector(loader, ns.id, sector)
	firms.sort_custom(func(a, b) -> bool: return Companies.headcount(ns, a) > Companies.headcount(ns, b))
	var rows := []
	for company in firms.slice(0, EMPLOYERS):
		rows.append({"label": String(company.company_name), "value": Companies.headcount(ns, company)})  # i18n: row-ok a firm's proper name
	if not rows.is_empty():
		var employers := ChartKit.bars(box, Strings.t("Biggest employers"), rows)
		employers.get_child(1).set_meta("employers", sector)

	var open := PanelKit.sized(Button.new())
	open.text = Strings.t("Open %s") % Labels.sector(sector)
	open.size_flags_horizontal = Control.SIZE_SHRINK_END
	open.set_meta("open_tab", SectorNeeds.tab_of(sector))
	open.pressed.connect(func() -> void: open_tab.call(SectorNeeds.tab_of(sector)))
	box.add_child(open)


static func _lead(sectors: Array, heads: Dictionary, share_rows: Array) -> String:
	var top := 0
	var lag := 0
	for i in sectors.size():
		if float(share_rows[i]["value"]) > float(share_rows[top]["value"]):
			top = i
		var gap := float(heads[sectors[i]]["trend"]) - float(heads[sectors[i]]["nation"])
		if gap < float(heads[sectors[lag]]["trend"]) - float(heads[sectors[lag]]["nation"]):
			lag = i
	return Strings.t(LEAD) % [Labels.sector(String(sectors[top])), Num.f(float(share_rows[top]["value"]), 0),
		Labels.sector(String(sectors[lag]))]


## A chip's words on one line: in a flow, a chip's wrapping label measures zero wide and
## stood one letter per line on the first frame.
static func _unwrapped(chip: Control) -> void:
	for label in chip.find_children("*", "Label", true, false):
		(label as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
