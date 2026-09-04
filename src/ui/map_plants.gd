extends RefCounted

## The plant glyphs -- V2.8. The SIXTH draw pass, frontmost, over U6c's project
## markers.
##
## NO ZOOM GATE, and that is the difference from src/ui/map_cities.gd rather than an
## oversight. Cities are 581 of them drawn by rank, so CITY_MIN_ZOOM exists to stop
## the opening Europe fit becoming a wall of crosses. A nation's plants are a handful,
## every one of them the player's own decision, and hiding the thing this block exists
## to show at the frame every game opens on would be the volume rule applied where
## there is no volume.
##
## HOLLOW WHILE BUILDING, FILLED ONCE RUNNING. One glyph, two states, so the fleet is
## legible from the map without a legend -- and it is the same distinction the panel's
## FLEET ledger prints in words, which is one fact told twice on purpose because the
## map cannot carry a sentence.

const UITheme = preload("res://src/ui/ui_theme.gd")

const RADIUS := 5.0


## `to_screen` is a Callable taking (lon, lat) and returning a Vector2, passed in
## rather than reached for, so this file never learns what a projection is --
## map_cities.gd's own arrangement.
static func draw_plants(canvas: CanvasItem, state, to_screen: Callable) -> void:
	var nation_ids: Array = state.nations.keys()
	nation_ids.sort()
	for nation_id in nation_ids:
		var ns = state.nations[nation_id]
		var plant_ids: Array = ns.plants.keys()
		plant_ids.sort()
		for plant_id in plant_ids:
			var entry: Dictionary = ns.plants[plant_id]
			var at: Vector2 = to_screen.call(float(entry.get("lon", 0.0)), float(entry.get("lat", 0.0)))
			if bool(entry.get("done", false)):
				canvas.draw_circle(at, RADIUS, UITheme.ACCENT)
			else:
				canvas.draw_arc(at, RADIUS, 0.0, TAU, 20, UITheme.ACCENT, 1.5)
