extends RefCounted

## V4.9a. The menu -> game boot, cut into stages a loading screen can draw
## between. Before this, menu.gd's _start_game() instantiated main.tscn and
## main.gd's _ready() did all of it inside one add_child(): ~7 s of frozen
## window at 41 nations, the last 4.5 s of it the network warm alone.
##
## The work is the SAME work main.gd's _ready() does, moved earlier rather than
## duplicated: this builds the DataLoader and the GameState and hands both to
## main.gd through pending_loader / pending_state, and main.gd skips its own
## build when they are set. A direct scene load (every test, every tool) sets
## neither and boots exactly as before -- one path to keep correct, the
## pending_load_slot precedent.
##
## Driven one step per frame: step(budget_usec) does at most one atomic stage,
## or one slice of a sliced one, and returns true once the game node is
## instantiated and waiting to enter the tree. Entering is the caller's job
## (it is what runs main.gd's _ready()), and it is the last stage on the bar.
##
## Lives in src/ui/ because it knows the game scene exists; src/sim/ is only
## ever called (Net.warm_step), never told about scenes.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Net = preload("res://src/sim/network.gd")

const GAME_SCENE := "res://src/ui/main.tscn"

## The bar's truth. `ms` is each stage's MEASURED cost on the author's machine
## (tools/boot_stages_probe.gd, windowed, two runs averaged and rounded,
## 2026-10-17: 7.5-7.7 s in all), and the
## bar's fraction is completed ms over total ms -- so the bar moves at the speed
## the work does, not at a designed pace. A stage that grows (a bigger roster,
## a heavier panel) makes the bar lie only in proportion until the probe is
## re-run and these numbers are copied back; tests/test_boot_stages.gd pins
## that every stage is listed once and weighs something.
##   scene   -- main.tscn and every script it preloads, compiled on a loader
##              thread so frames keep drawing. Godot reports no progress inside
##              it (a script's preloads are not tracked dependencies), so the
##              bar HOLDS here with the stage named rather than inventing a
##              pace -- the one stage whose inside cannot be observed.
##   data    -- DataLoader.load_all(), atomic
##   world   -- GameState.new_game(), atomic
##   network -- Net.warm_step(), sliced by row; its cost includes the frames
##              drawn between slices (~0.5 s at loading_screen.gd's budget)
##   enter   -- main.gd's _ready(): the map, the panels; atomic, and drawn
##              BEFORE it runs, so the bar shows how much is left while it does.
##              Re-measured 2026-10-18 at V4.10a: 1084 ms, up from 780 by the
##              ground's decode + mipmaps + upload in map_view.setup() (~285 ms
##              timed alone); the other four stages held inside their spread.
const STAGES := [
	{"id": "scene", "label": "Compiling the game", "ms": 1300},
	{"id": "data", "label": "Reading the record", "ms": 360},
	{"id": "world", "label": "Founding the world", "ms": 70},
	{"id": "network", "label": "Measuring the distances", "ms": 5000},
	{"id": "enter", "label": "Opening the desk", "ms": 1080},
]

var nation_id := ""
var scenario_id := ""
var load_slot := ""

## What the caller adds to the tree once step() returns true.
var game: Node

## stage id -> measured usec, for tools/boot_stages_probe.gd. "enter" is
## recorded by the caller through record_enter(), since it runs there.
var timings: Dictionary = {}

var _stage := 0
var _fraction := 0.0
var _stage_start := 0
var _loader
var _state
var _scene_requested := false


func _init(p_nation_id: String, p_scenario_id: String, p_load_slot: String) -> void:
	nation_id = p_nation_id
	scenario_id = p_scenario_id
	load_slot = p_load_slot


## Fraction of the whole boot, 0..1: finished stages' weight plus the current
## stage's weight times its own progress. Monotonic, because a stage's own
## fraction only climbs and stages only advance.
func progress() -> float:
	var total := 0.0
	var done := 0.0
	for i in STAGES.size():
		var ms := float(STAGES[i]["ms"])
		total += ms
		if i < _stage:
			done += ms
		elif i == _stage:
			done += ms * _fraction
	return clampf(done / total, 0.0, 1.0)


func label() -> String:
	return String(STAGES[mini(_stage, STAGES.size() - 1)]["label"])


func stage_id() -> String:
	return String(STAGES[mini(_stage, STAGES.size() - 1)]["id"])


## True once `game` is built and the only stage left is entering it.
func ready_to_enter() -> bool:
	return stage_id() == "enter"


func step(budget_usec: int) -> bool:
	if ready_to_enter():
		return true
	if _stage_start == 0:
		_stage_start = Time.get_ticks_usec()
	match stage_id():
		"scene":
			_step_scene()
		"data":
			_loader = DataLoader.new()
			_loader.load_all()
			_advance()
			# A loader with errors builds nothing further: main.gd's own error
			# path reports them and stops, exactly as a direct boot would.
			if not _loader.errors.is_empty():
				_skip_to_enter()
		"world":
			# The game node's own pending_player_id, not nation_id: a load
			# passes no nation, and main.gd's default is what a direct boot
			# would have built the throwaway state around.
			_state = GameState.new_game(_loader, game.pending_player_id, scenario_id)
			_advance()
			if not _state.errors.is_empty():
				_skip_to_enter()
		"network":
			_fraction = Net.warm_step(_state.region_graph, budget_usec)
			if _fraction >= 1.0:
				_advance()
	if ready_to_enter():
		game.pending_loader = _loader
		game.pending_state = _state
	return ready_to_enter()


func record_enter(usec: int) -> void:
	timings["enter"] = usec


func _step_scene() -> void:
	if not _scene_requested:
		_scene_requested = true
		# A second New Game in one process finds the scene already cached and
		# this returns LOADED on the first poll -- the bar skips the stage.
		ResourceLoader.load_threaded_request(GAME_SCENE)
	var out: Array = []
	var status := ResourceLoader.load_threaded_get_status(GAME_SCENE, out)
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		_instantiate()
		_advance()
	elif status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		if not out.is_empty():
			_fraction = maxf(_fraction, float(out[0]))
	else:
		# FAILED or INVALID_RESOURCE: a plain load() in _instantiate()
		# reports the real error where it happens.
		_instantiate()
		_advance()


func _instantiate() -> void:
	var packed: PackedScene
	if _scene_requested and ResourceLoader.load_threaded_get_status(GAME_SCENE) == ResourceLoader.THREAD_LOAD_LOADED:
		packed = ResourceLoader.load_threaded_get(GAME_SCENE)
	else:
		packed = load(GAME_SCENE)
	game = packed.instantiate()
	game.pending_load_slot = load_slot
	if not nation_id.is_empty():
		game.pending_player_id = nation_id
	game.pending_scenario_id = scenario_id


func _advance() -> void:
	timings[stage_id()] = Time.get_ticks_usec() - _stage_start
	_stage += 1
	_fraction = 0.0
	_stage_start = Time.get_ticks_usec()


func _skip_to_enter() -> void:
	while not ready_to_enter():
		_stage += 1
	_fraction = 0.0
