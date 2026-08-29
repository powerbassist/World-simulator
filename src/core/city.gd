class_name City
extends RefCounted

## Typed, validated in-memory representation of one entry in a region's `cities`
## array. See docs/geography-model.md.
##
## FOUR FIELDS, AND WHAT IS ABSENT IS THE DESIGN -- src/core/person.gd's argument
## one tier on. A city carries no unemployment, no sector mix, no growth and no
## head COUNT: `share` is of its region's population, and the head count is that
## share read through a population the nation already carries. Authoring a
## population here would be one quantity written twice, which is the redundancy
## tools/coercion_probe.gd cut when it deleted `tariff_rate_pct`.
##
## The consequence worth naming: there is nothing on this class a mechanism could
## hang off, so V2.2 ships a register and no behaviour. docs/tiers/v2.md section 5
## is the block that makes a city load-bearing, section 6 the one that moves people
## between them, and each arrives with the field it needs rather than finding it
## pre-authored and inert.
##
## `lonlat` is the one field nothing in src/sim/ will ever read. It is here because
## V2.2b draws these and U6c's rule -- *a lon/lat nothing reads carries no
## information* -- is satisfied by a click rather than by a simulation.


var id: String = ""

## `city_name`, not `name` -- company.gd, person.gd, party.gd and nation.gd all
## make the same dodge, because `name` is a Node property.
var city_name: String = ""

## Share of its REGION's population, in (0, 1]. The named cities of one region sum
## to at most 1.0 and the remainder is rural and unnamed towns, which is exactly
## what company.gd's `share` does one level down. Exactly 1.0 is legal and means a
## city-state: Hamburg, Ceuta and Melilla each are their region.
var share: float = 0.0

var lonlat: Vector2 = Vector2.ZERO


static func from_dict(d: Dictionary, region_id: String, index: int, filename: String, errors: Array[String]):
	var c := new()
	var path := "%s.cities[%d]" % [region_id, index]

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: %s missing or invalid string field 'id'" % [filename, path])
	else:
		c.id = d["id"]
		# A city id is read BARE -- off a firm's `city`, and off whatever V2.5 and
		# V2.6 point at one -- so it has to be self-describing and globally unique
		# the way a person id is. Prefixing with the region's own NUTS code gives
		# that for free, since a NUTS code is unique across Europe.
		if not c.id.begins_with(region_id + "_"):
			errors.append("%s: %s id '%s' must begin with '%s_'" % [
				filename, path, c.id, region_id,
			])

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, path])
	else:
		c.city_name = d["name"]

	if not d.has("share") or not (typeof(d["share"]) == TYPE_INT or typeof(d["share"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or non-numeric field 'share'" % [filename, path])
	else:
		c.share = float(d["share"])
		if c.share <= 0.0 or c.share > 1.0:
			errors.append("%s: %s share = %s must be in (0, 1]" % [filename, path, str(c.share)])

	var lonlat = d.get("lonlat", null)
	if typeof(lonlat) != TYPE_ARRAY or lonlat.size() != 2:
		errors.append("%s: %s missing or invalid field 'lonlat' -- expected [lon, lat]" % [filename, path])
	else:
		var lon = lonlat[0]
		var lat = lonlat[1]
		var numeric := (typeof(lon) == TYPE_INT or typeof(lon) == TYPE_FLOAT) \
			and (typeof(lat) == TYPE_INT or typeof(lat) == TYPE_FLOAT)
		if not numeric or absf(float(lon)) > 180.0 or absf(float(lat)) > 90.0:
			errors.append("%s: %s lonlat = [%s, %s] is not a lon/lat" % [
				filename, path, str(lon), str(lat),
			])
		else:
			c.lonlat = Vector2(float(lon), float(lat))

	for key in d.keys():
		if key != "id" and key != "name" and key != "share" and key != "lonlat":
			errors.append("%s: %s has unrecognised field '%s' -- a city's population is its share read through its region, and it carries no economy of its own until docs/tiers/v2.md section 5" % [
				filename, path, key,
			])

	return c
