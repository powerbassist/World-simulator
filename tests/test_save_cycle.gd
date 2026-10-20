extends SceneTree

## Headless test: godot --headless --script res://tests/test_save_cycle.gd
## Non-zero exit on any failure.
##
## The V5.0 play gate's crash, as a cycle a player runs rather than a round trip
## a test builds: a game with a public work started from its panel and a month
## played, SAVED through main.gd's own handler, the game left for the menu, and
## the save CONTINUED through the menu's loading screen -- then the Overview,
## the first panel to redraw, drawn on the loaded game.
##
## The defect it pins: a decision's figure with no "before" reading (the
## projects panel's baseline is Budget.snapshot(), which carries no approval)
## moves by NAN, "no data", and the Overview filters it with is_nan(). The save
## wrote that NAN as JSON null, the load handed it back as Nil, and is_nan(Nil)
## is a SCRIPT ERROR -- which the editor's debugger stops on: the author's
## "crash" on loading their save (2026-10-20). tools/suite_runner.py fails a run
## on a SCRIPT ERROR line, and the label check below fails without one.

const SaveManager = preload("res://src/core/save_manager.gd")
const Projects = preload("res://src/sim/projects.gd")

const SLOT := "__test_save_cycle__"
const START_TIMEOUT_FRAMES := 3000

var _failures: Array[String] = []
var _frame := 0
var _phase := "boot"
var _game
var _menu
var _loaded
var _label := ""
var _project_ids: Array = []
var _waited := 0


func _init() -> void:
	_game = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_game)


func _process(_delta: float) -> bool:
	_frame += 1
	match _phase:
		"boot":
			if _frame < 2:
				return false  # let the game's _ready() run
			if not _play_and_save():
				_cleanup()
				_finish()
				return false
			# Back to the menu: the game goes, a fresh menu comes, as the pause
			# menu's Main Menu does through change_scene_to_file().
			_game.queue_free()
			_phase = "menu"
		"menu":
			_menu = load("res://src/ui/menu.tscn").instantiate()
			root.add_child(_menu)
			_phase = "start"
		"start":
			_menu._start_game(SLOT)
			if _menu._loading == null:
				_fail("continuing the save put up no loading screen")
				_cleanup()
				_finish()
				return false
			_menu._loading.entered.connect(func(game: Node): _loaded = game)
			_phase = "wait"
		"wait":
			if _loaded == null:
				_waited += 1
				if _waited > START_TIMEOUT_FRAMES:
					_fail("the continued save never entered its game in %d frames" % START_TIMEOUT_FRAMES)
					_cleanup()
					_finish()
				return false
			_loaded._windows.open("overview")
			_loaded._overview_panel.mark_dirty()
			_phase = "draw"
		"draw":
			# One frame for the Overview's _process() to redraw on the loaded game.
			_phase = "check"
		"check":
			_check_loaded()
			_cleanup()
			_finish()
	return false


## A month of play the way the author's went: a public work started from its
## panel's own button, the month elapsed through main.gd's own handler (which
## writes the decision's movements at the History step), then SAVE.
func _play_and_save() -> bool:
	var state = _game._state
	var ns = state.player()
	var actions: Array = Projects.available(state, ns, _game._loader.project_actions)
	if actions.is_empty():
		_fail("no public work is available to start on a new game")
		return false
	_game._projects_panel._on_act(ns, actions[0])
	if _game._pending_effects.is_empty():
		_fail("starting '%s' from the projects panel queued no decision" % actions[0].action_name)
		return false
	_project_ids = ns.projects.keys()
	if _project_ids.is_empty():
		_fail("starting '%s' put nothing on the projects register" % actions[0].action_name)
		return false

	var year: int = state.year + (1 if state.month == 12 else 0)
	var month: int = 1 if state.month == 12 else state.month + 1
	_game._on_month_elapsed(year, month)
	if state.recent_effects.is_empty():
		_fail("the month elapsed and recorded no decision")
		return false
	var entry: Dictionary = state.recent_effects[0]
	_label = String(entry["label"])
	var has_nan := false
	for m in entry["movements"]:
		if is_nan(float(m["severity"])):
			has_nan = true
	if not has_nan:
		_fail("premise: '%s' moved no figure by NAN, so the save carries nothing the load can drop" % _label)
		return false

	_game._on_save_requested(SLOT)
	if not FileAccess.file_exists(SaveManager._path_for(SLOT)):
		_fail("SAVE through main.gd wrote no file")
		return false
	return true


func _check_loaded() -> void:
	if _loaded._state == null or _loaded._state.recent_effects.is_empty():
		_fail("the continued game has no recent decisions -- the save did not load")
		return
	var entry: Dictionary = _loaded._state.recent_effects[0]
	if String(entry["label"]) != _label:
		_fail("the continued game's last decision is '%s', expected '%s'" % [entry["label"], _label])
	for m in entry["movements"]:
		for key in ["change", "severity"]:
			if typeof(m[key]) != TYPE_FLOAT:
				_fail("a loaded movement's %s is %s, not a number -- NAN did not survive the save" % [key, type_string(typeof(m[key]))])
				return
	if not _collect_text(_loaded._overview_panel).contains(_label):
		_fail("the Overview did not draw '%s' on the continued game" % _label)
	for project_id in _project_ids:
		if not _loaded._state.player().projects.has(project_id):
			_fail("the started work '%s' did not survive the save" % project_id)


func _collect_text(node) -> String:
	var out := ""
	if node.is_queued_for_deletion():
		return out
	if node is Label or node is Button:
		out += node.text + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


func _cleanup() -> void:
	var dir := DirAccess.open(SaveManager.SAVE_DIR)
	if dir == null:
		return
	for p in [SaveManager._path_for(SLOT), SaveManager._path_for(SLOT) + SaveManager.TEMP_SUFFIX]:
		if FileAccess.file_exists(p):
			dir.remove(p)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_save_cycle: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
