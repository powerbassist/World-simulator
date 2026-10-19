extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. data/energy-sources.json and data/energy-actions/: the plant catalogue and its verbs.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too), every register lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim (now <ThisLoader>.<name>), its members read
## through `loader.`.

const EnergyAction = preload("res://src/core/energy_action.gd")
const EnergyK = preload("res://src/sim/energy_constants.gd")
const EnergySource = preload("res://src/core/energy_source.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")


## V1.7a. VerbActionsLoader.load_projects()'s shape, and deliberately a separate directory rather than
## a third op on the project channel: a project is a discrete dated commitment pointed
## at a named thing and a campaign effort is a standing rate pointed at a slice of the
## electorate, which is the distinction docs/tiers/v1.md section 7 exists for.
##
## THE CROSS-FILE CHECK IS THE HALF WORTH HAVING. Per-entry validation lives in
## src/core/campaign_action.gd; what only this function can see is whether the file is
## CONSISTENT -- that no two entries define the same effort, and that every stop names
## an effort some start actually defines. A stop pointing at nothing loads as a button
## that is never available, which is a content bug that renders as an absence and would
## be found by a player rather than by a check. VerbActionsLoader.load_projects()'s own split, inherited.
## data/energy-sources.json, ONE file and global. Per-entry validation lives in
## src/core/energy_source.gd; what only this function can see is that the file
## parsed at all and that no two entries share an id -- the register is keyed by id,
## so a duplicate would be one technology silently overwriting another.
static func load_energy_sources(loader, path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		loader.errors.append("data/energy-sources.json: could not read file")
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("sources")) != TYPE_ARRAY:
		loader.errors.append("data/energy-sources.json: expected {\"sources\": [...]}")
		return

	var raw_list: Array = (parsed as Dictionary)["sources"]
	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			loader.errors.append("data/energy-sources.json: sources[%d] is not an object" % i)
			continue
		var per_file_errors: Array[String] = []
		var source = EnergySource.from_dict(entry, "data/energy-sources.json", per_file_errors)
		loader.errors.append_array(per_file_errors)
		if source.id != "":
			if loader.energy_sources.has(source.id):
				loader.errors.append("data/energy-sources.json: duplicate source id '%s'" % source.id)
			loader.energy_sources[source.id] = source


## Every branch the import measured must be BUILDABLE, and every branch a source
## names must have been measured. The first half is what stops a mix key with no
## verb behind it -- a player who can never build renewables in a country that is
## 80 % renewable has a readout and not a lever. The second half is the partition.
static func validate_energy_sources(loader) -> void:
	if loader.energy_sources.is_empty():
		loader.errors.append("data/energy-sources.json defines no sources")
		return
	var covered: Dictionary = {}
	for source in loader.energy_sources.values():
		covered[source.branch] = true
		# from_dict() parses a missing emission_t_per_twh to a -1.0 sentinel, so this
		# one check refuses both an absent key and an authored negative. Absence must
		# fail loudly: 0.0 tonnes per TWh on a gas station is a confident lie the
		# emissions read would print for years.
		if source.emission_t_per_twh < 0.0:
			loader.errors.append("energy source '%s' is missing emission_t_per_twh -- the key must exist for every source and be non-negative" % source.id)
	for branch in EnergyK.BRANCHES:
		if not covered.has(branch):
			loader.errors.append("no energy source builds branch '%s' -- every measured branch needs a verb" % branch)
	for nation_id in loader.nations.keys():
		var n = loader.nations[nation_id]
		for branch in n.energy_mix.keys():
			if not EnergyK.BRANCHES.has(String(branch)):
				loader.errors.append("%s: imported.energy.mix names branch '%s', which is not in BRANCHES" % [nation_id, branch])


## data/energy-actions/*.json, VerbActionsLoader.load_projects()'s shape. Per-entry validation lives
## in src/core/energy_action.gd; what only this function can see is duplicate ids --
## two actions with one id would be two buttons the registry cannot tell apart.
static func load_energy_actions(loader, actions_dir: String) -> void:
	var da := DirAccess.open(actions_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % actions_dir)
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
		var path := actions_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("actions")) != TYPE_ARRAY:
			loader.errors.append("%s: invalid energy-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = EnergyAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			loader.errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					loader.errors.append("%s: duplicate energy action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true
				loader.energy_actions.append(action)
