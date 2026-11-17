extends RefCounted

## V5.3 e: what a measure would do (docs/design/finance-bill.md section 11). A READ over the
## forecasts the game already makes, never a new rule: nothing here writes the game. One
## measure (an open law at its own size, a spending line or a tax rate by a step) is applied
## once on a copy of the state through the game's own appliers (Legislature.apply_effects,
## Budget.commit) and read for every goal at once: the balance a year at today's economy,
## where each bloc's approval is heading (Opinion.target_of), where structural unemployment
## is heading (Economy.structural_target), the demand impulse's sign, and the division as it
## would fall now. Finances reads it for a line's figures (finance_read.gd).
##
## The Bills second pass took the goal tiles off the Bills tab, and with them the month's
## list of every measure, its ranking per goal and the two-year projection: their one reader
## was the goal panel.

const Legislature = preload("res://src/sim/legislature.gd")
const Budget = preload("res://src/sim/budget.gd")
const Economy = preload("res://src/sim/economy.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")
const FinanceBillLaw = preload("res://src/sim/finance_bill_law.gd")


## One measure on a copy: every goal's figure, and the division as it would fall now.
## A law tabled, queued, passed or put on cooldown since the month's list was built is no
## longer open: read as gone ({measure, unavailable}), which rank() leaves out.
static func read(state, loader, measure: Dictionary) -> Dictionary:
	var ns = state.player()
	var law = null
	if String(measure["kind"]) == "law":
		law = _law_if_open(state, loader, String(measure["id"]))
		if law == null:
			return {"measure": measure, "unavailable": true}
	var parties: Array = loader.parties.get(ns.id, [])
	var sim = state.duplicate_state()
	var sns = sim.player()
	Budget.recompute(sim, sns)
	var deficit_before := float(sns.deficit_pct_gdp) * float(sns.gdp_eur_bn)
	var impulse_before := float(sns.demand_impulse_pct)
	var vote: Dictionary
	if law != null:
		Legislature.apply_effects(sim, sns, law.effects, loader)
		vote = Legislature.resolve_vote(ns, parties, law, Legislature.takes_route(ns, law, false))
	else:
		var bill := {_channel(measure): {String(measure["key"]): float(measure["step"])}}
		Budget.commit(sim, _pending(sns, measure))
		vote = FinanceBill.resolve(ns, parties, FinanceBillLaw.law(ns, {"law_id": "finance:read", "finance": bill}))
	Budget.recompute(sim, sns)
	var sat_now := Opinion.issue_satisfaction(ns)
	var sat_then := Opinion.issue_satisfaction(sns)
	var blocs := {}
	for bloc in OpinionK.BLOC_KEYS:
		blocs[bloc] = Opinion.target_of(sns, bloc, sat_then, Opinion.bloc_weights(sns, bloc, sat_then)) \
			- Opinion.target_of(ns, bloc, sat_now, Opinion.bloc_weights(ns, bloc, sat_now))
	return {
		"measure": measure,
		"cost_bn": (deficit_before - float(sns.deficit_pct_gdp) * float(sns.gdp_eur_bn)) / 100.0,
		"bloc_target": blocs,
		"unemployment_target": Economy.structural_target(sns) - Economy.structural_target(ns),
		"impulse": float(sns.demand_impulse_pct) - impulse_before,
		"passes": bool(vote["passed"]), "yes": int(vote["yes_seats"]), "no": int(vote["no_seats"]),
	}


## The law, when it is open to propose now (_open_ids()'s rule), else null.
static func _law_if_open(state, loader, law_id: String):
	if _held(state.player()).has(law_id):
		return null
	return Legislature.open_law(state, state.player(), loader, law_id)


## The law ids in the slot and in the queue.
static func _held(ns) -> Dictionary:
	var held := {String(ns.tabled_bill.get("law_id", "")): true}
	for entry in ns.bill_queue:
		held[String(entry.get("law_id", ""))] = true
	return held


static func _channel(measure: Dictionary) -> String:
	return "spending_pct_gdp" if String(measure["kind"]) == "line" else "tax_rates_pct"


## A step as Budget.commit's absolute pending: the live value plus the step.
static func _pending(ns, measure: Dictionary) -> Dictionary:
	var register: Dictionary = ns.spending_pct_gdp if String(measure["kind"]) == "line" else ns.tax_rates_pct
	var key := String(measure["key"])
	return {_channel(measure): {key: float(register[key]) + float(measure["step"])}}
