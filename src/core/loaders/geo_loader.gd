extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. The map geometry and the roster-wide checks that need every nation in scope (neighbours, the roster tripwire).
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too), every register lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim (now <ThisLoader>.<name>), its members read
## through `loader.`.


## The roster tripwire's number (GeoLoader.validate_cross_file). One constant so the
## V4.11 tranches move it in one place.
const ROSTER_SIZE := 41
const CommoditiesLoader = preload("res://src/core/loaders/commodities_loader.gd")
const PoliticsLoader = preload("res://src/core/loaders/politics_loader.gd")


## A land border is mutual or it is not a land border. Nation.gd already checked
## each list's shape against its own file; only here is the whole roster in
## scope, so only here can "FRA lists DEU but DEU does not list FRA" be caught.
##
## This is what lets src/sim/diplomacy.gd derive one resting value per unordered
## pair without asking which nation's file it should believe -- the symmetric
## pair key of src/core/relations.gd would otherwise be resting on an asymmetric
## input. See docs/diplomacy-model.md.
static func validate_neighbours(loader) -> void:
	for id in loader.nations.keys():
		var n = loader.nations[id]
		for other_id in n.neighbours:
			if not loader.nations.has(other_id):
				loader.errors.append("%s.json: government.neighbours names '%s', which is not a loaded nation" % [id, other_id])
				continue
			if not loader.nations[other_id].neighbours.has(id):
				loader.errors.append("%s.json: government.neighbours lists '%s', but %s.json does not list '%s' back" % [
					id, other_id, other_id, id
				])


static func validate_cross_file(loader, geo_path: String, world_path: String) -> void:
	# V3.3: the roster is EU-27 plus the two non-EU neighbours, so the pin the
	# ten-nation era carried moves to 29. A tripwire, not a limit -- a roster
	# change edits this number beside the data it describes. V4.11 grows it by
	# the neighbourhood's twelve, simulated and not playable.
	if loader.nations.size() != ROSTER_SIZE:
		loader.errors.append("expected %d nations, loaded %d" % [ROSTER_SIZE, loader.nations.size()])

	# At least one, not exactly one -- V1.2a made a second nation playable, and
	# a third later is a one-flag data edit, not a code change. See ROADMAP.md (retired 2026-10-05 -- the tier docs carry the build order now).
	var playable_count := 0
	for n in loader.nations.values():
		if n.playable:
			playable_count += 1
	if playable_count < 1:
		loader.errors.append("expected at least 1 playable nation, found %d" % playable_count)

	loader.label_points.clear()
	var geo_ids := load_geo(loader, geo_path, loader.geo_features)
	for n in loader.nations.values():
		if not geo_ids.has(n.geo_id):
			loader.errors.append("%s.json: geo_id '%s' has no matching feature in %s" % [n.id, n.geo_id, geo_path])

	load_geo(loader, world_path, loader.world_features)
	CommoditiesLoader.validate_outlines(loader)

	for id in loader.nations.keys():
		var n = loader.nations[id]
		var roster: Array = loader.parties.get(id, [])
		var found := false
		for party in roster:
			if party.id == n.leader_party_id:
				found = true
				break
		if not found:
			loader.errors.append("%s.json: leader.party '%s' does not match any party in data/parties/%s.json" % [id, n.leader_party_id, id])


		PoliticsLoader.validate_political_system(loader, n)


## Reads one GeoJSON FeatureCollection into `into`, and every feature's label
## anchor into the shared label_points. Parameterised at U5b so europe.geojson
## and world.geojson go through exactly the same parser and the same error
## handling -- a malformed world file is an errors.append(), not a crash, the
## same as a malformed roster file has always been.
static func load_geo(loader, geo_path: String, into: Dictionary, keep_rings := false, rings_into: Dictionary = {}) -> Array:
	var ids: Array = []
	into.clear()
	rings_into.clear()
	var text := FileAccess.get_file_as_string(geo_path)
	if text.is_empty():
		loader.errors.append("%s: could not read file" % geo_path)
		return ids

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("features"):
		loader.errors.append("%s: invalid GeoJSON" % geo_path)
		return ids

	for feature in parsed["features"]:
		var props: Dictionary = feature.get("properties", {})
		var id: String = props["id"]
		ids.append(id)

		if props.has("label_lon") and props.has("label_lat"):
			loader.label_points[id] = Vector2(float(props["label_lon"]), float(props["label_lat"]))

		var geometry: Dictionary = feature.get("geometry", {})
		var polygons: Array = []
		var full_polygons: Array = []
		match geometry.get("type", ""):
			"MultiPolygon":
				for polygon_coords in geometry.get("coordinates", []):
					polygons.append(outer_ring(loader, polygon_coords))
					if keep_rings:
						full_polygons.append(all_rings(loader, polygon_coords))
			"Polygon":
				polygons.append(outer_ring(loader, geometry.get("coordinates", [])))
				if keep_rings:
					full_polygons.append(all_rings(loader, geometry.get("coordinates", [])))
			_:
				loader.errors.append("%s: feature '%s' has unsupported geometry type '%s'" % [geo_path, id, geometry.get("type", "")])
		into[id] = polygons
		if keep_rings:
			rings_into[id] = full_polygons
	return ids


## The first ring of a Polygon's coordinate array is the outer boundary; any
## further rings are holes, which S8's renderer and hit-test both ignore.
static func outer_ring(loader, polygon_coords: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	if polygon_coords.is_empty():
		return ring
	for point in polygon_coords[0]:
		ring.append(Vector2(point[0], point[1]))
	return ring


## Every ring of one polygon, outer first, holes after -- V2.7. Kept beside
## GeoLoader.outer_ring() because the pair states the rule twice on purpose: the renderer
## drops the holes and the siting cast needs them, and only reading this file once
## keeps the two from ever disagreeing about what the geometry says.
static func all_rings(loader, polygon_coords: Array) -> Array:
	var rings: Array = []
	for ring_coords in polygon_coords:
		var ring := PackedVector2Array()
		for point in ring_coords:
			ring.append(Vector2(point[0], point[1]))
		rings.append(ring)
	return rings
