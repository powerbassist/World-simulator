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

## Share of the NATION's GDP, in (0, 1]. V2.5.
##
## A SECOND PARTITION OF THE SAME NATION, not a second reading of the first, and the
## pair is the whole point: `share` is people and this is output, so `gdp_share /
## share` is a region's GDP per head against the national average -- a quantity
## nobody authored and the one the Region panel leads with. The residual is
## extra-regio output, which is what `<CC>ZZ` holds and why it was never in the
## roster.
var gdp_share: float = 0.0

## The region's unemployment rate over its nation's. Normalised at import so the
## population-weighted mean over the named regions is exactly 1.0, which is what
## makes src/sim/regions.gd's read a DECOMPOSITION of the national figure rather
## than a second opinion about it.
var unemployment_rel: float = 1.0

## agriculture / industry / services, summing to exactly 1.0 -- economy_constants
## .SECTOR_TREND's own three keys, so a region's trend is computed by the same
## expression as a nation's and no fourth sector can arrive here without arriving
## there. Unlike the two shares above this is NOT a partition of the nation: it is a
## partition of the region, which is why its residual is zero rather than unnamed.
var sector_mix: Dictionary = {}

## Crude rate of natural change -- births minus deaths per head, per cent per year,
## signed. V2.6c. CONTENT, not live state: the mean over the nation's live shares is
## taken in src/sim/natural_change.gd each month, so what this field carries is the
## measured differential and the sim's anchor does the rest. Britain carries 0.0
## everywhere -- UKM publishes no rates in the dataset family, and a differential
## mixing measured and invented rates invents flows -- which is a bound the model
## doc records, not a figure.
var natural_change_pct: float = 0.0


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

	if not d.has("gdp_share") or not (typeof(d["gdp_share"]) == TYPE_INT or typeof(d["gdp_share"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or non-numeric field 'gdp_share'" % [filename, path])
	else:
		r.gdp_share = float(d["gdp_share"])
		if r.gdp_share <= 0.0 or r.gdp_share > 1.0:
			errors.append("%s: %s gdp_share = %s must be in (0, 1]" % [filename, path, str(r.gdp_share)])

	if not d.has("unemployment_rel") or not (typeof(d["unemployment_rel"]) == TYPE_INT or typeof(d["unemployment_rel"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or non-numeric field 'unemployment_rel'" % [filename, path])
	else:
		r.unemployment_rel = float(d["unemployment_rel"])
		if r.unemployment_rel <= 0.0 or r.unemployment_rel > 5.0:
			errors.append("%s: %s unemployment_rel = %s must be in (0, 5]" % [filename, path, str(r.unemployment_rel)])

	var mix = d.get("sector_mix", null)
	if typeof(mix) != TYPE_DICTIONARY:
		errors.append("%s: %s missing or invalid field 'sector_mix'" % [filename, path])
	else:
		var mix_total: float = 0.0
		for key in ["agriculture", "industry", "services"]:
			if not (mix as Dictionary).has(key) or not (typeof(mix[key]) == TYPE_INT or typeof(mix[key]) == TYPE_FLOAT):
				errors.append("%s: %s sector_mix missing or non-numeric '%s'" % [filename, path, key])
				continue
			mix_total += float(mix[key])
			r.sector_mix[key] = float(mix[key])
		for key in (mix as Dictionary).keys():
			if key != "agriculture" and key != "industry" and key != "services":
				errors.append("%s: %s sector_mix has unrecognised sector '%s' -- the three are economy_constants.SECTOR_TREND's own keys" % [filename, path, key])
		# A partition of the region, so it closes exactly rather than leaving a
		# residual. The tolerance is float noise on three six-decimal numbers, not
		# a licence for a mix that nearly adds up.
		if r.sector_mix.size() == 3 and absf(mix_total - 1.0) > 0.000001:
			errors.append("%s: %s sector_mix sums to %s, not 1.0" % [filename, path, str(mix_total)])

	# REQUIRED, not defaulted: a region without the field is a register imported
	# before V2.6c or a hand edit, and silence would read as "this region's births
	# exactly offset its deaths" -- a confident claim nobody measured. The absent
	# figure is an error, the register's own rule for data/regions/.
	if not d.has("natural_change_pct") or not (typeof(d["natural_change_pct"]) == TYPE_INT or typeof(d["natural_change_pct"]) == TYPE_FLOAT):
		errors.append("%s: %s missing or non-numeric field 'natural_change_pct'" % [filename, path])
	else:
		r.natural_change_pct = float(d["natural_change_pct"])
		# Signed and per-head: the roster's measured span is +0.85 (Murcia) to
		# -0.82 (Campania's interior) and a natural rate outside plus-or-minus two
		# per cent has no measured precedent, so it is a mistyped digit rather than
		# demography.
		if absf(r.natural_change_pct) > 2.0:
			errors.append("%s: %s natural_change_pct = %s is outside plus-or-minus 2 %%/yr -- no measured rate in the roster approaches this" % [
				filename, path, str(r.natural_change_pct),
			])

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
		if key != "id" and key != "name" and key != "share" and key != "cities" \
			and key != "gdp_share" and key != "unemployment_rel" and key != "sector_mix" \
			and key != "natural_change_pct":
			errors.append("%s: %s has unrecognised field '%s' -- a region carries a population share, a GDP share, an unemployment ratio, a sector mix and a natural-change rate, and nothing else; a quantity that MOVES belongs on NationState, not here" % [
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


## What the nation's OUTPUT does not name: extra-regio -- offshore, embassies, ships.
## Derived rather than stored, for national_residual()'s reason one quantity over.
static func national_gdp_residual(regions: Array) -> float:
	var total: float = 0.0
	for r in regions:
		total += r.gdp_share
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
