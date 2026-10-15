extends SceneTree

## Headless test: godot --headless --script res://tests/test_legislature.gd
## Non-zero exit on any failure.
##
## Same discipline as test_elections.gd: every check runs the real tick
## sequence and reads what actually happened, rather than arguing that a
## formula implies an outcome.

## PRELOADED RATHER THAN USED AS A BARE `class_name`, and the shadowing is deliberate --
## src/core/data_loader.gd:9 does exactly this with the same identifier. AGENTS.md's
## gotcha is that a global class name does not resolve before
## .godot/global_script_class_cache.cfg exists, and `--headless --script` does not
## generate one -- so `Law.from_dict()` parsed here only because this machine had run
## the editor. On a fresh clone tools/run_tests.sh failed on this file and on no other,
## found by running the suite in a clean worktree while checking the V5 autoload fix.
const Law = preload("res://src/core/law.gd")
const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Companies = preload("res://src/sim/companies.gd")
const EK = preload("res://src/sim/economy_constants.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")

const GAME_START_YEAR := 2026
const GAME_START_MONTH := 1

var _failures: Array[String] = []
var _loader: DataLoader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_template_count_and_themes()
	_check_extra_law_is_data_only_edit()
	_check_vote_follows_assembly_composition()
	_check_majority_boundaries()
	_check_support_monotone_in_distance()
	_check_determinism()
	_check_failed_vote_names_opponents()
	_check_passed_law_moves_economy_and_opinion()
	_check_finite_over_ten_years_with_every_law_applied()
	_check_business_law_reaches_the_company_channel()
	_check_the_company_channel_refuses_what_it_must()

	_finish()


func _new_state(player_id := "FRA"):
	var state = GameState.new_game(_loader, player_id)
	if not state.errors.is_empty():
		_fail("new_game(%s) reported errors: %s" % [player_id, state.errors])
	state.year = GAME_START_YEAR
	state.month = GAME_START_MONTH
	return state


## At least sixteen templates, spanning tax, labour, social and institutional.
func _check_template_count_and_themes() -> void:
	if _loader.laws.size() < 16:
		_fail("expected at least 16 law templates, got %d" % _loader.laws.size())

	var themes := {}
	for law in _loader.laws:
		themes[law.theme] = true
	for theme in ["tax", "labour", "social", "institutional", "business"]:
		if not themes.has(theme):
			_fail("no law template found with theme '%s'" % theme)


## Adding a seventeenth law requires only a data/laws/ edit — a separate laws
## directory with one extra file loads, validates and behaves identically.
func _check_extra_law_is_data_only_edit() -> void:
	var extra := DataLoader.new()
	extra.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://tests/fixtures/laws_extra"
	)
	if not extra.errors.is_empty():
		_fail("extra laws directory did not load cleanly: %s" % [extra.errors])
		return

	var found := false
	for law in extra.laws:
		if law.id == "test_fixture_extra_law":
			found = true
	if not found:
		_fail("the fixture's extra law was not loaded from tests/fixtures/laws_extra")

	var state = GameState.new_game(extra, "FRA")
	if not state.errors.is_empty():
		_fail("new_game with the extra-laws loader reported errors: %s" % [state.errors])
		return
	var ns = state.player()
	var available: Array = Legislature.available(ns, extra.laws)
	var proposable := false
	for law in available:
		if law.id == "test_fixture_extra_law":
			proposable = true
	if not proposable:
		_fail("the fixture's extra law is not proposable at new-game")


## The same law, against two different assemblies, produces two different
## outcomes — the vote is a function of assembly composition, not a coin flip.
func _check_vote_follows_assembly_composition() -> void:
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties["FRA"]
	var law = _find_law("retirement_age_reform")
	if law == null:
		_fail("fixture law 'retirement_age_reform' not found")
		return

	var real_result := Legislature.resolve_vote(ns, party_list, law)

	# Build a hostile assembly: every seat given to the party furthest from the
	# law's own position.
	var furthest_id := ""
	var furthest_dist := -1.0
	for party in party_list:
		var support: float = Legislature.support(ns, party, law)
		var dist: float = -support
		if dist > furthest_dist:
			furthest_dist = dist
			furthest_id = party.id

	var hostile_ns = ns.duplicate_state()
	hostile_ns.seats_by_party = {}
	for party in party_list:
		hostile_ns.seats_by_party[party.id] = 0
	hostile_ns.seats_by_party[furthest_id] = ns.assembly_seats

	var hostile_result := Legislature.resolve_vote(hostile_ns, party_list, law)

	if real_result["passed"] == hostile_result["passed"] and real_result["yes_seats"] == hostile_result["yes_seats"]:
		_fail("resolve_vote produced an identical outcome against a real and a deliberately hostile assembly")


## THE EXACT BOUNDARIES of the two fixed thresholds, which nothing pinned: the
## suite audit's mutations M1 (a simple-majority tie passes, `>` -> `>=`) and M2
## (exactly two thirds fails, `>=` -> `>`) both kept the whole suite green. Two
## parties whose line and own conscience agree (so no seat rebels whatever their
## size) carry the whole assembly, sized to sit ON each boundary and one seat
## either side. 300 seats because 2/3 x 300 is exactly 200.0 in floating point --
## a total whose two thirds is not a whole number could not hold the boundary.
func _check_majority_boundaries() -> void:
	var state = _new_state()
	var ns = state.player().duplicate_state()
	var party_list: Array = _loader.parties["FRA"]
	var law = _find_law("retirement_age_reform")
	if law == null:
		_fail("fixture law 'retirement_age_reform' not found")
		return
	var yes_id := ""
	var no_id := ""
	for party in party_list:
		var line := Legislature.vote_of(Legislature.support(ns, party, law))
		if line != Legislature.vote_of(Legislature.spatial_support(ns, party, law)):
			continue
		if line == "yes" and yes_id == "":
			yes_id = party.id
		elif line == "no" and no_id == "":
			no_id = party.id
	if yes_id == "" or no_id == "":
		_fail("no rebel-free yes and no parties on 'retirement_age_reform' (yes '%s', no '%s') -- the fixture moved" % [yes_id, no_id])
		return

	var saved_majority: String = law.majority
	ns.assembly_seats = 300
	# [majority, yes seats, no seats, must pass]
	for c in [["simple", 150, 150, false], ["simple", 151, 149, true],
			["two_thirds", 200, 100, true], ["two_thirds", 199, 101, false]]:
		law.majority = c[0]
		ns.seats_by_party = {}
		for party in party_list:
			ns.seats_by_party[party.id] = 0
		ns.seats_by_party[yes_id] = c[1]
		ns.seats_by_party[no_id] = c[2]
		var result := Legislature.resolve_vote(ns, party_list, law)
		if result["yes_seats"] != c[1] or result["no_seats"] != c[2]:
			_fail("%s %d-%d: the vote counted %d-%d -- the boundary case is not the one asked" % [c[0], c[1], c[2], result["yes_seats"], result["no_seats"]])
		elif bool(result["passed"]) != c[3]:
			_fail("%s majority, %d yes to %d no of 300: passed=%s, expected %s" % [c[0], c[1], c[2], result["passed"], c[3]])
	# The loader's law objects are shared with every later check.
	law.majority = saved_majority


## Support falls monotonically as a law's own position moves further from a
## fixed party's ideology slot -- exercising the real Legislature.support(),
## not a re-derivation of its formula.
func _check_support_monotone_in_distance() -> void:
	var state = _new_state()
	var ns = state.player()
	var Law = load("res://src/core/law.gd")
	var party = _loader.parties["FRA"][0]  # centrist_liberal, economic 0.1, social -0.3

	var previous := 2.0  # above the maximum possible support
	for social_offset in [0.0, 0.3, 0.6, 0.9, 1.2]:
		var law = Law.new()
		law.id = "probe"
		law.majority = "simple"
		law.position = {"economic": 0.1, "social": -0.3 + social_offset}

		var s: float = Legislature.support(ns, party, law)
		if s > previous:
			_fail("support did not fall monotonically with distance: %.4f at offset %.2f followed %.4f" % [s, social_offset, previous])
		previous = s


## Same state, resolved twice, identical result.
func _check_determinism() -> void:
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties["FRA"]
	var law = _find_law("corporate_tax_cut")

	var a := Legislature.resolve_vote(ns, party_list, law)
	var b := Legislature.resolve_vote(ns, party_list, law)

	if a["passed"] != b["passed"] or a["yes_seats"] != b["yes_seats"] or a["party_votes"] != b["party_votes"]:
		_fail("determinism: resolve_vote differed between two resolutions of the same state")


## A law the assembly rejects names each opposing party after propose().
func _check_failed_vote_names_opponents() -> void:
	var state = _new_state()
	var ns = state.player()
	var party_list: Array = _loader.parties["FRA"]

	# Force a hostile assembly against a law, then propose it for real through
	# the same path the UI uses.
	var law = _find_law("working_time_reduction")
	var furthest_id := ""
	var furthest_dist := -1.0
	for party in party_list:
		var support: float = Legislature.support(ns, party, law)
		if -support > furthest_dist:
			furthest_dist = -support
			furthest_id = party.id
	ns.seats_by_party = {}
	for party in party_list:
		ns.seats_by_party[party.id] = 0
	ns.seats_by_party[furthest_id] = ns.assembly_seats

	var result := Legislature.propose(state, _loader, law)
	if result["passed"]:
		_fail("expected the hostile assembly to reject the law, but it passed")
		return

	var named_opponent := false
	for party_id in result["party_votes"]:
		if result["party_votes"][party_id] == "no" and party_id == furthest_id:
			named_opponent = true
	if not named_opponent:
		_fail("failed vote's party_votes did not name the opposing party '%s': %s" % [furthest_id, result["party_votes"]])

	if ns.last_law_result != result:
		_fail("ns.last_law_result was not set to the propose() result")


## Passing a law with both a budget effect and a bloc effect moves an economic
## number and an opinion number over the following months, against a
## do-nothing control run of the same length. carbon_levy passes against FRA's
## real starting assembly (centrist + social-democratic + green coalition), so
## this exercises the real propose() path rather than a hand-built one.
func _check_passed_law_moves_economy_and_opinion() -> void:
	var control = _new_state()
	var treated = _new_state()

	var law = _find_law("carbon_levy")
	if law == null:
		_fail("fixture law 'carbon_levy' not found")
		return

	var result := Legislature.propose(treated, _loader, law)
	if not result["passed"]:
		_fail("carbon_levy failed to pass against FRA's starting assembly, cannot test its effects")
		return

	for _i in range(12):
		Economy.tick_month(control)
		Budget.tick_month(control)
		Opinion.tick_month(control)
		Economy.tick_month(treated)
		Budget.tick_month(treated)
		Opinion.tick_month(treated)

	var c = control.player()
	var t = treated.player()

	if is_equal_approx(t.deficit_pct_gdp, c.deficit_pct_gdp):
		_fail("passing carbon_levy did not move the deficit relative to a do-nothing control")

	var c_rural: float = float(c.bloc_approval.get("rural", 0.0))
	var t_rural: float = float(t.bloc_approval.get("rural", 0.0))
	if t_rural >= c_rural:
		_fail("passing carbon_levy did not lower rural approval relative to control (treated %.2f, control %.2f)" % [t_rural, c_rural])


## Every field stays finite over ten years with every authored law applied at
## once, the same shape test_economy.gd uses for an absurd budget.
func _check_finite_over_ten_years_with_every_law_applied() -> void:
	var state = _new_state()

	for law in _loader.laws:
		# Ignore preconditions here on purpose -- the point is to stress-test
		# the accumulators, not to reproduce a plausible playthrough.
		Legislature.apply(state, state.player(), law, _loader)

	for month in range(120):
		Economy.tick_month(state)
		Budget.tick_month(state)
		Opinion.tick_month(state)
		Discipline.tick_month(state, _loader)
		Legislature.tick_month(state, _loader)

		var ns = state.player()
		if not is_finite(ns.gdp_eur_bn) or not is_finite(ns.debt_eur_bn) or not is_finite(ns.overall_approval_pct):
			_fail("non-finite value at month %d after applying every law: gdp=%s debt=%s approval=%s" % [
				month, ns.gdp_eur_bn, ns.debt_eur_bn, ns.overall_approval_pct
			])
			return
		if ns.unemployment_pct < 0.0 or ns.unemployment_pct > 100.0:
			_fail("unemployment out of sane range at month %d: %s" % [month, ns.unemployment_pct])
			return


func _find_law(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null


# --- V1.4b: effects.company ------------------------------------------------------

## The channel a subsidy reaches through Companies.execute(), reached from the
## other side: a `business` law survives a division and writes a sector burden.
## The whole of the a/b split, asserted rather than only argued.
func _check_business_law_reaches_the_company_channel() -> void:
	var state = _new_state()
	var ns = state.player()
	var law = _find_law("emissions_standards")
	if law == null:
		_fail("fixture law 'emissions_standards' not found")
		return
	if not law.effects.has("company"):
		_fail("emissions_standards carries no effects.company")
		return

	Legislature.apply(state, ns, law, _loader)
	if float(ns.regulation_burden.get("industry", 0.0)) <= 0.0:
		_fail("applying emissions_standards left industry's burden at %s" % [
			str(ns.regulation_burden.get("industry", 0.0))
		])
	# And it reached nothing else the channel does not own.
	if not ns.companies.is_empty() and Companies.share_of(ns, "FRA_aurignac") != 0.14:
		_fail("a regulation moved a firm's share, which is the subsidy's channel")


## The load-time refusals. Each is a rule this session states in prose somewhere,
## made mechanical -- a convention only the docs enforce is one an author breaks by
## not reading them, which is the argument docs/coercion-model.md's separator makes.
func _check_the_company_channel_refuses_what_it_must() -> void:
	var sectors: Array = EK.SECTOR_TREND.keys()

	var cases := {
		"both channels": {
			"company": {"sector": "industry", "burden": 0.3},
			"structural_unemployment_pct": 0.2,
		},
		"an unknown sector": {"company": {"sector": "tourism", "burden": 0.3}},
		"a burden of zero": {"company": {"sector": "industry", "burden": 0.0}},
		"a burden past the clamp": {"company": {"sector": "industry", "burden": 9.0}},
		"a firm id": {"company": {"sector": "industry", "burden": 0.3, "company_id": "FRA_aurignac"}},
		"a missing burden": {"company": {"sector": "industry"}},
	}

	for label in cases.keys():
		var errors: Array[String] = []
		Law.from_dict(
			{
				"id": "probe_%s" % label, "name": "Probe", "theme": "business",
				"summary": "", "position": {"economic": 0.0, "social": 0.0},
				"majority": "simple", "effects": cases[label],
			},
			"test_legislature.gd", errors,
			EK.TAX_KEYS, EK.SPENDING_KEYS, OpinionK.BLOC_KEYS, sectors
		)
		if errors.is_empty():
			_fail("a law with %s loaded without an error" % label)

	# ...and the shape that must still load.
	var ok: Array[String] = []
	Law.from_dict(
		{
			"id": "probe_ok", "name": "Probe", "theme": "business", "summary": "",
			"position": {"economic": 0.0, "social": 0.0}, "majority": "simple",
			"effects": {"company": {"sector": "services", "burden": -0.25}},
		},
		"test_legislature.gd", ok,
		EK.TAX_KEYS, EK.SPENDING_KEYS, OpinionK.BLOC_KEYS, sectors
	)
	if not ok.is_empty():
		_fail("a valid deregulation law was refused: %s" % [ok])


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_legislature: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
