extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. Diplomatic actions, the orgs
## and their council proposals, and (V5.1-0d) the pairs that hold no embassy.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too); every register
## lives on the loader, whose public surface did not move. Each function here
## is the body that used to be DataLoader._<name>() verbatim, now
## DiplomacyLoader.<name>(loader, ...), its members read through `loader.`.

const BlocProposal = preload("res://src/core/bloc_proposal.gd")
const DiplomaticAction = preload("res://src/core/diplomatic_action.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Org = preload("res://src/core/org.gd")
const OrgK = preload("res://src/core/org_constants.gd")
const RK = preload("res://src/core/relations.gd")


## Directory-scanned, exactly like PoliticsLoader.load_laws() and PoliticsLoader.load_scenarios() -- adding
## an action is a file, not a file plus an index entry. Every file holds
## {"actions": [...]}, matching a law file's {"laws": [...]}, so several actions
## can share a themed file. There is no cross-file half: an action names no
## nation, no party and no bloc roster beyond the global BLOC_KEYS its own
## from_dict already checks. See docs/diplomacy-model.md.
static func load_diplomatic_actions(loader, actions_dir: String) -> void:
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
			loader.errors.append("%s: invalid diplomatic-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = DiplomaticAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			loader.errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					loader.errors.append("%s: duplicate diplomatic action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true
			loader.diplomatic_actions.append(action)


## Directory-scanned, exactly like PoliticsLoader.load_laws(), PoliticsLoader.load_scenarios() and
## DiplomacyLoader.load_diplomatic_actions() -- adding a proposal is a file, not a file plus an
## index entry. Every file holds {"proposals": [...]}, matching a law file's
## {"laws": [...]}, so several proposals can share a themed file.
##
## Unlike those three, the ORDER matters: src/sim/bloc.gd rotates an index over
## this list to decide what reaches the council next, so the filename sort below
## and the authored order inside each file together are the agenda. That is the
## price of a scheduler with no RNG in it, and it is the right price.
static func load_orgs(loader, orgs_dir: String) -> void:
	var da := DirAccess.open(orgs_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % orgs_dir)
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

	for fname in filenames:
		var path := orgs_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			loader.errors.append("%s: invalid JSON" % fname)
			continue

		var per_file_errors: Array[String] = []
		var org: Org = Org.from_dict(parsed, fname, per_file_errors)
		loader.errors.append_array(per_file_errors)
		if org.id == "":
			continue
		if loader.orgs_by_id.has(org.id):
			loader.errors.append("%s: duplicate org id '%s'" % [fname, org.id])
			continue
		loader.orgs.append(org)
		loader.orgs_by_id[org.id] = org

	# Sorted by id, not by filename: the register's iteration order is a model
	# fact (every consumer iterates it sorted), not a side effect of file names.
	loader.orgs.sort_custom(func(a, b): return a.id < b.id)

	# Every member must be on the roster: an org binding a nation that does not
	# exist is content that reads as a membership and is not one -- the same
	# class of quiet failure a scenario naming an unplayable nation is refused
	# for. Runs after nations load, which the call order in load_all() promises.
	for org in loader.orgs:
		if loader.orgs.size() > OrgK.MAX_ORGS:
			loader.errors.append("orgs: %d orgs exceed the limit of %d" % [loader.orgs.size(), OrgK.MAX_ORGS])
			break
		for member_id in org.members.keys():
			if not loader.nations.has(member_id):
				loader.errors.append("orgs: %s lists member '%s', which is not a loaded nation" % [org.id, member_id])

	# A council org must carry what a new member enters with: the flip writes
	# it as live seat state, and a joiner with no weight is a member whose vote
	# never counts -- the second-class-member failure, refused at load.
	for org in loader.orgs:
		if org.council and org.accession_seats < 1:
			loader.errors.append("orgs: %s holds a council but carries no accession_seats" % org.id)

	# At most one parliament, because Elections seeds the EP clock from "the org
	# that carries one" and two of them would make that phrase ambiguous.
	var parliament_count := 0
	for org in loader.orgs:
		if not org.parliament.is_empty():
			parliament_count += 1
	if parliament_count > 1:
		loader.errors.append("orgs: %d orgs carry a parliament; at most one may" % parliament_count)


static func load_bloc_proposals(loader, proposals_dir: String) -> void:
	var da := DirAccess.open(proposals_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % proposals_dir)
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
		var path := proposals_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("proposals")) != TYPE_ARRAY:
			loader.errors.append("%s: invalid bloc-proposal file, expected {\"proposals\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["proposals"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: proposals[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var proposal = BlocProposal.from_dict(entry, fname, per_file_errors, loader.orgs_by_id.keys())
			loader.errors.append_array(per_file_errors)
			if proposal.id != "":
				if seen_ids.has(proposal.id):
					loader.errors.append("%s: duplicate bloc proposal id '%s'" % [fname, proposal.id])
				seen_ids[proposal.id] = true
			loader.bloc_proposals.append(proposal)
			# The per-org agenda, in exactly the order the flat list collects --
			# file order IS the agenda, and the register must not be the one
			# place that reorders it.
			if not loader.org_proposals.has(proposal.org_id):
				loader.org_proposals[proposal.org_id] = []
			loader.org_proposals[proposal.org_id].append(proposal)


## The cross-file half: a proposal names no nation, but two of its shapes only
## mean something against the roster it will run in.
##
## Runs after DiplomacyLoader.load_orgs(), because both checks need that org's membership.
static func validate_bloc_proposals(loader) -> void:
	for p in loader.bloc_proposals:
		# The proposal's own org must exist and be populated -- a proposal on an
		# org nobody belongs to can never reach a council, and one on an org that
		# does not exist is a typo the register refuses loudly.
		var org: Org = loader.orgs_by_id.get(p.org_id, null)
		if org == null:
			loader.errors.append("bloc-proposals: %s names org '%s', which is not loaded" % [p.id, p.org_id])
			continue
		var member_count := 0
		var outsider_count := 0
		for id in loader.nations.keys():
			if org.is_member(id):
				member_count += 1
			else:
				outsider_count += 1
		if member_count == 0:
			loader.errors.append("bloc-proposals: %s is loaded, but no loaded nation is a member of org '%s'" % [p.id, org.id])
		# V4.5a. A sponsor outside the club cannot table, lobby or mind -- and a
		# sponsor id that is no loaded nation is a typo that would read as "no
		# sponsor" forever. Checked against the AUTHORED start: a sponsor who later
		# withdraws loses the proposal at run time (Council reads live membership),
		# which is a fight's outcome rather than a content error.
		if p.sponsor != "":
			if not loader.nations.has(p.sponsor):
				loader.errors.append("bloc-proposals: %s sponsor '%s' is not a loaded nation" % [p.id, p.sponsor])
			elif not org.is_member(p.sponsor):
				loader.errors.append("bloc-proposals: %s sponsor '%s' is not a member of '%s'" % [p.id, p.sponsor, org.id])
		# A collective external tariff with nobody outside the bloc to levy it on
		# is content that can never do anything -- the same class of quiet failure
		# a scenario naming an unplayable nation is refused for.
		if not p.external_measure.is_empty() and outsider_count == 0:
			loader.errors.append("bloc-proposals: %s sets an external measure, but every loaded nation is a member of '%s'" % [p.id, org.id])


## V5.1-0d: data/world/embassies.json, the roster pairs WITHOUT diplomatic
## relations -- the exceptions to the rule that every roster state holds an
## embassy in every other (the file's own _note says why a rule and not a list).
## Read after the nations, because a pair is validated against the roster.
static func load_embassies(loader, path: String) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		loader.errors.append("%s: missing or invalid JSON" % path)
		return
	var errors: Array[String] = []
	loader.embassy_exceptions = parse_embassy_exceptions(loader, parsed, path.get_file(), errors)
	loader.errors.append_array(errors)


## Symmetric pair key -> true. Public so tests/test_embassies.gd can feed it a bad
## file without one on disk. A wrong pair is a load error, never a skipped line:
## a silently dropped exception would seed an embassy where none can stand.
static func parse_embassy_exceptions(loader, parsed: Dictionary, fname: String, errors: Array[String]) -> Dictionary:
	var out := {}
	var rows = parsed.get("without_relations")
	if typeof(rows) != TYPE_ARRAY:
		errors.append("%s: missing or invalid array field 'without_relations'" % fname)
		return out
	for i in rows.size():
		var pair = rows[i].get("pair") if typeof(rows[i]) == TYPE_DICTIONARY else null
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2 or pair[0] == pair[1]:
			errors.append("%s: without_relations[%d].pair must name two different nations" % [fname, i])
			continue
		if not loader.nations.has(pair[0]) or not loader.nations.has(pair[1]):
			errors.append("%s: without_relations[%d] names a nation not on the roster: %s" % [fname, i, str(pair)])
			continue
		var key := RK.key(String(pair[0]), String(pair[1]))
		if out.has(key):
			errors.append("%s: without_relations lists %s twice" % [fname, key])
		out[key] = true
	return out
