extends RefCounted

## V5.2 b+ R14 -- every bill the assembly can be asked to pass, one lookup: the
## authored list, the composed register and the OWNERSHIP BILLS. In France a
## nationalisation or a transfer of ownership is a matter for the law (the
## Constitution, Art. 34), so the two company verbs whose content says
## `requires_law` are never executive acts: each eligible firm is offered a ready
## bill (no drafting, unlike a composed law in statute.gd), and the vote is the
## cost. The design: docs/design/v5.2-bplus-spec.md "R14".
##
## AN OWNERSHIP BILL IS BUILT, NEVER STORED. Its id names the verb and the firm
## (`ownership:<action_id>:<company_id>`) and by_id() rebuilds it from content, so a
## bill the second chamber holds is found again on its day and after a load with no
## register of its own. Its effects carry the one channel `company_ownership` and
## nothing else: adoption runs the verb through Companies.execute(by_law = true),
## which pays the price on the debt and applies the action's own bloc_offset -- once.
##
## Legislature._law_by_id() moved here (and grew the ownership branch) so the bill
## and the lookup that finds it again live in one file.

const Law = preload("res://src/core/law.gd")
const Companies = preload("res://src/sim/companies.gd")

const OWNERSHIP_PREFIX := "ownership:"


## The law `law_id` names, or null: an authored law, else an ownership bill rebuilt
## from content (null when the verb or the firm is no longer in content).
static func by_id(loader, law_id: String):
	if loader == null or law_id == "":
		return null
	for law in loader.laws:
		if law.id == law_id:
			return law
	if not law_id.begins_with(OWNERSHIP_PREFIX):
		return null
	var parts := law_id.substr(OWNERSHIP_PREFIX.length()).split(":", true, 1)
	if parts.size() != 2:
		return null
	for firms in loader.companies.values():
		for company in firms:
			if String(company.id) == parts[1]:
				return _bill(_action(loader, parts[0]), company)
	return null


## The ready bills for one firm: one per `requires_law` verb whose preconditions
## hold for it now.
static func ownership(state, ns, loader, company_id: String) -> Array:
	var out: Array = []
	var company = null
	for c in Companies.firms_of(loader, ns.id):
		if String(c.id) == company_id:
			company = c
	if company == null:
		return out
	for action in Companies.available(state, ns, loader.company_actions, company_id, loader, true):
		var bill = _bill(action, company)
		if bill != null:
			out.append(bill)
	return out


## Every bill `ns` may table now -- what Legislature.propose()'s legality scan reads,
## so an ownership bill is a law like any other there (cooldown, a hold, 49.3).
static func open(state, ns, loader) -> Array:
	var out: Array = loader.laws + Law.composed_register(ns)
	for company in Companies.majors_of(loader, ns.id):
		out.append_array(ownership(state, ns, loader, String(company.id)))
	return out


## The adopted bill's channel: the verb, through the law's door. A firm no longer
## eligible on the day (a stake taken while the bill was held) is refused there and
## buys nothing; ns.last_company_result records the refusal.
static func adopt(state, ns, loader, terms: Dictionary) -> void:
	var action = _action(loader, String(terms.get("action_id", "")))
	if action != null:
		Companies.execute(state, ns, loader.company_actions, action, String(terms.get("company_id", "")), loader, true)


static func _action(loader, action_id: String):
	for action in loader.company_actions:
		if String(action.id) == action_id and action.requires_law:
			return action
	return null


## An ordinary bill at a simple majority, repeatable, positioned where the
## content's `bill` block says the parties read it.
static func _bill(action, company):
	if action == null or company == null:
		return null
	var law := Law.new()
	law.id = "%s%s:%s" % [OWNERSHIP_PREFIX, action.id, company.id]
	law.law_name = "%s: %s" % [action.action_name, company.company_name]
	law.theme = "business"
	law.summary = action.summary
	law.position = (action.bill["position"] as Dictionary).duplicate()
	law.majority = "simple"
	law.cooldown_months = int(action.bill["cooldown_months"])
	law.once = false
	law.effects = {"company_ownership": {"company_id": String(company.id), "action_id": String(action.id)}}
	return law
