class_name PoliticalSystem
extends RefCounted

## Typed, validated in-memory representation of one data/political-systems/*.json
## file. See docs/political-systems.md and docs/data-architecture.md.
##
## A template is a CONSTRAINT, not a defaults table. It carries the fields a
## nation cannot express on its own (which lose condition ends a run, whether a
## term limit is permitted) and it declares the allowed set for fields nations
## already carry flat (formation.method, formation.censure,
## legislative.dissolution.rule). Nothing here is copied onto a nation that
## doesn't already say it; data_loader.gd's cross-validation is what makes the
## constraint load-bearing.

const KNOWN_LOSE_CONDITIONS: Array[String] = [
	"executive_election_defeat", "party_not_largest", "never",
]

var id: String = ""
var display_name: String = ""

## What the office the player holds actually loses on. See
## src/sim/elections.gd -- dispatched here, never on the nation id.
var lose_condition: String = ""

## Every formation.method / formation.censure / legislative.dissolution.rule a
## nation using this template may declare. data_loader.gd fails at startup if
## a nation's flat field falls outside its template's set -- the check that
## makes the template load-bearing rather than decorative.
var allowed_formation_methods: Array[String] = []
var allowed_censure_rules: Array[String] = []
var allowed_dissolution_rules: Array[String] = []

## Every government.amendment.rule a nation using this template may declare.
## See docs/amendment-model.md.
var allowed_amendment_rules: Array[String] = []

## Every government.head_of_state.kind a nation using this template may
## declare. Added at V1.2d alongside system transition -- a transition writes
## a new head-of-state kind onto the target system, and this is what makes
## that write checkable target-side rather than trusted. Not needed before
## V1.2d because no nation's head-of-state kind ever changed. See
## docs/transition-model.md.
var allowed_head_of_state_kinds: Array[String] = []

## Whether a nation using this template may declare a term limit on the office
## the player holds. Nations without one still carry government.term_limit = 0,
## the same "field exists, zero means absent" shape EU membership uses.
var permits_term_limit: bool = false


static func from_dict(d: Dictionary, filename: String, errors: Array[String]):
	var s := new()

	s.id = _extract_string(d, "id", filename, errors)
	var stem := filename.get_basename()
	if s.id != "" and s.id != stem:
		errors.append("%s: id '%s' does not match filename" % [filename, s.id])

	s.display_name = _extract_string(d, "name", filename, errors)

	s.lose_condition = _extract_string(d, "lose_condition", filename, errors)
	if s.lose_condition != "" and not KNOWN_LOSE_CONDITIONS.has(s.lose_condition):
		errors.append("%s: lose_condition '%s' is not a recognised condition" % [filename, s.lose_condition])

	s.allowed_formation_methods = _extract_string_array(d, "allowed_formation_methods", filename, errors)
	s.allowed_censure_rules = _extract_string_array(d, "allowed_censure_rules", filename, errors)
	s.allowed_dissolution_rules = _extract_string_array(d, "allowed_dissolution_rules", filename, errors)
	s.allowed_amendment_rules = _extract_string_array(d, "allowed_amendment_rules", filename, errors)
	s.allowed_head_of_state_kinds = _extract_string_array(d, "allowed_head_of_state_kinds", filename, errors)

	s.permits_term_limit = _extract_bool(d, "permits_term_limit", filename, errors)

	return s


static func _extract_string(d: Dictionary, key: String, filename: String, errors: Array[String]) -> String:
	if not d.has(key) or typeof(d[key]) != TYPE_STRING:
		errors.append("%s: missing or invalid string field '%s'" % [filename, key])
		return ""
	return d[key]


static func _extract_bool(d: Dictionary, key: String, filename: String, errors: Array[String]) -> bool:
	if not d.has(key) or typeof(d[key]) != TYPE_BOOL:
		errors.append("%s: missing or invalid bool field '%s'" % [filename, key])
		return false
	return d[key]


static func _extract_string_array(d: Dictionary, key: String, filename: String, errors: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if not d.has(key) or typeof(d[key]) != TYPE_ARRAY:
		errors.append("%s: missing or invalid array field '%s'" % [filename, key])
		return out
	for entry in d[key]:
		if typeof(entry) != TYPE_STRING:
			errors.append("%s: %s contains a non-string entry" % [filename, key])
			continue
		out.append(entry)
	if out.is_empty():
		errors.append("%s: %s must not be empty" % [filename, key])
	return out
