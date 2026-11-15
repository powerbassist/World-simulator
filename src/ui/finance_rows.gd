extends RefCounted

## The rows beside the Finances page's stacks (finances_panel.gd) -- the controls of direction A, and
## the only place a name or a figure is written: the stacks carry neither. Revenue rows by base, a
## group's header with its total and its kinds under it, the small kinds folded into one line, the
## kinds not in force named once with the month they can be created; spending rows by line, then what
## no row here sets, said so in words (and never by colour alone: a muted swatch and "not set here").

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const LedgerBox = preload("res://src/ui/ledger_box.gd")
const TaxesLoader = preload("res://src/core/loaders/taxes_loader.gd")
const EK = preload("res://src/sim/economy_constants.gd")

## A part nobody sets here: the muted neutral of the page's two stacks, and a darker one for the
## debt service so that the two are told apart by more than their place.
const MUTED := Color("#56616A")
const SERVICE := Color("#3B444B")

const GROUP_NAME := {
	"consumption": "Consumption", "income": "Income", "companies_finance": "Companies and finance",  # i18n: msgid
	"wealth_property": "Wealth and property", "energy_environment": "Energy and environment",  # i18n: msgid
}
const NAME_WIDTH := 215.0
const SPENDING_NAME_WIDTH := 130.0
const RATE_WIDTH := 100.0
const FIGURE_WIDTH := 64.0
const SWATCH := 10.0


## The colour of a group follows the group (its slot in the loader's closed list), never its rank.
static func group_color(group_id: String) -> Color:
	return ChartStyle.SERIES[maxi(TaxesLoader.GROUPS.find(group_id), 0) % ChartStyle.SERIES.size()]


static func line_color(key: String) -> Color:
	return ChartStyle.SERIES[maxi(EK.SPENDING_KEYS.find(key), 0) % ChartStyle.SERIES.size()]


static func group_name(group_id: String) -> String:
	return Strings.t(String(GROUP_NAME.get(group_id, group_id)))


## A tax's unit as it is printed after the rate: a symbol is not translated, a word is.
static func unit_text(code: String) -> String:
	match code:
		"%":
			return " %"
		"pt":
			return Strings.t(" pt")
		"index":
			return Strings.t(" (index)")
		"EUR/l":
			return " €/l"
		"EUR/kg":
			return " €/kg"
		"EUR/t":
			return " €/t"
		"EUR/passenger":
			return Strings.t(" € a passenger")
	return " " + code


static func bn_text(value: float) -> String:
	return Strings.t("%s bn") % Num.f(value, 0 if absf(value) >= 10.0 else 1)


## The revenue column: every group (largest first) with its kinds, then what no row sets.
static func revenue(box: Control, book: Dictionary, state, loader, open_groups: Dictionary, toggle: Callable, wide: bool) -> void:
	var ns = state.player()
	for group in book["groups"]:
		var gid := String(group["id"])
		_header(box, group_color(gid), group_name(gid), bn_text(float(group["total"])), "")
		for kind in group["kinds"]:
			box.add_child(_kind_row(ns, kind, wide))
		var folded: Array = group["folded"]
		if not folded.is_empty():
			if open_groups.has(gid):
				for kind in folded:
					box.add_child(_kind_row(ns, kind, wide))
			else:
				box.add_child(_fold_button(folded, toggle.bind(gid)))
		var absent: Array = group["not_in_force"]
		if not absent.is_empty():
			var names := ", ".join(absent.map(func(k) -> String: return Strings.row_name("taxes", ns.tax_library[k])))
			var month := int(loader.nations[ns.id].finance_autumn_month)
			var line := PanelKit.plain_line(box, Strings.t("Not in force, creatable in %s: %s") % [DateText.month_long(month), names], PanelKit.Tone.DIM)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_header(box, MUTED, Strings.t("Other revenue"), bn_text(float(book["other_revenue_bn"])), Strings.t("not set here"),
		Strings.t("Revenue no tax in force on this page accounts for."))


## The spending column: the five lines, then the debt service and what no line sets.
static func spending(box: Control, book: Dictionary) -> void:
	_header(box, Color.TRANSPARENT, Strings.t("Spending"), bn_text(float(book["spending_bn"])), "")
	for line in book["lines"]:
		var row := _row()
		row.add_child(_swatch(line_color(String(line["key"]))))
		var name := _cell(row, Labels.portfolio(String(line["key"])), "", SPENDING_NAME_WIDTH)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_cell(row, Strings.t("%s %% of GDP") % Num.f(float(line["pct"]), 1), UiTheme.CAPTION, 0.0).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_cell(row, bn_text(float(line["bn"])), "", FIGURE_WIDTH).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(row)
	_header(box, SERVICE, Strings.t("Debt service"), bn_text(float(book["service_bn"])), Strings.t("not set here"),
		Strings.t("Interest on the debt: it follows the debt and the rates the markets ask."))
	_header(box, MUTED, Strings.t("Other spending"), bn_text(float(book["other_spending_bn"])), Strings.t("not set here"),
		Strings.t("Everything the state spends that none of the five lines sets."))


static func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.custom_minimum_size.y = 26.0 * UiTheme.text_scale()
	return row


static func _swatch(color: Color) -> Control:
	var swatch := ColorRect.new()
	swatch.color = color
	swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return swatch


static func _cell(parent: Control, text: String, variation: String, width: float) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = variation
	label.custom_minimum_size.x = width * UiTheme.text_scale()
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)
	return label


## A group's header (or a part's): swatch, name, a note ("not set here"), the total.
static func _header(box: Control, color: Color, name: String, total: String, note: String, tip := "") -> void:
	var row := _row()
	row.add_theme_constant_override("separation", 8)
	if color.a > 0.0:
		row.add_child(_swatch(color))
	else:
		var gap := Control.new()
		gap.custom_minimum_size.x = SWATCH
		row.add_child(gap)
	var label := _cell(row, name, UiTheme.HEADING, 0.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if note != "":
		var caption := _cell(row, note, UiTheme.CAPTION, 0.0)
		caption.clip_text = false
		caption.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	var figure := _cell(row, total, "", FIGURE_WIDTH)
	figure.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	if tip != "":
		row.tooltip_text = tip
		row.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_theme_constant_override("separation", 8)
	var spaced := MarginContainer.new()
	spaced.add_theme_constant_override("margin_top", 8)
	spaced.add_child(row)
	box.add_child(spaced)


static func _kind_row(ns, kind: Dictionary, wide: bool) -> Control:
	var row := _row()
	var gap := Control.new()
	gap.custom_minimum_size.x = SWATCH + 8.0
	row.add_child(gap)
	var tax: Dictionary = ns.tax_library[String(kind["id"])]
	var who := ", ".join((kind["who"] as Array).map(func(b) -> String: return Labels.bloc(String(b))))
	# The name takes what it needs (a kind's name is the longest thing on the row); who pays fills the
	# rest as a caption while there is room, and is the hover when there is not (130 %).
	var name := _cell(row, Strings.row_name("taxes", tax), "", NAME_WIDTH)
	name.tooltip_text = name.text
	if wide:
		var caption := _cell(row, who, UiTheme.CAPTION, 120.0)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	else:
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.tooltip_text = Strings.t("Paid by: %s") % who
		row.mouse_filter = Control.MOUSE_FILTER_PASS
	_cell(row, LedgerBox.text(float(kind["rate"]), int(kind["decimals"])) + unit_text(String(kind["unit"])), UiTheme.CAPTION, RATE_WIDTH).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_cell(row, bn_text(float(kind["yield_bn"])), "", FIGURE_WIDTH).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return row


static func _fold_button(folded: Array, on_press: Callable) -> Control:
	var button := Button.new()
	button.flat = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var sum := 0.0
	for kind in folded:
		sum += float(kind["yield_bn"])
	button.text = Strings.tn("%d other kind, %s bn", "%d other kinds, %s bn", folded.size()) % [folded.size(), Num.f(sum, 0 if sum >= 10.0 else 1)]
	button.pressed.connect(on_press)
	var gap := MarginContainer.new()
	gap.add_theme_constant_override("margin_left", int(SWATCH + 8.0))
	gap.add_child(button)
	return gap
