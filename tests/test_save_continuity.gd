extends SceneTree

## Headless test: godot --headless --script res://tests/test_save_continuity.gd
## Non-zero exit on any failure.
##
## A PLAYED game through the disk, and the game after it. Every round trip in
## tests/test_save_load.gd builds its state by hand -- a few systems ticked
## directly, or one register filled for the one check -- so a register only the
## real month or a player's command fills round-trips only if somebody thought
## to build it. Two of the V5.0 play gate's save escapes were exactly that: a
## NAN movement no fixture recorded (b0e5aa03) and an org's measure tag no
## fixture adopted (38d743d0). This file plays the game instead:
##
##   1. A few commands a player issues (a budget, a state visit, a treaty, a
##      tariff, a pact and a deployment under it, a sited public work, a bill,
##      and late on a withdrawal from an org, so a fight is in flight at the save),
##      through the same sim calls the panels make, then the game's own month
##      (src/sim/world_month.gd) long enough for the work to complete.
##   2. Saved and loaded through SaveManager, the path the menu takes. Every
##      field of GameState and of every NationState must come back -- the
##      reflective walk of test_save_load.gd, over a state nobody hand-built.
##   3. Nothing the save writes is an INF, nor a NAN outside the one sanctioned
##      slot (a decision's movement with no "before" reading, which the load
##      reads back as NAN). JSON writes a NAN as null, so the FILE SaveManager
##      wrote is walked too: a null anywhere else is the next crash on load.
##   4. CONTINUATION. Twelve more months on the original and on the loaded game,
##      then the same walk again: a save that loads wrong but equal-looking (a
##      derived register not rebuilt, a type that compares equal and ticks
##      differently) shows up as two games that drift apart.
##   5. FLOAT FIDELITY. The save writes full_precision: shortest round-trip
##      digits. JSON.parse_string reads them through Godot's own strtod, which is
##      not correctly rounded, so some floats still come back a few ULP off, but
##      no float may move by more than FLOAT_REL_EPS, the small ones FLOAT_EPS
##      would excuse included, and the share that comes back bit-exact stays
##      above EXACT_SHARE_FLOOR. The 15-digit writer this replaced moved a small
##      value by 5.8% and lost bits in most floats; this is the check that would
##      have said so.
##
## The fixture asserts what it produced, so a command that quietly stops
## applying fails here as "the fixture made nothing" rather than passing on an
## empty register.

## suite-exclusive: real filesystem I/O against user://saves/

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Budget = preload("res://src/sim/budget.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const Defence = preload("res://src/sim/defence.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const Projects = preload("res://src/sim/projects.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Relations = preload("res://src/core/relations.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Clock = preload("res://src/core/clock.gd")
const NationFields = preload("res://src/core/nation_fields.gd")

const SLOT := "__test_save_continuity__"
const BILL := "emissions_standards"
const PLAYER := "FRA"
const PARTNER := "DEU"
const RIVAL := "ITA"
## The flood defences build in 30 months (data/project-actions/projects.json),
## and a COMPLETED sited work is what puts a payoff on the derived map the load
## path rebuilds. Two months over, so the completion is not on the save's month.
const PLAYED_MONTHS := 32
## A membership fight begun this many months before the save, so the save carries
## one in flight: a fight's length is read back only when its referendum is won,
## so a load that loses it flips membership a month later instead of a term later.
const FIGHT_MONTHS_BEFORE_SAVE := 2
const CONTINUED_MONTHS := 12
## test_save_load.gd's two float bounds, and its argument for them.
const FLOAT_EPS := 1e-6
const FLOAT_REL_EPS := 1e-12
## Check 5's floor on the floats that come back bit-exact, set between the two
## writers' measured shares on this fixture: 0.414 with the 15-digit writer
## (12 678 of 30 609), 0.883 with full_precision (27 034) -- what is left is the
## parser's, so the floor sits clear of both rather than at 1.0.
const EXACT_SHARE_FLOOR := 0.75

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	var state = GameState.new_game(_loader, PLAYER)
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
		_finish()
		return
	state.year = 2026
	state.month = 1

	_play_commands(state)
	_play(state, PLAYED_MONTHS - FIGHT_MONTHS_BEFORE_SAVE)
	if not bool(Orgs.begin_withdrawal(state, _loader, state.player(), "eu").get("ok", false)):
		_fail("the withdrawal from the eu was refused -- the save would carry no fight")
	_play(state, FIGHT_MONTHS_BEFORE_SAVE)
	_check_fixture(state)

	var loaded = _save_and_load(state)
	if loaded != null:
		_check_finite("save", state.to_dict())
		_compare("after the load", state, loaded)
		_check_fidelity(state, loaded)
		_play(state, CONTINUED_MONTHS)
		_play(loaded, CONTINUED_MONTHS)
		_compare("%d months after the load" % CONTINUED_MONTHS, state, loaded)
	_cleanup()
	_finish()


## The commands, each through the call its panel makes. A refusal is a fixture
## failure, never a skip: the point is a state with these registers in it.
func _play_commands(state) -> void:
	Budget.commit(state, {
		"tax_rates_pct": {"income": 26.0, "corporate": 27.0, "vat": 21.0},
		"spending_pct_gdp": {"health": 12.0, "education": 6.0, "defence": 2.5},
	})
	var visit = _diplomatic("state_visit")
	if visit != null and not bool(Diplomacy.execute(state, _loader.diplomatic_actions, visit, PLAYER, PARTNER)["applied"]):
		_fail("the state visit to %s was refused" % PARTNER)
	var treaty = _diplomatic_by_effect("agreement", "enter")
	if treaty != null and not bool(Diplomacy.execute(state, _loader.diplomatic_actions, treaty, PLAYER, PARTNER)["applied"]):
		_fail("the treaty with %s was refused" % PARTNER)
	var tariff = _diplomatic_by_effect("measure", "impose")
	if tariff != null and not bool(Diplomacy.execute(state, _loader.diplomatic_actions, tariff, PLAYER, RIVAL)["applied"]):
		_fail("the tariff on %s was refused" % RIVAL)
	var pact = _diplomatic("defence_pact")
	if pact != null and not bool(Diplomacy.execute(state, _loader.diplomatic_actions, pact, PLAYER, PARTNER)["applied"]):
		_fail("the defence pact with %s was refused" % PARTNER)
	var deploy = _diplomatic("deploy_forces")
	if deploy != null and not bool(Diplomacy.execute(state, _loader.diplomatic_actions, deploy, PLAYER, PARTNER)["applied"]):
		_fail("the deployment to %s was refused" % PARTNER)

	var work = null
	for action in _loader.project_actions:
		if String(action.id) == "start_flood_defence":
			work = action
	if work == null:
		_fail("start_flood_defence is not in data/project-actions -- the sited work this test completes")
	elif not bool(Projects.execute(state, state.player(), _loader.project_actions, work).get("applied", false)):
		_fail("the flood defences were refused at new game")

	var bill = null
	for law in _loader.laws:
		if String(law.id) == BILL:
			bill = law
	if bill == null:
		_fail("emissions_standards is not in data/laws -- the bill this test proposes")
		return
	var result: Dictionary = Legislature.propose(state, _loader, bill)
	if not _bill_in_flight_or_law(state.player()) and not bool(result.get("passed", false)):
		_fail("the bill was proposed and went nowhere: %s" % [result])


## The registers the commands and the months were meant to fill, asserted.
func _check_fixture(state) -> void:
	var ns = state.player()
	if not Projects.is_done(ns, "flood_defence"):
		_fail("the flood defences did not complete in %d months" % PLAYED_MONTHS)
	if not (state.project_sited_pct as Dictionary).has(PLAYER):
		_fail("a completed sited work put nothing on project_sited_pct")
	if state.met_months.is_empty():
		_fail("the state visit left no meeting stamp")
	if state.agreements.is_empty():
		_fail("no agreement in force to save")
	if state.pacts.is_empty():
		_fail("no pact in force to save")
	var chosen := false
	for key in state.deployments.keys():
		if (state.deployments[key] as Dictionary).has("action_id"):
			chosen = true
	if not chosen:
		_fail("no deployment opened by a verb to save")
	var answered := false
	for key in state.measures.keys():
		if bool((state.measures[key] as Dictionary).get("retaliated", false)):
			answered = true
	if not answered:
		_fail("no measure in force has been answered -- the tariff drew no retaliation in %d months" % PLAYED_MONTHS)
	if state.accessions.is_empty():
		_fail("no membership fight in flight to save")
	if not _bill_in_flight_or_law(ns):
		_fail("the bill proposed at new game is neither law nor in flight at the save")
	if state.history.size() < PLAYED_MONTHS:
		_fail("history holds %d entries after %d months" % [state.history.size(), PLAYED_MONTHS])


## The game's own month, the date moved first exactly as tests/test_balance.gd
## and main.gd's month handler move it.
func _play(state, months: int) -> void:
	for _i in range(months):
		state.month += 1
		if state.month > 12:
			state.month = 1
			state.year += 1
		WorldMonth.tick_month(state, _loader)


## The bill as the save carries it: in force (its ledger entry -- passed_law_ids
## holds `once` laws only), held by the upper house, or out to a referendum.
## Anything else means the proposal came to nothing.
func _bill_in_flight_or_law(ns) -> bool:
	return ns.law_ledger.has(BILL) or ns.held_bills.has(BILL) \
		or String(ns.referendum_pending.get("law_id", "")) == BILL


func _save_and_load(state):
	var clock := Clock.new()
	clock.year = state.year
	clock.month = state.month
	clock.day = 12
	var error := SaveManager.save_game(state, clock, SLOT)
	clock.free()
	if not error.is_empty():
		_fail("save_game failed on a played game: %s" % error)
		return null
	# What SaveManager actually wrote: JSON has no NAN, so a NAN reaches the file
	# as null. A null anywhere but the sanctioned slot is a NAN (or a missing
	# value) the load will hand a reader as Nil -- the V5.0 crash's shape.
	var written = JSON.parse_string(FileAccess.get_file_as_string(SaveManager._path_for(SLOT)))
	if not (written is Dictionary) or not ((written as Dictionary).get("game_state") is Dictionary):
		_fail("the save file did not parse back to a payload with a game_state")
	else:
		_check_no_null("save", written["game_state"])
	var result := SaveManager.load_game(SLOT, _loader)
	if not bool(result.get("ok", false)):
		_fail("load_game failed on a save this test just wrote: %s" % result.get("error", ""))
		return null
	if int(result["day"]) != 12:
		_fail("day round-tripped as %s, expected 12" % [result["day"]])
	return result["state"]


func _compare(when: String, original, loaded) -> void:
	_check_pair("GameState (%s)" % when, original, loaded)
	if loaded.nations.size() != original.nations.size():
		_fail("%s: %d nations, expected %d" % [when, loaded.nations.size(), original.nations.size()])
	# The table's NOT_SAVED rows are display records of the last verb, left out
	# of the save by design (each row says why); test_nation_fields.gd pins that
	# they are dropped, so here they are not compared.
	var unsaved := {}
	for row in NationFields.FIELDS:
		if row[NationFields.COL_READ] == NationFields.NOT_SAVED:
			unsaved[row[NationFields.COL_NAME]] = true
	for id in original.nations.keys():
		if not loaded.nations.has(id):
			_fail("%s: nation %s is gone" % [when, id])
			continue
		_check_pair("NationState[%s] (%s)" % [id, when], original.nations[id], loaded.nations[id], unsaved)


## Every NAN or INF in the save, by path. The movements' change and severity are
## the one place a NAN is the model's own answer (Trends: "no data").
func _check_finite(path: String, value) -> void:
	match typeof(value):
		TYPE_FLOAT:
			# NAN is the movement slot's own "no data"; an INF is never an answer.
			if is_inf(value) or (is_nan(value) and not _nan_allowed(path)):
				_fail("the save holds %s at %s -- JSON cannot write it" % [value, path])
		TYPE_DICTIONARY:
			for key in value.keys():
				_check_finite("%s.%s" % [path, key], value[key])
		TYPE_ARRAY:
			for i in range(value.size()):
				_check_finite("%s[%d]" % [path, i], value[i])


func _check_no_null(path: String, value) -> void:
	match typeof(value):
		TYPE_NIL:
			if not _nan_allowed(path):
				_fail("the save file holds null at %s" % path)
		TYPE_DICTIONARY:
			for key in value.keys():
				_check_no_null("%s.%s" % [path, key], value[key])
		TYPE_ARRAY:
			for i in range(value.size()):
				_check_no_null("%s[%d]" % [path, i], value[i])


func _nan_allowed(path: String) -> bool:
	return path.begins_with("save.recent_effects[") and path.contains("].movements[") \
		and (path.ends_with(".change") or path.ends_with(".severity"))


## test_save_load.gd's reflective walk: every script variable, enumerated off the
## object rather than listed, so a field added later is covered the day it lands.
func _check_pair(where: String, original, loaded, skip: Dictionary = {}) -> void:
	var names := _script_variables(original)
	if names.is_empty():
		_fail("%s: could not enumerate script variables -- the walk is not running" % where)
		return
	for name in names:
		if name == "errors" or name == "nations" or skip.has(name):
			continue
		var a = original.get(name)
		var b = loaded.get(name)
		if not _deep_equal(a, b):
			_fail("%s.%s: original %s, loaded %s" % [where, name, str(a).left(200), str(b).left(200)])


func _deep_equal(a, b) -> bool:
	if typeof(a) != typeof(b):
		if (typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT) and (typeof(b) == TYPE_INT or typeof(b) == TYPE_FLOAT):
			return _floats_equal(float(a), float(b))
		return false
	match typeof(a):
		TYPE_DICTIONARY:
			if a.size() != b.size():
				return false
			for key in a.keys():
				if not b.has(key) or not _deep_equal(a[key], b[key]):
					return false
			return true
		TYPE_ARRAY:
			if a.size() != b.size():
				return false
			for i in range(a.size()):
				if not _deep_equal(a[i], b[i]):
					return false
			return true
		TYPE_FLOAT:
			return _floats_equal(a, b)
		_:
			return a == b


## Check 5: every float leaf of the original's to_dict() against the loaded game's,
## by path. Bit-exact means equal (NAN to NAN counts, the sanctioned slot); the
## worst relative gap is over all the others, with no absolute floor. A missing
## or non-numeric leaf counts as a miss (_compare() names the structure). Known
## limit: a subnormal float would read back as 0.0 whatever the writer --
## built_in_strtod's power of ten overflows past 1e308 -- and none is in the
## fixture.
func _check_fidelity(original, loaded) -> void:
	var a := {}
	var b := {}
	_float_leaves(original.to_dict(), "", a)
	_float_leaves(loaded.to_dict(), "", b)
	var exact := 0
	var worst := 0.0
	var worst_path := ""
	for path in a:
		var x: float = a[path]
		var got = b.get(path, NAN)
		if typeof(got) != TYPE_FLOAT and typeof(got) != TYPE_INT:
			got = NAN
		var y: float = float(got)
		if x == y or (is_nan(x) and is_nan(y)):
			exact += 1
			continue
		var rel: float = absf(x - y) / maxf(absf(x), absf(y))
		if is_nan(rel) or rel > worst:
			worst = 1.0 if is_nan(rel) else rel
			worst_path = path
	var share: float = float(exact) / float(maxi(1, a.size()))
	print("save fidelity: %d floats, %d bit-exact (%.3f), worst relative %s at %s" % [a.size(), exact, share, String.num_scientific(worst), worst_path])
	if a.size() < 1000:
		_fail("the fidelity walk found only %d floats -- it is not walking the save" % a.size())
	if share < EXACT_SHARE_FLOOR:
		_fail("%.3f of the save's floats came back bit-exact, under the floor %.2f -- is the save written without full_precision?" % [share, EXACT_SHARE_FLOOR])
	if worst > FLOAT_REL_EPS:
		_fail("a float came back %s off (relative) at %s, past %s -- the save lost its digits" % [String.num_scientific(worst), worst_path, String.num_scientific(FLOAT_REL_EPS)])


## The float leaves of a to_dict() tree, by path; ints, strings and the rest skip.
func _float_leaves(value, path: String, out: Dictionary) -> void:
	match typeof(value):
		TYPE_DICTIONARY:
			for key in value:
				_float_leaves(value[key], "%s/%s" % [path, key], out)
		TYPE_ARRAY:
			for i in (value as Array).size():
				_float_leaves(value[i], "%s[%d]" % [path, i], out)
		TYPE_FLOAT:
			out[path] = value


## NAN equals NAN here: the sanctioned "no data" movement is NAN on both sides.
func _floats_equal(a: float, b: float) -> bool:
	if is_nan(a) or is_nan(b):
		return is_nan(a) and is_nan(b)
	if absf(a - b) < FLOAT_EPS:
		return true
	return absf(a - b) <= maxf(absf(a), absf(b)) * FLOAT_REL_EPS


func _script_variables(obj) -> Array:
	var names: Array = []
	for p in obj.get_property_list():
		if not (int(p["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var name: String = p["name"]
		if name == "script" or name.begins_with("_"):
			continue
		names.append(name)
	return names


func _diplomatic(id: String):
	for action in _loader.diplomatic_actions:
		if String(action.id) == id:
			return action
	_fail("no diplomatic action '%s' to issue" % id)
	return null


func _diplomatic_by_effect(effect: String, op: String):
	for action in _loader.diplomatic_actions:
		if String(action.effects.get(effect, {}).get("op", "")) == op:
			return action
	_fail("no diplomatic action with a '%s' effect of op '%s' to issue" % [effect, op])
	return null


func _cleanup() -> void:
	var dir := DirAccess.open(SaveManager.SAVE_DIR)
	if dir != null:
		for p in [SaveManager._path_for(SLOT), SaveManager._path_for(SLOT) + SaveManager.TEMP_SUFFIX]:
			if FileAccess.file_exists(p):
				dir.remove(p)
	if FileAccess.file_exists(SaveManager._path_for(SLOT)):
		_fail("cleanup left '%s' behind in %s" % [SLOT, SaveManager.SAVE_DIR])


func _fail(message: String) -> void:
	if _failures.size() < 40:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_save_continuity: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	printerr("test_save_continuity: %d check(s) failed" % _failures.size())
	quit(1)
