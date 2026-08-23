class_name Nation
extends RefCounted

## Typed, validated in-memory representation of one data/nations/*.json file.
## Built and range-checked by from_dict(); see docs/data-architecture.md for
## the schema and the import script's ownership boundary on `imported`.

const C = preload("res://src/sim/economy_constants.gd")

const CycleK = preload("res://src/sim/cycle_constants.gd")

const InflationK = preload("res://src/sim/inflation_constants.gd")

const KNOWN_IMPORTED_KEYS: Array[String] = [
	"_source", "_year", "_trend_from_year", "_usd_eur", "population", "gdp_eur_bn",
	"unemployment_pct", "sectors", "cohorts", "inequality", "cycle", "prices",
]
const KNOWN_SECTOR_KEYS: Array[String] = ["agriculture", "industry", "services"]

## V1.5b. imported.cohorts, all six required and no others accepted -- KNOWN_SECTOR_KEYS'
## treatment, for the same reason: this block is script-written, so a key that is absent
## or misspelled is a broken import rather than an authoring choice to be tolerated.
const KNOWN_COHORT_KEYS: Array[String] = [
	"young_pct", "old_pct", "young_pct_per_yr", "old_pct_per_yr",
	"participation_pct", "pop_growth_pct",
]

## V1.5c. imported.inequality, KNOWN_COHORT_KEYS' treatment for the same reason. The two
## provenance keys are required rather than optional: this series is the only one in the
## block read at a year the rest of it does not describe, so a file that omits them
## claims a 2024 Gini it does not have.
const KNOWN_INEQUALITY_KEYS: Array[String] = [
	"gini_index", "gini_index_per_yr", "_year", "_from_year",
]

## V1.6a. imported.cycle, KNOWN_INEQUALITY_KEYS' treatment. The provenance keys are
## required for that block's reason and one harder: this is the only series in
## `imported` read over a DIFFERENT WINDOW from the rest of the file (1990-2024
## against 2015-2024) and with two years DELETED from it, so a file that omits them
## claims a figure measured the way everything above it was measured. `_excludes`
## names the deleted years explicitly rather than implying them, because the deletion
## is the block's one editorial act -- see tools/import_data.py.
const KNOWN_CYCLE_KEYS: Array[String] = [
	"amplitude_rel", "growth_sd_pct", "_from_year", "_to_year", "_excludes",
]

## V1.6b. imported.prices, KNOWN_CYCLE_KEYS' treatment for its exact reason: this
## series shares the cycle's 1990-2024 window rather than the 2015-2024 one the rest of
## the block uses, so a file that omits the provenance keys claims a figure measured
## the way everything above it was measured.
##
## `_excludes` is required even though it is always EMPTY, and that is the point rather
## than an oversight. The cycle drops 2020-21 because a pandemic is an exogenous OUTPUT
## shock in a series measuring output; the 2022-23 energy spike is a PRICE shock in a
## series measuring prices, which is the thing this indicator exists to record. An
## empty list states that the question was asked and answered -- see
## tools/import_data.py's PRICES_EXCLUDE_YEARS.
const KNOWN_PRICES_KEYS: Array[String] = [
	"inflation_pct", "_from_year", "_to_year", "_excludes",
]

## The 15-64 share may not fall below this, in points. It is a guard on the RESIDUAL:
## Demography.working_share() is 1 - young - old and is a DENOMINATOR twice over, in
## dependency_ratio() and in labour_force(), so a nation authored close to 100 % young
## plus old divides by nearly nothing and every figure downstream diverges. The roster's
## thinnest is Italy at 63.49, so 30.0 is a guard rail rather than a lever -- the
## treatment defence_constants.CAPABILITY_MAX gets.
const MIN_WORKING_PCT := 30.0

## Bounds on the compound annual population rate, in percent. Signed, because Italy's
## is measured at -0.238: a roster where every nation grows was economy_constants'
## flat POP_GROWTH_PCT = 0.15, and replacing it with a measured figure means admitting
## the ones that shrink. The floor is what stops a nation being authored into a
## negative population, which docs/data-architecture.md's checklist has always asked
## for and which was trivially true while the rate was one shared constant.
const MIN_POP_GROWTH_PCT := -3.0
const MAX_POP_GROWTH_PCT := 5.0
const KNOWN_ELECTION_SYSTEMS: Array[String] = ["pr_dhondt", "pr_national", "fptp", "two_round", "parallel"]

## Moved from data_loader.gd's now-deleted _load_policy_defaults() at V1.2a,
## when starting fiscal policy moved from the one shared policy_defaults.json
## into each nation's own fiscal block.
const MAX_TAX_RATE_PCT := 100.0
const MAX_SPENDING_PCT_GDP := 100.0

## How a government is assembled, and what it takes to bring one down. Both are
## dispatched on the string in src/sim/government.gd, never on the nation id —
## see docs/government-model.md and docs/engine-decision.md Rule 1.
const KNOWN_FORMATION_METHODS: Array[String] = [
	"presidential_appointment", "chancellor_election", "investiture",
	"coalition_negotiation", "largest_party", "directorial",
]
const KNOWN_CENSURE_RULES: Array[String] = [
	"absolute_members", "constructive_absolute", "simple_present", "none",
]

## Who may dissolve the assembly early, dispatched in src/sim/dissolution.gd,
## never on the nation id -- docs/dissolution-model.md and
## docs/engine-decision.md Rule 1.
const KNOWN_DISSOLUTION_RULES: Array[String] = [
	"executive_discretion", "confidence_failure", "head_of_state_limited",
	"self_dissolution", "none",
]

## What it takes to pass a constitutional amendment, dispatched in
## src/sim/legislature.gd's amendment vote path, never on the nation id --
## docs/amendment-model.md and docs/engine-decision.md Rule 1.
##
## referendum_required is declared, unresolved -- the same shape
## PoliticalSystem.KNOWN_LOSE_CONDITIONS' "never" uses for Switzerland: no
## referendum mechanic exists yet (V1.1f/V1.7), so no amendment is proposable
## for a nation carrying this rule. two_thirds is genuinely, measurably
## unreachable for Germany's six-party roster even at full term-start
## cohesion -- see docs/amendment-model.md's reachability sweep -- so Germany
## carries the real rule with no amendment content authored against it,
## rather than a detuned number invented to make the mechanic playable.
const KNOWN_AMENDMENT_RULES: Array[String] = [
	"ordinary_law", "three_fifths", "two_thirds", "three_quarters", "referendum_required",
]

## Who the head of state is, and how they got there. Dispatched nowhere in
## sim code except the elected_president clock dissolution.gd reads for
## head_of_state_limited -- otherwise decorative, read only by the government
## panel. See docs/political-systems.md.
const KNOWN_HEAD_OF_STATE_KINDS: Array[String] = [
	"executive_president", "elected_president", "hereditary_monarch", "collegial",
]

const MIN_TERM_LIMIT := 0
const MAX_TERM_LIMIT := 10

static var _id_regex := RegEx.create_from_string("^[A-Z]{3}$")

var id: String = ""
var nation_name: String = ""
var geo_id: String = ""
var capital: String = ""
var playable: bool = false

## The face of the nation, as a reference into data/people/. In nine of the ten
## this is the head of government and in France it is the head of state, so it
## resolves to a person another slot also points at -- which is fine and is the
## point of a register: two references may name one person, where two authored
## NAMES could disagree. Before U6b every nation file wrote this name twice.
var leader_person_id: String = ""
var leader_title: String = ""
var leader_party_id: String = ""

## The flag, as bands of colour plus a layout string src/ui/flag.gd dispatches
## on -- the same dispatch-on-a-data-string shape as formation_method and the
## six fields below it, and here for the same reason: a colour table keyed by
## nation id in the UI would be `if nation_id == "FRA"` wearing a hat, which
## docs/engine-decision.md Rule 1 forbids outright.
##
## Two nations are not bands and say so rather than being special-cased at the
## call site: GBR is `union` and CHE is `cross`. Both are drawn from the same
## `flag_bands` list, read in a layout-specific order -- see flag.gd.
##
## The bands are ordered hoist-first (left to right, or top to bottom). Charges
## are not modelled: Spain's arms and Luxembourg's proportions are not what a
## 24-pixel flag on a portrait card conveys.
const KNOWN_FLAG_LAYOUTS: Array[String] = ["vertical", "horizontal", "union", "cross"]

var flag_bands: Array[Color] = []
var flag_layout: String = ""

## Where this nation's infrastructure projects stand, as project id -> lon/lat.
## U6c, and the block is OPTIONAL: a nation with none draws no marker and
## simulates exactly as it did before, the way an absent data/outlets/ file means
## no press.
##
## **The site is on the NATION, not in data/project-actions/, and that is U6c's
## central call.** The action list is global -- one `high_speed_rail` shared by
## all ten -- so a coordinate inside `effects.project` would put every nation's
## rail spine at one point on the planet, and moving that directory per-nation to
## fix it reopens a call V1.6f made freely. U6b's rule applies unchanged: a law
## names an office and the nation names the person. A project names a work; the
## nation names the ground it stands on.
var project_sites: Dictionary = {}  # String project id -> Vector2(lon, lat)

## The assembly's own term and size, from government.legislative. Distinct from
## the executive's term below: in France those are two different clocks, and
## conflating them is what made the player's term read as the Assembly's.
var term_years: int = 0
var assembly_seats: int = 0
var chamber_name: String = ""

## Present only where the head of government is elected separately from the
## assembly — of the ten, only France. Absent means the executive is drawn from
## the chamber and its term IS the legislative term, the same "field exists,
## reader does nothing" shape EU membership already uses. See
## docs/government-model.md.
var has_executive: bool = false
var executive_title: String = ""
var executive_term_years: int = 0
var executive_next_year: int = 0
var executive_next_month: int = 0

## How a government forms and how it can be brought down. Required for all ten,
## resolved only for the player's nation — the same authored-but-not-resolved
## split docs/electoral-systems.md makes for the election schedule.
var formation_method: String = ""
var censure_rule: String = ""
var head_of_government_title: String = ""

## Who holds the head-of-government office at game start. Equal to the national
## leader for nine of the ten; France is the exception, where the leader is the
## President and the Prime Minister is a separate person.
var head_of_government_person_id: String = ""

## The nation's own next scheduled election, real and sourced — see
## docs/electoral-systems.md. Authored, not imported: tools/import_data.py never
## reads or writes it, same class as fiscal below.
var election_system: String = ""
var election_next_year: int = 0
var election_next_month: int = 0
var election_threshold_pct: float = 0.0

## Who may end the current assembly early, and what it costs to. Required for
## all ten, resolved only for the player's nation -- see docs/dissolution-model.md.
var dissolution_rule: String = ""
var dissolution_lockout_months: int = 0
var dissolution_notice_months: int = 0

## Which template this nation's institutions are declared as, validated by
## data_loader.gd against data/political-systems/*.json -- every flat field
## above must fall inside that template's allowed set. See
## docs/political-systems.md.
var system_id: String = ""

## The head of state -- absent from the game entirely before V1.2b. Required
## for all ten; only elected_president carries its own term/election clock,
## the same "present only where needed, and complete if present" shape
## has_executive already uses below.
var head_of_state_kind: String = ""
var head_of_state_title: String = ""
var head_of_state_person_id: String = ""
var head_of_state_term_years: int = 0

## Whom data/laws/amendments.json's Restoration Act puts on the throne. Authored
## per nation because the law is generic and the dynasty is not -- before U6b the
## law named "Alexander IV" inline, so every parliamentary republic in Europe
## restored one shared king. A nation that already has a monarch points this at
## that same person, so a republic-then-restoration returns the right house.
var pretender_person_id: String = ""
var head_of_state_next_year: int = 0
var head_of_state_next_month: int = 0

## How many terms the player's own office permits before the run ends
## termed-out, 0 meaning no limit. Only France's template permits a nonzero
## value -- see docs/political-systems.md.
var term_limit: int = 0

## What a constitutional amendment must clear to pass, dispatched by
## src/sim/legislature.gd's resolve_vote() amendment arm -- see
## docs/amendment-model.md.
var amendment_rule: String = ""

## Whether this nation's own constitution permits changing its political
## system at all -- distinct from amendment_rule, which is the bar an
## amendment must clear IF proposable. Per-nation, not per-template: DEU,
## ITA and AUT share parliamentary_republic with a transitioned GBR, and the
## prohibition on changing the form of state belongs to each nation's own
## constitution, not to the template's shape. Immutable at runtime -- no
## amendment in this game can un-entrench itself. See
## docs/transition-model.md.
var permits_system_change: bool = false

## EU membership and European Parliament seat count. Empty/zero for a
## non-member — GBR and CHE simply have no reader for these, see
## docs/electoral-systems.md.
var eu_member: bool = false
var eu_ep_seats: int = 0

## Which nations in the roster this one shares a land border with. A FACT, not
## a tuned number -- the same class as assembly_seats -- and the reason V1.3a
## derives relations rather than authoring 45 of them: it is one of only two
## inputs docs/data-sources.md can actually supply. Empty is legitimate: GBR's
## only land border is with a nation outside the ten.
##
## Borders outside the roster (Portugal, Slovenia, Denmark...) are deliberately
## absent. Nothing reads them, and listing an id no nation file defines would
## fail data_loader.gd's own cross-file check. See docs/diplomacy-model.md.
var neighbours: Array[String] = []

var debt_to_gdp_pct: float = 0.0
var tax_revenue_pct_gdp: float = 0.0

## Starting fiscal policy -- per nation since V1.2a. Previously one shared
## data/policy_defaults.json; see the _note on FRA.json's fiscal block for the
## sourcing and derivation of the other nine. GameState._build_nation() reads
## these instead of a loader-wide defaults argument.
var tax_rates_pct: Dictionary = {}          # income, corporate, vat
var spending_pct_gdp: Dictionary = {}       # health, education, defence, pensions, infrastructure
var other_spending_pct_gdp: float = 0.0

var population: int = 0
var gdp_eur_bn: float = 0.0
var unemployment_pct: float = 0.0
var sectors: Dictionary = {}

## V1.5b. The age structure, its measured slope, and the participation rate --
## imported.cohorts, written by tools/import_data.py from World Bank indicators over
## 2015-2024 and never authored. Keys are KNOWN_COHORT_KEYS below.
##
## The 15-64 share is NOT here, deliberately: Demography.working_share() derives it as
## the residual 1 - young - old, so there is exactly one answer and a conservation bug
## is structurally impossible. That is _apply_growth_to_sectors()'s discipline, and it
## is why _validate_cohorts() bounds the two shares against each other rather than
## checking a third against their sum.
var cohorts: Dictionary = {}

## V1.5c. imported.inequality -- the Gini index, its measured slope, and the two years
## they came from. Written by tools/import_data.py from World Bank SI.POV.GINI and never
## authored, the same standing as `cohorts` above.
##
## docs/tiers/v1.md section 6 says section 5's index "cannot be DERIVED", and it is
## right: there are no brackets, no deciles and no capital/labour split anywhere in this
## model. It does not follow that the index has to be invented. The provider that
## supplies every other figure in this block publishes it, which is why this is content
## and not a constant -- and why Unrest.inequality_deviation() can be a pure read with
## no field, no accumulator and no save entry.
var inequality: Dictionary = {}

## V1.6a. imported.cycle -- the nation's real-GDP-growth volatility relative to the
## roster mean, and the raw standard deviation it came from. Script-written, the same
## standing as `cohorts` and `inequality` above.
##
## `amplitude_rel` is the whole content contribution of the business cycle: the LEVEL
## is cycle_constants.CYCLE_AMPLITUDE_PCT, a pacing decision this game makes, and this
## is the SPREAD, which is measured. Ten values from 0.689 to 1.475 rather than ten
## copies of 1.0, which is what keeps the cycle off docs/foreign-policy-model.md's
## clustered `coalition_position` failure. See docs/cycle-model.md section 3.
var cycle: Dictionary = {}

## V1.6b. imported.prices -- the nation's own long-run inflation anchor, on the same
## standing as `cycle` above and measured the same way.
##
## `inflation_pct` is the whole content contribution of the inflation model, and the
## split matches the cycle's exactly: the RESPONSE is
## inflation_constants.INFLATION_UNEMP_BETA and INFLATION_CONVERGENCE, roster-wide and
## measured once, and this is the LEVEL each nation returns to, which differs. Ten
## values from 1.117 (Switzerland) to 2.903 (Spain), a 2.6x spread that does not
## cluster. See docs/inflation-model.md section 3.
var prices: Dictionary = {}


static func from_dict(d: Dictionary, filename: String, errors: Array[String]):
	var n := new()

	n.id = _extract_string(d, "id", filename, errors)
	if n.id != "" and not _id_regex.search(n.id):
		errors.append("%s: id '%s' must be three uppercase letters" % [filename, n.id])
	var stem := filename.get_basename()
	if n.id != "" and n.id != stem:
		errors.append("%s: id '%s' does not match filename" % [filename, n.id])

	n.nation_name = _extract_string(d, "name", filename, errors)
	n.geo_id = _extract_string(d, "geo_id", filename, errors)
	n.capital = _extract_string(d, "capital", filename, errors)
	n.playable = _extract_bool(d, "playable", filename, errors)

	var leader: Dictionary = _extract_dict(d, "leader", filename, errors)
	n.leader_person_id = _extract_string(leader, "person", filename, errors)
	n.leader_title = _extract_string(leader, "title", filename, errors)
	n.leader_party_id = _extract_string(leader, "party", filename, errors)

	var flag: Dictionary = _extract_dict(d, "flag", filename, errors)
	n.flag_layout = _extract_string(flag, "layout", filename, errors)
	if n.flag_layout != "" and not KNOWN_FLAG_LAYOUTS.has(n.flag_layout):
		errors.append("%s: flag.layout '%s' is not one of %s" % [filename, n.flag_layout, str(KNOWN_FLAG_LAYOUTS)])
	n.flag_bands = _extract_colours(flag, "bands", filename, errors)

	n.project_sites = _extract_project_sites(d, filename, errors)

	var government: Dictionary = _extract_dict(d, "government", filename, errors)

	var legislative: Dictionary = _extract_dict(government, "legislative", filename, errors)
	n.term_years = _extract_int(legislative, "term_years", "government.legislative.term_years", filename, errors)
	_check_range_int(n.term_years, 1, 10, "government.legislative.term_years", filename, errors)
	n.assembly_seats = _extract_int(legislative, "assembly_seats", "government.legislative.assembly_seats", filename, errors)
	_check_range_int(n.assembly_seats, 1, 2000, "government.legislative.assembly_seats", filename, errors)
	n.chamber_name = _extract_string(legislative, "chamber", filename, errors)

	var election: Dictionary = _extract_dict(legislative, "election", filename, errors)
	n.election_system = _extract_string(election, "system", filename, errors)
	if n.election_system != "" and not KNOWN_ELECTION_SYSTEMS.has(n.election_system):
		errors.append("%s: government.legislative.election.system '%s' is not a recognised method" % [filename, n.election_system])
	var next: Dictionary = _extract_dict(election, "next", filename, errors)
	n.election_next_year = _extract_int(next, "year", "government.legislative.election.next.year", filename, errors)
	_check_range_int(n.election_next_year, 2026, 2100, "government.legislative.election.next.year", filename, errors)
	n.election_next_month = _extract_int(next, "month", "government.legislative.election.next.month", filename, errors)
	_check_range_int(n.election_next_month, 1, 12, "government.legislative.election.next.month", filename, errors)
	n.election_threshold_pct = _extract_float(election, "threshold_pct", "government.legislative.election.threshold_pct", filename, errors)
	_check_range_float(n.election_threshold_pct, 0.0, 20.0, "government.legislative.election.threshold_pct", filename, errors)

	var dissolution: Dictionary = _extract_dict(legislative, "dissolution", filename, errors)
	n.dissolution_rule = _extract_string(dissolution, "rule", filename, errors)
	if n.dissolution_rule != "" and not KNOWN_DISSOLUTION_RULES.has(n.dissolution_rule):
		errors.append("%s: government.legislative.dissolution.rule '%s' is not a recognised rule" % [filename, n.dissolution_rule])
	n.dissolution_lockout_months = _extract_int(dissolution, "lockout_months", "government.legislative.dissolution.lockout_months", filename, errors)
	_check_range_int(n.dissolution_lockout_months, 0, 60, "government.legislative.dissolution.lockout_months", filename, errors)
	n.dissolution_notice_months = _extract_int(dissolution, "notice_months", "government.legislative.dissolution.notice_months", filename, errors)
	_check_range_int(n.dissolution_notice_months, 1, 6, "government.legislative.dissolution.notice_months", filename, errors)

	# Optional by design: absent means the executive comes out of the chamber.
	# Present, it must be complete — a half-authored executive block is the
	# silent-wrong-term bug this validation exists to prevent.
	n.has_executive = government.has("executive")
	if n.has_executive:
		var executive: Dictionary = _extract_dict(government, "executive", filename, errors)
		n.executive_title = _extract_string(executive, "title", filename, errors)
		n.executive_term_years = _extract_int(executive, "term_years", "government.executive.term_years", filename, errors)
		_check_range_int(n.executive_term_years, 1, 10, "government.executive.term_years", filename, errors)
		var exec_next: Dictionary = _extract_dict(executive, "next", filename, errors)
		n.executive_next_year = _extract_int(exec_next, "year", "government.executive.next.year", filename, errors)
		_check_range_int(n.executive_next_year, 2026, 2100, "government.executive.next.year", filename, errors)
		n.executive_next_month = _extract_int(exec_next, "month", "government.executive.next.month", filename, errors)
		_check_range_int(n.executive_next_month, 1, 12, "government.executive.next.month", filename, errors)

	n.system_id = _extract_string(government, "system", filename, errors)

	var head_of_state: Dictionary = _extract_dict(government, "head_of_state", filename, errors)
	n.head_of_state_kind = _extract_string(head_of_state, "kind", filename, errors)
	if n.head_of_state_kind != "" and not KNOWN_HEAD_OF_STATE_KINDS.has(n.head_of_state_kind):
		errors.append("%s: government.head_of_state.kind '%s' is not a recognised kind" % [filename, n.head_of_state_kind])
	n.head_of_state_title = _extract_string(head_of_state, "title", filename, errors)
	n.head_of_state_person_id = _extract_string(head_of_state, "person", filename, errors)
	# Only an elected head of state has a clock of its own -- a monarch, a
	# collegial presidency, or a president who IS the executive (France) does
	# not. Present-only-if-required, complete-if-present -- the same rule
	# `executive` below already enforces, for the same reason: a half-authored
	# clock is the silent-wrong-term bug the validation exists to prevent.
	if n.head_of_state_kind == "elected_president":
		n.head_of_state_term_years = _extract_int(head_of_state, "term_years", "government.head_of_state.term_years", filename, errors)
		_check_range_int(n.head_of_state_term_years, 1, 10, "government.head_of_state.term_years", filename, errors)
		var hos_next: Dictionary = _extract_dict(head_of_state, "next", filename, errors)
		n.head_of_state_next_year = _extract_int(hos_next, "year", "government.head_of_state.next.year", filename, errors)
		_check_range_int(n.head_of_state_next_year, 2026, 2100, "government.head_of_state.next.year", filename, errors)
		n.head_of_state_next_month = _extract_int(hos_next, "month", "government.head_of_state.next.month", filename, errors)
		_check_range_int(n.head_of_state_next_month, 1, 12, "government.head_of_state.next.month", filename, errors)
	elif head_of_state.has("term_years") or head_of_state.has("next"):
		errors.append("%s: government.head_of_state.kind '%s' must not carry term_years/next" % [filename, n.head_of_state_kind])

	n.term_limit = _extract_int(government, "term_limit", "government.term_limit", filename, errors)
	_check_range_int(n.term_limit, MIN_TERM_LIMIT, MAX_TERM_LIMIT, "government.term_limit", filename, errors)

	var amendment: Dictionary = _extract_dict(government, "amendment", filename, errors)
	n.amendment_rule = _extract_string(amendment, "rule", filename, errors)
	if n.amendment_rule != "" and not KNOWN_AMENDMENT_RULES.has(n.amendment_rule):
		errors.append("%s: government.amendment.rule '%s' is not a recognised rule" % [filename, n.amendment_rule])
	n.permits_system_change = _extract_bool(amendment, "permits_system_change", filename, errors)

	var formation: Dictionary = _extract_dict(government, "formation", filename, errors)
	n.formation_method = _extract_string(formation, "method", filename, errors)
	if n.formation_method != "" and not KNOWN_FORMATION_METHODS.has(n.formation_method):
		errors.append("%s: government.formation.method '%s' is not a recognised method" % [filename, n.formation_method])
	n.censure_rule = _extract_string(formation, "censure", filename, errors)
	if n.censure_rule != "" and not KNOWN_CENSURE_RULES.has(n.censure_rule):
		errors.append("%s: government.formation.censure '%s' is not a recognised rule" % [filename, n.censure_rule])
	n.head_of_government_title = _extract_string(formation, "head_of_government_title", filename, errors)
	n.head_of_government_person_id = _extract_string(formation, "head_of_government_person", filename, errors)

	n.pretender_person_id = _extract_string(government, "pretender_person", filename, errors)

	var eu: Dictionary = _extract_dict(government, "eu", filename, errors)
	n.eu_member = _extract_bool(eu, "member", filename, errors)
	if n.eu_member:
		n.eu_ep_seats = _extract_int(eu, "ep_seats", "government.eu.ep_seats", filename, errors)
		_check_range_int(n.eu_ep_seats, 1, 200, "government.eu.ep_seats", filename, errors)

	# Required and possibly empty, rather than optional: an absent key would be
	# indistinguishable from "this nation borders nobody", and one of the ten
	# genuinely borders nobody. Whether each id names a nation that LOADED, and
	# whether the relation is mutual, are cross-file questions --
	# data_loader.gd's _validate_neighbours().
	n.neighbours = _extract_neighbours(government, n.id, filename, errors)

	var fiscal: Dictionary = _extract_dict(d, "fiscal", filename, errors)
	n.debt_to_gdp_pct = _extract_float(fiscal, "debt_to_gdp_pct", "fiscal.debt_to_gdp_pct", filename, errors)
	_check_range_float(n.debt_to_gdp_pct, 0.0, 400.0, "fiscal.debt_to_gdp_pct", filename, errors)
	n.tax_revenue_pct_gdp = _extract_float(fiscal, "tax_revenue_pct_gdp", "fiscal.tax_revenue_pct_gdp", filename, errors)
	_check_range_float(n.tax_revenue_pct_gdp, 0.0, 100.0, "fiscal.tax_revenue_pct_gdp", filename, errors)

	var rates: Dictionary = _extract_dict(fiscal, "tax_rates_pct", filename, errors)
	for key in C.TAX_KEYS:
		var rate := _extract_float(rates, key, "fiscal.tax_rates_pct.%s" % key, filename, errors)
		_check_range_float(rate, 0.0, MAX_TAX_RATE_PCT, "fiscal.tax_rates_pct.%s" % key, filename, errors)
		n.tax_rates_pct[key] = rate

	var spending: Dictionary = _extract_dict(fiscal, "spending_pct_gdp", filename, errors)
	for key in C.SPENDING_KEYS:
		var amount := _extract_float(spending, key, "fiscal.spending_pct_gdp.%s" % key, filename, errors)
		_check_range_float(amount, 0.0, MAX_SPENDING_PCT_GDP, "fiscal.spending_pct_gdp.%s" % key, filename, errors)
		n.spending_pct_gdp[key] = amount

	n.other_spending_pct_gdp = _extract_float(fiscal, "other_spending_pct_gdp", "fiscal.other_spending_pct_gdp", filename, errors)
	_check_range_float(n.other_spending_pct_gdp, 0.0, MAX_SPENDING_PCT_GDP, "fiscal.other_spending_pct_gdp", filename, errors)

	var imported: Dictionary = _extract_dict(d, "imported", filename, errors)
	for key in imported.keys():
		if not KNOWN_IMPORTED_KEYS.has(key):
			errors.append("%s: imported.%s is not a recognised field" % [filename, key])

	n.population = _extract_int(imported, "population", "imported.population", filename, errors)
	_check_range_int(n.population, 100_000, 2_000_000_000, "imported.population", filename, errors)

	n.gdp_eur_bn = _extract_float(imported, "gdp_eur_bn", "imported.gdp_eur_bn", filename, errors)
	_check_range_float(n.gdp_eur_bn, 0.0001, 100_000.0, "imported.gdp_eur_bn", filename, errors)

	n.unemployment_pct = _extract_float(imported, "unemployment_pct", "imported.unemployment_pct", filename, errors)
	_check_range_float(n.unemployment_pct, 0.0, 100.0, "imported.unemployment_pct", filename, errors)

	n.sectors = _extract_dict(imported, "sectors", filename, errors)
	_validate_sectors(n.sectors, filename, errors)

	n.cohorts = _extract_dict(imported, "cohorts", filename, errors)
	_validate_cohorts(n.cohorts, filename, errors)

	n.inequality = _extract_dict(imported, "inequality", filename, errors)
	_validate_inequality(n.inequality, filename, errors)

	n.cycle = _extract_dict(imported, "cycle", filename, errors)
	_validate_cycle(n.cycle, filename, errors)

	n.prices = _extract_dict(imported, "prices", filename, errors)
	_validate_prices(n.prices, filename, errors)

	return n


## Shape and self-consistency only: three uppercase letters, no self-reference,
## no duplicates. Sorted on the way out so the derived resting value cannot
## depend on authoring order.
static func _extract_neighbours(government: Dictionary, nation_id: String, filename: String, errors: Array[String]) -> Array[String]:
	var out: Array[String] = []
	if not government.has("neighbours") or typeof(government["neighbours"]) != TYPE_ARRAY:
		errors.append("%s: missing or invalid array field 'government.neighbours'" % filename)
		return out

	for entry in government["neighbours"]:
		if typeof(entry) != TYPE_STRING or not _id_regex.search(entry):
			errors.append("%s: government.neighbours entry '%s' must be three uppercase letters" % [filename, str(entry)])
			continue
		if entry == nation_id:
			errors.append("%s: government.neighbours lists the nation itself" % filename)
			continue
		if out.has(entry):
			errors.append("%s: government.neighbours lists '%s' twice" % [filename, entry])
			continue
		out.append(entry)

	out.sort()
	return out


static func _validate_sectors(sectors: Dictionary, filename: String, errors: Array[String]) -> void:
	var keys := sectors.keys()
	keys.sort()
	var expected := KNOWN_SECTOR_KEYS.duplicate()
	expected.sort()
	if keys != expected:
		errors.append("%s: imported.sectors must have exactly keys %s, got %s" % [filename, expected, keys])
		return

	var total := 0.0
	for key in KNOWN_SECTOR_KEYS:
		var raw = sectors[key]
		if not (typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT):
			errors.append("%s: imported.sectors.%s is not numeric" % [filename, key])
			continue
		var value: float = raw
		if value < 0.0 or value > 1.0:
			errors.append("%s: imported.sectors.%s = %s out of range [0, 1]" % [filename, key, str(value)])
		total += value

	if absf(total - 1.0) > 0.001:
		errors.append("%s: imported.sectors sums to %s, expected 1.0" % [filename, str(total)])


## V1.5b. _validate_sectors()'s shape, with one difference that is the whole point:
## sectors are checked against a SUM because all three are authored, and cohorts are
## checked against a RESIDUAL because the third is not.
##
## The two range checks that are not obvious, and neither is decoration:
##
##   (1) young + old must leave MIN_WORKING_PCT of working age. working_share() is a
##       denominator in both dependency_ratio() and labour_force(), so a nation
##       authored near 100 % dependent divides by nearly nothing and every figure
##       downstream diverges. Checked here rather than clamped in demography.gd,
##       because a clamp would silently accept a broken import and run the game on it.
##   (2) pop_growth_pct is bounded and SIGNED. Italy's is -0.238, so a one-sided check
##       would refuse the roster; an unbounded one lets a bad import author a nation
##       into a negative population over fourteen years.
static func _validate_cohorts(cohorts: Dictionary, filename: String, errors: Array[String]) -> void:
	var keys := cohorts.keys()
	keys.sort()
	var expected := KNOWN_COHORT_KEYS.duplicate()
	expected.sort()
	if keys != expected:
		errors.append("%s: imported.cohorts must have exactly keys %s, got %s" % [filename, expected, keys])
		return

	for key in KNOWN_COHORT_KEYS:
		var raw = cohorts[key]
		if not (typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT):
			errors.append("%s: imported.cohorts.%s is not numeric" % [filename, key])
			return

	var young: float = cohorts["young_pct"]
	var old: float = cohorts["old_pct"]
	_check_range_float(young, 0.0, 100.0, "imported.cohorts.young_pct", filename, errors)
	_check_range_float(old, 0.0, 100.0, "imported.cohorts.old_pct", filename, errors)

	var working: float = 100.0 - young - old
	if working < MIN_WORKING_PCT:
		errors.append("%s: imported.cohorts leaves %s%% of working age, below the %s%% floor -- Demography.working_share() is a denominator twice over" % [filename, str(snappedf(working, 0.01)), str(MIN_WORKING_PCT)])

	# The slopes are bounded by the share they move: a share cannot travel more than
	# its own range per year, and a figure anywhere near that is a broken import
	# rather than a fast-ageing country. The roster's largest is France at +0.366.
	_check_range_float(cohorts["young_pct_per_yr"], -100.0, 100.0, "imported.cohorts.young_pct_per_yr", filename, errors)
	_check_range_float(cohorts["old_pct_per_yr"], -100.0, 100.0, "imported.cohorts.old_pct_per_yr", filename, errors)

	# Not [0, 100]: participation is a share of the 15-64 population, and a rate of
	# zero would put the labour force at zero and divide firm_jobs_offset_pct() by it.
	_check_range_float(cohorts["participation_pct"], 1.0, 100.0, "imported.cohorts.participation_pct", filename, errors)
	_check_range_float(cohorts["pop_growth_pct"], MIN_POP_GROWTH_PCT, MAX_POP_GROWTH_PCT, "imported.cohorts.pop_growth_pct", filename, errors)


## V1.5c. _validate_cohorts()'s shape. The one check worth explaining is the last: the
## two provenance years must differ, because the slope is measured over their span and a
## single-year series would divide by zero. tools/import_data.py refuses that case at
## import time; this refuses a hand-edited file that reintroduces it.
static func _validate_inequality(inequality: Dictionary, filename: String, errors: Array[String]) -> void:
	var keys := inequality.keys()
	keys.sort()
	var expected := KNOWN_INEQUALITY_KEYS.duplicate()
	expected.sort()
	if keys != expected:
		errors.append("%s: imported.inequality must have exactly keys %s, got %s" % [filename, expected, keys])
		return

	for key in KNOWN_INEQUALITY_KEYS:
		var raw = inequality[key]
		if not (typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT):
			errors.append("%s: imported.inequality.%s is not numeric" % [filename, key])
			return

	# The Gini index is bounded [0, 100] by definition; the roster spans 25.7 to 34.3.
	_check_range_float(inequality["gini_index"], 0.0, 100.0, "imported.inequality.gini_index", filename, errors)

	# SIGNED, and that is the interesting half: six of the ten are falling and four are
	# rising, so a one-sided check would refuse the roster. Bounded by the index's own
	# range per year, the treatment the cohort slopes get.
	_check_range_float(inequality["gini_index_per_yr"], -100.0, 100.0, "imported.inequality.gini_index_per_yr", filename, errors)

	if int(inequality["_year"]) <= int(inequality["_from_year"]):
		errors.append("%s: imported.inequality._year (%s) must be after _from_year (%s) -- the slope is measured over their span" % [
			filename, str(inequality["_year"]), str(inequality["_from_year"])
		])


## V1.6a. _validate_inequality()'s shape, with two checks that are specific to this
## block and are not decoration.
##
##   (1) `amplitude_rel` is bounded by cycle_constants.AMPLITUDE_REL_MIN/MAX, which is
##       a guard rail and not a lever -- MIN_WORKING_PCT's standing. A value of zero
##       would switch the cycle off for one nation silently, and Cycle.impulse_pct()
##       returns 0.0 on a non-positive relative amplitude rather than dividing by it,
##       so without this check a broken import produces a flat country and no error.
##   (2) `_excludes` must be an array, and it may be EMPTY. Empty is a legitimate
##       statement -- *this window needed no deletion* -- where a missing key is a file
##       that never considered the question. The roster's is [2020, 2021] for all ten.
static func _validate_cycle(cycle_block: Dictionary, filename: String, errors: Array[String]) -> void:
	var keys := cycle_block.keys()
	keys.sort()
	var expected := KNOWN_CYCLE_KEYS.duplicate()
	expected.sort()
	if keys != expected:
		errors.append("%s: imported.cycle must have exactly keys %s, got %s" % [filename, expected, keys])
		return

	for key in ["amplitude_rel", "growth_sd_pct", "_from_year", "_to_year"]:
		var raw = cycle_block[key]
		if not (typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT):
			errors.append("%s: imported.cycle.%s is not numeric" % [filename, key])
			return

	if typeof(cycle_block["_excludes"]) != TYPE_ARRAY:
		errors.append("%s: imported.cycle._excludes must be an array of years" % filename)
		return

	_check_range_float(
		cycle_block["amplitude_rel"], CycleK.AMPLITUDE_REL_MIN, CycleK.AMPLITUDE_REL_MAX,
		"imported.cycle.amplitude_rel", filename, errors
	)
	# A standard deviation cannot be negative, and a European economy whose real growth
	# varies by more than 25 points a year is a broken series rather than a country.
	_check_range_float(cycle_block["growth_sd_pct"], 0.0, 25.0, "imported.cycle.growth_sd_pct", filename, errors)

	if int(cycle_block["_to_year"]) <= int(cycle_block["_from_year"]):
		errors.append("%s: imported.cycle._to_year (%s) must be after _from_year (%s)" % [
			filename, str(cycle_block["_to_year"]), str(cycle_block["_from_year"])
		])


## V1.6b. _validate_cycle()'s shape, one session on.
static func _validate_prices(prices_block: Dictionary, filename: String, errors: Array[String]) -> void:
	var keys := prices_block.keys()
	keys.sort()
	var expected := KNOWN_PRICES_KEYS.duplicate()
	expected.sort()
	if keys != expected:
		errors.append("%s: imported.prices must have exactly keys %s, got %s" % [filename, expected, keys])
		return

	for key in ["inflation_pct", "_from_year", "_to_year"]:
		var raw = prices_block[key]
		if not (typeof(raw) == TYPE_FLOAT or typeof(raw) == TYPE_INT):
			errors.append("%s: imported.prices.%s is not numeric" % [filename, key])
			return

	if typeof(prices_block["_excludes"]) != TYPE_ARRAY:
		errors.append("%s: imported.prices._excludes must be an array of years" % filename)
		return

	_check_range_float(
		prices_block["inflation_pct"], InflationK.ANCHOR_MIN, InflationK.ANCHOR_MAX,
		"imported.prices.inflation_pct", filename, errors
	)

	if int(prices_block["_to_year"]) <= int(prices_block["_from_year"]):
		errors.append("%s: imported.prices._to_year (%s) must be after _from_year (%s)" % [
			filename, str(prices_block["_to_year"]), str(prices_block["_from_year"])
		])


## Hex strings in, Colors out, validated here rather than at the draw call --
## a malformed colour should fail the load like every other bad field, not
## render as transparent black on the portrait card and be blamed on the theme.
static func _extract_colours(d: Dictionary, key: String, filename: String, errors: Array[String]) -> Array[Color]:
	var out: Array[Color] = []
	if not d.has(key) or typeof(d[key]) != TYPE_ARRAY:
		errors.append("%s: missing or invalid array field 'flag.%s'" % [filename, key])
		return out

	for entry in d[key]:
		if typeof(entry) != TYPE_STRING or not Color.html_is_valid(entry):
			errors.append("%s: flag.%s entry '%s' is not a valid hex colour" % [filename, key, str(entry)])
			continue
		out.append(Color.html(entry))

	if out.size() < 2:
		errors.append("%s: flag.%s needs at least two colours, found %d" % [filename, key, out.size()])
	return out


static func _extract_string(d: Dictionary, key: String, filename: String, errors: Array[String]) -> String:
	if not d.has(key) or typeof(d[key]) != TYPE_STRING:
		errors.append("%s: missing or invalid string field '%s'" % [filename, key])
		return ""
	return d[key]


static func _extract_bool(d: Dictionary, key: String, filename: String, errors: Array[String]) -> bool:
	if not d.has(key) or typeof(d[key]) != TYPE_BOOL:
		errors.append("%s: missing or invalid bool field '%s'" % [filename, key])
		return false
	return d[key]


static func _extract_int(d: Dictionary, key: String, path: String, filename: String, errors: Array[String]) -> int:
	if not d.has(key) or not (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT):
		errors.append("%s: missing or invalid numeric field '%s'" % [filename, path])
		return 0
	return int(d[key])


static func _extract_float(d: Dictionary, key: String, path: String, filename: String, errors: Array[String]) -> float:
	if not d.has(key) or not (typeof(d[key]) == TYPE_INT or typeof(d[key]) == TYPE_FLOAT):
		errors.append("%s: missing or invalid numeric field '%s'" % [filename, path])
		return 0.0
	return float(d[key])


static func _extract_dict(d: Dictionary, key: String, filename: String, errors: Array[String]) -> Dictionary:
	if not d.has(key) or typeof(d[key]) != TYPE_DICTIONARY:
		errors.append("%s: missing or invalid object field '%s'" % [filename, key])
		return {}
	return d[key]


## Optional where every other block in this file is required: an absent
## `project_sites` is a nation with no sites, not an error. What IS an error is a
## malformed one, because a coordinate dropped silently is a marker that never
## appears with nothing anywhere to say why.
##
## Whether a key names a real project is NOT checked here. This parses one nation
## file and the loader has no project list at that point; tests/test_map_markers.gd
## checks the keys against data/project-actions/ instead, which is also where the
## stronger claim lives -- that the point is inside the nation's own polygon.
static func _extract_project_sites(d: Dictionary, filename: String, errors: Array[String]) -> Dictionary:
	var out := {}
	if not d.has("project_sites"):
		return out
	if typeof(d["project_sites"]) != TYPE_DICTIONARY:
		errors.append("%s: invalid object field 'project_sites'" % filename)
		return out

	var raw: Dictionary = d["project_sites"]
	for key in raw.keys():
		var pair = raw[key]
		if typeof(pair) != TYPE_ARRAY or pair.size() != 2:
			errors.append("%s: project_sites.%s must be [lon, lat]" % [filename, str(key)])
			continue
		var lon := float(pair[0])
		var lat := float(pair[1])
		if lon < -180.0 or lon > 180.0 or lat < -90.0 or lat > 90.0:
			errors.append(
				"%s: project_sites.%s = [%s, %s] is not a lon/lat"
				% [filename, str(key), str(lon), str(lat)]
			)
			continue
		out[String(key)] = Vector2(lon, lat)
	return out


static func _check_range_int(value: int, min_v: int, max_v: int, path: String, filename: String, errors: Array[String]) -> void:
	if value < min_v or value > max_v:
		errors.append("%s: %s = %d out of range [%d, %d]" % [filename, path, value, min_v, max_v])


static func _check_range_float(value: float, min_v: float, max_v: float, path: String, filename: String, errors: Array[String]) -> void:
	if value < min_v or value > max_v:
		errors.append("%s: %s = %s out of range [%s, %s]" % [filename, path, str(value), str(min_v), str(max_v)])
