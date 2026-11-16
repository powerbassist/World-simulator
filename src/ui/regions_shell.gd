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


static func panel(main) -> Control:
	var tab = RegionPanel.new()
	tab.setup(main._state, main._loader)
	tab.attach(main._windows, main._map_view)
	var overlay = MapRegions.new()
	main._map_view.add_child(overlay)
	var ids: Array = []
	for region in main._loader.regions.get(main._state.player_nation_id, []):
		ids.append(String(region.id))
	overlay.setup(main._map_view, ids, main._loader.region_features)
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
	tab._overlay = overlay
	var w = main._windows
	overlay.fit_rect = Rect2(w.DOCK_LEFT + float(w.DOCK_WIDTHS["region"]), w.DOCK_TOP,
		w.DOCK_WIDTH - float(w.DOCK_WIDTHS["region"]), 1080.0 - w.DOCK_TOP - w.DOCK_BOTTOM)
	main._map_view.region_picker = func(lonlat: Vector2) -> String:
		if not tab.is_visible_in_tree():
			return ""
		var id := Region.region_at_lonlat(main._loader.region_rings, lonlat.x, lonlat.y)
		return id if ids.has(id) else ""
	main._map_view.region_clicked.connect(tab.open_region)
	return tab
