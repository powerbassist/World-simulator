extends RefCounted

const Strings = preload("res://src/ui/strings.gd")
## V4.11c. What the map says about an outline -- a country drawn but not
## simulated. The text is a pure function of the loader (the outline register and
## the endowment shares), map_cities.gd's pattern: map_view draws it, the test
## reads it, and no state is involved. An outline's "trade weight" IS its share of
## world production (V4.11b's plan), so that is the line it gets.

const TOP_GOODS := 3


static func name_of(loader, id: String) -> String:
	return String(loader.outlines.get(id, {}).get("name", ""))  # i18n: row-ok not in TRANSLATABLE: a country outside the roster


## "Outline · Sugar 39% · Iron ore 16% · Meat 9% of world output", the goods
## ordered by this outline's share of world production, ties by good id so the
## line is stable; "Outline · No recorded production" when the sources name it
## nowhere.
static func profile_of(loader, id: String) -> String:
	var rows: Array = []
	for good_id in loader.commodity_endowments.keys():
		var share := float(loader.commodity_endowments[good_id].get(id, 0.0))
		if share > 0.0:
			rows.append([share, String(good_id)])
	if rows.is_empty():
		return Strings.t("Outline · No recorded production")
	rows.sort_custom(func(a, b) -> bool:
		return float(a[0]) > float(b[0]) if a[0] != b[0] else String(a[1]) < String(b[1]))
	var parts: Array[String] = []
	for row in rows.slice(0, TOP_GOODS):
		parts.append("%s %s" % [String(loader.commodity_goods[row[1]].get("name", row[1])), _percent(float(row[0]))])  # i18n: row-ok not in TRANSLATABLE: a good's name
	return Strings.t("Outline · %s of world output") % " · ".join(parts)


## Whole percent, with "<1%" for a share that would round to zero: a top-three good
## printed as "0%" reads as a contradiction.
static func _percent(share: float) -> String:
	return "<1%" if share < 0.005 else "%d%%" % roundi(share * 100.0)
