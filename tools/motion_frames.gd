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
##   layer_*.png   -- V4.9b: the map toggled political -> relations, at the
##                    toggle, mid-crossfade and settled
##   night_*.png   -- V4.9b: the June 2029 double election's count, at its
##                    start, past a third and two thirds of the regions, the
##                    verdict's first frame, and settled
##
##   godot --path "<repo>" --script res://tools/motion_frames.gd
##
## Windowed on purpose, like screenshot.gd: headless draws nothing.

const Motion = preload("res://src/ui/motion.gd")
const MapLayers = preload("res://src/ui/map_layers.gd")
const OsCursor = preload("res://tools/os_cursor.gd")

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
var _layer_frame := -1
var _layer_started := 0
var _night_started := 0


func _init() -> void:
	OsCursor.quiet_window()  # a capture needs neither the keyboard nor the real mouse
	Motion.override = 1
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_menu = load("res://src/ui/menu.tscn").instantiate()
	root.add_child(_menu)
	OsCursor.quiet_window()  # the menu's _ready applied the saved window mode just now


func _process(_delta: float) -> bool:
	OsCursor.quiet_window()  # again each frame: the saved settings may re-centre it
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
				_game._windows.close("budget")
				_phase = "layer"
			return false
		"layer":
			if _layer_frame < 0:
				_game._map_view.set_layer(MapLayers.RELATIONS)
				_layer_frame = _frame
				_layer_started = Time.get_ticks_msec()
				_shoot("layer_1_toggled")
				return false
			# Frames AND time again: the toggle frame carries a PNG save, and on
			# time alone the "mid" shot was the frame right after the toggle.
			_once("layer_2_mid", _frame >= _layer_frame + 3 and _game._map_view._layer_blend >= 0.4)
			if _frame >= _layer_frame + 10 and Time.get_ticks_msec() - _layer_started > int(Motion.LAYER_S * 1000.0) + 200:
				_shoot("layer_3_settled")
				_game._map_view.set_layer(MapLayers.POLITICAL)
				Motion.finish(_game._map_view)
				_phase = "night"
				_stage_the_double_election()
				_night_started = _frame
			return false
		"night":
			var panel = _game._election_panel
			if panel._night == null:
				return false
			var n: int = panel._night.size()
			_once("night_1_start", _frame == _night_started + 2)
			_once("night_2_third", _declared(panel) >= n / 3)
			_once("night_3_two_thirds", _declared(panel) >= (2 * n) / 3)
			if panel._revealed and not _shots.has("night_4_verdict"):
				_night_started = _frame
				_shoot("night_4_verdict")
			if _shots.has("night_4_verdict") and _frame >= _night_started + 30:
				_shoot("night_5_settled")
				print("motion_frames: %d captures in %s" % [_shots.size(), ProjectSettings.globalize_path(OUT_DIR)])
				return true
			return false
	return false


## Regions declared, read off the ticker ("7 of 13 regions declared ...").
func _declared(panel) -> int:
	var text: String = panel._ticker.text
	if not text.contains(" of "):
		return 0
	return text.get_slice(" ", 0).to_int()


## The double election of June 2029, 41 months on: the first plate with seat
## bars. The May 2027 presidential plate fires on the way and is replaced, the
## same read a player gets -- tools/screenshot.gd's --tally staging.
func _stage_the_double_election() -> void:
	var clock = _game._clock
	var target: int = clock.year * 12 + clock.month + 41
	while clock.year * 12 + clock.month < target:
		clock.advance_one_day()


func _once(name: String, condition: bool) -> void:
	if condition and not _shots.has(name):
		_shoot(name)


## The framebuffer of the PREVIOUS draw: _process runs before this frame's draw,
## so each capture is what the player saw one frame ago -- consistent across
## every shot, which is what a sequence needs.
func _shoot(name: String) -> void:
	_shots[name] = true
	if name.begins_with("layer_"):
		print("motion_frames: %s at frame %d, map blend %.2f" % [name, _frame, _game._map_view._layer_blend])
	elif name.begins_with("night_"):
		print("motion_frames: %s at frame %d, ticker '%s'" % [name, _frame, _game._election_panel._ticker.text])
	elif _game != null and _game._windows._frames.has("budget"):
		var f: Control = _game._windows._frames["budget"]
		print("motion_frames: %s at frame %d, budget window alpha %.2f scale %.3f" % [name, _frame, f.modulate.a, f.scale.x])
	var image := root.get_texture().get_image()
	var path := ProjectSettings.globalize_path(OUT_DIR.path_join(name + ".png"))
	image.save_png(path)
