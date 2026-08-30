extends RefCounted

## Finds a person's portrait, or the silhouette they fall back to -- V2.3.
##
## One call, `control_for()`, is what every surface that shows a person uses:
## art where art exists, the placeholder silhouette where it does not. The
## fallback is the design rather than the failure -- docs/tiers/v2.md §3's own
## call, recorded there: a person can be authored into the register and ship
## before the art run catches up, so a missing portrait is silent, in game,
## forever. (Stale art nobody references is the other direction and is refused
## -- by tools/portraits.gd and by tests/test_portraits.gd, not here.)
##
## The bytes rule, and the reason this is not `load()`: assets/portraits/ sits
## beside the fonts, the at-icons SVGs and the Blue Marble raster, and all four
## are read off disk and decoded in memory so a fresh clone running
## tools/run_tests.sh headless -- no .godot/, no import -- sees the same game
## the editor does. `load()` returns the imported CompressedTexture2D, which
## lives in .godot/ and is absent exactly there. map_raster.gd and icon.gd
## carry the same comment; test_map_view.gd's raster check is the pattern
## tests/test_portraits.gd follows.
##
## The sweep is derived, never counted: a portrait is found by the person's own
## id and the register is the list of ids, so no roster of filenames exists
## anywhere in src/ (the warning box in docs/tiers/v2.md §3). Person 72 either
## has a PNG -- or does not, and shows the silhouette until they do.

const PORTRAITS_DIR := "res://assets/portraits/"

const MapLayers = preload("res://src/ui/map_layers.gd")

## The band a portrait sits on: that person's nation's own map tone -- V2.3,
## and the author's call rather than the tier doc's. On the People window's
## Abroad wall each leader then reads on their country's colour, the same
## colour the map fills that country with, through the same PALETTE lookup --
## identity derived from the person id's own nation prefix, never authored.
## Display-side on purpose: the committed PNG stays canonical and one art
## asset serves every situation it may be shown in.
const BAND := 3

## One decode per person per session. Portraits are 216x296 and the People
## window rebuilds its rows on every dirty sweep, so an uncached read would
## decode the same handful of PNGs once a month for no reason. A miss is cached
## too: the fallback path should not re-stat the disk every refresh either.
static var _cache := {}


## The texture, or null when this person has no portrait. The only reader of
## assets/portraits/ in the game.
static func texture_for(person_id: String) -> ImageTexture:
	if _cache.has(person_id):
		return _cache[person_id]
	var tex := _load(person_id)
	_cache[person_id] = tex
	return tex


## A Control showing this person at `size`: a TextureRect of the art, or the
## silhouette Bust. Callers hold this, add it, and never think about which one
## they got -- that is the point of there being one call.
static func control_for(person_id: String, size: Vector2) -> Control:
	var tex := texture_for(person_id)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.custom_minimum_size = size
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		# The art is generated at the source's own aspect (216x296), and every
		# caller asks for that same aspect, so COVER crops nothing in practice --
		# it is here so a caller with a differently-shaped slot degrades to a
		# centered crop rather than a squash.
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		return rect
	var bust := Bust.new()
	bust.custom_minimum_size = size
	return bust


## The face with its nation's colour behind it -- the form every in-game
## surface shows. The band is the whole "background per situation" mechanism:
## one canonical PNG, the situation painted around it.
static func framed_for(person_id: String, size: Vector2) -> Control:
	var frame := Framed.new()
	frame.custom_minimum_size = size
	frame.tone = MapLayers.swatch(MapLayers.POLITICAL, null, "", _nation_of(person_id))
	frame.add_child(control_for(person_id, size - Vector2(BAND, BAND) * 2.0))
	return frame


## Person ids are `<NATION>_<surname>` by the loader's own namespacing rule, so
## the nation is in the id and no second mapping exists to drift.
static func _nation_of(person_id: String) -> String:
	return String(person_id.split("_")[0])


static func _load(person_id: String) -> ImageTexture:
	var bytes := FileAccess.get_file_as_bytes(PORTRAITS_DIR.path_join(person_id + ".png"))
	if bytes.is_empty():
		return null
	var img := Image.new()
	if img.load_png_from_buffer(bytes) != OK:
		push_error("portrait '%s' is not a decodable PNG; falling back to the silhouette" % person_id)
		return null
	return ImageTexture.create_from_image(img)


## The face, seated on its nation's band: a plain Control painting the band and
## holding the portrait inset by INSET pixels. Not a Container on purpose -- the
## inner is placed by anchors, so the portrait keeps whatever fixed minimum the
## caller asked for and nothing relayouts it. INSET mirrors the outer BAND; an
## inner class does not see the outer script's constants, so they are two
## declarations of one number with this comment tying them.
class Framed extends Control:
	const INSET := 3.0

	var tone := Color(0.106, 0.173, 0.290)

	func _init() -> void:
		# The only child this frame ever gets is the portrait; anchoring it on
		# entry beats a container, which would own the portrait's size.
		child_entered_tree.connect(func(child: Node):
			child.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			child.offset_left = INSET
			child.offset_top = INSET
			child.offset_right = -INSET
			child.offset_bottom = -INSET
		)

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), tone)


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
		draw_line(Vector2(0, h - 1), Vector2(w, h - 1), UiTheme.ACCENT, 1.0)

	func _draw_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
		var points := PackedVector2Array()
		for i in range(24):
			var angle := TAU * i / 24.0
			points.append(center + Vector2(cos(angle) * radius.x, sin(angle) * radius.y))
		draw_colored_polygon(points, color)
