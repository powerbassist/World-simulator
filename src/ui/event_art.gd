extends RefCounted

## The event plate library's one display read -- V4.4, on src/ui/portrait.gd's
## pattern: a pool of generated art keyed by (category, severity band), the
## variant picked at display time, stably, from the event's own id. The files
## are the pool, not the assignment.
##
## One call, `plate_texture()`, is what both surfaces that show a plate use --
## the Dispatches desk entry's header and the arrival card's title side -- so
## one crisis reads as one story in both places, and the naming rule lives in
## exactly one file. tests/test_event_art.gd enforces that: no other file
## under src/ui/ names the plate directory.
##
## The bytes rule, and the reason this is not `load()`: assets/event_art/ sits
## beside the portraits and the fonts, read off disk and decoded in memory so
## a fresh clone running the suite headless -- no .godot/, no import -- sees
## the same game the editor does. portrait.gd carries the full argument.
##
## Missing art is SILENT, the lenient precedent the portraits set: a plate the
## library does not hold returns null and the surface draws without it -- no
## hole, no error. What is NOT tolerated is a PARTIAL library once any of it
## ships, which is the test's all-or-nothing rule, not this file's.

const EventsK = preload("res://src/sim/events_constants.gd")

const ART_DIR := "res://assets/event_art/"

## The severity bands, index = severity - 1 (1 minor, 2 major, 3 critical --
## events_constants' SEVERITY_NAMES). The names are the files
## tools/event_art_generate.py renders.
const BANDS = EventsK.SEVERITY_NAMES

## Seeded variants per plate -- the pool's depth, the generator's VARIANTS.
const VARIANTS := 2


## One decode per plate path, per session; a miss is cached too, so a desk
## with no art yet does not re-stat the disk on every refresh.
static var _cache := {}


## The texture for one event's plate, or null when the library does not hold
## it. Stable: the same (category, severity, event id) always names the same
## file, so an event keeps its art between the card and the desk.
static func plate_texture(category: String, severity: int, event_id: String) -> ImageTexture:
	var path := plate_path(category, band_for(severity), variant_for(event_id, category))
	if _cache.has(path):
		return _cache[path]
	var tex: ImageTexture = null
	var bytes := FileAccess.get_file_as_bytes(path)
	if not bytes.is_empty():
		var img := Image.new()
		if img.load_webp_from_buffer(bytes) == OK:
			tex = ImageTexture.create_from_image(img)
		else:
			push_error("event plate '%s' is not decodable WebP; drawing without it" % path)
	_cache[path] = tex
	return tex


## The file a plate lives at -- also the test's walk, which demands every name
## this function can produce exists on disk and bytes-loads.
static func plate_path(category: String, band: String, variant: int) -> String:
	return ART_DIR.path_join("%s_%s_%d.webp" % [category, band, variant])


## severity 1..3 -> band name; out-of-range clamps, the loader's own bound
## already having refused anything outside at parse time (the seatbelt, not
## the gate).
static func band_for(severity: int) -> String:
	return BANDS[clampi(severity, 1, BANDS.size()) - 1]


## The variant an event shows: the backdrop library's assignment rule, ported.
## djb2 -- String.hash() is neither stable across engine bumps nor matching
## the Python the generator seeds with (portrait.gd carries the same five
## lines).
static func variant_for(event_id: String, category: String) -> int:
	return _djb2(event_id + ":" + category) % VARIANTS


static func _djb2(s: String) -> int:
	var h := 5381
	for b in s.to_utf8_buffer():
		h = ((h * 33) + b) & 0xFFFFFFFF
	return h
