class_name Region
extends RefCounted

## Typed, validated in-memory representation of one entry in a
## data/regions/*.json file, plus the handful of reads over the register that
## every caller would otherwise write for itself. See docs/geography-model.md.
##
## A REGION IS TO A NATION WHAT A FIRM IS TO ITS SECTOR, and that is
## docs/tiers/v2.md's own call rather than an analogy reached for afterwards.
## `share` is of the nation's population, the named regions sum to at most 1.0,
## and the remainder is the unnamed residual -- extra-regio output and the
## overseas territories the map's bounding box has dropped since S8. One level
## down, a city's share is of its region and the remainder is rural. Two
## partitions, two residuals, neither of them stored: a residual that is
## `1.0 - sum` cannot drift from the thing it is the remainder of.
##
## THE NUTS LEVEL IS NOWHERE IN THIS FILE, and that is a rule rather than an
## omission. France is imported at NUTS 1 and Italy at NUTS 2 because NUTS 2 for
## France is the regions abolished in 2016 and NUTS 1 for Italy is five
## statistical macro-areas -- a decision recorded in tools/import_data.py's
## REGION_LEVEL and in each file's `_source` line. src/ never learns a level
## exists, which is CLAUDE.md's first rule: content lives in data, and a nation
## that behaves differently has a field saying so.
##
## There is no src/core/geography.gd. U6b deleted src/core/people.gd before
## writing it, on the reasoning that a name lookup is a dictionary read and every
## panel already holds the loader; the same is true here, so the four queries
## below live on the type they query.

const City = preload("res://src/core/city.gd")


var id: String = ""

## `region_name`, not `name` -- city.gd's dodge, for the same reason.
var region_name: String = ""

## Share of the NATION's population, in (0, 1].
var share: float = 0.0

## In authored order, which the importer writes descending by population, so a
## panel that prints them in file order prints a ranking.
var cities: Array[City] = []


static func from_dict(d: Dictionary, index: int, filename: String, errors: Array[String]):
	var r := new()
	var path := "regions[%d]" % index

	if not d.has("id") or typeof(d["id"]) != TYPE_STRING or d["id"] == "":
		errors.append("%s: %s missing or invalid string field 'id'" % [filename, path])
	else:
		r.id = d["id"]

	if not d.has("name") or typeof(d["name"]) != TYPE_STRING or d["name"] == "":
		errors.append("%s: %s missing or invalid string field 'name'" % [filename, path])
	else:
		r.region_name = d["name"]

	if not d.has("share") or not (typeof(d["share"]) == TYPE_INT or typeof(d["share"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or non-numeric field 'share'" % [filename, path])
	else:
		r.share = float(d["share"])
		if r.share <= 0.0 or r.share > 1.0:
			errors.append("%s: %s share = %s must be in (0, 1]" % [filename, path, str(r.share)])

	var raw = d.get("cities", null)
	if typeof(raw) != TYPE_ARRAY or (raw as Array).is_empty():
		# Empty is an error rather than a legal thinner region: docs/tiers/v2.md
		# section 2 defines a region as "a main city plus the sum of the smaller
		# cities under it", and the importer's top-up rule names each region's
		# largest place whatever the population cut is. A region with no city is a
		# join that silently failed.
		errors.append("%s: %s missing or empty array field 'cities'" % [filename, path])
	else:
		var seen := {}
		var total := 0.0
		for i in (raw as Array).size():
			var entry = raw[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: %s.cities[%d] is not an object" % [filename, path, i])
				continue
			var city = City.from_dict(entry, r.id, i, filename, errors)
			if seen.has(city.id):
				errors.append("%s: %s has two cities with id '%s'" % [filename, path, city.id])
			seen[city.id] = true
			total += city.share
			r.cities.append(city)

		# The invariant the whole register rests on, checked where the file is read
		# rather than only where it is written -- and it is not hypothetical. The
		# raw GeoNames data puts London's twenty boroughs alongside London and
		# Brussels' communes alongside Brussels, which took those two regions to
		# 1.325 and 1.285 of themselves before tools/import_data.py's fit rule.
		if total > 1.0 + 1e-9:
			errors.append("%s: %s named cities sum to %s of their region -- a region cannot be more than fully named" % [
				filename, path, str(total),
			])

	for key in d.keys():
		if key != "id" and key != "name" and key != "share" and key != "cities":
			errors.append("%s: %s has unrecognised field '%s' -- a region carries no GDP, unemployment or sector mix until docs/tiers/v2.md section 5" % [
				filename, path, key,
			])

	return r


## What the region does NOT name: rural and unnamed towns, as a share of the
## region. Derived rather than stored, so it cannot disagree with the cities
## above it.
func city_residual() -> float:
	var total := 0.0
	for c in cities:
		total += c.share
	return maxf(0.0, 1.0 - total)


## What the nation does not name: extra-regio and the overseas regions the map's
## bounding box drops. `regions` is one nation's array, in loader order.
static func national_residual(regions: Array) -> float:
	var total := 0.0
	for r in regions:
		total += r.share
	return maxf(0.0, 1.0 - total)


## The region holding this city, or null. Linear over at most 21 regions and 129
## cities, which is why there is no index: building one would be a second record
## of a relationship the file already states.
static func region_of_city(regions: Array, city_id: String):
	for r in regions:
		for c in r.cities:
			if c.id == city_id:
				return r
	return null


static func find_city(regions: Array, city_id: String):
	for r in regions:
		for c in r.cities:
			if c.id == city_id:
				return c
	return null
