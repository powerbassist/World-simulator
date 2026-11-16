extends RefCounted

## What each region looks like on the map -- screen 6, slice 2 (the author's direction A).
## One measure at a time, the rail's chips pick it:
##   jobless    the region's unemployment against the nation's (the default: the brief's
##              "where", and the one measure on which most regions sit near the nation);
##   per_head   output per head against the nation's (Ile-de-France at 160 % puts most
##              regions under it, so this tint lights most of the map, and says so);
##   change     the region's jobless over the sample against the nation's change.
## A tone is a STATUS (UiTheme.BAD, WARN, GOOD), never the accent, and always has its glyph
## beside the figure, so the map never rests on colour alone: ▲ well worse, △ worse,
## ▼ better (the change only). A region near the nation has no tone and no glyph.
## A pure read over the state; region_sheet.gd's 12-month line reads changes() too.

const Regions = preload("res://src/sim/regions.gd")
const RegionRead = preload("res://src/sim/region_read.gd")
const Migration = preload("res://src/sim/migration.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")

const MEASURES := ["jobless", "per_head", "change"]
## The bands, against the nation: a ratio for the two levels, points for the change.
const LEVEL_WORSE := 1.05
const LEVEL_MUCH_WORSE := 1.15
const CHANGE_WORSE := 0.1
const CHANGE_MUCH_WORSE := 0.3
const NONE := Color(0, 0, 0, 0)


## The chip's words.
static func label(measure: String) -> String:
	match measure:
		"per_head": return Strings.t("Per head")
		"change": return Strings.t("12 months")
	return Strings.t("Jobless")


## region id -> {tone: Color, label: String} for the measure.
static func rows(state, ns, regions: Array, access: Dictionary, measure: String) -> Dictionary:
	var out := {}
	var sited: Dictionary = state.project_sited_pct.get(ns.id, {})
	var moved := changes(ns, regions)
	var nation := float(ns.unemployment_pct)
	for region in regions:
		var id := String(region.id)
		match measure:
			"per_head":
				var index := Regions.gdp_per_head_index(ns, regions, id, Migration.region_share(ns, id))
				out[id] = _row(1.0 / index if index > 0.0 else 0.0, LEVEL_WORSE, LEVEL_MUCH_WORSE, "%s %%" % Num.f(index * 100.0, 0))
			"change":
				if not (moved["here"] as Dictionary).has(id):
					out[id] = {"tone": NONE, "label": ""}
					continue
				var d := float(moved["here"][id])
				var rel := d - float(moved["nation"])
				var text := Strings.t("%s pt") % Num.fs(d, 1)
				if rel <= -CHANGE_WORSE:
					out[id] = {"tone": UiTheme.GOOD, "label": "▼ " + text}
				else:
					out[id] = _row(rel, CHANGE_WORSE, CHANGE_MUCH_WORSE, text)
			_:
				var u := Regions.unemployment_pct(ns, regions, id, access, sited)
				out[id] = _row(u / nation if nation > 0.0 else 0.0, LEVEL_WORSE, LEVEL_MUCH_WORSE, "%s %%" % Num.f(u, 1))
	return out


## Each region's jobless change over the sample, and the nation's, weighted by people
## (the regions' own, so the two are one measure). {here: {id: points}, nation: points};
## `here` is empty until the sample holds two months.
static func changes(ns, regions: Array) -> Dictionary:
	var here := {}
	var weight := 0.0
	var sum := 0.0
	if RegionRead.months_held(ns) >= 2:
		for region in regions:
			var series: Array = ns.region_history.get(String(region.id), {}).get("unemployment", [])
			if series.size() < 2:
				continue
			var d := float(series[-1]) - float(series[0])
			var w := Migration.region_share(ns, region.id)
			here[String(region.id)] = d
			sum += d * w
			weight += w
	return {"here": here, "nation": sum / weight if weight > 0.0 else 0.0}


static func _row(worse: float, band: float, much: float, text: String) -> Dictionary:
	if worse >= much:
		return {"tone": UiTheme.BAD, "label": "▲ " + text}
	if worse >= band:
		return {"tone": UiTheme.WARN, "label": "△ " + text}
	return {"tone": NONE, "label": text}
