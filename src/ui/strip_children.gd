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

## Issue key -> [now field, start field] on NationState, for the issues that are a
## delta of one plain field against its start. The tax and spending issues read a
## per-key dictionary instead (see _issue_operands), inflation reads the
## deviation Inflation already computes.
const ISSUE_FIELDS := {
	"jobs": ["unemployment_pct", "start_unemployment_pct", "Unemployment", "%.2f%%"],
	"growth": ["growth_annual_pct", "trend_annual_pct", "Growth", "%.2f%%"],
	"public_finances": ["deficit_pct_gdp", "start_deficit_pct_gdp", "Deficit", "%.2f%% of GDP"],
	"europe": ["bloc_burden", "start_bloc_burden", "Council burden", "%.2f"],
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
		label = issue.trim_prefix("tax_").capitalize() + " tax"
	return _out(label, [
		operands,
		"%.0f%% of minds, satisfaction %+.2f" % [salience * 100.0, sat],
	])


static func _issue_operands(ns, issue: String) -> String:
	if ISSUE_FIELDS.has(issue):
		var spec: Array = ISSUE_FIELDS[issue]
		var fmt: String = spec[3]
		return "%s %s now, %s at the start." % [
			spec[2], fmt % float(ns.get(spec[0])), fmt % float(ns.get(spec[1]))]
	if issue == "inflation":
		return "Inflation %+.2f points since the start." % Inflation.inflation_deviation(ns)
	if issue.begins_with("tax_"):
		var key := issue.substr(4)
		if ns.tax_rates_pct.has(key):
			return "Rate %.1f%% now, %.1f%% at the start." % [
				float(ns.tax_rates_pct[key]), float(ns.start_tax_rates_pct.get(key, 0.0))]
		return ""
	if ns.spending_pct_gdp.has(issue):
		return "Spending %.2f%% of GDP now, %.2f%% at the start." % [
			float(ns.spending_pct_gdp[issue]), float(ns.start_spending_pct_gdp.get(issue, 0.0))]
	return ""


## Debt-to-GDP now and back along the history Trends reads; a month history does
## not reach is a dash, never a zero.
static func _debt(state, ns) -> Dictionary:
	var lines: Array = ["Now: %.1f%% of GDP (%.0f Bn)." % [ns.debt_to_gdp_pct(), ns.debt_eur_bn]]
	for months in DEBT_PATH_MONTHS:
		var entry: Dictionary = Trends.entry_at(state, months)
		if entry.is_empty() or not entry.has("debt_to_gdp_pct"):
			lines.append("%d months ago: —" % months)
		else:
			lines.append("%d months ago: %.1f%% of GDP." % [months, float(entry["debt_to_gdp_pct"])])
	return _out("Debt path", lines)


static func _coalition(ns, loader) -> Dictionary:
	var names := {}
	if loader != null:
		for party in loader.parties.get(ns.id, []):
			names[String(party.id)] = String(party.party_name)
	var lines: Array = []
	for party_id in ns.coalition_party_ids:
		lines.append("%s: %d seats" % [
			names.get(String(party_id), String(party_id)), int(ns.seats_by_party.get(party_id, 0))])
	return _out("The coalition", lines)


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
		var line := "%s -- %.2f against a %.2f goal" % [
			String(terms.get("name", String(live["entry_id"]))),
			float(progress["current_value"]), float(progress["goal_value"])]
		var clock := StripReadings.programme_clock_text(terms, live)
		if not clock.is_empty():
			line += " · %s" % clock
		lines.append(line)
	return _out("The programme", lines)


static func _queue(ns, loader) -> Dictionary:
	var names := {}
	if loader != null:
		for event in loader.events:
			names[String(event.id)] = String(event.event_name)
	var lines: Array = []
	for entry in ns.event_queue:
		var severity := clampi(int(entry.get("severity", 1)), 1, EventsK.SEVERITY_NAMES.size())
		var event_id := String(entry.get("event_id", ""))
		lines.append("%s: %s" % [EventsK.SEVERITY_NAMES[severity - 1].capitalize(), names.get(event_id, event_id)])
	return _out("On the desk", lines)


static func _rules(state, ns) -> Dictionary:
	var lines: Array = []
	for rule in Orgs.rules_in_force(state, ns):
		lines.append("%s · breach %.2f · contribution %+.2f" % [
			String(rule.get("name", rule["id"])), float(rule.get("breach", 0.0)),
			float(rule.get("contribution", 0.0))])
	return _out("Rules in force", lines)


## The panel's own shortage list in the panel's own order: worst first, ties by id.
static func _short(ns, loader) -> Dictionary:
	if loader == null:
		return {}
	var short: Array = []
	for good_id in loader.commodity_goods.keys():
		var covered := CommoditiesPanel.coverage(ns, String(good_id))
		if covered < CommoditiesPanel.SHORTAGE_COVERAGE:
			short.append({"id": String(good_id), "coverage": covered})
	short.sort_custom(func(a, b) -> bool:
		if not is_equal_approx(float(a["coverage"]), float(b["coverage"])):
			return float(a["coverage"]) < float(b["coverage"])
		return String(a["id"]) < String(b["id"]))
	var lines: Array = []
	for row in short:
		var good = loader.commodity_goods.get(row["id"])
		lines.append("%s: %.0f%% of demand" % [
			String(good.name) if good != null else String(row["id"]), float(row["coverage"]) * 100.0])
	return _out("Short of demand", lines)
