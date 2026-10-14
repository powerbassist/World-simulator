extends SceneTree

## Headless test: godot --headless --script res://tests/test_law_content.gd
## Non-zero exit on any failure.
##
## V4.2 T7. The statute book's CONTENT shape, checked beside the loader's
## schema validation (test_data.gd boots the loader; this file reads the JSON
## directly with Godot's own parser). tools/law_lint.py checks the same
## discipline in Python -- two implementations of one schema, so the two
## cannot drift, the V4.3 orphan-rule lesson -- but a check only a shell
## invocation can reach is one the suite never runs. This file re-derives the
## headline bands: total count, theme coverage, per-bloc sign coverage, id
## uniqueness, and the linter's spread bands. It must NOT shell out.

const LegislatureK = preload("res://src/sim/legislature_constants.gd")

const THEME_KEYS := ["tax", "labour", "social", "institutional", "business"]
const BLOC_KEYS := ["workers", "pensioners", "urban", "rural", "business", "students"]

## The bands, declared in tools/law_lint.py's header BEFORE the content was
## written and restated here as constants. Total from the T7 brief; the rest
## from the register the existing 42 span.
const TOTAL_MIN := 118
const TOTAL_MAX := 122
const OFFSET_MAG_MIN := 0.04
const OFFSET_MAG_MAX := 0.40
const SPREAD_MIN := 0.2
const SPREAD_MAX := 0.8
const CENTROID_MAX := 0.6


func _init() -> void:
	var failures: Array[String] = []

	if not FileAccess.file_exists("res://tools/law_lint.py"):
		failures.append("tools/law_lint.py is missing -- the authoring linter is committed content")

	var dir := DirAccess.open("res://data/laws")
	if dir == null:
		_fail(failures, "data/laws/ not found")
		return

	var entries: Array = []  # [id, filename, dict]
	var seen_ids := {}
	var themed := {}
	var total := 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/laws/" + fname))
			if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("laws")) != TYPE_ARRAY:
				_fail(failures, "%s: invalid law file shape" % fname)
			else:
				for entry in parsed["laws"]:
					if typeof(entry) != TYPE_DICTIONARY:
						_fail(failures, "%s: non-object law entry" % fname)
						continue
					total += 1
					var id: String = entry.get("id", "")
					if seen_ids.has(id):
						_fail(failures, "%s: duplicate law id '%s' (also in %s)" % [fname, id, seen_ids[id]])
					seen_ids[id] = fname
					entries.append([id, fname, entry])
					var theme: String = entry.get("theme", "")
					if not themed.has(theme):
						themed[theme] = 0
					themed[theme] += 1
		fname = dir.get_next()
	dir.list_dir_end()

	if total < TOTAL_MIN or total > TOTAL_MAX:
		_fail(failures, "statute book carries %d laws, outside [%d, %d]" % [total, TOTAL_MIN, TOTAL_MAX])

	for theme in THEME_KEYS:
		if not themed.has(theme) or themed[theme] == 0:
			_fail(failures, "theme '%s' has no laws" % theme)

	# The spread discipline, re-derived from the JSON: magnitude register,
	# per-theme mean/max ratio, per-theme centroid, per-bloc sign coverage.
	var bloc_values := {}
	for bloc in BLOC_KEYS:
		bloc_values[bloc] = []
	for e in entries:
		var off = e[2].get("effects", {}).get("bloc_offset", {})
		if typeof(off) != TYPE_DICTIONARY:
			continue
		for bloc in off:
			if BLOC_KEYS.has(bloc):
				bloc_values[bloc].append(float(off[bloc]))

	for theme in THEME_KEYS:
		var mags: Array[float] = []
		var econ_sum := 0.0
		var soc_sum := 0.0
		var n := 0
		for e in entries:
			if e[2].get("theme", "") != theme:
				continue
			n += 1
			var pos = e[2].get("position", {})
			econ_sum += float(pos.get("economic", 0.0))
			soc_sum += float(pos.get("social", 0.0))
			var off = e[2].get("effects", {}).get("bloc_offset", {})
			if typeof(off) != TYPE_DICTIONARY:
				continue
			for v in off.values():
				mags.append(absf(float(v)))
				if absf(float(v)) < OFFSET_MAG_MIN or absf(float(v)) > OFFSET_MAG_MAX:
					_fail(failures, "%s: |bloc_offset| %.3f outside [%.2f, %.2f]"
							% [e[0], absf(float(v)), OFFSET_MAG_MIN, OFFSET_MAG_MAX])
		if n == 0:
			continue  # already failed above
		if mags.is_empty():
			_fail(failures, "theme '%s' carries no bloc_offset anywhere" % theme)
			continue
		var ratio: float = 0.0
		var mmax: float = mags.max()
		if mmax > 0.0:
			ratio = _mean(mags) / mmax
		if ratio < SPREAD_MIN or ratio > SPREAD_MAX:
			_fail(failures, "theme '%s': spread ratio %.3f outside [%.1f, %.1f]"
					% [theme, ratio, SPREAD_MIN, SPREAD_MAX])
		var econ_c: float = econ_sum / n
		var soc_c: float = soc_sum / n
		if absf(econ_c) > CENTROID_MAX or absf(soc_c) > CENTROID_MAX:
			_fail(failures, "theme '%s': centroid (%.3f, %.3f) outside [-%.1f, %.1f]"
					% [theme, econ_c, soc_c, CENTROID_MAX])

	for bloc in BLOC_KEYS:
		var pos_count := 0
		var neg_count := 0
		for v in bloc_values[bloc]:
			if v > 0.0:
				pos_count += 1
			elif v < 0.0:
				neg_count += 1
		if pos_count == 0 or neg_count == 0:
			_fail(failures, "bloc '%s' is one-signed across the whole book (+%d/-%d)"
					% [bloc, pos_count, neg_count])

	_check_lint_precondition_fields(failures)

	if failures.is_empty():
		print("test_law_content: all checks passed (%d laws across %d files)" % [total, themed.size()])
		quit(0)
	else:
		for f in failures:
			printerr(f)
		quit(1)


## tools/law_lint.py restates PRECONDITION_FIELDS by hand, and a restated list nothing
## compares drifts the day the source grows -- `eu_member` joined the loader's list and
## the lint went on refusing every law that read it. The list is parsed out of the python
## file's text and held equal to its source (tests/test_event_content.gd's approach for
## event_lint.py).
func _check_lint_precondition_fields(failures: Array[String]) -> void:
	var text := FileAccess.get_file_as_string("res://tools/law_lint.py")
	var start := text.find("\nPRECONDITION_FIELDS = [")
	if start < 0:
		_fail(failures, "law_lint.py no longer defines PRECONDITION_FIELDS as a list literal")
		return
	var body := text.substr(start, text.find("]", start) - start)
	var found: Array[String] = []
	var rx := RegEx.new()
	rx.compile("\"([a-z_0-9]+)\"")
	for m in rx.search_all(body):
		found.append(m.get_string(1))
	var want: Array[String] = []
	for item in LegislatureK.PRECONDITION_FIELDS:
		want.append(String(item))
	found.sort()
	want.sort()
	if found != want:
		_fail(failures, "law_lint.py PRECONDITION_FIELDS %s differs from legislature_constants %s" % [found, want])


func _mean(values: Array[float]) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / values.size()


func _fail(failures: Array[String], msg: String) -> void:
	failures.append(msg)
