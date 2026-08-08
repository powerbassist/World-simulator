class_name DataLoader
extends RefCounted

## Loads and validates every data/nations/*.json file. Always validates,
## always fails loudly — see docs/data-architecture.md.

const Nation = preload("res://src/core/nation.gd")
const Party = preload("res://src/core/party.gd")
const Law = preload("res://src/core/law.gd")
const PoliticalSystem = preload("res://src/core/political_system.gd")
const Scenario = preload("res://src/core/scenario.gd")
const DiplomaticAction = preload("res://src/core/diplomatic_action.gd")
const BlocProposal = preload("res://src/core/bloc_proposal.gd")
const Person = preload("res://src/core/person.gd")
const Company = preload("res://src/core/company.gd")
const CompanyAction = preload("res://src/core/company_action.gd")
const C = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

const MIN_PARTIES := 4
const MAX_PARTIES := 6

const EU = preload("res://src/core/eu.gd")

var nations: Dictionary = {}  # String id -> Nation
var parties: Dictionary = {}  # String id -> Array[Party]

## nation id -> Array[Person], in authored file order — the order the People
## window reads, and the only order anything reads, since nothing looks a person
## up by position.
var people: Dictionary = {}

## person id -> Person, FLAT and global. This is the dictionary that matters: a
## party id is only ever read inside a nation's context, so `parties` can be
## keyed by nation and party ids can collide across nations silently. A person id
## is read BARE — off NationState.pm_person_id, off an appointment entry that
## carries no nation field, out of last_censure in a save — so it has to be
## self-describing and globally unique. Hence the `<NATION>_<surname>` scheme and
## the prefix check in _validate_people(). See docs/people-model.md.
var person_by_id: Dictionary = {}
## nation id -> Array[Company], in authored file order — the order the Companies
## window reads. UNLIKE `people`, a nation may legitimately be ABSENT here: a
## nation with no data/companies/<ID>.json has unpartitioned sectors, which is
## what every nation looked like before V1.4a. That is why _load_companies() does
## not append a "could not read file" error the way _load_people() does.
var companies: Dictionary = {}

## Ordered, not keyed by id, the same way `laws` and `diplomatic_actions` are:
## the companies panel offers them as a list in authored order and nothing looks
## one up by id at runtime.
var company_actions: Array[CompanyAction] = []

var laws: Array[Law] = []
var political_systems: Dictionary = {}  # String id -> PoliticalSystem
var scenarios: Dictionary = {}  # String id -> Scenario

## Ordered, not keyed by id, the same way `laws` is: the nation panel offers
## them as a list in authored order and nothing looks one up by id at runtime.
var diplomatic_actions: Array[DiplomaticAction] = []

## Ordered, not keyed by id, and the order is load-bearing here in a way it is
## not for laws or diplomatic actions: src/sim/bloc.gd walks this list with a
## rotating index to decide what reaches the council next, so authored order IS
## the agenda. That is what keeps the council deterministic with no RNG.
var bloc_proposals: Array[BlocProposal] = []

var eu: EU = null
var errors: Array[String] = []

## geo feature id -> Array[PackedVector2Array]. One entry per polygon in the
## feature's MultiPolygon; each PackedVector2Array is that polygon's outer ring
## only, raw (lon, lat) degrees -- holes are not kept, S8's map only needs
## recognisable borders and a click hit-test, not exact enclaves. Read once at
## startup by _load_geo(), same as the id list _validate_cross_file already
## cross-checks.
var geo_features: Dictionary = {}

## The same shape as geo_features, for the ~160 countries the game does not
## simulate -- U5b's backdrop. Kept in a separate dictionary rather than merged,
## because the separation is what makes a non-simulated country structurally
## unclickable: map_view.gd hit-tests geo_features and only geo_features, so
## there is no filter anywhere that could be forgotten.
var world_features: Dictionary = {}

## Feature id -> Vector2(lon, lat), Natural Earth's own hand-placed label anchor.
## Both files contribute; map_view.gd draws labels for the roster only.
var label_points: Dictionary = {}


func load_all(nations_dir := "res://data/nations", geo_path := "res://data/geo/europe.geojson", parties_dir := "res://data/parties", eu_path := "res://data/eu_parliament.json", laws_dir := "res://data/laws", political_systems_dir := "res://data/political-systems", scenarios_dir := "res://data/scenarios", diplomatic_actions_dir := "res://data/diplomatic-actions", world_path := "res://data/geo/world.geojson", bloc_proposals_dir := "res://data/bloc-proposals", people_dir := "res://data/people", companies_dir := "res://data/companies", company_actions_dir := "res://data/company-actions") -> void:
	nations.clear()
	parties.clear()
	people.clear()
	person_by_id.clear()
	companies.clear()
	company_actions.clear()
	laws.clear()
	political_systems.clear()
	scenarios.clear()
	diplomatic_actions.clear()
	bloc_proposals.clear()
	errors = []

	var da := DirAccess.open(nations_dir)
	if da == null:
		errors.append("%s: directory not found" % nations_dir)
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
		var path := nations_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s: invalid JSON" % fname)
			continue

		var per_file_errors: Array[String] = []
		var nation = Nation.from_dict(parsed, fname, per_file_errors)
		errors.append_array(per_file_errors)
		if nation.id != "":
			nations[nation.id] = nation

	# People before parties, because _load_parties() resolves each party's
	# leader_person_id against the register and a reference cannot be checked
	# against a dictionary that has not been filled yet.
	for id in nations.keys():
		_load_people(id, people_dir)
	for id in nations.keys():
		_load_parties(id, parties_dir)
	for id in nations.keys():
		_load_companies(id, companies_dir)

	_load_company_actions(company_actions_dir)
	_load_laws(laws_dir)
	_load_political_systems(political_systems_dir)
	_load_scenarios(scenarios_dir)
	_load_diplomatic_actions(diplomatic_actions_dir)
	_load_bloc_proposals(bloc_proposals_dir)

	eu = EU.new()
	eu.load(eu_path)
	errors.append_array(eu.errors)

	_validate_cross_file(geo_path, world_path)
	_validate_amendments()
	_validate_scenarios()
	_validate_neighbours()
	_validate_bloc_proposals()
	_validate_people()
	_validate_companies()


## Resolve a person id to the name a screen prints. The ONLY reader of
## `person_by_id` outside this file, and the reason U6b needed no `people.gd`
## module: a name lookup is a dictionary read, and every panel that wants one
## already holds the loader. An unknown or empty id gives "", which is what the
## panels already did with an empty name field before the re-key -- so a
## government that does not exist still reads as one that does not exist.
func person_name(person_id: String) -> String:
	var person = person_by_id.get(person_id, null)
	return person.person_name if person != null else ""


## One data/people/<NATION>.json per nation, {"people": [...]}, the same shape
## and the same failure modes as data/parties/*.json. See docs/people-model.md.
func _load_people(nation_id: String, people_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := people_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: could not read file" % path)
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("people")) != TYPE_ARRAY:
		errors.append("%s: invalid people file, expected {\"people\": [...]}" % fname)
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

		if person_by_id.has(person.id):
			per_file_errors.append(
				"%s: person id '%s' is already used in another nation's file" % [fname, person.id]
			)
		else:
			person_by_id[person.id] = person
		parsed_people.append(person)

	errors.append_array(per_file_errors)
	people[nation_id] = parsed_people


## Every person is referenced, and every reference resolves inside its own
## nation. The first half is the unusual one and it is deliberate: an
## unreferenced person is content with no caller, which is what U6b's own probe
## cut a five-deep minister bench for. Authoring a name nobody can reach should
## fail the load rather than sit in a file looking like a feature.
func _validate_people() -> void:
	var referenced := {}

	for nation_id in nations.keys():
		var nation = nations[nation_id]
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
			_check_person_ref(nation_id, "%s.json" % nation_id, slot, pid, referenced)

		for party in parties.get(nation_id, []):
			if party.leader_person_id == "":
				continue
			_check_person_ref(
				nation_id, "parties/%s.json" % nation_id,
				"party '%s' leader_person" % party.id, party.leader_person_id, referenced
			)

	for nation_id in people.keys():
		for person in people[nation_id]:
			if not referenced.has(person.id):
				errors.append(
					"people/%s.json: person '%s' (%s) is referenced by nothing"
					% [nation_id, person.id, person.person_name]
				)


func _check_person_ref(nation_id: String, where: String, slot: String, pid: String, referenced: Dictionary) -> void:
	if not person_by_id.has(pid):
		errors.append("%s: %s names person '%s', which is not in the register" % [where, slot, pid])
		return
	# A nation pointing at another nation's person would resolve to a name and be
	# wrong in the one way a resolving reference can be — the same reason
	# _validate_neighbours() checks mutuality rather than mere existence.
	if not pid.begins_with("%s_" % nation_id):
		errors.append("%s: %s names person '%s', who belongs to another nation" % [where, slot, pid])
		return
	referenced[pid] = true


## One data/companies/<NATION>.json per nation, {"companies": [...]}, the same
## shape as data/people/*.json. See docs/companies-model.md.
##
## AN ABSENT FILE IS NOT AN ERROR, where an absent people file is. Every nation
## needs a leader; only a nation somebody can play needs firms, because only a
## player can subsidise one and _validate_companies() below refuses content
## nothing can reach. A nation with no file has unpartitioned sectors, which is
## what all ten had before this session -- so the seven that are not yet playable
## keep running the model they always ran.
func _load_companies(nation_id: String, companies_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := companies_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		companies[nation_id] = []
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("companies")) != TYPE_ARRAY:
		errors.append("%s: invalid companies file, expected {\"companies\": [...]}" % fname)
		companies[nation_id] = []
		return

	var raw_list: Array = parsed["companies"]
	var parsed_companies: Array = []
	var per_file_errors: Array[String] = []
	var seen_ids := {}

	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			per_file_errors.append("%s: companies[%d] is not an object" % [fname, i])
			continue
		var company = Company.from_dict(entry, i, fname, per_file_errors)
		if company.id == "":
			continue

		# The prefix rule people-model.md argues for, applied to a second register
		# and for a weaker reason honestly stated: a company id is read inside a
		# nation's context today, the way a party id is. It is namespaced anyway
		# because the register is keyed by it in a save and on an appointment entry
		# a later session may well book -- and re-namespacing after that happens is
		# the migration U6b had to perform on three fields.
		if not company.id.begins_with("%s_" % nation_id):
			per_file_errors.append(
				"%s: company id '%s' must begin with '%s_'" % [fname, company.id, nation_id]
			)
		if seen_ids.has(company.id):
			per_file_errors.append("%s: duplicate company id '%s'" % [fname, company.id])
		seen_ids[company.id] = true
		parsed_companies.append(company)

	errors.append_array(per_file_errors)
	companies[nation_id] = parsed_companies


## The cross-file half, and both checks are about content that cannot do anything.
##
## A sector's named shares summing past 1.0 is a partition claiming more than the
## sector holds. A sector holding exactly ONE named firm is subtler and is the
## check worth having: a lone firm has no rival to take share from, so a subsidy
## pointed at it moves nothing at all and the player pays a real bill for it. That
## is docs/tiers/v1.md section 6's "sectoral investment -- a lever pointed at a
## sector" wearing a firm's name, and refusing it at load is what keeps V1.4's
## subsidy and V1.6's sector lever distinguishable.
func _validate_companies() -> void:
	for nation_id in companies.keys():
		var by_sector := {}
		for company in companies[nation_id]:
			if company.sector == "":
				continue
			if not by_sector.has(company.sector):
				by_sector[company.sector] = []
			by_sector[company.sector].append(company)

		for sector in by_sector.keys():
			var group: Array = by_sector[sector]
			if group.size() < 2:
				errors.append(
					"companies/%s.json: sector '%s' has one named firm ('%s') -- a firm with no rival cannot gain share from anybody, so a subsidy pointed at it is a sector lever with a company's name on it"
					% [nation_id, sector, group[0].id]
				)
			var total := 0.0
			for company in group:
				total += company.share
			if total > 1.0 + 0.000001:
				errors.append(
					"companies/%s.json: sector '%s' shares sum to %s, above 1.0 -- the named firms would hold more than the sector does"
					% [nation_id, sector, str(total)]
				)


## Directory-scanned, exactly like _load_diplomatic_actions() -- adding a verb is
## a file, not a file plus an index entry. Every file holds {"actions": [...]}.
func _load_company_actions(actions_dir: String) -> void:
	var da := DirAccess.open(actions_dir)
	if da == null:
		errors.append("%s: directory not found" % actions_dir)
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
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("actions")) != TYPE_ARRAY:
			errors.append("%s: invalid company-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = CompanyAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					errors.append("%s: duplicate company action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true
			company_actions.append(action)


func _load_parties(nation_id: String, parties_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := parties_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("%s: could not read file" % path)
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("parties")) != TYPE_ARRAY:
		errors.append("%s: invalid party file, expected {\"parties\": [...]}" % fname)
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

	errors.append_array(per_file_errors)
	parties[nation_id] = parsed_parties


## Reads every data/laws/*.json file -- each {"laws": [...]}, grouped by theme,
## same shape as data/parties/*.json. See docs/legislature-model.md.
func _load_laws(laws_dir: String) -> void:
	var da := DirAccess.open(laws_dir)
	if da == null:
		errors.append("%s: directory not found" % laws_dir)
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
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("laws")) != TYPE_ARRAY:
			errors.append("%s: invalid law file, expected {\"laws\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["laws"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: laws[%d] is not an object" % [fname, i])
				continue
			var law = Law.from_dict(entry, fname, errors, C.TAX_KEYS, C.SPENDING_KEYS, OpinionK.BLOC_KEYS, C.SECTOR_TREND.keys())
			if law.id != "":
				if seen_ids.has(law.id):
					errors.append("%s: duplicate law id '%s'" % [fname, law.id])
				seen_ids[law.id] = true
			laws.append(law)


## Reads every data/political-systems/*.json file. See docs/political-systems.md
## and political_system.gd's own header for why a template is a constraint, not
## a defaults table -- the constraint itself is enforced below, in
## _validate_cross_file(), against every nation that names one.
func _load_political_systems(political_systems_dir: String) -> void:
	var da := DirAccess.open(political_systems_dir)
	if da == null:
		errors.append("%s: directory not found" % political_systems_dir)
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
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s: invalid JSON" % fname)
			continue

		var per_file_errors: Array[String] = []
		var system = PoliticalSystem.from_dict(parsed, fname, per_file_errors)
		errors.append_array(per_file_errors)
		if system.id != "":
			political_systems[system.id] = system


## Reads every data/scenarios/*.json file -- one authored starting state each.
## Same directory-scan shape as laws and political systems: no manifest, so
## adding a scenario is a file, not a file plus an index entry. The cross-file
## half of the validation (which nation, which parties, which blocs) is
## _validate_scenarios() below. See docs/scenario-model.md.
func _load_scenarios(scenarios_dir: String) -> void:
	var da := DirAccess.open(scenarios_dir)
	if da == null:
		errors.append("%s: directory not found" % scenarios_dir)
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
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s: invalid JSON" % fname)
			continue

		var per_file_errors: Array[String] = []
		var scenario = Scenario.from_dict(parsed, fname, per_file_errors)
		errors.append_array(per_file_errors)
		if scenario.id != "":
			if scenarios.has(scenario.id):
				errors.append("%s: duplicate scenario id '%s'" % [fname, scenario.id])
			scenarios[scenario.id] = scenario


## Directory-scanned, exactly like _load_laws() and _load_scenarios() -- adding
## an action is a file, not a file plus an index entry. Every file holds
## {"actions": [...]}, matching a law file's {"laws": [...]}, so several actions
## can share a themed file. There is no cross-file half: an action names no
## nation, no party and no bloc roster beyond the global BLOC_KEYS its own
## from_dict already checks. See docs/diplomacy-model.md.
func _load_diplomatic_actions(actions_dir: String) -> void:
	var da := DirAccess.open(actions_dir)
	if da == null:
		errors.append("%s: directory not found" % actions_dir)
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
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("actions")) != TYPE_ARRAY:
			errors.append("%s: invalid diplomatic-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = DiplomaticAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					errors.append("%s: duplicate diplomatic action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true
			diplomatic_actions.append(action)


## Directory-scanned, exactly like _load_laws(), _load_scenarios() and
## _load_diplomatic_actions() -- adding a proposal is a file, not a file plus an
## index entry. Every file holds {"proposals": [...]}, matching a law file's
## {"laws": [...]}, so several proposals can share a themed file.
##
## Unlike those three, the ORDER matters: src/sim/bloc.gd rotates an index over
## this list to decide what reaches the council next, so the filename sort below
## and the authored order inside each file together are the agenda. That is the
## price of a scheduler with no RNG in it, and it is the right price.
func _load_bloc_proposals(proposals_dir: String) -> void:
	var da := DirAccess.open(proposals_dir)
	if da == null:
		errors.append("%s: directory not found" % proposals_dir)
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
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("proposals")) != TYPE_ARRAY:
			errors.append("%s: invalid bloc-proposal file, expected {\"proposals\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["proposals"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: proposals[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var proposal = BlocProposal.from_dict(entry, fname, per_file_errors)
			errors.append_array(per_file_errors)
			if proposal.id != "":
				if seen_ids.has(proposal.id):
					errors.append("%s: duplicate bloc proposal id '%s'" % [fname, proposal.id])
				seen_ids[proposal.id] = true
			bloc_proposals.append(proposal)


## The cross-file half: a proposal names no nation, but two of its shapes only
## mean something against the roster it will run in.
##
## Runs after eu.load(), because both checks need the membership table.
func _validate_bloc_proposals() -> void:
	var member_count := 0
	var outsider_count := 0
	for id in nations.keys():
		if eu.is_member(id):
			member_count += 1
		else:
			outsider_count += 1

	for p in bloc_proposals:
		# A collective external tariff with nobody outside the bloc to levy it on
		# is content that can never do anything -- the same class of quiet failure
		# a scenario naming an unplayable nation is refused for.
		if not p.external_measure.is_empty() and outsider_count == 0:
			errors.append("bloc-proposals: %s sets an external measure, but every loaded nation is a member" % p.id)
		if member_count == 0:
			errors.append("bloc-proposals: %s is loaded, but no loaded nation is a bloc member" % p.id)


## A land border is mutual or it is not a land border. Nation.gd already checked
## each list's shape against its own file; only here is the whole roster in
## scope, so only here can "FRA lists DEU but DEU does not list FRA" be caught.
##
## This is what lets src/sim/diplomacy.gd derive one resting value per unordered
## pair without asking which nation's file it should believe -- the symmetric
## pair key of src/core/relations.gd would otherwise be resting on an asymmetric
## input. See docs/diplomacy-model.md.
func _validate_neighbours() -> void:
	for id in nations.keys():
		var n = nations[id]
		for other_id in n.neighbours:
			if not nations.has(other_id):
				errors.append("%s.json: government.neighbours names '%s', which is not a loaded nation" % [id, other_id])
				continue
			if not nations[other_id].neighbours.has(id):
				errors.append("%s.json: government.neighbours lists '%s', but %s.json does not list '%s' back" % [
					id, other_id, other_id, id
				])


func _validate_cross_file(geo_path: String, world_path: String) -> void:
	if nations.size() != 10:
		errors.append("expected 10 nations, loaded %d" % nations.size())

	# At least one, not exactly one -- V1.2a made a second nation playable, and
	# a third later is a one-flag data edit, not a code change. See ROADMAP.md.
	var playable_count := 0
	for n in nations.values():
		if n.playable:
			playable_count += 1
	if playable_count < 1:
		errors.append("expected at least 1 playable nation, found %d" % playable_count)

	label_points.clear()
	var geo_ids := _load_geo(geo_path, geo_features)
	for n in nations.values():
		if not geo_ids.has(n.geo_id):
			errors.append("%s.json: geo_id '%s' has no matching feature in %s" % [n.id, n.geo_id, geo_path])

	_load_geo(world_path, world_features)

	for id in nations.keys():
		var n = nations[id]
		var roster: Array = parties.get(id, [])
		var found := false
		for party in roster:
			if party.id == n.leader_party_id:
				found = true
				break
		if not found:
			errors.append("%s.json: leader.party '%s' does not match any party in data/parties/%s.json" % [id, n.leader_party_id, id])

		if n.eu_member != eu.is_member(id):
			errors.append("%s.json: government.eu.member=%s but data/eu_parliament.json members %s '%s'" % [
				id, n.eu_member, "has" if eu.is_member(id) else "lacks", id
			])
		elif n.eu_member and n.eu_ep_seats != eu.ep_seats(id):
			errors.append("%s.json: government.eu.ep_seats %d does not match data/eu_parliament.json's %d for '%s'" % [
				id, n.eu_ep_seats, eu.ep_seats(id), id
			])

		_validate_political_system(n)


## The template is a constraint, not a defaults table -- see political_system.gd.
## A nation's formation/censure/dissolution rule must fall inside the set its
## own template declares, and a term limit may only be authored where the
## template permits one. Failing loudly here is what makes the template
## load-bearing rather than decorative.
func _validate_political_system(n) -> void:
	if not political_systems.has(n.system_id):
		errors.append("%s.json: government.system '%s' names no file in data/political-systems/" % [n.id, n.system_id])
		return

	var system: PoliticalSystem = political_systems[n.system_id]
	if not system.allowed_formation_methods.has(n.formation_method):
		errors.append("%s.json: government.formation.method '%s' is not permitted by system '%s'" % [n.id, n.formation_method, n.system_id])
	if not system.allowed_censure_rules.has(n.censure_rule):
		errors.append("%s.json: government.formation.censure '%s' is not permitted by system '%s'" % [n.id, n.censure_rule, n.system_id])
	if not system.allowed_dissolution_rules.has(n.dissolution_rule):
		errors.append("%s.json: government.legislative.dissolution.rule '%s' is not permitted by system '%s'" % [n.id, n.dissolution_rule, n.system_id])
	if not system.allowed_amendment_rules.has(n.amendment_rule):
		errors.append("%s.json: government.amendment.rule '%s' is not permitted by system '%s'" % [n.id, n.amendment_rule, n.system_id])
	if n.term_limit > 0 and not system.permits_term_limit:
		errors.append("%s.json: government.term_limit %d is set but system '%s' does not permit a term limit" % [n.id, n.term_limit, n.system_id])
	if not system.allowed_head_of_state_kinds.has(n.head_of_state_kind):
		errors.append("%s.json: government.head_of_state.kind '%s' is not permitted by system '%s'" % [n.id, n.head_of_state_kind, n.system_id])


## A constitutional amendment can write an institutional field at RUNTIME, long
## past this startup check -- so the check that makes V1.2b's template
## load-bearing (a nation's flat field must fall inside its template's allowed
## set) has to hold for every value an amendment could ever WRITE, not just the
## value a nation starts with. Checked once here, against every system named in
## the amendment's own `systems` list, so a violating amendment cannot load --
## the runtime state it would produce is refused the same way a bad nation file
## already is. See docs/amendment-model.md.
func _validate_amendments() -> void:
	for law in laws:
		if not law.constitutional:
			continue
		var inst: Dictionary = law.effects.get("institutional", {})

		if law.changes_system:
			# A system transition writes every institutional field against a
			# TARGET system, not the systems it's proposed under -- `systems`
			# still gates proposability, but the written state must be legal
			# under where it lands, not where it started. See
			# docs/transition-model.md.
			_validate_institutional_against_system(law, inst, String(inst["system_id"]))
			continue

		for system_id in law.systems:
			_validate_institutional_against_system(law, inst, system_id)


## Checks `inst` -- one law's effects.institutional -- against one named
## system, appending an error for every field that system does not permit.
## Shared by an ordinary amendment (checked against every system it's
## proposed UNDER) and a system transition (checked against the single system
## it TARGETS) -- see _validate_amendments() above.
func _validate_institutional_against_system(law, inst: Dictionary, system_id: String) -> void:
	if not political_systems.has(system_id):
		errors.append("laws: %s names system '%s', which has no file in data/political-systems/" % [law.id, system_id])
		return
	var system: PoliticalSystem = political_systems[system_id]
	if inst.has("censure_rule") and not system.allowed_censure_rules.has(inst["censure_rule"]):
		errors.append("laws: %s effects.institutional.censure_rule '%s' is not permitted by system '%s'" % [law.id, inst["censure_rule"], system_id])
	if inst.has("dissolution_rule") and not system.allowed_dissolution_rules.has(inst["dissolution_rule"]):
		errors.append("laws: %s effects.institutional.dissolution_rule '%s' is not permitted by system '%s'" % [law.id, inst["dissolution_rule"], system_id])
	if inst.has("formation_method") and not system.allowed_formation_methods.has(inst["formation_method"]):
		errors.append("laws: %s effects.institutional.formation_method '%s' is not permitted by system '%s'" % [law.id, inst["formation_method"], system_id])
	if inst.has("amendment_rule") and not system.allowed_amendment_rules.has(inst["amendment_rule"]):
		errors.append("laws: %s effects.institutional.amendment_rule '%s' is not permitted by system '%s'" % [law.id, inst["amendment_rule"], system_id])
	if inst.has("term_limit") and int(inst["term_limit"]) > 0 and not system.permits_term_limit:
		errors.append("laws: %s effects.institutional.term_limit %d is set but system '%s' does not permit a term limit" % [law.id, int(inst["term_limit"]), system_id])
	if inst.has("head_of_state"):
		var hos: Dictionary = inst["head_of_state"]
		if hos.has("kind") and not system.allowed_head_of_state_kinds.has(hos["kind"]):
			errors.append("laws: %s effects.institutional.head_of_state.kind '%s' is not permitted by system '%s'" % [law.id, hos["kind"], system_id])


## The cross-file half of a scenario's validation -- everything that needs the
## nation's own roster rather than just the scenario file. Fails loudly at
## startup for the same reason a bad nation file does: a scenario is authored
## content, and a scenario naming a party that does not exist would silently
## override nothing. See docs/scenario-model.md.
func _validate_scenarios() -> void:
	for id in scenarios.keys():
		var s: Scenario = scenarios[id]

		if not nations.has(s.nation_id):
			errors.append("%s.json: nation '%s' is not a loaded nation" % [id, s.nation_id])
			continue

		# Playable, not merely loaded. A scenario is offered from the nation-select
		# surface, which lists playable nations only -- one authored against an
		# unplayable nation is content nothing can ever reach.
		var n = nations[s.nation_id]
		if not n.playable:
			errors.append("%s.json: nation '%s' is not playable, so this scenario can never be selected" % [id, s.nation_id])

		var roster: Array = parties.get(s.nation_id, [])
		if not s.seat_share.is_empty():
			# Merged over the nation's authored shares, then summed -- the same
			# invariant _load_parties() holds the party file to, checked against
			# what the scenario ACTUALLY produces rather than against the override
			# fragment, which is not required to sum to anything on its own.
			var merged := {}
			for party in roster:
				merged[party.id] = party.seat_share
			for party_id in s.seat_share.keys():
				if not merged.has(party_id):
					errors.append("%s.json: overrides.seat_share names '%s', which is not a party in data/parties/%s.json" % [id, party_id, s.nation_id])
					continue
				merged[party_id] = s.seat_share[party_id]

			var total := 0.0
			for share in merged.values():
				total += float(share)
			if absf(total - 1.0) > 0.001:
				errors.append("%s.json: overrides.seat_share leaves the roster summing to %s, expected 1.0" % [id, str(total)])

		for bloc in s.bloc_approval.keys():
			if not OpinionK.BLOC_KEYS.has(bloc):
				errors.append("%s.json: overrides.bloc_approval names '%s', which is not a voter bloc" % [id, bloc])


## Reads one GeoJSON FeatureCollection into `into`, and every feature's label
## anchor into the shared label_points. Parameterised at U5b so europe.geojson
## and world.geojson go through exactly the same parser and the same error
## handling -- a malformed world file is an errors.append(), not a crash, the
## same as a malformed roster file has always been.
func _load_geo(geo_path: String, into: Dictionary) -> Array:
	var ids: Array = []
	into.clear()
	var text := FileAccess.get_file_as_string(geo_path)
	if text.is_empty():
		errors.append("%s: could not read file" % geo_path)
		return ids

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("features"):
		errors.append("%s: invalid GeoJSON" % geo_path)
		return ids

	for feature in parsed["features"]:
		var props: Dictionary = feature.get("properties", {})
		var id: String = props["id"]
		ids.append(id)

		if props.has("label_lon") and props.has("label_lat"):
			label_points[id] = Vector2(float(props["label_lon"]), float(props["label_lat"]))

		var geometry: Dictionary = feature.get("geometry", {})
		var polygons: Array = []
		match geometry.get("type", ""):
			"MultiPolygon":
				for polygon_coords in geometry.get("coordinates", []):
					polygons.append(_outer_ring(polygon_coords))
			"Polygon":
				polygons.append(_outer_ring(geometry.get("coordinates", [])))
			_:
				errors.append("%s: feature '%s' has unsupported geometry type '%s'" % [geo_path, id, geometry.get("type", "")])
		into[id] = polygons
	return ids


## The first ring of a Polygon's coordinate array is the outer boundary; any
## further rings are holes, which S8's renderer and hit-test both ignore.
func _outer_ring(polygon_coords: Array) -> PackedVector2Array:
	var ring := PackedVector2Array()
	if polygon_coords.is_empty():
		return ring
	for point in polygon_coords[0]:
		ring.append(Vector2(point[0], point[1]))
	return ring
