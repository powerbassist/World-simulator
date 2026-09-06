extends SceneTree

## U6b. The register: what it holds, what it refuses, and what it is NOT allowed
## to grow into. Model: docs/people-model.md.
##
## The load-bearing assertions here are the ones about what does NOT happen:
##
##   - NO PERSON IS UNREFERENCED. An orphan is content with no caller, which is
##     what this session's own probe cut a five-deep minister bench for. The
##     loader refuses one, so a name authored into a file and wired to nothing
##     fails the load rather than sitting there looking like a feature.
##   - A PERSON CARRIES NO MECHANISM. Person has exactly two fields, checked by
##     reading the file: the moment one has a number in it, this turns red and a
##     later session has to come and say why. That is docs/tiers/v1.md §4/§5's
##     boundary, and it is the argument the whole U6 split was taken on.
##   - src/sim/ HANDLES NO NAMES. After the re-key the simulation layer moves
##     person IDs and nothing else, so no display string can leak into a model.
##   - THE REGISTER IS THE ONLY PLACE A NAME LIVES. data/nations/ and
##     data/parties/ wrote one person's name twice in all ten files before U6b;
##     asserted here so a later content edit cannot quietly put one back.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Person = preload("res://src/core/person.gd")
const Legislature = preload("res://src/sim/legislature.gd")

const NATIONS := ["AUT", "BEL", "CHE", "DEU", "ESP", "FRA", "GBR", "ITA", "LUX", "NLD"]

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_register_loads()
	_check_ids_are_namespaced()
	_check_every_reference_resolves()
	_check_no_orphans()
	_check_duplicate_id_refused()
	_check_foreign_reference_refused()
	_check_orphan_refused()
	_check_person_carries_no_mechanism()
	_check_sim_moves_ids_not_names()
	_check_no_name_is_authored_twice()
	_check_restored_monarch_is_per_nation()

	if _failures.is_empty():
		print("test_people: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _check_register_loads() -> void:
	if _loader.people.size() != NATIONS.size():
		_fail("register holds %d nations, expected %d" % [_loader.people.size(), NATIONS.size()])
	for id in NATIONS:
		var roster: Array = _loader.people.get(id, [])
		if roster.is_empty():
			_fail("%s has no people at all" % id)
	if _loader.person_by_id.is_empty():
		_fail("the flat person_by_id index is empty")

	# The flat index and the per-nation lists are two views of one set, so a
	# person missing from either is a divergence rather than an omission.
	var flat := 0
	for id in _loader.people.keys():
		flat += (_loader.people[id] as Array).size()
	if flat != _loader.person_by_id.size():
		_fail("per-nation rosters hold %d people, the flat index holds %d" % [flat, _loader.person_by_id.size()])


## The asymmetry with party ids, asserted rather than argued: a person id is read
## BARE off NationState and off an appointment, so it has to say which nation it
## belongs to. A party id never is, which is why parties are not namespaced.
func _check_ids_are_namespaced() -> void:
	for nation_id in _loader.people.keys():
		for person in _loader.people[nation_id]:
			if not person.id.begins_with("%s_" % nation_id):
				_fail("person '%s' is in %s's file but not prefixed with it" % [person.id, nation_id])
			if person.person_name == "":
				_fail("person '%s' has no name" % person.id)


func _check_every_reference_resolves() -> void:
	for nation_id in NATIONS:
		var nation = _loader.nations[nation_id]
		for slot in [
			nation.leader_person_id, nation.head_of_state_person_id,
			nation.head_of_government_person_id, nation.pretender_person_id,
		]:
			if String(slot) == "" or not _loader.person_by_id.has(slot):
				_fail("%s has a nation-level person slot that does not resolve: '%s'" % [nation_id, slot])
		for party in _loader.parties[nation_id]:
			if not _loader.person_by_id.has(party.leader_person_id):
				_fail("%s party '%s' names person '%s', which is not in the register" % [nation_id, party.id, party.leader_person_id])


## The unusual half of the load, and the one this session earned the hard way.
func _check_no_orphans() -> void:
	var referenced := {}
	for nation_id in NATIONS:
		var nation = _loader.nations[nation_id]
		referenced[nation.leader_person_id] = true
		referenced[nation.head_of_state_person_id] = true
		referenced[nation.head_of_government_person_id] = true
		referenced[nation.pretender_person_id] = true
		for party in _loader.parties[nation_id]:
			referenced[party.leader_person_id] = true
	for pid in _loader.person_by_id.keys():
		if not referenced.has(pid):
			_fail("person '%s' is referenced by nothing -- an orphan should not have loaded" % pid)


func _check_duplicate_id_refused() -> void:
	_expect_fixture_error(
		"res://tests/fixtures/people_duplicate_id", "already used in another nation",
		"a person id reused across two nation files"
	)


func _check_foreign_reference_refused() -> void:
	_expect_fixture_error(
		"res://tests/fixtures/people_bad_prefix", "must begin with",
		"a person id whose prefix does not match its own file"
	)


func _check_orphan_refused() -> void:
	_expect_fixture_error(
		"res://tests/fixtures/people_orphan", "referenced by nothing",
		"a person nothing points at"
	)


func _expect_fixture_error(people_dir: String, needle: String, what: String) -> void:
	var fixture := DataLoader.new()
	fixture.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://data/laws",
		"res://data/political-systems", "res://data/scenarios",
		"res://data/diplomatic-actions", "res://data/geo/world.geojson",
		"res://data/bloc-proposals", people_dir
	)
	for e in fixture.errors:
		if e.find(needle) != -1:
			return
	_fail("%s did not fail to load, or did not name the problem: %s" % [what, fixture.errors])


## Person has TWO fields. Read off the file rather than asserted about an
## instance, because the failure this guards against is a later session ADDING
## one -- an `age`, a `competence`, a `loyalty` -- and an instance check would
## still pass with a third field sitting there unused.
func _check_person_carries_no_mechanism() -> void:
	var src := FileAccess.get_file_as_string("res://src/core/person.gd")
	if src.is_empty():
		_fail("could not read src/core/person.gd")
		return
	# Column zero only: an indented `var` is a local inside from_dict(), and
	# counting those made the first version of this check report four fields.
	var fields: Array[String] = []
	for raw_line in src.split("\n"):
		var line := String(raw_line)
		if line.begins_with("var "):
			fields.append(line.strip_edges())
	if fields.size() != 2:
		_fail("Person declares %d fields, expected exactly 2 (id, person_name): %s -- a person carrying a NUMBER is a mechanism, and docs/tiers/v1.md §4/§5 own that work" % [fields.size(), fields])


## The prize of the re-key, and the property that keeps a display string out of a
## model. src/sim/ moves person IDs; it resolves none of them.
func _check_sim_moves_ids_not_names() -> void:
	for file_name in ["government.gd", "legislature.gd", "calendar.gd", "cabinet.gd", "elections.gd"]:
		var src := FileAccess.get_file_as_string("res://src/sim/%s" % file_name)
		if src.is_empty():
			_fail("could not read src/sim/%s" % file_name)
			continue
		var code := _code_only(src)
		if code.find("person_name") != -1:
			_fail("src/sim/%s reads person_name -- the sim layer moves ids, and a name in a model is what the re-key removed" % file_name)
		if code.find("person_by_id") != -1:
			_fail("src/sim/%s reaches into the person register -- resolution belongs to the UI" % file_name)


## Comments stripped, because these files DISCUSS the register at length and the
## first version of this check failed on government.gd's own explanation of why
## it no longer touches it.
func _code_only(src: String) -> String:
	var out := ""
	for raw_line in src.split("\n"):
		var line := String(raw_line)
		var hash_at := line.find("#")
		if hash_at != -1:
			line = line.substr(0, hash_at)
		out += line + "\n"
	return out


## data/nations/*.json wrote its leader's name twice in ALL TEN files before U6b
## (as leader.name and again as either head_of_state.name or
## head_of_government_name), and data/parties/*.json wrote it a third time. The
## register makes those references rather than copies, so this asserts no data
## file carries a person's display name at all any more.
func _check_no_name_is_authored_twice() -> void:
	var names := {}
	for pid in _loader.person_by_id.keys():
		names[_loader.person_by_id[pid].person_name] = pid
	for nation_id in NATIONS:
		for path in ["res://data/nations/%s.json" % nation_id, "res://data/parties/%s.json" % nation_id]:
			var text := FileAccess.get_file_as_string(path)
			for person_name in names.keys():
				if text.find(String(person_name)) != -1:
					_fail("%s still spells out '%s' -- it should carry the id '%s' instead" % [path, person_name, names[person_name]])


## The content bug the register fixed, asserted so it cannot come back. The
## Restoration Act applies to any parliamentary_republic and used to carry one
## authored king, so every republic in Europe restored the same man.
func _check_restored_monarch_is_per_nation() -> void:
	var seen := {}
	for nation_id in NATIONS:
		var pid := String(_loader.nations[nation_id].pretender_person_id)
		if seen.has(pid):
			_fail("%s and %s share pretender '%s' -- a restoration must return that nation's OWN dynasty" % [nation_id, seen[pid], pid])
		seen[pid] = nation_id

	# And a monarchy points the slot at the monarch it already has, so a
	# republic-then-restoration puts the same house back rather than inventing a
	# second claimant for one country.
	for nation_id in NATIONS:
		var nation = _loader.nations[nation_id]
		if nation.head_of_state_kind == "hereditary_monarch":
			if nation.pretender_person_id != nation.head_of_state_person_id:
				_fail("%s is a monarchy but its pretender is not its sitting monarch" % nation_id)

	# The law itself must no longer name anybody.
	for law in _loader.laws:
		var inst = law.effects.get("institutional", {})
		if typeof(inst) != TYPE_DICTIONARY or not inst.has("head_of_state"):
			continue
		if (inst["head_of_state"] as Dictionary).has("name"):
			_fail("law '%s' authors a head-of-state NAME -- a transition names an office, the nation names the person" % law.id)


func _fail(message: String) -> void:
	_failures.append(message)
