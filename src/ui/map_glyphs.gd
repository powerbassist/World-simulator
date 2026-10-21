extends RefCounted

## City glyphs in tiers -- V4.10b. The register that says which mark a city gets
## and (through map_view's LABEL_ZOOM_T*) when its name is shown; map_cities.gd
## stays the register of WHAT a city is (population, unrest, campaign).
##
## Three tiers, capital first and then live population, the author's call at the
## V4.10b plan gate: a capital outranks a bigger city because a political map is
## read by its seats of government, and a size-only rule would leave Bern a small
## cross beside Zurich. The SIZE of every mark stays MapCities.radius_of() -- tiers
## change the mark and the naming rule, not the scale a player already reads.
##
## Capitals are src/core/capital.gd's rule (V5.1-0d moved it there so the diary's
## travel pricing reads the same one): a NAME match between data/nations/*.json
## "capital" and the city register, folded (case and diacritics), because the two
## files were imported from different sources: MDA's "Chișinău" is the city
## "Chisinau". A nation whose
## capital is not in the register at all falls back to its largest city -- MLT's
## Valletta (~6k people) is below the register's cut. That fallback is a BOUND,
## recorded in docs/map-platform-model.md §10, not a silent guess.

const MapCities = preload("res://src/ui/map_cities.gd")
const Capital = preload("res://src/core/capital.gd")

## The tier-2 floor. Half a million is where a European city stops being a
## regional town and starts being a name a player expects on a country-scale map
## (Lyon, Leeds, Wrocław, Genoa sit just above it; most regional seats sit below).
const TIER2_POP := 500_000.0

## The capital's ring sits this far outside its cross, the same gap map_cities
## uses for the unrest ring, so the two never read as different families of mark.
const CAPITAL_RING_GAP := 2.0
const CAPITAL_RING_WIDTH := 1.5
const CAPITAL_RING_POINTS := 20

## Tier 3's stroke against tier 2's: thinner rather than smaller, because the
## radius already carries the size.
const TIER3_WIDTH_SCALE := 0.625

## Clearance around a glyph that a name may not enter.
const RECT_PAD := 2.0

## city_id -> nation_id, one per nation (see the header for the fallback).
static func capitals(loader) -> Dictionary:
	var out := {}
	for nid in loader.nations.keys():
		var city = Capital.city(loader, String(nid))
		if city != null:
			out[city.id] = String(nid)
	return out


## Ambiguity is a data defect (two cities folding to the capital's name); a
## capital absent from the register is the recorded bound, not an error.
static func capital_errors(loader) -> Array[String]:
	var out: Array[String] = []
	for nid in loader.nations.keys():
		var want := Capital.fold(String(loader.nations[nid].capital))
		var n := 0
		for region in loader.regions.get(nid, []):
			for city in region.cities:
				if want != "" and Capital.fold(city.city_name) == want:
					n += 1
		if n > 1:
			out.append("%s: capital '%s' matches %d cities" % [nid, loader.nations[nid].capital, n])
	return out


static func tier_of(city: Dictionary, capitals: Dictionary) -> int:
	if capitals.has(String(city.get("city_id", ""))):
		return 1
	if float(city.get("population", 0.0)) >= TIER2_POP:
		return 2
	return 3


static func _extent(city: Dictionary, tier: int) -> float:
	var r := MapCities.radius_of(city)
	if tier == 1:
		r += CAPITAL_RING_GAP + CAPITAL_RING_WIDTH
	return r + RECT_PAD


static func glyph_rect(at: Vector2, city: Dictionary, tier: int) -> Rect2:
	var e := _extent(city, tier)
	return Rect2(at - Vector2(e, e), Vector2(e, e) * 2.0)


## A cross rather than a dot -- V2.2b's glyph, moved here unchanged for tiers 2
## and 3: the one mark that says *people* rather than *thing*, legible from 2 px
## to 12 px where a ring would close up. Tier 1 adds a ring.
static func draw_glyph(canvas: CanvasItem, at: Vector2, city: Dictionary, tier: int, width: float) -> void:
	var color: Color = MapCities.color_of(city)
	var radius := MapCities.radius_of(city)
	var w := width * TIER3_WIDTH_SCALE if tier == 3 else width
	var arm := Vector2(radius, 0.0).rotated(PI / 4.0)
	canvas.draw_line(at - arm, at + arm, color, w)
	canvas.draw_line(at - Vector2(arm.x, -arm.y), at + Vector2(arm.x, -arm.y), color, w)
	if tier == 1:
		canvas.draw_arc(at, radius + CAPITAL_RING_GAP, 0.0, TAU, CAPITAL_RING_POINTS,
			color, CAPITAL_RING_WIDTH)
