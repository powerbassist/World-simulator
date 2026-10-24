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
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const EnergyPanel = preload("res://src/ui/energy_panel.gd")

const RADIUS := 5.0
## The built share as a thicker arc over the hollow ring, from twelve o'clock
## clockwise (V5.2 b+, R1): the ring alone said "building" and never how far.
const PROGRESS_WIDTH := 3.0


## `to_screen` is a Callable taking (lon, lat) and returning a Vector2, passed in
## rather than reached for, so this file never learns what a projection is --
## map_cities.gd's own arrangement.
static func draw_plants(canvas: CanvasItem, state, to_screen: Callable, loader = null) -> void:
	var nation_ids: Array = state.nations.keys()
	nation_ids.sort()
	for nation_id in nation_ids:
		var ns = state.nations[nation_id]
		var plant_ids: Array = ns.plants.keys()
		plant_ids.sort()
		for plant_id in plant_ids:
			var entry: Dictionary = ns.plants[plant_id]
			var at: Vector2 = to_screen.call(float(entry.get("lon", 0.0)), float(entry.get("lat", 0.0)))
			var color := color_of(String(nation_id), String(state.player_nation_id))
			if bool(entry.get("done", false)):
				canvas.draw_circle(at, RADIUS, color)
			else:
				canvas.draw_arc(at, RADIUS, 0.0, TAU, 20, Color(color, 0.5), 1.5)
				var built := progress(entry, loader)
				if built > 0.0:
					canvas.draw_arc(at, RADIUS, -PI / 2.0, -PI / 2.0 + TAU * built, 20, color, PROGRESS_WIDTH)


## The share of a plant built, 0 to 1: the months gone of its source's build time.
## No loader (or a source the content lost) reads as nothing built yet.
static func progress(entry: Dictionary, loader) -> float:
	if bool(entry.get("done", false)):
		return 1.0
	var source = loader.energy_sources.get(String(entry.get("source_id", ""))) if loader != null else null
	if source == null or int(source.build_months) <= 0:
		return 0.0
	return clampf(1.0 - float(entry.get("months_left", 0)) / float(source.build_months), 0.0, 1.0)


## The plant under `pos` as [nation id, plant id], or []. A radius test in SCREEN
## space: the glyph is a fixed number of pixels at every zoom, so a degree-radius
## target would shrink as the player zoomed out to look for it. Nearest wins.
static func hit(state, to_screen: Callable, pos: Vector2) -> Array:
	var best: Array = []
	if state == null:
		return best
	var best_d: float = RADIUS + 3.0
	var nation_ids: Array = state.nations.keys()
	nation_ids.sort()
	for nation_id in nation_ids:
		var ns = state.nations[nation_id]
		var plant_ids: Array = ns.plants.keys()
		plant_ids.sort()
		for plant_id in plant_ids:
			var entry: Dictionary = ns.plants[plant_id]
			var d: float = (to_screen.call(float(entry.get("lon", 0.0)), float(entry.get("lat", 0.0))) as Vector2).distance_to(pos)
			if d <= best_d:
				best_d = d
				best = [String(nation_id), String(plant_id)]
	return best


## The cursor's readout over a plant, the map's own lines ([text, size] pairs, as
## the outline readout's): what and where, then how far it is. The player's own
## plant gives its progress and months; another nation's says only whether it
## runs -- its schedule is that government's.
static func readout_lines(state, loader, nation_id: String, plant_id: String) -> Array:
	var ns = state.nations.get(nation_id)
	if ns == null or not ns.plants.has(plant_id):
		return []
	var entry: Dictionary = ns.plants[plant_id]
	var where := String(entry.get("region_id", ""))
	for region in loader.regions.get(nation_id, []):
		if region.id == where:
			where = String(region.region_name)
	var title := EnergyPanel.plant_label(ns, plant_id, loader)
	var status := Strings.t("Running")
	if not bool(entry.get("done", false)):
		var left := int(entry.get("months_left", 0))
		status = Strings.t("Under construction")
		if nation_id == String(state.player_nation_id):
			status = Strings.tn("Under construction: %s %% built, %d month left", "Under construction: %s %% built, %d months left", left) % [
				Num.f(progress(entry, loader) * 100.0, 0), left]
	return [["%s · %s" % [title, where] if where != "" else title, UITheme.SIZE_SMALL], [status, UITheme.SIZE_MICRO]]


## The played nation's plants wear its accent, every other nation's the neutral map
## tone -- the accent is whose identity this game is, not a colour for every mark.
static func color_of(nation_id: String, player_id: String) -> Color:
	return UITheme.accent() if nation_id == player_id else UITheme.MAP_NEUTRAL
