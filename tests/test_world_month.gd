extends SceneTree

## Headless test: godot --headless --script res://tests/test_world_month.gd
##
## src/sim/world_month.gd is the game's month, and this file holds three things
## about it that a comment cannot:
##
##   1. The order it runs is its STEPS list, recorded through its own hook, and
##      the hook sees each record at the step that wrote it.
##   2. The hook is a seam and not an input: a month ticked with a hook that does
##      nothing is the month ticked with none, to the last saved byte.
##   3. Nothing else carries a copy of the month. Every harness that runs the real
##      month calls tick_month(), and no function anywhere outside world_month.gd
##      ticks more than half its systems by hand -- the hand copies drifted for as
##      long as they existed (V1.5d never called Media, tick_budget_probe never
##      timed Commodities, events_probe's E4/E5 chain never ticked Commodities),
##      and a copy that falls behind measures a world the game never runs.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const WorldMonth = preload("res://src/sim/world_month.gd")
const Budget = preload("res://src/sim/budget.gd")
const Trade = preload("res://src/sim/trade.gd")

## The harnesses that run the real month. Each must call WorldMonth.tick_month in
## code (a comment naming it is not a call).
const HARNESSES := [
	# V5.1-0a: the game's month is main.gd's through its runner, which calls the
	# whole month for a hand-driven day and the same cursor across frames.
	"res://src/ui/month_runner.gd",
	"res://tests/test_balance.gd",
	"res://tools/balance_probe.gd",
	"res://tools/tick_budget_probe.gd",
	"res://tools/endowment_probe.gd",
	"res://tools/programme_probe.gd",
	"res://tools/council_probe.gd",
	"res://tools/agency_probe.gd",
	"res://tools/upper_house_probe.gd",
	"res://tools/judiciary_probe.gd",
	"res://tools/energy_probe.gd",
	"res://tools/referendum_probe.gd",
	"res://tools/events_probe.gd",
]

## A function ticking more distinct month systems than this by hand is a copy of
## the month. Half of the thirty: the per-system probes that tick a deliberate
## few (calendar, media, pledge, campaign...) sit at fifteen or under.
const MAX_HAND_TICKED := 15

## The deliberate subsets above the bar, each with the reason it is not the month.
## "path::function" -> why.
const ALLOWED := {
	"res://src/sim/budget.gd::project": "the fiscal projection: a budget preview must not legislate, vote or charge a promise",
	"res://tests/test_budget.gd::_run": "project()'s mirror, held to project() rather than to the month",
	"res://tools/events_probe.gd::_step": "E0/E2/E3's reduced world: no Events, by design -- the tables measure the field ranges an event is authored against",
}

const SCAN_DIRS := ["res://src", "res://tools", "res://tests"]

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_the_hook_records_steps_in_order()
	_check_a_hook_changes_nothing()
	_check_the_cursor_is_the_month()
	_check_every_harness_runs_the_month()
	_check_no_hand_copy_is_left()
	_finish()


func _check_the_hook_records_steps_in_order() -> void:
	var state = _new_state()
	var seen: Array = []
	_advance(state)
	var history_before: int = state.history.size()
	var report := WorldMonth.tick_month(state, _loader, func(step: String, after: bool, so_far: Dictionary) -> void:
		seen.append([step, after])
		# Each record is in the report from the step that wrote it, and not before.
		for pair in [["History", "history_entry"], ["Characters", "character_acts"],
				["Elections", "election_results"]]:
			if step == pair[0] and so_far.has(pair[1]) != after:
				_fail("report[%s] is %s %s the %s step" % [
					pair[1], "present" if so_far.has(pair[1]) else "absent",
					"after" if after else "before", step])
	)

	var expected: Array = []
	for step in WorldMonth.STEPS:
		expected.append([step, false])
		expected.append([step, true])
	if seen != expected:
		_fail("the hook saw %s, not STEPS before/after in order" % [seen])
	if not (report.get("history_entry") is Dictionary):
		_fail("report has no history_entry Dictionary")
	if not (report.get("character_acts") is Array):
		_fail("report has no character_acts Array")
	if not (report.get("election_results") is Array):
		_fail("report has no election_results Array")
	if state.history.size() != history_before + 1:
		_fail("one month appended %d history entries, not 1" % (state.history.size() - history_before))


func _check_a_hook_changes_nothing() -> void:
	var plain = _new_state()
	var hooked = _new_state()
	for m in range(2):
		_advance(plain)
		_advance(hooked)
		WorldMonth.tick_month(plain, _loader)
		WorldMonth.tick_month(hooked, _loader, func(_step: String, _after: bool, _report: Dictionary) -> void:
			pass
		)
	if JSON.stringify(plain.to_dict()) != JSON.stringify(hooked.to_dict()):
		_fail("a month ticked with a no-op hook saved differently from one ticked without")


## V5.1-0a. The cursor is the month a player watches: src/ui/month_runner.gd
## runs it a unit at a time across frames, and the UI draws between two units.
## So the month is held to three things here. The hook sees the same calls in
## the same order as a month run whole. Economy and Diplomacy arrive in slices
## (more units than steps -- the reason the cursor exists), each unit under its
## own key. And what the UI reads between two units -- the books, a trade vector
## -- writes nothing the month then reads: the sliced month with a reader at
## every gap saves byte for byte as the month run whole. That the cursor is the
## OLD month is the balance table's to prove (balance_parallel, base vs tip).
func _check_the_cursor_is_the_month() -> void:
	var whole = _new_state()
	var sliced = _new_state()
	for m in range(2):
		_advance(whole)
		_advance(sliced)
		var seen_whole: Array = []
		var seen_sliced: Array = []
		WorldMonth.tick_month(whole, _loader, func(step: String, after: bool, _report: Dictionary) -> void:
			seen_whole.append([step, after]))
		var month = WorldMonth.begin(sliced, _loader, func(step: String, after: bool, _report: Dictionary) -> void:
			seen_sliced.append([step, after]))
		var keys := {}
		var units := 0
		while not WorldMonth.done(month):
			keys[WorldMonth.unit_key(month)] = true
			WorldMonth.run_unit(month)
			units += 1
			Budget.snapshot(sliced)
			Trade.weights(sliced, sliced.player_nation_id)
		if seen_sliced != seen_whole:
			_fail("the sliced month's hook saw %d calls in a different order from the whole month's" % seen_sliced.size())
		# Economy alone brings a pre-pass and a unit per nation.
		if units <= WorldMonth.STEPS.size() + sliced.nations.size():
			_fail("the month ran in %d units for %d steps -- Economy and Diplomacy did not slice" % [
				units, WorldMonth.STEPS.size()])
		if keys.size() != units:
			_fail("%d units shared %d keys -- a runner cannot time them apart" % [units, keys.size()])
	if JSON.stringify(whole.to_dict()) != JSON.stringify(sliced.to_dict()):
		_fail("two sliced months, read between every unit, saved differently from two whole ones")


func _check_every_harness_runs_the_month() -> void:
	for path in HARNESSES:
		var called := false
		for line in FileAccess.get_file_as_string(path).split("\n"):
			var stripped := line.strip_edges()
			if not stripped.begins_with("#") and stripped.contains("WorldMonth.tick_month("):
				called = true
		if not called:
			_fail("%s does not call WorldMonth.tick_month -- it is running a month of its own" % path)


func _check_no_hand_copy_is_left() -> void:
	var systems: Array[String] = []
	for step in WorldMonth.STEPS:
		if step != "Access" and step != "History":
			systems.append(step)
	var found_allowed := {}
	for path in _gd_files():
		if path == "res://src/sim/world_month.gd":
			continue
		var fn := "<top>"
		var ticked := {}
		for line in FileAccess.get_file_as_string(path).split("\n"):
			if line.begins_with("func ") or line.begins_with("static func "):
				_judge(path, fn, ticked, found_allowed)
				fn = line.trim_prefix("static ").trim_prefix("func ").get_slice("(", 0)
				ticked = {}
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			for system in systems:
				if stripped.contains(system + ".tick_month("):
					ticked[system] = true
		_judge(path, fn, ticked, found_allowed)
	# An allowance nothing needs any more is a hole a future copy walks through.
	for key in ALLOWED.keys():
		if not found_allowed.has(key):
			_fail("ALLOWED names %s, which no longer ticks more than %d systems -- drop the entry" % [key, MAX_HAND_TICKED])


func _judge(path: String, fn: String, ticked: Dictionary, found_allowed: Dictionary) -> void:
	if ticked.size() <= MAX_HAND_TICKED:
		return
	var key := "%s::%s" % [path, fn]
	if ALLOWED.has(key):
		found_allowed[key] = true
		return
	_fail("%s ticks %d month systems by hand -- a copy of the month; call WorldMonth.tick_month instead" % [key, ticked.size()])


func _gd_files() -> Array[String]:
	var out: Array[String] = []
	var pending: Array[String] = []
	pending.append_array(SCAN_DIRS)
	while not pending.is_empty():
		var dir_path: String = pending.pop_back()
		var dir := DirAccess.open(dir_path)
		if dir == null:
			_fail("could not open %s" % dir_path)
			continue
		for sub in dir.get_directories():
			pending.append(dir_path + "/" + sub)
		for name in dir.get_files():
			if name.ends_with(".gd"):
				out.append(dir_path + "/" + name)
	return out


func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	state.year = 2026
	state.month = 1
	return state


func _advance(state) -> void:
	state.month += 1
	if state.month > 12:
		state.month = 1
		state.year += 1


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_world_month: all checks passed")
		quit(0)
		return
	for message in _failures:
		printerr(message)
	printerr("test_world_month: %d check(s) failed" % _failures.size())
	quit(1)
