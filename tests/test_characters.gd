extends SceneTree

## V4.3, Task 3. The wants -> acts machine's structural pins, headless:
##
##   - THE LEAF PROPERTY: characters.gd preloads character_constants, the act
##     constants, government (the price primitive) and legislature (the ONE
##     applier) and NOTHING ELSE -- no cabinet, elections, unrest, media or
##     judiciary; meter values arrive as arguments (the calendar.gd law).
##   - THE TICK-ORDER PIN: after Cabinet.tick_month, before Elections.tick_month
##     in main.gd -- the Programme precedent, read from source.
##   - THE SINGLE-WRITER PINS: nothing in src/sim/ writes seats_by_party but
##     elections.gd; nothing but characters.gd writes the five person-state
##     registers (init_nation + tick_month call sites).
##   - DETERMINISM: the same state, ticked twice, produces identical acts and
##     identical registers.
##   - THE BANDS P1-P5 are the probe's (tools/characters_probe.gd); the unit
##     pins here are the structural halves the probe cannot see from a run.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Characters = preload("res://src/sim/characters.gd")
const CharacterK = preload("res://src/sim/character_constants.gd")
const Government = preload("res://src/sim/government.gd")

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])

	_check_leaf_property()
	_check_tick_order_pin()
	_check_single_writers()
	_check_determinism()
	_check_idle_nation_is_silent()
	_check_programme_want_is_term_scoped_and_alive_only()
	_check_challenge_reaches_the_premiership()

	if _failures.is_empty():
		print("test_characters: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)


## THE LEAF PROPERTY, source-scanned the way test_map_cities.gd polices the
## marker contract: the four ALLOWED preloads and no others. The meter systems
## are the ones a writer's temptation would reach for first.
func _check_leaf_property() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/characters.gd")
	if src.is_empty():
		_fail("could not read src/sim/characters.gd")
		return
	var allowed := [
		"character_constants.gd", "character_act_constants.gd",
		"government.gd", "legislature.gd",
	]
	# Comments STRIPPED (the tick-order check's own lesson): characters.gd
	# discusses the systems it refuses to preload at length, and a comment
	# naming an allowed file beside a disallowed preload would pass a raw scan.
	var code := _code_only(src)
	for line in code.split("\n"):
		var l := String(line)
		if not l.contains("preload("):
			continue
		var found := false
		for a in allowed:
			if l.contains(String(a)):
				found = true
		if not found:
			_fail("characters.gd preloads outside its leaf: %s" % l.strip_edges())


## THE TICK-ORDER PIN: the game month's call order, read from source (the
## programme/tick-order precedent -- a comment saying the order is not the
## check; the two call sites' relative order is). Comments are STRIPPED first:
## world_month.gd discusses "Elections.tick_month" in prose above its call, and
## a raw find() would order the COMMENT, not the call.
func _check_tick_order_pin() -> void:
	var src := FileAccess.get_file_as_string("res://src/sim/world_month.gd")
	if src.is_empty():
		_fail("could not read src/sim/world_month.gd")
		return
	var code := _code_only(src)
	var cabinet_at := code.find("Cabinet.tick_month(")
	var characters_at := code.find("Characters.tick_month(")
	var elections_at := code.find("Elections.tick_month(")
	if cabinet_at == -1 or characters_at == -1 or elections_at == -1:
		_fail("world_month.gd is missing one of Cabinet/Characters/Elections tick calls")
		return
	if not (cabinet_at < characters_at and characters_at < elections_at):
		_fail("Characters.tick_month must run after Cabinet and before Elections in the month handler -- wants read Opinion-settled state, Elections writes the stamp pair and runs last")


## SINGLE WRITERS. seats_by_party is elections' alone to WRITE (the defect a
## defection could commit -- discipline/government/legislature READ it, which
## is their input and their right); the six person-state registers are
## characters' alone to write. The scan matches the WRITE form, not the name:
## assignment into the dict or erase on it.
func _check_single_writers() -> void:
	var register_writers: Array[String] = [
		"person_loyalty", "person_standing", "person_grudges",
		"party_leader_override", "person_party_override", "person_want_state",
	]
	for file in _sim_files():
		var src := FileAccess.get_file_as_string("res://src/sim/%s" % file)
		if src.is_empty():
			continue
		var code := _code_only(src)
		if file != "elections.gd" and code.contains("seats_by_party["):
			# An indexed WRITE, not a .get read: every legit reader reads
			# seats_by_party through .get() or a for-in, never assigns into it.
			_fail("src/sim/%s writes seats_by_party -- elections.gd owns the seat, the whip follows it" % file)
		for reg in register_writers:
			if file != "characters.gd" and _indexed_write(code, reg):
				_fail("src/sim/%s writes the %s register -- characters.gd is its one writer" % [file, reg])
	# And the same scan over src/core and src/ui, where a stray writer would be
	# no less a defect -- the UI writes nothing, and core's state layer touches
	# the registers only through whole-property assignment in the round-trip.
	# src/core/loaders since V5.0b: the scan does not recurse.
	for dir in ["src/core", "src/core/loaders", "src/ui"]:
		var da := DirAccess.open("res://%s" % dir)
		if da == null:
			continue
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			if not f.ends_with(".gd"):
				f = da.get_next()
				continue
			var src := FileAccess.get_file_as_string("res://%s/%s" % [dir, f])
			if not src.is_empty():
				var code := _code_only(src)
				for reg in register_writers:
					if _indexed_write(code, reg):
						_fail("%s/%s writes the %s register -- characters.gd is its one writer" % [dir, f, reg])
			f = da.get_next()
		da.list_dir_end()


## DETERMINISM: two fresh copies of one made state, ticked with the same
## meters, produce identical acts and identical registers. The project law,
## pinned where a rand() would first appear -- and the comparison is between
## FRESH STATES rather than consecutive ticks because the first tick MOVES
## the registers (grudges decay, loyalty settles), which is the machine
## working, not indeterminism.
func _check_determinism() -> void:
	var meters := {"grievance": 80.0, "press_freedom": 0.0, "judicial_independence": 0.0}
	var fresh = GameState.new_game(_loader, "FRA")
	if not fresh.errors.is_empty():
		_fail("new_game(FRA) reported %s" % [fresh.errors])
		return
	var run_one: Array = Characters.tick_month(fresh, _loader, meters)
	var fresh_two = GameState.new_game(_loader, "FRA")
	var run_two: Array = Characters.tick_month(fresh_two, _loader, meters)

	if run_one.size() != run_two.size():
		_fail("two identical starting states produced %d and %d acts -- the machine is not deterministic" % [run_one.size(), run_two.size()])
		return
	for i in run_one.size():
		if String(run_one[i]["act"]) != String(run_two[i]["act"]) or String(run_one[i]["person_id"]) != String(run_two[i]["person_id"]):
			_fail("acts differ between identical runs at %d: %s vs %s" % [i, str(run_one[i]), str(run_two[i])])
	var snap_one := _snapshot(fresh.player())
	var snap_two := _snapshot(fresh_two.player())
	for key in snap_one.keys():
		if str(snap_one[key]) != str(snap_two[key]):
			_fail("register '%s' differs between identical runs" % key)


## The idle negative control at the unit level: month one of a fresh game, no
## player decision anywhere, must fire ZERO acts -- P1's principle before the
## probe's 168-month sweep. The bench carries authored wants; month one reads
## them all as `prev = served` (the edge-trigger's first-observation default),
## so no pulse writes and no register moves -- the structural reason the idle
## term stays silent, not an absence of content.
func _check_idle_nation_is_silent() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var meters := {"grievance": float(state.player().unrest_pct), "press_freedom": float(state.player().press_freedom), "judicial_independence": 0.0}
	var acts: Array = Characters.tick_month(state, _loader, meters)
	if not acts.is_empty():
		_fail("a fresh game with no player decision fired %d character acts -- wants can only be denied by a decision" % acts.size())


## The programme want's two gates, pinned at the read the machine prices (the
## standard review's 92-scoring find: a completed entry counted as alive, so
## an oppose-stance author read their want denied for ever and the standing
## denial billed monthly to the end of the run). A want is satisfied only when
## the entry is alive (active) on THIS term's register.
func _check_programme_want_is_term_scoped_and_alive_only() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var want := {"family": "programme", "stance": "support", "object": "programme:prog_jobs_first", "below": 0.0}
	var person = _loader.person_by_id.get("FRA_moucron")
	if person == null:
		_fail("FRA_moucron missing from the register -- the fixture needs a real person id")
		return
	var meters := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}
	var leaders := {}
	# Not chosen: not satisfied, whatever the register may later hold.
	ns.programme = []
	if Characters.want_satisfied(ns, person, want, meters, leaders):
		_fail("an unchosen programme entry read satisfied -- the want judges participation")
	# Alive on this term: satisfied.
	ns.programme = [{"entry_id": "prog_jobs_first", "chosen_term": int(ns.terms_served), "status": "active"}]
	if not Characters.want_satisfied(ns, person, want, meters, leaders):
		_fail("an active this-term entry read unsatisfied -- participation is the judgement")
	# Completed this term: a conclusion, not a standing fact.
	ns.programme = [{"entry_id": "prog_jobs_first", "chosen_term": int(ns.terms_served), "status": "complete"}]
	if Characters.want_satisfied(ns, person, want, meters, leaders):
		_fail("a completed entry read satisfied -- conclusions pay through the programme channel, not the want")
	# Alive on a PAST term: not this term's participation.
	ns.programme = [{"entry_id": "prog_jobs_first", "chosen_term": int(ns.terms_served) - 1, "status": "active"}]
	if Characters.want_satisfied(ns, person, want, meters, leaders):
		_fail("a past-term entry read satisfied -- the want judges this term's register")
	ns.programme = []


## A fired challenge must survive the next government formation: the
## challenger's override is the party's LIVE leadership, and form() refilling
## pm_person_id from the authored (or start-of-game) edge would reinstall the
## person the player watched deposed -- the resurrected-rival outcome the
## SAVE_VERSION 36 argument refuses for dropped saves (the standard review's
## 85-scoring find).
func _check_challenge_reaches_the_premiership() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var pm_party := String(ns.pm_party_id)
	var authored_leader := ""
	for party in _loader.parties.get(ns.id, []):
		if String(party.id) == pm_party:
			authored_leader = String(party.leader_person_id)
			break
	if authored_leader == "":
		_fail("FRA's pm party '%s' has no authored leader -- fixture broken" % pm_party)
		return
	var challenger := ""
	for party in _loader.parties.get(ns.id, []):
		if String(party.id) == pm_party:
			continue
		if String(party.leader_person_id) != "" and _loader.person_by_id.has(String(party.leader_person_id)):
			challenger = String(party.leader_person_id)
			break
	if challenger == "":
		_fail("no challenger available for the premiership test -- fixture broken")
		return
	ns.party_leader_override[pm_party] = challenger
	var party_list: Array = _loader.parties.get(ns.id, [])
	var formed = Government.form(ns, party_list)
	if String(formed.get("pm_person_id", "")) != challenger:
		_fail("form() named '%s' PM with a live override naming '%s' -- the deposed rival was resurrected" % [String(formed.get("pm_person_id", "")), challenger])
	# And the no-override path is unchanged: clear and re-form.
	ns.party_leader_override.erase(pm_party)
	var reformed = Government.form(ns, party_list)
	var expected := authored_leader
	if pm_party == String(ns.incumbent_party_id) and String(ns.start_head_of_government_person_id) != "":
		expected = String(ns.start_head_of_government_person_id)
	if String(reformed.get("pm_person_id", "")) != expected:
		_fail("form() without an override named '%s', expected '%s' -- the authored path moved" % [String(reformed.get("pm_person_id", "")), expected])


func _snapshot(ns) -> Dictionary:
	return {
		"person_loyalty": (ns.person_loyalty as Dictionary).duplicate(true),
		"person_standing": (ns.person_standing as Dictionary).duplicate(true),
		"person_grudges": (ns.person_grudges as Dictionary).duplicate(true),
		"party_leader_override": (ns.party_leader_override as Dictionary).duplicate(true),
		"person_party_override": (ns.person_party_override as Dictionary).duplicate(true),
		"person_want_state": (ns.person_want_state as Dictionary).duplicate(true),
	}


func _sim_files() -> Array[String]:
	var out: Array[String] = []
	var da := DirAccess.open("res://src/sim")
	if da == null:
		_fail("could not open res://src/sim")
		return out
	da.list_dir_begin()
	var f := da.get_next()
	while f != "":
		if f.ends_with(".gd"):
			out.append(f)
		f = da.get_next()
	da.list_dir_end()
	return out


## Assignment-shaped write detection: a line that indexes the register AND
## assigns into it (`] =`) or erases from it. A bare `register[key]` read --
## top_bar's `ns.person_grudges[pid] >= 0.05` -- is a reader's right; the
## scan is a tripwire for WRITERS, and the read/write shape is what says
## which is which.
func _indexed_write(code: String, reg: String) -> bool:
	for raw_line in code.split("\n"):
		var line := String(raw_line)
		if not line.contains("%s[" % reg):
			continue
		if line.contains("] =") or line.contains(".erase("):
			return true
	return false


func _code_only(src: String) -> String:
	var out := ""
	for raw_line in src.split("\n"):
		var line := String(raw_line)
		var hash_at := line.find("#")
		if hash_at != -1:
			line = line.substr(0, hash_at)
		out += line + "\n"
	return out


func _fail(message: String) -> void:
	_failures.append(message)
