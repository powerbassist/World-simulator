extends RefCounted

## V5.3 c' slice C (docs/design/v5.3-c-register.md section 9, "The regional warning"): a
## region whose shown figure of a unit type stands far enough behind the nation's arrives
## as a warning, the register's way in ("Build here, Give it priority, or Leave it").
##
##   behind(ns, loader, type, region)   how far the region's shown figure stands behind
##                                      the nation's, as a share of it, + when worse;
##   in_band(ns, loader, type, region)  whether that is far enough to warn, read live, so
##                                      a build that closes the gap clears it at once;
##   tick(ns, loader, now, notes)       the month's arrival: at most one, the worst region
##                                      in band not warned for that type in the last
##                                      UNIT_WARN_REARM_MONTHS, stamped in ns.unit_warned
##                                      and noted {kind "region_warning", type, region,
##                                      figure, national}. UnitBuild.tick_month calls it.
##
## A WARNING MOVES NO NUMBER. It is a stamp and a note: QuietMonth reads the stamp (an
## arrival ends the quiet month), the screen reads the note. Its answers are the
## register's own verbs, which the player takes or not.
##
## THE PLAYER ONLY, as the register is (the AI's use of it is 0.6). Rule 1: no nation id;
## a nation with no stock file for a type is never warned for it.

const UK = preload("res://src/sim/units_constants.gd")
const Units = preload("res://src/sim/units.gd")

const KIND := "region_warning"


static func behind(ns, loader, type_id: String, region_id: String) -> float:
	return _behind(loader, type_id, Units.shown_figure(ns, loader, type_id, region_id), Units.national_figure(ns, loader, type_id))


static func in_band(ns, loader, type_id: String, region_id: String) -> bool:
	if not loader.unit_types.has(type_id) or Units.start_capacity(loader, ns.id, type_id, region_id) <= 0.0:
		return false
	return behind(ns, loader, type_id, region_id) >= UK.UNIT_REGION_BAND


static func tick(ns, loader, now: int, notes: Array) -> void:
	var best := {}
	var worst := -INF
	var types: Array = loader.unit_types.keys()
	types.sort()
	for type_id in types:
		if not Units.offered(loader, ns.id, type_id):
			continue
		# One basis for every region of the type (Units.preview with nothing placed).
		var shown := Units.preview(ns, loader, type_id, {})
		var national := Units.national_figure(ns, loader, type_id)
		for r in loader.regions.get(ns.id, []):
			var key := "%s|%s" % [type_id, r.id]
			if Units.start_capacity(loader, ns.id, type_id, r.id) <= 0.0 \
					or (ns.unit_warned.has(key) and now - int(ns.unit_warned[key]) < UK.UNIT_WARN_REARM_MONTHS):
				continue
			var gap := _behind(loader, type_id, float(shown[r.id]), national)
			# Strictly worse wins: ties go to the first type, then the regions' file order.
			if gap >= UK.UNIT_REGION_BAND and gap > worst:
				worst = gap
				best = {"kind": KIND, "type": type_id, "region": String(r.id), "figure": float(shown[r.id]), "national": national}
	if best.is_empty():
		return
	ns.unit_warned["%s|%s" % [best["type"], best["region"]]] = now
	notes.append(best)


static func _behind(loader, type_id: String, figure: float, national: float) -> float:
	if national == 0.0:
		return 0.0
	var sign := 1.0 if String(loader.unit_types[type_id]["figure"]["better"]) == "lower" else -1.0
	return sign * (figure / national - 1.0)
