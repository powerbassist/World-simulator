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
const ActsOn = preload("res://src/ui/acts_on.gd")
const FinanceOfWhich = preload("res://src/ui/finance_of_which.gd")
const TaxLibrary = preload("res://src/core/tax_library.gd")
const TaxesLoader = preload("res://src/core/loaders/taxes_loader.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const FinanceDraft = preload("res://src/ui/finance_draft.gd")

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
## A spending line's figure ("from 11.0 to 12.5 %"): the name button takes the rest, never this. The unit is the
## column's heading (% of GDP), so the figure stays short enough for the pane at the former 130 % text size.
const PCT_WIDTH := 124.0
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
static func revenue(box: Control, book: Dictionary, state, loader, open_groups: Dictionary, toggle: Callable, ctx: Dictionary) -> void:
	var ns = state.player()
	for group in book["groups"]:
		var gid := String(group["id"])
		_header(box, group_color(gid), group_name(gid), bn_text(float(group["total"])), "")
		for kind in group["kinds"]:
			_kind_with_editor(box, ns, kind, ctx)
		var folded: Array = group["folded"]
		if not folded.is_empty():
			if open_groups.has(gid):
				for kind in folded:
					_kind_with_editor(box, ns, kind, ctx)
			else:
				box.add_child(_fold_button(folded, toggle.bind(gid)))
		var absent: Array = group["not_in_force"]
		if not absent.is_empty() and bool(ctx.get("autumn", false)):
			# The autumn bill may put a kind in force: each is a row with its verb (a kind already in the draft is an
			# ordinary kind row with its editor, and one at vote is locked as every row at vote is).
			for kind in absent:
				_birth_row(box, ns, String(kind), ctx)
		elif not absent.is_empty():
			var names := ", ".join(absent.map(func(k) -> String: return Strings.row_name("taxes", ns.tax_library[k])))
			var month := int(loader.nations[ns.id].finance_autumn_month)
			var line := PanelKit.plain_line(box, Strings.t("Not in force, creatable in %s: %s") % [DateText.month_long(month), names], PanelKit.Tone.DIM)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD
	_header(box, MUTED, Strings.t("Other revenue"), bn_text(float(book["other_revenue_bn"])), Strings.t("not set here"), _other_revenue_tip(ctx))
	FinanceOfWhich.build(box, book["of_which"]["revenue"], "other_revenue", ctx)


## The spending column: the five lines, then the debt service and what no line sets.
static func spending(box: Control, book: Dictionary, ctx: Dictionary) -> void:
	_header(box, Color.TRANSPARENT, Strings.t("Spending"), bn_text(float(book["spending_bn"])), Strings.t("lines in % of GDP"))
	for line in book["lines"]:
		var row := _row()
		row.add_child(_swatch(line_color(String(line["key"]))))
		var id := row_id(FinanceDraft.SPENDING, String(line["key"]))
		# A line with a sector slipping says so while closed: a warning on a closed row is unseen (the Budget's mark).
		var shown := Labels.portfolio(String(line["key"]))
		var name := _name_cell(row, Strings.t("%s (!)") % shown if (ctx.get("slipping", []) as Array).has(String(line["key"])) else shown, id, SPENDING_NAME_WIDTH, ctx)
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# What a briefing's Go on the deficit lands on (acts_on.gd): any line's slider acts on the balance.
		ActsOn.tag(name, ["deficit", "balance"])
		var pct := _cell(row, "", UiTheme.CAPTION, PCT_WIDTH)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		(ctx["cells"] as Dictionary)[id] = [pct, FinanceDraft.SPENDING, String(line["key"]), float(line["pct"])]
		_cell(row, bn_text(float(line["bn"])), "", FIGURE_WIDTH).horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		box.add_child(row)
		if String(ctx["open"]) == id and not (ctx["tabled"] as Dictionary).has(id):
			box.add_child((ctx["editor"] as Callable).call(FinanceDraft.SPENDING, String(line["key"])))
	_header(box, SERVICE, Strings.t("Debt service"), bn_text(float(book["service_bn"])), Strings.t("not set here"),
		Strings.t("Interest on the debt: it follows the debt and the rates the markets ask."))
	_header(box, MUTED, Strings.t("Other spending"), bn_text(float(book["other_spending_bn"])), Strings.t("not set here"),
		Strings.t("Everything the state spends that none of the five lines sets. The parts that are not zero are listed under it (the Union, deployments, subsidies and the like); the rest of the authored figure is not split."))
	FinanceOfWhich.build(box, book["of_which"]["spending"], "other_spending", ctx)


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
	# A header's name is what the column is read by: it keeps its own width, and the note gives way (it fills what is
	# left and is trimmed), never "Other spend..." (QA's T1 on #366, once the scroll bar's gap took 8 px at the
	# former 130 % text size).
	label.clip_text = false
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	if note != "":
		var caption := _cell(row, note, UiTheme.CAPTION, 0.0)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	else:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if note != "":
			tip = note if tip == "" else note + ". " + tip
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


static func _kind_row(ns, kind: Dictionary, ctx: Dictionary) -> Control:
	var row := _row()
	var gap := Control.new()
	gap.custom_minimum_size.x = SWATCH + 8.0
	row.add_child(gap)
	var tax: Dictionary = ns.tax_library[String(kind["id"])]
	var who := ", ".join((kind["who"] as Array).map(func(b) -> String: return Labels.bloc(String(b))))
	# The name takes what it needs (a kind's name is the longest thing on the row); who pays fills the
	# rest as a caption while there is room, and is always the row's hover too: at the largest size the caption is cut.
	var id := row_id(FinanceDraft.TAX, String(kind["id"]))
	var name := _name_cell(row, Strings.row_name("taxes", tax), id, NAME_WIDTH, ctx)
	name.tooltip_text = name.text
	var at_vote: bool = (ctx["tabled"] as Dictionary).has(id)
	var tag := who
	if at_vote:
		tag = Strings.t("At vote")
	elif (ctx["draft"] as FinanceDraft).is_created(String(kind["id"])):
		tag = Strings.t("Creation")
	var caption := _cell(row, tag, UiTheme.CAPTION, 120.0)
	caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	# Who pays is the caption's text unless the row is at vote or created: the hover always says it, so a
	# caption cut to an ellipsis can still be read.
	caption.set_meta("who_pays", true)
	row.tooltip_text = Strings.t("Paid by: %s") % who
	row.mouse_filter = Control.MOUSE_FILTER_PASS
	var rate := _cell(row, "", UiTheme.CAPTION, RATE_WIDTH)
	rate.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	(ctx["cells"] as Dictionary)[id] = [rate, FinanceDraft.TAX, String(kind["id"]), float(kind["rate"]), int(kind["decimals"]), String(kind["unit"])]
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


## The identity of an editable row: its channel and key, the one string the page, the goal panel's Go and the
## tests name a row by.
static func row_id(channel: String, key: String) -> String:
	return "%s:%s" % [channel, key]


## A kind not in force, in the autumn: its name and the verb that puts it in force. In the draft already, or at vote, it is
## a kind row like any other (no rate yet, no yield).
static func _birth_row(box: Control, ns, kind: String, ctx: Dictionary) -> void:
	var id := row_id(FinanceDraft.TAX, kind)
	var tax: Dictionary = ns.tax_library[kind]
	if (ctx["draft"] as FinanceDraft).is_created(kind) or (ctx["tabled"] as Dictionary).has(id):
		_kind_with_editor(box, ns, {"id": kind, "rate": 0.0, "yield_bn": 0.0, "unit": String(tax["unit"]), "who": tax.get("who_pays", []),
			"decimals": TaxLibrary.step_decimals(ns, kind)}, ctx)
		return
	var row := _row()
	var gap := Control.new()
	gap.custom_minimum_size.x = SWATCH + 8.0
	row.add_child(gap)
	var name := _cell(row, Strings.row_name("taxes", tax), UiTheme.CAPTION, NAME_WIDTH)
	name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name.tooltip_text = Strings.row_summary("taxes", tax)
	var put := PanelKit.sized(Button.new())
	put.name = "PutInForce_" + kind  # i18n: ok a node name, found by tests
	put.text = Strings.t("Put in force")
	put.flat = true
	put.pressed.connect((ctx["on_create"] as Callable).bind(kind))
	row.add_child(put)
	box.add_child(row)


## A row with its editor under it while it is the open one.
static func _kind_with_editor(box: Control, ns, kind: Dictionary, ctx: Dictionary) -> void:
	box.add_child(_kind_row(ns, kind, ctx))
	var id := row_id(FinanceDraft.TAX, String(kind["id"]))
	if String(ctx["open"]) == id and not (ctx["tabled"] as Dictionary).has(id):
		box.add_child((ctx["editor"] as Callable).call(FinanceDraft.TAX, String(kind["id"])))


## A row's name: the button that opens its editor, or a plain name while the row is at vote (a tabled
## row is locked until the bill is withdrawn, as in the picture).
static func _name_cell(row: Control, text: String, id: String, width: float, ctx: Dictionary) -> Control:
	if (ctx["tabled"] as Dictionary).has(id):
		var locked := _cell(row, text, "", width)
		locked.tooltip_text = Strings.t("At vote: withdraw the bill to change it.")
		return locked
	var button := Button.new()
	button.text = text
	button.theme_type_variation = UiTheme.SUBROW_BUTTON
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.toggle_mode = true
	button.button_pressed = String(ctx["open"]) == id
	button.custom_minimum_size.x = width * UiTheme.text_scale()
	button.clip_text = true
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.pressed.connect((ctx["on_open"] as Callable).bind(id))
	row.add_child(button)
	return button


## Every moved row's figure, in place: "20 -> 22 %" while the draft moves it or a tabled bill will, the
## register's figure otherwise. Written on the cells the rows kept, never by rebuilding them (a rebuild
## would drop the slider the player is holding).
static func paint_rates(ctx: Dictionary) -> void:
	var draft = ctx["draft"]
	var tabled: Dictionary = ctx["tabled"]
	for id in ctx["cells"]:
		var cell: Array = ctx["cells"][id]
		var label: Label = cell[0]
		if not is_instance_valid(label):
			continue
		var channel := String(cell[1])
		var key := String(cell[2])
		var live := float(cell[3])
		var target := live
		if tabled.has(id):
			target = live + float(tabled[id])
		elif draft.is_moved(channel, key):
			target = draft.value(channel, key)
		var spending := channel == FinanceDraft.SPENDING
		var places := 1 if spending else int(cell[4])
		var was := LedgerBox.text(live, places)
		var unit := "" if spending else unit_text(String(cell[5]))
		if channel == FinanceDraft.TAX and draft.is_abolished(key):
			label.text = Strings.t("abolish")
		# A birth at vote is a kind not in force; one in force at 0 % (the wealth tax) raised is a rate row (retro item 11).
		elif channel == FinanceDraft.TAX and (draft.is_created(key) or (tabled.has(id) and not draft.in_force(key))):
			label.text = Strings.t("new, at %s") % (LedgerBox.text(target, places) + unit)
		elif target == live:
			label.text = Strings.t("%s %%") % Num.f(live, 1) if spending else was + unit
		elif spending:
			label.text = Strings.t("from %s to %s %%") % [was, LedgerBox.text(target, places)]
		else:
			label.text = Strings.t("from %s to %s") % [was, LedgerBox.text(target, places) + unit]


## What the unset revenue holds, as the model keeps it (FinanceRead.other_parts): the part set when the game
## begins so that revenue equals the nation's real figure, and what the laws in force add.
static func _other_revenue_tip(ctx: Dictionary) -> String:
	var parts: Array = ctx["parts"]["revenue"]
	return Strings.t("%s bn of it is revenue no rate here sets (social contributions, local taxes), and %s bn is what laws in force add. Tariffs and dividends are listed under it when there are any; the rest is not split.") % [
		Num.f(float(parts[0]["bn"]), 0), Num.f(float(parts[1]["bn"]), 1)]


## A drafted change's name (finance_draft.gd's rows()): a line, a tax, a kind put in force or abolished, the brackets.
## The bill's sheet and the Books page's tray both say it.
static func change_label(ns, row: Dictionary) -> String:
	var key := String(row["key"])
	match String(row["channel"]):
		FinanceDraft.SPENDING:
			return Labels.portfolio(key)
		FinanceDraft.TAX:
			var tax := Strings.row_name("taxes", ns.tax_library[key])
			return Strings.t("Creation of %s") % tax if bool(row.get("birth", false)) else tax
		FinanceDraft.ABOLISH:
			return Strings.t("Abolition of %s") % Strings.row_name("taxes", ns.tax_library[key])
	return Strings.t("Income brackets")


## "11 → 12.5 % of GDP": the change's value today and in the draft, in its row's own unit and decimals.
static func change_figures(ns, row: Dictionary) -> String:
	var key := String(row["key"])
	var places := 1
	var unit := Strings.t(" % of GDP")
	match String(row["channel"]):
		FinanceDraft.TAX, FinanceDraft.ABOLISH:
			places = TaxLibrary.step_decimals(ns, key)
			unit = unit_text(String(ns.tax_library[key]["unit"]))
		FinanceDraft.BRACKETS:
			places = 2
			unit = ""
	return "%s → %s%s" % [LedgerBox.text(float(row["live"]), places), LedgerBox.text(float(row["draft"]), places), unit]
