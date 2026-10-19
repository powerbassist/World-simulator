extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. data/campaign-actions/ and data/pledges/: the campaign verbs and the promises.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too), every register lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim (now <ThisLoader>.<name>), its members read
## through `loader.`.

const CampaignAction = preload("res://src/core/campaign_action.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const PledgeAction = preload("res://src/core/pledge_action.gd")


static func load_campaign_actions(loader, actions_dir: String) -> void:
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
	var defined := {}     # effort_id -> the filename that defined it
	var referenced := {}  # effort_id -> the action id that stops it
	for fname in filenames:
		var path := actions_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("actions")) != TYPE_ARRAY:
			loader.errors.append("%s: invalid campaign-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = CampaignAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			loader.errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					loader.errors.append("%s: duplicate campaign action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true

			var eid := CampaignAction.effort_id(action)
			if eid != "":
				match CampaignAction.op_of(action):
					"start":
						if defined.has(eid):
							loader.errors.append("%s: effort '%s' is defined twice (also in %s) -- its price and its reach would depend on which entry loaded last" % [
								fname, eid, str(defined[eid])
							])
						defined[eid] = fname
					"stop":
						referenced[eid] = action.id
			loader.campaign_actions.append(action)

	for eid in referenced.keys():
		if not defined.has(eid):
			loader.errors.append("%s: '%s' stops effort '%s', which no action starts" % [
				actions_dir, str(referenced[eid]), str(eid)
			])


## V1.7b's promises, from data/pledges/. CampaignLoader.load_campaign_actions()'s shape.
##
## THE CROSS-FILE CHECK IS THE HALF WORTH HAVING, and here it is a different check
## from that one. A campaign effort needs a stop for every start; a pledge has no
## second op at all -- see src/sim/pledges_constants.gd's PLEDGE_TERMS -- so what only
## this function can see is that no two entries define the same `pledge_id`. The
## register is keyed on it and Pledges.has_pledged() refuses a duplicate, so two
## entries sharing one id would be two promises the player could only ever make one
## of, chosen by whichever file loaded last.
static func load_pledges(loader, pledges_dir: String) -> void:
	var da := DirAccess.open(pledges_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % pledges_dir)
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
	var defined := {}  # pledge_id -> the filename that defined it
	for fname in filenames:
		var path := pledges_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("pledges")) != TYPE_ARRAY:
			loader.errors.append("%s: invalid pledge file, expected {\"pledges\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["pledges"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: pledges[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = PledgeAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			loader.errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					loader.errors.append("%s: duplicate pledge action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true

			var pid := PledgeAction.pledge_id(action)
			if pid != "":
				if defined.has(pid):
					loader.errors.append("%s: pledge '%s' is defined twice (also in %s) -- the register is keyed on it, so the player could only ever make one of them" % [
						fname, pid, str(defined[pid])
					])
				defined[pid] = fname
			loader.pledges.append(action)
