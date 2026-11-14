extends SceneTree

## The goal read's frame gate (docs/design/finance-bill.md section 11, the parent's
## ruling 1 of 2026-11-14): one tier-1 read is a ~30 ms state copy that cannot be sliced,
## so the frame time it costs is measured beside the budget forecast's own, the gate being
## "no worse than the budget forecast already is". Dev-only, never ships.
##
##   APPDATA="$(mktemp -d)" godot --headless --path . --script res://tools/goal_read_frame_probe.gd
##
## Each phase runs its units the way budget_forecast.gd's _advance() does: per frame, at
## least one unit, then more while FRAME_BUDGET_USEC is left. The figure is the WORK each
## frame carries, in ms: the render is the same frame either way, so the difference
## between phases is this work and nothing else. Headless on purpose: a windowed run takes
## the author's keyboard (AGENTS.md), and adds a draw that does not depend on the phase.
## Run ALONE (a timing probe: CPU contention reads as cost).
##
## Phases, France at game start: (1) the budget forecast's "now" projection, 24 months;
## (2) tier 1 filling, every measure; (3) one tier-2 run, the baseline then the measure.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Budget = preload("res://src/sim/budget.gd")
const GoalRead = preload("res://src/sim/goal_read.gd")
const BudgetForecast = preload("res://src/ui/budget_forecast.gd")
const Net = preload("res://src/sim/network.gd")

var _loader
var _state
var _phase := 0
var _frames: Array[float] = []
var _job
var _list
var _years
var _first_unit_ms := -1.0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	_state = GameState.new_game(_loader, "FRA")
	_state.year = 2026
	_state.month = 1
	# The distance table warmed as the game warms it at boot (main.gd, behind the loading
	# screen). Without it the first unit built the ~4.4 s table inside one frame, a freeze
	# the game never has: the "4.57 s first projection" this probe once reported.
	Net.warm(_state.region_graph)
	_job = Budget.projection(_state, {}, 24, _loader)


func _process(_delta: float) -> bool:
	var start := Time.get_ticks_usec()
	var ran := false
	var finished := false
	while true:
		if ran and Time.get_ticks_usec() - start >= BudgetForecast.FRAME_BUDGET_USEC:
			break
		var unit := Time.get_ticks_usec()
		finished = _unit()
		if _first_unit_ms < 0.0:
			_first_unit_ms = (Time.get_ticks_usec() - unit) / 1000.0
		ran = true
		if finished:
			break
	_frames.append((Time.get_ticks_usec() - start) / 1000.0)
	if finished:
		_report()
		_frames.clear()
		_first_unit_ms = -1.0
		_phase += 1
		if _phase == 1:
			_list = GoalRead.list_for(null, _state, _loader)
		elif _phase == 2:
			_years = GoalRead.years_for(null, _state, _loader, {"kind": "line", "key": "education", "step": 0.5})
		else:
			return true
	return false


## One unit of the phase; true when the phase is over.
func _unit() -> bool:
	match _phase:
		0:
			Budget.projection_step(_job)
			return Budget.projection_done(_job)
		1:
			GoalRead.step(_list)
			return _list.done()
	_years.step()
	return _years.done()


func _report() -> void:
	var name: String = ["budget forecast (24 months)", "tier 1 (France, every measure)", "tier 2 (baseline + one measure)"][_phase]
	var sorted := _frames.duplicate()
	sorted.sort()
	var total := 0.0
	for f in _frames:
		total += f
	print("%s: %d frames, max %.1f ms, p95 %.1f ms, mean %.1f ms, total %.2f s, first unit %.1f ms" % [
		name, _frames.size(), sorted[sorted.size() - 1], sorted[int(floor(0.95 * (sorted.size() - 1)))],
		total / _frames.size(), total / 1000.0, _first_unit_ms])
