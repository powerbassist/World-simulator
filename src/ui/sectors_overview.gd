extends RefCounted

## The Sectors overview's two readings -- G3 S3, the author's "C La frise". The page is what
## runs and when it lands (sectors_timeline.gd, sectors_decision.gd); this file draws the two
## things around it: the strip of three sector DOORS on top (output, the trend a year against
## the nation's, an 18-month curve, the verdict and what waits, one Open) and, under the
## timeline, the economy's shape (the share of output as bars, the trend a year as a dot plot
## against the economy's own line, the lead sentence over them).
##
## Every figure is a reader's: SectorRead.head (Economy.sector_trend_pct against the
## nation's trend), GameState.history's `sectors` for the curve, SectorNeeds for what waits.
## A decision is a STATUS: every waiting sector's bar is the WARN tone and its door carries
## the amber count (AGENTS.md: identity and status colour never mixed). No chart wears the
## accent for a quantity (G3 decision 5).

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

## Months on a card's curve (the picture's 18).
const CURVE_MONTHS := 18
## The door's curve, in px at text size 100.
const CURVE_HEIGHT := 32.0
const CURVE_WIDTH := 130.0
## The chip glyph on a sector under the economy's pace and on a waiting card.
const GLYPH := "warning"  # i18n: ok an icon file name
## The lead: the largest sector by share, then, when one lags, the one furthest under the nation's trend.
const LEAD := "%s: %s %% of output. Slowest against the economy: %s."  # i18n: msgid
const LEAD_ALONE := "%s: %s %% of output."  # i18n: msgid
const VERDICT_CHIPS := {
	"behind": UiTheme.CHIP_BAD, "slower": UiTheme.CHIP_WARN, "pace": UiTheme.CHIP_GOOD, "ahead": UiTheme.CHIP_GOOD,
}


## The strip of doors under `parent`, one per sector. `open_tab` is called with a sector
## tab's window id.
static func doors(parent: Control, state, loader, ns, open_tab: Callable) -> HBoxContainer:
	var strip := HBoxContainer.new()
	strip.add_theme_constant_override("separation", 12)
	parent.add_child(strip)
	var waiting: Dictionary = SectorNeeds.counts(state, loader, ns)
	var history: Array = ChartSeries.last(state, CURVE_MONTHS)
	for s in EK.SECTOR_TREND.keys():
		_door(strip, ns, String(s), SectorRead.head(state, loader, ns, String(s)),
			int(waiting.get(SectorNeeds.tab_of(String(s)), 0)), history, open_tab)
	return strip


## The economy's shape under `parent`, as a sheet: the lead, the share bars, the dot plot.
## Returns the lead's Label (the panel's _title).
static func charts(parent: Control, state, loader, ns, open_tab: Callable) -> Label:
	var sectors: Array = EK.SECTOR_TREND.keys()
	var heads := {}
	var total := 0.0
	for s in sectors:
		heads[s] = SectorRead.head(state, loader, ns, String(s))
		total += float(heads[s]["output"])
	var waiting: Dictionary = SectorNeeds.counts(state, loader, ns)
	var body := PanelKit.sheet(parent)
	var lead := PanelKit.plain_line(body, "", PanelKit.Tone.PLAIN)
	lead.theme_type_variation = UiTheme.LEAD
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 32)
	body.add_child(row)
	var share_rows := []
	var dot_rows := []
	var marked := []
	for i in sectors.size():
		var s := String(sectors[i])
		var share := 100.0 * float(heads[s]["output"]) / total if total > 0.0 else 0.0
		share_rows.append({"label": Labels.sector(s), "value": share})
		if int(waiting.get(SectorNeeds.tab_of(s), 0)) > 0:
			marked.append(i)
		var trend := float(heads[s]["trend"])
		dot_rows.append({"id": s, "label": Labels.sector(s), "before": trend, "after": trend, "moved": false})
	var share_box := ChartKit.bars(row, Strings.t("Share of output"), share_rows, {"unit": " %", "marked": marked})
	share_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	share_box.get_child(1).set_meta("overview", "share")
	var dots := ChartKit.dots(row, Strings.t("Trend a year, against the economy (%s %%)") % Num.fs(float(ns.trend_annual_pct), 1),
		dot_rows, {"reference": float(ns.trend_annual_pct), "places": 1})
	dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dot_chart: Control = dots.get_meta("chart")
	dot_chart.set_meta("overview", "growth")
	# A dot is a way in, as a door's Open is.
	dot_chart.picked.connect(func(id: String) -> void: open_tab.call(SectorNeeds.tab_of(id)))
	lead.text = _lead(sectors, heads, share_rows)
	return lead


static func _door(parent: Control, ns, sector: String, head: Dictionary, waiting: int, history: Array, open_tab: Callable) -> void:
	var plate := PanelContainer.new()
	plate.theme_type_variation = UiTheme.PLATE
	plate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	plate.size_flags_stretch_ratio = 1.0
	plate.set_meta("sector_card", sector)
	parent.add_child(plate)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	plate.add_child(line)
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation", 4)
	line.add_child(words)
	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 8)
	words.add_child(top)
	var name := Label.new()
	name.theme_type_variation = UiTheme.LEAD
	name.text = Labels.sector(sector)
	top.add_child(name)
	var verdict := String(head["verdict"])
	var chip := PanelKit.chip(top, SectorRead.verdict_words(verdict), VERDICT_CHIPS.get(verdict, UiTheme.CHIP),
		GLYPH if verdict in ["behind", "slower"] else "")
	chip.set_meta("verdict_chip", sector)
	_unwrapped(chip)
	if waiting > 0:
		var wait := PanelKit.chip(top, Strings.tn("%d waits", "%d wait", waiting) % waiting, UiTheme.CHIP_WARN, "event")  # i18n: ok an icon file name
		wait.set_meta("decision_chip", sector)
		_unwrapped(wait)
	PanelKit.plain_line(words, Strings.t("%s bn output · %s %% a year, nation %s") % [Num.f(float(head["output"]), 0),
		Num.fs(float(head["trend"]), 1), Num.fs(float(head["nation"]), 1)], PanelKit.Tone.PLAIN)
	# The sector's regulation burden: the public account's net rows name the sectors that carry one.
	var burden: float = Companies.regulation_burden_of(ns, sector)
	if burden != 0.0:
		PanelKit.plain_line(words, (Strings.t("Regulated: %s") if burden > 0.0 else Strings.t("Deregulated: %s")) % Num.fs(burden, 2))
	var values := PackedFloat64Array()
	for e in history:
		var outputs = e.get("sectors", null)
		if outputs is Dictionary and (outputs as Dictionary).has(sector):
			values.append(float(outputs[sector]))
	var curve := ChartKit.spark(line, values, ChartSeries.months(history))
	curve.custom_minimum_size = Vector2(CURVE_WIDTH, CURVE_HEIGHT) * UiTheme.text_scale()
	curve.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	curve.set_meta("sector_curve", sector)
	# Under two months there is no line to draw: no band left empty (the figures carry today).
	curve.visible = values.size() >= 2
	var open := PanelKit.button(Strings.t("Open"), PanelKit.Size.S)
	open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	open.tooltip_text = Strings.t("Open %s") % Labels.sector(sector)
	open.set_meta("open_tab", SectorNeeds.tab_of(sector))
	open.pressed.connect(func() -> void: open_tab.call(SectorNeeds.tab_of(sector)))
	# In a flow, not the door's own row: a verb's box wraps (test_i18n_fit).
	var verbs := PanelKit.buttons(line)
	verbs.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	verbs.add_child(open)


static func _lead(sectors: Array, heads: Dictionary, share_rows: Array) -> String:
	var top := 0
	var lag := 0
	for i in sectors.size():
		if float(share_rows[i]["value"]) > float(share_rows[top]["value"]):
			top = i
		var gap := float(heads[sectors[i]]["trend"]) - float(heads[sectors[i]]["nation"])
		if gap < float(heads[sectors[lag]]["trend"]) - float(heads[sectors[lag]]["nation"]):
			lag = i
	var largest := Labels.sector(String(sectors[top]))
	var share := Num.f(float(share_rows[top]["value"]), 0)
	if not String(heads[sectors[lag]]["verdict"]) in ["behind", "slower"]:
		return Strings.t(LEAD_ALONE) % [largest, share]
	return Strings.t(LEAD) % [largest, share, Labels.sector(String(sectors[lag]))]


## A chip's words on one line: in a flow, a chip's wrapping label measures zero wide and
## stood one letter per line on the first frame.
static func _unwrapped(chip: Control) -> void:
	for label in chip.find_children("*", "Label", true, false):  # i18n: ok a class name
		(label as Label).autowrap_mode = TextServer.AUTOWRAP_OFF
