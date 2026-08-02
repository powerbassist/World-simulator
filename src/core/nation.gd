class_name Nation
extends RefCounted

## Typed, validated in-memory representation of one data/nations/*.json file.
## Built and range-checked by from_dict(); see docs/data-architecture.md for
## the schema and the import script's ownership boundary on `imported`.

const C = preload("res://src/sim/economy_constants.gd")

const KNOWN_IMPORTED_KEYS: Array[String] = [
	"_source", "_year", "_usd_eur", "population", "gdp_eur_bn",
	"unemployment_pct", "sectors",
]
const KNOWN_SECTOR_KEYS: Array[String] = ["agriculture", "industry", "services"]
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

var leader_name: String = ""
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
var head_of_government_name: String = ""

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
var head_of_state_name: String = ""
var head_of_state_term_years: int = 0
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
	n.leader_name = _extract_string(leader, "name", filename, errors)
	n.leader_title = _extract_string(leader, "title", filename, errors)
	n.leader_party_id = _extract_string(leader, "party", filename, errors)

	var flag: Dictionary = _extract_dict(d, "flag", filename, errors)
	n.flag_layout = _extract_string(flag, "layout", filename, errors)
	if n.flag_layout != "" and not KNOWN_FLAG_LAYOUTS.has(n.flag_layout):
		errors.append("%s: flag.layout '%s' is not one of %s" % [filename, n.flag_layout, str(KNOWN_FLAG_LAYOUTS)])
	n.flag_bands = _extract_colours(flag, "bands", filename, errors)

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
	n.head_of_state_name = _extract_string(head_of_state, "name", filename, errors)
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
	n.head_of_government_name = _extract_string(formation, "head_of_government_name", filename, errors)

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


static func _check_range_int(value: int, min_v: int, max_v: int, path: String, filename: String, errors: Array[String]) -> void:
	if value < min_v or value > max_v:
		errors.append("%s: %s = %d out of range [%d, %d]" % [filename, path, value, min_v, max_v])


static func _check_range_float(value: float, min_v: float, max_v: float, path: String, filename: String, errors: Array[String]) -> void:
	if value < min_v or value > max_v:
		errors.append("%s: %s = %s out of range [%s, %s]" % [filename, path, str(value), str(min_v), str(max_v)])
