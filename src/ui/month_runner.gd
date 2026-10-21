extends Node

## The month across frames -- V5.1-0a, and the V5.0 play gate's "half a second
## delay every month. why this freeze every month?". The month ran inside one
## frame: ~245 ms of simulation plus the UI's half, measured 645-712 ms a frame
## at speed 3 with nothing open. Here it runs a unit at a time
## (src/sim/world_month.gd's cursor) under a frame budget, and the screen goes on
## drawing while it closes.
##
## THE MAIN THREAD, NOT A WORKER, and src/core/parallel.gd's rule 4 is why: on
## this build pow() and exp() on a pool thread return a different last bit from
## the main thread's, so the whole month on a worker would move numbers. Spread
## over frames on the main thread it is the same code in the same order, with
## nothing written between two units -- byte-identical by construction.
##
## WHAT HOLDS WHILE IT RUNS, so nothing reads or writes half a month:
##   - the clock: no day advances, and the 1st's day_advanced waits for the
##     month (Clock.hold() / release());
##   - every input event: deferred here, ahead of the GUI, and replayed in order
##     once the month is done -- a click mid-month would write state between two
##     units, a key could open a panel onto half a month;
##   - the windows: their processing stops, so every panel holds the frame it
##     last drew, and refreshes on the month's own sweep at the end.
## What still moves: the draw, the cards the month's hooks push as it goes, and
## the clock's date, dimmed while the month closes (clock_cluster.gd).
##
## A hand-driven day -- a test or a tool calling Clock.advance_one_day() -- gets
## its month whole before the call returns, as every harness always has.

const WorldMonth = preload("res://src/sim/world_month.gd")

## Simulation per frame. At 60 Hz with vsync a frame has 16.7 ms; this leaves the
## UI and the draw ~4 ms of it, so a month of small units keeps 60 fps. A unit
## longer than the budget (the costliest step whole is ~45 ms) runs alone in its
## frame -- the reason Economy and Diplomacy come in slices.
const FRAME_BUDGET_USEC := 12000

var _month = null          # WorldMonth.Month while one is closing
var _done := Callable()
var _clock: Node = null
var _held: Node = null
## WorldMonth.unit_key() -> that unit's cost last month, usec: the estimate that
## keeps a unit known to be long out of a frame already part spent.
var _cost := {}
## V5.1-0b. The last month's cost per step, microseconds -- step name -> usec,
## summed over the step's units: the perf overlay's numbers (src/ui/dev_perf.gd).
## Timed here, per UNIT, because Economy and Diplomacy come in slices that can span
## frames: the step hook's before/after would measure the frames between them, not
## the work. Only a real-time month fills it; a hand-driven one runs whole.
var last_month_costs := {}
var _month_costs := {}
var _deferred: Array[InputEvent] = []


## One month, then `done.call(report)`. Real time passing is spread across
## frames, holding `clock` and `held` (the windows) until the month is done; a
## hand-driven day runs it whole, now.
func run(state, loader, on_step: Callable, done: Callable, clock: Node, held: Node) -> void:
	if not clock.in_real_time:
		# The table times the last REAL-TIME month; a hand-driven one runs whole and
		# is not timed, so the old table would pass for current. Clear it instead.
		last_month_costs = {}
		done.call(WorldMonth.tick_month(state, loader, on_step))
		return
	_month = WorldMonth.begin(state, loader, on_step)
	_month_costs = {}
	_done = done
	_clock = clock
	_held = held
	clock.hold()
	held.process_mode = Node.PROCESS_MODE_DISABLED


func running() -> bool:
	return _month != null


func _process(_delta: float) -> void:
	if _month == null:
		return
	var start := Time.get_ticks_usec()
	var ran := false
	while not WorldMonth.done(_month):
		var key := WorldMonth.unit_key(_month)
		var now := Time.get_ticks_usec()
		if ran and now - start + int(_cost.get(key, 0)) > FRAME_BUDGET_USEC:
			break
		var step: String = WorldMonth.STEPS[_month.step]
		WorldMonth.run_unit(_month)
		var spent := Time.get_ticks_usec() - now
		_cost[key] = spent
		_month_costs[step] = int(_month_costs.get(step, 0)) + spent
		ran = true
	if not WorldMonth.done(_month):
		return
	var report: Dictionary = _month.report
	last_month_costs = _month_costs
	_month = null
	_held.process_mode = Node.PROCESS_MODE_INHERIT
	# The month's end in the order it always ran: the UI's tail first, then the
	# 1st's day_advanced (an appointment acts after the month), then the input
	# the player gave while it closed.
	_done.call(report)
	_clock.release()
	var events := _deferred
	_deferred = []
	for event in events:
		get_viewport().push_input(event, true)


func _input(event: InputEvent) -> void:
	if _month == null:
		return
	_deferred.append(event)
	get_viewport().set_input_as_handled()
