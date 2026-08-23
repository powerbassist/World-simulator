class_name InvestmentAction
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/investment-actions/*.json file. See docs/sector-model.md.
##
## THE SEVENTH EFFECT CHANNEL. `effects.investment` names an op, the SECTOR it is
## pointed at, and, for the setting op, that op's one dial; src/sim/investment.gd
## dispatches it against the acting nation's own register.
##
## Mirrors src/core/company_action.gd, which mirrors src/core/diplomatic_action.gd
## -- the third directory on one shape rather than a third kind of content, the way
## V1.3a's directory served five sessions and V1.4a's served three.
##
## THE SECTOR IS AUTHORED RATHER THAN CHOSEN BY THE PLAYER AT THE BUTTON, and that
## is this session's one content call. A company action takes its target as a
## parameter because a firm's differentiator -- its headcount and its share -- is
## already per-firm content, so nine firms behave nine ways under one action. Three
## sectors under one action would share a single authored `bloc_offset`, making
## WHICH SECTOR an economic decision and a politically identical one; that is
## docs/companies-model.md's own finding (a layer is more than a sector lever
## exactly to the extent its members are authored differently) applied one level up.
##
## Naming a sector in content is precedented and is not engine-decision.md Rule 1's
## `if nation_id == "FRA"`: src/core/law.gd's _extract_company() already has a
## `business` law name the sector it burdens. Rule 1 forbids a branch on an id in
## CODE, not a content file naming one of three model constants.
##
## What is NOT borrowed is as deliberate as what is:
##
##   `effects.relations` -- a domestic act has no pair to move.
##   `cooldown_months` -- absent. A programme is standing STATE, so
##     `investment_active` gates it and a cooldown beside that is two gates on one
##     fact. company_action.gd's reason exactly.
##   `position` / `majority` / `once` -- absent. This is an executive verb and
##     there is no assembly division to score. A sector lever that WERE a law would
##     be V1.4b's regulation with a plus sign, which is why docs/tiers/v1.md
##     section 6's decomposition puts (e) under V1.3a's rule rather than V1.4b's.

const K = preload("res://src/sim/investment_constants.gd")
const EK = preload("res://src/sim/economy_constants.gd")
## Borrowed rather than re-declared, for company_action.gd's reason: the bound on
## how hard ONE authored action may hit a bloc's approval is a property of the
## opinion model, and a second number for it would be two answers to one question.
const DK = preload("res://src/sim/diplomacy_constants.gd")


var id: String = ""
var action_name: String = ""
var summary: String = ""

## Array of {"field": String, "op": String, "value": float}, each field checked
## against investment_constants.PRECONDITION_FIELDS at load time.
var preconditions: Array = []

## Two channels: `investment` (required) and `bloc_offset` (optional). The second
## is optional for diplomatic_action.gd's reason -- whether an authored price is
## legible is a measurement, and whether one must exist is not.
var effects: Dictionary = {}

const EFFECT_CHANNELS := ["investment", "bloc_offset"]


static func from_dict(d: Dictionary, filename: String, errors: Array[String], bloc_keys: Array):
	var a := new()

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: missing or invalid string field 'id'" % filename)
	else:
		a.id = d["id"]

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, a.id])
	else:
		a.action_name = d["name"]

	a.summary = d.get("summary", "")
	if typeof(a.summary) != TYPE_STRING:
		errors.append("%s: %s summary must be a string" % [filename, a.id])
		a.summary = ""

	a.preconditions = _extract_preconditions(d, a.id, filename, errors)
	a.effects = _extract_effects(d, a.id, filename, errors, bloc_keys)

	return a


static func _extract_preconditions(d: Dictionary, action_id: String, filename: String, errors: Array[String]) -> Array:
	var raw = d.get("preconditions", [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s: %s preconditions must be an array" % [filename, action_id])
		return []

	var out: Array = []
	for i in raw.size():
		var entry = raw[i]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s: %s preconditions[%d] is not an object" % [filename, action_id, i])
			continue

		var field = entry.get("field", "")
		if typeof(field) != TYPE_STRING or not K.PRECONDITION_FIELDS.has(field):
			errors.append("%s: %s preconditions[%d].field '%s' is not a recognised field" % [filename, action_id, i, str(field)])
			continue

		var op = entry.get("op", "")
		if typeof(op) != TYPE_STRING or not K.PRECONDITION_OPS.has(op):
			errors.append("%s: %s preconditions[%d].op '%s' is not a recognised operator" % [filename, action_id, i, str(op)])
			continue

		if not entry.has("value") or not (typeof(entry["value"]) == TYPE_INT or typeof(entry["value"]) == TYPE_FLOAT):
			errors.append("%s: %s preconditions[%d].value is missing or not numeric" % [filename, action_id, i])
			continue

		out.append({"field": field, "op": op, "value": float(entry["value"])})

	return out


static func _extract_effects(d: Dictionary, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	var raw = d.get("effects", {})
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects must be an object" % [filename, action_id])
		return {}

	var out := {}

	if not raw.has("investment"):
		errors.append("%s: %s effects.investment is required -- an action that points at no sector is not an investment action" % [filename, action_id])
	else:
		out["investment"] = _extract_investment(raw["investment"], action_id, filename, errors)

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_bloc_offset(raw["bloc_offset"], action_id, filename, errors, bloc_keys)

	for key in raw.keys():
		if not EFFECT_CHANNELS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, action_id, key])

	return out


## `sector` is required for EVERY op, including the one that clears -- unlike the
## dial, which only the setting op carries. A withdrawal still has to say what it
## is withdrawing from.
##
## One dial per op, and the refusal at the bottom is what keeps it that way. An
## authored cost, build rate or trend coefficient beside the intensity would each
## be a second number describing one strength, which is the redundancy
## tools/coercion_probe.gd found between an authored tariff rate and a measure's
## severity and DELETED rather than documented.
static func _extract_investment(raw, action_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.investment must be an object" % [filename, action_id])
		return {}

	var op = raw.get("op", "")
	if typeof(op) != TYPE_STRING or not K.INVESTMENT_OPS.has(op):
		errors.append("%s: %s effects.investment.op '%s' is not a recognised op (%s)" % [
			filename, action_id, str(op), str(K.INVESTMENT_OPS)
		])
		return {}

	var sector = raw.get("sector", "")
	if typeof(sector) != TYPE_STRING or not EK.SECTOR_TREND.has(sector):
		errors.append("%s: %s effects.investment.sector '%s' is not one of the three sectors (%s)" % [
			filename, action_id, str(sector), str(EK.SECTOR_TREND.keys())
		])
		return {}

	var out := {"op": op, "sector": sector}
	var term := String(K.INVESTMENT_OP_TERM.get(op, ""))

	if term == "":
		for key in raw.keys():
			if key != "op" and key != "sector":
				errors.append("%s: %s effects.investment.%s is set on a \"%s\" -- it clears the sector's programme and reads no terms" % [
					filename, action_id, key, op
				])
		return out

	var value := float(raw.get(term, 0.0))
	if value <= 0.0:
		errors.append("%s: %s effects.investment.%s must be > 0 -- an \"%s\" that moves nothing is not one" % [
			filename, action_id, term, op
		])
	elif value > K.MAX_INVESTMENT_INTENSITY:
		errors.append("%s: %s effects.investment.%s = %s exceeds its ceiling (%s)" % [
			filename, action_id, term, str(value), str(K.MAX_INVESTMENT_INTENSITY)
		])
	out[term] = value

	for key in raw.keys():
		if key != "op" and key != "sector" and key != term:
			errors.append("%s: %s effects.investment.%s is not a recognised term on an \"%s\" -- %s is its only dial, and a cost or a rate beside it is one strength written twice" % [
				filename, action_id, key, op, term
			])

	return out


static func _extract_bloc_offset(raw, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.bloc_offset must be an object" % [filename, action_id])
		return {}
	if raw.is_empty():
		errors.append("%s: %s effects.bloc_offset is present but empty" % [filename, action_id])

	var out := {}
	for key in raw.keys():
		if not bloc_keys.has(key):
			errors.append("%s: %s effects.bloc_offset.%s is not a recognised bloc" % [filename, action_id, key])
			continue
		if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
			errors.append("%s: %s effects.bloc_offset.%s must be numeric" % [filename, action_id, key])
			continue
		var value := float(raw[key])
		if absf(value) > DK.MAX_ACTION_BLOC_OFFSET:
			errors.append("%s: %s effects.bloc_offset.%s = %s exceeds MAX_ACTION_BLOC_OFFSET (%s)" % [
				filename, action_id, key, str(value), str(DK.MAX_ACTION_BLOC_OFFSET)
			])
		out[key] = value
	return out
