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
const Regions = preload("res://src/sim/regions.gd")
## V2.6b1, for the demonstration ring. The site is DERIVED here every refresh
## rather than stored anywhere, which is what lets the ring move if the model ever
## moves it -- and it is read through Unrest rather than Siting directly, because
## which signal sites a demonstration is unrest's business and not the map's.
const Unrest = preload("res://src/sim/unrest.gd")
const UnrestK = preload("res://src/sim/unrest_constants.gd")
## V2.6b2, for the meeting ring. Read through Campaign rather than the raw register
## for the demonstration ring's reason: whose verb the site belongs to is the sim's
## business and not the map's.
const Campaign = preload("res://src/sim/campaign.gd")
const Strings = preload("res://src/ui/strings.gd")

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

## V2.6b1. The demonstration ring: drawn around the cross rather than replacing it,
## because the city is still a city and the unrest is a thing happening AT it. Sized
## off the glyph's own radius so it clears the arms at every population.
const RING_GAP := 3.0
const RING_WIDTH := 2.0
const RING_POINTS := 24

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

		# WHERE THE UNIONS ARE OUT, and only once they are. Gated on the same
		# threshold src/ui/economy_panel.gd's own line uses, so the map and the panel
		# cannot disagree about whether anything is happening -- and so a quiet game
		# draws nothing at all rather than a permanent ring on the region that would
		# host a demonstration if there were one. The nine never reach it: their
		# grievance is gated off in Unrest.tick_month() and reads exactly 0.0.
		var demo_city := ""
		if float(ns.unrest_pct) >= UnrestK.UNREST_THRESHOLD_PCT:
			var demo_list: Array = state.regions.get(id, [])
			demo_city = String(Unrest.site_report(ns, demo_list,
				Regions.accessibility_for(ns, demo_list, state.region_graph),
				state.project_sited_pct.get(id, {}))["city_id"])

		# WHERE THE PRESIDENT IS, for the player alone -- the nine never campaign
		# (tests/test_campaign.gd pins it), and campaign_count <= 1 is content, so
		# this is at most one ring on the whole map. Derived here every refresh like
		# the demonstration's, and gated on an effort actually being in the field, so
		# a quiet game draws nothing at all.
		var campaign_city := ""
		if String(id) == String(state.player_nation_id):
			var running: Array = Campaign.running(ns)
			if not running.is_empty():
				var site := Campaign.site_of(ns, String(running[0]))
				if site != "":
					var principal = Campaign.principal_city(loader, ns, site)
					if principal != null:
						campaign_city = String(principal.id)

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
					"unrest": demo_city != "" and String(city.id) == demo_city,
					"campaign": campaign_city != "" and String(city.id) == campaign_city,
					"own": String(id) == String(state.player_nation_id),
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


## The played nation's own cities wear its accent, every other nation's the neutral
## map tone (V5.1a QA: zoomed in, Bucharest and Madrid showed France's blue).
static func color_of(city: Dictionary) -> Color:
	return UiTheme.accent() if bool(city.get("own", false)) else UiTheme.MAP_NEUTRAL


## Is this the city the country's demonstration is in? Duck-typed off the record the
## way is_filled() reads a marker's, so map_view.gd asks rather than indexing.
static func is_unrest(city: Dictionary) -> bool:
	return bool(city.get("unrest", false))


## Is this the city the player's campaign meetings are in? is_unrest()'s shape.
static func is_campaign(city: Dictionary) -> bool:
	return bool(city.get("campaign", false))


## The ring sits outside the cross's arms at every size.
static func ring_radius(city: Dictionary) -> float:
	return radius_of(city) + RING_GAP


## What the cross says when the cursor is on it, drawn on hover alone for labels'
## own reason: 581 names at the Europe view are 581 names on top of each other.
## The population is formatted by PanelKit.pop_text, the one formatter, so the
## hover label and the City panel cannot print two roundings of one figure.
static func label_of(city: Dictionary) -> String:
	var text := "%s  --  %s" % [
		String(city.get("name", "")),
		PanelKit.pop_text(float(city.get("population", 0.0))),
	]
	# V2.6b1. The ring says THAT something is happening and the label says WHAT, which
	# is the split the marker layer already uses for built-against-building. The noun
	# is deliberately not the act label: unrest_constants.ACT_LABELS picks `protest` or
	# `strike` off the stock and src/ui/main.gd's card owns that wording, so a second
	# surface naming it would be two places to disagree -- the exact split
	# economy_panel.gd's own unrest line already keeps.
	if is_unrest(city):
		text += Strings.t("  --  where the unions are out")
	elif is_campaign(city):
		text += Strings.t("  --  where the meetings are")
	return text
