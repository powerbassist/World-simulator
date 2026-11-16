extends RefCounted

## The Regions tab's wiring in main.gd's shell -- screen 6, slice 2 (the author's direction A,
## "A, la carte"). Here rather than in main.gd, which is at its size ratchet. main.gd keeps
## its literal register("region", ...) line (the strip's and the outliner's tests read the
## registered window ids off those calls); this file makes the panel and joins it to the map:
##   - the overlay (map_regions.gd) on map_view, shown while the tab is (region_panel.gd);
##   - map_view.region_picker: a point inside one of the player's regions answers its id
##     while the tab is open, "" otherwise, so the nation click is untouched elsewhere;
##   - region_clicked opens that region's sheet.

const RegionPanel = preload("res://src/ui/region_panel.gd")
const MapRegions = preload("res://src/ui/map_regions.gd")
const Region = preload("res://src/core/region.gd")
const Migration = preload("res://src/sim/migration.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")


static func panel(main) -> Control:
	var tab = RegionPanel.new()
	tab.setup(main._state, main._loader)
	tab.attach(main._windows, main._map_view)
	var overlay = MapRegions.new()
	main._map_view.add_child(overlay)
	tab._overlay = overlay
	overlay.fit_rect_source = fit_rect_for
	# The canvas changes size with the window and the interface size (F11, a drag, a
	# Settings change): with the tab open, the nation is framed again on the new canvas.
	main.get_viewport().size_changed.connect(func():
		if tab.is_visible_in_tree():
			overlay.request_fit()
	)
	bind(main, overlay)
	# A load re-runs every registered panel's setup() (main.gd's _on_load_requested), and
	# Continue is a load over the default game: the overlay follows it there, or a save of
	# another nation kept the startup nation's regions (the retro review's item 1).
	tab.rebind = func():
		bind(main, overlay)
		# A load with the tab open: the loaded nation framed, not the discarded one's view.
		if tab.is_visible_in_tree():
			overlay.request_fit()
	main._map_view.region_picker = func(lonlat: Vector2) -> String:
		if not tab.is_visible_in_tree():
			return ""
		var id := Region.region_at_lonlat(main._loader.region_rings, lonlat.x, lonlat.y)
		for region in main._loader.regions.get(main._state.player_nation_id, []):
			if String(region.id) == id:
				return id
		return ""
	main._map_view.region_clicked.connect(tab.open_region)
	return tab


## The overlay's regions, holes and avoided cities, from the nation main._state plays.
static func bind(main, overlay) -> void:
	var ids: Array = []
	for region in main._loader.regions.get(main._state.player_nation_id, []):
		ids.append(String(region.id))
	var holed := {}
	for id in ids:
		holed[id] = main._loader.region_rings.get(id, [])
	overlay.setup(main._map_view, ids, main._loader.region_features, holed)
	# Each region's largest city: its marker is the one a figure must not cover (QA's T1 on
	# #384, Paris under Ile-de-France's figure). Every city would leave a dense region no place.
	var ns = main._state.player()
	var cities := {}
	for region in main._loader.regions.get(ns.id, []):
		var largest = null
		for c in region.cities:
			if largest == null or Migration.city_population(ns, region.id, c.id) > Migration.city_population(ns, region.id, largest.id):
				largest = c
		cities[String(region.id)] = [] if largest == null else [largest.lonlat]
	overlay.set_avoid(cities)


## The map the Regions tab frames the nation in, on a canvas of `view` logical px: right
## of the narrow dock, left of the inbox's strip, between the strip of figures and the
## day ribbon. At 1920x1080 it is the rect it always was (the strip right of the
## 1240 dock); a bigger canvas (settings_panel.gd's interface size) widens and
## heightens it with the map rather than stopping at 1080.
static func fit_rect_for(view: Vector2) -> Rect2:
	var w = WindowManager
	var left: float = w.DOCK_LEFT + float(w.DOCK_WIDTHS["region"])
	# The inbox's strip, measured at the reference: what the 1240 dock leaves of 1920.
	var strip: float = 1920.0 - (w.DOCK_LEFT + w.DOCK_WIDTH)
	return Rect2(left, w.DOCK_TOP, view.x - strip - left, view.y - w.DOCK_TOP - w.DOCK_BOTTOM)
