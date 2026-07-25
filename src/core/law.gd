class_name Law
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/laws/*.json file. See docs/data-architecture.md and
## docs/legislature-model.md.
##
## Mirrors src/core/party.gd's from_dict shape: a plain data object built once
## at load time, validated loudly, never mutated afterward.

const LK = preload("res://src/sim/legislature_constants.gd")

const THEME_KEYS := ["tax", "labour", "social", "institutional"]

## Effect keys that are a single float delta into one of the non-budget
## channels legislature.gd accumulates onto NationState.
const SCALAR_EFFECT_KEYS := [
	"structural_unemployment_pct", "potential_growth_pct", "other_revenue_pct_gdp",
]

var id: String = ""
var law_name: String = ""
var theme: String = ""
var summary: String = ""

## Position on the same two-axis ideology space election_constants.gd's
## SLOT_POSITION uses -- economic (-1 left ... +1 right), social (-1 open ...
## +1 traditional). No parallel vocabulary; see docs/legislature-model.md.
var position: Dictionary = {}

var majority: String = ""

## Months a law must wait after failing before it can be proposed again.
## Passed laws with `once = true` can never be proposed again at all.
var cooldown_months: int = 0
var once: bool = true

## Array of {"field": String, "op": String, "value": float}, each field checked
## against legislature_constants.PRECONDITION_FIELDS at load time.
var preconditions: Array = []

## {"tax_rates_pct": {...}, "spending_pct_gdp": {...},
##  "structural_unemployment_pct": float, "potential_growth_pct": float,
##  "other_revenue_pct_gdp": float, "bloc_offset": {...}} -- any subset.
var effects: Dictionary = {}


static func from_dict(d: Dictionary, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array):
	var law := new()

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: missing or invalid string field 'id'" % filename)
	else:
		law.id = d["id"]

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, law.id])
	else:
		law.law_name = d["name"]

	if not d.has("theme") or typeof(d["theme"]) != TYPE_STRING or not THEME_KEYS.has(d["theme"]):
		errors.append("%s: %s theme must be one of %s" % [filename, law.id, THEME_KEYS])
	else:
		law.theme = d["theme"]

	law.summary = d.get("summary", "")
	if typeof(law.summary) != TYPE_STRING:
		errors.append("%s: %s summary must be a string" % [filename, law.id])
		law.summary = ""

	law.position = _extract_position(d, law.id, filename, errors)

	if not d.has("majority") or not LK.MAJORITY_KEYS.has(d.get("majority")):
		errors.append("%s: %s majority must be one of %s" % [filename, law.id, LK.MAJORITY_KEYS])
	else:
		law.majority = d["majority"]

	law.cooldown_months = int(d.get("cooldown_months", 0))
	if law.cooldown_months < 0:
		errors.append("%s: %s cooldown_months must be >= 0" % [filename, law.id])

	law.once = bool(d.get("once", false))

	law.preconditions = _extract_preconditions(d, law.id, filename, errors)
	law.effects = _extract_effects(d, law.id, filename, errors, tax_keys, spending_keys, bloc_keys)

	return law


static func _extract_position(d: Dictionary, law_id: String, filename: String, errors: Array[String]) -> Dictionary:
	var pos: Dictionary = d.get("position", {})
	if typeof(pos) != TYPE_DICTIONARY or not pos.has("economic") or not pos.has("social"):
		errors.append("%s: %s missing or invalid object field 'position' {economic, social}" % [filename, law_id])
		return {"economic": 0.0, "social": 0.0}

	var econ := float(pos.get("economic", 0.0))
	var social := float(pos.get("social", 0.0))
	if econ < -1.0 or econ > 1.0:
		errors.append("%s: %s position.economic = %s out of range [-1, 1]" % [filename, law_id, str(econ)])
	if social < -1.0 or social > 1.0:
		errors.append("%s: %s position.social = %s out of range [-1, 1]" % [filename, law_id, str(social)])
	return {"economic": econ, "social": social}


static func _extract_preconditions(d: Dictionary, law_id: String, filename: String, errors: Array[String]) -> Array:
	var raw = d.get("preconditions", [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s: %s preconditions must be an array" % [filename, law_id])
		return []

	var out: Array = []
	for i in raw.size():
		var entry = raw[i]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("%s: %s preconditions[%d] is not an object" % [filename, law_id, i])
			continue

		var field = entry.get("field", "")
		if typeof(field) != TYPE_STRING or not LK.PRECONDITION_FIELDS.has(field):
			errors.append("%s: %s preconditions[%d].field '%s' is not a recognised field" % [filename, law_id, i, str(field)])
			continue

		var op = entry.get("op", "")
		if typeof(op) != TYPE_STRING or not LK.PRECONDITION_OPS.has(op):
			errors.append("%s: %s preconditions[%d].op '%s' is not a recognised operator" % [filename, law_id, i, str(op)])
			continue

		if not entry.has("value") or not (typeof(entry["value"]) == TYPE_INT or typeof(entry["value"]) == TYPE_FLOAT):
			errors.append("%s: %s preconditions[%d].value is missing or not numeric" % [filename, law_id, i])
			continue

		out.append({"field": field, "op": op, "value": float(entry["value"])})

	return out


static func _extract_effects(d: Dictionary, law_id: String, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array) -> Dictionary:
	var raw: Dictionary = d.get("effects", {})
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects must be an object" % [filename, law_id])
		return {}

	var out := {}

	if raw.has("tax_rates_pct"):
		out["tax_rates_pct"] = _extract_keyed_deltas(raw["tax_rates_pct"], tax_keys, "effects.tax_rates_pct", law_id, filename, errors)

	if raw.has("spending_pct_gdp"):
		out["spending_pct_gdp"] = _extract_keyed_deltas(raw["spending_pct_gdp"], spending_keys, "effects.spending_pct_gdp", law_id, filename, errors)

	for key in SCALAR_EFFECT_KEYS:
		if raw.has(key):
			if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
				errors.append("%s: %s effects.%s must be numeric" % [filename, law_id, key])
			else:
				out[key] = float(raw[key])

	if raw.has("bloc_offset"):
		out["bloc_offset"] = _extract_keyed_deltas(raw["bloc_offset"], bloc_keys, "effects.bloc_offset", law_id, filename, errors)

	for key in raw.keys():
		if key != "tax_rates_pct" and key != "spending_pct_gdp" and key != "bloc_offset" and not SCALAR_EFFECT_KEYS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, law_id, key])

	return out


static func _extract_keyed_deltas(raw, known_keys: Array, path: String, law_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s %s must be an object" % [filename, law_id, path])
		return {}

	var out := {}
	for key in raw.keys():
		if not known_keys.has(key):
			errors.append("%s: %s %s.%s is not a recognised key" % [filename, law_id, path, key])
			continue
		if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
			errors.append("%s: %s %s.%s must be numeric" % [filename, law_id, path, key])
			continue
		out[key] = float(raw[key])
	return out
