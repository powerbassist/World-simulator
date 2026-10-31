extends SceneTree

## U6b + V4.3. The register: what it holds, what it refuses, and what it is
## NOT allowed to grow into. Model: docs/people-model.md (section 14 is the
## character layer).
##
## The load-bearing assertions here are the ones about what does NOT happen:
##
##   - NO PERSON IS UNREFERENCED. An orphan is content with no caller, which
##     is what this session's own probe cut a five-deep minister bench for. The
##     loader refuses one, so a name authored into a file and wired to nothing
##     fails the load rather than sitting there looking like a feature. V4.3
##     widened what references a person (slot OR non-politician kind OR party
##     edge) -- the judge nobody slots is LEGAL, the partyless backbencher
##     politician is not, and both halves are pinned.
##   - A PERSON IS A WANT CARRIER, NOT A MECHANISM CARRIER. Person has exactly
##     eleven fields, checked by reading the file: what someone IS and WANTS is
##     content, and every number that MOVES lives on NationState. The moment a
##     twelfth field appears, this turns red and a later session has to say why.
##   - EVERY KIND PLUGS IN. A kind in KIND_KEYS is a politician shape (wants +
##     standing) or carries a meter in KIND_METERS -- a kind with neither is
##     content that cannot act, refused here rather than loading inert.
##   - src/sim/ HANDLES NO NAMES. After the re-key the simulation layer moves
##     person IDs and nothing else, so no display string can leak into a model.
##   - THE REGISTER IS THE ONLY PLACE A NAME LIVES. data/nations/ and
##     data/parties/ wrote one person's name twice in all ten files before U6b;
##     asserted here so a later content edit cannot quietly put one back.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Person = preload("res://src/core/person.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")

## The register is the list (V4 handoff): a literal 29-id roster here went
## stale the moment V4.11 grew the roster -- five test files at once.
func _nations() -> Array:
	var ids: Array = _loader.nations.keys()
	ids.sort()
	return ids

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
	_check_person_field_contract()
	_check_kind_meter_coverage()
	_check_character_fields_in_band()
	_check_character_fixture_refusals()
	_check_v52a_fields_default()
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
	if _loader.people.size() != _nations().size():
		_fail("register holds %d nations, expected %d" % [_loader.people.size(), _nations().size()])
	for id in _nations():
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
	for nation_id in _nations():
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
## V4.3's rescoped rule: a person is referenced by a slot, OR by a
## non-politician kind (the kind is the meter hook), OR by an authored
## party_id (the backbencher edge). The loader enforces it; this check
## re-derives it independently so the two cannot silently diverge.
func _check_no_orphans() -> void:
	var referenced := {}
	for nation_id in _nations():
		var nation = _loader.nations[nation_id]
		referenced[nation.leader_person_id] = true
		referenced[nation.head_of_state_person_id] = true
		referenced[nation.head_of_government_person_id] = true
		referenced[nation.pretender_person_id] = true
		for party in _loader.parties[nation_id]:
			referenced[party.leader_person_id] = true
	for nation_id in _loader.people.keys():
		for person in _loader.people[nation_id]:
			if person.kind != "politician" or person.party_id != "":
				referenced[person.id] = true
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


## Person has ELEVEN fields -- id, person_name, kind, traits, ambition,
## party_id, wants, bench, social_skill, spouse_id, wealth_eur_m -- read off the file rather than asserted about an
## instance, because the failure this guards against is a later session ADDING
## one (an `age`, a `competence`, a `loyalty`) and an instance check would
## still pass with a ninth field sitting there unused. The character layer's
## law (people-model 14.1) is that WHAT MOVES lives on NationState; this check
## is what makes that enforceable rather than aspirational. `bench` is the
## portrait tiering flag -- an art-logistics marker, not character content,
## and the one field a person carries for the pipeline rather than the model.
## V5.2a's three, argued at their declarations in person.gd: a reading skill
## and a spouse are who someone IS and do not move, and the wealth is the
## authored START -- what the president gains or loses is a delta on
## NationState (people-model 14.9), so the law above still holds.
func _check_person_field_contract() -> void:
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
	var names: Array[String] = []
	for f in fields:
		names.append(f.replace("var ", "").get_slice(":", 0).strip_edges())
	var expected: Array[String] = []
	for n in ["id", "person_name", "kind", "traits", "ambition", "party_id", "wants", "bench",
			"social_skill", "spouse_id", "wealth_eur_m",
			# V5.2d: which recorded voice plays them. A presentation fact that
			# never moves and that no slot states; no mechanism reads it.
			"voice",
			# V5.3-0: a one-line biography, the same class of fact as the voice
			# (presentation only, never moves, read by the UI alone).
			"bio"]:
		expected.append(String(n))
	if names != expected:
		_fail("Person declares %s, expected exactly %s -- a new field is a number or a fact that MOVES or that a slot already states, and people-model 14 owns that argument" % [str(names), str(expected)])


## Every kind plugs in or is refused: a politician shape acts through wants +
## standing, every other kind must carry a meter in KIND_METERS, and the table
## must name no kind or meter outside the vocabularies. A kind that cannot act
## is content loading inert -- the class of failure this suite exists to make
## loud.
## V4.7a: `executive` joins the no-meter exemption as a DECLARED STOPGAP (the
## reason lives beside KIND_KEYS in character_constants.gd, and it is the same
## sentence): a chief's action is the firm's action under V4.7b's autonomy
## machine, and the chief's own lever is V4.2's lobbying. When V4.2 opens it,
## this exemption narrows back or the kind grows a lever -- a kind exempt here
## forever is exactly the inert content this check exists to refuse.
## V5.3-0: the staff kinds (CharacterK.KIND_STAFF) are exempt for the opposite
## reason, and not as a stopgap: a chief of staff must NOT act -- moving no
## number is their whole contract, which tests/test_staff_kind.gd pins.
func _check_kind_meter_coverage() -> void:
	for kind in CharacterK.KIND_KEYS:
		if kind in ["politician", "regional_figure", "executive"] or CharacterK.KIND_STAFF.has(kind):
			continue
		if not CharacterK.KIND_METERS.has(kind):
			_fail("kind '%s' has no meter and no political lever -- declare it in KIND_METERS or refuse the kind" % kind)
	for kind in CharacterK.KIND_METERS.keys():
		if not CharacterK.KIND_KEYS.has(kind):
			_fail("KIND_METERS names kind '%s', which is not in KIND_KEYS" % kind)
		if not CharacterK.METER_KEYS.has(String(CharacterK.KIND_METERS[kind])):
			_fail("KIND_METERS maps '%s' at meter '%s', which is not in METER_KEYS" % [kind, String(CharacterK.KIND_METERS[kind])])
	for family in CharacterK.WANT_STANCES.keys():
		if not ["programme", "office", "meter"].has(family):
			_fail("WANT_STANCES carries family '%s', which the object grammar does not define" % family)


## The loaded register itself: every person's character fields inside their
## bands. The defaults (kind "politician", ambition 0.5) are in band by
## construction, so this is a belt on the loader's own refusal -- it fires only
## if someone bypasses from_dict.
func _check_character_fields_in_band() -> void:
	for nation_id in _loader.people.keys():
		for person in _loader.people[nation_id]:
			if not CharacterK.KIND_KEYS.has(person.kind):
				_fail("person '%s' has kind '%s' outside KIND_KEYS" % [person.id, person.kind])
			if person.ambition < 0.0 or person.ambition > 1.0:
				_fail("person '%s' has ambition %.2f outside [0, 1]" % [person.id, person.ambition])
			if person.traits.size() > 3:
				_fail("person '%s' carries %d traits" % [person.id, person.traits.size()])
			for t in person.traits:
				if not CharacterK.TRAIT_KEYS.has(t):
					_fail("person '%s' carries trait '%s' outside the set" % [person.id, t])
			if person.social_skill < 0.0 or person.social_skill > 1.0:
				_fail("person '%s' has social_skill %.2f outside [0, 1]" % [person.id, person.social_skill])
			if person.wealth_eur_m < 0.0:
				_fail("person '%s' has wealth_eur_m %.2f below zero" % [person.id, person.wealth_eur_m])
			if person.spouse_id != "" and (person.spouse_id == person.id
					or not _loader.person_by_id.has(person.spouse_id)):
				_fail("person '%s' has spouse_id '%s', which names no one else" % [person.id, person.spouse_id])


## One fixture, every refusal class, both halves of the orphan rule. The clean
## pair (a judge no slot points at; a backbencher with a resolvable party edge
## and valid wants) must produce NO error naming them -- the positive half of
## the V4.3 rule, which a needle list alone cannot say.
func _check_character_fixture_refusals() -> void:
	var fixture := DataLoader.new()
	fixture.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://data/laws",
		"res://data/political-systems", "res://data/scenarios",
		"res://data/diplomatic-actions", "res://data/geo/world.geojson",
		"res://data/bloc-proposals", "res://tests/fixtures/people_character"
	)
	var needles := [
		"field 'kind' must be one of",
		"is not in the trait set",
		"twice",
		"at most 3",
		"outside [0, 1]",
		"must be a number in [0, 1]",
		"not legal for a programme want",
		"no known want family",
		"exactly one of below/above",
		"only a meter want reads one",
		"not a want field",
		"one want per object",
		"which is not one of the meters",
		"pairs with",
		"which is not in the register",
		"not one of the cabinet's",
		"not a party of this nation",
		"not premiership, a portfolio or a party leadership",
		"not one of this nation's parties",
		"field 'social_skill' must be a number in [0, 1]",
		"field 'wealth_eur_m' must be a number >= 0",
		"field 'spouse_id' must be a string",
		"resolves to no person",
		"names the person themself",
	]
	var missing: Array[String] = []
	for needle in needles:
		var found := false
		for e in fixture.errors:
			if e.find(needle) != -1:
				found = true
				break
		if not found:
			missing.append(needle)
	if not missing.is_empty():
		_fail("character fixture did not fire (or did not name): %s -- errors were: %s" % [str(missing), str(fixture.errors)])
	for pid in ["FRA_legrain", "FRA_okwant"]:
		for e in fixture.errors:
			if e.find(pid) != -1:
				_fail("clean bench person '%s' was named in a load error: %s" % [pid, e])


## V5.2a. A record that authors none of the three reads the defaults with no
## error -- 0.5 a middling reader, no spouse, no authored wealth -- which is
## the truth about all 2 147 people before Content authors them.
func _check_v52a_fields_default() -> void:
	var errors: Array[String] = []
	var p = Person.from_dict({"id": "FRA_plain", "name": "Plain Person"}, 0, "inline", errors)
	if not errors.is_empty():
		_fail("a record without the V5.2a fields did not load clean: %s" % [errors])
	if not is_equal_approx(p.social_skill, 0.5) or p.spouse_id != "" or p.wealth_eur_m != 0.0:
		_fail("absent V5.2a fields read %.2f / '%s' / %.2f, wanted 0.5 / '' / 0.0" % [
			p.social_skill, p.spouse_id, p.wealth_eur_m])


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
	for nation_id in _nations():
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
	for nation_id in _nations():
		var pid := String(_loader.nations[nation_id].pretender_person_id)
		if seen.has(pid):
			_fail("%s and %s share pretender '%s' -- a restoration must return that nation's OWN dynasty" % [nation_id, seen[pid], pid])
		seen[pid] = nation_id

	# And a monarchy points the slot at the monarch it already has, so a
	# republic-then-restoration puts the same house back rather than inventing a
	# second claimant for one country.
	for nation_id in _nations():
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
