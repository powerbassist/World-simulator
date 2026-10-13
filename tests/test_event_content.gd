extends SceneTree

## Headless content test: re-derives event_lint.py's two book bands from shipped JSON,
## so a rule reachable only by a shell invocation is actually run by the suite.

const MEAN_BAND := 0.008
const BUSINESS_WORST_MAX := 0.30

const EventsK = preload("res://src/sim/events_constants.gd")
const LegislatureK = preload("res://src/sim/legislature_constants.gd")
const EconomyK = preload("res://src/sim/economy_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check_lint_vocabulary()
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


## tools/event_lint.py restates the closed vocabularies by hand ("two
## implementations of one schema"), and a restated list nothing compares drifts
## the day the source list grows -- `eu_member` was added to the loader's
## precondition list and the lint would have refused every gated event. Each
## list is read out of the python file's text and held equal to its source.
func _check_lint_vocabulary() -> void:
	var text := FileAccess.get_file_as_string("res://tools/event_lint.py")
	if text.is_empty():
		_fail("tools/event_lint.py unreadable")
		return
	var pairs := {
		"CATEGORIES": EventsK.CATEGORIES,
		"ON_ACTIONS": EventsK.ON_ACTIONS,
		"PRECONDITION_FIELDS": LegislatureK.PRECONDITION_FIELDS,
		"PRECONDITION_OPS": LegislatureK.PRECONDITION_OPS,
		"TAX_KEYS": EconomyK.TAX_KEYS,
		"SPENDING_KEYS": EconomyK.SPENDING_KEYS,
		"BLOC_KEYS": OpinionK.BLOC_KEYS,
	}
	for name in pairs:
		var start := text.find("\n%s = [" % name)
		if start < 0:
			_fail("event_lint.py no longer defines %s as a list literal" % name)
			continue
		var body := text.substr(start, text.find("]", start) - start)
		var found: Array[String] = []
		var rx := RegEx.new()
		rx.compile("\"([a-z_0-9<>=]+)\"")
		for m in rx.search_all(body):
			found.append(m.get_string(1))
		var want: Array[String] = []
		for item in pairs[name]:
			want.append(String(item))
		found.sort()
		want.sort()
		if found != want:
			_fail("event_lint.py %s %s differs from its source list %s" % [name, found, want])
	_check_lint_bloc_size(text)


## BLOC_SIZE is a dictionary, so the list loop above cannot hold it. The lint's
## size-weighted mean band is only the test's own band if the weights agree, and a
## re-weighted bloc in opinion_constants would otherwise leave the lint judging the
## book on the old sizes while this test judged it on the new ones.
func _check_lint_bloc_size(text: String) -> void:
	var start := text.find("\nBLOC_SIZE = {")
	if start < 0:
		_fail("event_lint.py no longer defines BLOC_SIZE as a dict literal")
		return
	var body := text.substr(start, text.find("}", start) - start)
	var rx := RegEx.new()
	rx.compile("\"([a-z_]+)\"\\s*:\\s*([0-9.]+)")
	var found: Dictionary = {}
	for m in rx.search_all(body):
		found[m.get_string(1)] = float(m.get_string(2))
	var want_keys: Array = OpinionK.BLOC_SIZE.keys()
	var found_keys: Array = found.keys()
	want_keys.sort()
	found_keys.sort()
	if found_keys != want_keys:
		_fail("event_lint.py BLOC_SIZE keys %s differ from opinion_constants %s" % [found_keys, want_keys])
		return
	for bloc in want_keys:
		if absf(float(found[bloc]) - float(OpinionK.BLOC_SIZE[bloc])) > 1e-9:
			_fail("event_lint.py BLOC_SIZE[%s] = %s differs from opinion_constants %s"
					% [bloc, found[bloc], OpinionK.BLOC_SIZE[bloc]])


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
				if OpinionK.BLOC_SIZE.has(bloc):
					mean += float(OpinionK.BLOC_SIZE[bloc]) * value
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
