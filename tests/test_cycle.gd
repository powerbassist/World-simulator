extends SceneTree

## Headless test: godot --headless --script res://tests/test_cycle.gd
## Non-zero exit on any failure.
##
## V1.6a. The business cycle. Five properties, of which two are architectural claims
## checked by reading the source file -- the idiom docs/people-model.md,
## docs/calendar-model.md, docs/society-model.md and docs/demography-model.md all use,
## and it is doing more work here than usual: this module's whole design is that it has
## NO STATE AND NO TICK, and both are invisible to a behavioural test.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const K = preload("res://src/sim/cycle_constants.gd")

const MONTHS := 168
const START_YEAR := 2026

var _failures: Array[String] = []
var _loader


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return

	_check_zero_at_the_epoch()
	_check_determinism()
	_check_the_ten_differ()
	_check_amplitude_is_content()
	_check_projection_reproduces_the_cycle()
	_check_no_tick_and_no_state()
	_check_single_writer()

	_finish()


## The opening month reads EXACTLY 0.0 for all ten, and the reason is the content
## rather than a re-run: `imported.unemployment_pct` and SECTOR_TREND describe a nation
## at potential, so a cycle that started mid-slump would contradict its own data file on
## the first frame the player sees.
func _check_zero_at_the_epoch() -> void:
	var state = _new_state("FRA")
	for ns in state.nations.values():
		var v: float = Cycle.impulse_pct(ns, K.CYCLE_EPOCH_YEAR, K.CYCLE_EPOCH_MONTH)
		if v != 0.0:
			_fail("epoch: %s reads %.9f at the epoch month, not exactly 0.0" % [ns.id, v])

	# ...and it does NOT stay there, which is the other half. A term that is always zero
	# is the decorative-axis failure docs/scenario-model.md records.
	var moved := false
	for m in range(1, 60):
		if absf(Cycle.impulse_pct(state.player(), START_YEAR + int(m / 12), (m % 12) + 1)) > 0.1:
			moved = true
			break
	if not moved:
		_fail("epoch: FRA's impulse never left 0.0 in five years -- the cycle is decorative")


## No randomness anywhere, which is what makes Budget.project() equal to what happens.
## Two states built independently must agree to the bit, and the same month must give
## the same answer whenever it is asked -- there is no sequence state to advance.
func _check_determinism() -> void:
	var a = _new_state("FRA")
	var b = _new_state("FRA")
	for m in range(60):
		var year: int = START_YEAR + int(m / 12)
		var month: int = (m % 12) + 1
		for id in a.nations.keys():
			var x: float = Cycle.impulse_pct(a.nations[id], year, month)
			var y: float = Cycle.impulse_pct(b.nations[id], year, month)
			if x != y:
				_fail("determinism: %s month %d gave %.12f then %.12f" % [id, m, x, y])
				return
	# Order-independence: asking for month 40 before month 3 must not change month 3.
	var late: float = Cycle.impulse_pct(a.player(), START_YEAR + 3, 5)
	var early: float = Cycle.impulse_pct(a.player(), START_YEAR, 4)
	var early_again: float = Cycle.impulse_pct(a.player(), START_YEAR, 4)
	if early != early_again:
		_fail("determinism: the same month answered %.12f then %.12f -- there is sequence state" % [early, early_again])
	if late == early and not is_zero_approx(late):
		_fail("determinism: two different months gave the identical non-zero value")


## The ten must not move as one. A shared zero phase with no per-nation draw would put
## every nation into recession in the same month, which is the clustered
## `coalition_position` failure docs/foreign-policy-model.md records, in a new place.
func _check_the_ten_differ() -> void:
	var state = _new_state("FRA")
	var signs_seen := {}
	for m in range(6, 24):
		var year: int = START_YEAR + int(m / 12)
		var month: int = (m % 12) + 1
		var up := 0
		var down := 0
		for ns in state.nations.values():
			if Cycle.impulse_pct(ns, year, month) > 0.0:
				up += 1
			else:
				down += 1
		signs_seen[m] = [up, down]
		if up > 0 and down > 0:
			return
	_fail("divergence: no month in the first two years had nations moving both ways: %s" % [signs_seen])


## `cycle_amplitude_rel` is content and it must reach the model. France is the quietest
## of the ten at 0.689 and Luxembourg the loudest at 1.475, so their long-run spreads
## must differ in that direction -- otherwise the import is decorative and the whole
## measured-not-authored argument is empty.
func _check_amplitude_is_content() -> void:
	var state = _new_state("FRA")
	var fra = state.nations["FRA"]
	var lux = state.nations["LUX"]
	if fra.cycle_amplitude_rel >= lux.cycle_amplitude_rel:
		_fail("content: FRA's amplitude_rel %.3f is not below LUX's %.3f -- the import is wrong" % [
			fra.cycle_amplitude_rel, lux.cycle_amplitude_rel
		])
		return

	var fra_peak := 0.0
	var lux_peak := 0.0
	for m in range(MONTHS):
		var year: int = START_YEAR + int(m / 12)
		var month: int = (m % 12) + 1
		fra_peak = maxf(fra_peak, absf(Cycle.impulse_pct(fra, year, month)))
		lux_peak = maxf(lux_peak, absf(Cycle.impulse_pct(lux, year, month)))
	if fra_peak >= lux_peak:
		_fail("content: FRA peaks at %.3f and LUX at %.3f, but LUX is authored 2.1x louder" % [
			fra_peak, lux_peak
		])


## THE FORECAST BAND RESTS ENTIRELY ON THIS, and it is the reason the cycle is written
## inside Economy.tick_month() rather than as a system of its own with a tick to wire.
## Budget.project() runs the real model on a copy; if the cycle did not reproduce there,
## the one surface in the game that promises "this is what will happen" would be wrong
## by the size of a recession, and src/ui/budget_panel.gd's band would be drawn around a
## path that is not the path.
func _check_projection_reproduces_the_cycle() -> void:
	var state = _new_state("FRA")
	# Twelve months in, so the cycle is well off its epoch zero before the comparison.
	for m in range(12):
		state.year = START_YEAR + int(m / 12)
		state.month = (m % 12) + 1
		Economy.tick_month(state)
		Budget.tick_month(state)

	var projected := Budget.project(state, {}, 12, _loader)
	var moved := false
	for row in projected:
		if absf(float(row.get("cycle_impulse_pct", 0.0))) > 0.1:
			moved = true
	if not moved:
		_fail("projection: twelve projected months carry no cycle at all -- the band would be flat")

	# ...and it must be the SAME path. Advance the real game over the same window and
	# compare month by month, which is tests/test_budget.gd's equality check narrowed to
	# the one field this session added.
	for i in range(projected.size()):
		var m: int = 12 + i
		state.year = START_YEAR + int(m / 12)
		state.month = (m % 12) + 1
		Economy.tick_month(state)
		Budget.tick_month(state)
		var real: float = state.player().cycle_impulse_pct
		var guess: float = float(projected[i].get("cycle_impulse_pct", 0.0))
		if absf(real - guess) > 1.0e-9:
			_fail("projection: month %d projected %.9f and delivered %.9f" % [i + 1, guess, real])
			return


## The architectural claim, checked by reading the file. src/sim/cycle.gd must have NO
## tick_month() and NO accumulator: the whole design is that every harness reaches it
## through Economy.tick_month() and so cannot forget it, which is what
## docs/decision-log.md's V1.5d entry cost a session to learn. A later session adding a
## tick turns this red and has to come and say why.
func _check_no_tick_and_no_state() -> void:
	var source := FileAccess.get_file_as_string("res://src/sim/cycle.gd")
	if source == "":
		_fail("source: could not read src/sim/cycle.gd")
		return
	for line in source.split("\n"):
		var stripped := line.strip_edges()
		if stripped.begins_with("#"):
			continue
		if stripped.begins_with("static func tick_month") or stripped.begins_with("func tick_month"):
			_fail("source: cycle.gd has grown a tick_month() -- every harness reaches it through Economy.tick_month() precisely so none can forget it")
		# The RAW line, not the stripped one: a class member sits at column zero and a
		# local is indented inside a function. Stripping first caught twelve locals and
		# said the module was stateful, which is the check reading the wrong thing --
		# this session's own error, three tables running.
		if line.begins_with("var ") or line.begins_with("@export"):
			_fail("source: cycle.gd declares state (%s) -- the generator is a pure function of the clock and a stored phase would break Budget.project()" % stripped)


## `cycle_impulse_pct` has exactly one writer and it is Economy.tick_month(). The
## discipline `share`, `state_share`, `regulation_burden`, `migration_stance`,
## `settlement_stance` and `gini_index` all hold to, asserted the same way.
func _check_single_writer() -> void:
	var writers: Array[String] = []
	for path in ["res://src/sim/cycle.gd", "res://src/sim/budget.gd", "res://src/sim/companies.gd",
			"res://src/sim/unrest.gd", "res://src/sim/society.gd", "res://src/sim/demography.gd",
			"res://src/sim/trade.gd", "res://src/sim/coercion.gd"]:
		var source := FileAccess.get_file_as_string(path)
		for line in source.split("\n"):
			var stripped := line.strip_edges()
			if stripped.begins_with("#"):
				continue
			if stripped.contains("cycle_impulse_pct =") or stripped.contains("cycle_impulse_pct +="):
				writers.append("%s: %s" % [path, stripped])
	if not writers.is_empty():
		_fail("single writer: cycle_impulse_pct is assigned outside Economy.tick_month(): %s" % [writers])


func _new_state(nation_id: String):
	var state = GameState.new_game(_loader, nation_id)
	state.year = START_YEAR
	state.month = 1
	return state


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_cycle: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
