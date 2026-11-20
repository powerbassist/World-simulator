extends RefCounted

## V5.3 c' slice C (docs/design/v5.3-c-register.md section 9, "The regional warning"): a
## region in the band of a unit type (Units.band: among the nation's few furthest behind,
## and far enough behind) arrives as a warning, the register's way in ("Build here, Give
## it priority, or Leave it").
##
##   tick(ns, loader, now, notes)   the month's arrival: at most one, the region furthest
##                                  behind of every type's band not warned for that type
##                                  in the last UNIT_WARN_REARM_MONTHS, stamped in
##                                  ns.unit_warned and noted {kind "region_warning", type,
##                                  region, figure, national}. UnitBuild.tick_month calls it.
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


static func tick(ns, loader, now: int, notes: Array) -> void:
	var best_type := ""
	var best_region := ""
	var worst := -INF
	var types: Array = loader.unit_types.keys()
	types.sort()
	for type_id in types:
		if not Units.offered(loader, ns.id, type_id):
			continue
		var band := Units.band(ns, loader, type_id)
		for region in band:
			var key := "%s|%s" % [type_id, region]
			if ns.unit_warned.has(key) and now - int(ns.unit_warned[key]) < UK.UNIT_WARN_REARM_MONTHS:
				continue
			# Strictly worse wins: ties go to the first type, then the band's own order.
			if float(band[region]) > worst:
				worst = float(band[region])
				best_type = type_id
				best_region = region
	if best_type == "":
		return
	ns.unit_warned["%s|%s" % [best_type, best_region]] = now
	notes.append({"kind": KIND, "type": best_type, "region": best_region,
		"figure": Units.shown_figure(ns, loader, best_type, best_region), "national": Units.national_figure(ns, loader, best_type)})
