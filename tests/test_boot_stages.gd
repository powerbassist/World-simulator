extends SceneTree

## V4.9a. The staged boot behind the loading screen (src/ui/boot_stages.gd):
## its stage table is complete and weighs something, its bar never goes back,
## it hands main.gd the loader and state it built (and main.gd TAKES them --
## a main that quietly rebuilt its own would still boot, just twice as slowly,
## which is the silent failure this pins), and a load passes its slot through.

const BootStages = preload("res://src/ui/boot_stages.gd")
const Net = preload("res://src/sim/network.gd")

const SaveManager = preload("res://src/core/save_manager.gd")
const SAVED_SLOT := "__test_boot_stages_deu__"
const HANDLED := ["scene", "data", "world", "network", "enter"]
const TIMEOUT_FRAMES := 4000

var _failures: Array[String] = []
var _boot
var _progress: Array[float] = []
var _labels := {}
var _frame := 0
var _phase := "new"
var _game: Node


func _init() -> void:
	_check_table()
	_boot = BootStages.new("DEU", "", "")


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > TIMEOUT_FRAMES:
		_fail("the %s boot never reached its enter stage in %d frames" % [_phase, TIMEOUT_FRAMES])
		_report()
		return true
	match _phase:
		"new":
			if not _boot.ready_to_enter():
				_progress.append(_boot.progress())
				_labels[_boot.label()] = true
				_boot.step(50_000)
				return false
			_check_new_game_ready()
			_game = _boot.game
			root.add_child(_game)
			_phase = "entered"
			return false
		"entered":
			_check_main_took_them()
			# Second boot in the same process: the network table is warm, so
			# that stage must finish on its first step.
			_boot = BootStages.new("", "", "__no_such_slot__")
			_phase = "load"
			return false
		"load":
			if not _boot.ready_to_enter():
				var before: String = _boot.stage_id()
				_boot.step(50_000)
				if before == "network" and _boot.stage_id() == "network":
					_fail("a warm network table took more than one step on a second boot")
				return false
			_check_load_ready()
			# A save that reads: the boot goes straight into it (game_reload.gd), no France first.
			var error: String = SaveManager.save_game(_game._state, _game._clock, SAVED_SLOT)
			if error != "":
				_fail("could not write the Germany save: %s" % error)
				_report()
				return true
			_boot = BootStages.new("", "", SAVED_SLOT)
			_phase = "saved"
			return false
		"saved":
			if not _boot.ready_to_enter():
				_boot.step(50_000)
				return false
			_check_saved_load_ready()
			SaveManager.delete_slot(SAVED_SLOT)
			_report()
			return true
	return false


## A menu load of a save that reads boots straight into the save's nation: the state the game is
## handed is the save's, the slot is spent, and no throwaway game of main's default nation is built.
func _check_saved_load_ready() -> void:
	var game: Node = _boot.game
	if game.pending_save.is_empty():
		_fail("a load boot of a readable save handed the game no save")
	elif not is_same(game.pending_save["state"], game.pending_state):
		_fail("a load boot built a state beside the save's")
	if game.pending_load_slot != "":
		_fail("a load boot of a readable save left slot '%s' for main to load again" % game.pending_load_slot)
	if game.pending_state == null or game.pending_state.player_nation_id != "DEU":
		_fail("a load boot of a Germany save built a game for '%s'" % (game.pending_state.player_nation_id if game.pending_state != null else "nothing"))
	game.free()


func _check_table() -> void:
	var ids := []
	for s in BootStages.STAGES:
		ids.append(String(s["id"]))
		if int(s["ms"]) <= 0:
			_fail("stage %s weighs %d ms -- the bar could not move through it" % [s["id"], int(s["ms"])])
		if String(s["label"]).is_empty():
			_fail("stage %s has no label to show" % s["id"])
	if ids != HANDLED:
		_fail("BootStages.STAGES lists %s, step() handles %s in that order" % [ids, HANDLED])


func _check_new_game_ready() -> void:
	for i in range(1, _progress.size()):
		if _progress[i] < _progress[i - 1]:
			_fail("the boot's progress went backwards: %.4f after %.4f" % [_progress[i], _progress[i - 1]])
			break
	if _progress.is_empty() or _progress[0] != 0.0:
		_fail("the boot did not start at 0")
	# At "enter" the bar shows exactly what is left: enter's own share.
	var total := 0.0
	var enter_ms := 0.0
	for s in BootStages.STAGES:
		total += float(s["ms"])
		if s["id"] == "enter":
			enter_ms = float(s["ms"])
	if not is_equal_approx(_boot.progress(), 1.0 - enter_ms / total):
		_fail("at the enter stage the bar reads %.4f, expected %.4f" % [_boot.progress(), 1.0 - enter_ms / total])
	for s in BootStages.STAGES:
		if s["id"] != "enter" and not _labels.has(String(s["label"])):
			# A stage that finishes inside one step is still shown for the frame
			# that step ran in -- unless it was skipped, which only errors do.
			_fail("stage %s was never shown" % s["id"])
		if s["id"] != "enter" and not _boot.timings.has(s["id"]):
			_fail("stage %s recorded no timing for tools/boot_stages_probe.gd" % s["id"])
	var game: Node = _boot.game
	if game == null:
		_fail("ready to enter with no game node built")
		return
	if game.is_inside_tree():
		_fail("the boot put the game in the tree itself; entering is the caller's step")
	if game.pending_player_id != "DEU" or game.pending_load_slot != "":
		_fail("the game carries nation '%s' slot '%s', expected DEU and none" % [game.pending_player_id, game.pending_load_slot])
	if game.pending_loader == null or not game.pending_loader.errors.is_empty():
		_fail("the game was handed no loader, or one with errors")
	if game.pending_state == null or game.pending_state.player_nation_id != "DEU":
		_fail("the game was handed no state, or one for the wrong nation")
		return
	if Net.warm_step(game.pending_state.region_graph, 1) != 1.0:
		_fail("the network table was not warm when the boot declared itself ready")


func _check_main_took_them() -> void:
	if _game._loader != _boot.game.pending_loader or _game._state != _boot.game.pending_state:
		_fail("main.gd built its own loader or state instead of taking the boot's")
	if _game._state.player_nation_id != "DEU":
		_fail("the entered game plays '%s', expected DEU" % _game._state.player_nation_id)


func _check_load_ready() -> void:
	var game: Node = _boot.game
	if game.pending_load_slot != "__no_such_slot__":
		_fail("a load boot carries slot '%s'" % game.pending_load_slot)
	# A save that does not read: the boot falls back to a new game around main.gd's own default
	# and keeps the slot, so main's load path says why on the save screen.
	if game.pending_state.player_nation_id != game.DEFAULT_PLAYER_NATION_ID:
		_fail("a load boot built its throwaway state for '%s', expected main.gd's default" % game.pending_state.player_nation_id)
	game.free()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("test_boot_stages: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
