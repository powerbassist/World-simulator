extends RefCounted

## One thing the council can be asked to adopt, loaded from
## data/bloc-proposals/*.json. Validated at startup and never mutated, the same
## treatment src/core/law.gd and src/core/diplomatic_action.gd get.
##
## Shaped after a LAW rather than after a diplomatic action, and that is the
## session's one content-shape decision. docs/diplomacy-model.md cut `position`,
## `majority` and `once` from a diplomatic action because an executive act has no
## division to score. A bloc proposal has one: the council divides, the player is
## one voter in it, and the vote can be lost. So it carries a `position` on the
## same two-axis space every party, coalition and law already uses, and
## src/sim/bloc.gd scores the other members' coalition_position against it.
##
## The model, and the justification for every constant, is docs/bloc-model.md.

const K = preload("res://src/sim/bloc_constants.gd")
const CK = preload("res://src/sim/coercion_constants.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")

var id: String = ""
var proposal_name: String = ""
var summary: String = ""

## The org whose council this proposal reaches. Required since V3.2 -- the
## register carries many councils and the flat agenda list alone can no longer
## answer "whose council is this". Validated against the loaded org ids.
var org_id: String = ""

## Position on the same two-axis ideology space election_constants.gd's
## SLOT_POSITION uses -- economic (-1 left ... +1 right), social (-1 open ...
## +1 traditional). No parallel vocabulary, exactly as src/core/law.gd says.
var position: Dictionary = {}

## What this rule requires of a member that is bound by it, or {} for a proposal
## that binds nobody's policy and only moves money.
## {field, op, value, tolerance, severity}.
var constraint: Dictionary = {}

## Standing change to a bound member's net transfer, percent of GDP. Signed: a
## joint fund the player draws on is negative, a contribution increase positive.
## This is where a bloc proposal can be a BENEFIT rather than only a cost, and
## the reason there is no structural single-market uplift -- see
## docs/bloc-model.md, "Deliberately absent".
var transfer_pct_gdp: float = 0.0

## The bloc setting an external tariff collectively: {kind, severity}, applied by
## every member against every non-member. Optional, and the first reader of
## V1.3c's directed register from outside src/sim/coercion.gd.
var external_measure: Dictionary = {}

## V4.5a. This proposal's decision class, or "" to read its org's decision_rule
## -- a proposal cannot see its org at parse time, so the inheritance is
## resolved by Council.decision_of() at the division, not here.
var decision: String = ""

## V4.5a. The NATION that wants this adopted, or "" for none. A nation, not a
## person: the face is that nation's live head of government, so an election
## abroad changes who is pushing without the content knowing. Validated against
## the org's authored members by data_loader._validate_bloc_proposals().
var sponsor: String = ""


static func from_dict(d: Dictionary, filename: String, errors: Array[String], org_ids: Array):
	var p := new()

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: missing or invalid string field 'id'" % filename)
	else:
		p.id = d["id"]

	# org is REQUIRED and validated against the loaded register, the same way an
	# action's bloc_offset keys are validated against BLOC_KEYS -- a proposal on
	# an org that does not exist is a council that can never convene. The ids
	# ride in rather than a lookup, because a core content type reaching into
	# the loader is the dependency pointing the wrong way.
	var org = d.get("org", "")
	if typeof(org) != TYPE_STRING or org == "":
		errors.append("%s: %s missing string field 'org'" % [filename, p.id])
	elif not org_ids.has(org):
		errors.append("%s: %s names org '%s', which is not a loaded org" % [filename, p.id, org])
	else:
		p.org_id = org

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, p.id])
	else:
		p.proposal_name = d["name"]

	p.summary = d.get("summary", "")
	if typeof(p.summary) != TYPE_STRING:
		errors.append("%s: %s summary must be a string" % [filename, p.id])
		p.summary = ""

	p.position = _extract_position(d, p.id, filename, errors)
	p.constraint = _extract_constraint(d, p.id, filename, errors)
	p.external_measure = _extract_external_measure(d, p.id, filename, errors)

	var transfer = d.get("transfer_pct_gdp", 0.0)
	if not (typeof(transfer) == TYPE_INT or typeof(transfer) == TYPE_FLOAT):
		errors.append("%s: %s transfer_pct_gdp must be numeric" % [filename, p.id])
	else:
		p.transfer_pct_gdp = float(transfer)
		if absf(p.transfer_pct_gdp) > K.MAX_PROPOSAL_TRANSFER_PCT_GDP:
			errors.append("%s: %s transfer_pct_gdp %.3f exceeds the limit of +/-%.2f%% of GDP" % [
				filename, p.id, p.transfer_pct_gdp, K.MAX_PROPOSAL_TRANSFER_PCT_GDP,
			])

	var decision = d.get("decision", "")
	if typeof(decision) != TYPE_STRING:
		errors.append("%s: %s decision must be a string" % [filename, p.id])
	elif decision != "" and not CouncilK.DECISION_RULES.has(decision):
		errors.append("%s: %s decision '%s' is not one of %s" % [filename, p.id, decision, CouncilK.DECISION_RULES])
	else:
		p.decision = decision

	var sponsor = d.get("sponsor", "")
	if typeof(sponsor) != TYPE_STRING:
		errors.append("%s: %s sponsor must be a nation id string" % [filename, p.id])
	else:
		p.sponsor = sponsor

	# A proposal that constrains nobody, moves no money and sets no external
	# measure is a vote about nothing -- the council would divide over it and the
	# player would feel exactly the same either way. Refused for the same reason
	# diplomatic_action.gd refuses a zero effects.relations: it is content that
	# reads as a decision and is not one.
	if p.constraint.is_empty() and p.transfer_pct_gdp == 0.0 and p.external_measure.is_empty():
		errors.append("%s: %s has no constraint, no transfer and no external_measure -- nothing would change if it passed" % [filename, p.id])

	return p


static func _extract_position(d: Dictionary, proposal_id: String, filename: String, errors: Array[String]) -> Dictionary:
	var raw = d.get("position", null)
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s missing or invalid object field 'position'" % [filename, proposal_id])
		return {"economic": 0.0, "social": 0.0}

	var out := {}
	for axis in ["economic", "social"]:
		var v = raw.get(axis, null)
		if not (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT):
			errors.append("%s: %s position.%s is missing or not numeric" % [filename, proposal_id, axis])
			out[axis] = 0.0
			continue
		if float(v) < -1.0 or float(v) > 1.0:
			errors.append("%s: %s position.%s %.3f is outside [-1, 1]" % [filename, proposal_id, axis, float(v)])
		out[axis] = clampf(float(v), -1.0, 1.0)
	return out


## The rule itself. `tolerance` is the breach size at which this rule contributes
## its full severity to the burden -- floored at load, because a tolerance near
## zero turns a continuous quantity into a step and the panel would show a cliff
## where the model claims a slope.
static func _extract_constraint(d: Dictionary, proposal_id: String, filename: String, errors: Array[String]) -> Dictionary:
	var raw = d.get("constraint", null)
	if raw == null:
		return {}
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s constraint must be an object" % [filename, proposal_id])
		return {}

	var field = raw.get("field", "")
	if typeof(field) != TYPE_STRING or not K.CONSTRAINT_FIELDS.has(field):
		errors.append("%s: %s constraint.field '%s' is not a recognised field" % [filename, proposal_id, str(field)])
		return {}

	var op = raw.get("op", "")
	if typeof(op) != TYPE_STRING or not K.CONSTRAINT_OPS.has(op):
		errors.append("%s: %s constraint.op '%s' is not a recognised operator" % [filename, proposal_id, str(op)])
		return {}

	if not raw.has("value") or not (typeof(raw["value"]) == TYPE_INT or typeof(raw["value"]) == TYPE_FLOAT):
		errors.append("%s: %s constraint.value is missing or not numeric" % [filename, proposal_id])
		return {}

	var tolerance := float(raw.get("tolerance", 0.0))
	if tolerance < K.MIN_CONSTRAINT_TOLERANCE:
		errors.append("%s: %s constraint.tolerance %.3f is below the minimum of %.2f" % [
			filename, proposal_id, tolerance, K.MIN_CONSTRAINT_TOLERANCE,
		])
		return {}

	var severity := float(raw.get("severity", 1.0))
	if severity <= 0.0 or severity > K.MAX_RULE_SEVERITY:
		errors.append("%s: %s constraint.severity %.3f is outside (0, %.2f]" % [
			filename, proposal_id, severity, K.MAX_RULE_SEVERITY,
		])
		return {}

	return {
		"field": field,
		"op": op,
		"value": float(raw["value"]),
		"tolerance": tolerance,
		"severity": severity,
	}


## The bloc acting as one against a non-member. Severity is capped below
## coercion_constants.MAX_MEASURE_SEVERITY deliberately -- see bloc_constants.gd.
static func _extract_external_measure(d: Dictionary, proposal_id: String, filename: String, errors: Array[String]) -> Dictionary:
	var raw = d.get("external_measure", null)
	if raw == null:
		return {}
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s external_measure must be an object" % [filename, proposal_id])
		return {}

	var kind = raw.get("kind", "")
	if typeof(kind) != TYPE_STRING or not CK.MEASURE_KINDS.has(kind):
		errors.append("%s: %s external_measure.kind '%s' is not a recognised measure kind" % [filename, proposal_id, str(kind)])
		return {}

	var severity := float(raw.get("severity", 0.0))
	if severity <= 0.0 or severity > K.MAX_PROPOSAL_EXTERNAL_SEVERITY:
		errors.append("%s: %s external_measure.severity %.3f is outside (0, %.2f]" % [
			filename, proposal_id, severity, K.MAX_PROPOSAL_EXTERNAL_SEVERITY,
		])
		return {}

	return {"kind": kind, "severity": severity}
