extends SceneTree

## Headless test: godot --headless --script res://tests/test_transition.gd
## Non-zero exit on any failure.
##
## V1.2d: system transition -- the same amendment mechanism V1.2c built,
## pointed at effects.institutional.system_id. Exercises the real
## Legislature.available()/apply() path, the same discipline
## tests/test_amendment.gd uses rather than re-deriving the threshold math.
## See docs/transition-model.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Government = preload("res://src/sim/government.gd")

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

	_check_gbr_playable_and_loads_clean()
	_check_transition_refused_where_constitution_forbids_it()
	_check_transition_available_for_gbr()
	_check_transition_writes_every_field_legally_under_the_target()
	_check_derived_president_is_largest_partys_leader()
	_check_restoration_proposable_after_abolition()
	_check_load_bearing_cross_check_incomplete_bundle()
	_check_load_bearing_cross_check_illegal_target()
	_check_held_amendment_lapses_after_a_transition()

	_finish()


func _new_state(player_id: String):
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


## GBR is now data/nations/GBR.json's playable:true -- the third playable
## nation, and a headless run must not fire any France/Germany assumption.
func _check_gbr_playable_and_loads_clean() -> void:
	if not _loader.nations.has("GBR") or not _loader.nations["GBR"].playable:
		_fail("GBR.json is not marked playable")
		return

	var state = _new_state("GBR")
	if not state.errors.is_empty():
		return  # already reported by _new_state

	for _i in range(24):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1


## France (Art. 89 §5), Germany (Art. 79(3)), Italy (Art. 139) and Austria
## each declare permits_system_change: false -- a transition amendment must
## not appear in available() for any of them, even though the amendment's own
## `systems` filter would otherwise let one of them propose one (there is no
## constitutional_monarchy nation among them today, but the gate must hold on
## its own, not depend on that coincidence).
func _check_transition_refused_where_constitution_forbids_it() -> void:
	var law = _find_law("abolish_the_monarchy")
	if law == null:
		_fail("abolish_the_monarchy not found in data/laws/amendments.json")
		return

	for nation_id in ["FRA", "DEU", "ITA", "AUT"]:
		var state = _new_state(nation_id)
		var ns = state.player()
		if ns.permits_system_change:
			_fail("%s carries permits_system_change: true, expected false" % nation_id)
			continue
		# Force the nation's own system_id to match the amendment's `systems`
		# filter, isolating the permits_system_change gate from the ordinary
		# systems filter that would refuse it anyway for these four.
		ns.system_id = "constitutional_monarchy"
		var available: Array = Legislature.available(ns, _loader.laws)
		for l in available:
			if l.id == law.id:
				_fail("%s: abolish_the_monarchy is available despite permits_system_change: false" % nation_id)


## GBR permits a system change and starts constitutional_monarchy --
## abolish_the_monarchy must be proposable, and restore_the_monarchy (which
## targets parliamentary_republic) must not be, yet.
func _check_transition_available_for_gbr() -> void:
	var state = _new_state("GBR")
	var ns = state.player()
	var available: Array = Legislature.available(ns, _loader.laws)
	var ids := {}
	for l in available:
		ids[l.id] = true

	if not ids.has("abolish_the_monarchy"):
		_fail("abolish_the_monarchy is not proposable for GBR")
	if ids.has("restore_the_monarchy"):
		_fail("restore_the_monarchy (parliamentary_republic only) is proposable for GBR before any transition")


## The completeness rule proven live: applying abolish_the_monarchy must leave
## GBR's institutional state entirely legal under parliamentary_republic --
## the same cross-check data_loader.gd's _validate_political_system() runs
## for a nation file, run here against LIVE post-transition state.
func _check_transition_writes_every_field_legally_under_the_target() -> void:
	var state = _new_state("GBR")
	var ns = state.player()
	var law = _find_law("abolish_the_monarchy")
	if law == null:
		return

	Legislature.apply(state, ns, law, _loader)

	if ns.system_id != "parliamentary_republic":
		_fail("apply(abolish_the_monarchy) left system_id at '%s', expected parliamentary_republic" % ns.system_id)
		return

	var system = _loader.political_systems.get(ns.system_id)
	if system == null:
		_fail("system_id '%s' names no loaded template" % ns.system_id)
		return

	if not system.allowed_formation_methods.has(ns.formation_method):
		_fail("post-transition formation_method '%s' is not legal under %s" % [ns.formation_method, ns.system_id])
	if not system.allowed_censure_rules.has(ns.censure_rule):
		_fail("post-transition censure_rule '%s' is not legal under %s" % [ns.censure_rule, ns.system_id])
	if not system.allowed_dissolution_rules.has(ns.dissolution_rule):
		_fail("post-transition dissolution_rule '%s' is not legal under %s" % [ns.dissolution_rule, ns.system_id])
	if not system.allowed_amendment_rules.has(ns.amendment_rule):
		_fail("post-transition amendment_rule '%s' is not legal under %s" % [ns.amendment_rule, ns.system_id])
	if not system.allowed_head_of_state_kinds.has(ns.head_of_state_kind):
		_fail("post-transition head_of_state_kind '%s' is not legal under %s" % [ns.head_of_state_kind, ns.system_id])
	if ns.term_limit > 0 and not system.permits_term_limit:
		_fail("post-transition term_limit %d is set but %s does not permit one" % [ns.term_limit, ns.system_id])

	# lose_condition happens to be identical for constitutional_monarchy and
	# parliamentary_republic (both party_not_largest) -- checked anyway, since
	# apply() re-reads it off the target rather than leaving the old value.
	if ns.lose_condition != system.lose_condition:
		_fail("post-transition lose_condition '%s' does not match the target template's '%s'" % [ns.lose_condition, system.lose_condition])


## An elected_president's holder is DERIVED from the largest party's own leader,
## not authored -- proven against the real largest party, not a re-derivation of
## "largest". Since U6b it is derived as a person ID, and the other branch is
## derived too: a restored monarch comes from the nation's own pretender rather
## than from a name the law carried, which is checked below.
func _check_derived_president_is_largest_partys_leader() -> void:
	var state = _new_state("GBR")
	var ns = state.player()
	var party_list: Array = _loader.parties.get("GBR", [])
	var law = _find_law("abolish_the_monarchy")
	if law == null:
		return

	var largest_id := Government.largest_party_id(ns, party_list)
	var expected_person := ""
	for party in party_list:
		if party.id == largest_id:
			expected_person = party.leader_person_id

	Legislature.apply(state, ns, law, _loader)

	if ns.head_of_state_kind != "elected_president":
		_fail("post-transition head_of_state_kind is '%s', expected elected_president" % ns.head_of_state_kind)
	if ns.head_of_state_person_id != expected_person:
		_fail("derived president is '%s', expected the largest party's leader '%s'" % [ns.head_of_state_person_id, expected_person])
	var expected_next_year := GAME_START_YEAR + 5  # abolish_the_monarchy's term_years
	if ns.head_of_state_next_year != expected_next_year or ns.head_of_state_next_month != GAME_START_MONTH:
		_fail("derived president's clock is %d-%02d, expected %d-%02d" % [ns.head_of_state_next_year, ns.head_of_state_next_month, expected_next_year, GAME_START_MONTH])


## restore_the_monarchy targets parliamentary_republic -- only proposable
## once abolish_the_monarchy has actually moved a GBR-shaped nation there.
func _check_restoration_proposable_after_abolition() -> void:
	var state = _new_state("GBR")
	var ns = state.player()
	var abolish = _find_law("abolish_the_monarchy")
	var restore = _find_law("restore_the_monarchy")
	if abolish == null or restore == null:
		_fail("expected fixture transition amendments not found in data/laws/amendments.json")
		return

	Legislature.apply(state, ns, abolish, _loader)

	var available: Array = Legislature.available(ns, _loader.laws)
	var ids := {}
	for l in available:
		ids[l.id] = true
	if not ids.has(restore.id):
		_fail("restore_the_monarchy is not proposable for a transitioned GBR")


## Mirrors tests/test_amendment.gd's _check_load_bearing_cross_check(): a
## system_id write with the rest of the required bundle missing must fail to
## load, naming the law and the missing field.
func _check_load_bearing_cross_check_incomplete_bundle() -> void:
	var fixture_loader := DataLoader.new()
	fixture_loader.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://tests/fixtures/laws_bad_transition",
	)
	var named := false
	for e in fixture_loader.errors:
		if e.find("test_fixture_incomplete_transition") != -1 and e.find("formation_method") != -1:
			named = true
	if not named:
		_fail("a system_id write missing the rest of the required bundle did not fail to load, or did not name the missing field: %s" % [fixture_loader.errors])


## A COMPLETE bundle, but a field illegal under the TARGET system, must also
## fail to load -- proving the check is against the target, not against the
## systems the amendment is proposed under (which do permit the value, by
## construction of the fixture).
func _check_load_bearing_cross_check_illegal_target() -> void:
	var fixture_loader := DataLoader.new()
	fixture_loader.load_all(
		"res://data/nations", "res://data/geo/europe.geojson", "res://data/parties",
		"res://tests/fixtures/laws_bad_transition",
	)
	var named := false
	for e in fixture_loader.errors:
		if e.find("formation_method") != -1 and e.find("parliamentary_republic") != -1:
			named = true
	if not named:
		_fail("a transition bundle illegal under its own target system did not fail to load, or did not name both: %s" % [fixture_loader.errors])


## V5.0d. A bill the upper house holds is applied when the hold runs out, and the
## constitutional gate available() runs at proposal was not re-run then -- so a GBR
## amendment authored for a monarchy, released after the Republic Act, wrote a
## dissolution rule the republic's template refuses. It lapses instead; the same
## for a referendum that settles after the system changed.
func _check_held_amendment_lapses_after_a_transition() -> void:
	var state = _new_state("GBR")
	var ns = state.player()
	var abolish = _find_law("abolish_the_monarchy")
	var reform = _find_law("executive_dissolution_reform")
	if abolish == null or reform == null:
		_fail("abolish_the_monarchy or executive_dissolution_reform not found")
		return
	ns.held_bills[reform.id] = {"months": 1, "origin": "player"}
	Legislature.apply(state, ns, abolish, _loader)
	var dissolution_after_transition: String = ns.dissolution_rule
	Legislature.tick_month(state, _loader)
	if ns.held_bills.has(reform.id):
		_fail("the held amendment was not released at the end of its hold")
	if ns.dissolution_rule != dissolution_after_transition:
		_fail("a held monarchy amendment released under %s wrote dissolution_rule '%s'" % [ns.system_id, ns.dissolution_rule])
	if bool(ns.last_law_result.get("passed", true)):
		_fail("the lapsed release is recorded as passed")

	Legislature._settle_referendum(state, ns, _loader, {"law_id": reform.id, "passed": true})
	if ns.dissolution_rule != dissolution_after_transition:
		_fail("a referendum settling a monarchy amendment under %s wrote dissolution_rule '%s'" % [ns.system_id, ns.dissolution_rule])


func _fail(message: String) -> void:
	if _failures.size() < 30:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_transition: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
