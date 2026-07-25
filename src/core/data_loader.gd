class_name DataLoader
extends RefCounted

## Loads and validates every data/nations/*.json file. Always validates,
## always fails loudly — see docs/data-architecture.md.

const Nation = preload("res://src/core/nation.gd")
const Party = preload("res://src/core/party.gd")
const C = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/election_constants.gd")

const MIN_PARTIES := 4
const MAX_PARTIES := 6

const MAX_TAX_RATE_PCT := 100.0
const MAX_SPENDING_PCT_GDP := 100.0

const EU = preload("res://src/core/eu.gd")

var nations: Dictionary = {}  # String id -> Nation
var parties: Dictionary = {}  # String id -> Array[Party]
var policy_defaults: Dictionary = {}
var eu: EU = null
var errors: Array[String] = []


func load_all(nations_dir := "res://data/nations", geo_path := "res://data/geo/europe.geojson", parties_dir := "res://data/parties", policy_path := "res://data/policy_defaults.json", eu_path := "res://data/eu_parliament.json") -> void:
	nations.clear()
	parties.clear()
	policy_defaults.clear()
	errors = []

	var da := DirAccess.open(nations_dir)
	if da == null:
		errors.append("%s: directory not found" % nations_dir)
		return

	var filenames: Array[String] = []
	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if not da.current_is_dir() and file_name.ends_with(".json"):
			filenames.append(file_name)
		file_name = da.get_next()
	da.list_dir_end()
	filenames.sort()

	for fname in filenames:
		var path := nations_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s: invalid JSON" % fname)
			continue

		var per_file_errors: Array[String] = []
		var nation = Nation.from_dict(parsed, fname, per_file_errors)
		errors.append_array(per_file_errors)
		if nation.id != "":
			nations[nation.id] = nation

	for id in nations.keys():
		_load_parties(id, parties_dir)

	_load_policy_defaults(policy_path)

	eu = EU.new()
	eu.load(eu_path)
	errors.append_array(eu.errors)

	_validate_cross_file(geo_path)


## Starting tax rates and spending split, shared by every nation. Static content
## like the nation files, so it gets the same treatment: parsed once at startup,
## validated loudly, never mutated. See docs/economy-model.md.
func _load_policy_defaults(policy_path: String) -> void:
	var text := FileAccess.get_file_as_string(policy_path)
	if text.is_empty():
		errors.append("%s: could not read file" % policy_path)
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("%s: invalid JSON" % policy_path)
		return

	var fname := policy_path.get_file()
	policy_defaults = parsed

	var rates := _extract_dict(parsed, "tax_rates_pct", fname)
	for key in C.TAX_KEYS:
		_check_number(rates, key, "tax_rates_pct.%s" % key, 0.0, MAX_TAX_RATE_PCT, fname)

	var spending := _extract_dict(parsed, "spending_pct_gdp", fname)
	for key in C.SPENDING_KEYS:
		_check_number(spending, key, "spending_pct_gdp.%s" % key, 0.0, MAX_SPENDING_PCT_GDP, fname)

	_check_number(parsed, "other_spending_pct_gdp", "other_spending_pct_gdp", 0.0, MAX_SPENDING_PCT_GDP, fname)


func _extract_dict(d: Dictionary, key: String, filename: String) -> Dictionary:
	if not d.has(key) or typeof(d[key]) != TYPE_DICTIONARY:
		errors.append("%s: missing or invalid object field '%s'" % [filename, key])
		return {}
	return d[key]


func _check_number(d: Dictionary, key: String, path: String, min_v: float, max_v: float, filename: String) -> void:
	if not d.has(key) or not (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT):
		errors.append("%s: missing or invalid numeric field '%s'" % [filename, path])
		return
	var value := float(d[key])
	if value < min_v or value > max_v:
		errors.append("%s: %s = %s out of range [%s, %s]" % [filename, path, str(value), str(min_v), str(max_v)])


func _load_parties(nation_id: String, parties_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := parties_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: could not read file" % path)
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("parties")) != TYPE_ARRAY:
		errors.append("%s: invalid party file, expected {\"parties\": [...]}" % fname)
		return

	var raw_list: Array = parsed["parties"]
	var parsed_parties: Array[Party] = []
	var per_file_errors: Array[String] = []
	var seen_ids := {}
	var total := 0.0

	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			per_file_errors.append("%s: parties[%d] is not an object" % [fname, i])
			continue
		var party = Party.from_dict(entry, i, fname, per_file_errors)
		if party.id != "":
			if seen_ids.has(party.id):
				per_file_errors.append("%s: duplicate party id '%s'" % [fname, party.id])
			seen_ids[party.id] = true
		total += party.seat_share
		parsed_parties.append(party)

	if parsed_parties.size() < MIN_PARTIES or parsed_parties.size() > MAX_PARTIES:
		per_file_errors.append("%s: expected %d-%d parties, got %d" % [fname, MIN_PARTIES, MAX_PARTIES, parsed_parties.size()])

	if absf(total - 1.0) > 0.001:
		per_file_errors.append("%s: seat_share sums to %s, expected 1.0" % [fname, str(total)])

	for party in parsed_parties:
		if party.ideology_slot != "" and not K.SLOT_KEYS.has(party.ideology_slot):
			per_file_errors.append("%s: ideology_slot '%s' has no position in election_constants.SLOT_POSITION" % [fname, party.ideology_slot])

	errors.append_array(per_file_errors)
	parties[nation_id] = parsed_parties


func _validate_cross_file(geo_path: String) -> void:
	if nations.size() != 10:
		errors.append("expected 10 nations, loaded %d" % nations.size())

	var playable_count := 0
	for n in nations.values():
		if n.playable:
			playable_count += 1
	if playable_count != 1:
		errors.append("expected exactly 1 playable nation, found %d" % playable_count)

	var geo_ids := _load_geo_ids(geo_path)
	for n in nations.values():
		if not geo_ids.has(n.geo_id):
			errors.append("%s.json: geo_id '%s' has no matching feature in %s" % [n.id, n.geo_id, geo_path])

	for id in nations.keys():
		var n = nations[id]
		var roster: Array = parties.get(id, [])
		var found := false
		for party in roster:
			if party.id == n.leader_party_id:
				found = true
				break
		if not found:
			errors.append("%s.json: leader.party '%s' does not match any party in data/parties/%s.json" % [id, n.leader_party_id, id])

		if n.eu_member != eu.is_member(id):
			errors.append("%s.json: government.eu.member=%s but data/eu_parliament.json members %s '%s'" % [
				id, n.eu_member, "has" if eu.is_member(id) else "lacks", id
			])
		elif n.eu_member and n.eu_ep_seats != eu.ep_seats(id):
			errors.append("%s.json: government.eu.ep_seats %d does not match data/eu_parliament.json's %d for '%s'" % [
				id, n.eu_ep_seats, eu.ep_seats(id), id
			])


func _load_geo_ids(geo_path: String) -> Array:
	var ids: Array = []
	var text := FileAccess.get_file_as_string(geo_path)
	if text.is_empty():
		errors.append("%s: could not read file" % geo_path)
		return ids

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("features"):
		errors.append("%s: invalid GeoJSON" % geo_path)
		return ids

	for feature in parsed["features"]:
		ids.append(feature["properties"]["id"])
	return ids
