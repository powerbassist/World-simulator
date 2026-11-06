extends SceneTree

## V5.3 a + b, band B6 (docs/design/v5.3-ab.md section 6): the regard a new game
## starts with. The author: "plus ils sont opposés à tes idées plus ils ne
## t'apprécient pas", then a real-relations offset on top. The expected values are
## computed HERE from the band's own numbers (0.10, -0.25, -0.10) and the data the
## rule reads, never from the constants that build them: a test that read the
## constant would pass any slope.
##
##   - THE FORMULA, over every playable nation and every person with a party: own
##     party warm, the start coalition neutral, the others by distance and cordon. A
##     party's leader counts as a party person though the data gives them no party_id.
##   - THE ORDER: within one cordon status a farther party never starts warmer.
##   - THE SPEC'S FIGURES, hand-computed there, as literals.
##   - THE OFFSET: added, clamped, read only against the authored start leader.
##   - THE LOADER refuses a shipped number out of range or past two decimals.
##   - THE EDGES: never the president, never the staff, no press owner starts hostile,
##     and the first month's bond rule turns the coldest into rivals.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Person = preload("res://src/core/person.gd")
const President = preload("res://src/sim/president.gd")
const Shadows = preload("res://src/sim/shadows.gd")
const Staff = preload("res://src/sim/staff.gd")
const EK = preload("res://src/sim/election_constants.gd")

## The band's numbers, spelled out on purpose (see the header).
const OWN_PARTY := 0.10
const PER_DISTANCE := -0.25
const CORDON := -0.10
## "To two decimals", the band's own precision.
const TO_TWO_DECIMALS := 0.005

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_the_formula()
	_check_the_order_within_a_cordon_status()
	_check_the_specs_figures()
	_check_the_offset_is_added_and_clamped()
	_check_someone_else_seated_reads_no_offset()
	_check_the_loader_refuses_a_bad_offset()
	_check_no_press_owner_starts_hostile()
	_check_the_first_month_turns_the_coldest_into_rivals()

	if _failures.is_empty():
		print("test_start_regard: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


func _playable() -> Array:
	var out: Array = []
	for id in _loader.nations:
		if _loader.nations[id].playable:
			out.append(String(id))
	if out.size() < 4:
		_fail("only %d playable nations: the band reads four" % out.size())
	return out


## A person's party: the authored edge, else the party they lead, because a leader
## carries no party_id ("the party names them", src/ui/party_chip.gd).
func _party_of(nation_id: String, person_id: String) -> String:
	var own := String(_loader.person_by_id[person_id].party_id)
	if own != "":
		return own
	for party in _loader.parties.get(nation_id, []):
		if String(party.leader_person_id) == person_id:
			return String(party.id)
	return ""


func _party(nation_id: String, party_id: String):
	for party in _loader.parties.get(nation_id, []):
		if String(party.id) == party_id:
			return party
	return null


func _distance(a, b) -> float:
	var pa: Dictionary = EK.SLOT_POSITION[a.ideology_slot]
	var pb: Dictionary = EK.SLOT_POSITION[b.ideology_slot]
	return Vector2(float(pa["economic"]), float(pa["social"])).distance_to(Vector2(float(pb["economic"]), float(pb["social"])))


func _cordoned(a, b) -> bool:
	return a.excluded_partners.has(b.id) or b.excluded_partners.has(a.id)


## The rule as the band writes it, for one party against the president's.
func _ideas_term(ns, nation_id: String, party_id: String, own_id: String) -> float:
	if party_id == "":
		return 0.0
	if party_id == own_id:
		return OWN_PARTY
	if ns.coalition_party_ids.has(party_id):
		return 0.0
	var party = _party(nation_id, party_id)
	var own = _party(nation_id, own_id)
	return PER_DISTANCE * _distance(party, own) + (CORDON if _cordoned(party, own) else 0.0)


func _check_the_formula() -> void:
	for nation_id in _playable():
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.player()
		var leader := President.leader_id(ns)
		var own := _party_of(nation_id, leader)
		if own == "":
			_fail("%s: the president '%s' reads no party" % [nation_id, leader])
			continue
		var opponents := 0
		var colleagues := 0
		var opponent_leaders := 0
		for person in Staff.cast(_loader, nation_id):
			var pid := String(person.id)
			if pid == leader:
				if ns.person_rapport.has(pid):
					_fail("%s: the president has a regard for themself" % nation_id)
				continue
			var party := _party_of(nation_id, pid)
			var want := clampf(_ideas_term(ns, nation_id, party, own) + float(person.start_regard_offset), -1.0, 1.0)
			var got := President.rapport(ns, pid)
			if absf(got - want) >= TO_TWO_DECIMALS:
				_fail("%s: %s (%s) starts at %.4f, the rule says %.4f" % [nation_id, pid, party, got, want])
			if party == own:
				colleagues += 1
			elif party != "" and not ns.coalition_party_ids.has(party):
				opponents += 1
				if String(person.party_id) == "":
					opponent_leaders += 1
		# Positive controls: a rule read over nobody passes every line above.
		if colleagues == 0 or opponents == 0 or opponent_leaders == 0:
			_fail("%s: read %d colleagues, %d opponents, %d opposing leaders" % [nation_id, colleagues, opponents, opponent_leaders])
		var chief = Staff.chief_of(_loader, nation_id)
		if chief != null and ns.person_rapport.has(String(chief.id)):
			_fail("%s: the chief of staff was seeded" % nation_id)


func _check_the_order_within_a_cordon_status() -> void:
	for nation_id in _playable():
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.player()
		var own_id := _party_of(nation_id, President.leader_id(ns))
		var own = _party(nation_id, own_id)
		var rows: Array = []
		for party in _loader.parties.get(nation_id, []):
			if String(party.id) == own_id or ns.coalition_party_ids.has(String(party.id)):
				continue
			var start := _seed_of_party(ns, nation_id, String(party.id))
			if is_nan(start):
				continue
			rows.append({"id": party.id, "d": _distance(party, own), "c": _cordoned(party, own), "start": start})
		for a in rows:
			for b in rows:
				if bool(a["c"]) == bool(b["c"]) and float(a["d"]) > float(b["d"]) and float(a["start"]) > float(b["start"]):
					_fail("%s: %s is farther than %s and starts warmer" % [nation_id, a["id"], b["id"]])


## The regard of a party's people who carry no offset; NAN when every one of them
## carries one (an offset is allowed to break the order: it is a relation, not an idea).
func _seed_of_party(ns, nation_id: String, party_id: String) -> float:
	for person in Staff.cast(_loader, nation_id):
		if float(person.start_regard_offset) == 0.0 and _party_of(nation_id, String(person.id)) == party_id \
				and String(person.id) != President.leader_id(ns):
			return President.rapport(ns, String(person.id))
	return NAN


## Section 6's table for France, and QA's two for Germany (TAKE on #233).
func _check_the_specs_figures() -> void:
	var figures := {
		"FRA": {"renouveau_civique": 0.10, "alliance_verte": 0.0, "parti_social_uni": 0.0,
			"union_conservatrice": -0.16, "gauche_populaire": -0.25, "front_souverainiste": -0.38},
		"DEU": {"linke_allianz": -0.39, "gruene_zukunft": -0.31},
	}
	for nation_id in figures:
		var ns = GameState.new_game(_loader, nation_id).player()
		for party_id in figures[nation_id]:
			var got := _seed_of_party(ns, nation_id, party_id)
			if is_nan(got) or absf(got - float(figures[nation_id][party_id])) >= TO_TWO_DECIMALS:
				_fail("%s: %s starts at %s, section 6 says %.2f" % [nation_id, party_id, str(got), float(figures[nation_id][party_id])])


## The first person of a party, and a person with no party, of the France cast.
func _someone(nation_id: String, party_id: String) -> String:
	for person in Staff.cast(_loader, nation_id):
		if String(person.id) != _loader.nations[nation_id].leader_person_id and _party_of(nation_id, String(person.id)) == party_id:
			return String(person.id)
	_fail("%s: nobody in party '%s'" % [nation_id, party_id])
	return ""


func _with_offsets(offsets: Dictionary, body: Callable) -> void:
	var before := {}
	for pid in offsets:
		before[pid] = _loader.person_by_id[pid].start_regard_offset
		_loader.person_by_id[pid].start_regard_offset = float(offsets[pid])
	body.call()
	for pid in offsets:
		_loader.person_by_id[pid].start_regard_offset = before[pid]


func _check_the_offset_is_added_and_clamped() -> void:
	var partner := _someone("FRA", "alliance_verte")
	var opponent := _someone("FRA", "union_conservatrice")
	var cold := _someone("FRA", "front_souverainiste")
	var loose := _someone("FRA", "")
	var president := String(_loader.nations["FRA"].leader_person_id)
	var chief := String(Staff.chief_of(_loader, "FRA").id)
	_with_offsets({partner: 0.20, opponent: -0.30, cold: -0.90, loose: 0.15, president: 0.30, chief: 0.30}, func() -> void:
		var ns = GameState.new_game(_loader, "FRA").player()
		_near(President.rapport(ns, partner), 0.20, "an offset on a neutral partner")
		_near(President.rapport(ns, opponent), -0.46, "an offset on top of the distance")
		_near(President.rapport(ns, cold), -1.0, "the sum is clamped")
		_near(President.rapport(ns, loose), 0.15, "a person with no party takes the offset alone")
		if ns.person_rapport.has(president) or ns.person_rapport.has(chief):
			_fail("an offset wrote a row for the president or the staff"))


func _near(got: float, want: float, why: String) -> void:
	if absf(got - want) >= TO_TWO_DECIMALS:
		_fail("%s: got %.4f, want %.2f" % [why, got, want])


## "Read against the nation's authored start leader only": a relation with one real
## politician says nothing about the person a scenario seats instead. Every scenario
## is read for what it seats. None seats someone else today (measured: all four keep
## the file's leader), so that start is staged through the real road, a scenario's
## seats handing another party the largest share, and read from new_game's own answer.
func _check_someone_else_seated_reads_no_offset() -> void:
	for scenario_id in _loader.scenarios:
		var nation_id := String(_loader.scenarios[scenario_id].nation_id)
		var loose_here := _someone(nation_id, "")
		_with_offsets({loose_here: 0.15}, func() -> void:
			var ns = GameState.new_game(_loader, nation_id, String(scenario_id)).player()
			var seated := President.leader_id(ns) == String(_loader.nations[nation_id].leader_person_id)
			_near(President.rapport(ns, loose_here), 0.15 if seated else 0.0, "%s, authored leader seated: %s" % [scenario_id, str(seated)]))

	var scenario = _loader.scenarios["gbr_hung_parliament"]
	var shares: Dictionary = scenario.seat_share
	scenario.seat_share = {"national_unity_party": 0.40, "progress_alliance": 0.16, "liberal_union": 0.10,
		"patriot_front": 0.22, "ecology_alliance": 0.06, "home_nations_bloc": 0.06}
	var loose := _someone("GBR", "")
	_with_offsets({loose: 0.15}, func() -> void:
		var ns = GameState.new_game(_loader, "GBR", "gbr_hung_parliament").player()
		var leader := President.leader_id(ns)
		if leader == String(_loader.nations["GBR"].leader_person_id) or _party_of("GBR", leader) != "national_unity_party":
			_fail("the staged start did not seat someone else: '%s'" % leader)
		_near(President.rapport(ns, loose), 0.0, "someone else seated reads no offset")
		# The president's party is the seated leader's, not the file's.
		for person in Staff.cast(_loader, "GBR"):
			if String(person.id) != leader and _party_of("GBR", String(person.id)) == "national_unity_party":
				_near(President.rapport(ns, String(person.id)), OWN_PARTY, "a colleague of the seated leader"))
	scenario.seat_share = shares


func _check_the_loader_refuses_a_bad_offset() -> void:
	for bad in [0.31, -0.31, 0.255, "0.2", true]:
		var errors: Array[String] = []
		Person.from_dict({"id": "X_a", "name": "A", "start_regard_offset": bad}, 0, "t.json", errors)
		if errors.is_empty():
			_fail("the loader took start_regard_offset %s" % str(bad))
	for good in [0.30, -0.30, 0.25, -0.07, 0, 0.0]:
		var errors: Array[String] = []
		var p = Person.from_dict({"id": "X_a", "name": "A", "start_regard_offset": good}, 0, "t.json", errors)
		if not errors.is_empty() or absf(float(p.start_regard_offset) - float(good)) > 0.0000001:
			_fail("the loader refused start_regard_offset %s: %s" % [str(good), errors])
	var errors: Array[String] = []
	if float(Person.from_dict({"id": "X_a", "name": "A"}, 0, "t.json", errors).start_regard_offset) != 0.0:
		_fail("an absent offset does not read zero")


## Exposure._hostile_press reads below zero rapport, and section 6 says the seed
## leaves that share alone: no press owner holds a political office.
func _check_no_press_owner_starts_hostile() -> void:
	for nation_id in _playable():
		var ns = GameState.new_game(_loader, nation_id).player()
		var owners := 0
		for person in _loader.people.get(nation_id, []):
			if String(person.kind) == "press_owner":
				owners += 1
				if President.rapport(ns, String(person.id)) < 0.0:
					_fail("%s: press owner %s starts hostile" % [nation_id, person.id])
		if owners == 0:
			_fail("%s: no press owner read" % nation_id)


## The rule writes rapport only; the bond rule that already reads "below -0.30 is a
## rival" (Shadows.tick_month) turns them in the first month, so no second copy of it
## lives at the seed.
func _check_the_first_month_turns_the_coldest_into_rivals() -> void:
	var rivals_somewhere := 0
	for nation_id in _playable():
		var state = GameState.new_game(_loader, nation_id)
		var ns = state.player()
		Shadows.tick_month(state, _loader)
		for pid in ns.person_rapport:
			var is_rival := String(ns.person_bond.get(pid, "")) == "rival"
			if is_rival != (President.rapport(ns, pid) < -0.30):
				_fail("%s: %s at %.3f reads bond '%s'" % [nation_id, pid, President.rapport(ns, pid), ns.person_bond.get(pid, "")])
			if is_rival:
				rivals_somewhere += 1
	if rivals_somewhere == 0:
		_fail("no nation has a rival after the first month: France's far party should")


func _fail(message: String) -> void:
	_failures.append(message)
