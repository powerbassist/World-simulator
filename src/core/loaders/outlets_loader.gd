extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. data/outlets/: the press register per nation and its orphan-file check.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator and the only caller, every register still lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim, its members read through `loader.`.

const Outlet = preload("res://src/core/outlet.gd")


## One data/outlets/<NATION>.json per nation, {"outlets": [...]}, the same shape as
## data/companies/*.json. See docs/media-model.md.
##
## A PER-NATION LOOKUP RATHER THAN A DIRECTORY SCAN, and that is a deliberate choice
## between two shapes this file already has. Scanning is right for laws and diplomatic
## actions, where a file IS the unit of content; a lookup is right here, because it
## makes an outlets file for a nation that does not exist structurally impossible
## instead of an error somebody has to remember to write. What it cannot see is an
## ORPHAN file -- data/outlets/FRE.json is simply never opened -- so
## _validate_outlets() scans the directory for exactly that, which is
## tools/check_names.sh's zero-files-scanned burn caught in advance rather than after.
##
## AN ABSENT FILE IS NOT AN ERROR, for _load_companies()' reason and one stronger: a
## nation with no press has a framing deviation of exactly 0.0 for every bloc, so the
## seven nations nobody can play keep running the opinion model they have run since S10,
## bit for bit.
static func load_outlets(loader, nation_id: String, outlets_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := outlets_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		loader.outlets[nation_id] = []
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("outlets")) != TYPE_ARRAY:
		loader.errors.append("%s: invalid outlets file, expected {\"outlets\": [...]}" % fname)
		loader.outlets[nation_id] = []
		return

	var raw_list: Array = parsed["outlets"]
	var parsed_outlets: Array = []
	var per_file_errors: Array[String] = []
	var seen_ids := {}

	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			per_file_errors.append("%s: outlets[%d] is not an object" % [fname, i])
			continue
		var outlet = Outlet.from_dict(entry, i, fname, per_file_errors)
		if outlet.id == "":
			continue

		if not outlet.id.begins_with("%s_" % nation_id):
			per_file_errors.append(
				"%s: outlet id '%s' must begin with '%s_'" % [fname, outlet.id, nation_id]
			)
		if seen_ids.has(outlet.id):
			per_file_errors.append("%s: duplicate outlet id '%s'" % [fname, outlet.id])
		seen_ids[outlet.id] = true
		parsed_outlets.append(outlet)

	loader.errors.append_array(per_file_errors)
	loader.outlets[nation_id] = parsed_outlets


## The cross-file half. Two checks, and the interesting half is the check that is
## deliberately NOT here.
##
## A bloc's named reaches summing past 1.0 is a partition claiming more audience than
## the bloc contains -- _validate_companies()' share check, transferred whole.
##
## _validate_companies() ALSO refuses a sector holding exactly one named firm, and that
## refusal does NOT transfer. Its reason is that a lone firm has no rival to take share
## from, so a subsidy pointed at it moves nothing; a lone outlet has nothing of the kind
## wrong with it, because its hostility simply IS 100 % of its bloc's affiliated press
## and the deviation reads it fine. Copying the check across by symmetry would be the
## error docs/unrest-model.md's fourth-refusal paragraph names in the law schema --
## SYMMETRY IS NOT THE TEST -- so the non-check is written down rather than left as an
## absence a later reader repairs.
static func validate_outlets(loader, outlets_dir: String) -> void:
	for nation_id in loader.outlets.keys():
		var by_audience := {}
		for outlet in loader.outlets[nation_id]:
			if outlet.audience == "":
				continue
			if not by_audience.has(outlet.audience):
				by_audience[outlet.audience] = []
			by_audience[outlet.audience].append(outlet)

		for audience in by_audience.keys():
			var total := 0.0
			for outlet in by_audience[audience]:
				total += outlet.reach
			if total > 1.0 + 0.000001:
				loader.errors.append(
					"outlets/%s.json: audience '%s' reaches sum to %s, above 1.0 -- the named outlets would reach more of the bloc than the bloc contains"
					% [nation_id, audience, str(total)]
				)

	# The orphan scan the per-nation lookup above cannot do for itself.
	var da := DirAccess.open(outlets_dir)
	if da == null:
		return
	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if not da.current_is_dir() and file_name.ends_with(".json"):
			var id := file_name.get_basename()
			if not loader.nations.has(id):
				loader.errors.append(
					"outlets/%s: no nation '%s' exists -- this file is never read, so its outlets are content nothing can reach"
					% [file_name, id]
				)
		file_name = da.get_next()
	da.list_dir_end()
