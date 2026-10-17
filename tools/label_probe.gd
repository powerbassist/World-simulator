extends SceneTree

## The city-name band probe -- V4.10b. Dev-only, never ships.
##
##   godot --path "<repo>" --script res://tools/label_probe.gd
##
## Windowed (the font and the 1920x1080 window are what the placement is made
## of). The rule it measures was written into map_view.gd's LABEL_ZOOM_T* comment
## and the V4.10b plan BEFORE it was run: a tier's names turn on at the lowest
## zoom of GRID where >= 70 % of that tier's on-screen cities get a name in BOTH
## stress views, with the tiers above it already on. It drives the same
## _place_labels() the frame draws, with the probe override (max_tier) that
## names tiers 1..k at any zoom.
##
## The stress views are where the roster is densest in cities: the Ruhr and the
## Po valley (the V4.10 handoff's own pair).

const MainScene := "res://src/ui/main.tscn"
const VIEWS := [
	{"name": "Nordrhein-Westfalen", "lon": 7.0, "lat": 51.4},
	{"name": "Lombardia", "lon": 9.5, "lat": 45.6},
]
const GRID := [2.0, 2.5, 3.0, 3.5, 4.0, 5.0, 6.0, 8.0]
const BAND_PCT := 70.0
const SIZE := Vector2i(1920, 1080)

var _main: Node = null
var _frames := 0


func _initialize() -> void:
	root.size = SIZE
	_main = load(MainScene).instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < 40:
		return false
	_run()
	quit(0)
	return true


func _run() -> void:
	var map = _main._map_view
	print("map size %s" % [map.size])
	var tier_of := {}
	for city in map._cities:
		tier_of["city:" + String(city["city_id"])] = int(city.get("tier", 3))
	# first_zoom[view][tier] = lowest grid zoom passing the band
	var first := {}
	for v in VIEWS:
		first[v["name"]] = {1: -1.0, 2: -1.0, 3: -1.0}
	print("view | zoom | tier | on-screen | named | pct | place ms (all tiers)")
	for v in VIEWS:
		for z in GRID:
			map.set_zoom_for_test(z)
			map.center_on_lonlat(float(v["lon"]), float(v["lat"]))
			var t0 := Time.get_ticks_usec()
			map._place_labels(3)
			var ms := float(Time.get_ticks_usec() - t0) / 1000.0
			# The placement the game actually runs, with the shipped LABEL_ZOOM_T*.
			var t1 := Time.get_ticks_usec()
			var shipped: Array = map._place_labels()
			print("%s | %.1f | SHIPPED | %d names | %.2f ms" % [v["name"], z, shipped.size(),
				float(Time.get_ticks_usec() - t1) / 1000.0])
			for k in [1, 2, 3]:
				var placed: Array = map._place_labels(k)
				var onscreen := int(map._label_onscreen.get(k, 0))
				var named := 0
				for p in placed:
					if int(tier_of.get(String(p["id"]), 0)) == k:
						named += 1
				var pct := 100.0 * float(named) / float(onscreen) if onscreen > 0 else 100.0
				print("%s | %.1f | %d | %d | %d | %.0f%% | %.2f" % [v["name"], z, k, onscreen, named, pct, ms])
				if pct >= BAND_PCT and float(first[v["name"]][k]) < 0.0:
					first[v["name"]][k] = z
	print("--- band (lowest grid zoom with >= %.0f%% named, per view) ---" % BAND_PCT)
	for k in [1, 2, 3]:
		var worst := -1.0
		var missing := false
		for v in VIEWS:
			var f := float(first[v["name"]][k])
			print("tier %d  %s: %s" % [k, v["name"], "never" if f < 0.0 else "%.1f" % f])
			if f < 0.0:
				missing = true
			worst = maxf(worst, f)
		print("tier %d  LABEL_ZOOM_T%d = %s" % [k, k, "BOUND (hover only)" if missing else "%.1f" % worst])
