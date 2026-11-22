extends RefCounted

## The register's PROGRAMME sheet -- G3 S4, Register in C (register-in-c.png): the programme's facts beside the
## regions, as the bill's facts are beside Books. What and where (two tiles), the money (the quote's range and the
## bill by year, its running cost in the hue of the spending line it lands on), when it opens and what can go wrong,
## then the screen's one filled button. Moved out of register_panel.gd (the size ratchet).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const DateText = preload("res://src/ui/date_text.gd")
const ChartKit = preload("res://src/ui/chart_kit.gd")
const RegisterMoney = preload("res://src/ui/register_money.gd")
const RegisterLines = preload("res://src/ui/register_lines.gd")
const FinanceRowsUi = preload("res://src/ui/finance_rows.gd")
const Labels = preload("res://src/ui/labels.gd")
const Icon = preload("res://src/ui/icon.gd")
const Units = preload("res://src/sim/units.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const UnitBuild = preload("res://src/sim/unit_build.gd")
const UK = preload("res://src/sim/units_constants.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")

const WIDTH := 360.0


static func build(panel, parent: Control, ns, row: Dictionary, quote: Dictionary) -> void:
	var body := PanelKit.sheet(parent, Strings.t("The programme"))
	body.get_parent().size_flags_horizontal = Control.SIZE_FILL
	body.get_parent().custom_minimum_size.x = WIDTH * UiTheme.text_scale()
	# As tall as its own content, never the regions' table: a long table (Poland's 17 regions at 115 %) would carry the
	# press under the fold (pass 2 T6 on #447).
	body.get_parent().size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var rows: Array = panel.rows()
	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", 8)
	body.add_child(tiles)
	PanelKit.figure_tile(tiles, str(panel._sum()), Strings.row_name("units", row))
	var where: String = panel._region_name(String(rows[0]["region"])) if rows.size() == 1 else Strings.tn("%d region", "%d regions", rows.size()) % rows.size()
	PanelKit.figure_tile(tiles, where, Strings.t("Where")).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# No quote: nothing to price; why is said once, under the greyed press (pass 2 T2 on #447).
	if not quote.is_empty():
		_money(panel, body, row, quote)
		_when(panel, body, ns, quote)
	_in_bill(panel, body, ns)
	_press(panel, body)


static func _money(panel, body: Control, row: Dictionary, quote: Dictionary) -> void:
	PanelKit.heading(body, Strings.t("The money"))
	var lo := float(quote["lo_eur_m"]) / 1000.0
	var hi := float(quote["hi_eur_m"]) / 1000.0
	var months := int(quote["build_months"])
	var running := float(quote["running_eur_m_year"]) / 1000.0
	var line := PanelKit.plain_line(body, Strings.t("%s to %s bn over %d months, then %s bn a year for good.") % [
		Num.f(lo, 2), Num.f(hi, 2), months, Num.f(running, 2)], PanelKit.Tone.PLAIN)
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.set_meta("money", true)
	ChartKit.range_bar(body, Strings.t("Price range, bn"), lo, float(quote["estimate_eur_m"]) / 1000.0, hi).set_meta("range", true)
	PanelKit.plain_line(body, Strings.t("By year, bn"), PanelKit.Tone.DIM).theme_type_variation = UiTheme.CAPTION
	var cash = RegisterMoney.new()
	cash.set_meta("cash", true)
	# Its running cost lands on a spending line: that line's hue, never the accent (Diane's R4 on #443).
	cash.running_color = FinanceRowsUi.line_color(String(row.get("line", "")))
	body.add_child(cash)
	cash.cash_of(UnitPrice.now(panel._state), months, float(quote["estimate_eur_m"]) / 1000.0, running,
		[Strings.t("Building"), Strings.t("Running cost, on %s's line") % Labels.portfolio(String(row.get("line", "")))])


static func _when(panel, body: Control, ns, quote: Dictionary) -> void:
	PanelKit.heading(body, Strings.t("When, and what can go wrong"))
	var months := int(quote["build_months"])
	var open_at := UnitPrice.now(panel._state) + months
	PanelKit.plain_line(body, Strings.t("Opens about %s, %d months after the vote.") % [
		DateText.month_long_year((open_at - 1) % 12 + 1, (open_at - 1) / 12), months], PanelKit.Tone.PLAIN)
	# A risk without a date is plain text with its glyph (Design, Register in C): amber is for a date to answer by.
	var risk := HBoxContainer.new()
	risk.add_theme_constant_override("separation", 6)
	body.add_child(risk)
	var glyph := TextureRect.new()
	glyph.texture = Icon.load_icon("res://assets/icons/material/warning.svg", UiTheme.BAD, roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale()))
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	risk.add_child(glyph)
	var odds := PanelKit.plain_line(risk, Strings.t("%s %% chance of one overrun ask during the build") % Num.f(100.0 * float(quote["odds"]), 0), PanelKit.Tone.PLAIN)
	odds.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	odds.set_meta("odds", true)
	RegisterLines.union(body, panel._state, ns, panel._loader, {"type": panel._type, "rows": panel.rows()}, quote)
	# The concentration surcharge (section 4), said on the region it falls on, before the press.
	var surcharge: Dictionary = quote.get("surcharge", {})
	for id in surcharge:
		# A warning only when it rounds to 1 % or more (the parent's ruling): the range carries the rest.
		if roundi(100.0 * float(surcharge[id])) >= 1:
			PanelKit.chip(body, Strings.t("+%s %% on the price in %s: many units there within a year") % [
				Num.f(100.0 * float(surcharge[id]), 0), panel._region_name(String(id))]).set_meta("surcharge", String(id))


## The programmes the tabled finance bill already carries, with the day it divides.
static func _in_bill(panel, body: Control, ns) -> void:
	var held: Array = (ns.tabled_bill.get("finance", {}) as Dictionary).get(FinanceRows.UNITS, [])
	if held.is_empty():
		return
	PanelKit.heading(body, Strings.t("In the finance bill"))
	var when := DateText.day_month(int(ns.tabled_bill.get("vote_day", 1)), int(ns.tabled_bill.get("vote_month", 1)))
	var forced := bool(ns.tabled_bill.get("forced", false))
	for p in held:
		var n := 0
		for r in p.get("rows", []):
			n += int(r.get("units", 0))
		var name := Strings.row_name("units", Units.row(panel._loader, String(p.get("type", ""))))
		var text := Strings.tn("%d unit of %s: adopted without a vote on %s.", "%d units of %s: adopted without a vote on %s.", n) if forced else Strings.tn("%d unit of %s: it divides on %s.", "%d units of %s: it divides on %s.", n)
		PanelKit.plain_line(body, text % [n, name, when], PanelKit.Tone.PLAIN).set_meta("in_bill", true)


## The press, greyed with the bill's own reason before it is pressed, and the refusal said under it.
static func _press(panel, body: Control) -> void:
	var bill := {FinanceRows.UNITS: [{"type": panel._type, "op": UK.OP_BUILD, "rows": panel.rows()}]}
	var why: String = panel._why_not(bill)
	var press := PanelKit.sized(Button.new())
	press.theme_type_variation = UiTheme.PRIMARY
	press.text = Strings.t("Put it in the finance bill")
	press.disabled = why != ""
	press.set_meta("table", true)
	press.pressed.connect(func() -> void: panel.table_programme())
	PanelKit.buttons(body).add_child(press)
	var said: String = why if why != "" else panel._refusal
	var refusal := PanelKit.plain_line(body, said, PanelKit.Tone.PLAIN)
	refusal.theme_type_variation = UiTheme.WARN_TEXT
	refusal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	refusal.visible = said != ""
	refusal.set_meta("refusal", true)


## What the bill's rail shows as the place this programme would take (a dashed row): {} while it cannot be tabled.
static func landing(panel, row: Dictionary, quote: Dictionary) -> Dictionary:
	var rows: Array = panel.rows()
	var bill := {FinanceRows.UNITS: [{"type": panel._type, "op": UK.OP_BUILD, "rows": rows}]}
	if quote.is_empty() or panel._why_not(bill) != "":
		return {}
	var n: int = panel._sum()
	var where: String = panel._region_name(String(rows[0]["region"])) if rows.size() == 1 else Strings.tn("%d region", "%d regions", rows.size()) % rows.size()
	return {"title": Strings.tn("%s · %s · %d lands here", "%s · %s · %d land here", n) % [Strings.row_name("units", row), where, n],
		"line": Strings.t("%s to %s bn over %d months, then %s bn a year") % [Num.f(float(quote["lo_eur_m"]) / 1000.0, 2),
			Num.f(float(quote["hi_eur_m"]) / 1000.0, 2), int(quote["build_months"]), Num.f(float(quote["running_eur_m_year"]) / 1000.0, 2)]}
