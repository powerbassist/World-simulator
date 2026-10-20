extends RefCounted

## travel_days()'s geography, moved out of diplomacy.gd verbatim at V5.1-0a so
## that file could take its month in units without growing past its size
## baseline (V5.0c's diplomacy_verbs.gd precedent). Pure reads of the loader; no
## state, no sim module preloaded.

## A nation's capital as a lon/lat, or null. The register keys cities by region,
## so this scans the nation's own cities for the one named nation.capital — a
## per-nation scan over a handful of regions, called once at booking time.
## Variant rather than Vector2 because null is the not-found answer.
static func capital_lonlat(loader, nation_id: String) -> Variant:
	var nation = loader.nations.get(nation_id)
	if nation == null:
		push_error("diplomacy: no nation '%s' to read a capital from" % nation_id)
		return null
	var wanted := String(nation.capital)
	for region in loader.regions.get(nation_id, []):
		for city in region.cities:
			if String(city.city_name) == wanted:
				return city.lonlat
	push_error("diplomacy: capital '%s' of %s is not in the city register" % [wanted, nation_id])
	return null


## Great-circle distance in kilometres. Half the haversine, on a mean-earth
## radius; the precision is beside the point when the answer is rounded up to
## whole days against a 280 km rate.
static func haversine_km(a: Vector2, b: Vector2) -> float:
	const EARTH_RADIUS_KM := 6371.0
	var lon1 := deg_to_rad(a.x)
	var lat1 := deg_to_rad(a.y)
	var lon2 := deg_to_rad(b.x)
	var lat2 := deg_to_rad(b.y)
	var dlat := lat2 - lat1
	var dlon := lon2 - lon1
	var h := sin(dlat * 0.5) * sin(dlat * 0.5) \
		+ cos(lat1) * cos(lat2) * sin(dlon * 0.5) * sin(dlon * 0.5)
	return 2.0 * EARTH_RADIUS_KM * asin(minf(1.0, sqrt(h)))
