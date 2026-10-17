extends SceneTree

## V4.9a. SEQUENCE captures of what moves, because a single frame of motion
## either catches a tween mid-flight and looks broken or catches it settled
## and says nothing (tools/screenshot.gd forces motion off for that reason).
## Two sequences, written to reports/motion_frames/ (gitignored):
##
##   loading_*.png -- menu -> New Game: the loading screen at its first frame,
##                    past 30 % and 60 % of the bar, at the enter stage, and
##                    the first frame of the fade off the game
##   open_*.png    -- a window opening: the frame it is opened on, two frames
##                    into the tween, and settled
##
##   godot --path "<repo>" --script res://tools/motion_frames.gd
##
## Windowed on purpose, like screenshot.gd: headless draws nothing.

const Motion = preload("res://src/ui/motion.gd")

const OUT_DIR := "res://reports/motion_frames"
const TIMEOUT_FRAMES := 5000

var _menu: Node
var _loading
var _game: Node
var _frame := 0
var _phase := "boot"
var _shots := {}
var _entered_frame := -1
var _open_frame := -1
var _open_started := 0


func _init() -> void:
	Motion.override = 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_menu = load("res://src/ui/menu.tscn").instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame > TIMEOUT_FRAMES:
		printerr("motion_frames: timed out in phase %s" % _phase)
		return true
	match _phase:
		"boot":
			if _frame == 3:
				_menu._start_game("", "FRA")
				_loading = _menu._loading
				_loading.entered.connect(func(game: Node):
					_game = game
					_entered_frame = _frame
				)
				return false
			if _frame < 4:
				return false
			if _game == null:
				var p: float = _loading.boot.progress()
				_once("loading_1_first", _frame == 5)
				_once("loading_2_past30", p >= 0.3)
				_once("loading_3_past60", p >= 0.6)
				_once("loading_4_enter", _loading.boot.ready_to_enter())
				return false
			# The frame after entering: the screen sits over the game, fading.
			_once("loading_5_fade", _frame == _entered_frame + 1)
			if _frame > _entered_frame + 60:
				_phase = "open"
			return false
		"open":
			if _open_frame < 0:
				_game._windows.open("budget")
				_open_frame = _frame
				_open_started = Time.get_ticks_msec()
				_shoot("open_1_opened")
				return false
			_once("open_2_mid", _frame == _open_frame + 2)
			# Frames AND time: opening a heavy window costs one long build frame,
			# and a wall-clock test alone fired on the frame right after it --
			# capturing the tween's first step and calling it settled.
			if _frame >= _open_frame + 20 and Time.get_ticks_msec() - _open_started > int(Motion.OPEN_S * 1000.0) + 200:
				_shoot("open_3_settled")
				print("motion_frames: %d captures in %s" % [_shots.size(), ProjectSettings.globalize_path(OUT_DIR)])
				return true
			return false
	return false


func _once(name: String, condition: bool) -> void:
	if condition and not _shots.has(name):
		_shoot(name)


## The framebuffer of the PREVIOUS draw: _process runs before this frame's draw,
## so each capture is what the player saw one frame ago -- consistent across
## every shot, which is what a sequence needs.
func _shoot(name: String) -> void:
	_shots[name] = true
	if _game != null and _game._windows._frames.has("budget"):
		var f: Control = _game._windows._frames["budget"]
		print("motion_frames: %s at frame %d, budget window alpha %.2f scale %.3f" % [name, _frame, f.modulate.a, f.scale.x])
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(name + ".png"))
	image.save_png(path)
