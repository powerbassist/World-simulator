extends RefCounted

## V5.3 c' slice C (docs/design/v5.3-c-register.md section 9, "The regional warning"): a
## region in the band of a unit type (Units.band: among the nation's few furthest behind,
## and far enough behind) arrives as a warning, the register's way in ("Build here, Give
## it priority, or Leave it").
##
##   tick(state, ns, loader, now, notes)   the month's arrival: at most one, the region
##                                         furthest behind of every type's band not warned
##                                         for that type in the last UNIT_WARN_REARM_MONTHS,
##                                         stamped in ns.unit_warned and noted {kind
##                                         "region_warning", type, region, figure, national}.
##                                         UnitBuild.tick_month calls it;
##   answers(state, ns, loader, type, r)   its answers as effects: leave it ({}), or build
##                                         the type's band_units there (the estimate as
##                                         debt once, the running cost on the line a year,
##                                         the vote's bloc moves).
##
## A WARNING MOVES NO NUMBER. It is a stamp and a note: QuietMonth reads the stamp, the
## screen reads the note. Its answers are the register's own verbs, which the player
## takes or not. The stamp is {month, differs}: `differs` is EventDraw.answers_differ over
## the answers, the filter QuietMonth applies to every arrival (a desk event, a process
## ask, a request), so a warning whose build is no decision on the strip's own bars does
## not end the quiet month -- the same rule, not a second one.
##
## THE PLAYER ONLY, as the register is (the AI's use of it is 0.6). Rule 1: no nation id;
## a nation with no stock file for a type is never warned for it.

const UK = preload("res://src/sim/units_constants.gd")
const Units = preload("res://src/sim/units.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const EventDraw = preload("res://src/sim/event_draw.gd")
# unit_build.gd calls tick(); static calls only, as finance_rows' pair with it.
const UnitBuild = preload("res://src/sim/unit_build.gd")

const KIND := "region_warning"


static func tick(state, ns, loader, now: int, notes: Array) -> void:
	var best_type := ""
	var best_region := ""
	var worst := -INF
	var types: Array = loader.unit_types.keys()
	types.sort()
	for type_id in types:
		var band := Units.band(ns, loader, type_id)
		var building := _building(ns, type_id)
		for region in band:
			var key := "%s|%s" % [type_id, region]
			if ns.unit_warned.has(key) and now - int(ns.unit_warned[key].get("month", -UK.UNIT_WARN_REARM_MONTHS)) < UK.UNIT_WARN_REARM_MONTHS:
				continue
			# Its answer is under way (pass 1 on #425): no "build here" until the build opens.
			if building.has(region):
				continue
			# Strictly worse wins: ties go to the first type, then the band's own order.
			if float(band[region]) > worst:
				worst = float(band[region])
				best_type = type_id
				best_region = region
	if best_type == "":
		return
	ns.unit_warned["%s|%s" % [best_type, best_region]] = {"month": now,
		"differs": EventDraw.answers_differ(ns, answers(state, ns, loader, best_type, best_region))}
	notes.append({"kind": KIND, "type": best_type, "region": best_region,
		"figure": Units.shown_figure(ns, loader, best_type, best_region), "national": Units.national_figure(ns, loader, best_type)})


## The regions where a build of the type is under way: {region: true}.
static func _building(ns, type_id: String) -> Dictionary:
	var out := {}
	for p in ns.unit_programmes:
		if String(p.get("type", "")) == type_id and String(p.get("op", "")) == UK.OP_BUILD \
				and String(p.get("state", "")) == UK.STATE_BUILDING:
			for r in p.get("rows", []):
				out[String(r.get("region", ""))] = true
	return out


static func answers(state, ns, loader, type_id: String, region_id: String) -> Array:
	var t: Dictionary = loader.unit_types[type_id]
	var n := int(t["band_units"])
	var row := {"type": type_id, "op": UK.OP_BUILD, "rows": [{"region": region_id, "units": n}]}
	var gdp_m := float(ns.gdp_eur_bn) * 1000.0
	var running := 100.0 * float(n) * float((t["running_eur_m"] as Dictionary).get(ns.id, 0.0)) / gdp_m if gdp_m > 0.0 else 0.0
	return [{}, {"bloc_offset": UnitBuild.blocs(ns, loader, row),
		"debt_eur_bn": float(UnitPrice.quote(state, ns, loader, row)["estimate_eur_m"]) / 1000.0,
		"spending_pct_gdp": {String(t["line"]): running}}]
