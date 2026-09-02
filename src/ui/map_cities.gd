extends RefCounted

## The city register's draw-side derivation -- V2.2b, the tier's own *"cities drawn
## and clickable"*. The one place a city glyph is derived; map_view.gd's
## _draw_cities() asks this and indexes nothing itself, which is map_markers.gd's
## contract unchanged.
##
## **Not a LAYERS entry, for markers' own reason.** A map_layers.LAYERS entry
## chooses a roster FILL, one at a time, through a per-nation scalar; a city is a
## point, additive, and orthogonal to whatever fill is up. Made a layer it would
## also restate V1.6f's all-zero dead content in a new register, because a fill
## needs a value and a city's value is its *size*. tests/test_map_markers.gd pins
## LAYERS at four and this session does not touch it.
##
## **Brass, and this is the spend the tier reserved.** ROADMAP's V2.1a row: "brass
## keeps one meaning; V2.2 has already reserved the next spend of it". The tier doc
## spends it here and only here: *brass crosses onto the map for the first time and
## only for where people are; everything else stays navy, white and roster hue.*
## A project marker is already brass, and the two share the meaning rather than
## split it -- *a place you can point at that the game has named*.
##
## Radius is a function of POPULATION, not a fixed number of pixels. This is the
## one deliberate departure from map_markers.gd, whose dots stay the same size at
## every zoom because five sites on France are five sites; 581 cities on Europe are
## a ranking, and the tier doc's own spec is radius proportional to the square root
## of population -- the shape that makes a 9 M capital and its 71 k suburb read as
## the same kind of thing at a glance without the suburb vanishing.
##
## Stateless and pure, markers' shape: a read over the loader's register and
## GameState. The register is static content, so map_view builds this list once in
## setup() rather than per draw -- the population under it drifts with the sim, and
## that is fine: a glyph's radius is a ranking, and a ranking does not move by the
## few tenths of a percent a decade of drift is worth.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Migration = preload("res://src/sim/migration.gd")

## The population a cross is measured against: capital-city scale, the top of the
## roster's own range (London reads ~9.1 M). RADIUS_BASE is what that city draws;
## everything smaller is the square root of its ratio to it.
const REFERENCE_POP := 8_000_000.0
const RADIUS_BASE := 9.0

## The clamp matters only at the small end -- a 71 k town is sqrt(71/8000) = 9 %
## of the reference radius, which is a single pixel and not a mark. The top of the
## range never reaches RADIUS_MAX on this roster; it exists so a future import
## naming a metro area cannot grow a cross into a blob.
const RADIUS_MIN := 2.0
const RADIUS_MAX := 12.0

const WIDTH := 2.0
const HOVER_WIDTH := 3.0

const LABEL_COLOR := Color(0.94, 0.96, 1.0, 0.96)
const LABEL_SHADOW := Color(0.0, 0.0, 0.0, 0.7)


## Every named city on the roster, as plain dictionaries: {nation_id, city_id,
## name, region_id, region_name, lonlat, population}. All ten nations -- the
## register is public data and the map colours all ten, so a German cross that
## answered no click would be drawn content the game cannot reach.
##
## ASCENDING population, so the largest draws last and wins an overlap -- the
## marker convention, where draw order and hit order walk the same list and last
## match wins. Paris over its own suburbs is also the correct reading order.
static func cities(loader, state) -> Array:
	var out: Array = []
	if loader == null or state == null:
		return out

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var ns = state.nations.get(id)
		if ns == null:
			continue
		for region in loader.regions.get(id, []):
			for city in region.cities:
				out.append({
					"nation_id": String(id),
					"city_id": city.id,
					"name": city.city_name,
					"region_id": region.id,
					"region_name": region.region_name,
					"lonlat": city.lonlat,
					"population": Migration.city_population(ns, region.id, city.id),
				})
	out.sort_custom(func(a, b): return float(a["population"]) < float(b["population"]))
	return out


static func radius_of(city: Dictionary) -> float:
	return clampf(
		RADIUS_BASE * sqrt(float(city.get("population", 0.0)) / REFERENCE_POP),
		RADIUS_MIN, RADIUS_MAX
	)


## The name sits above the glyph, clear of it -- markers' rule, offset by the
## radius rather than a constant because this glyph is not one size.
static func label_offset(radius: float) -> Vector2:
	return Vector2(0.0, -radius - 6.0)


static func color_of(_city: Dictionary) -> Color:
	return UiTheme.ACCENT


## What the cross says when the cursor is on it, drawn on hover alone for labels'
## own reason: 581 names at the Europe view are 581 names on top of each other.
## The population is formatted by PanelKit.pop_text, the one formatter, so the
## hover label and the City panel cannot print two roundings of one figure.
static func label_of(city: Dictionary) -> String:
	return "%s  --  %s" % [
		String(city.get("name", "")),
		PanelKit.pop_text(float(city.get("population", 0.0))),
	]
