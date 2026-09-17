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
const Region = preload("res://src/core/region.gd")
const Outlet = preload("res://src/core/outlet.gd")
const CompanyAction = preload("res://src/core/company_action.gd")
const InvestmentAction = preload("res://src/core/investment_action.gd")
const ProjectAction = preload("res://src/core/project_action.gd")
const EnergySource = preload("res://src/core/energy_source.gd")
const EnergyAction = preload("res://src/core/energy_action.gd")
const EnergyK = preload("res://src/sim/energy_constants.gd")
const CampaignAction = preload("res://src/core/campaign_action.gd")
const PledgeAction = preload("res://src/core/pledge_action.gd")
const GameEvent = preload("res://src/core/event.gd")
const Summit = preload("res://src/core/summit.gd")
const C = preload("res://src/sim/economy_constants.gd")
const K = preload("res://src/sim/election_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")

const MIN_PARTIES := 4
const MAX_PARTIES := 6

const Org = preload("res://src/core/org.gd")
const OrgK = preload("res://src/core/org_constants.gd")

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

## nation id -> Array[Region], in authored order, which the importer writes
## descending by population -- V2.2a. UNLIKE `companies` and `outlets`, a nation
## may NOT be absent: this is the partition docs/tiers/v2.md section 5 makes the
## economic spine, so a nation with no regions is a nation the rest of this tier
## cannot describe rather than one running an older model.
##
## Region ids are NUTS codes, globally unique across Europe, and city ids are that
## code plus a slug -- so unlike a party id and like a person id, both are safe to
## read bare off a firm's `city`.
var regions: Dictionary = {}

## nation id -> Array[Outlet], in authored file order. Absent for the same reason
## `companies` may be absent, and with a stronger consequence: a nation with no
## data/outlets/<ID>.json has NO press, so media.gd's per-bloc deviation is exactly
## 0.0 for every bloc and its salience gain is exactly opinion_constants.SALIENCE_GAIN
## forever -- the model all ten nations ran before V1.5d. tests/test_media.gd asserts
## that with exact equality rather than is_zero_approx.
var outlets: Dictionary = {}

## Ordered, not keyed by id, the same way `laws` and `diplomatic_actions` are:
## the companies panel offers them as a list in authored order and nothing looks
## one up by id at runtime.
var company_actions: Array[CompanyAction] = []

## V1.6e's verbs. Ordered, not keyed by id, for company_actions' reason -- the
## companies panel offers them as a list in authored order and nothing looks one up
## by id at runtime. UNLIKE `companies` this is not per nation: an investment action
## names one of the three sectors economy_constants.SECTOR_TREND fixes for every
## nation, so there is nothing here a roster could differ over.
var investment_actions: Array[InvestmentAction] = []

## V2.8. id -> EnergySource. A global flat catalogue, not per-nation: see
## data/energy-sources.json's own note about why U6c's objection does not apply.
var energy_sources: Dictionary = {}

## V2.8's verbs, on the ninth effect channel. Ordered, not keyed by id, for
## project_actions' reason.
var energy_actions: Array[EnergyAction] = []

## V1.6f's verbs. Ordered, not keyed by id, for investment_actions' reason. Global
## rather than per nation for the reason data/project-actions/projects.json's own note
## gives: no project names a place, because per-project geography is the U-track half
## this session split off, so there is nothing here a roster could differ over yet.
var project_actions: Array[ProjectAction] = []

## V1.7a's verbs. Ordered, not keyed by id, for project_actions' reason. Global
## rather than per nation for the reason data/campaign-actions/campaign.json's own
## note gives: an effort names no place and no institution, so none of the five is
## true of France in a way it is not true of Germany.
var campaign_actions: Array[CampaignAction] = []

## V1.7b. The sixth directory on data/diplomatic-actions/'s shape. A global flat list
## for data/campaign-actions/'s reason -- a promise names no place and no institution.
var pledges: Array[PledgeAction] = []

## V4.1. The programme ladder, on the pledges shape but as raw validated Dictionaries
## rather than a core class: an entry is a trigger table and four effect slots, and
## src/sim/programme.gd casts on every read. Global rather than per nation for
## data/programme/economy.json's own reason -- a programme is chosen by the player's
## nation and names no place, so there is nothing here a roster could differ over.
var programme: Array = []

## V1.8's occasions. The SEVENTH directory on data/diplomatic-actions/'s shape, and the
## last content type the V1 tier adds. Ordered rather than keyed, and the order is
## load-bearing here in a way it is not for the six above: Events._next_event() takes
## the FIRST event whose gate is open this month, so authored order is the tiebreak
## between two crises drawn in the same month.
##
## Global rather than per nation, and unlike data/companies/ and data/outlets/ that is
## not a coverage decision deferred to a later session: an event names no place, no firm
## and no institution, and its subject is an OFFICE every one of the ten fills. See
## src/core/event.gd.
var events: Array[GameEvent] = []

## Summit scenes, V2.4b. Keyed by partner nation id, each value the pool of
## Summit scenes a meeting there can draw. A nation with no pool draws nothing
## at its arrivals -- a meeting without a scene is the ordinary state visit,
## not an error. Loaded from data/summits/ (see _load_summits).
var summits := {}

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

## The supranational organisations, V3.2 -- data/orgs/*.json. Sorted by id so
## anything that iterates the register is reproducible; orgs_by_id is the
## lookup the validators and Orgs.net_positions() read. Membership on these
## objects is the authored START; the live truth is NationState.orgs, which an
## accession or a withdrawal rewrites months into a run.
var orgs: Array[Org] = []
var orgs_by_id: Dictionary = {}

## Per-ORG proposal agendas, org_id -> Array[BlocProposal] in the same flat-file
## order bloc_proposals holds -- file order inside an org is its agenda order,
## and preserving it is part of what the track-(a) bit-identity run proves.
var org_proposals: Dictionary = {}

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

## NUTS id -> Array[PackedVector2Array], the same shape as geo_features, from
## data/geo/regions.geojson -- V2.2b. Keyed by the region's own NUTS code, which
## is Region.id, so map_view.gd joins the register to its geometry with a
## dictionary read and holds no nation-to-region mapping of its own. Holes are
## not kept, on geo_features' rule; the one place holes were load-bearing --
## placing each city inside its region -- was settled at import time and is
## re-checked by a test with its own hole-aware cast, not by the renderer.
var region_features: Dictionary = {}

## region id -> every polygon's EVERY ring, holes included -- V2.7. The renderer
## wants outer rings only, which is why region_features above stays that shape; the
## point-in-polygon that files a project's authored coordinate under a region needs
## the holes, because Berlin's site lives inside Brandenburg's outer ring and only
## the hole ring says whose it is. Written by the same _load_geo pass over the same
## file, so the two can never describe different rosters.
var region_rings: Dictionary = {}

## data/geo/region_graph.json -- V2.7. The transport graph as content: `edges` is
## [a, b, km, kind] with a < b, `endowment` is region id -> motorway density over the
## roster mean. Loaded rather than left on disk (V2.2a's own call for the geometry,
## flipped at V2.2b for the same reason): src/sim/network.gd reads it every tick.
##
## A DICTIONARY AND NOT A TYPE. There is no src/core/region_graph.gd, for the reason
## U6b deleted src/core/people.gd before writing it and V2.5 kept the register an
## Array: the one reader takes it as DATA, U6a's Calendar.due() shape, and a type
## here would be a second record of a file that already states its own shape.
var region_graph: Dictionary = {}

## Feature id -> Vector2(lon, lat), Natural Earth's own hand-placed label anchor.
## Both files contribute; map_view.gd draws labels for the roster only.
var label_points: Dictionary = {}


func load_all(nations_dir := "res://data/nations", geo_path := "res://data/geo/europe.geojson", parties_dir := "res://data/parties", laws_dir := "res://data/laws", political_systems_dir := "res://data/political-systems", scenarios_dir := "res://data/scenarios", diplomatic_actions_dir := "res://data/diplomatic-actions", world_path := "res://data/geo/world.geojson", bloc_proposals_dir := "res://data/bloc-proposals", people_dir := "res://data/people", companies_dir := "res://data/companies", company_actions_dir := "res://data/company-actions", outlets_dir := "res://data/outlets", investment_actions_dir := "res://data/investment-actions", project_actions_dir := "res://data/project-actions", campaign_actions_dir := "res://data/campaign-actions", pledges_dir := "res://data/pledges", events_dir := "res://data/events", regions_dir := "res://data/regions", regions_geo_path := "res://data/geo/regions.geojson", regions_graph_path := "res://data/geo/region_graph.json", summits_dir := "res://data/summits", energy_sources_path := "res://data/energy-sources.json", energy_actions_dir := "res://data/energy-actions", orgs_dir := "res://data/orgs", programme_dir := "res://data/programme") -> void:
	nations.clear()
	parties.clear()
	people.clear()
	person_by_id.clear()
	companies.clear()
	regions.clear()
	region_graph.clear()
	region_rings.clear()
	outlets.clear()
	company_actions.clear()
	investment_actions.clear()
	project_actions.clear()
	energy_sources.clear()
	energy_actions.clear()
	campaign_actions.clear()
	events.clear()
	summits.clear()
	pledges.clear()
	programme.clear()
	laws.clear()
	political_systems.clear()
	scenarios.clear()
	diplomatic_actions.clear()
	bloc_proposals.clear()
	orgs.clear()
	orgs_by_id.clear()
	org_proposals.clear()
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
	for id in nations.keys():
		_load_outlets(id, outlets_dir)
	for id in nations.keys():
		_load_regions(id, regions_dir)

	_load_company_actions(company_actions_dir)
	_load_investment_actions(investment_actions_dir)
	_load_projects(project_actions_dir)
	_load_energy_sources(energy_sources_path)
	_load_energy_actions(energy_actions_dir)
	_load_campaign_actions(campaign_actions_dir)
	_load_events(events_dir)
	_load_summits(summits_dir)
	_load_pledges(pledges_dir)
	_load_programme(programme_dir)
	_load_laws(laws_dir)
	_load_political_systems(political_systems_dir)
	_load_scenarios(scenarios_dir)
	_load_diplomatic_actions(diplomatic_actions_dir)
	# Orgs before proposals: a proposal names its org, and a reference cannot be
	# validated against a register that has not been filled yet.
	_load_orgs(orgs_dir)
	_load_bloc_proposals(bloc_proposals_dir)

	_validate_cross_file(geo_path, world_path)
	_validate_amendments()
	_validate_scenarios()
	_validate_neighbours()
	_validate_bloc_proposals()
	_validate_people()
	_validate_companies()
	_validate_outlets(outlets_dir)
	_validate_regions(regions_dir, regions_geo_path, regions_graph_path)
	_validate_energy_sources()


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

	# The programme register's ids, for want resolution. Built once here rather
	# than per person: 37 entries against ~1600 people, and a linear scan per
	# want would be 1600 scans of the thing a Dictionary answers once.
	var programme_ids := {}
	for entry in programme:
		programme_ids[String(entry["id"])] = true

	for nation_id in people.keys():
		var party_ids := {}
		for party in parties.get(nation_id, []):
			party_ids[party.id] = true

		for person in people[nation_id]:
			# A bench politician's affiliation is authored on them because no
			# slot points at it; it must resolve in THIS nation's list, the
			# same inside-one-nation's-context rule party ids always follow.
			if person.party_id != "" and not party_ids.has(person.party_id):
				errors.append(
					"people/%s.json: person '%s' claims party '%s', which is not one of this nation's parties"
					% [nation_id, person.id, person.party_id]
				)
			for want in person.wants:
				_resolve_want(want, nation_id, person.id, party_ids, programme_ids)

			if referenced.has(person.id):
				continue
			if person.kind != "politician" or person.party_id != "":
				continue
			errors.append(
				"people/%s.json: person '%s' (%s) is referenced by nothing"
				% [nation_id, person.id, person.person_name]
			)


## The cross-register half of want validation. Shape, stance and threshold
## coherence were checked at parse (person.gd, against character_constants);
## what remains is that the object NAMES something real: a programme entry
## that exists, a portfolio the cabinet knows, a party of this person's own
## nation. An unresolvable want is a load error naming the person, not an
## inert want quietly never satisfied.
func _resolve_want(want: Dictionary, nation_id: String, person_id: String, party_ids: Dictionary, programme_ids: Dictionary) -> void:
	var object := String(want["object"])
	var rest := object.substr(object.find(":") + 1)

	if object.begins_with("programme:"):
		if not programme_ids.has(rest):
			errors.append(
				"people/%s.json: person '%s' wants programme entry '%s', which is not in the register"
				% [nation_id, person_id, rest]
			)
		return

	if object.begins_with("office:"):
		if rest == "premiership":
			# Every nation has exactly one; nothing to resolve against.
			return
		if rest.begins_with("portfolio:"):
			var key := rest.substr("portfolio:".length())
			if not CharacterK.PORTFOLIO_KEYS.has(key):
				errors.append(
					"people/%s.json: person '%s' wants portfolio '%s', which is not one of the cabinet's (%s)"
					% [nation_id, person_id, key, str(CharacterK.PORTFOLIO_KEYS)]
				)
			return
		if rest.begins_with("party_leadership:"):
			var pid := rest.substr("party_leadership:".length())
			if not party_ids.has(pid):
				errors.append(
					"people/%s.json: person '%s' wants the leadership of '%s', which is not a party of this nation"
					% [nation_id, person_id, pid]
				)
			return
		errors.append(
			"people/%s.json: person '%s' wants office '%s', which is not premiership, a portfolio or a party leadership"
			% [nation_id, person_id, rest]
		)
		return

	# meter:<key> resolved against METER_KEYS at parse; nothing further here.


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


## One data/regions/<NATION>.json per nation, {"regions": [...]}, on
## data/companies/*.json's per-nation shape -- V2.2a. See docs/geography-model.md.
##
## AN ABSENT FILE *IS* AN ERROR, and that is the one place this register departs from
## the two it copies. A nation with no companies has unpartitioned sectors and a nation
## with no outlets has no press, and both are models the roster ran before V1.4a and
## V1.5d respectively -- so an absent file there is a coverage decision a later session
## may take. There is no such prior model here: docs/tiers/v2.md section 5 makes
## national = sum of regions the economic spine, so a nation with no regions is one the
## rest of this tier cannot describe at all.
func _load_regions(nation_id: String, regions_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := regions_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		errors.append("regions/%s: could not read file" % fname)
		regions[nation_id] = []
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("regions")) != TYPE_ARRAY:
		errors.append("regions/%s: invalid regions file, expected {\"regions\": [...]}" % fname)
		regions[nation_id] = []
		return

	var raw_list: Array = parsed["regions"]
	var parsed_regions: Array = []
	var per_file_errors: Array[String] = []
	var seen_ids := {}

	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			per_file_errors.append("regions/%s: regions[%d] is not an object" % [fname, i])
			continue
		var region = Region.from_dict(entry, i, "regions/" + fname, per_file_errors)
		if region.id == "":
			continue
		if seen_ids.has(region.id):
			per_file_errors.append("regions/%s: duplicate region id '%s'" % [fname, region.id])
		seen_ids[region.id] = true
		parsed_regions.append(region)

	errors.append_array(per_file_errors)
	regions[nation_id] = parsed_regions


## The cross-file half, and every one of these three checks exists because the raw
## data broke it during the session that wrote them.
##
## The national partition: named regions summing past 1.0 claim more of the country
## than there is. The Eurostat response carries TWO NUTS VINTAGES AT ONCE -- `NL35`
## and `NL36` are the 2024 codes for Utrecht and Zuid-Holland and `NL31`/`NL33` the
## 2021 ones, equal to the person -- so a Netherlands built without filtering to the
## geometry's own roster is 5.1 M people too large.
##
## The domicile: a firm's `city` naming a place the register does not hold is
## docs/tiers/v2.md section 2's own claim -- *"a city's employment is already written
## in data/companies/"* -- failing silently, and it is the ONLY thing making that field
## load-bearing before V2.2b draws it. U6c's rule about a coordinate nothing reads.
##
## The orphan file: _validate_outlets()' scan, for its reason. A per-nation lookup
## structurally cannot see data/regions/FRE.json, because that file is simply never
## opened -- which is tools/check_names.sh's zero-files-scanned burn in a new place.
##
## The geometry: every register region must have a polygon, because the register is
## the set of NUTS codes carrying BOTH a figure and a GISCO polygon -- that single
## rule is what resolved extra-regio, the two Dutch vintages and the overseas
## regions, so a region with figures and no geometry is an import that has drifted
## from its own authority. V2.2a shipped the file unopened (nothing drew it, so a
## launch should not pay 180 KB for it); V2.2b draws it, and this is where the
## load happens -- _validate_cross_file's precedent, the load and the check it
## exists for arriving together.
func _validate_regions(regions_dir: String, regions_geo_path: String, regions_graph_path: String) -> void:
	var city_ids := {}
	for nation_id in regions.keys():
		var total := 0.0
		var gdp_total := 0.0
		for region in regions[nation_id]:
			total += region.share
			gdp_total += region.gdp_share
			for city in region.cities:
				if city_ids.has(city.id):
					errors.append(
						"regions/%s.json: city id '%s' is already used by %s -- a city id is read bare off a firm's `city` and has to be globally unique"
						% [nation_id, city.id, city_ids[city.id]]
					)
				city_ids[city.id] = nation_id
		if total > 1.0 + 0.000001:
			errors.append(
				"regions/%s.json: region shares sum to %s, above 1.0 -- the named regions would hold more people than the nation does"
				% [nation_id, str(total)]
			)
		if gdp_total > 1.0 + 0.000001:
			errors.append(
				"regions/%s.json: region GDP shares sum to %s, above 1.0 -- the named regions would produce more than the nation does"
				% [nation_id, str(gdp_total)]
			)

	for nation_id in companies.keys():
		for company in companies[nation_id]:
			if company.city == "":
				continue
			if not city_ids.has(company.city):
				errors.append(
					"companies/%s.json: firm '%s' is domiciled in '%s', which is not a city in data/regions/"
					% [nation_id, company.id, company.city]
				)
			elif city_ids[company.city] != nation_id:
				errors.append(
					"companies/%s.json: firm '%s' is domiciled in '%s', which is a city of %s"
					% [nation_id, company.id, company.city, city_ids[company.city]]
				)

	_load_geo(regions_geo_path, region_features, true, region_rings)
	_load_region_graph(regions_graph_path)
	for nation_id in regions.keys():
		for region in regions[nation_id]:
			if not region_features.has(region.id):
				errors.append(
					"regions/%s.json: region '%s' has no polygon in %s -- the geometry is the authority on the roster, and a region that cannot be drawn is one the register cannot hold"
					% [nation_id, region.id, regions_geo_path]
				)

	# FIFTH RULE, V2.7. Every graph id is a register id and every register id has an
	# endowment. V2.2b's fourth rule cross-checks the register against the GEOMETRY at
	# load time; this is the same check against the GRAPH, and it is what catches an
	# importer run that wrote one file and not the other -- the two are generated
	# together and can only disagree by a partial run.
	if not region_graph.is_empty():
		var endowment: Dictionary = region_graph.get("endowment", {})
		for nation_id in regions.keys():
			for region in regions[nation_id]:
				if not endowment.has(region.id):
					errors.append("regions/%s.json: region '%s' has no entry in data/geo/region_graph.json -- re-run tools/import_data.py" % [nation_id, region.id])
		for region_id in endowment.keys():
			var known := false
			for nation_id in regions.keys():
				for region in regions[nation_id]:
					if region.id == region_id:
						known = true
						break
			if not known:
				errors.append("geo/region_graph.json: names region '%s', which no data/regions/ file carries" % region_id)

	var da := DirAccess.open(regions_dir)
	if da == null:
		errors.append("%s: directory not found" % regions_dir)
		return
	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if not da.current_is_dir() and file_name.ends_with(".json"):
			var nation_id := file_name.get_basename()
			if not nations.has(nation_id):
				errors.append(
					"regions/%s: no nation with id '%s' -- the file is never opened"
					% [file_name, nation_id]
				)
		file_name = da.get_next()
	da.list_dir_end()


## The graph, refused loudly rather than defaulted. An absent file is an error and not
## an empty graph: a nation whose regions cannot reach each other has every
## accessibility read collapse to its own output, which is a different model running
## silently -- data/regions/'s own rule ("there is no prior model in which a nation
## has no places") one file over.
func _load_region_graph(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		errors.append("geo/region_graph.json: could not read file")
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		errors.append("geo/region_graph.json: expected an object")
		return
	var raw_edges = (parsed as Dictionary).get("edges", null)
	var raw_endowment = (parsed as Dictionary).get("endowment", null)
	if typeof(raw_edges) != TYPE_ARRAY or typeof(raw_endowment) != TYPE_DICTIONARY:
		errors.append("geo/region_graph.json: expected 'edges' array and 'endowment' object")
		return
	var edges: Array = []
	for i in (raw_edges as Array).size():
		var entry = raw_edges[i]
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 4:
			errors.append("geo/region_graph.json: edges[%d] is not [a, b, km, kind]" % i)
			continue
		edges.append([String(entry[0]), String(entry[1]), float(entry[2]), String(entry[3])])
	var endowment: Dictionary = {}
	for key in (raw_endowment as Dictionary).keys():
		endowment[String(key)] = float(raw_endowment[key])
	region_graph = {"edges": edges, "endowment": endowment}


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
func _load_outlets(nation_id: String, outlets_dir: String) -> void:
	var fname := "%s.json" % nation_id
	var path := outlets_dir.path_join(fname)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		outlets[nation_id] = []
		return

	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("outlets")) != TYPE_ARRAY:
		errors.append("%s: invalid outlets file, expected {\"outlets\": [...]}" % fname)
		outlets[nation_id] = []
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

	errors.append_array(per_file_errors)
	outlets[nation_id] = parsed_outlets


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
func _validate_outlets(outlets_dir: String) -> void:
	for nation_id in outlets.keys():
		var by_audience := {}
		for outlet in outlets[nation_id]:
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
				errors.append(
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
			if not nations.has(id):
				errors.append(
					"outlets/%s: no nation '%s' exists -- this file is never read, so its outlets are content nothing can reach"
					% [file_name, id]
				)
		file_name = da.get_next()
	da.list_dir_end()


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


## V1.6e. _load_company_actions()'s shape, and deliberately a separate directory
## rather than a fourth op on the company channel: a subsidy is pointed at a firm
## inside a sector and this is pointed at the sector, which is exactly the
## distinction docs/companies-model.md section 12 says no validator can enforce
## from inside one content type.
func _load_investment_actions(actions_dir: String) -> void:
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
			errors.append("%s: invalid investment-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = InvestmentAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					errors.append("%s: duplicate investment action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true
			investment_actions.append(action)



## V1.6f. _load_investment_actions()'s shape, and deliberately a separate directory
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
func _load_projects(actions_dir: String) -> void:
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
	var defined := {}   # project_id -> the filename that defined it
	var referenced := {}  # project_id -> the action id that abandons it
	for fname in filenames:
		var path := actions_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("actions")) != TYPE_ARRAY:
			errors.append("%s: invalid project-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = ProjectAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					errors.append("%s: duplicate project action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true

			var pid := ProjectAction.project_id(action)
			if pid != "":
				match ProjectAction.op_of(action):
					"start":
						if defined.has(pid):
							errors.append("%s: project '%s' is defined twice (also in %s) -- its duration, price and payoff would depend on which entry loaded last" % [
								fname, pid, str(defined[pid])
							])
						defined[pid] = fname
					"abandon":
						referenced[pid] = action.id
			project_actions.append(action)

	for pid in referenced.keys():
		if not defined.has(pid):
			errors.append("%s: '%s' abandons project '%s', which no action starts" % [
				actions_dir, str(referenced[pid]), str(pid)
			])


## V1.7a. _load_projects()'s shape, and deliberately a separate directory rather than
## a third op on the project channel: a project is a discrete dated commitment pointed
## at a named thing and a campaign effort is a standing rate pointed at a slice of the
## electorate, which is the distinction docs/tiers/v1.md section 7 exists for.
##
## THE CROSS-FILE CHECK IS THE HALF WORTH HAVING. Per-entry validation lives in
## src/core/campaign_action.gd; what only this function can see is whether the file is
## CONSISTENT -- that no two entries define the same effort, and that every stop names
## an effort some start actually defines. A stop pointing at nothing loads as a button
## that is never available, which is a content bug that renders as an absence and would
## be found by a player rather than by a check. _load_projects()'s own split, inherited.
## data/energy-sources.json, ONE file and global. Per-entry validation lives in
## src/core/energy_source.gd; what only this function can see is that the file
## parsed at all and that no two entries share an id -- the register is keyed by id,
## so a duplicate would be one technology silently overwriting another.
func _load_energy_sources(path: String) -> void:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		errors.append("data/energy-sources.json: could not read file")
		return
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY or typeof((parsed as Dictionary).get("sources")) != TYPE_ARRAY:
		errors.append("data/energy-sources.json: expected {\"sources\": [...]}")
		return

	var raw_list: Array = (parsed as Dictionary)["sources"]
	for i in raw_list.size():
		var entry = raw_list[i]
		if typeof(entry) != TYPE_DICTIONARY:
			errors.append("data/energy-sources.json: sources[%d] is not an object" % i)
			continue
		var per_file_errors: Array[String] = []
		var source = EnergySource.from_dict(entry, "data/energy-sources.json", per_file_errors)
		errors.append_array(per_file_errors)
		if source.id != "":
			if energy_sources.has(source.id):
				errors.append("data/energy-sources.json: duplicate source id '%s'" % source.id)
			energy_sources[source.id] = source


## Every branch the import measured must be BUILDABLE, and every branch a source
## names must have been measured. The first half is what stops a mix key with no
## verb behind it -- a player who can never build renewables in a country that is
## 80 % renewable has a readout and not a lever. The second half is the partition.
func _validate_energy_sources() -> void:
	if energy_sources.is_empty():
		errors.append("data/energy-sources.json defines no sources")
		return
	var covered: Dictionary = {}
	for source in energy_sources.values():
		covered[source.branch] = true
		# from_dict() parses a missing emission_t_per_twh to a -1.0 sentinel, so this
		# one check refuses both an absent key and an authored negative. Absence must
		# fail loudly: 0.0 tonnes per TWh on a gas station is a confident lie the
		# emissions read would print for years.
		if source.emission_t_per_twh < 0.0:
			errors.append("energy source '%s' is missing emission_t_per_twh -- the key must exist for every source and be non-negative" % source.id)
	for branch in EnergyK.BRANCHES:
		if not covered.has(branch):
			errors.append("no energy source builds branch '%s' -- every measured branch needs a verb" % branch)
	for nation_id in nations.keys():
		var n = nations[nation_id]
		for branch in n.energy_mix.keys():
			if not EnergyK.BRANCHES.has(String(branch)):
				errors.append("%s: imported.energy.mix names branch '%s', which is not in BRANCHES" % [nation_id, branch])


## data/energy-actions/*.json, _load_projects()'s shape. Per-entry validation lives
## in src/core/energy_action.gd; what only this function can see is duplicate ids --
## two actions with one id would be two buttons the registry cannot tell apart.
func _load_energy_actions(actions_dir: String) -> void:
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
			errors.append("%s: invalid energy-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = EnergyAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					errors.append("%s: duplicate energy action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true
				energy_actions.append(action)


func _load_campaign_actions(actions_dir: String) -> void:
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
	var defined := {}     # effort_id -> the filename that defined it
	var referenced := {}  # effort_id -> the action id that stops it
	for fname in filenames:
		var path := actions_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("actions")) != TYPE_ARRAY:
			errors.append("%s: invalid campaign-action file, expected {\"actions\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["actions"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: actions[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = CampaignAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					errors.append("%s: duplicate campaign action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true

			var eid := CampaignAction.effort_id(action)
			if eid != "":
				match CampaignAction.op_of(action):
					"start":
						if defined.has(eid):
							errors.append("%s: effort '%s' is defined twice (also in %s) -- its price and its reach would depend on which entry loaded last" % [
								fname, eid, str(defined[eid])
							])
						defined[eid] = fname
					"stop":
						referenced[eid] = action.id
			campaign_actions.append(action)

	for eid in referenced.keys():
		if not defined.has(eid):
			errors.append("%s: '%s' stops effort '%s', which no action starts" % [
				actions_dir, str(referenced[eid]), str(eid)
			])


## V1.7b's promises, from data/pledges/. _load_campaign_actions()'s shape.
##
## THE CROSS-FILE CHECK IS THE HALF WORTH HAVING, and here it is a different check
## from that one. A campaign effort needs a stop for every start; a pledge has no
## second op at all -- see src/sim/pledges_constants.gd's PLEDGE_TERMS -- so what only
## this function can see is that no two entries define the same `pledge_id`. The
## register is keyed on it and Pledges.has_pledged() refuses a duplicate, so two
## entries sharing one id would be two promises the player could only ever make one
## of, chosen by whichever file loaded last.
func _load_pledges(pledges_dir: String) -> void:
	var da := DirAccess.open(pledges_dir)
	if da == null:
		errors.append("%s: directory not found" % pledges_dir)
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
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("pledges")) != TYPE_ARRAY:
			errors.append("%s: invalid pledge file, expected {\"pledges\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["pledges"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: pledges[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var action = PledgeAction.from_dict(entry, fname, per_file_errors, OpinionK.BLOC_KEYS)
			errors.append_array(per_file_errors)
			if action.id != "":
				if seen_ids.has(action.id):
					errors.append("%s: duplicate pledge action id '%s'" % [fname, action.id])
				seen_ids[action.id] = true

			var pid := PledgeAction.pledge_id(action)
			if pid != "":
				if defined.has(pid):
					errors.append("%s: pledge '%s' is defined twice (also in %s) -- the register is keyed on it, so the player could only ever make one of them" % [
						fname, pid, str(defined[pid])
					])
				defined[pid] = fname
			pledges.append(action)


## Reads every data/programme/*.json file -- {"programme": [...]}, the directory-scan
## shape _load_pledges uses. Entries are kept as raw validated Dictionaries: the
## extraction below is the validation, and src/sim/programme.gd casts on every read.
##
## THE LOUD REFUSALS, on the summits' sidecar contract's reasoning:
##   - an entry carrying a field outside ProgrammeK.ENTRY_FIELDS is a load error,
##     because a typo'd field must never be an inert half of an entry nobody reads;
##   - every effect slot (`immediate`, `on_complete`, `on_fail`, `on_invalid`,
##     `on_timeout`) is priced only on the SHARED channels, extracted through
##     Law.extract_shared_effects -- the one applier events already use, not a
##     second. `institutional` is deliberately absent: a programme is not an
##     amendment, and a conclusion that rewrote the constitution as a side effect
##     of missing a deficit target is not a thing this schema may express;
##   - an entry with NO trigger and NO deadline is refused, because an entry that
##     could never conclude would tick forever.
func _load_programme(programme_dir: String) -> void:
	var da := DirAccess.open(programme_dir)
	if da == null:
		errors.append("%s: directory not found" % programme_dir)
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
		var path := programme_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("programme")) != TYPE_ARRAY:
			errors.append("%s: invalid programme file, expected {\"programme\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["programme"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: programme[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var terms := _extract_programme_entry(entry, fname, per_file_errors)
			errors.append_array(per_file_errors)
			if terms.is_empty():
				continue
			if seen_ids.has(terms["id"]):
				errors.append("%s: duplicate programme entry id '%s' -- two entries sharing one id would be two programmes the player could only ever choose one of" % [fname, terms["id"]])
			seen_ids[terms["id"]] = true
			programme.append(terms)


func _extract_programme_entry(d: Dictionary, filename: String, errors: Array[String]) -> Dictionary:
	# The unknown-field refusal FIRST: an entry carrying anything beside the schema
	# does not get the courtesy of a partial load.
	for key in d.keys():
		if not ProgrammeK.ENTRY_FIELDS.has(String(key)):
			errors.append("%s: programme entry carries '%s', which is not a recognised field (%s)" % [
				filename, str(key), str(ProgrammeK.ENTRY_FIELDS)
			])

	# The other half of the whitelist, enforced: an entry missing a required
	# field is refused even where the per-field checks below could default it.
	# Each of these is validated in its own right further down; this loop is
	# what makes ABSENCE itself the load error REQUIRED_FIELDS promises.
	for key in ProgrammeK.REQUIRED_FIELDS:
		if not d.has(key):
			errors.append("%s: programme entry '%s' is missing required field '%s' (%s)" % [
				filename, str(d.get("id", "?")), str(key), str(ProgrammeK.REQUIRED_FIELDS)
			])

	var out := {}

	var id = d.get("id", "")
	if typeof(id) != TYPE_STRING or id == "":
		errors.append("%s: programme entry missing or invalid string field 'id'" % filename)
		return {}
	out["id"] = id

	var name = d.get("name", "")
	if typeof(name) != TYPE_STRING or name == "":
		errors.append("%s: %s missing or invalid string field 'name' -- the offer needs the noun" % [filename, id])
	else:
		out["name"] = name

	var summary = d.get("summary", "")
	if typeof(summary) != TYPE_STRING or String(summary).strip_edges() == "":
		errors.append("%s: %s summary must be a non-empty string -- the offer prints it under the name" % [filename, id])
	else:
		out["summary"] = summary

	var group = d.get("group", "")
	if typeof(group) != TYPE_STRING or not ProgrammeK.GROUPS.has(group):
		errors.append("%s: %s group '%s' is not one of the five (%s)" % [filename, id, str(group), str(ProgrammeK.GROUPS)])
	else:
		out["group"] = group

	var activation = d.get("activation", "")
	if typeof(activation) != TYPE_STRING or not ProgrammeK.ACTIVATIONS.has(activation):
		errors.append("%s: %s activation '%s' is not one of the four (%s)" % [filename, id, str(activation), str(ProgrammeK.ACTIVATIONS)])
	else:
		out["activation"] = activation

	var timeout = d.get("timeout_months", -1)
	if not (typeof(timeout) == TYPE_INT or typeof(timeout) == TYPE_FLOAT) or int(timeout) < 0:
		errors.append("%s: %s timeout_months must be a non-negative number -- 0 means no deadline, and an author who has not decided is an error rather than a default" % [filename, id])
	else:
		out["timeout_months"] = int(timeout)

	var current_value = d.get("current_value", "")
	if typeof(current_value) != TYPE_STRING or not ProgrammeK.TRIGGER_FIELDS.has(current_value):
		errors.append("%s: %s current_value '%s' is not a figure a trigger can read (%s)" % [filename, id, str(current_value), str(ProgrammeK.TRIGGER_FIELDS)])
	else:
		out["current_value"] = current_value

	if d.has("goal_value") and (typeof(d["goal_value"]) == TYPE_INT or typeof(d["goal_value"]) == TYPE_FLOAT):
		out["goal_value"] = float(d["goal_value"])
	else:
		errors.append("%s: %s goal_value is missing or not numeric" % [filename, id])

	var progressbar = d.get("progressbar", "")
	if typeof(progressbar) != TYPE_STRING or not ProgrammeK.PROGRESS_DIRECTIONS.has(progressbar):
		errors.append("%s: %s progressbar '%s' is not a direction (%s)" % [filename, id, str(progressbar), str(ProgrammeK.PROGRESS_DIRECTIONS)])
	else:
		out["progressbar"] = progressbar

	if d.has("weight"):
		if typeof(d["weight"]) == TYPE_INT or typeof(d["weight"]) == TYPE_FLOAT:
			out["weight"] = float(d["weight"])
		else:
			errors.append("%s: %s weight must be numeric" % [filename, id])
	if d.has("pinned"):
		if typeof(d["pinned"]) == TYPE_BOOL:
			out["pinned"] = d["pinned"]
		else:
			errors.append("%s: %s pinned must be a bool" % [filename, id])

	var raw_possible = d.get("possible", [])
	if typeof(raw_possible) != TYPE_ARRAY:
		errors.append("%s: %s possible must be an array of {field, op, value}" % [filename, id])
	else:
		var possible: Array = []
		for i in raw_possible.size():
			var trigger := _extract_programme_trigger(raw_possible[i], id, filename, "possible[%d]" % i, errors)
			if not trigger.is_empty():
				possible.append(trigger)
		if not possible.is_empty():
			out["possible"] = possible

	for key in ["complete", "fail", "invalid"]:
		if d.has(key):
			var trigger := _extract_programme_trigger(d[key], id, filename, key, errors)
			if not trigger.is_empty():
				out[key] = trigger

	for key in ["immediate", "on_complete", "on_fail", "on_invalid", "on_timeout"]:
		if d.has(key):
			var effects := _extract_programme_effects(d[key], id, filename, key, errors)
			if not effects.is_empty():
				out[key] = effects

	# An entry that could never conclude would tick forever, so it is a load error
	# and not an authoring choice. Any one trigger suffices; so does a deadline.
	if not out.has("complete") and not out.has("fail") and not out.has("invalid") \
			and int(out.get("timeout_months", 0)) <= 0:
		errors.append("%s: %s has no trigger and no deadline -- it could never conclude" % [filename, id])

	return out


func _extract_programme_trigger(raw, owner_id: String, filename: String, what: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s %s must be an object {field, op, value}" % [filename, owner_id, what])
		return {}

	var field = raw.get("field", "")
	if typeof(field) != TYPE_STRING or not ProgrammeK.TRIGGER_FIELDS.has(field):
		errors.append("%s: %s %s.field '%s' is not a recognised field (%s)" % [
			filename, owner_id, what, str(field), str(ProgrammeK.TRIGGER_FIELDS)
		])
		return {}

	var op = raw.get("op", "")
	if typeof(op) != TYPE_STRING or not ProgrammeK.TRIGGER_OPS.has(op):
		errors.append("%s: %s %s.op '%s' is not a recognised operator (%s)" % [
			filename, owner_id, what, str(op), str(ProgrammeK.TRIGGER_OPS)
		])
		return {}

	if not raw.has("value") or not (typeof(raw["value"]) == TYPE_INT or typeof(raw["value"]) == TYPE_FLOAT):
		errors.append("%s: %s %s.value is missing or not numeric" % [filename, owner_id, what])
		return {}

	return {"field": field, "op": op, "value": float(raw["value"])}


func _extract_programme_effects(raw, owner_id: String, filename: String, what: String, errors: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("%s: %s %s must be an object of effect channels" % [filename, owner_id, what])
		return {}

	# extract_shared_effects() extracts the channels it knows and says nothing about
	# the ones it does not, so the unknown-channel refusal is ours -- law.gd's
	# _extract_effects() does this half for laws, and there is no second applier to
	# inherit it from here.
	for key in raw.keys():
		if not Law.SHARED_EFFECT_CHANNELS.has(key) and not Law.SCALAR_EFFECT_KEYS.has(key):
			errors.append("%s: %s %s.%s is not a recognised effect channel -- a conclusion prices only on the channels laws and events already share" % [
				filename, owner_id, what, str(key)
			])

	return Law.extract_shared_effects(
		raw, owner_id, filename, errors, C.TAX_KEYS, C.SPENDING_KEYS, OpinionK.BLOC_KEYS, C.SECTOR_TREND.keys()
	)


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
func _load_orgs(orgs_dir: String) -> void:
	var da := DirAccess.open(orgs_dir)
	if da == null:
		errors.append("%s: directory not found" % orgs_dir)
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
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s: invalid JSON" % fname)
			continue

		var per_file_errors: Array[String] = []
		var org: Org = Org.from_dict(parsed, fname, per_file_errors)
		errors.append_array(per_file_errors)
		if org.id == "":
			continue
		if orgs_by_id.has(org.id):
			errors.append("%s: duplicate org id '%s'" % [fname, org.id])
			continue
		orgs.append(org)
		orgs_by_id[org.id] = org

	# Sorted by id, not by filename: the register's iteration order is a model
	# fact (every consumer iterates it sorted), not a side effect of file names.
	orgs.sort_custom(func(a, b): return a.id < b.id)

	# Every member must be on the roster: an org binding a nation that does not
	# exist is content that reads as a membership and is not one -- the same
	# class of quiet failure a scenario naming an unplayable nation is refused
	# for. Runs after nations load, which the call order in load_all() promises.
	for org in orgs:
		if orgs.size() > OrgK.MAX_ORGS:
			errors.append("orgs: %d orgs exceed the limit of %d" % [orgs.size(), OrgK.MAX_ORGS])
			break
		for member_id in org.members.keys():
			if not nations.has(member_id):
				errors.append("orgs: %s lists member '%s', which is not a loaded nation" % [org.id, member_id])

	# A council org must carry what a new member enters with: the flip writes
	# it as live seat state, and a joiner with no weight is a member whose vote
	# never counts -- the second-class-member failure, refused at load.
	for org in orgs:
		if org.council and org.accession_seats < 1:
			errors.append("orgs: %s holds a council but carries no accession_seats" % org.id)

	# At most one parliament, because Elections seeds the EP clock from "the org
	# that carries one" and two of them would make that phrase ambiguous.
	var parliament_count := 0
	for org in orgs:
		if not org.parliament.is_empty():
			parliament_count += 1
	if parliament_count > 1:
		errors.append("orgs: %d orgs carry a parliament; at most one may" % parliament_count)


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
			var proposal = BlocProposal.from_dict(entry, fname, per_file_errors, orgs_by_id.keys())
			errors.append_array(per_file_errors)
			if proposal.id != "":
				if seen_ids.has(proposal.id):
					errors.append("%s: duplicate bloc proposal id '%s'" % [fname, proposal.id])
				seen_ids[proposal.id] = true
			bloc_proposals.append(proposal)
			# The per-org agenda, in exactly the order the flat list collects --
			# file order IS the agenda, and the register must not be the one
			# place that reorders it.
			if not org_proposals.has(proposal.org_id):
				org_proposals[proposal.org_id] = []
			org_proposals[proposal.org_id].append(proposal)


## The cross-file half: a proposal names no nation, but two of its shapes only
## mean something against the roster it will run in.
##
## Runs after _load_orgs(), because both checks need that org's membership.
func _validate_bloc_proposals() -> void:
	for p in bloc_proposals:
		# The proposal's own org must exist and be populated -- a proposal on an
		# org nobody belongs to can never reach a council, and one on an org that
		# does not exist is a typo the register refuses loudly.
		var org: Org = orgs_by_id.get(p.org_id, null)
		if org == null:
			errors.append("bloc-proposals: %s names org '%s', which is not loaded" % [p.id, p.org_id])
			continue
		var member_count := 0
		var outsider_count := 0
		for id in nations.keys():
			if org.is_member(id):
				member_count += 1
			else:
				outsider_count += 1
		if member_count == 0:
			errors.append("bloc-proposals: %s is loaded, but no loaded nation is a member of org '%s'" % [p.id, org.id])
		# A collective external tariff with nobody outside the bloc to levy it on
		# is content that can never do anything -- the same class of quiet failure
		# a scenario naming an unplayable nation is refused for.
		if not p.external_measure.is_empty() and outsider_count == 0:
			errors.append("bloc-proposals: %s sets an external measure, but every loaded nation is a member of '%s'" % [p.id, org.id])


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
	# V3.3: the roster is EU-27 plus the two non-EU neighbours, so the pin the
	# ten-nation era carried moves to 29. A tripwire, not a limit -- a roster
	# change edits this number beside the data it describes.
	if nations.size() != 29:
		errors.append("expected 29 nations, loaded %d" % nations.size())

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
func _load_geo(geo_path: String, into: Dictionary, keep_rings := false, rings_into: Dictionary = {}) -> Array:
	var ids: Array = []
	into.clear()
	rings_into.clear()
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
		var full_polygons: Array = []
		match geometry.get("type", ""):
			"MultiPolygon":
				for polygon_coords in geometry.get("coordinates", []):
					polygons.append(_outer_ring(polygon_coords))
					if keep_rings:
						full_polygons.append(_all_rings(polygon_coords))
			"Polygon":
				polygons.append(_outer_ring(geometry.get("coordinates", [])))
				if keep_rings:
					full_polygons.append(_all_rings(geometry.get("coordinates", [])))
			_:
				errors.append("%s: feature '%s' has unsupported geometry type '%s'" % [geo_path, id, geometry.get("type", "")])
		into[id] = polygons
		if keep_rings:
			rings_into[id] = full_polygons
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


## Every ring of one polygon, outer first, holes after -- V2.7. Kept beside
## _outer_ring() because the pair states the rule twice on purpose: the renderer
## drops the holes and the siting cast needs them, and only reading this file once
## keeps the two from ever disagreeing about what the geometry says.
func _all_rings(polygon_coords: Array) -> Array:
	var rings: Array = []
	for ring_coords in polygon_coords:
		var ring := PackedVector2Array()
		for point in ring_coords:
			ring.append(Vector2(point[0], point[1]))
		rings.append(ring)
	return rings


## V1.8. _load_projects()'s shape, and the seventh directory to take it.
##
## THE CROSS-FILE CHECK IS THE HALF WORTH HAVING, and here it is a different half from
## every previous one. Per-entry validation lives in src/core/event.gd; what only this
## function can see is whether the SET is coherent -- that no two entries define the
## same event, and that no two events name the same subject office AND the same
## precondition field, which is the content-level shape of the same collision
## _validate_companies() refuses when a sector holds one named firm. Two scandals about
## the prime minister with identical gates are one event authored twice, and the second
## can only ever fire in the months the first did not.
func _load_events(events_dir: String) -> void:
	var da := DirAccess.open(events_dir)
	if da == null:
		errors.append("%s: directory not found" % events_dir)
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
	var gates := {}   # "office|field,field" -> the event id that already claims it
	for fname in filenames:
		var path := events_dir.path_join(fname)
		var text := FileAccess.get_file_as_string(path)
		if text.is_empty():
			errors.append("%s: could not read file" % fname)
			continue

		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY or typeof(parsed.get("events")) != TYPE_ARRAY:
			errors.append("%s: invalid event file, expected {\"events\": [...]}" % fname)
			continue

		var raw_list: Array = parsed["events"]
		for i in raw_list.size():
			var entry = raw_list[i]
			if typeof(entry) != TYPE_DICTIONARY:
				errors.append("%s: events[%d] is not an object" % [fname, i])
				continue
			var per_file_errors: Array[String] = []
			var ev = GameEvent.from_dict(
				entry, fname, per_file_errors,
				C.TAX_KEYS, C.SPENDING_KEYS, OpinionK.BLOC_KEYS, C.SECTOR_TREND.keys()
			)
			errors.append_array(per_file_errors)
			if ev.id == "":
				continue
			if seen_ids.has(ev.id):
				errors.append("%s: duplicate event id '%s'" % [fname, ev.id])
			seen_ids[ev.id] = true

			var fields: Array[String] = []
			for cond in ev.preconditions:
				fields.append("%s%s%s" % [cond["field"], cond["op"], str(cond["value"])])
			fields.sort()
			# V3.5f: A GATE IS WHAT AN EVENT NAMES. This check's target is the gate
			# somebody wrote twice -- "two scandals about the prime minister with
			# identical gates" -- but the empty join below made every event with no
			# subject office and no precondition collide with the first such event
			# loaded, and data/events/climate.json's river_flood against
			# broadcast_charter was the first false positive: a pure-hazard crisis
			# about nobody is a shape the content owns (the scandals' own argument,
			# one file over), and two such events are separated by id, body,
			# likelihood, once-ness and the per-event hazard hash, with content order
			# deciding only which of two same-month draws goes first --
			# src/sim/events.gd's own comment. The check keeps its full strength for
			# every event that names a subject or a gate.
			if ev.has_subject() or not ev.preconditions.is_empty():
				var gate := "%s|%s" % [ev.subject_office, ",".join(fields)]
				if gates.has(gate):
					errors.append("%s: '%s' has the same subject and the same gate as '%s' -- two events that can only ever fire in the same months are one event authored twice, and the second fires only where the first did not" % [
						fname, ev.id, str(gates[gate])
					])
				gates[gate] = ev.id
			events.append(ev)


## V2.4b. One summit = two files sharing an id: <ID>.dialogue is the scene in
## dialogue_manager syntax, <ID>.json the sidecar that names it and prices its
## responses. The id is NATION_prefixed and self-describing the way a city id
## is, and the join between the two files is the response LABEL -- validated
## here, loudly, because a scene that offers a choice nothing prices ships a
## live button that refuses silently, which this project has paid for twice.
## The dialogue itself compiles at DRAW time through the addon, so what the
## loader stores is text and the compiler's errors arrive where they can name
## the file they came from.
func _load_summits(summits_dir: String) -> void:
	var da := DirAccess.open(summits_dir)
	if da == null:
		errors.append("%s: directory not found" % summits_dir)
		return

	var ids: Array[String] = []
	da.list_dir_begin()
	var file_name := da.get_next()
	while file_name != "":
		if not da.current_is_dir() and file_name.ends_with(".dialogue"):
			ids.append(file_name.trim_suffix(".dialogue"))
		file_name = da.get_next()
	da.list_dir_end()
	ids.sort()

	for sid in ids:
		var nation_id := sid.split("_")[0] if sid.contains("_") else ""
		if not nations.has(nation_id):
			errors.append("%s: id '%s' does not begin with a nation id -- a summit belongs to a partner" % [sid, sid])
			continue

		var text := FileAccess.get_file_as_string(summits_dir.path_join(sid + ".dialogue"))
		var sidecar_text := FileAccess.get_file_as_string(summits_dir.path_join(sid + ".json"))
		if text.is_empty() or sidecar_text.is_empty():
			errors.append("%s: could not read the .dialogue or its .json sidecar" % sid)
			continue
		var parsed = JSON.parse_string(sidecar_text)
		if typeof(parsed) != TYPE_DICTIONARY:
			errors.append("%s: invalid sidecar, expected an object" % sid)
			continue

		var per_file_errors: Array[String] = []
		var summit = Summit.from_dict(
			text, nation_id, sid, parsed, sid, per_file_errors,
			C.TAX_KEYS, C.SPENDING_KEYS, OpinionK.BLOC_KEYS, C.SECTOR_TREND.keys()
		)
		errors.append_array(per_file_errors)
		if not summits.has(nation_id):
			summits[nation_id] = []
		summits[nation_id].append(summit)
