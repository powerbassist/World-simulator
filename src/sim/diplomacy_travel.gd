extends RefCounted

## travel_days()'s geography, moved out of diplomacy.gd verbatim at V5.1-0a so
## that file could take its month in units without growing past its size
## baseline (V5.0c's diplomacy_verbs.gd precedent). Pure reads of the loader; no
## state, and no sim module preloaded beyond the constants.

const DK = preload("res://src/sim/diplomacy_constants.gd")
const Capital = preload("res://src/core/capital.gd")


## Diplomacy.travel_days()'s body, moved here at V5.1-0d so diplomacy.gd could take
## the embassy register without growing past its size baseline. The contract is
## that function's comment.
static func days(loader, from_id: String, to_id: String) -> int:
	var from_lonlat: Variant = capital_lonlat(loader, from_id)
	var to_lonlat: Variant = capital_lonlat(loader, to_id)
	if from_lonlat == null or to_lonlat == null:
		return DK.TRAVEL_DAYS_MAX
	var km := haversine_km(from_lonlat, to_lonlat)
	var days_n := int(ceil(km / DK.TRAVEL_KM_PER_DAY))
	return clampi(days_n, DK.TRAVEL_DAYS_MIN, DK.TRAVEL_DAYS_MAX)


## A nation's capital as a lon/lat, or null -- src/core/capital.gd's rule, the one
## the map draws (G1: this used an exact name match, so MDA and MLT priced at the
## ceiling). Variant rather than Vector2 because null is the not-found answer, and
## it now means a nation with no city at all, which still errors loudly.
static func capital_lonlat(loader, nation_id: String) -> Variant:
	var at: Variant = Capital.lonlat(loader, nation_id)
	if at == null:
		push_error("diplomacy: nation '%s' has no city to read a capital from" % nation_id)
	return at


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
