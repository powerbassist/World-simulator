extends RefCounted

## Finds a person's portrait in one of five expressions, stages it into a
## scene when asked, or falls back to the silhouette -- V3.7.
##
## One call, `framed_for()`, is what every surface that shows a person uses:
## art where art exists, the placeholder silhouette where it does not, and --
## new at V3.7 -- a situational backdrop composited BEHIND the bust when the
## caller names a scene. The fallback is the design rather than the failure --
## docs/tiers/v2.md §3's own call, recorded there: a person can be authored
## into the register and ship before the art run catches up, so a missing
## portrait is silent, in game, forever. (Stale art nobody references is the
## other direction and is refused -- by tools/portraits.gd and by
## tests/test_portraits.gd, not here.)
##
## What V3.7 retired, and why the seams this file now owns exist at all: the
## V2.3 duotone ramp hid every cut-out seam for free and the nation-hue band
## was the stand-in for "background per situation". Realism replaced the
## ramp, and a photographic scene library (assets/portrait_scenes/, rendered
## by tools/backgrounds_generate.py) replaced the band. A photographic cutout
## on a photographic room is where the two meet, and SCENE_GRADE below is the
## dial that keeps the head IN the room rather than ON it.
##
## The bytes rule, and the reason this is not `load()`: assets/portraits/ and
## assets/portrait_scenes/ sit beside the fonts, the at-icons SVGs and the
## Blue Marble raster, and all are read off disk and decoded in memory so a
## fresh clone running tools/run_tests.sh headless -- no .godot/, no import --
## sees the same game the editor does. `load()` returns the imported
## CompressedTexture2D, which lives in .godot/ and is absent exactly there.
## map_raster.gd and icon.gd carry the same comment; test_map_view.gd's raster
## check is the pattern tests/test_portraits.gd follows.
##
## The sweep is derived, never counted: a portrait is found by the person's
## own id and the register is the list of ids, so no roster of filenames
## exists anywhere in src/ (the warning box in docs/tiers/v2.md §3). Person
## 214 either has art -- or does not, and shows the silhouette until they do.

const Grade = preload("res://src/ui/grade.gd")

const PORTRAITS_DIR := "res://assets/portraits/"
const SCENES_DIR := "res://assets/portrait_scenes/"

enum Emotion { NEUTRAL, PLEASED, STERN, WORRIED, WEARY }
enum Scene { NONE, OFFICE, OFFICE_NIGHT, CABINET_ROOM, PARLIAMENT_CHAMBER, PRESS_ROOM,
             TV_STUDIO, CORRIDOR, PODIUM_FLAGS, SUMMIT_HALL, STATE_DINNER,
             STREET_CITY, PLAZA_CROWD, GARDEN_PARK, AIRPORT_TARMAC }

## The enum's own file vocabulary, one name per non-NONE value. The names are
## the backdrop files tools/backgrounds_generate.py renders and the strings
## data/summits/ may carry; src/core/summit.gd's SCENES is the VALIDATION
## source for that data and tests/test_portraits.gd pins the two lists equal
## -- two sources with no test is the hand-written-list failure this repo
## keeps re-finding.
const SCENE_NAMES := {
	Scene.OFFICE: "office", Scene.OFFICE_NIGHT: "office_night",
	Scene.CABINET_ROOM: "cabinet_room", Scene.PARLIAMENT_CHAMBER: "parliament_chamber",
	Scene.PRESS_ROOM: "press_room", Scene.TV_STUDIO: "tv_studio",
	Scene.CORRIDOR: "corridor", Scene.PODIUM_FLAGS: "podium_flags",
	Scene.SUMMIT_HALL: "summit_hall", Scene.STATE_DINNER: "state_dinner",
	Scene.STREET_CITY: "street_city", Scene.PLAZA_CROWD: "plaza_crowd",
	Scene.GARDEN_PARK: "garden_park", Scene.AIRPORT_TARMAC: "airport_tarmac",
}
## Directory names under assets/portraits/, index-aligned with Emotion.
const EMOTION_DIRS := ["neutral", "pleased", "stern", "worried", "weary"]

## The realism glue, and the dial Phase B turns if a bust reads as a sticker:
## the head is modulated toward the scene's tint by `dim` so a studio-lit
## cut-out sits IN a warm evening room rather than ON it. Numbers are authored
## judgements to be tuned against real frames in Phase B -- there is no
## measuring a tint against art that does not exist yet.
const SCENE_GRADE := {
	"office": {"tint": Color(1.0, 0.97, 0.92), "dim": 0.05},
	"office_night": {"tint": Color(0.75, 0.78, 1.0), "dim": 0.22},
	"cabinet_room": {"tint": Color(1.0, 0.93, 0.85), "dim": 0.10},
	"parliament_chamber": {"tint": Color(1.0, 0.95, 0.90), "dim": 0.12},
	"press_room": {"tint": Color(0.95, 0.97, 1.0), "dim": 0.04},
	"tv_studio": {"tint": Color(0.85, 0.92, 1.0), "dim": 0.15},
	"corridor": {"tint": Color(1.0, 0.96, 0.90), "dim": 0.08},
	"podium_flags": {"tint": Color(1.0, 1.0, 0.98), "dim": 0.06},
	"summit_hall": {"tint": Color(1.0, 0.96, 0.90), "dim": 0.10},
	"state_dinner": {"tint": Color(1.0, 0.88, 0.75), "dim": 0.18},
	"street_city": {"tint": Color(0.97, 0.98, 1.0), "dim": 0.06},
	"plaza_crowd": {"tint": Color(1.0, 0.99, 0.95), "dim": 0.08},
	"garden_park": {"tint": Color(0.97, 1.0, 0.95), "dim": 0.05},
	"airport_tarmac": {"tint": Color(0.92, 0.94, 1.0), "dim": 0.14},
}

## Below this the scene is skipped regardless of what the caller asked: at
## the People window's 22x30 a backdrop is mush that costs a decode.
const SCENE_MIN_PX := 40.0

## One decode per person per emotion, and one per backdrop file, per session.
## The People window rebuilds its rows on every dirty sweep, so an uncached
## read would decode the same handful of images once a month for no reason. A
## miss is cached too: the fallback path should not re-stat the disk every
## refresh either.
static var _cache := {}
static var _scene_cache := {}


## The texture, or null when this person has no art for this emotion. The only
## reader of assets/portraits/ in the game.
static func texture_for(person_id: String, emotion: Emotion = Emotion.NEUTRAL) -> ImageTexture:
	var key := person_id + ":" + str(emotion)
	if _cache.has(key):
		return _cache[key]
	var tex := _load(person_id, emotion)
	_cache[key] = tex
	return tex


## A Control showing this person at `size`: a TextureRect of the art, or the
## silhouette Bust. Callers hold this, add it, and never think about which one
## they got -- that is the point of there being one call.
static func control_for(person_id: String, size: Vector2,
		emotion: Emotion = Emotion.NEUTRAL) -> Control:
	var tex := texture_for(person_id, emotion)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.custom_minimum_size = size
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# The art is generated at the source's own aspect (432x592), and every
		# caller asks for that same aspect, so COVER crops nothing in practice --
		# it is here so a caller with a differently-shaped slot degrades to a
		# centered crop rather than a squash.
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		return Grade.apply(rect)
	var bust := Bust.new()
	bust.custom_minimum_size = size
	return bust


## The face, staged into its situation when one is named and possible: a
## backdrop the person keeps between calls (variant picked from their own id,
## so one person's office is stably THEIR office), a contact shadow, the
## tinted bust, a light vignette. Any miss -- Scene.NONE, below the 40px
## floor, no committed backdrop file yet -- lands on the plain theme ground,
## which is what keeps the game whole in Phase A when the scene library does
## not exist yet.
static func framed_for(person_id: String, size: Vector2,
		emotion: Emotion = Emotion.NEUTRAL, scene: Scene = Scene.NONE) -> Control:
	if scene != Scene.NONE and minf(size.x, size.y) >= SCENE_MIN_PX:
		var staged := _stage(person_id, size, emotion, scene)
		if staged != null:
			return staged
	var frame := Control.new()
	frame.custom_minimum_size = size
	var inner := control_for(person_id, size, emotion)
	frame.add_child(inner)
	inner.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return frame


static func _stage(person_id: String, size: Vector2,
		emotion: Emotion, scene: Scene) -> Control:
	var scene_name: String = SCENE_NAMES[scene]
	# The person's own room first: <scene>_<NATION>_<n>.webp carries the flag
	# they serve and the view from their capital's window (rendered per nation
	# by backgrounds_generate.py --nation). The nation comes off the id's own
	# prefix, the same derivation the loader already trusts. The generic
	# <scene>_<n>.webp is the fallback -- it is deliberately flag-free, so a
	# nation without variants still reads as nowhere-in-particular rather
	# than as somebody else's country.
	var variant := _djb2(person_id + ":" + scene_name) % 3
	var nation := person_id.split("_")[0]
	var backdrop_tex := _scene_texture(
		SCENES_DIR.path_join("%s_%s_%d.webp" % [scene_name, nation, variant]))
	if backdrop_tex == null:
		backdrop_tex = _scene_texture(
			SCENES_DIR.path_join("%s_%d.webp" % [scene_name, variant]))
	if backdrop_tex == null:
		return null
	var backdrop := TextureRect.new()
	backdrop.texture = backdrop_tex
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	Grade.apply(backdrop)
	var bust := control_for(person_id, size, emotion)
	var staged := Staged.new(backdrop, bust, SCENE_GRADE[scene_name])
	staged.custom_minimum_size = size
	return staged


## The Scene enum from the name the data carries. Unknowns read NONE -- the
## loader has already refused an unknown scene at load (src/core/summit.gd),
## so this is the seatbelt, not the gate.
static func scene_from_name(name: String) -> Scene:
	for scene in SCENE_NAMES:
		if SCENE_NAMES[scene] == name:
			return scene
	return Scene.NONE


## Stable across engine versions and matching the Python djb2 the generator
## seeds with -- String.hash() is neither (tools/comfy_client.py carries the
## same five lines); the variant pick must survive re-runs.
static func _djb2(s: String) -> int:
	var h := 5381
	for b in s.to_utf8_buffer():
		h = ((h * 33) + b) & 0xFFFFFFFF
	return h


## V5.3-0 R15: the generic `scene_name` backdrop (flag-free, so it reads as
## nowhere in particular), its variant picked by `key` so one story keeps one
## picture; null when the library has none.
static func backdrop(scene_name: String, key: String) -> ImageTexture:
	return _scene_texture(SCENES_DIR.path_join("%s_%d.webp" % [scene_name, _djb2(key + ":" + scene_name) % 3]))


## WebP bytes -> texture, or null. Kept as its own function so both the bust
## and the backdrop paths decode the same way.
static func _scene_texture(path: String) -> ImageTexture:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var tex: ImageTexture = null
	var bytes := FileAccess.get_file_as_bytes(path)
	if not bytes.is_empty():
		var img := Image.new()
		if img.load_webp_from_buffer(bytes) == OK:
			tex = ImageTexture.create_from_image(img)
	_scene_cache[path] = tex
	return tex


static func _load(person_id: String, emotion: Emotion) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(
		PORTRAITS_DIR.path_join(EMOTION_DIRS[emotion]).path_join(person_id + ".webp"))
	if not bytes.is_empty():
		var img := Image.new()
		if img.load_webp_from_buffer(bytes) == OK:
			return ImageTexture.create_from_image(img)
		push_error("portrait '%s/%s' is not decodable WebP; falling back" % [person_id, EMOTION_DIRS[emotion]])
	# The LEGACY BRIDGE (flat .png fallback) died in the same commit that
	# committed the per-emotion assets -- its premise was new code over old
	# PNGs, and there are no old PNGs on the tree anymore. A person with no
	# art reads null and the silhouette answers, which is what a register a
	# generation ahead of its art has always looked like.
	return null


## The composite: backdrop, contact shadow, tinted bust, vignette. Not a
## Container, for the same reason the old Framed was not: the children are
## placed by anchors so nothing relayouts the bust. The overlays are
## MOUSE_FILTER_IGNORE because they sit ON TOP of the bust -- a vignette that
## claimed clicks would eat the surfaces under it.
class Staged extends Control:
	const UiTheme = preload("res://src/ui/ui_theme.gd")

	func _init(backdrop: TextureRect, bust: Control, grade: Dictionary) -> void:
		backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(backdrop)
		var shadow := Shadow.new()
		add_child(shadow)
		bust.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		# white.lerp(tint, dim): modulate, never a colour overlay -- the cut-
		# out's own highlights must survive the grade.
		bust.modulate = Color.WHITE.lerp(grade["tint"], grade["dim"])
		add_child(bust)
		var vignette := TextureRect.new()
		vignette.texture = _vignette_texture()
		vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(vignette)

	## Radial darkening toward the frame's edge -- the soft focus look a real
	## photograph of a person in a room carries, and one more thing that makes
	## a cut-out read as situated. Built once per stage; it is 128x176.
	static func _vignette_texture() -> GradientTexture2D:
		var grad := Gradient.new()
		grad.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.02, 0.03, 0.06, 0.30)])
		grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		var tex := GradientTexture2D.new()
		tex.gradient = grad
		tex.fill = GradientTexture2D.FILL_RADIAL
		tex.fill_from = Vector2(0.5, 0.42)
		tex.fill_to = Vector2(0.5, 0.42) + Vector2(0.75, 0.75)
		tex.width = 128
		tex.height = 176
		return tex

	## The contact shadow: two stacked translucent ellipses under the
	## shoulders, drawn where the bust's own draw cannot -- behind it.
	class Shadow extends Control:
		func _ready() -> void:
			set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			mouse_filter = Control.MOUSE_FILTER_IGNORE

		func _draw() -> void:
			var c := Vector2(size.x * 0.5, size.y * 0.94)
			_draw_blob(c, Vector2(size.x * 0.30, size.y * 0.035), 0.22)
			_draw_blob(c, Vector2(size.x * 0.20, size.y * 0.022), 0.30)

		func _draw_blob(center: Vector2, radius: Vector2, alpha: float) -> void:
			var pts := PackedVector2Array()
			for i in range(24):
				var a := TAU * i / 24.0
				pts.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y))
			draw_colored_polygon(pts, Color(0, 0, 0, alpha))


## The placeholder portrait_card.gd shipped alone at U5a, kept as the fallback
## when V2.3's art arrived. Shoulders, neck, head, and the suggestion of a
## collar -- enough to read as a person at small sizes and obviously not a
## likeness, which is still the point for anyone the art run has not reached.
class Bust extends Control:
	const UiTheme = preload("res://src/ui/ui_theme.gd")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var body := UiTheme.SLATE.lightened(0.06)
		var skin := UiTheme.TEXT_DIM.darkened(0.10)

		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.INK)

		# Shoulders: a wide, shallow ellipse cropped by the bottom edge. Wider
		# than the head by a good margin -- at this size a narrow body reads as
		# a lightbulb rather than as a person.
		_draw_ellipse(Vector2(w * 0.5, h * 1.30), Vector2(w * 0.62, h * 0.52), body)

		# Neck, then head. Drawn after the shoulders so the neck disappears
		# behind them instead of ending in a visible stump.
		draw_rect(Rect2(Vector2(w * 0.43, h * 0.44), Vector2(w * 0.14, h * 0.24)), skin)
		_draw_ellipse(Vector2(w * 0.5, h * 0.34), Vector2(w * 0.17, h * 0.20), skin)

		# Collar, as two strokes rather than a shape -- it is what makes the
		# silhouette read as a suit instead of a bust in a museum.
		draw_line(Vector2(w * 0.34, h * 0.72), Vector2(w * 0.50, h * 0.98), UiTheme.INK, 2.0)
		draw_line(Vector2(w * 0.66, h * 0.72), Vector2(w * 0.50, h * 0.98), UiTheme.INK, 2.0)

		# The brass hairline the plate carries on its top edge, repeated along
		# the bottom of the frame so the bust reads as inset rather than as a
		# hole punched in the card.
		draw_line(Vector2(0, h - 1), Vector2(w, h - 1), UiTheme.accent(), 1.0)

	func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
		var points := PackedVector2Array()
		for i in range(24):
			var angle := TAU * i / 24.0
			points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		draw_colored_polygon(points, color)
