extends RefCounted

## What is being built, and where -- U6c, the last clause of docs/tiers/v1.md
## section 6 and the map half V1.6f split off. The one place a project marker is
## derived; map_view.gd's _draw_markers() asks this and indexes nothing itself,
## which is map_layers.gd's contract in the same shape.
##
## **A marker is NOT a fifth entry in map_layers.LAYERS, and that is U6c's second
## call.** A LAYERS entry chooses a roster FILL -- one at a time, through a
## per-nation scalar -- where a marker is a point, is additive, and is orthogonal
## to whatever fill is up. map_view.gd's own header already settles it: "no map
## layer adds, removes or reorders a draw layer". Made a layer it would also be
## structurally dead content, because the nine never build and its value would
## read exactly 0 for nine of the ten forever -- which is V1.6f's own "a frame of
## an all-zero data layer proves nothing" arriving as a design, not as a frame.
## tests/test_map_markers.gd pins LAYERS at four so a later session moving it has
## to come and say why.
##
## Stateless and pure: a read over the loader's content and GameState, the shape
## src/sim/trade.gd and map_layers.gd both take. Nothing is cached, so a finished
## project is finished on the map the frame after it is finished in the register.

const Projects = preload("res://src/sim/projects.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Screen pixels, not degrees. A marker is a UI mark rather than geography -- the
## nation labels already work this way -- so zooming in does not grow the dot,
## and five sites on France stay five sites at every zoom.
const RADIUS := 6.0
const RING_WIDTH := 2.0

## Hover moves the STROKE and nothing else, which is U5c's rule rather than a
## style choice: brass is the accent and the fill is already carrying the
## built/building distinction, so widening the ring is the only mark left that
## does not restate a datum the player is pointing at.
const HOVER_RING_WIDTH := 4.0

## The dot sits on the site; the name sits above it, clear of the glyph.
const LABEL_OFFSET := Vector2(0.0, -RADIUS - 6.0)
const LABEL_COLOR := Color(0.94, 0.96, 1.0, 0.96)
const LABEL_SHADOW := Color(0.0, 0.0, 0.0, 0.7)


## Every project currently standing somewhere, as plain dictionaries:
## {nation_id, project_id, name, lonlat, built, months_left}.
##
## An UNSTARTED project produces nothing. A marker is a thing in the world, and
## the world does not contain a road nobody has begun -- which is also why the
## Public Works panel's third section has no counterpart here: the map says
## *where*, and an unbuilt project is nowhere.
##
## Iterates the whole roster rather than the player's nation, so there is no
## `if nation_id ==` anywhere and a later session that lets another nation build
## needs no edit here. Today the nine simply have no register entries.
static func markers(loader, state) -> Array:
	var out: Array = []
	if loader == null or state == null:
		return out

	var ids: Array = loader.nations.keys()
	ids.sort()
	for id in ids:
		var nation = loader.nations[id]
		if nation.project_sites.is_empty():
			continue
		var ns = state.nations.get(id)
		if ns == null:
			continue

		var project_ids: Array = nation.project_sites.keys()
		project_ids.sort()
		for pid in project_ids:
			var project_id := String(pid)
			if not Projects.is_started(ns, project_id):
				continue
			out.append({
				"nation_id": String(id),
				"project_id": project_id,
				"name": Projects.name_of(loader, project_id),
				"lonlat": nation.project_sites[project_id],
				"built": Projects.is_done(ns, project_id),
				"months_left": Projects.months_left(ns, project_id),
			})
	return out


## Filled once it is finished, hollow while it is being built. One shape and one
## colour, because the two states are the same object at two times -- a second
## hue would say they were two kinds of thing, and the palette has one accent.
static func is_filled(marker: Dictionary) -> bool:
	return bool(marker.get("built", false))


static func color_of(_marker: Dictionary) -> Color:
	return UiTheme.ACCENT


## What the marker says when the cursor is on it. Drawn on hover alone: the dots
## are the layer and stay at every zoom, and it is their NAMES that would collide
## on a France 60 pixels wide at the world view.
static func label_of(marker: Dictionary, loader) -> String:
	if is_filled(marker):
		return "%s  --  finished" % String(marker.get("name", ""))
	var left := int(marker.get("months_left", 0))
	var terms := Projects.terms_of(loader, String(marker.get("project_id", "")))
	var total := int(terms.get("build_months", 0))
	if total <= 0:
		return "%s  --  %d months remaining" % [String(marker.get("name", "")), left]
	# "remaining" is not decoration and the screenshot pass is what said so: the
	# frame read "12 of 96 months", which a player reads as twelve months DONE
	# when it is twelve to go. Worded exactly as projects_panel.gd words it, so
	# two surfaces on one register cannot disagree about which number that is.
	return "%s  --  %d of %d months remaining" % [String(marker.get("name", "")), left, total]
