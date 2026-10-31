extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. data/people/: the person
## register per nation and its cross-register checks (party, office and want
## references).
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too); every register
## lives on the loader, whose public surface did not move. Each function here
## is the body that used to be DataLoader._<name>() verbatim, now
## PeopleLoader.<name>(loader, ...), its members read through `loader.`.

const CharacterK = preload("res://src/sim/character_constants.gd")
const Person = preload("res://src/core/person.gd")


## One data/people/<NATION>.json per nation, {"people": [...]}, the same shape
## and the same failure modes as data/parties/*.json. See docs/people-model.md.
static func load_people(loader, nation_id: String, people_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := people_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		loader.errors.append("%s: could not read file" % path)
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("people")) != TYPE_ARRAY:
		loader.errors.append("%s: invalid people file, expected {\"people\": [...]}" % fname)
		return

	var raw_list: Array = parsed["people"]
	var parsed_people: Array[Person] = []
	var per_file_errors: Array[String] = []
	var seen_ids := {}

	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			per_file_errors.append("%s: people[%d] is not an object" % [fname, i])
			continue
		var person = Person.from_dict(entry, i, fname, per_file_errors)
		if person.id == "":
			continue

		# The prefix rule is the load-bearing one: global uniqueness follows from
		# per-file uniqueness plus a prefix that cannot repeat across files, since
		# a nation gets exactly one file named after it. The flat duplicate check
		# below is therefore redundant BY DESIGN — it can only fire if this rule is
		# ever relaxed, which is exactly when a duplicate stops being impossible.
		if not person.id.begins_with("%s_" % nation_id):
			per_file_errors.append(
				"%s: person id '%s' must begin with '%s_'" % [fname, person.id, nation_id]
			)
		if seen_ids.has(person.id):
			per_file_errors.append("%s: duplicate person id '%s'" % [fname, person.id])
		seen_ids[person.id] = true

		if loader.person_by_id.has(person.id):
			per_file_errors.append(
				"%s: person id '%s' is already used in another nation's file" % [fname, person.id]
			)
		else:
			loader.person_by_id[person.id] = person
		parsed_people.append(person)

	loader.errors.append_array(per_file_errors)
	loader.people[nation_id] = parsed_people


## Every person is referenced, and every reference resolves inside its own
## nation. The first half is the unusual one and it is deliberate: an
## unreferenced person is content with no caller, which is what U6b's own probe
## cut a five-deep minister bench for. Authoring a name nobody can reach should
## fail the load rather than sit in a file looking like a feature.
##
## V4.3 widened what a reference IS: a person is referenced by a slot, OR by a
## non-politician kind (the kind is the meter hook -- a union leader has no
## slot anywhere, and what points at them is the grievance ladder their kind
## reads), OR by an authored party_id. A politician with no slot, no kind and
## no party is still an orphan. This is also where want OBJECTS resolve against
## the other registers: people load before parties and programme (load_all's
## own ordering note), so person.gd can only check closed vocabularies and
## every cross-register half waits for here, the first place the whole loader
## is in hand.
static func validate_people(loader) -> void:
	var referenced := {}

	for nation_id in loader.nations.keys():
		var nation = loader.nations[nation_id]
		var slots := {
			"leader.person": nation.leader_person_id,
			"government.head_of_state.person": nation.head_of_state_person_id,
			"government.formation.head_of_government_person": nation.head_of_government_person_id,
			"government.pretender_person": nation.pretender_person_id,
		}
		for slot in slots.keys():
			var pid: String = String(slots[slot])
			if pid == "":
				continue
			check_person_ref(loader, nation_id, "%s.json" % nation_id, slot, pid, referenced)

		for party in loader.parties.get(nation_id, []):
			if party.leader_person_id == "":
				continue
			check_person_ref(loader, 
				nation_id, "parties/%s.json" % nation_id,
				"party '%s' leader_person" % party.id, party.leader_person_id, referenced
			)

	# The programme register's ids, for want resolution. Built once here rather
	# than per person: 37 entries against ~1600 people, and a linear scan per
	# want would be 1600 scans of the thing a Dictionary answers once.
	var programme_ids := {}
	for entry in loader.programme:
		programme_ids[String(entry["id"])] = true

	for nation_id in loader.people.keys():
		var party_ids := {}
		for party in loader.parties.get(nation_id, []):
			party_ids[party.id] = true

		for person in loader.people[nation_id]:
			# A bench politician's affiliation is authored on them because no
			# slot points at it; it must resolve in THIS nation's list, the
			# same inside-one-nation's-context rule party ids always follow.
			if person.party_id != "" and not party_ids.has(person.party_id):
				loader.errors.append(
					"people/%s.json: person '%s' claims party '%s', which is not one of this nation's parties"
					% [nation_id, person.id, person.party_id]
				)
			# V5.3-0. Staff move no number (CharacterK.KIND_STAFF): a want is what
			# asks and settles a grudge, a party is what defects and challenges, so
			# either on a staff person is a road into the arithmetic, refused here.
			if CharacterK.KIND_STAFF.has(person.kind):
				if not person.wants.is_empty():
					loader.errors.append("people/%s.json: person '%s' is staff (kind '%s') and carries wants; staff carry none"
						% [nation_id, person.id, person.kind])
				if person.party_id != "":
					loader.errors.append("people/%s.json: person '%s' is staff (kind '%s') and claims party '%s'; staff carry none"
						% [nation_id, person.id, person.kind, person.party_id])
			for want in person.wants:
				resolve_want(loader, want, nation_id, person.id, party_ids, programme_ids)
			# V5.2a. Any nation's register: a marriage need not stop at a border.
			if person.spouse_id == person.id:
				loader.errors.append("people/%s.json: person '%s' spouse_id names the person themself"
					% [nation_id, person.id])
			elif person.spouse_id != "" and not loader.person_by_id.has(person.spouse_id):
				loader.errors.append("people/%s.json: person '%s' spouse_id '%s' resolves to no person"
					% [nation_id, person.id, person.spouse_id])

			if referenced.has(person.id):
				continue
			if person.kind != "politician" or person.party_id != "":
				continue
			loader.errors.append(
				"people/%s.json: person '%s' (%s) is referenced by nothing"
				% [nation_id, person.id, person.person_name]
			)


## The cross-register half of want validation. Shape, stance and threshold
## coherence were checked at parse (person.gd, against character_constants);
## what remains is that the object NAMES something real: a programme entry
## that exists, a portfolio the cabinet knows, a party of this person's own
## nation. An unresolvable want is a load error naming the person, not an
## inert want quietly never satisfied.
static func resolve_want(loader, want: Dictionary, nation_id: String, person_id: String, party_ids: Dictionary, programme_ids: Dictionary) -> void:
	var object := String(want["object"])
	var rest := object.substr(object.find(":") + 1)

	if object.begins_with("programme:"):
		if not programme_ids.has(rest):
			loader.errors.append(
				"people/%s.json: person '%s' wants programme entry '%s', which is not in the register"
				% [nation_id, person_id, rest]
			)
		return

	if object.begins_with("office:"):
		if object == "office:premiership":
			# Every nation has exactly one; nothing to resolve against. The
			# whole-string compare IS the guard: "office:premiership:junk" is
			# a typo wearing a valid prefix, and a resolver that read only the
			# first segment would load it as the premiership itself.
			return
		if rest.begins_with("portfolio:"):
			var key := rest.substr("portfolio:".length())
			if not CharacterK.PORTFOLIO_KEYS.has(key):
				loader.errors.append(
					"people/%s.json: person '%s' wants portfolio '%s', which is not one of the cabinet's (%s)"
					% [nation_id, person_id, key, str(CharacterK.PORTFOLIO_KEYS)]
				)
			return
		if rest.begins_with("party_leadership:"):
			var pid := rest.substr("party_leadership:".length())
			if not party_ids.has(pid):
				loader.errors.append(
					"people/%s.json: person '%s' wants the leadership of '%s', which is not a party of this nation"
					% [nation_id, person_id, pid]
				)
			return
		loader.errors.append(
			"people/%s.json: person '%s' wants office '%s', which is not premiership, a portfolio or a party leadership"
			% [nation_id, person_id, rest]
		)
		return

	# meter:<key> is validated against METER_KEYS in person.gd, at parse -- it
	# is a closed vocabulary, not a cross-register reference; nothing further
	# here.


static func check_person_ref(loader, nation_id: String, where: String, slot: String, pid: String, referenced: Dictionary) -> void:
	if not loader.person_by_id.has(pid):
		loader.errors.append("%s: %s names person '%s', which is not in the register" % [where, slot, pid])
		return
	# A nation pointing at another nation's person would resolve to a name and be
	# wrong in the one way a resolving reference can be — the same reason
	# GeoLoader.validate_neighbours() checks mutuality rather than mere existence.
	if not pid.begins_with("%s_" % nation_id):
		loader.errors.append("%s: %s names person '%s', who belongs to another nation" % [where, slot, pid])
		return
	# V5.3-0: an office or a party's leadership is a seat in the arithmetic, and
	# staff hold none (CharacterK.KIND_STAFF).
	var kind := String(loader.person_by_id[pid].kind)
	if CharacterK.KIND_STAFF.has(kind):
		loader.errors.append("%s: %s names person '%s', who is staff (kind '%s') and holds no slot" % [where, slot, pid, kind])
		return
	referenced[pid] = true


## V5.2d. The voice archetype table (data/voices/archetypes.json): its rows by id and
## its defaults. Read once; src/core/voices.gd is the one reader.
static func load_voices(loader, path: String) -> void:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("archetypes")) != TYPE_ARRAY \
			or typeof(parsed.get("defaults")) != TYPE_DICTIONARY:
		loader.errors.append("%s: could not read the voice table, expected {\"archetypes\": [...], \"defaults\": {...}}" % path)
		return
	for row in parsed["archetypes"]:
		if typeof(row) == TYPE_DICTIONARY and String(row.get("id", "")) != "":
			loader.voice_archetypes[String(row["id"])] = row
	for key in parsed["defaults"]:
		loader.voice_defaults[String(key)] = String(parsed["defaults"][key])


## A person's voice names an archetype the table defines, of the person's own kind
## -- a typo would voice nothing, a wrong kind would put a press owner's voice on a
## judge. Every default names a defined archetype.
static func validate_voices(loader) -> void:
	for pid in loader.person_by_id:
		var person = loader.person_by_id[pid]
		if String(person.voice) == "":
			continue
		var row = loader.voice_archetypes.get(String(person.voice), null)
		if row == null:
			loader.errors.append("people: %s voice '%s' is not an archetype in data/voices/archetypes.json" % [pid, person.voice])
		elif String(row.get("kind", "")) != String(person.kind):
			loader.errors.append("people: %s is a %s but voice '%s' is a %s archetype" % [pid, person.kind, person.voice, row.get("kind", "")])
	for key in loader.voice_defaults:
		if not loader.voice_archetypes.has(loader.voice_defaults[key]):
			loader.errors.append("data/voices/archetypes.json: default '%s' names no archetype ('%s')" % [key, loader.voice_defaults[key]])
