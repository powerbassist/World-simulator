extends SceneTree

## Frame-cost probe for the map platform -- V3.1 step-0. Dev-only, never ships.
##
##   godot --path "<repo>" --script res://tools/frame_probe.gd
##
## Run WINDOWED, not --headless: there is no renderer headless, so every frame
## figure below would be a lie. This is the instrument the V3.1 model doc cites,
## on tools/measure_austerity_peak.gd's precedent -- the measurement committed
## beside the verdict it produced.
##
## Why several passes and not one number: the 2026-09-05 playtest (P4) reported
## game speed halving at max zoom and read it as render cost eating the clock.
## clock.gd is time-based -- delta accumulates and the day loop catches up -- so
## render cost alone CANNOT halve its rate, and P4's own low-zoom readings (1.12,
## 0.99 days/sec) are day quantization of an 8-second sample (9/8, 8/8). The 0.50
## needs another cause. Each pass below measures one thing the P4 number
## conflated:
##
##  1. INVENTORY -- vertices and rings per geometry vintage, read off the live
##     loader. Where the vertex mass actually is, before any fix guesses.
##  2. SWEEP -- true frame time at each zoom with VSYNC OFF, at the project's
##     1080p window and again at the playtest's 2560x1440 device resolution
##     (stretch mode canvas_items keeps the canvas logical size, so the extra
##     pixels are pure fill load). Paused clock, so no month tick redraws and no
##     event arrivals land inside a sample.
##  3. CLOCK WINDOWS -- the playtest's own regime: vsync ON at 1440p, clock
##     UNPAUSED at speed 1, days counted from the clock's own signal with the
##     pause state logged. If a healthy time-based clock ever reads materially
##     under 1.00 day/sec, the record says so together with what was paused.
##
## Attribution: samples with the minimap hidden and then the whole map hidden.
## Minimap._process() queues a redraw of itself EVERY frame (its own comment
## says why), so its cost must be measured rather than assumed into "the map".

const MainScene := "res://src/ui/main.tscn"

## Paris. Every zoom is framed on the same land-heavy point, so the deep-zoom
## samples rasterise polygons rather than open sea -- the player case the gate
## is about.
const CENTER_LON := 2.35
const CENTER_LAT := 48.86

const SETTLE_FRAMES := 12
const RESIZE_SETTLE_FRAMES := 40
const FRAMES_PER_SAMPLE := 240

## The clock-health windows are wall-clock, not frame-count: a window that
## renders at 30 fps would need twice the frames for the same real time.
const CLOCK_WINDOW_SECONDS := 8.0

const SIZE_BASE := Vector2i(1920, 1080)
const SIZE_BIG := Vector2i(2560, 1440)

var _main: Node = null
var _phase := "settle"
var _settle_left := 30
var _samples: Array = []  # {label, frames, delta_sum, max_ms, calls, prims}
var _current: Dictionary = {}
var _configs: Array = []
var _clock_days := 0
var _clock_frames := 0
var _clock_delta := 0.0
var _clock_pause_log: Array = []
var _last_logged_paused := false
var _clock_t0 := 0
var _sample_running := false


func _initialize() -> void:
	_main = load(MainScene).instantiate()
	root.add_child(_main)
	print("screen=%dx%d" % [
		DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y])


func _build_configs() -> void:
	var mv = _main._map_view
	# Sweep 1: the project window at 1080p device pixels, vsync off, so frame
	# ms is the real render cost and not the refresh interval.
	_configs = [
		{"label": "1080 min_zoom", "zoom": mv.min_zoom(), "map": true, "minimap": true, "size": SIZE_BASE, "vsync": false},
		{"label": "1080 opening fit", "zoom": 2.08, "map": true, "minimap": true, "size": SIZE_BASE, "vsync": false},
		{"label": "1080 crosses 2.98", "zoom": 2.98, "map": true, "minimap": true, "size": SIZE_BASE, "vsync": false},
		{"label": "1080 zoom 4.0", "zoom": 4.0, "map": true, "minimap": true, "size": SIZE_BASE, "vsync": false},
		{"label": "1080 max_zoom", "zoom": mv.MAX_ZOOM, "map": true, "minimap": true, "size": SIZE_BASE, "vsync": false},
		{"label": "1080 max, no minimap", "zoom": mv.MAX_ZOOM, "map": true, "minimap": false, "size": SIZE_BASE, "vsync": false},
		{"label": "1080 max, no map", "zoom": mv.MAX_ZOOM, "map": false, "minimap": true, "size": SIZE_BASE, "vsync": false},
		{"label": "1080 HUD only", "zoom": mv.MAX_ZOOM, "map": false, "minimap": false, "size": SIZE_BASE, "vsync": false},
		# Sweep 2: the playtest's device resolution, same logical canvas.
		{"label": "1440 min_zoom", "zoom": mv.min_zoom(), "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false},
		{"label": "1440 opening fit", "zoom": 2.08, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false},
		{"label": "1440 crosses 2.98", "zoom": 2.98, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false},
		{"label": "1440 max_zoom", "zoom": mv.MAX_ZOOM, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false},
		{"label": "1440 max, no map", "zoom": mv.MAX_ZOOM, "map": false, "minimap": true, "size": SIZE_BIG, "vsync": false},
	]
	# V3.4's four gates, declared in the plan before any draw landed.
	# G3: the map's own event-driven band with the spine pass live. The
	# everything-visible band is the case with no headroom to spare, so it is
	# measured at the opening fit and at the crosses zoom, not at max.
	_configs.append({"label": "G3 1440 opening fit, roads", "zoom": 2.08, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false, "flows": false})
	_configs.append({"label": "G3 1440 crosses 2.98, roads", "zoom": 2.98, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false, "flows": false})
	# G4: the overlay alone. Measured as the difference between these two rows,
	# which is the attribution method the minimap rows above already use.
	_configs.append({"label": "G4 1440 max_zoom, convoys off", "zoom": mv.MAX_ZOOM, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false, "flows": false})
	_configs.append({"label": "G4 1440 max_zoom, convoys on", "zoom": mv.MAX_ZOOM, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false, "flows": true})
	# G5: the worst frame the game can actually show -- everything visible AND
	# the overlay animating over it.
	#
	# LABELLED "convoys" AND NOT "arcs", because the opening fit is on the convoy
	# side of the branch: map_flows draws arcs below map_view.CITY_MIN_ZOOM (2.0)
	# and convoys at or above it, and the fit is 2.08. The game therefore OPENS in
	# the overlay's expensive branch, with every spine in view and nothing for the
	# cull to remove -- which is what makes this row the worst frame rather than a
	# corner case. The arc branch gets its own row below, at min_zoom, so the
	# cheap half of the overlay is measured instead of assumed.
	_configs.append({"label": "G5 1440 opening fit, convoys", "zoom": 2.08, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false, "flows": true})
	# The five rows above hold the clock, so the overlay draws ONCE and the rows
	# price its pixels, not its animation. The four below run the clock, which is
	# the only state in which map_flows queues a redraw at all -- the cost G4 and
	# G5 are actually declared against. Both halves are kept because the
	# difference between them IS the re-record, and naming it separates a fill
	# problem from a script problem for whoever reads this next.
	_configs.append({"label": "G4 max_zoom off, clock run", "zoom": mv.MAX_ZOOM, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false, "flows": false, "run": true})
	_configs.append({"label": "G4 max_zoom convoys, clock run", "zoom": mv.MAX_ZOOM, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false, "flows": true, "run": true})
	_configs.append({"label": "G5 1440 fit convoys, clock run", "zoom": 2.08, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false, "flows": true, "run": true})
	_configs.append({"label": "G5 1440 min_zoom arcs, run", "zoom": mv.min_zoom(), "map": true, "minimap": true, "size": SIZE_BIG, "vsync": false, "flows": true, "run": true})
	# The clock-health windows reproduce P4's own regime: vsync ON, 1440p,
	# clock unpaused at speed 1.
	_configs.append({"label": "CLOCK-WINDOW @ 1440 opening fit", "zoom": 2.08, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": true, "clock": true})
	_configs.append({"label": "CLOCK-WINDOW @ 1440 max_zoom", "zoom": mv.MAX_ZOOM, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": true, "clock": true})
	# G6: the one that matters most. V3's own opening complaint is that map
	# render cost eats the clock (0.50 days/sec at max zoom, pre-cull). An
	# always-running 60 Hz redraw is that failure mode's exact shape returning,
	# so it is measured under the same regime rather than argued about.
	_configs.append({"label": "G6 CLOCK-WINDOW @ 1440 fit convoys", "zoom": 2.08, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": true, "clock": true, "flows": true})
	_configs.append({"label": "G6 CLOCK-WINDOW @ 1440 max convoys", "zoom": mv.MAX_ZOOM, "map": true, "minimap": true, "size": SIZE_BIG, "vsync": true, "clock": true, "flows": true})


## Absolute day count for one clock date -- clock.gd's own month lengths, so a
## month boundary cannot read as zero elapsed days. (Kept for reference; the
## day count itself comes from the clock's day_advanced signal.)
func _abs_days(year: int, month: int, day: int) -> int:
	var days := year * 365
	var lengths: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	for i in month - 1:
		days += lengths[i]
	return days + day


func _print_inventory() -> void:
	var sets := {
		"world 1:110m": _main._loader.world_features,
		"roster 1:50m": _main._loader.geo_features,
		"regions 1:10m": _main._loader.region_features,
	}
	print("--- vertex inventory (live loader) ---")
	for set_name in sets:
		var rings := 0
		var points := 0
		for id in sets[set_name]:
			for ring in sets[set_name][id]:
				if ring.size() >= 3:
					rings += 1
					points += ring.size()
		print("%-14s nations=%d rings=%d points=%d" % [
			set_name, sets[set_name].size(), rings, points])
	print("cities drawn above CITY_MIN_ZOOM=%d   markers=%d" % [
		_main._map_view._cities.size(), _main._map_view._markers.size()])


func _set_zoom(z: float) -> void:
	_main._map_view.set_zoom_for_test(z)
	_main._map_view.center_on_lonlat(CENTER_LON, CENTER_LAT)


func _apply_config(cfg: Dictionary) -> void:
	# V3.4. A frame sample of the flows overlay MUST run the clock. map_flows
	# only queues a redraw while the clock is unpaused, so a paused sample
	# measures an already-recorded canvas item and reports the animated cost as
	# near zero. "run" marks the rows that pay the per-frame re-record.
	_sample_running = bool(cfg.get("run", false))
	_main._clock.paused = not (bool(cfg.get("clock", false)) or _sample_running)
	if Vector2i(root.size) != Vector2i(cfg["size"]):
		root.size = Vector2i(cfg["size"])
		_settle_left = RESIZE_SETTLE_FRAMES
	else:
		_settle_left = SETTLE_FRAMES
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if bool(cfg["vsync"]) else DisplayServer.VSYNC_DISABLED)
	_main._map_view.visible = bool(cfg["map"])
	_main._minimap.visible = bool(cfg["minimap"])
	# V3.4. Roads ride map_view's own pass, so they are toggled by the layer
	# gate rather than by a node; the flows overlay is its own control and is
	# toggled by visibility AND by the layer, because it only animates on TRADE.
	_main._map_view.set_layer("trade" if bool(cfg.get("flows", false)) else "political")
	if _main._map_flows != null:
		_main._map_flows.visible = bool(cfg.get("flows", false))
	_set_zoom(float(cfg["zoom"]))


func _start_sample(label: String) -> void:
	_current = {
		"label": label, "frames": 0, "delta": 0.0, "max_ms": 0.0,
		"calls": 0.0, "prims": 0.0,
		"running": _sample_running, "paused_seen": false,
	}
	_phase = "settle_sample"


func _finish_sample() -> void:
	if int(_current["frames"]) > 0:
		_samples.append(_current)
	_phase = "next_config"


func _restore_toggles() -> void:
	_main._map_view.visible = true
	_main._minimap.visible = true


func _process(delta: float) -> bool:
	match _phase:
		"settle":
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = "inventory"
		"inventory":
			# Connected here rather than in _initialize(): the first attempt
			# connected before main's _ready had run and read a Nil clock --
			# which is exactly the register-before-setup ordering main.gd
			# documents for the same reason.
			_main._clock.day_advanced.connect(func(_y: int, _m: int, _d: int): _clock_days += 1)
			_print_inventory()
			_build_configs()
			_phase = "next_config"
		"next_config":
			if not _configs.is_empty():
				var cfg: Dictionary = _configs.pop_front()
				_apply_config(cfg)
				if bool(cfg.get("clock", false)):
					_start_clock_window(String(cfg["label"]))
				else:
					_start_sample(String(cfg["label"]))
			else:
				_restore_toggles()
				_report()
				quit(0)
				return true
		"settle_sample":
			_settle_left -= 1
			if _settle_left <= 0:
				_phase = "sample"
		"sample":
			# An event arrival pauses the clock (main.gd sets it on a decision),
			# which freezes the overlay mid-sample and would understate the very
			# cost the row exists to measure. Recorded, on the clock window's
			# own precedent, rather than left to look like a good number.
			if _sample_running and bool(_main._clock.paused):
				_current["paused_seen"] = true
			_current["frames"] = int(_current["frames"]) + 1
			_current["delta"] = float(_current["delta"]) + delta
			_current["max_ms"] = maxf(float(_current["max_ms"]), delta * 1000.0)
			if int(_current["frames"]) >= FRAMES_PER_SAMPLE:
				_current["calls"] = Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				_current["prims"] = Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				_finish_sample()
		"clock_window":
			_clock_frames += 1
			_clock_delta += delta
			var paused: bool = _main._clock.paused
			if paused != _last_logged_paused:
				_last_logged_paused = paused
				_clock_pause_log.append({
					"t": Time.get_ticks_msec() - _clock_t0,
					"paused": paused,
					"deciding": _main._paused_for_decision,
				})
			if (Time.get_ticks_msec() - _clock_t0) / 1000.0 >= CLOCK_WINDOW_SECONDS:
				_finish_clock_window()
	return false


func _start_clock_window(label: String) -> void:
	_clock_days = 0
	_clock_frames = 0
	_clock_delta = 0.0
	_clock_pause_log = []
	_last_logged_paused = false
	_clock_t0 = Time.get_ticks_msec()
	_phase = "clock_window"
	print("--- clock window: %s (speed %d, vsync on, %dx%d) ---" % [
		label, _main._clock.speed, root.size.x, root.size.y])


func _finish_clock_window() -> void:
	var secs := (Time.get_ticks_msec() - _clock_t0) / 1000.0
	var fps := float(_clock_frames) / maxf(_clock_delta, 0.0001)
	# Two rates, because they disagree when the process is descheduled. The
	# clock is time-based on the frame delta it is HANDED, so wall time that the
	# engine never counted as delta is time the clock could not have used: a
	# suspension shows up as a dead clock unless both are printed.
	print("days=%d over %.2fs wall (%.2fs counted) -> %.3f days/sec wall, %.3f counted   fps=%.1f   paused_at_end=%s deciding=%s" % [
		_clock_days, secs, _clock_delta,
		float(_clock_days) / secs, float(_clock_days) / maxf(_clock_delta, 0.0001), fps,
		_main._clock.paused, _main._paused_for_decision])
	for entry in _clock_pause_log:
		print("  pause change @%.2fs: paused=%s deciding=%s" % [
			float(entry["t"]) / 1000.0, entry["paused"], entry["deciding"]])
	_phase = "next_config"


func _report() -> void:
	# The clock column and not the header carries the pause state, because the
	# rows no longer agree about it: the gate rows that must animate run it.
	print("--- frame samples (%d frames each, vsync off unless labelled) ---" % FRAMES_PER_SAMPLE)
	print("%-32s %8s %8s %8s %9s %11s  %s" % [
		"config", "avg ms", "max ms", "fps", "drawcalls", "primitives", "clock"])
	for s in _samples:
		var avg_ms := float(s["delta"]) / float(s["frames"]) * 1000.0
		var fps := float(s["frames"]) / maxf(float(s["delta"]), 0.0001)
		var regime := "paused"
		if bool(s.get("running", false)):
			regime = "PAUSED MID-SAMPLE" if bool(s.get("paused_seen", false)) else "running"
		print("%-32s %8.2f %8.2f %8.1f %9.0f %11.0f  %s" % [
			s["label"], avg_ms, float(s["max_ms"]), fps, s["calls"], s["prims"], regime])
