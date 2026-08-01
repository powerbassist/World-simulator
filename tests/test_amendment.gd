extends SceneTree

## Headless test: godot --headless --script res://tests/test_amendment.gd
## Non-zero exit on any failure.
##
## V1.2c: constitutional amendment. An amendment is a law with three
## additions -- constitutional, systems, effects.institutional -- not a
## second pipeline, so this file exercises the real Legislature.propose()
## path throughout rather than re-deriving the threshold math. See
## docs/amendment-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Law = preload("res://src/core/law.gd")
const PoliticalSystem = preload("res://src/core/political_system.gd")

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

	_check_amendment_only_proposable_under_its_own_systems()
	_check_amendment_reads_nations_own_threshold()
	_check_amendment_writes_institutional_field()
	_check_writing_amendment_rule_changes_a_later_vote()
	_check_article_49_3_cannot_force_an_amendment()
	_check_determinism()
	_check_load_bearing_cross_check()

	_finish()


func _new_state(player_id := "FRA"):
	var state = GameState.new_game(_loader, player_id)
	if not state.errors.is_empty():
		_fail("new_game(%s) reported errors: %s" % [player_id, state.errors])
	state.year = GAME_START_YEAR
	state.month = GAME_START_MONTH
	return state


func _find_law(law_id: String):
	for law in _loader.laws:
		if law.id == law_id:
			return law
	return null


## FRA's system is semi_presidential_republic; a constitutional_monarchy-only
## amendment must not appear in France's available() list, and vice versa.
func _check_amendment_only_proposable_under_its_own_systems() -> void:
	var state = _new_state("FRA")
	var ns = state.player()

	var fra_law = _find_law("abolish_term_limits")
	var monarchy_law = _find_law("constructive_confidence_reform")
	if fra_law == null or monarchy_law == null:
		_fail("expected fixture amendments not found in data/laws/amendments.json")
		return

	var available: Array = Legislature.available(ns, _loader.laws)
	var ids := {}
	for law in available:
		ids[law.id] = true

	if not ids.has(fra_law.id):
		_fail("abolish_term_limits (semi_presidential_republic) is not proposable for FRA")
	if ids.has(monarchy_law.id):
		_fail("constructive_confidence_reform (constitutional_monarchy only) is proposable for FRA")


## resolve_vote() must read the PROPOSING nation's own ns.amendment_rule, not
## a fixed fraction -- proven by giving the same coalition just enough seats
## to clear France's real 3/5 (0.60) and showing that is not enough for a
## hypothetical two_thirds nation under the identical seat split.
func _check_amendment_reads_nations_own_threshold() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties["FRA"]
	var law = _find_law("abolish_term_limits")
	if law == null:
		return

	# Build a two-party assembly at exactly 62% yes -- above 3/5, below 2/3.
	# Ranked by real support() (bonus included), not spatial_support(), so the
	# "no" seat block is actually a no vote rather than an arbitrary party
	# that happens to like the bill too.
	var yes_party := ""
	var no_party := ""
	var best_support := -2.0
	var worst_support := 2.0
	for party in party_list:
		var s: float = Legislature.support(ns, party, law)
		if s > best_support:
			best_support = s
			yes_party = party.id
		if s < worst_support:
			worst_support = s
			no_party = party.id
	ns.seats_by_party = {}
	for party in party_list:
		ns.seats_by_party[party.id] = 0
	var yes_seats := int(round(0.62 * float(ns.assembly_seats)))
	ns.seats_by_party[yes_party] = yes_seats
	ns.seats_by_party[no_party] = ns.assembly_seats - yes_seats

	ns.amendment_rule = "three_fifths"
	var result_35 := Legislature.resolve_vote(ns, party_list, law)
	if not result_35["passed"]:
		_fail("62%% yes did not pass under three_fifths (0.60): %s" % [result_35])

	ns.amendment_rule = "two_thirds"
	var result_23 := Legislature.resolve_vote(ns, party_list, law)
	if result_23["passed"]:
		_fail("62%% yes passed under two_thirds (0.667), which it should not clear")


## Passing abolish_term_limits writes ns.term_limit = 0, and elections.gd's
## own executive-verdict branch -- not a re-derivation of it -- reads the new
## value at the next executive election.
func _check_amendment_writes_institutional_field() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	ns.term_limit = 2
	ns.terms_served = 2  # would be termed out under the ORIGINAL limit

	var law = _find_law("abolish_term_limits")
	if law == null:
		return
	Legislature.apply(state, ns, law, _loader)

	if ns.term_limit != 0:
		_fail("apply(abolish_term_limits) left term_limit at %d, expected 0" % ns.term_limit)


## The reader, not just the field: with the limit abolished, elections.gd's
## own termed-out branch must not fire for an incumbent who would have been
## termed out under the original limit.
func _check_writing_amendment_rule_changes_a_later_vote() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties["FRA"]

	ns.term_limit = 2
	ns.terms_served = 2
	ns.next_executive_year = state.year
	ns.next_executive_month = state.month

	var law = _find_law("abolish_term_limits")
	if law == null:
		return
	Legislature.apply(state, ns, law, _loader)

	Elections.tick_month(state, _loader)
	if not ns.in_government:
		_fail("incumbent was termed out at the executive verdict despite abolish_term_limits having passed")


## Article 89's revision procedure has no executive bypass -- Article 49.3
## must refuse a constitutional law rather than adopt it without a vote.
func _check_article_49_3_cannot_force_an_amendment() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var law = _find_law("abolish_term_limits")
	if law == null:
		return

	var before_term_limit: int = ns.term_limit
	var result := Legislature.propose(state, _loader, law, true)

	if result.get("passed", false):
		_fail("Article 49.3 adopted a constitutional amendment; it must refuse instead")
	if not result.get("refused", false):
		_fail("forcing a constitutional amendment did not report 'refused': %s" % [result])
	if ns.term_limit != before_term_limit:
		_fail("forcing a constitutional amendment mutated state despite being refused")


## Same state, resolved twice through the amendment branch, identical result --
## the same property test_legislature.gd's _check_determinism() proves for the
## ordinary majority types.
func _check_determinism() -> void:
	var state = _new_state("FRA")
	var ns = state.player()
	var party_list: Array = _loader.parties["FRA"]
	var law = _find_law("abolish_term_limits")
	if law == null:
		return

	var a := Legislature.resolve_vote(ns, party_list, law)
	var b := Legislature.resolve_vote(ns, party_list, law)
	if a["passed"] != b["passed"] or a["yes_seats"] != b["yes_seats"]:
		_fail("determinism: amendment resolve_vote differed between two resolutions of the same state")


## The check that makes the amendment/template cross-check load-bearing: a
## fixture amendment naming a system whose allowed_censure_rules does not
## include the value the amendment would write must fail to load, the same
## proof tests/test_political_systems.gd gives for a nation's own flat field.
func _check_load_bearing_cross_check() -> void:
	var fixture_loader := DataLoader.new()
	fixture_loader.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://data/eu_parliament.json", "res://tests/fixtures/laws_bad_amendment",
	)
	var named_both := false
	for e in fixture_loader.errors:
		if e.find("censure_rule") != -1 and e.find("semi_presidential_republic") != -1:
			named_both = true
	if not named_both:
		_fail("an amendment writing a censure_rule illegal for its own named system did not fail to load, or did not name both: %s" % [fixture_loader.errors])


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_amendment: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
