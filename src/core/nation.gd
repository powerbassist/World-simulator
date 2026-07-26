class_name Nation
extends RefCounted

## Typed, validated in-memory representation of one data/nations/*.json file.
## Built and range-checked by from_dict(); see docs/data-architecture.md for
## the schema and the import script's ownership boundary on `imported`.

const KNOWN_IMPORTED_KEYS: Array[String] = [
	"_source", "_year", "_usd_eur", "population", "gdp_eur_bn",
	"unemployment_pct", "sectors",
]
const KNOWN_SECTOR_KEYS: Array[String] = ["agriculture", "industry", "services"]
const KNOWN_ELECTION_SYSTEMS: Array[String] = ["pr_dhondt", "pr_national", "fptp", "two_round", "parallel"]

## How a government is assembled, and what it takes to bring one down. Both are
## dispatched on the string in src/sim/government.gd, never on the nation id —
## see docs/government-model.md and docs/engine-decision.md Rule 1.
const KNOWN_FORMATION_METHODS: Array[String] = [
	"presidential_appointment", "chancellor_election", "investiture",
	"coalition_negotiation", "largest_party", "directorial",
]
const KNOWN_CENSURE_RULES: Array[String] = [
	"absolute_members", "constructive_absolute", "simple_present", "none",
]

static var _id_regex := RegEx.create_from_string("^[A-Z]{3}$")

var id: String = ""
var nation_name: String = ""
var geo_id: String = ""
var capital: String = ""
var playable: bool = false

var leader_name: String = ""
var leader_title: String = ""
var leader_party_id: String = ""

## The assembly's own term and size, from government.legislative. Distinct from
## the executive's term below: in France those are two different clocks, and
## conflating them is what made the player's term read as the Assembly's.
var term_years: int = 0
var assembly_seats: int = 0
var chamber_name: String = ""

## Present only where the head of government is elected separately from the
## assembly — of the ten, only France. Absent means the executive is drawn from
## the chamber and its term IS the legislative term, the same "field exists,
## reader does nothing" shape EU membership already uses. See
## docs/government-model.md.
var has_executive: bool = false
var executive_title: String = ""
var executive_term_years: int = 0
var executive_next_year: int = 0
var executive_next_month: int = 0

## How a government forms and how it can be brought down. Required for all ten,
## resolved only for the player's nation — the same authored-but-not-resolved
## split docs/electoral-systems.md makes for the election schedule.
var formation_method: String = ""
var censure_rule: String = ""
var head_of_government_title: String = ""

## Who holds the head-of-government office at game start. Equal to the national
## leader for nine of the ten; France is the exception, where the leader is the
## President and the Prime Minister is a separate person.
var head_of_government_name: String = ""

## The nation's own next scheduled election, real and sourced — see
## docs/electoral-systems.md. Authored, not imported: tools/import_data.py never
## reads or writes it, same class as fiscal below.
var election_system: String = ""
var election_next_year: int = 0
var election_next_month: int = 0
var election_threshold_pct: float = 0.0

## EU membership and European Parliament seat count. Empty/zero for a
## non-member — GBR and CHE simply have no reader for these, see
## docs/electoral-systems.md.
var eu_member: bool = false
var eu_ep_seats: int = 0

var debt_to_gdp_pct: float = 0.0
var tax_revenue_pct_gdp: float = 0.0

var population: int = 0
var gdp_eur_bn: float = 0.0
var unemployment_pct: float = 0.0
var sectors: Dictionary = {}


static func from_dict(d: Dictionary, filename: String, errors: Array[String]):
	var n := new()

	n.id = _extract_string(d, "id", filename, errors)
	if n.id != "" and not _id_regex.search(n.id):
		errors.append("%s: id '%s' must be three uppercase letters" % [filename, n.id])
	var stem := filename.get_basename()
	if n.id != "" and n.id != stem:
		errors.append("%s: id '%s' does not match filename" % [filename, n.id])

	n.nation_name = _extract_string(d, "name", filename, errors)
	n.geo_id = _extract_string(d, "geo_id", filename, errors)
	n.capital = _extract_string(d, "capital", filename, errors)
	n.playable = _extract_bool(d, "playable", filename, errors)

	var leader: Dictionary = _extract_dict(d, "leader", filename, errors)
	n.leader_name = _extract_string(leader, "name", filename, errors)
	n.leader_title = _extract_string(leader, "title", filename, errors)
	n.leader_party_id = _extract_string(leader, "party", filename, errors)

	var government: Dictionary = _extract_dict(d, "government", filename, errors)

	var legislative: Dictionary = _extract_dict(government, "legislative", filename, errors)
	n.term_years = _extract_int(legislative, "term_years", "government.legislative.term_years", filename, errors)
	_check_range_int(n.term_years, 1, 10, "government.legislative.term_years", filename, errors)
	n.assembly_seats = _extract_int(legislative, "assembly_seats", "government.legislative.assembly_seats", filename, errors)
	_check_range_int(n.assembly_seats, 1, 2000, "government.legislative.assembly_seats", filename, errors)
	n.chamber_name = _extract_string(legislative, "chamber", filename, errors)

	var election: Dictionary = _extract_dict(legislative, "election", filename, errors)
	n.election_system = _extract_string(election, "system", filename, errors)
	if n.election_system != "" and not KNOWN_ELECTION_SYSTEMS.has(n.election_system):
		errors.append("%s: government.legislative.election.system '%s' is not a recognised method" % [filename, n.election_system])
	var next: Dictionary = _extract_dict(election, "next", filename, errors)
	n.election_next_year = _extract_int(next, "year", "government.legislative.election.next.year", filename, errors)
	_check_range_int(n.election_next_year, 2026, 2100, "government.legislative.election.next.year", filename, errors)
	n.election_next_month = _extract_int(next, "month", "government.legislative.election.next.month", filename, errors)
	_check_range_int(n.election_next_month, 1, 12, "government.legislative.election.next.month", filename, errors)
	n.election_threshold_pct = _extract_float(election, "threshold_pct", "government.legislative.election.threshold_pct", filename, errors)
	_check_range_float(n.election_threshold_pct, 0.0, 20.0, "government.legislative.election.threshold_pct", filename, errors)

	# Optional by design: absent means the executive comes out of the chamber.
	# Present, it must be complete — a half-authored executive block is the
	# silent-wrong-term bug this validation exists to prevent.
	n.has_executive = government.has("executive")
	if n.has_executive:
		var executive: Dictionary = _extract_dict(government, "executive", filename, errors)
		n.executive_title = _extract_string(executive, "title", filename, errors)
		n.executive_term_years = _extract_int(executive, "term_years", "government.executive.term_years", filename, errors)
		_check_range_int(n.executive_term_years, 1, 10, "government.executive.term_years", filename, errors)
		var exec_next: Dictionary = _extract_dict(executive, "next", filename, errors)
		n.executive_next_year = _extract_int(exec_next, "year", "government.executive.next.year", filename, errors)
		_check_range_int(n.executive_next_year, 2026, 2100, "government.executive.next.year", filename, errors)
		n.executive_next_month = _extract_int(exec_next, "month", "government.executive.next.month", filename, errors)
		_check_range_int(n.executive_next_month, 1, 12, "government.executive.next.month", filename, errors)

	var formation: Dictionary = _extract_dict(government, "formation", filename, errors)
	n.formation_method = _extract_string(formation, "method", filename, errors)
	if n.formation_method != "" and not KNOWN_FORMATION_METHODS.has(n.formation_method):
		errors.append("%s: government.formation.method '%s' is not a recognised method" % [filename, n.formation_method])
	n.censure_rule = _extract_string(formation, "censure", filename, errors)
	if n.censure_rule != "" and not KNOWN_CENSURE_RULES.has(n.censure_rule):
		errors.append("%s: government.formation.censure '%s' is not a recognised rule" % [filename, n.censure_rule])
	n.head_of_government_title = _extract_string(formation, "head_of_government_title", filename, errors)
	n.head_of_government_name = _extract_string(formation, "head_of_government_name", filename, errors)

	var eu: Dictionary = _extract_dict(government, "eu", filename, errors)
	n.eu_member = _extract_bool(eu, "member", filename, errors)
	if n.eu_member:
		n.eu_ep_seats = _extract_int(eu, "ep_seats", "government.eu.ep_seats", filename, errors)
		_check_range_int(n.eu_ep_seats, 1, 200, "government.eu.ep_seats", filename, errors)

	var fiscal: Dictionary = _extract_dict(d, "fiscal", filename, errors)
	n.debt_to_gdp_pct = _extract_float(fiscal, "debt_to_gdp_pct", "fiscal.debt_to_gdp_pct", filename, errors)
	_check_range_float(n.debt_to_gdp_pct, 0.0, 400.0, "fiscal.debt_to_gdp_pct", filename, errors)
	n.tax_revenue_pct_gdp = _extract_float(fiscal, "tax_revenue_pct_gdp", "fiscal.tax_revenue_pct_gdp", filename, errors)
	_check_range_float(n.tax_revenue_pct_gdp, 0.0, 100.0, "fiscal.tax_revenue_pct_gdp", filename, errors)

	var imported: Dictionary = _extract_dict(d, "imported", filename, errors)
	for key in imported.keys():
		if not KNOWN_IMPORTED_KEYS.has(key):
			errors.append("%s: imported.%s is not a recognised field" % [filename, key])

	n.population = _extract_int(imported, "population", "imported.population", filename, errors)
	_check_range_int(n.population, 100_000, 2_000_000_000, "imported.population", filename, errors)

	n.gdp_eur_bn = _extract_float(imported, "gdp_eur_bn", "imported.gdp_eur_bn", filename, errors)
	_check_range_float(n.gdp_eur_bn, 0.0001, 100_000.0, "imported.gdp_eur_bn", filename, errors)

	n.unemployment_pct = _extract_float(imported, "unemployment_pct", "imported.unemployment_pct", filename, errors)
	_check_range_float(n.unemployment_pct, 0.0, 100.0, "imported.unemployment_pct", filename, errors)

	n.sectors = _extract_dict(imported, "sectors", filename, errors)
	_validate_sectors(n.sectors, filename, errors)

	return n


static func _validate_sectors(sectors: Dictionary, filename: String, errors: Array[String]) -> void:
	var keys := sectors.keys()
	keys.sort()
	var expected := KNOWN_SECTOR_KEYS.duplicate()
	expected.sort()
	if keys != expected:
		errors.append("%s: imported.sectors must have exactly keys %s, got %s" % [filename, expected, keys])
		return

	var total := 0.0
	for key in KNOWN_SECTOR_KEYS:
		var raw = sectors[key]
		if not (typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT):
			errors.append("%s: imported.sectors.%s is not numeric" % [filename, key])
			continue
		var value: float = raw
		if value < 0.0 or value > 1.0:
			errors.append("%s: imported.sectors.%s = %s out of range [0, 1]" % [filename, key, str(value)])
		total += value

	if absf(total - 1.0) > 0.001:
		errors.append("%s: imported.sectors sums to %s, expected 1.0" % [filename, str(total)])


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


static func _extract_int(d: Dictionary, key: String, path: String, filename: String, errors: Array[String]) -> int:
	if not d.has(key) or not (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT):
		errors.append("%s: missing or invalid numeric field '%s'" % [filename, path])
		return 0
	return int(d[key])


static func _extract_float(d: Dictionary, key: String, path: String, filename: String, errors: Array[String]) -> float:
	if not d.has(key) or not (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT):
		errors.append("%s: missing or invalid numeric field '%s'" % [filename, path])
		return 0.0
	return float(d[key])


static func _extract_dict(d: Dictionary, key: String, filename: String, errors: Array[String]) -> Dictionary:
	if not d.has(key) or typeof(d[key]) != TYPE_DICTIONARY:
		errors.append("%s: missing or invalid object field '%s'" % [filename, key])
		return {}
	return d[key]


static func _check_range_int(value: int, min_v: int, max_v: int, path: String, filename: String, errors: Array[String]) -> void:
	if value < min_v or value > max_v:
		errors.append("%s: %s = %d out of range [%d, %d]" % [filename, path, value, min_v, max_v])


static func _check_range_float(value: float, min_v: float, max_v: float, path: String, filename: String, errors: Array[String]) -> void:
	if value < min_v or value > max_v:
		errors.append("%s: %s = %s out of range [%s, %s]" % [filename, path, str(value), str(min_v), str(max_v)])
