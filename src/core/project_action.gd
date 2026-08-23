class_name ProjectAction
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/project-actions/*.json file. See docs/projects-model.md.
##
## THE EIGHTH EFFECT CHANNEL. `effects.project` names an op, the PROJECT it is
## pointed at, and, for the starting op, that project's three authored facts;
## src/sim/projects.gd dispatches it against the acting nation's own register.
##
## Mirrors src/core/investment_action.gd, which mirrors src/core/company_action.gd,
## which mirrors src/core/diplomatic_action.gd -- the FOURTH directory on one shape
## rather than a fourth kind of content, the way V1.3a's directory served five
## sessions and V1.4a's served three.
##
## THE PROJECT ID IS AUTHORED ON EVERY OP, INCLUDING THE ONE THAT CANCELS.
## investment_action.gd requires `sector` on its withdrawal for the same reason: an
## act that says only "stop" has not said what it is stopping. The id is the
## register key, so a start and its abandon name the same string and nothing has to
## infer the pairing from an action id.
##
## THREE TERMS ON `start`, WHERE investment_action.gd PERMITS EXACTLY ONE. That file
## refuses a second because an authored cost beside `intensity` would be one strength
## written twice, the redundancy tools/coercion_probe.gd deleted. Here
## src/sim/projects_constants.gd ships no constant turning any one of the three into
## the other two, so duration, price and payoff are three independent facts about a
## named object rather than three descriptions of one. See PROJECT_OP_TERMS.
##
## What is NOT borrowed is as deliberate as what is:
##
##   `effects.relations` -- a domestic act has no pair to move.
##   `cooldown_months` -- absent, and harder than V1.6e's absence. A project is built
##     ONCE: `project_started` gates it, the register never forgets, and a cooldown
##     beside that would be a second gate on a fact that can never change back.
##   `position` / `majority` / `once` -- absent. This is an executive verb and there
##     is no assembly division to score, by docs/tiers/v1.md section 6's
##     decomposition call 2. `once` is not needed because the register IS once.

const K = preload("res://src/sim/projects_constants.gd")
## Borrowed rather than re-declared, for investment_action.gd's reason: the bound on
## how hard ONE authored action may hit a bloc's approval is a property of the
## opinion model, and a second number for it would be two answers to one question.
const DK = preload("res://src/sim/diplomacy_constants.gd")


var id: String = ""
var action_name: String = ""
var summary: String = ""

## Array of {"field": String, "op": String, "value": float}, each field checked
## against projects_constants.PRECONDITION_FIELDS at load time.
var preconditions: Array = []

## Two channels: `project` (required) and `bloc_offset` (optional). The second is
## optional for diplomatic_action.gd's reason -- whether an authored price is
## legible is a measurement, and whether one must exist is not.
var effects: Dictionary = {}

const EFFECT_CHANNELS := ["project", "bloc_offset"]


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


static func project_id(a) -> String:
	return String(a.effects.get("project", {}).get("project_id", ""))


static func op_of(a) -> String:
	return String(a.effects.get("project", {}).get("op", ""))


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

	if not raw.has("project"):
		errors.append("%s: %s effects.project is required -- an action that names no project is not a project action" % [filename, action_id])
	else:
		out["project"] = _extract_project(raw["project"], action_id, filename, errors)

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_bloc_offset(raw["bloc_offset"], action_id, filename, errors, bloc_keys)

	for key in raw.keys():
		if not EFFECT_CHANNELS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, action_id, key])

	return out


## Each of the three `start` terms is range-checked here rather than clamped later,
## because a project that loads at a value the model would clamp is content that does
## not say what it does. investment_action.gd's treatment of `intensity`.
static func _extract_project(raw, action_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.project must be an object" % [filename, action_id])
		return {}

	var project_op = raw.get("op", "")
	if typeof(project_op) != TYPE_STRING or not K.PROJECT_OPS.has(project_op):
		errors.append("%s: %s effects.project.op '%s' is not a recognised op (%s)" % [
			filename, action_id, str(project_op), str(K.PROJECT_OPS)
		])
		return {}

	var pid = raw.get("project_id", "")
	if typeof(pid) != TYPE_STRING or pid == "":
		errors.append("%s: %s effects.project.project_id is missing -- every op names the project it points at, including the one that cancels" % [
			filename, action_id
		])
		return {}

	var out := {"op": project_op, "project_id": pid}
	var terms: Array = K.PROJECT_OP_TERMS.get(project_op, [])

	if terms.is_empty():
		for key in raw.keys():
			if key != "op" and key != "project_id":
				errors.append("%s: %s effects.project.%s is set on an '%s' -- it cancels a build in progress and reads no terms" % [
					filename, action_id, key, project_op
				])
		return out

	# *** `project_name` IS A DISPLAY FIELD AND NOT A FOURTH TERM, and the distinction is
	# the fifteenth screenshot pass's second find. *** The diary's project row read
	# "Opens: Build the High-Speed Rail Spine", because the only name in the file was the
	# ACTION's -- and an action name is an imperative, which is right on a button and
	# wrong after a colon. Two surfaces genuinely need two strings: Public Works puts a
	# verb on the button the player presses, and the diary and the finished list want the
	# noun the country ends up with.
	#
	# It is deliberately NOT in K.PROJECT_OP_TERMS. That list is the numeric terms, and
	# its whole argument -- three independent quantities where investment_action.gd has
	# one -- is about strengths written twice. A name is not a strength.
	var display = raw.get("project_name", "")
	if typeof(display) != TYPE_STRING or display == "":
		errors.append("%s: %s effects.project.project_name is missing -- the action name is an imperative and the diary needs the noun" % [
			filename, action_id
		])
	else:
		out["project_name"] = display

	for term in terms:
		if not raw.has(term):
			errors.append("%s: %s effects.project.%s is required on a '%s' -- a project states its duration, its price and its payoff, and none of the three is derived from the others" % [
				filename, action_id, term, project_op
			])
			continue
		if not (typeof(raw[term]) == TYPE_INT or typeof(raw[term]) == TYPE_FLOAT):
			errors.append("%s: %s effects.project.%s must be numeric" % [filename, action_id, term])
			continue
		out[term] = float(raw[term])

	_check_range(out, "build_months", float(K.MIN_BUILD_MONTHS) - 1.0, float(K.MAX_BUILD_MONTHS), action_id, filename, errors)
	_check_range(out, "cost_pct_gdp", 0.0, K.MAX_PROJECT_COST_PCT_GDP, action_id, filename, errors)
	_check_range(out, "potential_growth_pct", 0.0, K.MAX_PROJECT_POTENTIAL_PCT, action_id, filename, errors)

	if out.has("build_months"):
		out["build_months"] = float(int(out["build_months"]))

	for key in raw.keys():
		if key != "op" and key != "project_id" and key != "project_name" and not terms.has(key):
			errors.append("%s: %s effects.project.%s is not a recognised term on a '%s' (%s)" % [
				filename, action_id, key, project_op, str(terms)
			])

	return out


## `low` is exclusive and `high` inclusive: a project costing nothing or worth
## nothing is not one, and the ceilings are reachable by design.
static func _check_range(out: Dictionary, key: String, low: float, high: float, action_id: String, filename: String, errors: Array[String]) -> void:
	if not out.has(key):
		return
	var value := float(out[key])
	if value <= low:
		errors.append("%s: %s effects.project.%s = %s is at or below its floor (%s) -- a project that costs nothing, takes no time or buys nothing is not one" % [
			filename, action_id, key, str(value), str(low)
		])
	elif value > high:
		errors.append("%s: %s effects.project.%s = %s exceeds its ceiling (%s)" % [
			filename, action_id, key, str(value), str(high)
		])


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
