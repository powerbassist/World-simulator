extends SceneTree

## Headless test: godot --headless --script res://tests/test_president.gd
## Non-zero exit on any failure.
##
## V5.2a, the president's registers (src/sim/president.gd; people-model 14.9;
## docs/design/v5.2-spec.md "The registers (V5.2a)"). What this file holds:
##
##   - ABSENT IS "NOTHING HAS HAPPENED YET". A fresh game and a save made before
##     V5.2a read a stranger, neutral rapport, no bond, the authored money,
##     nothing promised and nothing left behind -- the reason none of the seven
##     earned a SAVE_VERSION bump (test_nation_fields pins the table half).
##   - THE BOUNDS AND THE VOCABULARIES ARE THE WRITER'S. Knowledge clamps to
##     [0, 1], rapport to [-1, 1]; a bond, a commitment and a piece of evidence
##     outside their closed lists are refused with the register untouched.
##   - THE AUTHOR'S COVERAGE (2026-10-21, answer 1). The played nation's people
##     plus the foreign heads of state and government -- never another nation's
##     backbencher, never an id nobody authored.
##   - ONE WRITER. No file under src/ but president.gd writes the seven fields.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const NationState = preload("res://src/core/nation_state.gd")
const Party = preload("res://src/core/party.gd")
const President = preload("res://src/sim/president.gd")
const K = preload("res://src/sim/president_constants.gd")

const PLAYER := "FRA"
const FOREIGN := "DEU"

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_absent_reads_as_nothing_happened()
	_check_bounds_clamp()
	_check_knowledge_bands()
	_check_coverage()
	_check_bond_vocabulary_and_derived_relationship()
	_check_money_is_the_authored_start_plus_the_delta()
	_check_party_funds_field()
	_check_rows_refuse_and_round_trip_with_int_months()
	# V5.2c Task 1: the exposure register and its two writers.
	_check_grow_evidence_accrues_one_row()
	_check_expose_moves_the_row()
	_check_a_pre_c_save_reads_nothing_exposed_and_the_current_leader()
	_check_one_writer()

	_finish()


func _check_absent_reads_as_nothing_happened() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var pid := _own_person()
	var party_id: String = _loader.parties[PLAYER][0].id
	var authored: float = _loader.parties[PLAYER][0].funds_eur_m
	var old_save = NationState.from_dict({"id": PLAYER})
	for ns in [state.player(), old_save]:
		if President.knowledge(ns, pid) != 0.0 or President.knowledge_band(ns, pid) != "stranger":
			_fail("absent knowledge read %.2f / %s, not 0 / stranger" % [President.knowledge(ns, pid), President.knowledge_band(ns, pid)])
		if President.rapport(ns, pid) != 0.0:
			_fail("absent rapport read %.2f, not 0" % President.rapport(ns, pid))
		if President.relationship(ns, pid) != "stranger":
			_fail("absent relationship read '%s', not stranger" % President.relationship(ns, pid))
		if President.wealth_eur_m(ns, _loader, pid) != _loader.person_by_id[pid].wealth_eur_m:
			_fail("absent wealth delta did not read the authored start")
		if President.party_money_eur_m(ns, _loader, party_id) != authored:
			_fail("absent party money delta did not read the authored start")
		if not President.commitments_with(ns, pid).is_empty() or President.evidence_size(ns) != 0.0:
			_fail("an absent register read a commitment or evidence")


func _check_bounds_clamp() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var pid := _own_person()
	President.learn(state, ns, _loader, pid, 5.0)
	if President.knowledge(ns, pid) != 1.0:
		_fail("knowledge did not clamp at 1: %.2f" % President.knowledge(ns, pid))
	President.learn(state, ns, _loader, pid, -9.0)
	if President.knowledge(ns, pid) != 0.0:
		_fail("knowledge did not clamp at 0: %.2f" % President.knowledge(ns, pid))
	President.adjust_rapport(state, ns, _loader, pid, 3.0)
	if President.rapport(ns, pid) != 1.0:
		_fail("rapport did not clamp at 1: %.2f" % President.rapport(ns, pid))
	President.adjust_rapport(state, ns, _loader, pid, -7.0)
	if President.rapport(ns, pid) != -1.0:
		_fail("rapport did not clamp at -1: %.2f" % President.rapport(ns, pid))


## B4's bands: stranger [0, 0.33), acquaintance [0.33, 0.67), known [0.67, 1].
func _check_knowledge_bands() -> void:
	var pid := _own_person()
	for case in [[0.32, "stranger"], [0.33, "acquaintance"], [0.66, "acquaintance"], [0.67, "known"], [1.0, "known"]]:
		var state = GameState.new_game(_loader, PLAYER)
		var ns = state.player()
		President.learn(state, ns, _loader, pid, float(case[0]))
		if President.knowledge_band(ns, pid) != String(case[1]):
			_fail("knowledge %.2f read band '%s', wanted '%s'" % [case[0], President.knowledge_band(ns, pid), case[1]])


func _check_coverage() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var foreign = state.nations[FOREIGN]
	var heads := [String(foreign.head_of_state_person_id), String(foreign.pm_person_id)]
	var backbencher := ""
	for person in _loader.people[FOREIGN]:
		if not heads.has(person.id):
			backbencher = person.id
			break
	for pid in [_own_person(), heads[0], heads[1]]:
		if pid == "":
			_fail("%s has an empty head slot -- the fixture lost its foreign head" % FOREIGN)
		elif not President.covers(state, ns, _loader, pid):
			_fail("'%s' is not covered, and the author's call covers it" % pid)
	# The president themself: an edge needs two ends.
	var leader := President.leader_id(ns)
	if leader == "" or not leader.begins_with("%s_" % PLAYER):
		_fail("leader_id read '%s' for %s" % [leader, PLAYER])
	for pid in [backbencher, "%s_nobody_authored" % PLAYER, leader]:
		if President.covers(state, ns, _loader, pid):
			_fail("'%s' is covered, and it is outside the author's call" % pid)
		var wrote: bool = President.learn(state, ns, _loader, pid, 0.5) \
			or President.adjust_rapport(state, ns, _loader, pid, 0.5) \
			or President.set_bond(state, ns, _loader, pid, "friend") \
			or President.commit(state, ns, _loader, "promise", pid, "programme:x", _now(state) + 3) \
			or President.leave_evidence(state, ns, _loader, "favour", pid, 1.0)
		if wrote or ns.person_knowledge.has(pid) or ns.person_rapport.has(pid) or ns.person_bond.has(pid) \
				or not ns.commitments.is_empty() or not ns.exposure_evidence.is_empty():
			_fail("a writer accepted '%s', outside the coverage" % pid)


func _check_bond_vocabulary_and_derived_relationship() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var pid := _own_person()
	for bond in K.BONDS:
		if not President.set_bond(state, ns, _loader, pid, bond) or President.relationship(ns, pid) != bond:
			_fail("bond '%s' did not take" % bond)
	for bad in ["stranger", "acquaintance", "lover"]:
		if President.set_bond(state, ns, _loader, pid, bad):
			_fail("'%s' was accepted as a bond -- stranger and acquaintance are read off knowledge" % bad)
	President.set_bond(state, ns, _loader, pid, "")
	if ns.person_bond.has(pid) or President.relationship(ns, pid) != "stranger":
		_fail("clearing a bond left '%s'" % President.relationship(ns, pid))
	President.learn(state, ns, _loader, pid, 0.5)
	if President.relationship(ns, pid) != "acquaintance":
		_fail("knowledge 0.5 with no bond read '%s', not acquaintance" % President.relationship(ns, pid))
	President.learn(state, ns, _loader, pid, 0.4)
	if President.relationship(ns, pid) != "acquaintance":
		_fail("a known person with no bond read '%s', not acquaintance" % President.relationship(ns, pid))


func _check_money_is_the_authored_start_plus_the_delta() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var pid := _own_person()
	var person = _loader.person_by_id[pid]
	var party = _loader.parties[PLAYER][0]
	var kept_wealth: float = person.wealth_eur_m
	var kept_funds: float = party.funds_eur_m
	person.wealth_eur_m = 2.0
	party.funds_eur_m = 10.0
	if not President.adjust_wealth_eur_m(ns, _loader, pid, 3.5) or President.wealth_eur_m(ns, _loader, pid) != 5.5:
		_fail("wealth read %.2f, not the authored 2.0 + 3.5" % President.wealth_eur_m(ns, _loader, pid))
	if not President.adjust_party_money_eur_m(ns, _loader, party.id, -1.25) \
			or President.party_money_eur_m(ns, _loader, party.id) != 8.75:
		_fail("party money read %.2f, not the authored 10.0 - 1.25" % President.party_money_eur_m(ns, _loader, party.id))
	var foreign_party: String = _loader.parties[FOREIGN][0].id
	if President.adjust_party_money_eur_m(ns, _loader, foreign_party, 1.0) or ns.party_money_delta_eur_m.has(foreign_party):
		_fail("another nation's party took a delta on this nation's register")
	if President.adjust_wealth_eur_m(ns, _loader, String(_loader.people[FOREIGN][0].id), 1.0):
		_fail("a foreign person's wealth took a delta on this nation's register")
	person.wealth_eur_m = kept_wealth
	party.funds_eur_m = kept_funds


func _check_party_funds_field() -> void:
	var base := {
		"id": "p", "name": "P", "ideology_slot": "centre", "seat_share": 0.1,
		"leader_person": "FRA_x", "discipline": 0.5, "competence": 0.5, "excluded_partners": [],
	}
	var errors: Array[String] = []
	var plain = Party.from_dict(base, 0, "inline", errors)
	if not errors.is_empty() or plain.funds_eur_m != 0.0:
		_fail("a party without funds_eur_m read %.2f with errors %s" % [plain.funds_eur_m, errors])
	var funded := base.duplicate()
	funded["funds_eur_m"] = 12.5
	if Party.from_dict(funded, 0, "inline", errors).funds_eur_m != 12.5 or not errors.is_empty():
		_fail("funds_eur_m 12.5 did not load: %s" % [errors])
	var broke := base.duplicate()
	broke["funds_eur_m"] = -1
	Party.from_dict(broke, 0, "inline", errors)
	if errors.size() != 1 or errors[0].find("funds_eur_m") == -1:
		_fail("a negative funds_eur_m was not refused by name: %s" % [errors])


func _check_rows_refuse_and_round_trip_with_int_months() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var pid := _own_person()
	var due := _now(state) + 6
	if President.commit(state, ns, _loader, "bribe", pid, "programme:x", due):
		_fail("a commitment kind outside the list was accepted")
	if President.commit(state, ns, _loader, "promise", pid, "programme:x", _now(state)):
		_fail("a promise due this month or earlier was accepted")
	if President.commit(state, ns, _loader, "promise", pid, "", due):
		_fail("a promise of nothing was accepted")
	if President.leave_evidence(state, ns, _loader, "theft", pid, 1.0) \
			or President.leave_evidence(state, ns, _loader, "favour", pid, 0.0):
		_fail("evidence outside the list, or of no size, was accepted")
	if not ns.commitments.is_empty() or not ns.exposure_evidence.is_empty():
		_fail("a refused row reached the register")
	if not President.commit(state, ns, _loader, "promise", pid, "programme:x", due) \
			or not President.leave_evidence(state, ns, _loader, "favour", pid, 0.5):
		_fail("a legal commitment or piece of evidence was refused")
		return
	var loaded = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	var rows: Array[Dictionary] = President.commitments_with(loaded, pid)
	if rows.size() != 1:
		_fail("the commitment did not survive the round trip: %s" % [rows])
		return
	var row: Dictionary = rows[0]
	if typeof(row["due_month"]) != TYPE_INT or int(row["due_month"]) != due \
			or typeof(row["made_month"]) != TYPE_INT or int(row["made_month"]) != _now(state):
		_fail("the commitment's months came back %s, not ints %d / %d" % [row, _now(state), due])
	if String(row["kind"]) != "promise" or String(row["object"]) != "programme:x":
		_fail("the commitment came back %s" % [row])
	if not is_equal_approx(President.evidence_size(loaded), 0.5):
		_fail("the evidence came back at %.2f, not 0.5" % President.evidence_size(loaded))


## The recent_effects scan's method (tests/test_effects_ledger.gd), over the seven
## fields: a mutating call, an indexed store or an assignment through a member
## access (`ns.commitments.append(`, `ns.person_bond[id] =`). What it does not
## catch: a write through a local alias, which a writer would have to go out of
## its way to hide. Code only -- strings and comments are stripped first.
const FIELDS := "person_knowledge|person_rapport|person_bond|person_wealth_delta_eur_m|party_money_delta_eur_m|commitments|commitments_judged|exposure_evidence|exposures"
const WRITE := "\\.(%s)\\s*(\\.\\s*(push_front|push_back|append|append_array|insert|remove_at|erase|clear|resize|pop_front|pop_back|pop_at|sort|sort_custom|reverse|fill|shuffle|assign|merge|set)\\s*\\(|\\[[^\\]]*\\]\\s*[-+*/]?=(?!=)|\\s*[-+*/]?=(?!=))"
const WRITER := "res://src/sim/president.gd"


func _check_one_writer() -> void:
	var write := RegEx.create_from_string(WRITE % FIELDS)
	var strings := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'")
	var files: Array = []
	_gd_files("res://src", files)
	if files.size() < 100:
		_fail("the writer scan found %d files under src/ -- it is not reading the tree" % files.size())
	var seen_writer := false
	for path in files:
		var code := ""
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var bare := strings.sub(line, "\"\"", true)
			var cut := bare.find("#")
			code += (bare if cut < 0 else bare.substr(0, cut)) + "\n"
		var found := write.search(code)
		if found == null:
			continue
		if path == WRITER:
			seen_writer = true
			continue
		_fail("%s writes a president register (`%s`) -- src/sim/president.gd is the one writer" % [path, found.get_string().strip_edges()])
	if not seen_writer:
		_fail("src/sim/president.gd no longer writes a register -- the scan lost its positive control")


func _gd_files(dir_path: String, out: Array) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for name in dir.get_files():
		if name.ends_with(".gd"):
			out.append(dir_path + "/" + name)
	for sub in dir.get_directories():
		_gd_files(dir_path + "/" + sub, out)


## The affair's accrual: one open row per kind and person, grown in place, and
## stamped with the president who left it -- so a successor's affair is a row of
## its own, never the predecessor's grown (the plan's Review focus 3).
func _check_grow_evidence_accrues_one_row() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var pid := _own_person()
	if President.grow_evidence(state, ns, _loader, "theft", pid, 0.1) \
			or President.grow_evidence(state, ns, _loader, "affair", pid, 0.0) \
			or President.grow_evidence(state, ns, _loader, "affair", "nobody", 0.1):
		_fail("a grow outside the kinds, of nothing, or on an uncovered id was accepted")
	if not ns.exposure_evidence.is_empty():
		_fail("a refused grow reached the register")
	if not President.grow_evidence(state, ns, _loader, "affair", pid, 0.1) \
			or not President.grow_evidence(state, ns, _loader, "affair", pid, 0.1):
		_fail("a legal grow was refused")
		return
	if ns.exposure_evidence.size() != 1 or not is_equal_approx(float(ns.exposure_evidence[0]["size"]), 0.2):
		_fail("two grows of 0.1 on one affair left %s, not one row of 0.2" % [ns.exposure_evidence])
		return
	var first := President.leader_id(ns)
	if String(ns.exposure_evidence[0].get("leader_id", "")) != first:
		_fail("the grown row does not name the president who left it: %s" % [ns.exposure_evidence[0]])
	var successor := ""
	for person in _loader.people[PLAYER]:
		if person.id != pid and person.id != first:
			successor = String(person.id)
			break
	ns.head_of_state_person_id = successor
	ns.pm_person_id = successor
	President.grow_evidence(state, ns, _loader, "affair", pid, 0.1)
	if ns.exposure_evidence.size() != 2 or not is_equal_approx(float(ns.exposure_evidence[0]["size"]), 0.2) \
			or String(ns.exposure_evidence[1].get("leader_id", "")) != successor:
		_fail("a successor's grow touched the predecessor's row: %s" % [ns.exposure_evidence])


## expose_evidence moves one row, stamped with its route and month, and refuses
## -- writing nothing -- a bad index, a route outside the list, or a route that
## cannot reach the row's kind (the courts do not read a favour; since #170's call 1
## the press does).
func _check_expose_moves_the_row() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var ns = state.player()
	var pid := _own_person()
	var made := _now(state)
	President.leave_evidence(state, ns, _loader, "favour", pid, 0.5)
	President.leave_evidence(state, ns, _loader, "personal_wealth", pid, 0.25)
	if not President.expose_evidence(ns, 1, "tv", made + 2).is_empty() \
			or not President.expose_evidence(ns, 2, "press", made + 2).is_empty() \
			or not President.expose_evidence(ns, -1, "press", made + 2).is_empty() \
			or not President.expose_evidence(ns, 0, "courts", made + 2).is_empty():
		_fail("an exposure by an unknown route, of no row, or by a route that cannot reach the kind was accepted")
	if ns.exposure_evidence.size() != 2 or not ns.exposures.is_empty():
		_fail("a refused exposure wrote to a register")
		return
	var want := {
		"kind": "personal_wealth", "route": "press", "person_id": pid, "size": 0.25,
		"made_month": made, "exposed_month": made + 2, "leader_id": President.leader_id(ns),
	}
	var row: Dictionary = President.expose_evidence(ns, 1, "press", made + 2)
	if row != want:
		_fail("the exposure came back %s, not %s" % [row, want])
	if ns.exposure_evidence.size() != 1 or String(ns.exposure_evidence[0]["kind"]) != "favour":
		_fail("the exposed row did not leave the evidence, or took the wrong one: %s" % [ns.exposure_evidence])
	var loaded = NationState.from_dict(JSON.parse_string(JSON.stringify(ns.to_dict())))
	var rows: Array[Dictionary] = President.exposures(loaded)
	if rows.size() != 1 or rows[0] != want or typeof(rows[0]["exposed_month"]) != TYPE_INT:
		_fail("the exposure did not survive the round trip with int months: %s" % [rows])


## A save from before V5.2c: no `exposures`, and evidence rows that name no
## president. It reads as nothing exposed, and such a row is the sitting
## president's (every pre-c row was left by whoever sat then).
func _check_a_pre_c_save_reads_nothing_exposed_and_the_current_leader() -> void:
	var state = GameState.new_game(_loader, PLAYER)
	var pid := _own_person()
	var raw: Dictionary = JSON.parse_string(JSON.stringify(state.player().to_dict()))
	raw.erase("exposures")
	raw["exposure_evidence"] = [{"kind": "favour", "person_id": pid, "size": 0.5, "month": _now(state)}]
	var old = NationState.from_dict(raw)
	if not old.exposures.is_empty() or not President.exposures(old).is_empty():
		_fail("an absent exposures register read an exposure")
	if President.evidence_leader(old, old.exposure_evidence[0]) != President.leader_id(old):
		_fail("a pre-c evidence row did not read as the sitting president's")
	var row: Dictionary = President.expose_evidence(old, 0, "turned", _now(state) + 1)
	if String(row.get("leader_id", "")) != President.leader_id(old) or President.leader_id(old) == "":
		_fail("a pre-c row exposed without the sitting president's id: %s" % [row])


## The first of the played nation's people who is not the president: any one
## will do, every read is per id, and the president has no edge to themself.
func _own_person() -> String:
	var nation = _loader.nations[PLAYER]
	for person in _loader.people[PLAYER]:
		if person.id != nation.head_of_state_person_id and person.id != nation.head_of_government_person_id:
			return String(person.id)
	return ""


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_president: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
