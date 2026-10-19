class_name Scenario
extends RefCounted

## Typed, validated in-memory representation of one data/scenarios/*.json file.
## See docs/scenario-model.md and docs/data-architecture.md.
##
## A scenario is an authored STARTING STATE for one nation -- debt, seat
## composition, starting approval -- applied once, at GameState.new_game(), and
## never again. It is the project's answer to difficulty: varying the starting
## state changes data and no tuned constant, so every measured balance number
## survives it. See docs/tiers/declined.md for why there is no difficulty slider.
##
## Deliberately NOT here: the coalition, and the institutional system. The
## coalition is derived by Government.form() from the seats a scenario already
## authors, so authoring both would author a contradiction the formation rule
## exists to resolve. The system is docs/transition-model.md's mechanism, and a
## scenario that rewrote it would be a second, unchecked route into the
## institutional state docs/political-systems.md built the template constraint
## to guard.

## Every override key is OPTIONAL, and absent means "whatever the nation's own
## data already says". That is what makes a partial scenario -- the common case
## -- expressible without restating a nation file. A separate `has_` flag rather
## than a sentinel value, because 0.0 is a legitimate debt level.
var id: String = ""
var nation_id: String = ""
var display_name: String = ""
var description: String = ""

var has_debt_to_gdp_pct: bool = false
var debt_to_gdp_pct: float = 0.0

## party id -> seat share. Merged OVER the nation's authored shares, so naming
## one party leaves the rest alone -- but the merged total still has to sum to
## 1.0, which PoliticsLoader.validate_scenarios() checks against the real roster.
var seat_share: Dictionary = {}

## bloc key -> starting approval in [0, 100]. Applied over APPROVAL_NEUTRAL;
## unnamed blocs stay neutral. Per-bloc rather than one overall figure because
## overall_approval_pct is a weighted roll-up of the blocs -- authoring the
## roll-up alone would be contradicted by the first tick that recomputes it.
var bloc_approval: Dictionary = {}


static func from_dict(d: Dictionary, filename: String, errors: Array[String]):
	var s := new()

	s.id = _extract_string(d, "id", filename, errors)
	var stem := filename.get_basename()
	if s.id != "" and s.id != stem:
		errors.append("%s: id '%s' does not match filename" % [filename, s.id])

	s.nation_id = _extract_string(d, "nation", filename, errors)
	s.display_name = _extract_string(d, "name", filename, errors)
	s.description = _extract_string(d, "description", filename, errors)

	if not d.has("overrides") or typeof(d["overrides"]) != TYPE_DICTIONARY:
		errors.append("%s: missing or invalid object field 'overrides'" % filename)
		return s

	var overrides: Dictionary = d["overrides"]

	# An overrides block that overrides nothing is a scenario the menu would
	# offer as a distinct start and that plays identically to Standard -- the
	# same class of quiet lie an unreachable law would be.
	var known := ["debt_to_gdp_pct", "seat_share", "bloc_approval"]
	var named := 0
	for key in overrides.keys():
		if not known.has(key):
			errors.append("%s: overrides has unknown key '%s'" % [filename, key])
		else:
			named += 1
	if named == 0:
		errors.append("%s: overrides names none of %s -- a scenario that overrides nothing is Standard under another name" % [filename, str(known)])

	if overrides.has("debt_to_gdp_pct"):
		var raw = overrides["debt_to_gdp_pct"]
		if typeof(raw) != TYPE_FLOAT and typeof(raw) != TYPE_INT:
			errors.append("%s: overrides.debt_to_gdp_pct is not a number" % filename)
		else:
			s.has_debt_to_gdp_pct = true
			s.debt_to_gdp_pct = float(raw)
			if s.debt_to_gdp_pct < 0.0:
				errors.append("%s: overrides.debt_to_gdp_pct %s is negative" % [filename, str(s.debt_to_gdp_pct)])

	s.seat_share = _extract_number_map(overrides, "seat_share", filename, errors)
	s.bloc_approval = _extract_number_map(overrides, "bloc_approval", filename, errors)

	# Range only. WHICH party ids and WHICH bloc keys are legal is a cross-file
	# question -- it needs the nation's own roster -- so it lives in
	# PoliticsLoader.validate_scenarios() beside the other cross-file checks.
	for party_id in s.seat_share.keys():
		var share: float = s.seat_share[party_id]
		if share < 0.0 or share > 1.0:
			errors.append("%s: overrides.seat_share['%s'] %s is outside [0, 1]" % [filename, party_id, str(share)])

	for bloc in s.bloc_approval.keys():
		var approval: float = s.bloc_approval[bloc]
		if approval < 0.0 or approval > 100.0:
			errors.append("%s: overrides.bloc_approval['%s'] %s is outside [0, 100]" % [filename, bloc, str(approval)])

	return s


static func _extract_string(d: Dictionary, key: String, filename: String, errors: Array[String]) -> String:
	if not d.has(key) or typeof(d[key]) != TYPE_STRING:
		errors.append("%s: missing or invalid string field '%s'" % [filename, key])
		return ""
	if d[key] == "":
		errors.append("%s: field '%s' is empty" % [filename, key])
	return d[key]


## A {String: number} object, returned with every value coerced to float. An
## absent key is not an error -- every override is optional; a present key that
## is not an object is.
static func _extract_number_map(d: Dictionary, key: String, filename: String, errors: Array[String]) -> Dictionary:
	var out := {}
	if not d.has(key):
		return out
	if typeof(d[key]) != TYPE_DICTIONARY:
		errors.append("%s: overrides.%s is not an object" % [filename, key])
		return out

	var raw: Dictionary = d[key]
	if raw.is_empty():
		errors.append("%s: overrides.%s is present but empty" % [filename, key])
		return out

	for entry_key in raw.keys():
		var value = raw[entry_key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			errors.append("%s: overrides.%s['%s'] is not a number" % [filename, key, entry_key])
			continue
		out[String(entry_key)] = float(value)
	return out
