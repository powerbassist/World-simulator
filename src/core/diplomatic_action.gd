class_name DiplomaticAction
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/diplomatic-actions/*.json file. See docs/diplomacy-model.md and
## docs/data-architecture.md.
##
## Mirrors src/core/law.gd's from_dict shape: a plain data object built once at
## load time, validated loudly, never mutated afterward.
##
## Borrowed from the law template: preconditions, cooldown, effects. Deliberately
## NOT borrowed: `position`, `majority`, `once`. A diplomatic action is an
## executive act with no assembly division, so there is no vote to resolve and
## nothing for an ideology position to score -- giving it either would be a
## parallel vocabulary for a mechanism that does not exist here. `once` is
## absent because the cooldown is keyed per (action, target): a state visit to
## Germany and a state visit to Italy are separate uses of the same verb, and
## "once, ever, against anybody" is not a shape any action in this block wants.

const DK = preload("res://src/sim/diplomacy_constants.gd")


var id: String = ""
var action_name: String = ""
var summary: String = ""

## Months this action must wait before it can be used against THE SAME target
## again. Zero is legal and means no cooldown.
var cooldown_months: int = 0

## Array of {"field": String, "op": String, "value": float}, each field checked
## against diplomacy_constants.PRECONDITION_FIELDS at load time. "relations" is
## evaluated against the target of the proposed action; every other field is the
## acting nation's own state.
var preconditions: Array = []

## {"relations": float, "bloc_offset": {...}} -- `relations` is required and
## non-zero, `bloc_offset` optional.
var effects: Dictionary = {}


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

	a.cooldown_months = int(d.get("cooldown_months", 0))
	if a.cooldown_months < 0:
		errors.append("%s: %s cooldown_months must be >= 0" % [filename, a.id])

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
		if typeof(field) != TYPE_STRING or not DK.PRECONDITION_FIELDS.has(field):
			errors.append("%s: %s preconditions[%d].field '%s' is not a recognised field" % [filename, action_id, i, str(field)])
			continue

		var op = entry.get("op", "")
		if typeof(op) != TYPE_STRING or not DK.PRECONDITION_OPS.has(op):
			errors.append("%s: %s preconditions[%d].op '%s' is not a recognised operator" % [filename, action_id, i, str(op)])
			continue

		if not entry.has("value") or not (typeof(entry["value"]) == TYPE_INT or typeof(entry["value"]) == TYPE_FLOAT):
			errors.append("%s: %s preconditions[%d].value is missing or not numeric" % [filename, action_id, i])
			continue

		out.append({"field": field, "op": op, "value": float(entry["value"])})

	return out


## `relations` is REQUIRED and must be non-zero. An action that moves no pair is
## a domestic gesture wearing a diplomacy label -- the same class of quiet lie
## src/core/scenario.gd refuses for an overrides block that overrides nothing.
## `bloc_offset` is optional: an action with no domestic price is legitimate,
## and the measurement in docs/diplomacy-model.md is about whether a price that
## IS authored is legible, not about whether one must exist.
static func _extract_effects(d: Dictionary, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	var raw = d.get("effects", {})
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects must be an object" % [filename, action_id])
		return {}

	var out := {}

	if not raw.has("relations"):
		errors.append("%s: %s effects.relations is required -- an action that moves no pair is not a diplomatic action" % [filename, action_id])
	elif not (typeof(raw["relations"]) == TYPE_INT or typeof(raw["relations"]) == TYPE_FLOAT):
		errors.append("%s: %s effects.relations must be numeric" % [filename, action_id])
	else:
		var delta := float(raw["relations"])
		if is_zero_approx(delta):
			errors.append("%s: %s effects.relations is zero -- an action that moves no pair is not a diplomatic action" % [filename, action_id])
		if absf(delta) > DK.MAX_ACTION_RELATIONS_DELTA:
			errors.append("%s: %s effects.relations = %s exceeds MAX_ACTION_RELATIONS_DELTA (%s)" % [
				filename, action_id, str(delta), str(DK.MAX_ACTION_RELATIONS_DELTA)
			])
		out["relations"] = delta

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_bloc_offset(raw["bloc_offset"], action_id, filename, errors, bloc_keys)

	for key in raw.keys():
		if key != "relations" and key != "bloc_offset":
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, action_id, key])

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
