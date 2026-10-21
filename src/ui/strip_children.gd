extends RefCounted

## V4.8b. Level two of the strip's tooltip: what a level-1 line is made of.
## `strip_readings.gd` marks a line with a `child_id`; the popup asks for the
## breakdown only when the pointer reaches that line, so nothing here runs on the
## per-day refresh path.
##
## The rule is the register's: surface a figure an existing query computes, never
## decompose one the machine does not (the author's V4.8a call, no src/sim/ diff).
## So an approval issue shows the two operands Opinion.issue_satisfaction
## subtracts -- where the figure stands against where the term began -- and the
## salience and satisfaction it already ranks, and does NOT split satisfaction
## into causes nothing computes. GDP, unemployment, inflation and unrest have no
## child for the same reason.
##
## child(reading_id, child_id, state, loader) -> {title, lines: Array[String]};
## {} for a pair this file does not know, so the walker catches a stale id.

const Labels = preload("res://src/ui/labels.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const Trends = preload("res://src/ui/trends.gd")
const CommoditiesPanel = preload("res://src/ui/commodities_panel.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const EventsK = preload("res://src/sim/events_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")

## Issue key -> [now field, start field] on NationState, for the issues that are a
## delta of one plain field against its start. The tax and spending issues read a
## per-key dictionary instead (see _issue_operands), inflation reads the
## deviation Inflation already computes.
const ISSUE_FIELDS := {
	"jobs": {"now": "unemployment_pct", "base": "start_unemployment_pct", "against": "at the start",  # i18n: msgid against caption fmt
		"caption": "Unemployment", "fmt": "%s%%"},  # i18n: msgid against caption fmt
	# Growth is priced against the nation's TREND, not where growth began: calling
	# it "at the start" told the player the wrong baseline (V4.8b review).
	"growth": {"now": "growth_annual_pct", "base": "trend_annual_pct", "against": "against its trend",  # i18n: msgid against caption fmt
		"caption": "Growth", "fmt": "%s%%"},  # i18n: msgid against caption fmt
	"public_finances": {"now": "deficit_pct_gdp", "base": "start_deficit_pct_gdp", "against": "at the start",  # i18n: msgid against caption fmt
		"caption": "Deficit", "fmt": "%s%% of GDP"},  # i18n: msgid against caption fmt
	"europe": {"now": "bloc_burden", "base": "start_bloc_burden", "against": "at the start",  # i18n: msgid against caption fmt
		"caption": "Council burden", "fmt": "%s"},  # i18n: msgid against caption fmt
}

## How far back the debt path reaches, in months: the strip's own window, then
## double and quadruple it.
const DEBT_PATH_MONTHS: Array[int] = [Trends.TREND_MONTHS, Trends.TREND_MONTHS * 2, Trends.TREND_MONTHS * 4]


static func child(reading_id: String, child_id: String, state, loader) -> Dictionary:
	if state == null or state.player() == null:
		return {}
	var ns = state.player()
	match reading_id:
		"approval":
			if child_id.begins_with("issue:"):
				return _issue(ns, child_id.substr(6))
		"deficit":
			if child_id == "debt":
				return _debt(state, ns)
		"assembly":
			if child_id == "coalition":
				return _coalition(ns, loader)
		"programme":
			if child_id == "entries":
				return _programme(ns, loader)
		"desk":
			if child_id == "queue":
				return _queue(ns, loader)
		"europe":
			if child_id == "rules":
				return _rules(state, ns)
		"commodities":
			if child_id == "short":
				return _short(ns, loader)
	return {}


static func _out(title: String, lines: Array) -> Dictionary:
	var texts: Array[String] = []
	for line in lines:
		texts.append(String(line))
	return {"title": title, "lines": texts}


## Where an issue's input stands now and where the term began, then the salience
## and satisfaction the approval line already prints. An issue this file has no
## operands for is {} -- the walker requires every OpinionK.ISSUE_LABEL key to have
## some, so a new issue cannot slip in without a breakdown.
static func _issue(ns, issue: String) -> Dictionary:
	var label := String(OpinionK.ISSUE_LABEL.get(issue, ""))
	if label.is_empty() and not ns.tax_rates_pct.has(issue.trim_prefix("tax_")):
		return {}
	var operands := _issue_operands(ns, issue)
	if operands.is_empty():
		return {}
	var sat := float(Opinion.issue_satisfaction(ns).get(issue, 0.0))
	var salience := float(ns.issue_salience.get(issue, 0.0))
	if label.is_empty():
		label = Labels.tax(issue.trim_prefix("tax_"))
	return _out(label, [
		operands,
		Strings.t("%.0f%% of minds, satisfaction %s") % [salience * 100.0, Num.fs(sat, 2)],
	])


static func _issue_operands(ns, issue: String) -> String:
	if ISSUE_FIELDS.has(issue):
		var spec: Dictionary = ISSUE_FIELDS[issue]
		var fmt: String = Strings.t(spec["fmt"])
		return Strings.t("%s %s now, %s %s.") % [
			Strings.t(spec["caption"]), fmt % Num.f(float(ns.get(spec["now"])), 2), fmt % Num.f(float(ns.get(spec["base"])), 2), Strings.t(spec["against"])]
	if issue == "inflation":
		return Strings.t("Inflation %s points since the start.") % Num.fs(Inflation.inflation_deviation(ns), 2)
	if issue.begins_with("tax_"):
		var key := issue.substr(4)
		if ns.tax_rates_pct.has(key):
			return Strings.t("Rate %s%% now, %s%% at the start.") % [
				Num.f(float(ns.tax_rates_pct[key]), 1), Num.f(float(ns.start_tax_rates_pct.get(key, 0.0)), 1)]
		return ""
	if ns.spending_pct_gdp.has(issue):
		return Strings.t("Spending %s%% of GDP now, %s%% at the start.") % [
			Num.f(float(ns.spending_pct_gdp[issue]), 2), Num.f(float(ns.start_spending_pct_gdp.get(issue, 0.0)), 2)]
	return ""


## Debt-to-GDP now and back along the history Trends reads; a month history does
## not reach is a dash, never a zero.
static func _debt(state, ns) -> Dictionary:
	var lines: Array = [Strings.t("Now: %s%% of GDP (%.0f Bn).") % [Num.f(ns.debt_to_gdp_pct(), 1), ns.debt_eur_bn]]
	for months in DEBT_PATH_MONTHS:
		var entry: Dictionary = Trends.entry_at(state, months)
		if entry.is_empty() or not entry.has("debt_to_gdp_pct"):
			lines.append(Strings.t("%d months ago: —") % months)
		else:
			lines.append(Strings.t("%d months ago: %s%% of GDP.") % [months, Num.f(float(entry["debt_to_gdp_pct"]), 1)])
	return _out(Strings.t("Debt path"), lines)


static func _coalition(ns, loader) -> Dictionary:
	var names := {}
	if loader != null:
		for party in loader.parties.get(ns.id, []):
			names[String(party.id)] = String(party.party_name)
	var lines: Array = []
	for party_id in ns.coalition_party_ids:
		lines.append(Strings.t("%s: %d seats") % [
			names.get(String(party_id), String(party_id)), int(ns.seats_by_party.get(party_id, 0))])
	return _out(Strings.t("The coalition"), lines)


## Every running entry, not only the nearest-deadline one the figure prices.
static func _programme(ns, loader) -> Dictionary:
	var lines: Array = []
	for live in ns.programme:
		if String(live["status"]) != ProgrammeK.STATUS_ACTIVE:
			continue
		var terms: Dictionary = Programme.terms_of(loader, String(live["entry_id"]))
		if terms.is_empty():
			continue
		var progress: Dictionary = Programme.progress_of(ns, terms)
		var line := Strings.t("%s -- %s against a %s goal") % [
			Strings.row("programme", String(live["entry_id"]), "name", String(terms.get("name", String(live["entry_id"])))),
			Num.f(float(progress["current_value"]), 2), Num.f(float(progress["goal_value"]), 2)]
		var clock := StripReadings.programme_clock_text(terms, live)
		if not clock.is_empty():
			line += " · %s" % clock
		lines.append(line)
	return _out(Strings.t("The programme"), lines)


static func _queue(ns, loader) -> Dictionary:
	var names := {}
	if loader != null:
		for event in loader.events:
			names[String(event.id)] = Strings.row_name("events", event)
	var lines: Array = []
	for entry in ns.event_queue:
		var severity := clampi(int(entry.get("severity", 1)), 1, EventsK.SEVERITY_NAMES.size())
		var event_id := String(entry.get("event_id", ""))
		lines.append("%s: %s" % [Labels.severity(EventsK.SEVERITY_NAMES[severity - 1]), names.get(event_id, event_id)])
	return _out(Strings.t("On the desk"), lines)


static func _rules(state, ns) -> Dictionary:
	var lines: Array = []
	for rule in Orgs.rules_in_force(state, ns):
		lines.append(Strings.t("%s · breach %s · contribution %s") % [
			Strings.row("bloc-proposals", String(rule["id"]), "name", String(rule.get("name", rule["id"]))), Num.f(float(rule.get("breach", 0.0)), 2),
			Num.fs(float(rule.get("contribution", 0.0)), 2)])
	return _out(Strings.t("Rules in force"), lines)


## The panel's own shortage list in the panel's own order: worst first, ties by id.
static func _short(ns, loader) -> Dictionary:
	if loader == null:
		return {}
	var lines: Array = []
	for row in CommoditiesPanel.shortages(ns, loader.commodity_goods.keys()):
		var good = loader.commodity_goods.get(row["id"])
		lines.append(Strings.t("%s: %.0f%% of demand") % [
			String(good.name) if good != null else String(row["id"]), float(row["coverage"]) * 100.0])
	return _out(Strings.t("Short of demand"), lines)
