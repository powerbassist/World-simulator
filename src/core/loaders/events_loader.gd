extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. data/events/ and data/summits/: the event book and the summit scenes.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator and the only caller, every register still lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim, its members read through `loader.`.

const C = preload("res://src/sim/economy_constants.gd")
const GameEvent = preload("res://src/core/event.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Summit = preload("res://src/core/summit.gd")


## V1.8. _load_projects()'s shape, and the seventh directory to take it.
##
## THE CROSS-FILE CHECK IS THE HALF WORTH HAVING, and here it is a different half from
## every previous one. Per-entry validation lives in src/core/event.gd; what only this
## function can see is whether the SET is coherent -- that no two entries define the
## same event, and that no two events name the same subject office AND the same
## precondition field, which is the content-level shape of the same collision
## _validate_companies() refuses when a sector holds one named firm. Two scandals about
## the prime minister with identical gates are one event authored twice, and the second
## can only ever fire in the months the first did not.
static func load_events(loader, events_dir: String) -> void:
	var da := DirAccess.open(events_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % events_dir)
		return

	var filenames: Array[String] = []
	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if not da.current_is_dir() and file_name.ends_with(".json"):
			filenames.append(file_name)
		file_name = da.get_next()
	da.list_dir_end()
	filenames.sort()

	var seen_ids := {}
	var gates := {}   # "office|field,field" -> the event id that already claims it
	for fname in filenames:
		var path := events_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("events")) != TYPE_ARRAY:
			loader.errors.append("%s: invalid event file, expected {\"events\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["events"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: events[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var ev = GameEvent.from_dict(
				entry, fname, per_file_errors,
				C.TAX_KEYS, C.SPENDING_KEYS, OpinionK.BLOC_KEYS, C.SECTOR_TREND.keys()
			)
			loader.errors.append_array(per_file_errors)
			if ev.id == "":
				continue
			if seen_ids.has(ev.id):
				loader.errors.append("%s: duplicate event id '%s'" % [fname, ev.id])
			seen_ids[ev.id] = true

			var fields: Array[String] = []
			var names_a_gate := false
			for cond in ev.preconditions:
				# Membership is a SCOPE and not a trigger, so it never makes an
				# event "name a gate" (below) -- but it stays in the KEY: an EU-only
				# event and an ungated sibling with the same subject and other gate
				# fire in DIFFERENT months (the sibling also fires for a non-member),
				# so they are two events, not one authored twice.
				if cond["field"] != "eu_member":
					names_a_gate = true
				fields.append("%s%s%s" % [cond["field"], cond["op"], str(cond["value"])])
			fields.sort()
			# V3.5f: A GATE IS WHAT AN EVENT NAMES. This check's target is the gate
			# somebody wrote twice -- "two scandals about the prime minister with
			# identical gates" -- but the empty join below made every event with no
			# subject office and no precondition collide with the first such event
			# loaded, and the old climate.json's river_flood against
			# broadcast_charter was the first false positive: a pure-hazard crisis
			# about nobody is a shape the content owns (the scandals' own argument,
			# one file over), and two such events are separated by id, body,
			# likelihood, once-ness and the per-event hazard hash, with content order
			# deciding only which of two same-month draws goes first --
			# src/sim/events.gd's own comment. The check keeps its full strength for
			# every event that names a subject or a gate.
			# The KEY carries on_action too: a hazard event and a hook event with the
			# same subject and gate are unrelated occasions (the hazard draws on the
			# state, the hook on a register the machines stamp), not one event twice.
			if ev.has_subject() or names_a_gate:
				var gate := "%s|%s|%s" % [ev.subject_office, ev.on_action, ",".join(fields)]
				if gates.has(gate):
					loader.errors.append("%s: '%s' has the same subject and the same gate as '%s' -- two events that can only ever fire in the same months are one event authored twice, and the second fires only where the first did not" % [
						fname, ev.id, str(gates[gate])
					])
				gates[gate] = ev.id
			loader.events.append(ev)

	# V4.4: the checks that need the whole set in hand, _validate_people's pattern --
	# a chain may arm an event authored in another file, and a cycle is a property of
	# the SET, not of any one event. Edges run announcing-event -> armed-event; an
	# event's own choices are alternatives, so one choice's arms never reaches
	# another's, but an armed event arms in turn when IT is answered, which is where
	# a cycle would live.
	# A chain TARGET may be a hook event: both doors run in the same tick (armed
	# chains first, then hooks), but events.gd's _deliver stamps a cooldown of at
	# least the next month on every delivery and every door checks it, so the hook
	# door cannot deliver what the chain door just delivered
	# (tests/test_events.gd pins it at runtime).
	var arm_edges := {}
	for ev in loader.events:
		for choice in ev.choices:
			var arms: Dictionary = choice.get("arms", {})
			if arms.is_empty():
				continue
			var target := String(arms.get("event_id", ""))
			if not seen_ids.has(target):
				loader.errors.append("%s: '%s' arms '%s', which is not a loaded event -- a chain that points at nothing can never land" % [
					events_dir, ev.id, target
				])
				continue
			if not arm_edges.has(ev.id):
				arm_edges[ev.id] = []
			arm_edges[ev.id].append(target)
	for start_id in arm_edges.keys():
		# Depth-first walk carrying its own path; an edge back onto the path is the
		# cycle. One report per start is enough -- the author fixes the loop, not
		# every entry into it.
		var found_cycle := false
		var frontier: Array = [[start_id, [start_id]]]
		while not frontier.is_empty() and not found_cycle:
			var frame: Array = frontier.pop_back()
			var node: String = frame[0]
			var node_path: Array = frame[1]
			for next_id in arm_edges.get(node, []):
				if node_path.has(next_id):
					loader.errors.append("%s: the chain through '%s' is a cycle ('%s' -> '%s' closes it) -- a follow-up that re-arms its own ancestry never runs out of future" % [
						events_dir, start_id, node, next_id
					])
					found_cycle = true
					break
				frontier.append([next_id, node_path + [next_id]])


## V2.4b. One summit = two files sharing an id: <ID>.dialogue is the scene in
## dialogue_manager syntax, <ID>.json the sidecar that names it and prices its
## responses. The id is NATION_prefixed and self-describing the way a city id
## is, and the join between the two files is the response LABEL -- validated
## here, loudly, because a scene that offers a choice nothing prices ships a
## live button that refuses silently, which this project has paid for twice.
## The dialogue itself compiles at DRAW time through the addon, so what the
## loader stores is text and the compiler's errors arrive where they can name
## the file they came from.
static func load_summits(loader, summits_dir: String) -> void:
	var da := DirAccess.open(summits_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % summits_dir)
		return

	var ids: Array[String] = []
	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if not da.current_is_dir() and file_name.ends_with(".dialogue"):
			ids.append(file_name.trim_suffix(".dialogue"))
		file_name = da.get_next()
	da.list_dir_end()
	ids.sort()

	for sid in ids:
		var nation_id := sid.split("_")[0] if sid.contains("_") else ""
		if not loader.nations.has(nation_id):
			loader.errors.append("%s: id '%s' does not begin with a nation id -- a summit belongs to a partner" % [sid, sid])
			continue

		var text := FileAccess.get_file_as_string(summits_dir.path_join(sid + ".dialogue"))
		var sidecar_text := FileAccess.get_file_as_string(summits_dir.path_join(sid + ".json"))
		if text.is_empty() or sidecar_text.is_empty():
			loader.errors.append("%s: could not read the .dialogue or its .json sidecar" % sid)
			continue
		var parsed = JSON.parse_string(sidecar_text)
		if typeof(parsed) != TYPE_DICTIONARY:
			loader.errors.append("%s: invalid sidecar, expected an object" % sid)
			continue

		var per_file_errors: Array[String] = []
		var summit = Summit.from_dict(
			text, nation_id, sid, parsed, sid, per_file_errors,
			C.TAX_KEYS, C.SPENDING_KEYS, OpinionK.BLOC_KEYS, C.SECTOR_TREND.keys()
		)
		loader.errors.append_array(per_file_errors)
		if not loader.summits.has(nation_id):
			loader.summits[nation_id] = []
		loader.summits[nation_id].append(summit)
