extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. data/programme/: the government programme entries, their triggers and their effects.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too), every register lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim (now <ThisLoader>.<name>), its members read
## through `loader.`.

const C = preload("res://src/sim/economy_constants.gd")
const Law = preload("res://src/core/law.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")


## Reads every data/programme/*.json file -- {"programme": [...]}, the directory-scan
## shape CampaignLoader.load_pledges uses. Entries are kept as raw validated Dictionaries: the
## extraction below is the validation, and src/sim/programme.gd casts on every read.
##
## THE LOUD REFUSALS, on the summits' sidecar contract's reasoning:
##   - an entry carrying a field outside ProgrammeK.ENTRY_FIELDS is a load error,
##     because a typo'd field must never be an inert half of an entry nobody reads;
##   - every effect slot (`immediate`, `on_complete`, `on_fail`, `on_invalid`,
##     `on_timeout`) is priced only on the SHARED channels, extracted through
##     Law.extract_shared_effects -- the one applier events already use, not a
##     second. `institutional` is deliberately absent: a programme is not an
##     amendment, and a conclusion that rewrote the constitution as a side effect
##     of missing a deficit target is not a thing this schema may express;
##   - an entry with NO trigger and NO deadline is refused, because an entry that
##     could never conclude would tick forever.
static func load_programme(loader, programme_dir: String) -> void:
	var da := DirAccess.open(programme_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % programme_dir)
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
	for fname in filenames:
		var path := programme_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("programme")) != TYPE_ARRAY:
			loader.errors.append("%s: invalid programme file, expected {\"programme\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["programme"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: programme[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var terms := extract_programme_entry(loader, entry, fname, per_file_errors)
			loader.errors.append_array(per_file_errors)
			if terms.is_empty():
				continue
			if seen_ids.has(terms["id"]):
				loader.errors.append("%s: duplicate programme entry id '%s' -- two entries sharing one id would be two programmes the player could only ever choose one of" % [fname, terms["id"]])
			seen_ids[terms["id"]] = true
			loader.programme.append(terms)


static func extract_programme_entry(loader, d: Dictionary, filename: String, errors: Array[String]) -> Dictionary:
	# The unknown-field refusal FIRST: an entry carrying anything beside the schema
	# does not get the courtesy of a partial load.
	for key in d.keys():
		if not ProgrammeK.ENTRY_FIELDS.has(String(key)):
			errors.append("%s: programme entry carries '%s', which is not a recognised field (%s)" % [
				filename, str(key), str(ProgrammeK.ENTRY_FIELDS)
			])

	# The other half of the whitelist, enforced: an entry missing a required
	# field is refused even where the per-field checks below could default it.
	# Each of these is validated in its own right further down; this loop is
	# what makes ABSENCE itself the load error REQUIRED_FIELDS promises.
	for key in ProgrammeK.REQUIRED_FIELDS:
		if not d.has(key):
			errors.append("%s: programme entry '%s' is missing required field '%s' (%s)" % [
				filename, str(d.get("id", "?")), str(key), str(ProgrammeK.REQUIRED_FIELDS)
			])

	var out := {}

	var id = d.get("id", "")
	if typeof(id) != TYPE_STRING or id == "":
		errors.append("%s: programme entry missing or invalid string field 'id'" % filename)
		return {}
	out["id"] = id

	var name = d.get("name", "")
	if typeof(name) != TYPE_STRING or name == "":
		errors.append("%s: %s missing or invalid string field 'name' -- the offer needs the noun" % [filename, id])
	else:
		out["name"] = name

	var summary = d.get("summary", "")
	if typeof(summary) != TYPE_STRING or String(summary).strip_edges() == "":
		errors.append("%s: %s summary must be a non-empty string -- the offer prints it under the name" % [filename, id])
	else:
		out["summary"] = summary

	var group = d.get("group", "")
	if typeof(group) != TYPE_STRING or not ProgrammeK.GROUPS.has(group):
		errors.append("%s: %s group '%s' is not one of the five (%s)" % [filename, id, str(group), str(ProgrammeK.GROUPS)])
	else:
		out["group"] = group

	var activation = d.get("activation", "")
	if typeof(activation) != TYPE_STRING or not ProgrammeK.ACTIVATIONS.has(activation):
		errors.append("%s: %s activation '%s' is not one of the four (%s)" % [filename, id, str(activation), str(ProgrammeK.ACTIVATIONS)])
	else:
		out["activation"] = activation

	var timeout = d.get("timeout_months", -1)
	if not (typeof(timeout) == TYPE_INT or typeof(timeout) == TYPE_FLOAT) or int(timeout) < 0:
		errors.append("%s: %s timeout_months must be a non-negative number -- 0 means no deadline, and an author who has not decided is an error rather than a default" % [filename, id])
	else:
		out["timeout_months"] = int(timeout)

	var current_value = d.get("current_value", "")
	if typeof(current_value) != TYPE_STRING or not ProgrammeK.TRIGGER_FIELDS.has(current_value):
		errors.append("%s: %s current_value '%s' is not a figure a trigger can read (%s)" % [filename, id, str(current_value), str(ProgrammeK.TRIGGER_FIELDS)])
	else:
		out["current_value"] = current_value

	if d.has("goal_value") and (typeof(d["goal_value"]) == TYPE_INT or typeof(d["goal_value"]) == TYPE_FLOAT):
		out["goal_value"] = float(d["goal_value"])
	else:
		errors.append("%s: %s goal_value is missing or not numeric" % [filename, id])

	var progressbar = d.get("progressbar", "")
	if typeof(progressbar) != TYPE_STRING or not ProgrammeK.PROGRESS_DIRECTIONS.has(progressbar):
		errors.append("%s: %s progressbar '%s' is not a direction (%s)" % [filename, id, str(progressbar), str(ProgrammeK.PROGRESS_DIRECTIONS)])
	else:
		out["progressbar"] = progressbar

	if d.has("weight"):
		if typeof(d["weight"]) == TYPE_INT or typeof(d["weight"]) == TYPE_FLOAT:
			out["weight"] = float(d["weight"])
		else:
			errors.append("%s: %s weight must be numeric" % [filename, id])
	if d.has("pinned"):
		if typeof(d["pinned"]) == TYPE_BOOL:
			out["pinned"] = d["pinned"]
		else:
			errors.append("%s: %s pinned must be a bool" % [filename, id])

	var raw_possible = d.get("possible", [])
	if typeof(raw_possible) != TYPE_ARRAY:
		errors.append("%s: %s possible must be an array of {field, op, value}" % [filename, id])
	else:
		var possible: Array = []
		for i in raw_possible.size():
			var trigger := extract_programme_trigger(loader, raw_possible[i], id, filename, "possible[%d]" % i, errors)
			if not trigger.is_empty():
				possible.append(trigger)
		if not possible.is_empty():
			out["possible"] = possible

	for key in ["complete", "fail", "invalid"]:
		if d.has(key):
			var trigger := extract_programme_trigger(loader, d[key], id, filename, key, errors)
			if not trigger.is_empty():
				out[key] = trigger

	for key in ["immediate", "on_complete", "on_fail", "on_invalid", "on_timeout"]:
		if d.has(key):
			var effects := extract_programme_effects(loader, d[key], id, filename, key, errors)
			if not effects.is_empty():
				out[key] = effects

	# An entry that could never conclude would tick forever, so it is a load error
	# and not an authoring choice. Any one trigger suffices; so does a deadline.
	if not out.has("complete") and not out.has("fail") and not out.has("invalid") \
			and int(out.get("timeout_months", 0)) <= 0:
		errors.append("%s: %s has no trigger and no deadline -- it could never conclude" % [filename, id])

	return out


static func extract_programme_trigger(loader, raw, owner_id: String, filename: String, what: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s %s must be an object {field, op, value}" % [filename, owner_id, what])
		return {}

	var field = raw.get("field", "")
	if typeof(field) != TYPE_STRING or not ProgrammeK.TRIGGER_FIELDS.has(field):
		errors.append("%s: %s %s.field '%s' is not a recognised field (%s)" % [
			filename, owner_id, what, str(field), str(ProgrammeK.TRIGGER_FIELDS)
		])
		return {}

	var op = raw.get("op", "")
	if typeof(op) != TYPE_STRING or not ProgrammeK.TRIGGER_OPS.has(op):
		errors.append("%s: %s %s.op '%s' is not a recognised operator (%s)" % [
			filename, owner_id, what, str(op), str(ProgrammeK.TRIGGER_OPS)
		])
		return {}

	if not raw.has("value") or not (typeof(raw["value"]) == TYPE_INT or typeof(raw["value"]) == TYPE_FLOAT):
		errors.append("%s: %s %s.value is missing or not numeric" % [filename, owner_id, what])
		return {}

	return {"field": field, "op": op, "value": float(raw["value"])}


static func extract_programme_effects(loader, raw, owner_id: String, filename: String, what: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s %s must be an object of effect channels" % [filename, owner_id, what])
		return {}

	# extract_shared_effects() extracts the channels it knows and says nothing about
	# the ones it does not, so the unknown-channel refusal is ours -- law.gd's
	# _extract_effects() does this half for laws, and there is no second applier to
	# inherit it from here.
	for key in raw.keys():
		if not Law.SHARED_EFFECT_CHANNELS.has(key) and not Law.SCALAR_EFFECT_KEYS.has(key):
			errors.append("%s: %s %s.%s is not a recognised effect channel -- a conclusion prices only on the channels laws and events already share" % [
				filename, owner_id, what, str(key)
			])

	return Law.extract_shared_effects(
		raw, owner_id, filename, errors, C.TAX_KEYS, C.SPENDING_KEYS, OpinionK.BLOC_KEYS, C.SECTOR_TREND.keys()
	)
