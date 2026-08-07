class_name CompanyAction
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/company-actions/*.json file. See docs/companies-model.md.
##
## THE FIFTH EFFECT CHANNEL, and the first one pointed at something that is not a
## nation. `effects.company` names an op and, for the two setting ops, that op's
## one dial; src/sim/companies.gd dispatches it against one firm of the acting
## nation's own register.
##
## Mirrors src/core/diplomatic_action.gd, which is the point: V1.3a's shape served
## a, b, c, f and g without a new content type, and V1.4a, b and c are meant to
## share this one the same way. What is NOT borrowed is as deliberate as what is:
##
##   `effects.relations` -- required there, absent here. A subsidy is a domestic
##     act with no pair to move. Borrowing it would give the block a foreign-policy
##     vocabulary for a mechanism that has no counterparty.
##   `cooldown_months` -- absent. A subsidy is standing STATE rather than an event,
##     so `subsidy_active` gates it directly and a cooldown register beside that
##     would be two gates on one fact.
##   `position` / `majority` / `once` -- absent, for diplomatic_action.gd's own
##     reason: this is an executive act and there is no assembly division to score.
##     V1.4b's regulation IS a law and gets all three by being one.

const K = preload("res://src/sim/companies_constants.gd")
## Borrowed rather than re-declared. The bound is on how hard ONE AUTHORED ACTION
## may hit a bloc's approval, which is a property of the opinion model and not of
## diplomacy; a second number for it would be two answers to one question, which is
## what the symmetric pair key exists to prevent one register away.
const DK = preload("res://src/sim/diplomacy_constants.gd")


var id: String = ""
var action_name: String = ""
var summary: String = ""

## Array of {"field": String, "op": String, "value": float}, each field checked
## against companies_constants.PRECONDITION_FIELDS at load time.
var preconditions: Array = []

## Two channels: `company` (required) and `bloc_offset` (optional). The second is
## optional for diplomatic_action.gd's reason -- whether an authored price is
## legible is a measurement, and whether one must exist is not.
var effects: Dictionary = {}

const EFFECT_CHANNELS := ["company", "bloc_offset"]


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

	if not raw.has("company"):
		errors.append("%s: %s effects.company is required -- an action that touches no firm is not a company action" % [filename, action_id])
	else:
		out["company"] = _extract_company(raw["company"], action_id, filename, errors)

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_bloc_offset(raw["bloc_offset"], action_id, filename, errors, bloc_keys)

	for key in raw.keys():
		if not EFFECT_CHANNELS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, action_id, key])

	return out


## An op names EXACTLY ONE DIAL or names none, and companies_constants.
## COMPANY_OP_TERM is the table that says which. `withdraw` and `privatise` carry
## no terms: they name nothing and set nothing, they clear. Terms on either would
## be an author believing they had written something read by nobody -- the rule a
## measure's "lift" and an agreement's "exit" already get.
##
## One dial per op, and the refusal at the bottom is what keeps it that way. An
## authored per-action cost, share-shift rate, jobs multiplier or purchase price
## would each be a second number describing one strength -- the redundancy
## tools/coercion_probe.gd found between an authored tariff rate and a measure's
## severity, and deleted rather than documented. V1.4c's price is DERIVED from the
## firm's own output for exactly that reason: an authored one would let a content
## file disagree with the register about what a firm is worth.
static func _extract_company(raw, action_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.company must be an object" % [filename, action_id])
		return {}

	var op = raw.get("op", "")
	if typeof(op) != TYPE_STRING or not K.COMPANY_OPS.has(op):
		errors.append("%s: %s effects.company.op '%s' is not a recognised op (%s)" % [
			filename, action_id, str(op), str(K.COMPANY_OPS)
		])
		return {}

	var out := {"op": op}
	var term := String(K.COMPANY_OP_TERM.get(op, ""))

	if term == "":
		for key in raw.keys():
			if key != "op":
				errors.append("%s: %s effects.company.%s is set on a \"%s\" -- it clears the firm's state and reads no terms" % [
					filename, action_id, key, op
				])
		return out

	var ceiling: float = K.MAX_SUBSIDY_INTENSITY if term == "intensity" else K.MAX_STAKE
	var value := float(raw.get(term, 0.0))
	if value <= 0.0:
		errors.append("%s: %s effects.company.%s must be > 0 -- a \"%s\" that moves nothing is not one" % [
			filename, action_id, term, op
		])
	elif value > ceiling:
		errors.append("%s: %s effects.company.%s = %s exceeds its ceiling (%s)" % [
			filename, action_id, term, str(value), str(ceiling)
		])
	out[term] = value

	for key in raw.keys():
		if key != "op" and key != term:
			errors.append("%s: %s effects.company.%s is not a recognised term on a \"%s\" -- %s is its only dial, and a cost or a rate beside it is one strength written twice" % [
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
