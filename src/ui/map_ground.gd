extends RefCounted

## The ground at depth -- V4.10a. A paper-and-hillshade texture baked once by
## tools/ground_generate.py from NOAA ETOPO 2022 relief and the repo's own
## geometry; provenance in docs/data-sources.md.
##
## It RETIRES the satellite at depth rather than scaling it. V3.1 refused
## per-tile raster LOD with a measured reason (the raster is one quad; fill rate
## never moved), and nothing here overturns that: the photograph keeps globe
## view, where its 15 texels per degree are honest, and hands off to this one
## quad as the zoom outruns them. The minimap is globe view by definition and
## keeps the photograph.
##
## Read as bytes and never through the import system, for map_raster.gd's
## reason in full: the editor's imported copy lives in .godot/, which a fresh
## clone does not have while tools/run_tests.sh runs headless straight from the
## repo. The committed `.webp.import` is `importer="keep"` for the same reason
## the Blue Marble's is.
##
## The bounds come from the sidecar the generator wrote beside the image, so the
## rect the ground is drawn into is the rect it was baked for and is authored
## nowhere else. Mipmapped on decode: at the band's low edge the 60 texel/deg
## image lands on 15 screen px/deg, a 4:1 minification that shimmers without
## them.

const PATH := "res://assets/map/ground_europe.webp"
const SIDECAR_PATH := "res://assets/map/ground_europe.json"

## The satellite's texel density: 5400 px across 360 degrees (map_raster.gd's
## asset). The band is derived from it, not chosen: the photograph is drawn 1:1
## at zoom SAT_TEXELS_PER_DEG / BASE_SCALE (1.25 with map_view's 12 px/deg) and
## the ground starts fading in there; tests/test_map_ground.gd re-derives this
## number from the decoded raster so a new photograph cannot silently move the
## band.
const SAT_TEXELS_PER_DEG := 15.0

## The upscale at which the photograph has gone visibly soft and the ground has
## fully taken over: 2x, zoom 2.5. The opening fit (2.08) therefore lands most of
## the way to the ground -- the author signed that off at the V4.10a plan gate.
const BAND_UPSCALE_END := 2.0

static var _cached: ImageTexture = null
static var _sidecar: Dictionary = {}
static var _attempted := false


## Returns null if the asset is missing or undecodable, and the map then draws
## exactly as it did before V4.10a: the satellite at every zoom. A missing ground
## makes depth plainer, never makes the game fail to start.
static func texture() -> ImageTexture:
	_load_once()
	return _cached


## The sidecar as written by the generator, or {} if absent.
static func sidecar() -> Dictionary:
	_load_once()
	return _sidecar


## The ground's lon/lat rect, origin at (lon_min, lat_min). Rect2() if absent.
static func bounds() -> Rect2:
	_load_once()
	if _sidecar.is_empty():
		return Rect2()
	var lon_min := float(_sidecar["lon_min"])
	var lat_min := float(_sidecar["lat_min"])
	return Rect2(lon_min, lat_min,
		float(_sidecar["lon_max"]) - lon_min, float(_sidecar["lat_max"]) - lat_min)


## 0 while the photograph is at or under 1:1, 1 once it is upscaled 2x, a
## smoothstep between. Pure: the zoom and map_view's base scale are passed in so
## this file does not depend on map_view (data -> sim -> ui holds inside ui too).
static func band_alpha(zoom: float, base_scale: float) -> float:
	var z0 := SAT_TEXELS_PER_DEG / base_scale
	return smoothstep(z0, z0 * BAND_UPSCALE_END, zoom)


static func _load_once() -> void:
	if _attempted:
		return
	_attempted = true

	var side_text := FileAccess.get_file_as_string(SIDECAR_PATH)
	var parsed = JSON.parse_string(side_text) if side_text != "" else null
	if not parsed is Dictionary:
		push_warning("ground sidecar not found at %s; the satellite stays at depth" % SIDECAR_PATH)
		return

	var bytes := FileAccess.get_file_as_bytes(PATH)
	if bytes.is_empty():
		push_warning("ground not found at %s; the satellite stays at depth" % PATH)
		return
	var image := Image.new()
	if image.load_webp_from_buffer(bytes) != OK:
		push_warning("ground at %s could not be decoded" % PATH)
		return
	image.generate_mipmaps()
	_sidecar = parsed
	_cached = ImageTexture.create_from_image(image)
