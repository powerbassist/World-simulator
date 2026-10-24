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
const NationState = preload("res://src/core/nation_state.gd")
const Person = preload("res://src/core/person.gd")
const CharacterK_Act = preload("res://src/sim/character_act_constants.gd")
const CK_Act = CharacterK_Act

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
	_check_refusal_price_reads_the_traits()
	_check_act_price_fades()
	_check_an_act_records_what_it_wrote()
	_check_fourteen_years_of_acts_leave_the_clamp()
	_check_want_served_is_stance_aware()

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
		"act_bloc_offset",
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


## V5.2b. A refusal (a declined or lapsed request, a failed lever) prices on the
## two registers 14.1 names, through this file -- the trait intake as for a
## denied want: loyal halves the grudge taken, principled doubles it, both
## multiply. What it returns is what it applied, which the card prints.
func _check_refusal_price_reads_the_traits() -> void:
	for case in [[[], 1.0], [["loyal"], 0.5], [["principled"], 2.0], [["loyal", "principled"], 1.0]]:
		var ns = NationState.new()
		ns.id = "FRA"  # b3: grudge and loyalty are this nation's people's (price_refusal's gate)
		var person = Person.new()
		person.id = "FRA_case"
		for t in case[0]:
			person.traits.append(String(t))
		if not is_equal_approx(Characters.grudge_intake(person), float(case[1])):
			_fail("grudge_intake(%s) read %.2f, wanted %.2f" % [case[0], Characters.grudge_intake(person), case[1]])
		var applied: Dictionary = Characters.price_refusal(ns, person, 0.1, -0.05)
		if not is_equal_approx(float(ns.person_grudges.get("FRA_case", 0.0)), 0.1 * float(case[1])):
			_fail("a refusal priced %s at grudge %.3f, wanted %.3f" % [case[0], float(ns.person_grudges.get("FRA_case", 0.0)), 0.1 * float(case[1])])
		if not is_equal_approx(float(ns.person_loyalty.get("FRA_case", 0.0)), -0.05):
			_fail("a refusal's loyalty did not land: %.3f" % float(ns.person_loyalty.get("FRA_case", 0.0)))
		if not is_equal_approx(float(applied["grudge"]), float(ns.person_grudges["FRA_case"])) \
				or not is_equal_approx(float(applied["loyalty"]), -0.05):
			_fail("price_refusal returned %s, not what it applied" % [applied])
	# The ceiling: a refusal brings a person to the brief's leak, never past it --
	# near the ceiling it takes only the room left and says so, at or over it
	# nothing, and refusal_grudge() (the card's price) agrees with what is paid.
	var ceiling: float = CharacterK_Act.GRUDGE_REFUSAL_CEILING
	for start in [ceiling - 0.05, ceiling, 0.95]:
		var near = NationState.new()
		near.id = "FRA"
		var p = Person.new()
		p.id = "FRA_near"
		near.person_grudges["FRA_near"] = start
		var promised: float = Characters.refusal_grudge(near, p, 0.2)
		var paid: Dictionary = Characters.price_refusal(near, p, 0.2, 0.0)
		var want := maxf(0.0, ceiling - start)
		if not is_equal_approx(float(paid["grudge"]), want) or not is_equal_approx(promised, want):
			_fail("a refusal from %.3f wrote %.3f (promised %.3f), wanted %.3f -- the ceiling is %.3f" % [
				start, float(paid["grudge"]), promised, want, ceiling])


## V5.2b, the author's call "le cout s'efface", banded by Gameplay (bands-v5.2.md,
## "B3 amendment (2026-10-24)"): one act, then nothing -- 50 % of its price remains
## at H months and 25 % at 2H (H the shipped half-life), each within a point, never
## crossing zero; and only
## the act's share fades -- a law's cost beside it stays where it was.
func _check_act_price_fades() -> void:
	if not is_equal_approx(CK_Act.ACT_OFFSET_MONTHLY_KEEP, pow(0.5, 1.0 / float(CK_Act.ACT_OFFSET_HALF_LIFE_MONTHS))):
		_fail("ACT_OFFSET_MONTHLY_KEEP %.10f is not 0.5^(1/%d)" % [CK_Act.ACT_OFFSET_MONTHLY_KEEP, CK_Act.ACT_OFFSET_HALF_LIFE_MONTHS])
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var base := float(ns.bloc_offset.get("workers", 0.0))
	ns.bloc_offset["workers"] = base - 0.3 - 0.2   # a law's -0.3, an act's -0.2
	ns.act_bloc_offset["workers"] = -0.2
	var h: int = CK_Act.ACT_OFFSET_HALF_LIFE_MONTHS
	for m in range(2 * h):
		if not Characters.tick_month(state, _loader, _idle_meters(ns)).is_empty():
			_fail("the fade fixture fired an act -- it measures the act's fade, not a new one")
			return
		var left := float(ns.act_bloc_offset.get("workers", 0.0)) / -0.2
		if left < 0.0 or left > 1.0:
			_fail("month %d: the act's price crossed zero or grew (%.4f of it left)" % [m + 1, left])
			return
		if m + 1 == h and absf(left - 0.50) > 0.01:
			_fail("at %d months %.3f of the act's price remains, not 0.50 +- 0.01" % [h, left])
		if m + 1 == 2 * h and absf(left - 0.25) > 0.01:
			_fail("at %d months %.3f of the act's price remains, not 0.25 +- 0.01" % [2 * h, left])
		if m + 1 == h and not is_equal_approx(float(ns.bloc_offset["workers"]), base - 0.3 - 0.2 * left):
			_fail("bloc_offset reads %.4f, not the law's -0.3 plus the act's faded share over %.4f" % [float(ns.bloc_offset["workers"]), base])


## The act's share is what the act wrote: a brief's price on the two blocs it
## prices and nothing on the rest, computed from the price constants rather than
## read back from bloc_offset -- so a non-act write inside the act loop, booked as
## act cost, fails here (QA's R2 on PR #104).
func _check_an_act_records_what_it_wrote() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var pid := _plain_politician(ns)
	ns.person_grudges[pid] = 0.47   # over the brief gate after the month's decay, under defect
	var before: Dictionary = ns.bloc_offset.duplicate()
	var acts: Array = Characters.tick_month(state, _loader, _idle_meters(ns))
	var briefed := false
	for act in acts:
		briefed = briefed or (String(act["act"]) == "brief_against" and String(act["person_id"]) == pid)
	if not briefed:
		_fail("the fixture's brief did not fire: %s" % [acts])
		return
	var price: float = CK_Act.PRICE_BRIEF * (CK_Act.STANDING_WEIGHT_BASE + float(ns.person_standing.get(pid, 0.0)))
	for bloc in ns.bloc_offset:
		var want: float = price if CK_Act.BRIEF_BLOCS.has(bloc) else 0.0
		if not is_equal_approx(float(ns.act_bloc_offset.get(bloc, 0.0)), want):
			_fail("bloc %s: the brief's price is %.4f and the register recorded %.4f" % [bloc, want, float(ns.act_bloc_offset.get(bloc, 0.0))])


## Fourteen years of acts no longer pin the clamp: one brief a year from a person
## of middling standing -- fourteen of them, 3.5 points permanent before the fade,
## settle near 0.85 with it.
func _check_fourteen_years_of_acts_leave_the_clamp() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var pid := _plain_politician(ns)
	ns.person_standing[pid] = 0.5
	var briefs := 0
	for m in range(168):
		if m % 12 == 0:
			ns.person_grudges[pid] = 0.47
		for act in Characters.tick_month(state, _loader, _idle_meters(ns)):
			briefs += 1 if String(act["act"]) == "brief_against" else 0
		ns.person_grudges[pid] = minf(float(ns.person_grudges[pid]), 0.3)   # one brief per year, no more
	if briefs < 14:
		_fail("the fourteen-year fixture fired %d briefs, not one a year" % briefs)
	for bloc in ns.bloc_offset:
		if absf(float(ns.bloc_offset[bloc])) >= 1.0 - 0.000001:
			_fail("after fourteen years of yearly briefs bloc_offset['%s'] sits on its clamp" % bloc)


func _idle_meters(ns) -> Dictionary:
	return {"grievance": float(ns.unrest_pct), "press_freedom": float(ns.press_freedom), "judicial_independence": 0.0}


## A FRA politician with no trait that bends the brief (networked) or the grudge.
func _plain_politician(ns) -> String:
	for person in _loader.people["FRA"]:
		if person.kind == "politician" and not person.traits.has("networked") \
				and not person.traits.has("loyal") and not person.traits.has("principled"):
			return String(person.id)
	return ""


## The stance-aware read the request trigger asks: a sponsor is served when the
## entry is alive, an opposer when it is not -- the one door, so the trigger and
## the edge-trigger cannot read a want two ways.
func _check_want_served_is_stance_aware() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()
	var person = Person.new()
	person.id = "FRA_case"
	var meters := {"grievance": 0.0, "press_freedom": 0.0, "judicial_independence": 0.0}
	var entry := "prog_in_the_black"
	var sponsor := {"object": "programme:%s" % entry, "stance": "sponsor"}
	var oppose := {"object": "programme:%s" % entry, "stance": "oppose"}
	if Characters.want_served(ns, person, sponsor, meters, {}) or not Characters.want_served(ns, person, oppose, meters, {}):
		_fail("with nothing chosen, a sponsor read served or an opposer read denied")
	ns.programme.append({"entry_id": entry, "chosen_term": int(ns.terms_served), "months_live": 0,
		"status": "active", "concluded_term": -1, "concluded_term_month": -1})
	if not Characters.want_served(ns, person, sponsor, meters, {}) or Characters.want_served(ns, person, oppose, meters, {}):
		_fail("with the entry alive, a sponsor read denied or an opposer read served")


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
