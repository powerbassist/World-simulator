extends SceneTree

## Placement-lag probe -- V5.1-d, G6 of the play gate ("placing on the map with a
## panel still open is laggy and buggy"). Dev-only, never ships.
##
##   APPDATA="$(mktemp -d)" godot --path "<repo>" --script res://tools/placement_probe.gd
##
## WINDOWED, not --headless: there is no renderer headless, so every figure would be
## a lie. Alone on the machine (a timing probe: AGENTS.md, one Godot at a time).
##
## The armed placement mode (energy order, the reticle at the cursor) on the opening
## fit of Paris, clock paused, vsync off, 1920x1080. Four rows, each sampled PASSES
## times in alternation so a drift in the machine lands on every row alike:
##   closed, moving  -- the workspace shut (what d1a does on arming), the pointer
##                      moves over the map;
##   open, moving    -- the energy tab docked, the pointer moves over the same
##                      pixels (now the dock's content, where the player's pointer is);
##   open, idle      -- the tab docked, the pointer still: the cost of the panel itself;
##   closed, idle    -- the shut baseline.
## The pointer is moved through the viewport's own input path (push_input), so the
## routing, the hover and the tooltip timers are the real ones.

const MainScene := "res://src/ui/main.tscn"
const SIZE := Vector2i(1920, 1080)
const BOOT_FRAMES := 40
const SETTLE_FRAMES := 30
const SAMPLE_FRAMES := 240
const PASSES := 2

var _main: Node = null
var _configs: Array = [
	{"label": "closed, moving", "open": false, "move": true},
	{"label": "open, moving", "open": true, "move": true},
	{"label": "open, idle", "open": true, "move": false},
	{"label": "closed, idle", "open": false, "move": false},
]
var _plan: Array = []  # config indices, PASSES times over
var _step := -1
var _boot_left := BOOT_FRAMES
var _settle_left := 0
var _frame_in_sample := 0
var _times: Dictionary = {}  # label -> Array of ms
var _calls: Dictionary = {}  # label -> Array of draw calls
var _armed := false


func _initialize() -> void:
	root.size = SIZE
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_main = load(MainScene).instantiate()
	root.add_child(_main)
	for pass_index in PASSES:
		for i in _configs.size():
			_plan.append(i)
	for config in _configs:
		_times[config["label"]] = []
		_calls[config["label"]] = []


func _process(delta: float) -> bool:
	if _boot_left > 0:
		_boot_left -= 1
		if _boot_left == 0:
			_arm()
			_next_config()
		return false
	if _settle_left > 0:
		_settle_left -= 1
		_move_pointer(_configs[_plan[_step]], 0)
		return false
	var config: Dictionary = _configs[_plan[_step]]
	_move_pointer(config, _frame_in_sample)
	(_times[config["label"]] as Array).append(delta * 1000.0)
	(_calls[config["label"]] as Array).append(
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	_frame_in_sample += 1
	if _frame_in_sample >= SAMPLE_FRAMES:
		if not _next_config():
			_report()
			quit(0)
			return true
	return false


## The clock held, the opening fit on Paris, an energy order armed -- the state the
## play gate's player was in when the map stuttered.
func _arm() -> void:
	_main._clock.paused = true
	_main._map_view.set_zoom_for_test(2.08)
	_main._map_view.center_on_lonlat(2.35, 48.86)
	if _main._loader.energy_actions.is_empty():
		push_error("placement_probe: no energy action to arm")
		return
	_main._energy_panel.order_armed.emit(String(_main._loader.energy_actions[0].id))
	_armed = _main._map_view.is_placing()
	print("placement armed: %s (screen %dx%d)" % [_armed, root.size.x, root.size.y])


func _next_config() -> bool:
	_step += 1
	if _step >= _plan.size():
		return false
	var config: Dictionary = _configs[_plan[_step]]
	# Through the window manager's own calls: arming closed the workspace (d1a), so
	# an "open" row docks the tab again over the armed mode.
	if bool(config["open"]):
		_main._windows.open("energy")
	else:
		_main._windows.close_all()
	_settle_left = SETTLE_FRAMES
	_frame_in_sample = 0
	return true


func _move_pointer(config: Dictionary, frame: int) -> void:
	if not bool(config["move"]):
		return
	var at := Vector2(
		300.0 + 1100.0 * (0.5 + 0.5 * sin(frame * 0.05)),
		300.0 + 450.0 * (0.5 + 0.5 * sin(frame * 0.031)))
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)


func _report() -> void:
	print("PROBE G6 placement (%d passes x %d frames per row, vsync off, 1080p, opening fit)" % [PASSES, SAMPLE_FRAMES])
	for config in _configs:
		var label: String = config["label"]
		var ms: Array = _times[label]
		var sorted := ms.duplicate()
		sorted.sort()
		var sum := 0.0
		for v in ms:
			sum += float(v)
		var calls_sum := 0.0
		for c in _calls[label]:
			calls_sum += float(c)
		print("  %-16s mean %.2f ms  p95 %.2f  max %.2f  draw calls %.0f" % [
			label, sum / maxf(ms.size(), 1), float(sorted[int(sorted.size() * 0.95)]),
			float(sorted[sorted.size() - 1]), calls_sum / maxf(ms.size(), 1)])
