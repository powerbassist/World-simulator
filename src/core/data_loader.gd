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
const CampaignAction = preload("res://src/core/campaign_action.gd")
const PledgeAction = preload("res://src/core/pledge_action.gd")
const GameEvent = preload("res://src/core/event.gd")
const Summit = preload("res://src/core/summit.gd")
const PeopleLoader = preload("res://src/core/loaders/people_loader.gd")
const CompaniesLoader = preload("res://src/core/loaders/companies_loader.gd")
const RegionsLoader = preload("res://src/core/loaders/regions_loader.gd")
const OutletsLoader = preload("res://src/core/loaders/outlets_loader.gd")
const VerbActionsLoader = preload("res://src/core/loaders/verb_actions_loader.gd")
const EnergyLoader = preload("res://src/core/loaders/energy_loader.gd")
const CampaignLoader = preload("res://src/core/loaders/campaign_loader.gd")
const CommoditiesLoader = preload("res://src/core/loaders/commodities_loader.gd")
const ProgrammeLoader = preload("res://src/core/loaders/programme_loader.gd")
const PoliticsLoader = preload("res://src/core/loaders/politics_loader.gd")
const DiplomacyLoader = preload("res://src/core/loaders/diplomacy_loader.gd")
const GeoLoader = preload("res://src/core/loaders/geo_loader.gd")
const EventsLoader = preload("res://src/core/loaders/events_loader.gd")


## Read through DataLoader by the surfaces; declared beside its validator.
const COMMODITY_CATEGORIES = CommoditiesLoader.COMMODITY_CATEGORIES

const Org = preload("res://src/core/org.gd")

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

## V4.6. The goods register and the recipe table, both from data/commodities/.
## Keyed by id, and a DICTIONARY rather than a typed value type for
## region_graph's own reason: the reader takes them as DATA and a type here
## would be a second record of a file that already states its own shape. What
## only this file can see -- and what _load_commodity_recipes() refuses per entry
## -- is that every recipe's output and every one of its inputs names a good the
## register declares, because an input nobody declares would sit in the file
## looking like a recipe and produce nothing at tick time.
var commodity_goods: Dictionary = {}
var commodity_recipes: Dictionary = {}

## V4.11b. good id -> {producer id: share of WORLD production}, for the raw and agri
## goods only; producers are nation ids, outline ids and WORLD_OTHER (what the
## sources leave unnamed). Generated content (tools/endowments_generate.py,
## docs/commodities-model.md section 8). EMPTY when the file is absent, and that
## absence reads correctly: commodities.gd then sizes every capacity from sector
## output exactly as it did before V4.11 -- which is what the commodity fixtures
## that carry only goods and recipes rely on.
var commodity_endowments: Dictionary = {}

## V4.11b. outline id -> {"name": String, "gdp_eur_bn": float (-1.0 = unmeasured)}
## for every country world.geojson draws that the roster does not simulate. The
## REGISTER of the outline grade (src/core/roster.gd); its GDP is the one figure
## an outline's commodity demand reads. No domestic model.
var outlines: Dictionary = {}


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
## last content type the V1 tier adds. Ordered rather than keyed, and the order still
## matters in two places: the hook door takes the FIRST event on a happening that
## passes its gates, cooldown and likelihood draw, then breaks (authored order is that
## tiebreak), and Events._weighted_pick walks the
## cumulative authored weights in content order. It does NOT break a same-month tie
## between hazard draws: the winner inside a category is a pure weighted draw keyed
## on the SORTED roster of eligible ids, so reordering the files only moves where a
## given event sits on the weight line.
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

## Read through DataLoader by tests/test_events.gd; declared beside its validator.
const ROSTER_SIZE = GeoLoader.ROSTER_SIZE

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


func load_all(nations_dir := "res://data/nations", geo_path := "res://data/geo/europe.geojson", parties_dir := "res://data/parties", laws_dir := "res://data/laws", political_systems_dir := "res://data/political-systems", scenarios_dir := "res://data/scenarios", diplomatic_actions_dir := "res://data/diplomatic-actions", world_path := "res://data/geo/world.geojson", bloc_proposals_dir := "res://data/bloc-proposals", people_dir := "res://data/people", companies_dir := "res://data/companies", company_actions_dir := "res://data/company-actions", outlets_dir := "res://data/outlets", investment_actions_dir := "res://data/investment-actions", project_actions_dir := "res://data/project-actions", campaign_actions_dir := "res://data/campaign-actions", pledges_dir := "res://data/pledges", events_dir := "res://data/events", regions_dir := "res://data/regions", regions_geo_path := "res://data/geo/regions.geojson", regions_graph_path := "res://data/geo/region_graph.json", summits_dir := "res://data/summits", energy_sources_path := "res://data/energy-sources.json", energy_actions_dir := "res://data/energy-actions", orgs_dir := "res://data/orgs", programme_dir := "res://data/programme", commodities_dir := "res://data/commodities", world_dir := "res://data/world") -> void:
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
	commodity_goods.clear()
	commodity_recipes.clear()
	commodity_endowments.clear()
	outlines.clear()
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
		PeopleLoader.load_people(self, id, people_dir)
	for id in nations.keys():
		PoliticsLoader.load_parties(self, id, parties_dir)
	for id in nations.keys():
		CompaniesLoader.load_companies(self, id, companies_dir)
	for id in nations.keys():
		OutletsLoader.load_outlets(self, id, outlets_dir)
	for id in nations.keys():
		RegionsLoader.load_regions(self, id, regions_dir)

	VerbActionsLoader.load_company_actions(self, company_actions_dir)
	VerbActionsLoader.load_investment_actions(self, investment_actions_dir)
	VerbActionsLoader.load_projects(self, project_actions_dir)
	EnergyLoader.load_energy_sources(self, energy_sources_path)
	EnergyLoader.load_energy_actions(self, energy_actions_dir)
	CampaignLoader.load_campaign_actions(self, campaign_actions_dir)
	EventsLoader.load_events(self, events_dir)
	EventsLoader.load_summits(self, summits_dir)
	CampaignLoader.load_pledges(self, pledges_dir)
	ProgrammeLoader.load_programme(self, programme_dir)
	PoliticsLoader.load_laws(self, laws_dir)
	PoliticsLoader.load_political_systems(self, political_systems_dir)
	PoliticsLoader.load_scenarios(self, scenarios_dir)
	DiplomacyLoader.load_diplomatic_actions(self, diplomatic_actions_dir)
	# Orgs before proposals: a proposal names its org, and a reference cannot be
	# validated against a register that has not been filled yet.
	DiplomacyLoader.load_orgs(self, orgs_dir)
	DiplomacyLoader.load_bloc_proposals(self, bloc_proposals_dir)
	# Goods before recipes: a recipe's inputs and output are checked against the
	# register, and a reference cannot be validated against a dictionary that has
	# not been filled yet.
	CommoditiesLoader.load_commodity_goods(self, commodities_dir.path_join("goods.json"))
	CommoditiesLoader.load_commodity_recipes(self, commodities_dir.path_join("recipes.json"))
	CommoditiesLoader.load_commodity_endowments(self, commodities_dir.path_join("endowments.json"))
	CommoditiesLoader.load_outlines(self, world_dir.path_join("outlines.json"))

	GeoLoader.validate_cross_file(self, geo_path, world_path)
	PoliticsLoader.validate_amendments(self)
	PoliticsLoader.validate_scenarios(self)
	GeoLoader.validate_neighbours(self)
	DiplomacyLoader.validate_bloc_proposals(self)
	PeopleLoader.validate_people(self)
	CompaniesLoader.validate_companies(self)
	OutletsLoader.validate_outlets(self, outlets_dir)
	RegionsLoader.validate_regions(self, regions_dir, regions_geo_path, regions_graph_path)
	EnergyLoader.validate_energy_sources(self)
	CommoditiesLoader.validate_commodities(self)


## Resolve a person id to the name a screen prints. The ONLY reader of
## `person_by_id` outside this file, and the reason U6b needed no `people.gd`
## module: a name lookup is a dictionary read, and every panel that wants one
## already holds the loader. An unknown or empty id gives "", which is what the
## panels already did with an empty name field before the re-key -- so a
## government that does not exist still reads as one that does not exist.
func person_name(person_id: String) -> String:
	var person = person_by_id.get(person_id, null)
	return person.person_name if person != null else ""


## The same lookup for a FIRM's name, added when the companies panel and the
## HUD were found carrying byte-identical private copies of it (the ultra's
## find). An unknown id gives back the id, which is what both surfaces'
## fallbacks did -- a name the register cannot resolve is still worth
## printing as the thing the player can go check.
func firm_name(nation_id: String, company_id: String) -> String:
	for company in companies.get(nation_id, []):
		if company.id == company_id:
			return String(company.company_name)
	return company_id


## The same seam for a NATION's display name: the takeover card and the
## panel's bid row printed the raw three-letter id where every other surface
## resolves the name (the pass-4 fleet's find). An unknown id gives back the
## id, the same fallback rule firm_name runs.
func nation_name(nation_id: String) -> String:
	var nation = nations.get(nation_id, null)
	return String(nation.nation_name) if nation != null else nation_id


## The private entry points a test drives one loader through, kept as delegators
## so V5.0b moved no caller: each forwards to the per-content loader that now
## holds the body.
func _load_companies(nation_id: String, companies_dir: String) -> void:
	CompaniesLoader.load_companies(self, nation_id, companies_dir)


func _validate_bloc_proposals() -> void:
	DiplomacyLoader.validate_bloc_proposals(self)


func _load_energy_sources(path: String) -> void:
	EnergyLoader.load_energy_sources(self, path)


func _validate_energy_sources() -> void:
	EnergyLoader.validate_energy_sources(self)


func _load_events(events_dir: String) -> void:
	EventsLoader.load_events(self, events_dir)


func _validate_political_system(n) -> void:
	PoliticsLoader.validate_political_system(self, n)


func _extract_programme_entry(d: Dictionary, filename: String, errors: Array[String]) -> Dictionary:
	return ProgrammeLoader.extract_programme_entry(self, d, filename, errors)
