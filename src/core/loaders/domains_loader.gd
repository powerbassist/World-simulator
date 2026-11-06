extends RefCounted

## V5.3 a: data/domains/<line>.json, each spending line split into sectors (the
## shape agreed between Content and Systems, 2026-11-01; docs/design/v5.3-ab.md
## 3.1). One file per line of economy_constants.SPENDING_KEYS:
##
##   {line, sectors: [{id, name, summary, codes: [string],
##                     quantity: {id, unit, better: "higher" | "lower"},
##                     start: {<NATION> | "default": {share, quantity, year, source,
##                                                   note?, need_drift_pct_year?,
##                                                   need_source?}}}]}
##
## The facts are Content's (sourced, one row per sector); the tuning is
## src/sim/domains_constants.gd's (a sector id the table does not know for its line
## is refused: it would move nothing, band A2). A missing directory is no sectors
## at all: every read falls back to the line's total, which is what the game was
## before V5.3 a. A bad row is a load error, never a skipped line.

const EK = preload("res://src/sim/economy_constants.gd")
const DK = preload("res://src/sim/domains_constants.gd")


static func load_domains(loader, dir: String) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	var files: Array[String] = []
	for f in da.get_files():
		if String(f).ends_with(".json"):
			files.append(String(f))
	files.sort()
	for fname in files:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(fname)))
		if typeof(parsed) != TYPE_DICTIONARY:
			loader.errors.append("%s: missing or invalid JSON" % fname)
			continue
		var errors: Array[String] = []
		var line := parse_line(loader, parsed, fname, errors)
		loader.errors.append_array(errors)
		if errors.is_empty():
			loader.domains[String(line["line"])] = line


## One line's file, validated, with each nation's shares renormalised to exactly
## 1.0. Public so tests/test_domains.gd can feed it a bad row without a file on
## disk. Returns {line, sectors} ({} with errors appended when it refuses).
static func parse_line(loader, parsed: Dictionary, fname: String, errors: Array[String]) -> Dictionary:
	var line := String(parsed.get("line", ""))
	if not EK.SPENDING_KEYS.has(line):
		errors.append("%s: 'line' must be one of %s" % [fname, str(EK.SPENDING_KEYS)])
		return {}
	if fname.get_basename() != line:
		errors.append("%s: holds line '%s'; one file per line, named after it" % [fname, line])
		return {}
	var rows = parsed.get("sectors")
	if typeof(rows) != TYPE_ARRAY or (rows as Array).size() < 2:
		errors.append("%s: 'sectors' must list at least two sectors (one is no choice)" % fname)
		return {}
	var sectors: Array = []
	var keys := {}
	for i in (rows as Array).size():
		var s = _sector(loader, rows[i], line, "%s: sectors[%d]" % [fname, i], errors)
		if s.is_empty():
			return {}
		for other in sectors:
			if String(other["id"]) == String(s["id"]):
				errors.append("%s: sector '%s' is listed twice" % [fname, s["id"]])
				return {}
		if i == 0:
			keys = (s["start"] as Dictionary).duplicate()
		elif not _same_keys(keys, s["start"]):
			errors.append("%s: sector '%s' starts in other nations than '%s'; every start key must be in every sector, so its shares sum to 1"
				% [fname, s["id"], sectors[0]["id"]])
			return {}
		sectors.append(s)
	for nation in keys:
		var total := 0.0
		for s in sectors:
			total += float(s["start"][nation]["share"])
		if absf(total - 1.0) > DK.SHARE_SUM_TOLERANCE:
			errors.append("%s: %s's shares sum to %.4f, not 1.0" % [fname, nation, total])
			return {}
		for s in sectors:
			s["start"][nation]["share"] = float(s["start"][nation]["share"]) / total
	return {"line": line, "sectors": sectors}


static func _sector(loader, raw, line: String, where: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: not an object" % where)
		return {}
	for key in ["id", "name", "summary"]:
		if typeof(raw.get(key)) != TYPE_STRING or String(raw[key]) == "":
			errors.append("%s: missing or empty string '%s'" % [where, key])
			return {}
	var id := String(raw["id"])
	if not (DK.SECTOR_IDS.get(line, []) as Array).has(id):
		errors.append("%s: '%s' is not a %s sector domains_constants.gd knows (it would move nothing)" % [where, id, line])
		return {}
	var codes = raw.get("codes")
	if typeof(codes) != TYPE_ARRAY or (codes as Array).any(func(c) -> bool: return typeof(c) != TYPE_STRING):
		errors.append("%s: 'codes' must be a list of strings" % where)
		return {}
	var q = raw.get("quantity")
	if typeof(q) != TYPE_DICTIONARY or typeof(q.get("id")) != TYPE_STRING or typeof(q.get("unit")) != TYPE_STRING \
			or not ["higher", "lower"].has(String(q.get("better", ""))):
		errors.append("%s: 'quantity' needs an id, a unit and better: higher or lower" % where)
		return {}
	var start = raw.get("start")
	if typeof(start) != TYPE_DICTIONARY or not (start as Dictionary).has("default"):
		errors.append("%s: 'start' needs a 'default' row" % where)
		return {}
	var out_start := {}
	for nation in start:
		if nation != "default" and not loader.nations.has(nation):
			errors.append("%s: start names '%s', not a roster nation" % [where, nation])
			return {}
		var row = start[nation]
		if typeof(row) != TYPE_DICTIONARY or typeof(row.get("share")) != TYPE_FLOAT \
				or float(row["share"]) <= 0.0 or float(row["share"]) > 1.0:
			errors.append("%s: %s's share must be a number in (0, 1]" % [where, nation])
			return {}
		if typeof(row.get("quantity")) != TYPE_FLOAT or float(row["quantity"]) <= 0.0:
			errors.append("%s: %s's quantity must be a number above 0" % [where, nation])
			return {}
		if typeof(row.get("source")) != TYPE_STRING or String(row["source"]) == "" or typeof(row.get("year")) != TYPE_FLOAT:
			errors.append("%s: %s needs a source and a year" % [where, nation])
			return {}
		var need = row.get("need_drift_pct_year", 0.0)
		if typeof(need) != TYPE_FLOAT or absf(float(need)) > DK.NEED_DRIFT_MAX_PCT_YEAR:
			errors.append("%s: %s's need_drift_pct_year must be a number within %.1f a year" % [where, nation, DK.NEED_DRIFT_MAX_PCT_YEAR])
			return {}
		if float(need) != 0.0 and String(row.get("need_source", "")) == "":
			errors.append("%s: %s has a need drift and no need_source" % [where, nation])
			return {}
		out_start[String(nation)] = {"share": float(row["share"]), "quantity": float(row["quantity"]),
			"year": int(row["year"]), "source": String(row["source"]), "note": String(row.get("note", "")),
			"need_drift_pct_year": float(need), "need_source": String(row.get("need_source", ""))}
	return {"id": id, "name": String(raw["name"]), "summary": String(raw["summary"]),
		"codes": (codes as Array).duplicate(), "quantity": (q as Dictionary).duplicate(), "start": out_start}


static func _same_keys(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k):
			return false
	return true
