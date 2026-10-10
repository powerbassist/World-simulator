extends SceneTree

## Headless content test: re-derives event_lint.py's two book bands from shipped JSON,
## so a rule reachable only by a shell invocation is actually run by the suite.

const BLOC_SIZE := {
	"workers": 0.30, "pensioners": 0.24, "urban": 0.15,
	"rural": 0.13, "business": 0.10, "students": 0.08,
}
const MEAN_BAND := 0.008
const BUSINESS_WORST_MAX := 0.30

var _failures: Array[String] = []


func _init() -> void:
	var entries: Array = []
	var dir := DirAccess.open("res://data/events")
	if dir == null:
		_fail("data/events/ not found")
		_finish()
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/events/" + fname))
			if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("events")) != TYPE_ARRAY:
				_fail("%s: invalid event file shape" % fname)
			else:
				for event in parsed["events"]:
					if typeof(event) == TYPE_DICTIONARY:
						entries.append([fname, event])
		fname = dir.get_next()
	dir.list_dir_end()

	for message in _band_failures(entries):
		_fail(message)

	# Mutate only an in-memory deep copy: the mean band must reject a broken choice.
	var control: Array = entries.duplicate(true)
	var mutated := false
	for row in control:
		for choice in row[1].get("choices", []):
			var offset: Dictionary = choice.get("effects", {}).get("bloc_offset", {})
			if not offset.is_empty():
				offset["workers"] = float(offset.get("workers", 0.0)) + 1.0
				mutated = true
				break
		if mutated:
			break
	if not mutated:
		_fail("negative control found no bloc_offset choice to mutate")
	elif _band_failures(control).is_empty():
		_fail("negative control mutation did not violate either event-content band")

	_finish()


func _band_failures(entries: Array) -> Array[String]:
	var failures: Array[String] = []
	var business_worst := 0
	var choice_total := 0
	for row in entries:
		var fname: String = row[0]
		var event: Dictionary = row[1]
		var event_id: String = String(event.get("id", "<no id>"))
		for choice in event.get("choices", []):
			if typeof(choice) != TYPE_DICTIONARY:
				continue
			var choice_id: String = String(choice.get("id", "<no choice id>"))
			var offset: Dictionary = choice.get("effects", {}).get("bloc_offset", {})
			if offset.is_empty():
				continue
			var mean := 0.0
			var worst_bloc := ""
			var worst_value := INF
			for bloc in offset:
				var value := float(offset[bloc])
				if BLOC_SIZE.has(bloc):
					mean += float(BLOC_SIZE[bloc]) * value
				if value < worst_value:
					worst_value = value
					worst_bloc = String(bloc)
			if absf(mean) > MEAN_BAND:
				failures.append("%s: %s.%s size-weighted mean %+.4f outside +-%.3f"
						% [fname, event_id, choice_id, mean, MEAN_BAND])
			if worst_bloc == "business":
				business_worst += 1
			choice_total += 1
	if choice_total > 0:
		var share := float(business_worst) / float(choice_total)
		if share > BUSINESS_WORST_MAX:
			failures.append("event book: business is strict worst on %.1f%% of choices, over %.0f%% band"
					% [100.0 * share, 100.0 * BUSINESS_WORST_MAX])
	return failures


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_event_content: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr("FAIL: %s" % message)
	quit(1)
