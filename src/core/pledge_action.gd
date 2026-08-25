class_name PledgeAction
extends RefCounted

## Typed, validated in-memory representation of one entry in a data/pledges/*.json
## file. See docs/pledge-model.md.
##
## THE TENTH EFFECT CHANNEL. `effects.pledge` names a promise, the {field, op, value}
## triple that decides whether it is being kept, and what standing broken takes off
## each named bloc every month. src/sim/pledges.gd judges it against the acting
## nation's own state.
##
## Mirrors src/core/campaign_action.gd, which mirrors src/core/project_action.gd,
## which mirrors src/core/investment_action.gd, which mirrors src/core/company_action.gd,
## which mirrors src/core/diplomatic_action.gd -- the SIXTH directory on one shape
## rather than a sixth kind of content.
##
## *** IT CARRIES NO `op` ON THE CHANNEL AND EVERY PREVIOUS ONE DOES, and the absence
## is the model rather than an omission. *** Five directories ship a start and a stop
## because an obligation only the clock can close is a permanent monotone charge --
## docs/defence-model.md's rule. A pledge charges only while it stands BROKEN, so it
## stops the month the player comes back into compliance: the off switch already
## exists and it is called governing. See pledges_constants.PLEDGE_TERMS.
##
## *** THE `op` THAT IS HERE IS THE PROMISE'S OWN, and it is a different thing from
## the five channels' dispatch op. *** `{"field": "unemployment_pct", "op": "<=",
## "value": 7.0}` is one sentence, and splitting the comparator out of it would be a
## promise that did not say which way it pointed.
##
## What is NOT borrowed is as deliberate as what is:
##
##   `effects.relations` -- a domestic act has no pair to move.
##   `cooldown_months` -- absent. The window IS the cooldown: a promise can only be
##     made inside a run-up and is judged over the term that run-up is for, so
##     `pledge_count` and the clock between them already bound how many exist.
##   `position` / `majority` / `once` -- absent. This is an executive verb and there
##     is no assembly division to score.

const K = preload("res://src/sim/pledges_constants.gd")
## Borrowed rather than re-declared, for campaign_action.gd's and project_action.gd's
## reason: the bound on how hard ONE authored action may hit a bloc's approval is a
## property of the opinion model, and a second number for it would be two answers to
## one question. Here it bounds the REWARD -- what a bloc pays you for making the
## promise, at the moment you make it.
const DK = preload("res://src/sim/diplomacy_constants.gd")


var id: String = ""
var action_name: String = ""
var summary: String = ""

## Array of {"field": String, "op": String, "value": float}, each field checked
## against pledges_constants.PRECONDITION_FIELDS at load time.
var preconditions: Array = []

## Two channels: `pledge` (required) and `bloc_offset` (optional). The second is
## optional for diplomatic_action.gd's reason -- whether an authored price is legible
## is a measurement, and whether one must exist is not. Here it is the promise's
## UPFRONT REWARD, and a promise nobody wanted to hear is a legal thing to author.
var effects: Dictionary = {}

const EFFECT_CHANNELS := ["pledge", "bloc_offset"]


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


static func pledge_id(a) -> String:
	return String(a.effects.get("pledge", {}).get("pledge_id", ""))


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

	if not raw.has("pledge"):
		errors.append("%s: %s effects.pledge is required -- an action that promises nothing is not a pledge" % [filename, action_id])
	else:
		out["pledge"] = _extract_pledge(raw["pledge"], action_id, filename, errors, bloc_keys)

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_bloc_offset(raw["bloc_offset"], action_id, filename, errors, bloc_keys)

	for key in raw.keys():
		if not EFFECT_CHANNELS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, action_id, key])

	return out


static func _extract_pledge(raw, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.pledge must be an object" % [filename, action_id])
		return {}

	var out := {}

	var pid = raw.get("pledge_id", "")
	if typeof(pid) != TYPE_STRING or pid == "":
		errors.append("%s: %s effects.pledge.pledge_id is missing -- the register is keyed on it" % [filename, action_id])
		return {}
	out["pledge_id"] = pid

	# `pledge_name` is a DISPLAY field and not a term about the promise, for the
	# reason project_action.gd gives about `project_name` and campaign_action.gd about
	# `effort_name`: an action name is the imperative the button carries, and every
	# other surface -- the diary of what you owe, the ledger, the result screen --
	# needs the noun.
	var display = raw.get("pledge_name", "")
	if typeof(display) != TYPE_STRING or display == "":
		errors.append("%s: %s effects.pledge.pledge_name is missing -- the action name is an imperative and the ledger needs the noun" % [
			filename, action_id
		])
	else:
		out["pledge_name"] = display

	var field = raw.get("field", "")
	if typeof(field) != TYPE_STRING or not K.PLEDGE_FIELDS.has(field):
		errors.append("%s: %s effects.pledge.field '%s' is not something this game lets a president promise (%s)" % [
			filename, action_id, str(field), str(K.PLEDGE_FIELDS)
		])
	else:
		out["field"] = field

	var promise_op = raw.get("op", "")
	if typeof(promise_op) != TYPE_STRING or not K.PLEDGE_OPS.has(promise_op):
		errors.append("%s: %s effects.pledge.op '%s' is not a recognised comparator -- a promise is a BOUND, so only %s (see pledges_constants.PLEDGE_OPS)" % [
			filename, action_id, str(promise_op), str(K.PLEDGE_OPS)
		])
	else:
		out["op"] = promise_op

	if not raw.has("value") or not (typeof(raw["value"]) == TYPE_INT or typeof(raw["value"]) == TYPE_FLOAT):
		errors.append("%s: %s effects.pledge.value is missing or not numeric" % [filename, action_id])
	else:
		out["value"] = float(raw["value"])

	if not raw.has("breach_offset"):
		errors.append("%s: %s effects.pledge.breach_offset is required -- a promise nothing happens for breaking is not one" % [
			filename, action_id
		])
	else:
		out["breach_offset"] = _extract_breach_offset(raw["breach_offset"], action_id, filename, errors, bloc_keys)

	for key in raw.keys():
		if not K.PLEDGE_TERMS.has(key):
			errors.append("%s: %s effects.pledge.%s is not a recognised term (%s)" % [
				filename, action_id, key, str(K.PLEDGE_TERMS)
			])

	return out


## bloc -> what standing broken takes off that bloc's approval target each month,
## AUTHORED AS A MAGNITUDE. src/sim/pledges.gd subtracts it, so a negative here would
## be a promise that pays for being broken -- refused rather than clamped, because
## content that loads at a value the model would flip is content that does not say
## what it does.
static func _extract_breach_offset(raw, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.pledge.breach_offset must be an object" % [filename, action_id])
		return {}
	if raw.is_empty():
		errors.append("%s: %s effects.pledge.breach_offset is present but empty -- a promise nobody would punish is not one" % [
			filename, action_id
		])

	var out := {}
	for key in raw.keys():
		if not bloc_keys.has(key):
			errors.append("%s: %s effects.pledge.breach_offset.%s is not a recognised bloc" % [filename, action_id, key])
			continue
		if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
			errors.append("%s: %s effects.pledge.breach_offset.%s must be numeric" % [filename, action_id, key])
			continue
		var value := float(raw[key])
		if value < 0.0:
			errors.append("%s: %s effects.pledge.breach_offset.%s = %s is negative -- it is authored as a MAGNITUDE and charged as a subtraction, so a negative is a promise that pays for being broken" % [
				filename, action_id, key, str(value)
			])
			continue
		if value > K.MAX_BREACH_OFFSET_PER_MONTH:
			errors.append("%s: %s effects.pledge.breach_offset.%s = %s exceeds MAX_BREACH_OFFSET_PER_MONTH (%s)" % [
				filename, action_id, key, str(value), str(K.MAX_BREACH_OFFSET_PER_MONTH)
			])
		out[key] = value
	return out


## The UPFRONT reward: what each bloc gives you for making the promise, applied once
## at the moment it is made. Signed, unlike breach_offset, because a promise the
## business bloc likes is a promise the workers may resent hearing -- one act, two
## signs, which is campaign_action.gd's own argument about mobilisation.
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
