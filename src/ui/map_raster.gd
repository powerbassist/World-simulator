extends RefCounted

## The world satellite raster -- U5b. NASA Blue Marble, next-generation
## topography and bathymetry, December 2004. Public domain; provenance in
## docs/data-sources.md.
##
## Deliberately **not** load("res://assets/map/..."). That path returns the
## editor's imported CompressedTexture2D out of .godot/, which is gitignored and
## absent on a fresh clone until the editor has opened the project once, while
## tools/run_tests.sh runs headless straight from the repo. Same trap and the
## same escape as icon.gd's SVG and ui_theme.gd's fonts: read the bytes, decode
## them in memory, never touch the import system.
##
## Plate carrée, which is already map_view.gd's projection -- lon maps linearly
## to x and lat linearly to y across the whole image -- so the texture drops onto
## the existing transform with no reprojection and its rect in map space is
## derived from the four constants below rather than authored anywhere.
##
## Cached statically because two surfaces draw it (the map and the minimap) and
## 5400x2700 is ~44 MB decoded. One decode, one texture, two viewers.
##
## The committed `.jpg.import` beside the asset sets `importer="keep"`, and that
## is not tidiness. Left to its default, Godot VRAM-compresses 14.6 million pixels
## the moment .godot/ is absent -- which is every fresh clone, i.e. exactly the
## case tools/run_tests.sh is meant to be fast in -- and the first headless test
## of the run sits there for the best part of ten minutes producing an artefact
## nothing reads, because the bytes below are decoded straight from the .jpg.
## `keep` copies the file and does nothing else.

const PATH := "res://assets/map/blue_marble_5400x2700.jpg"

const LON_MIN := -180.0
const LON_MAX := 180.0
const LAT_MIN := -90.0
const LAT_MAX := 90.0

static var _cached: ImageTexture = null
static var _attempted := false


## Returns null if the asset is missing or undecodable. That is a real outcome
## rather than a bug -- callers fall back to a flat sea, the same way ui_theme
## falls back to the engine's built-in sans when a font is absent. A missing
## raster should make the game look plainer, never fail to start.
static func texture() -> ImageTexture:
	if _attempted:
		return _cached
	_attempted = true

	var bytes := FileAccess.get_file_as_bytes(PATH)
	if bytes.is_empty():
		push_warning("map raster not found at %s; falling back to a flat sea" % PATH)
		return null

	var image := Image.new()
	if image.load_jpg_from_buffer(bytes) != OK:
		push_warning("map raster at %s could not be decoded" % PATH)
		return null

	_cached = ImageTexture.create_from_image(image)
	return _cached
