extends SceneTree

## Headless test: godot --headless --script res://tests/test_effect_baselines.gd
## Non-zero exit on any failure.
##
## QA's pre-gate issue 2: the "before" a command's effect is measured from was
## Budget.snapshot() at twelve sites, which has no approval in it, so
## Trends.movements_between() gave Approval a NaN change -- the Overview dropped
## the row and the save wrote null. Every baseline is Trends.snapshot_now(),
## which carries opinion beside the budget.
##
##   - an event answered through the Events window, a month later, sits in
##     recent_effects with a NUMBER for Approval;
##   - no UI file takes an effect baseline from Budget.snapshot() any more
##     (trends.gd builds snapshot_now() out of it, and is the one reader).

const Events = preload("res://src/sim/events.gd")
const Trends = preload("res://src/ui/trends.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_check_an_answer_moves_approval()
	_check_no_budget_baseline()
	_finish()
	return true


func _check_an_answer_moves_approval() -> void:
	var ns = _main._state.player()
	var ev = null
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt) and not candidate.choices.is_empty():
			ev = candidate
			break
	if ev == null:
		_fail("no quiet event with choices to answer")
		return
	ns.event_queue.clear()
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	_main._pending_effects.clear()
	_main._events_panel._on_choose(ev, ev.choices[0])
	if _main._pending_effects.size() != 1:
		_fail("premise: answering queued %d effects, not 1" % _main._pending_effects.size())
		return
	var clock = _main._clock
	clock.set_process(false)
	var month: int = clock.month
	while clock.month == month:
		clock.advance_one_day()
	if _main._state.recent_effects.is_empty():
		_fail("the answered event left no recent effect after its month")
		return
	var found := false
	for movement in _main._state.recent_effects[0]["movements"]:
		if String(movement["key"]) == Trends.APPROVAL_KEY:
			found = true
			if is_nan(float(movement["change"])):
				_fail("the answered event's Approval change is NaN")
	if not found:
		_fail("the answered event's effect has no Approval row")


func _check_no_budget_baseline() -> void:
	var dir := DirAccess.open("res://src/ui")
	for file in dir.get_files():
		if not file.ends_with(".gd") or file == "trends.gd":
			continue
		var source := FileAccess.get_file_as_string("res://src/ui/".path_join(file))
		for line in source.split("\n"):
			if line.contains("Budget.snapshot(") and not line.strip_edges().begins_with("#"):
				_fail("%s takes a baseline from Budget.snapshot(), which has no approval: %s" % [file, line.strip_edges()])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_effect_baselines: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
