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
	for pid in [backbencher, "%s_nobody_authored" % PLAYER]:
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
const FIELDS := "person_knowledge|person_rapport|person_bond|person_wealth_delta_eur_m|party_money_delta_eur_m|commitments|exposure_evidence"
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


## The first of the played nation's people: any one will do, every read is per id.
func _own_person() -> String:
	return String(_loader.people[PLAYER][0].id)


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
