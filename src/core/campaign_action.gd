class_name CampaignAction
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/campaign-actions/*.json file. See docs/campaign-model.md.
##
## THE NINTH EFFECT CHANNEL. `effects.campaign` names an op, the EFFORT it is pointed
## at, and, for the starting op, that effort's two authored facts; src/sim/campaign.gd
## dispatches it against the acting nation's own register.
##
## Mirrors src/core/project_action.gd, which mirrors src/core/investment_action.gd,
## which mirrors src/core/company_action.gd, which mirrors src/core/diplomatic_action.gd
## -- the FIFTH directory on one shape rather than a fifth kind of content.
##
## THE EFFORT ID IS AUTHORED ON EVERY OP, INCLUDING THE ONE THAT STOPS, for
## project_action.gd's reason: an act that says only "stop" has not said what it is
## stopping. The id is the register key, so a start and its stop name the same string.
##
## *** `mobilisation` IS A DICTIONARY TERM WHERE EVERY PREVIOUS CHANNEL'S TERMS ARE
## SCALARS, AND THAT IS WHAT THE SESSION IS ABOUT. *** An effort names WHO it reaches,
## not how hard it pushes in general: the whole decision a campaign offers is which
## part of the electorate to spend the run-up on, and a scalar strength would have
## nowhere to put it. It is validated against the same BLOC_KEYS `bloc_offset` uses,
## and the two are not a double count -- one moves who turns out and the other moves
## how they feel, which are different landing sites in different units. See
## docs/campaign-model.md.
##
## What is NOT borrowed is as deliberate as what is:
##
##   `effects.relations` -- a domestic act has no pair to move.
##   `cooldown_months` -- absent. The window IS the cooldown: everything clears when
##     the run-up ends, so an effort runs at most once per election by construction.
##   `position` / `majority` / `once` -- absent. This is an executive verb and there is
##     no assembly division to score.

const K = preload("res://src/sim/campaign_constants.gd")
## Borrowed rather than re-declared, for project_action.gd's reason: the bound on how
## hard ONE authored action may hit a bloc's approval is a property of the opinion
## model, and a second number for it would be two answers to one question.
const DK = preload("res://src/sim/diplomacy_constants.gd")


var id: String = ""
var action_name: String = ""
var summary: String = ""

## Array of {"field": String, "op": String, "value": float}, each field checked
## against campaign_constants.PRECONDITION_FIELDS at load time.
var preconditions: Array = []

## Two channels: `campaign` (required) and `bloc_offset` (optional). The second is
## optional for diplomatic_action.gd's reason -- whether an authored price is legible
## is a measurement, and whether one must exist is not.
var effects: Dictionary = {}

const EFFECT_CHANNELS := ["campaign", "bloc_offset"]


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


static func effort_id(a) -> String:
	return String(a.effects.get("campaign", {}).get("effort_id", ""))


static func op_of(a) -> String:
	return String(a.effects.get("campaign", {}).get("op", ""))


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

	if not raw.has("campaign"):
		errors.append("%s: %s effects.campaign is required -- an action that names no effort is not a campaign action" % [filename, action_id])
	else:
		out["campaign"] = _extract_campaign(raw["campaign"], action_id, filename, errors, bloc_keys)

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_bloc_offset(raw["bloc_offset"], action_id, filename, errors, bloc_keys)

	for key in raw.keys():
		if not EFFECT_CHANNELS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, action_id, key])

	return out


## Both `start` terms are range-checked here rather than clamped later, because an
## effort that loads at a value the model would clamp is content that does not say
## what it does. project_action.gd's treatment of its three.
static func _extract_campaign(raw, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.campaign must be an object" % [filename, action_id])
		return {}

	var campaign_op = raw.get("op", "")
	if typeof(campaign_op) != TYPE_STRING or not K.CAMPAIGN_OPS.has(campaign_op):
		errors.append("%s: %s effects.campaign.op '%s' is not a recognised op (%s)" % [
			filename, action_id, str(campaign_op), str(K.CAMPAIGN_OPS)
		])
		return {}

	var eid = raw.get("effort_id", "")
	if typeof(eid) != TYPE_STRING or eid == "":
		errors.append("%s: %s effects.campaign.effort_id is missing -- every op names the effort it points at, including the one that stops" % [
			filename, action_id
		])
		return {}

	var out := {"op": campaign_op, "effort_id": eid}
	var terms: Array = K.CAMPAIGN_OP_TERMS.get(campaign_op, [])

	if terms.is_empty():
		for key in raw.keys():
			if key != "op" and key != "effort_id":
				errors.append("%s: %s effects.campaign.%s is set on a '%s' -- it ends an effort already in the field and reads no terms" % [
					filename, action_id, key, campaign_op
				])
		return out

	# `effort_name` is a DISPLAY field and not a third term, for the reason
	# project_action.gd gives about `project_name`: an action name is the imperative the
	# button carries and the ledger needs the noun. The term list is about QUANTITIES,
	# and a name is not a quantity.
	var display = raw.get("effort_name", "")
	if typeof(display) != TYPE_STRING or display == "":
		errors.append("%s: %s effects.campaign.effort_name is missing -- the action name is an imperative and the ledger needs the noun" % [
			filename, action_id
		])
	else:
		out["effort_name"] = display

	if not raw.has("cost_pct_gdp"):
		errors.append("%s: %s effects.campaign.cost_pct_gdp is required on a '%s'" % [filename, action_id, campaign_op])
	elif not (typeof(raw["cost_pct_gdp"]) == TYPE_INT or typeof(raw["cost_pct_gdp"]) == TYPE_FLOAT):
		errors.append("%s: %s effects.campaign.cost_pct_gdp must be numeric" % [filename, action_id])
	else:
		var cost := float(raw["cost_pct_gdp"])
		if cost <= 0.0:
			errors.append("%s: %s effects.campaign.cost_pct_gdp = %s is at or below its floor -- an effort that costs nothing is not one, and a free one would be strictly dominant" % [
				filename, action_id, str(cost)
			])
		elif cost > K.MAX_CAMPAIGN_COST_PCT_GDP:
			errors.append("%s: %s effects.campaign.cost_pct_gdp = %s exceeds its ceiling (%s)" % [
				filename, action_id, str(cost), str(K.MAX_CAMPAIGN_COST_PCT_GDP)
			])
		out["cost_pct_gdp"] = cost

	if not raw.has("mobilisation"):
		errors.append("%s: %s effects.campaign.mobilisation is required on a '%s' -- an effort that names no audience has not said who it reaches" % [
			filename, action_id, campaign_op
		])
	else:
		out["mobilisation"] = _extract_mobilisation(raw["mobilisation"], action_id, filename, errors, bloc_keys)

	for key in raw.keys():
		if key != "op" and key != "effort_id" and key != "effort_name" and not terms.has(key):
			errors.append("%s: %s effects.campaign.%s is not a recognised term on a '%s' (%s)" % [
				filename, action_id, key, campaign_op, str(terms)
			])

	return out


## bloc -> log-odds shift per month, signed. An effort may depress a bloc as well as
## raise one, which is what makes negative campaigning expressible without a second
## op: a broadcast that fires up your own base and disgusts everybody else is ONE act
## with two signs, not two acts.
static func _extract_mobilisation(raw, action_id: String, filename: String, errors: Array[String], bloc_keys: Array) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.campaign.mobilisation must be an object" % [filename, action_id])
		return {}
	if raw.is_empty():
		errors.append("%s: %s effects.campaign.mobilisation is present but empty" % [filename, action_id])

	var out := {}
	for key in raw.keys():
		if not bloc_keys.has(key):
			errors.append("%s: %s effects.campaign.mobilisation.%s is not a recognised bloc" % [filename, action_id, key])
			continue
		if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
			errors.append("%s: %s effects.campaign.mobilisation.%s must be numeric" % [filename, action_id, key])
			continue
		var value := float(raw[key])
		if absf(value) > K.MAX_MOBILISATION_PER_MONTH:
			errors.append("%s: %s effects.campaign.mobilisation.%s = %s exceeds MAX_MOBILISATION_PER_MONTH (%s)" % [
				filename, action_id, key, str(value), str(K.MAX_MOBILISATION_PER_MONTH)
			])
		out[key] = value
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
