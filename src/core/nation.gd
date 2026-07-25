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

static var _id_regex := RegEx.create_from_string("^[A-Z]{3}$")

var id: String = ""
var nation_name: String = ""
var geo_id: String = ""
var capital: String = ""
var playable: bool = false

var term_years: int = 0
var assembly_seats: int = 0

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

	var government: Dictionary = _extract_dict(d, "government", filename, errors)
	n.term_years = _extract_int(government, "term_years", "government.term_years", filename, errors)
	_check_range_int(n.term_years, 1, 10, "government.term_years", filename, errors)
	n.assembly_seats = _extract_int(government, "assembly_seats", "government.assembly_seats", filename, errors)
	_check_range_int(n.assembly_seats, 1, 2000, "government.assembly_seats", filename, errors)

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
