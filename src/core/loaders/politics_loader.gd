extends RefCounted

## V5.0b: one of DataLoader's per-content loaders. Parties, laws, political systems and scenarios, with the validators that read them against each other.
##
## Static functions over the loader they fill: DataLoader.load_all() is the one
## orchestrator (a few test entry points delegate here too), every register lives on the loader
## (its public surface did not move), and each function here is the body that
## used to be DataLoader._<name>() verbatim (now <ThisLoader>.<name>), its members read
## through `loader.`.

const C = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
const Law = preload("res://src/core/law.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const Party = preload("res://src/core/party.gd")
const PoliticalSystem = preload("res://src/core/political_system.gd")
const Scenario = preload("res://src/core/scenario.gd")

const MIN_PARTIES := 4

const MAX_PARTIES := 6


static func load_parties(loader, nation_id: String, parties_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := parties_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		loader.errors.append("%s: could not read file" % path)
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("parties")) != TYPE_ARRAY:
		loader.errors.append("%s: invalid party file, expected {\"parties\": [...]}" % fname)
		return

	var raw_list: Array = parsed["parties"]
	var parsed_parties: Array[Party] = []
	var per_file_errors: Array[String] = []
	var seen_ids := {}
	var total := 0.0

	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			per_file_errors.append("%s: parties[%d] is not an object" % [fname, i])
			continue
		var party = Party.from_dict(entry, i, fname, per_file_errors)
		if party.id != "":
			if seen_ids.has(party.id):
				per_file_errors.append("%s: duplicate party id '%s'" % [fname, party.id])
			seen_ids[party.id] = true
		total += party.seat_share
		parsed_parties.append(party)

	if parsed_parties.size() < MIN_PARTIES or parsed_parties.size() > MAX_PARTIES:
		per_file_errors.append("%s: expected %d-%d parties, got %d" % [fname, MIN_PARTIES, MAX_PARTIES, parsed_parties.size()])

	if absf(total - 1.0) > 0.001:
		per_file_errors.append("%s: seat_share sums to %s, expected 1.0" % [fname, str(total)])

	for party in parsed_parties:
		if party.ideology_slot != "" and not K.SLOT_KEYS.has(party.ideology_slot):
			per_file_errors.append("%s: ideology_slot '%s' has no position in election_constants.SLOT_POSITION" % [fname, party.ideology_slot])

		# A cordon naming a party that does not exist would silently exclude
		# nothing, which is the same class of quiet failure the slot check above
		# exists to catch.
		for other in party.excluded_partners:
			if not seen_ids.has(other):
				per_file_errors.append("%s: party '%s' excludes '%s', which is not a party in this nation" % [fname, party.id, other])
			elif other == party.id:
				per_file_errors.append("%s: party '%s' excludes itself" % [fname, party.id])

	loader.errors.append_array(per_file_errors)
	loader.parties[nation_id] = parsed_parties


## Reads every data/laws/*.json file -- each {"laws": [...]}, grouped by theme,
## same shape as data/parties/*.json. See docs/legislature-model.md.
static func load_laws(loader, laws_dir: String) -> void:
	var da := DirAccess.open(laws_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % laws_dir)
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
		var path := laws_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("laws")) != TYPE_ARRAY:
			loader.errors.append("%s: invalid law file, expected {\"laws\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["laws"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				loader.errors.append("%s: laws[%d] is not an object" % [fname, i])
				continue
			var law = Law.from_dict(entry, fname, loader.errors, C.TAX_KEYS, C.SPENDING_KEYS, OpinionK.BLOC_KEYS, C.SECTOR_TREND.keys())
			if law.id != "":
				if seen_ids.has(law.id):
					loader.errors.append("%s: duplicate law id '%s'" % [fname, law.id])
				seen_ids[law.id] = true
			loader.laws.append(law)


## Reads every data/political-systems/*.json file. See docs/political-systems.md
## and political_system.gd's own header for why a template is a constraint, not
## a defaults table -- the constraint itself is enforced below, in
## GeoLoader.validate_cross_file(), against every nation that names one.
static func load_political_systems(loader, political_systems_dir: String) -> void:
	var da := DirAccess.open(political_systems_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % political_systems_dir)
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
		var path := political_systems_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			loader.errors.append("%s: invalid JSON" % fname)
			continue

		var per_file_errors: Array[String] = []
		var system = PoliticalSystem.from_dict(parsed, fname, per_file_errors)
		loader.errors.append_array(per_file_errors)
		if system.id != "":
			loader.political_systems[system.id] = system


## Reads every data/scenarios/*.json file -- one authored starting state each.
## Same directory-scan shape as laws and political systems: no manifest, so
## adding a scenario is a file, not a file plus an index entry. The cross-file
## half of the validation (which nation, which parties, which blocs) is
## PoliticsLoader.validate_scenarios() below. See docs/scenario-model.md.
static func load_scenarios(loader, scenarios_dir: String) -> void:
	var da := DirAccess.open(scenarios_dir)
	if da == null:
		loader.errors.append("%s: directory not found" % scenarios_dir)
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
		var path := scenarios_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			loader.errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			loader.errors.append("%s: invalid JSON" % fname)
			continue

		var per_file_errors: Array[String] = []
		var scenario = Scenario.from_dict(parsed, fname, per_file_errors)
		loader.errors.append_array(per_file_errors)
		if scenario.id != "":
			if loader.scenarios.has(scenario.id):
				loader.errors.append("%s: duplicate scenario id '%s'" % [fname, scenario.id])
			loader.scenarios[scenario.id] = scenario


## The template is a constraint, not a defaults table -- see political_system.gd.
## A nation's formation/censure/dissolution rule must fall inside the set its
## own template declares, and a term limit may only be authored where the
## template permits one. Failing loudly here is what makes the template
## load-bearing rather than decorative.
static func validate_political_system(loader, n) -> void:
	if not loader.political_systems.has(n.system_id):
		loader.errors.append("%s.json: government.system '%s' names no file in data/political-systems/" % [n.id, n.system_id])
		return

	var system: PoliticalSystem = loader.political_systems[n.system_id]
	if not system.allowed_formation_methods.has(n.formation_method):
		loader.errors.append("%s.json: government.formation.method '%s' is not permitted by system '%s'" % [n.id, n.formation_method, n.system_id])
	if not system.allowed_censure_rules.has(n.censure_rule):
		loader.errors.append("%s.json: government.formation.censure '%s' is not permitted by system '%s'" % [n.id, n.censure_rule, n.system_id])
	if not system.allowed_dissolution_rules.has(n.dissolution_rule):
		loader.errors.append("%s.json: government.legislative.dissolution.rule '%s' is not permitted by system '%s'" % [n.id, n.dissolution_rule, n.system_id])
	if not system.allowed_amendment_rules.has(n.amendment_rule):
		loader.errors.append("%s.json: government.amendment.rule '%s' is not permitted by system '%s'" % [n.id, n.amendment_rule, n.system_id])
	if n.term_limit > 0 and not system.permits_term_limit:
		loader.errors.append("%s.json: government.term_limit %d is set but system '%s' does not permit a term limit" % [n.id, n.term_limit, n.system_id])
	if not system.allowed_head_of_state_kinds.has(n.head_of_state_kind):
		loader.errors.append("%s.json: government.head_of_state.kind '%s' is not permitted by system '%s'" % [n.id, n.head_of_state_kind, n.system_id])


## A constitutional amendment can write an institutional field at RUNTIME, long
## past this startup check -- so the check that makes V1.2b's template
## load-bearing (a nation's flat field must fall inside its template's allowed
## set) has to hold for every value an amendment could ever WRITE, not just the
## value a nation starts with. Checked once here, against every system named in
## the amendment's own `systems` list, so a violating amendment cannot load --
## the runtime state it would produce is refused the same way a bad nation file
## already is. See docs/amendment-model.md.
static func validate_amendments(loader) -> void:
	for law in loader.laws:
		if not law.constitutional:
			continue
		var inst: Dictionary = law.effects.get("institutional", {})

		if law.changes_system:
			# A system transition writes every institutional field against a
			# TARGET system, not the systems it's proposed under -- `systems`
			# still gates proposability, but the written state must be legal
			# under where it lands, not where it started. See
			# docs/transition-model.md.
			validate_institutional_against_system(loader, law, inst, String(inst["system_id"]))
			continue

		for system_id in law.systems:
			validate_institutional_against_system(loader, law, inst, system_id)


## Checks `inst` -- one law's effects.institutional -- against one named
## system, appending an error for every field that system does not permit.
## Shared by an ordinary amendment (checked against every system it's
## proposed UNDER) and a system transition (checked against the single system
## it TARGETS) -- see PoliticsLoader.validate_amendments() above.
static func validate_institutional_against_system(loader, law, inst: Dictionary, system_id: String) -> void:
	if not loader.political_systems.has(system_id):
		loader.errors.append("laws: %s names system '%s', which has no file in data/political-systems/" % [law.id, system_id])
		return
	var system: PoliticalSystem = loader.political_systems[system_id]
	if inst.has("censure_rule") and not system.allowed_censure_rules.has(inst["censure_rule"]):
		loader.errors.append("laws: %s effects.institutional.censure_rule '%s' is not permitted by system '%s'" % [law.id, inst["censure_rule"], system_id])
	if inst.has("dissolution_rule") and not system.allowed_dissolution_rules.has(inst["dissolution_rule"]):
		loader.errors.append("laws: %s effects.institutional.dissolution_rule '%s' is not permitted by system '%s'" % [law.id, inst["dissolution_rule"], system_id])
	if inst.has("formation_method") and not system.allowed_formation_methods.has(inst["formation_method"]):
		loader.errors.append("laws: %s effects.institutional.formation_method '%s' is not permitted by system '%s'" % [law.id, inst["formation_method"], system_id])
	if inst.has("amendment_rule") and not system.allowed_amendment_rules.has(inst["amendment_rule"]):
		loader.errors.append("laws: %s effects.institutional.amendment_rule '%s' is not permitted by system '%s'" % [law.id, inst["amendment_rule"], system_id])
	if inst.has("term_limit") and int(inst["term_limit"]) > 0 and not system.permits_term_limit:
		loader.errors.append("laws: %s effects.institutional.term_limit %d is set but system '%s' does not permit a term limit" % [law.id, int(inst["term_limit"]), system_id])
	if inst.has("head_of_state"):
		var hos: Dictionary = inst["head_of_state"]
		if hos.has("kind") and not system.allowed_head_of_state_kinds.has(hos["kind"]):
			loader.errors.append("laws: %s effects.institutional.head_of_state.kind '%s' is not permitted by system '%s'" % [law.id, hos["kind"], system_id])


## The cross-file half of a scenario's validation -- everything that needs the
## nation's own roster rather than just the scenario file. Fails loudly at
## startup for the same reason a bad nation file does: a scenario is authored
## content, and a scenario naming a party that does not exist would silently
## override nothing. See docs/scenario-model.md.
static func validate_scenarios(loader) -> void:
	for id in loader.scenarios.keys():
		var s: Scenario = loader.scenarios[id]

		if not loader.nations.has(s.nation_id):
			loader.errors.append("%s.json: nation '%s' is not a loaded nation" % [id, s.nation_id])
			continue

		# Playable, not merely loaded. A scenario is offered from the nation-select
		# surface, which lists playable nations only -- one authored against an
		# unplayable nation is content nothing can ever reach.
		var n = loader.nations[s.nation_id]
		if not n.playable:
			loader.errors.append("%s.json: nation '%s' is not playable, so this scenario can never be selected" % [id, s.nation_id])

		var roster: Array = loader.parties.get(s.nation_id, [])
		if not s.seat_share.is_empty():
			# Merged over the nation's authored shares, then summed -- the same
			# invariant PoliticsLoader.load_parties() holds the party file to, checked against
			# what the scenario ACTUALLY produces rather than against the override
			# fragment, which is not required to sum to anything on its own.
			var merged := {}
			for party in roster:
				merged[party.id] = party.seat_share
			for party_id in s.seat_share.keys():
				if not merged.has(party_id):
					loader.errors.append("%s.json: overrides.seat_share names '%s', which is not a party in data/parties/%s.json" % [id, party_id, s.nation_id])
					continue
				merged[party_id] = s.seat_share[party_id]

			var total := 0.0
			for share in merged.values():
				total += float(share)
			if absf(total - 1.0) > 0.001:
				loader.errors.append("%s.json: overrides.seat_share leaves the roster summing to %s, expected 1.0" % [id, str(total)])

		for bloc in s.bloc_approval.keys():
			if not OpinionK.BLOC_KEYS.has(bloc):
				loader.errors.append("%s.json: overrides.bloc_approval names '%s', which is not a voter bloc" % [id, bloc])
