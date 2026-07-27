class_name DataLoader
extends RefCounted

## Loads and validates every data/nations/*.json file. Always validates,
## always fails loudly — see docs/data-architecture.md.

const Nation = preload("res://src/core/nation.gd")
const Party = preload("res://src/core/party.gd")
const Law = preload("res://src/core/law.gd")
const PoliticalSystem = preload("res://src/core/political_system.gd")
const C = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

const MIN_PARTIES := 4
const MAX_PARTIES := 6

const EU = preload("res://src/core/eu.gd")

var nations: Dictionary = {}  # String id -> Nation
var parties: Dictionary = {}  # String id -> Array[Party]
var laws: Array[Law] = []
var political_systems: Dictionary = {}  # String id -> PoliticalSystem
var eu: EU = null
var errors: Array[String] = []

## geo feature id -> Array[PackedVector2Array]. One entry per polygon in the
## feature's MultiPolygon; each PackedVector2Array is that polygon's outer ring
## only, raw (lon, lat) degrees -- holes are not kept, S8's map only needs
## recognisable borders and a click hit-test, not exact enclaves. Read once at
## startup by _load_geo(), same as the id list _validate_cross_file already
## cross-checks.
var geo_features: Dictionary = {}


func load_all(nations_dir := "res://data/nations", geo_path := "res://data/geo/europe.geojson", parties_dir := "res://data/parties", eu_path := "res://data/eu_parliament.json", laws_dir := "res://data/laws", political_systems_dir := "res://data/political-systems") -> void:
	nations.clear()
	parties.clear()
	laws.clear()
	political_systems.clear()
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

	_load_laws(laws_dir)
	_load_political_systems(political_systems_dir)

	eu = EU.new()
	eu.load(eu_path)
	errors.append_array(eu.errors)

	_validate_cross_file(geo_path)


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

		# A cordon naming a party that does not exist would silently exclude
		# nothing, which is the same class of quiet failure the slot check above
		# exists to catch.
		for other in party.excluded_partners:
			if not seen_ids.has(other):
				per_file_errors.append("%s: party '%s' excludes '%s', which is not a party in this nation" % [fname, party.id, other])
			elif other == party.id:
				per_file_errors.append("%s: party '%s' excludes itself" % [fname, party.id])

	errors.append_array(per_file_errors)
	parties[nation_id] = parsed_parties


## Reads every data/laws/*.json file -- each {"laws": [...]}, grouped by theme,
## same shape as data/parties/*.json. See docs/legislature-model.md.
func _load_laws(laws_dir: String) -> void:
	var da := DirAccess.open(laws_dir)
	if da == null:
		errors.append("%s: directory not found" % laws_dir)
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

	var seen_ids := {}
	for fname in filenames:
		var path := laws_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("laws")) != TYPE_ARRAY:
			errors.append("%s: invalid law file, expected {\"laws\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["laws"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: laws[%d] is not an object" % [fname, i])
				continue
			var law = Law.from_dict(entry, fname, errors, C.TAX_KEYS, C.SPENDING_KEYS, OpinionK.BLOC_KEYS)
			if law.id != "":
				if seen_ids.has(law.id):
					errors.append("%s: duplicate law id '%s'" % [fname, law.id])
				seen_ids[law.id] = true
			laws.append(law)


## Reads every data/political-systems/*.json file. See docs/political-systems.md
## and political_system.gd's own header for why a template is a constraint, not
## a defaults table -- the constraint itself is enforced below, in
## _validate_cross_file(), against every nation that names one.
func _load_political_systems(political_systems_dir: String) -> void:
	var da := DirAccess.open(political_systems_dir)
	if da == null:
		errors.append("%s: directory not found" % political_systems_dir)
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
		var path := political_systems_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s: invalid JSON" % fname)
			continue

		var per_file_errors: Array[String] = []
		var system = PoliticalSystem.from_dict(parsed, fname, per_file_errors)
		errors.append_array(per_file_errors)
		if system.id != "":
			political_systems[system.id] = system


func _validate_cross_file(geo_path: String) -> void:
	if nations.size() != 10:
		errors.append("expected 10 nations, loaded %d" % nations.size())

	# At least one, not exactly one -- V1.2a made a second nation playable, and
	# a third later is a one-flag data edit, not a code change. See ROADMAP.md.
	var playable_count := 0
	for n in nations.values():
		if n.playable:
			playable_count += 1
	if playable_count < 1:
		errors.append("expected at least 1 playable nation, found %d" % playable_count)

	var geo_ids := _load_geo(geo_path)
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

		_validate_political_system(n)


## The template is a constraint, not a defaults table -- see political_system.gd.
## A nation's formation/censure/dissolution rule must fall inside the set its
## own template declares, and a term limit may only be authored where the
## template permits one. Failing loudly here is what makes the template
## load-bearing rather than decorative.
func _validate_political_system(n) -> void:
	if not political_systems.has(n.system_id):
		errors.append("%s.json: government.system '%s' names no file in data/political-systems/" % [n.id, n.system_id])
		return

	var system: PoliticalSystem = political_systems[n.system_id]
	if not system.allowed_formation_methods.has(n.formation_method):
		errors.append("%s.json: government.formation.method '%s' is not permitted by system '%s'" % [n.id, n.formation_method, n.system_id])
	if not system.allowed_censure_rules.has(n.censure_rule):
		errors.append("%s.json: government.formation.censure '%s' is not permitted by system '%s'" % [n.id, n.censure_rule, n.system_id])
	if not system.allowed_dissolution_rules.has(n.dissolution_rule):
		errors.append("%s.json: government.legislative.dissolution.rule '%s' is not permitted by system '%s'" % [n.id, n.dissolution_rule, n.system_id])
	if n.term_limit > 0 and not system.permits_term_limit:
		errors.append("%s.json: government.term_limit %d is set but system '%s' does not permit a term limit" % [n.id, n.term_limit, n.system_id])


func _load_geo(geo_path: String) -> Array:
	var ids: Array = []
	geo_features.clear()
	var text := FileAccess.get_file_as_string(geo_path)
	if text.is_empty():
		errors.append("%s: could not read file" % geo_path)
		return ids

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("features"):
		errors.append("%s: invalid GeoJSON" % geo_path)
		return ids

	for feature in parsed["features"]:
		var id: String = feature["properties"]["id"]
		ids.append(id)

		var geometry: Dictionary = feature.get("geometry", {})
		var polygons: Array = []
		match geometry.get("type", ""):
			"MultiPolygon":
				for polygon_coords in geometry.get("coordinates", []):
					polygons.append(_outer_ring(polygon_coords))
			"Polygon":
				polygons.append(_outer_ring(geometry.get("coordinates", [])))
			_:
				errors.append("%s: feature '%s' has unsupported geometry type '%s'" % [geo_path, id, geometry.get("type", "")])
		geo_features[id] = polygons
	return ids


## The first ring of a Polygon's coordinate array is the outer boundary; any
## further rings are holes, which S8's renderer and hit-test both ignore.
func _outer_ring(polygon_coords: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	if polygon_coords.is_empty():
		return ring
	for point in polygon_coords[0]:
		ring.append(Vector2(point[0], point[1]))
	return ring
