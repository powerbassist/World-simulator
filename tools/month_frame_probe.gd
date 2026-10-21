extends SceneTree

## Frame-time probe for the three freezes the V5.0 play gate scored 1/5 on --
## V5.1-0a. Dev-only, never ships.
##
##   APPDATA="$(mktemp -d)" godot --path . --script res://tools/month_frame_probe.gd -- [--months=N] [--drag-frames=N] [--json=PATH]
##
## Run WINDOWED, not --headless: a headless frame draws nothing, so its time is
## not the time a player waits. tick_budget_probe.gd times the month's SYSTEMS;
## this times the FRAMES the player sees while the real main scene runs them --
## the sim, the UI's half of the month, every panel's refresh and the draw. The
## author's three complaints, in order, each a phase:
##
##   months      the clock at speed 3 over N month boundaries, nothing open
##               ("11 s de delai le dernier jour du mois", then "half a second
##               delay every month").
##   drag        the budget window open, one lever dragged a step per frame for
##               N frames and released ("budget levers sont cassés ou font
##               freeze le jeu"), then the frames until the forecast settles.
##   budget_month  one month boundary at speed 3 WITH the budget window open --
##               the fix pass measured ~10 s there and left it to this block.
##   placement   a reactor armed, the cursor moved over France, the click that
##               sites it (P4, "freezes when placing construction") -- once with
##               every window closed, once with the Energy window still open.
##
## The frame time is the wall time between two calls of this script's
## _process(), which SceneTree makes once per frame ahead of the nodes' own --
## so it covers everything the frame did: script, nodes, draw, vsync wait. Every
## pause the game takes (an event on the desk, the term-start programme, an
## election) is answered the way tests/test_election_panel.gd's driver answers
## it, and the frame that answers is labelled so its own cost is not read as the
## month's.
##
## Read the WORST FRAME per phase and the count past 50 ms (the V5.1 brief's
## target). Wall-clock on one dev machine: compare a base run with a tip run made
## the same hour, alone (AGENTS.md: a timing probe runs alone).

const MainScene := "res://src/ui/main.tscn"
const Events = preload("res://src/sim/events.gd")
const Programme = preload("res://src/sim/programme.gd")

const SETTLE_FRAMES := 30
## Frames after a month boundary that still belong to it: the boundary frame
## itself before V5.1-0a, the month's slices after it, and the refresh behind.
const MONTH_WINDOW_FRAMES := 40
## Central France: the click that sites the reactor must land in the player's own
## country (main.gd refuses a point abroad, loudly).
const SITE_LON := 2.35
const SITE_LAT := 46.6
const PLACE_MOVE_FRAMES := 30
const AFTER_FRAMES := 90
## A frame past this is a freeze the player sees -- the brief's ~50 ms target.
const FREEZE_MS := 50.0

var _main: Node = null
var _months_wanted := 6
var _drag_frames := 30
var _json_path := ""

var _phase := "boot"
var _phase_left := SETTLE_FRAMES
var _last_us := 0
var _frame_label := ""      # what the frame now ending did, set while it ran
var _frames: Array = []     # {phase, label, ms}
var _boundaries := 0
var _last_month := 0
var _month_window_left := 0
var _slider: HSlider = null
var _drag_done := 0
var _site := Vector2.ZERO
var _move_done := 0
var _after_left := 0
var _keep_open := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--months="):
			_months_wanted = int(arg.get_slice("=", 1))
		elif arg.begins_with("--drag-frames="):
			_drag_frames = int(arg.get_slice("=", 1))
		elif arg.begins_with("--json="):
			_json_path = arg.get_slice("=", 1)
	_main = load(MainScene).instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_usec()
	if _main == null or _main._state == null:
		return false
	var clock: Node = _main._clock
	# The rollover happened inside the frame now ending, so that frame is the
	# one labelled: before V5.1-0a it carried the whole month.
	if clock.month != _last_month:
		if _last_month != 0 and _phase in ["months", "budget_month"]:
			_boundaries += 1
			_month_window_left = MONTH_WINDOW_FRAMES
			_frame_label = "boundary"
		_last_month = clock.month
	if _last_us != 0 and _phase != "boot":
		_frames.append({"phase": _phase, "label": _frame_label, "ms": float(now - _last_us) / 1000.0})
	_last_us = now
	_frame_label = ""
	if _month_window_left > 0:
		_month_window_left -= 1
		_frame_label = "month"
	return _step(clock)


func _step(clock: Node) -> bool:
	match _phase:
		"boot":
			_answer_pauses(clock)
			_phase_left -= 1
			if _phase_left <= 0:
				_main._windows.close_all()
				clock.set_speed(3)
				clock.paused = false
				_phase = "months"
		"months":
			_answer_pauses(clock)
			if _boundaries >= _months_wanted and _month_window_left == 0:
				clock.paused = true
				_main._windows.open("budget")
				_frame_label = "open"
				_phase = "budget_open"
				_phase_left = SETTLE_FRAMES
		"budget_open":
			if _forecast_settled():
				_phase_left -= 1
			if _phase_left <= 0:
				_slider = _main._budget_panel._sliders[_main._budget_panel._lever_keys()[0]]
				_phase = "drag"
		"drag":
			_slider.value = _slider.value + _slider.step
			_frame_label = "drag"
			_drag_done += 1
			if _drag_done >= _drag_frames:
				_slider.drag_ended.emit(true)
				_frame_label = "release"
				_phase = "drag_settle"
				_after_left = AFTER_FRAMES * 12
		"drag_settle":
			_after_left -= 1
			if (_forecast_settled() and _after_left < AFTER_FRAMES * 11) or _after_left <= 0:
				_boundaries = 0
				clock.paused = false
				_phase = "budget_month"
		"budget_month":
			# At speed 3 a month closes faster than a projection does, so the
			# forecast is never settled while the clock runs (it shows the last
			# one, marked updating). After the boundary the clock stops and the
			# phase waits for it, so its frames are timed too.
			if _boundaries >= 1 and _month_window_left == 0:
				clock.paused = true
				if _forecast_settled():
					_arm(false)
					_phase = "placement"
			else:
				_answer_pauses(clock)
		"placement":
			if _move_done < PLACE_MOVE_FRAMES:
				var motion := InputEventMouseMotion.new()
				var wiggle := Vector2(cos(_move_done * 0.4), sin(_move_done * 0.4)) * 30.0
				motion.position = _site + wiggle
				motion.global_position = motion.position
				root.push_input(motion, true)
				_frame_label = "hover"
				_move_done += 1
			elif _move_done == PLACE_MOVE_FRAMES:
				for pressed in [true, false]:
					var click := InputEventMouseButton.new()
					click.button_index = MOUSE_BUTTON_LEFT
					click.pressed = pressed
					click.position = _site
					click.global_position = _site
					root.push_input(click, true)
				_frame_label = "click"
				_move_done += 1
				_after_left = AFTER_FRAMES
			else:
				_after_left -= 1
				if _after_left <= 0:
					if _keep_open:
						_report()
						return true
					_arm(true)
					_move_done = 0
					_phase = "placement_open"
		"placement_open":
			_phase = "placement"
			var done := _step(clock)
			_phase = "placement_open"
			return done
	return false


## A reactor armed from the Energy window. Closed again (`keep_open` false) so the
## click reaches the map -- closing does not disarm, main.gd's Escape does -- or
## kept open and moved aside, with the site drawn left of it, so the click pays
## for an open panel's refresh the way the player's click does.
func _arm(keep_open: bool) -> void:
	_keep_open = keep_open
	var mv = _main._map_view
	_main._windows.close_all()
	mv.center_on_lonlat(SITE_LON, SITE_LAT)
	_main._windows.open("energy")
	_main._energy_panel.order_armed.emit("order_nuclear_epr")
	if keep_open:
		var frame: Control = _main._windows.frame("energy")
		frame.position.x = _main._windows.size.x - frame.size.x
		var view: Vector2 = mv.size
		var left: Vector2 = mv._screen_to_lonlat(Vector2(view.x * 0.25, view.y * 0.5))
		mv.center_on_lonlat(SITE_LON + (SITE_LON - left.x), SITE_LAT)
	else:
		_main._windows.close_all()
	_site = mv._lonlat_to_screen(SITE_LON, SITE_LAT)
	_frame_label = "arm"


## The forecast's own "still computing" flag where the panel has one (V5.1-0a),
## else settled once the panel has redrawn -- the base computed it in the frame.
func _forecast_settled() -> bool:
	var panel = _main._budget_panel
	if "_forecast" in panel:
		return not panel._forecast.busy() and not panel._dirty
	return not panel._dirty


func _answer_pauses(clock: Node) -> void:
	if not clock.paused:
		return
	var ns = _main._state.player()
	if _main._election_panel != null and _main._election_panel.visible:
		_main._election_panel.hide()
	elif Events.is_pending(ns) and not Events.pending_event(ns, _main._loader).choices.is_empty():
		Events.choose(_main._state, _main._loader,
			String(Events.pending_event(ns, _main._loader).choices[0]["id"]))
	else:
		var offer: Array = Programme.available(_main._state, ns, _main._loader)
		if not offer.is_empty():
			_main._agenda_panel.programme_chosen.emit(String(offer[0]["id"]))
	clock.paused = false
	_main._windows.close_all()
	_frame_label = "answer"


func _report() -> void:
	var by_phase := {}
	for f in _frames:
		var key: String = f["phase"]
		if not by_phase.has(key):
			by_phase[key] = {"frames": 0, "worst_ms": 0.0, "worst_label": "", "over": 0, "sum_ms": 0.0}
		var row: Dictionary = by_phase[key]
		row["frames"] += 1
		row["sum_ms"] += f["ms"]
		if f["ms"] > FREEZE_MS:
			row["over"] += 1
		if f["ms"] > row["worst_ms"]:
			row["worst_ms"] = f["ms"]
			row["worst_label"] = f["label"]
	print("month_frame_probe: months=%d drag_frames=%d" % [_months_wanted, _drag_frames])
	print("%-14s %7s %10s %-8s %8s %10s" % ["phase", "frames", "worst ms", "at", ">50ms", "wall s"])
	for key in ["months", "budget_open", "drag", "drag_settle", "budget_month", "placement", "placement_open"]:
		if not by_phase.has(key):
			continue
		var row: Dictionary = by_phase[key]
		print("%-14s %7d %10.1f %-8s %8d %10.2f" % [key, row["frames"], row["worst_ms"],
			row["worst_label"], row["over"], row["sum_ms"] / 1000.0])
	print("frames past %.0f ms, in order:" % FREEZE_MS)
	for f in _frames:
		if f["ms"] > FREEZE_MS:
			print("  %-13s %-8s %9.1f" % [f["phase"], f["label"], f["ms"]])
	if _json_path != "":
		var file := FileAccess.open(_json_path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify({"phases": by_phase, "frames": _frames}, "  "))
	quit(0)
