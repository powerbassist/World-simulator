class_name Law
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/laws/*.json file. See docs/data-architecture.md and
## docs/legislature-model.md.
##
## Mirrors src/core/party.gd's from_dict shape: a plain data object built once
## at load time, validated loudly, never mutated afterward.

const LK = preload("res://src/sim/legislature_constants.gd")
const Nation = preload("res://src/core/nation.gd")
## V1.4b. Borrowed rather than re-declared, exactly as src/core/company_action.gd
## borrows it: the bound on how hard one authored rule may lean on a sector is a
## property of the companies model, and a second number for it here would be one
## strength written twice.
const CK = preload("res://src/sim/companies_constants.gd")

## `business` is V1.4b's, and it is named for a DOMAIN like the other four rather
## than for a mechanism. A theme called "regulation" is where V1.6's sectoral
## investment would wrongly land -- that is a lever pointed at a sector too, and
## the thing that separates them is the register, not the word.
const THEME_KEYS := ["tax", "labour", "social", "institutional", "business"]

## Effect keys that are a single float delta into one of the non-budget
## channels legislature.gd accumulates onto NationState.
const SCALAR_EFFECT_KEYS := [
	"structural_unemployment_pct", "potential_growth_pct", "other_revenue_pct_gdp",
]

## effects.institutional keys a constitutional amendment may set, each an
## ABSOLUTE value written straight onto NationState -- an institution is set,
## not nudged, unlike every other effect channel above. Whether a given VALUE
## is allowed for a given nation is a template question, checked once at
## load by DataLoader against every system named in this law's own `systems`
## list -- see docs/amendment-model.md. This dict only checks that the value
## is a recognised member of the right enum at all.
const INSTITUTIONAL_EFFECT_KEYS := {
	"censure_rule": Nation.KNOWN_CENSURE_RULES,
	"dissolution_rule": Nation.KNOWN_DISSOLUTION_RULES,
	"formation_method": Nation.KNOWN_FORMATION_METHODS,
	"amendment_rule": Nation.KNOWN_AMENDMENT_RULES,
}
## Integer institutional effect keys, checked by range rather than by enum.
const INSTITUTIONAL_INT_KEYS := {
	"term_limit": [Nation.MIN_TERM_LIMIT, Nation.MAX_TERM_LIMIT],
	"term_months": [12, 120],
}

## Keys a system-transition amendment must ALSO write if it writes
## effects.institutional.system_id -- a bare system_id write would leave every
## OTHER field at its pre-transition value, which is exactly the
## half-understood institutional state docs/political-systems.md refuses.
## head_of_state is a nested object, checked separately by
## _extract_head_of_state(). See docs/transition-model.md.
const SYSTEM_CHANGE_REQUIRED_KEYS := [
	"formation_method", "censure_rule", "dissolution_rule", "amendment_rule", "term_limit",
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
##  "other_revenue_pct_gdp": float, "bloc_offset": {...},
##  "institutional": {...}, "company": {...}} -- any subset.
##
## `company` is V1.4b's, and it is the SAME CHANNEL NAME company_action.gd uses
## with a deliberately different shape: an action names an op against the one firm
## it is pointed at, a law names a SECTOR and a burden. That is the a/b split
## written into the schema rather than only into the docs -- a subsidy is an
## executive act aimed at a firm, a regulation is a law aimed at a sector.
var effects: Dictionary = {}

## A constitutional amendment: resolve_vote() reads the proposing nation's own
## ns.amendment_rule instead of `majority` above. See docs/amendment-model.md.
var constitutional: bool = false

## Which political-system templates this law may be proposed under -- filters
## Legislature.available(). Required and non-empty when constitutional is
## true; ignored (and must be absent) otherwise, the same
## present-only-if-needed shape Nation's executive block uses.
var systems: Array[String] = []

## True when effects.institutional writes system_id -- a system transition,
## not an ordinary amendment. Derived once at load, the same precedent
## `constitutional` sets, so Legislature.available() does not dig into a
## nested dict every call. Gated separately from `constitutional` by
## ns.permits_system_change -- see docs/transition-model.md.
var changes_system: bool = false


## `sector_keys` is PASSED rather than preloaded, the way tax_keys, spending_keys
## and bloc_keys already are: which sectors exist is the economy model's list, and
## a validator reaching sideways for it is the dependency data_loader.gd exists to
## carry. The bound on a burden's size is a different question and comes from CK.
static func from_dict(d: Dictionary, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array, sector_keys: Array):
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

	law.constitutional = bool(d.get("constitutional", false))
	if law.constitutional and law.majority != "amendment":
		errors.append("%s: %s constitutional laws must set majority: 'amendment'" % [filename, law.id])
	if not law.constitutional and law.majority == "amendment":
		errors.append("%s: %s majority 'amendment' requires constitutional: true" % [filename, law.id])

	if law.constitutional:
		law.systems = _extract_string_array(d, "systems", law.id, filename, errors)
		if law.systems.is_empty():
			errors.append("%s: %s constitutional laws must name at least one system in 'systems'" % [filename, law.id])
	elif d.has("systems"):
		errors.append("%s: %s 'systems' is only valid on a constitutional law" % [filename, law.id])

	law.preconditions = _extract_preconditions(d, law.id, filename, errors)
	law.effects = _extract_effects(d, law.id, filename, errors, tax_keys, spending_keys, bloc_keys, sector_keys, law.constitutional)
	law.changes_system = law.effects.get("institutional", {}).has("system_id")

	return law


static func _extract_string_array(d: Dictionary, key: String, law_id: String, filename: String, errors: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var raw = d.get(key, [])
	if typeof(raw) != TYPE_ARRAY:
		errors.append("%s: %s %s must be an array" % [filename, law_id, key])
		return out
	for entry in raw:
		if typeof(entry) != TYPE_STRING:
			errors.append("%s: %s %s contains a non-string entry" % [filename, law_id, key])
			continue
		out.append(entry)
	return out


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


static func _extract_effects(d: Dictionary, law_id: String, filename: String, errors: Array[String], tax_keys: Array, spending_keys: Array, bloc_keys: Array, sector_keys: Array, allow_institutional: bool) -> Dictionary:
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

	if raw.has("institutional"):
		if not allow_institutional:
			errors.append("%s: %s effects.institutional is only valid on a constitutional law" % [filename, law_id])
		else:
			out["institutional"] = _extract_institutional(raw["institutional"], law_id, filename, errors)

	if raw.has("company"):
		out["company"] = _extract_company(raw["company"], law_id, filename, errors, sector_keys)

	# THE ANTI-DOUBLE-COUNT, MADE MECHANICAL. A regulation's burden reaches
	# structural unemployment through Companies.headcount(), which is the same act
	# (a law passing), the same landing site (Economy._update_unemployment()) and
	# the same units as `structural_unemployment_pct`. A law carrying both would be
	# two answers to one question with no way for a reader to tell which one the
	# number came from.
	#
	# docs/legislature-model.md's existing lever-vs-bloc_offset rule says the same
	# thing about a different pair and says it in PROSE -- "the sixteen templates
	# each pick one story and tell it once". This one is a load error instead,
	# because a convention that only the docs enforce is one an author breaks by
	# not reading them. Same shape as the directed key that refuses a symmetric one.
	if raw.has("company") and raw.has("structural_unemployment_pct"):
		errors.append("%s: %s carries both effects.company and effects.structural_unemployment_pct -- a sector burden already reaches structural unemployment through the firm register, so the two are one story told twice. Pick one." % [filename, law_id])

	for key in raw.keys():
		if key != "tax_rates_pct" and key != "spending_pct_gdp" and key != "bloc_offset" and key != "institutional" and key != "company" and not SCALAR_EFFECT_KEYS.has(key):
			errors.append("%s: %s effects.%s is not a recognised effect channel" % [filename, law_id, key])

	return out


## V1.4b. A regulation names a SECTOR and a burden on it, and that is the whole
## schema -- `sector` and `burden`, refused if anything else appears.
##
## MUST NOT NAME A FIRM, and the refusal below is where that is enforced rather
## than merely intended. Share movement is the subsidy's persistent channel, and a
## law that could point at one firm would be a second writer of it -- two answers
## to the question of who is winning the sector. A regulation is sector-wide by
## construction, and the register is what it reads rather than what it moves.
##
## The burden is SIGNED. Deregulation is the negative direction on the same
## accumulator, not a repeal verb: there is no repeal in this project and a `once`
## law never returns, so a burden that could only ever rise would be a permanent
## monotone charge -- the failure docs/defence-model.md names, where a clamp stops
## being a guard rail and becomes the number. A signed burden also costs no new
## precondition field, and legislature_constants.PRECONDITION_FIELDS has no sector
## parameter and should not grow one.
static func _extract_company(raw, law_id: String, filename: String, errors: Array[String], sector_keys: Array) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.company must be an object" % [filename, law_id])
		return {}

	var sector = raw.get("sector", "")
	if typeof(sector) != TYPE_STRING or not sector_keys.has(sector):
		errors.append("%s: %s effects.company.sector '%s' is not a recognised sector (%s)" % [
			filename, law_id, str(sector), str(sector_keys)
		])
		return {}

	if not raw.has("burden") or not (typeof(raw["burden"]) == TYPE_INT or typeof(raw["burden"]) == TYPE_FLOAT):
		errors.append("%s: %s effects.company.burden is missing or not numeric" % [filename, law_id])
		return {}

	var burden := float(raw["burden"])
	if burden == 0.0:
		errors.append("%s: %s effects.company.burden is 0.0 -- a rule that binds nobody is not a rule" % [filename, law_id])
	elif absf(burden) > CK.REGULATION_BURDEN_MAX:
		errors.append("%s: %s effects.company.burden = %s exceeds REGULATION_BURDEN_MAX (%s)" % [
			filename, law_id, str(burden), str(CK.REGULATION_BURDEN_MAX)
		])

	for key in raw.keys():
		if key != "sector" and key != "burden":
			errors.append("%s: %s effects.company.%s is not a recognised term -- a regulation names a sector and a burden, and a firm id or a share rate beside them would make a law the second writer of the subsidy's channel" % [
				filename, law_id, key
			])

	return {"sector": sector, "burden": burden}


## Absolute values written straight onto NationState -- see
## INSTITUTIONAL_EFFECT_KEYS' header comment. Only checks that the value is a
## recognised member of the right enum at all; whether it is the RIGHT value
## for a given nation's declared system is DataLoader's cross-check against
## this law's own `systems` list.
static func _extract_institutional(raw, law_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.institutional must be an object" % [filename, law_id])
		return {}
	if raw.is_empty():
		errors.append("%s: %s effects.institutional must not be empty" % [filename, law_id])

	var out := {}
	for key in raw.keys():
		if key == "system_id":
			# A system-transition target. Whether it names a real template, and
			# whether the rest of `out` is legal under that template, is
			# DataLoader's target-side cross-check -- this only checks the
			# value is a non-empty string. See docs/transition-model.md.
			if typeof(raw[key]) != TYPE_STRING or raw[key] == "":
				errors.append("%s: %s effects.institutional.system_id must be a non-empty string" % [filename, law_id])
			else:
				out[key] = raw[key]
		elif key == "head_of_state":
			out[key] = _extract_head_of_state(raw[key], law_id, filename, errors)
		elif INSTITUTIONAL_EFFECT_KEYS.has(key):
			var allowed: Array = INSTITUTIONAL_EFFECT_KEYS[key]
			if typeof(raw[key]) != TYPE_STRING or not allowed.has(raw[key]):
				errors.append("%s: %s effects.institutional.%s must be one of %s" % [filename, law_id, key, allowed])
			else:
				out[key] = raw[key]
		elif INSTITUTIONAL_INT_KEYS.has(key):
			var range: Array = INSTITUTIONAL_INT_KEYS[key]
			if not (typeof(raw[key]) == TYPE_INT or typeof(raw[key]) == TYPE_FLOAT):
				errors.append("%s: %s effects.institutional.%s must be numeric" % [filename, law_id, key])
			else:
				var value := int(raw[key])
				if value < int(range[0]) or value > int(range[1]):
					errors.append("%s: %s effects.institutional.%s = %d out of range [%d, %d]" % [filename, law_id, key, value, range[0], range[1]])
				out[key] = value
		else:
			errors.append("%s: %s effects.institutional.%s is not a recognised institutional field" % [filename, law_id, key])

	# Completeness: a system_id write with nothing else is the exact
	# half-understood state the template's own cross-check refuses for a
	# nation file -- see SYSTEM_CHANGE_REQUIRED_KEYS' header comment.
	if out.has("system_id"):
		for key in SYSTEM_CHANGE_REQUIRED_KEYS:
			if not out.has(key):
				errors.append("%s: %s writes system_id but is missing effects.institutional.%s, required for every system transition" % [filename, law_id, key])
		if not out.has("head_of_state"):
			errors.append("%s: %s writes system_id but is missing effects.institutional.head_of_state, required for every system transition" % [filename, law_id])
	elif out.has("head_of_state"):
		errors.append("%s: %s effects.institutional.head_of_state is only valid alongside system_id" % [filename, law_id])

	return out


## The office an amendment installs, not the person -- see
## docs/transition-model.md. `elected_president` derives its holder from the
## largest party's own leader at apply() time, so `name` is forbidden there,
## the mirror of Nation.gd's own head-of-state parsing (which always requires
## a name, because a nation's starting head of state is always authored, never
## derived). `term_years` is required only for `elected_president`, the same
## present-only-if-needed shape Nation.gd's own clock uses.
static func _extract_head_of_state(raw, law_id: String, filename: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s effects.institutional.head_of_state must be an object" % [filename, law_id])
		return {}

	var out := {}

	var kind = raw.get("kind", "")
	if typeof(kind) != TYPE_STRING or not Nation.KNOWN_HEAD_OF_STATE_KINDS.has(kind):
		errors.append("%s: %s effects.institutional.head_of_state.kind '%s' is not a recognised kind" % [filename, law_id, str(kind)])
		return {}
	out["kind"] = kind

	var title = raw.get("title", "")
	if typeof(title) != TYPE_STRING or title == "":
		errors.append("%s: %s effects.institutional.head_of_state.title is missing or invalid" % [filename, law_id])
	else:
		out["title"] = title

	# A transition names an OFFICE; the acting nation's own content names who
	# fills it. That is true for every kind now, where before it was true only
	# for elected_president: the Restoration Act used to author "Alexander IV"
	# inline, so every parliamentary republic in Europe restored the SAME king.
	# The nation's `government.pretender_person` answers it per nation instead —
	# and a monarchy points that reference at its own sitting monarch, so a
	# restoration puts the right dynasty back. See docs/transition-model.md.
	if raw.has("name"):
		errors.append("%s: %s effects.institutional.head_of_state.name must not be set for any kind -- the holder is derived at apply() time, from the largest party's leader for 'elected_president' and from the nation's own government.pretender_person otherwise" % [filename, law_id])

	if kind == "elected_president":
		if not raw.has("term_years") or not (typeof(raw["term_years"]) == TYPE_INT or typeof(raw["term_years"]) == TYPE_FLOAT):
			errors.append("%s: %s effects.institutional.head_of_state.term_years is missing or not numeric, required for kind 'elected_president'" % [filename, law_id])
		else:
			var term_years := int(raw["term_years"])
			if term_years < 1 or term_years > 10:
				errors.append("%s: %s effects.institutional.head_of_state.term_years = %d out of range [1, 10]" % [filename, law_id, term_years])
			out["term_years"] = term_years
	elif raw.has("term_years"):
		errors.append("%s: %s effects.institutional.head_of_state.term_years must not be set for kind '%s'" % [filename, law_id, kind])

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
