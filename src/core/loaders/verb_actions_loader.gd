extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. The three economic verb directories: company actions, investment actions and projects.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too), every register lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim (now <ThisLoader>.<name>), its members read
## through `loader.`.

const CompanyAction = preload("res://src/core/company_action.gd")
const InvestmentAction = preload("res://src/core/investment_action.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const ProjectAction = preload("res://src/core/project_action.gd")


## Directory-scanned, exactly like DiplomacyLoader.load_diplomatic_actions() -- adding a verb is
## a file, not a file plus an index entry. Every file holds {"actions": [...]}.
static func load_company_actions(loader, actions_dir: String) -> void:
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
			loader.errors.append("%s: invalid company-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = CompanyAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			loader.errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					loader.errors.append("%s: duplicate company action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true
			loader.company_actions.append(action)


## V1.6e. VerbActionsLoader.load_company_actions()'s shape, and deliberately a separate directory
## rather than a fourth op on the company channel: a subsidy is pointed at a firm
## inside a sector and this is pointed at the sector, which is exactly the
## distinction docs/companies-model.md section 12 says no validator can enforce
## from inside one content type.
static func load_investment_actions(loader, actions_dir: String) -> void:
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
			loader.errors.append("%s: invalid investment-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = InvestmentAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			loader.errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					loader.errors.append("%s: duplicate investment action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true
			loader.investment_actions.append(action)


## V1.6f. VerbActionsLoader.load_investment_actions()'s shape, and deliberately a separate directory
## rather than a third op on the investment channel: a programme is a standing rate
## pointed at a sector and a project is a discrete dated commitment pointed at a named
## thing, which is the distinction docs/sector-model.md section 1 used to split this
## session off in the first place.
##
## THE CROSS-FILE CHECK IS THE HALF WORTH HAVING. Per-entry validation lives in
## src/core/project_action.gd; what only this function can see is whether the file is
## CONSISTENT -- that no two entries define the same project, and that every abandon
## names a project some start actually defines. An abandon pointing at nothing loads
## as a button that is never available, which is a content bug that renders as an
## absence and would be found by a player rather than by a check. V1.2e's per-file /
## cross-file split, and V1.3b's zero-sum sector check.
static func load_projects(loader, actions_dir: String) -> void:
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
	var defined := {}   # project_id -> the filename that defined it
	var referenced := {}  # project_id -> the action id that abandons it
	for fname in filenames:
		var path := actions_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("actions")) != TYPE_ARRAY:
			loader.errors.append("%s: invalid project-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = ProjectAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			loader.errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					loader.errors.append("%s: duplicate project action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true

			var pid := ProjectAction.project_id(action)
			if pid != "":
				match ProjectAction.op_of(action):
					"start":
						if defined.has(pid):
							loader.errors.append("%s: project '%s' is defined twice (also in %s) -- its duration, price and payoff would depend on which entry loaded last" % [
								fname, pid, str(defined[pid])
							])
						defined[pid] = fname
					"abandon":
						referenced[pid] = action.id
			loader.project_actions.append(action)

	for pid in referenced.keys():
		if not defined.has(pid):
			loader.errors.append("%s: '%s' abandons project '%s', which no action starts" % [
				actions_dir, str(referenced[pid]), str(pid)
			])
