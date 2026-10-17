extends SceneTree

## Headless test: godot --headless --script res://tests/test_map_ground.gd
## Non-zero exit on any failure.
##
## V4.10a, the ground at depth. What the suite cannot see is the pixels -- that
## is screenshot.gd's job at each zoom band. What it can pin is every silent
## failure the ground carries: a band that is not the one derived from the
## satellite's texel density (the opening screen changes for no recorded
## reason), an asset that decodes at a size its sidecar does not claim (the
## ground drawn offset from the coast it was baked against), a ground that
## does not cover the roster, mipmaps quietly lost (shimmer at the band's low
## edge), and a regression to load(), which is green here and dark on a fresh
## clone -- MapRaster's own failure class.

const DataLoader = preload("res://src/core/data_loader.gd")
const MapGround = preload("res://src/ui/map_ground.gd")
const MapRaster = preload("res://src/ui/map_raster.gd")

## map_view.BASE_SCALE. Restated rather than preloading map_view so this test
## exercises band_alpha() the way map_view calls it, with the scale passed in;
## _check_band_derived fails if the two ever disagree on what 1.25 means.
const BASE_SCALE := 12.0

var _failures: Array[String] = []


func _init() -> void:
	_check_band_derived()
	_check_sat_density()
	_check_asset_decodes()
	_check_bounds_cover_roster()
	_check_no_load()
	_finish()


func _check_band_derived() -> void:
	# Satellite 1:1 at zoom 15 / 12 = 1.25; a 2x upscale at 2.5.
	if MapGround.band_alpha(1.25, BASE_SCALE) != 0.0:
		_failures.append("band: alpha at the satellite's 1:1 zoom (1.25) is %f, want 0" % MapGround.band_alpha(1.25, BASE_SCALE))
	if MapGround.band_alpha(2.5, BASE_SCALE) != 1.0:
		_failures.append("band: alpha at the satellite's 2x upscale (2.5) is %f, want 1" % MapGround.band_alpha(2.5, BASE_SCALE))
	if MapGround.band_alpha(0.5, BASE_SCALE) != 0.0:
		_failures.append("band: ground shows at globe view (zoom 0.5)")
	if MapGround.band_alpha(8.0, BASE_SCALE) != 1.0:
		_failures.append("band: satellite still shows at max zoom (8.0)")
	var mid := MapGround.band_alpha(1.9, BASE_SCALE)
	if mid <= 0.0 or mid >= 1.0:
		_failures.append("band: zoom 1.9 should be mid-crossfade, got %f" % mid)
	var prev := -1.0
	for step in 201:
		var z := 0.05 + (8.0 - 0.05) * float(step) / 200.0
		var a := MapGround.band_alpha(z, BASE_SCALE)
		if a < prev:
			_failures.append("band: alpha falls from %f to %f at zoom %f" % [prev, a, z])
			break
		prev = a


func _check_sat_density() -> void:
	var sat := MapRaster.texture()
	if sat == null:
		_failures.append("satellite raster did not decode; the band is derived from it")
		return
	var density := float(sat.get_width()) / (MapRaster.LON_MAX - MapRaster.LON_MIN)
	if density != MapGround.SAT_TEXELS_PER_DEG:
		_failures.append("SAT_TEXELS_PER_DEG is %f but the raster carries %f texels/deg" % [MapGround.SAT_TEXELS_PER_DEG, density])


func _check_asset_decodes() -> void:
	var tex := MapGround.texture()
	if tex == null:
		_failures.append("ground texture did not decode from bytes")
		return
	var side := MapGround.sidecar()
	if tex.get_width() != int(side.get("width", -1)) or tex.get_height() != int(side.get("height", -1)):
		_failures.append("ground is %dx%d, sidecar claims %sx%s" % [tex.get_width(), tex.get_height(), side.get("width"), side.get("height")])
	if not tex.get_image().has_mipmaps():
		_failures.append("ground texture has no mipmaps; it shimmers at the band's low edge")


func _check_bounds_cover_roster() -> void:
	var b := MapGround.bounds()
	if b.size.x <= 0.0 or b.size.y <= 0.0:
		_failures.append("ground bounds are empty: %s" % [b])
		return
	var side := MapGround.sidecar()
	var ppd := float(side.get("px_per_deg", 0.0))
	if absf(b.size.x * ppd - float(side.get("width", 0))) > 0.5:
		_failures.append("ground bounds width %f deg x %f px/deg != %s px" % [b.size.x, ppd, side.get("width")])
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [loader.errors])
		return
	for id in loader.nations.keys():
		var n = loader.nations[id]
		for ring: PackedVector2Array in loader.geo_features.get(n.geo_id, []):
			for pt in ring:
				# Rect2.has_point() excludes the far edges; the extent is snapped
				# OUT by whole degrees plus a margin, so nothing sits on one.
				if not b.has_point(pt):
					_failures.append("roster nation %s has a point %s outside the ground %s" % [id, pt, b])
					return


func _check_no_load() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/map_ground.gd")
	var re := RegEx.new()
	re.compile("(?<![_a-z])load\\(")
	# Code only: the header explains WHY it never calls load(), in those words.
	for line in src.split("\n"):
		var code := line.split("#")[0]
		if re.search(code) != null:
			_failures.append("map_ground.gd calls load(): %s -- a fresh clone has no imported texture, read the bytes" % line.strip_edges())


func _finish() -> void:
	if _failures.is_empty():
		print("test_map_ground: OK")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: ", f)
		quit(1)
