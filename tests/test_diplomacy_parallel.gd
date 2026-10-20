extends SceneTree

## Headless test: godot --headless --script res://tests/test_diplomacy_parallel.gd
## Non-zero exit on any failure.
##
## V5.0c2 runs Diplomacy's two heavy reads on WorkerThreadPool (src/core/parallel.gd,
## src/sim/diplomacy_agenda.gd). The claim is that the threaded path is the serial
## path, bit for bit; the 51-regime table (cmp-identical, three runs) is the
## whole-game proof, and this file is the direct one -- both paths on ONE state,
## outputs compared exactly, REPEATED, because one lucky run can hide a race:
##
##   1. The pool really fans out: one fan-out's elements run on more than one
##      thread, and the memo phase is `active` inside it and clear after it.
##   2. Each memo is read-only while `active`: a miss computes the same value and
##      stores nothing (Org.shared_bonus, the trade turn memo, Cycle's two); and a
##      vector built from Trade's masses table is the vector pow() builds.
##   5. Rule 4 by reading the files: no libm call (pow, exp, log, the trig family)
##      on the workers' path outside the two sanctioned sites -- the platform this
##      runs on may well be thread-stable, so the scan is what holds the rule.
##   3. Twenty rounds, the world a month further on each round: an acting
##      nation's every target slot (pair terms and every offer's score) and its
##      best act, threaded against serial, under the memos the tick opens; and
##      the third-party list of a hostile and a friendly act on several pairs,
##      threaded against ForeignPolicy's serial composition.
##   4. Whole months in lockstep: two copies of one state, one ticked threaded
##      and one serial, compared through to_dict() after every month.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Agenda = preload("res://src/sim/diplomacy_agenda.gd")
const FP = preload("res://src/sim/foreign_policy.gd")
const Trade = preload("res://src/sim/trade.gd")
const Org = preload("res://src/core/org.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Parallel = preload("res://src/core/parallel.gd")

const ROUNDS := 20
const LOCKSTEP_MONTHS := 4

var _failures: Array[String] = []


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return
	_check_pool_fans_out()
	var state = GameState.new_game(loader, "FRA")
	for _i in range(3):
		WorldMonth.tick_month(state, loader)
	_check_memos_read_only(state)
	_check_rounds(state, loader)
	_check_lockstep(loader)
	_check_no_libm_on_workers()
	Parallel.enabled = true
	_finish()


func _check_pool_fans_out() -> void:
	Parallel.enabled = true
	var n := 64
	var slots: Array = Parallel.slots(n)
	Parallel.each(n, func(i: int) -> void:
		var slot: Dictionary = slots[i]
		var spin := 0.0
		for k in 20000:
			spin += sqrt(float(k + i))
		slot["thread"] = OS.get_thread_caller_id()
		slot["active"] = Parallel.active
		slot["spin"] = spin)
	var threads := {}
	for slot in slots:
		threads[slot["thread"]] = true
		if not bool(slot["active"]):
			_fail("an element ran with the memo phase clear")
	if threads.size() < 2 and OS.get_processor_count() > 1:
		_fail("64 elements ran on %d thread(s) -- the pool did not fan out" % threads.size())
	if Parallel.active:
		_fail("the memo phase is still active after the join")


func _check_memos_read_only(state) -> void:
	var ids: Array = state.nations.keys()
	ids.sort()
	Org.memo_open(state)
	Parallel.active = true
	var a := Org.shared_bonus(state, "FRA", "DEU", "trade_bonus")
	var org_written := not Org._memo.is_empty()
	Parallel.active = false
	var b := Org.shared_bonus(state, "FRA", "DEU", "trade_bonus")
	if org_written:
		_fail("Org.shared_bonus wrote its memo during a fan-out")
	if a != b or Org._memo.is_empty():
		_fail("Org.shared_bonus read-only miss %.17g, stored %.17g (memo empty: %s)" % [a, b, Org._memo.is_empty()])
	Org.memo_close()

	Trade.turn_open(state)
	Trade.masses_open(state)
	Parallel.active = true
	var wa: Dictionary = Trade.weights(state, ids[1])
	var turn_written := not Trade._turn.is_empty()
	Parallel.active = false
	Trade.masses_close()
	var wb: Dictionary = Trade.weights(state, ids[1])
	if turn_written:
		_fail("the trade turn memo was written during a fan-out")
	if var_to_str(wa) != var_to_str(wb) or Trade._turn.is_empty():
		_fail("the turn memo's read-only miss differs from its stored value")
	Trade.turn_close()

	for id in ids:
		var plain: Dictionary = Trade.weights(state, id)
		Trade.masses_open(state)
		var massed: Dictionary = Trade.weights(state, id)
		Trade.masses_close()
		if var_to_str(plain) != var_to_str(massed):
			_fail("%s: a vector built from the masses table differs from pow()'s" % id)
			break

	var key := "parallel-test|%d" % Time.get_ticks_usec()
	Parallel.active = true
	var ua := Cycle.unit(key, 3)
	var pa := Cycle.unit_pair("parallel-test", key, 5)
	var cycle_written := Cycle._seed_memo.has(key) or Cycle._pair_memo.has("parallel-test")
	Parallel.active = false
	if cycle_written:
		_fail("Cycle's seed memos were written during a fan-out")
	if ua != Cycle.unit(key, 3) or pa != Cycle.unit_pair("parallel-test", key, 5):
		_fail("Cycle's read-only draw differs from its stored one")


func _check_rounds(state, loader) -> void:
	var compared := 0
	var acted := 0
	var effects := 0
	for round_i in ROUNDS:
		WorldMonth.tick_month(state, loader)
		var ids: Array = state.nations.keys()
		ids.sort()
		# A third of the actors each round, rotating, so twenty rounds see all of
		# them several times without paying for every one every round.
		for k in ids.size():
			if (k + round_i) % 3 != 0 or state.nations[ids[k]].has_budget:
				continue
			var actor_id: String = ids[k]
			var threaded := _best(state, loader, actor_id, ids, true)
			var serial := _best(state, loader, actor_id, ids, false)
			if threaded != serial:
				_fail("round %d, %s: threaded best act %s, serial %s" % [round_i, actor_id, threaded, serial])
			if _slots(state, loader, actor_id, ids, true) != _slots(state, loader, actor_id, ids, false):
				_fail("round %d, %s: the threaded target slots differ from the serial ones" % [round_i, actor_id])
			compared += 1
			if threaded != "{}":
				acted += 1
		for pair in [["FRA", "DEU"], ["DEU", "POL"], [ids[round_i % ids.size()], "ITA"]]:
			if pair[0] == pair[1]:
				continue
			for delta in [-8.0, 6.0]:
				Parallel.enabled = true
				var threaded: Array = Agenda.third_party_effects(state, pair[0], pair[1], delta)
				Parallel.enabled = false
				var serial: Array = FP.third_party_effects(state, pair[0], pair[1], delta)
				Parallel.enabled = true
				if var_to_str(threaded) != var_to_str(serial):
					_fail("round %d, %s on %s by %.1f: the threaded third-party list differs" % [round_i, pair[0], pair[1], delta])
				effects += threaded.size()
	if compared < ROUNDS * 5 or acted == 0 or effects == 0:
		_fail("near-vacuous rounds: %d best acts compared, %d non-empty, %d third-party effects" % [compared, acted, effects])


## One best act, with the memos the tick holds open around it, as a comparable
## string (the action by id).
func _best(state, loader, actor_id: String, ids: Array, threaded: bool) -> String:
	Parallel.enabled = threaded
	Org.memo_open(state)
	Trade.turn_open(state)
	var choice: Dictionary = Diplomacy._best_act(state, loader, actor_id, ids)
	Trade.turn_close()
	Org.memo_close()
	Parallel.enabled = true
	if choice.is_empty():
		return "{}"
	return var_to_str([choice["action"].id, choice["target_id"], choice["reason"]])


## Every target slot score_targets() fills, as a comparable string (actions by id).
func _slots(state, loader, actor_id: String, ids: Array, threaded: bool) -> String:
	var targets: Array = []
	for id in ids:
		if id != actor_id:
			targets.append(id)
	var offers_of := func(target_id: String) -> Array:
		return Diplomacy.available(state, loader.diplomatic_actions, actor_id, target_id)
	Parallel.enabled = threaded
	Org.memo_open(state)
	Trade.turn_open(state)
	var slots: Array = Agenda.score_targets(state, actor_id, targets, offers_of)
	Trade.turn_close()
	Org.memo_close()
	Parallel.enabled = true
	var flat: Array = []
	for slot in slots:
		var candidates: Array = []
		for candidate in slot.get("candidates", []):
			candidates.append([candidate[0].id, candidate[1]])
		flat.append([slot.get("terms", {}), candidates])
	return var_to_str(flat)


func _check_lockstep(loader) -> void:
	var threaded = GameState.new_game(loader, "FRA")
	var serial = GameState.new_game(loader, "FRA")
	for month in LOCKSTEP_MONTHS:
		Parallel.enabled = true
		WorldMonth.tick_month(threaded, loader)
		Parallel.enabled = false
		WorldMonth.tick_month(serial, loader)
		Parallel.enabled = true
		if var_to_str(threaded.to_dict()) != var_to_str(serial.to_dict()):
			_fail("month %d: the threaded and the serial world differ" % (month + 1))
			return
	if threaded.foreign_acts.is_empty():
		_fail("no nation acted in %d lockstep months -- the comparison never reached execute()" % LOCKSTEP_MONTHS)


## The files whose code the workers run (diplomacy.gd for available() and its
## reads), each with what it may say: {function: [sanctioned expression, ...]},
## "*" for a function that runs on the calling thread only. Trade.masses_open()
## and ForeignPolicy.stake_factor() run there; Trade._raw()'s one pow() is the
## fallback taken with no masses table open (it errors if a fan-out reaches it),
## and is the ONLY libm call _raw() may hold; travel_days() and _haversine_km()
## are not on the workers' path. WORKER_FUNCTIONS names a file read only inside
## the functions listed -- nation_state.gd is reached through one precondition.
const WORKER_FILES := {
	"res://src/sim/trade.gd": {"masses_open": ["*"], "_raw": ["pow(maxf(0.0, b.gdp_eur_bn), K.GRAVITY_EXPONENT)"]},
	"res://src/sim/foreign_policy.gd": {"stake_factor": ["*"]},
	"res://src/sim/diplomacy.gd": {"travel_days": ["*"], "_haversine_km": ["*"]},
	"res://src/sim/diplomacy_agenda.gd": {},
	"res://src/sim/diplomacy_verbs.gd": {},
	"res://src/sim/coercion.gd": {},
	"res://src/sim/defence.gd": {},
	"res://src/core/relations.gd": {},
	"res://src/core/org.gd": {},
	"res://src/core/parallel.gd": {},
}
const WORKER_FUNCTIONS := {
	"res://src/core/nation_state.gd": ["debt_to_gdp_pct"],
}


func _check_no_libm_on_workers() -> void:
	var libm := RegEx.create_from_string("\\b(pow|exp|log|sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh)\\s*\\(|\\*\\*")
	var strings := RegEx.create_from_string("\"(?:[^\"\\\\]|\\\\.)*\"")
	var paths: Array = WORKER_FILES.keys() + WORKER_FUNCTIONS.keys()
	for path in paths:
		var allowed: Dictionary = WORKER_FILES.get(path, {})
		var only: Array = WORKER_FUNCTIONS.get(path, [])
		var source := FileAccess.get_file_as_string(path)
		if source.is_empty():
			_fail("could not read %s" % path)
			continue
		var current := ""
		var seen_only := 0
		for line in source.split("\n"):
			# String literals out first (an error message may name pow()), then
			# the comment.
			var code := strings.sub(line, "\"\"", true)
			var cut := code.find("#")
			code = code if cut < 0 else code.substr(0, cut)
			if code.begins_with("static func ") or code.begins_with("func "):
				current = code.get_slice("func ", 1).get_slice("(", 0).strip_edges()
				if only.has(current):
					seen_only += 1
			if not only.is_empty() and not only.has(current):
				continue
			var sanctioned: Array = allowed.get(current, [])
			if sanctioned.has("*"):
				continue
			for expression in sanctioned:
				code = code.replace(String(expression), "")
			if libm.search(code) != null:
				_fail("%s: %s() calls libm on the workers' path (parallel.gd rule 4): %s" % [path, current, line.strip_edges()])
		if seen_only != only.size():
			_fail("%s: found %d of the functions %s -- the scan list is stale" % [path, seen_only, only])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_diplomacy_parallel: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
