class_name EnergyAction
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/energy-actions/*.json file. See docs/energy-model.md.
##
## THE NINTH EFFECT CHANNEL. `effects.energy` names an op and, for `order`, the
## SOURCE it is pointed at; src/sim/energy.gd dispatches it against the acting
## nation's own register. The fifth directory on data/diplomatic-actions/'s shape
## rather than a fifth kind of content.
##
## THE REGION IS NOT AUTHORED AND CANNOT BE. It is the PLAYER's, passed to
## execute() as an argument -- V2.6b2's rule, where the campaign meeting's region is
## the player's and never Siting.site()'s, and the one proof the two sited halves
## were never one shape. That is also the whole difference between this file and
## src/core/project_action.gd, whose place is authored in data/nations/.
##
## `decommission` NAMES A PLANT ID AT EXECUTE TIME, not in the content: unlike a
## project, a nation may hold several stations of one kind, so an act that says only
## "shut a reactor" has not said which. The op is authored; the target is chosen.

const K = preload("res://src/sim/energy_constants.gd")
## Borrowed rather than re-declared, for project_action.gd's reason: the bound on
## how hard ONE authored action may hit a bloc's approval is a property of the
## opinion model, and a second number for it would be two answers to one question.
const DK = preload("res://src/sim/diplomacy_constants.gd")

var id: String = ""
var action_name: String = ""
var summary: String = ""

## Array of {"field": String, "op": String, "value": float}, each field checked
## against energy_constants.PRECONDITION_FIELDS at load time.
var preconditions: Array = []

## Two channels: `energy` (required) and `bloc_offset` (optional), project_action.gd's
## pair with the op swapped -- whether an authored price is legible is a measurement,
## and whether one must exist is not.
var effects: Dictionary = {}

const EFFECT_CHANNELS := ["energy", "bloc_offset"]
const ENERGY_OPS := ["order", "decommission"]


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


static func energy_op(a) -> String:
	return String(a.effects.get("energy", {}).get("op", ""))


static func source_id_of(a) -> String:
	return String(a.effects.get("energy", {}).get("source_id", ""))


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

		var cond_op = entry.get("op", "")
		if typeof(cond_op) != TYPE_STRING or not K.PRECONDITION_OPS.has(cond_op):
			errors.append("%s: %s preconditions[%d].op '%s' is not a recognised operator" % [filename, action_id, i, str(cond_op)])
			continue

		if not entry.has("value") or not (typeof(entry["value"]) == TYPE_INT or typeof(entry["value"]) == TYPE_FLOAT):
			errors.append("%s: %s preconditions[%d].value is missing or not numeric" % [filename, action_id, i])
			continue

		out.append({"field": field, "op": cond_op, "value": float(entry["value"])})

	return out


static func _extract_effects(d: Dictionary, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	var raw = d.get("effects", {})
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects must be an object" % [filename, action_id])
		return {}

	var out := {}

	if not raw.has("energy"):
		errors.append("%s: %s effects.energy is required -- an action that names no op is not an energy action" % [filename, action_id])
	else:
		out["energy"] = _extract_energy(raw["energy"], action_id, filename, errors)

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_bloc_offset(raw["bloc_offset"], action_id, filename, errors, bloc_keys)

	for key in raw.keys():
		if not EFFECT_CHANNELS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, action_id, key])

	return out


## `order` names the source it builds and nothing else; `decommission` names nothing
## at all, because the plant it closes is chosen from the register at execute time.
static func _extract_energy(raw, action_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.energy must be an object" % [filename, action_id])
		return {}

	var energy_op = raw.get("op", "")
	if typeof(energy_op) != TYPE_STRING or not ENERGY_OPS.has(energy_op):
		errors.append("%s: %s effects.energy.op '%s' is not a recognised op (%s)" % [
			filename, action_id, str(energy_op), str(ENERGY_OPS)
		])
		return {}

	var out := {"op": energy_op}

	if energy_op == "order":
		var sid = raw.get("source_id", "")
		if typeof(sid) != TYPE_STRING or sid == "":
			errors.append("%s: %s effects.energy.source_id is required on an 'order' -- a build that names no technology has not said what it builds" % [
				filename, action_id
			])
		else:
			out["source_id"] = sid
	elif raw.has("source_id"):
		errors.append("%s: %s effects.energy.source_id is set on a 'decommission' -- the plant closed is a register entry, not a technology" % [
			filename, action_id
		])

	for key in raw.keys():
		if key != "op" and key != "source_id":
			errors.append("%s: %s effects.energy.%s is not a recognised term on a '%s'" % [
				filename, action_id, key, energy_op
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
