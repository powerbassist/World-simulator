extends SceneTree

## V3.4. The animated overlay: it takes no clicks, it is not a map layer, it
## culls before it transforms, and it stops when the clock does.
##
## Driven a frame at a time because a Control outside the scene tree has not run
## _ready() -- tests/test_map_plants.gd's idiom.

const Main = preload("res://src/ui/main.tscn")
const MapLayers = preload("res://src/ui/map_layers.gd")

var _failures: Array[String] = []
var _frame: int = 0
var _main: Node = null


func _init() -> void:
	_main = Main.instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	# The cull check needs a settled frame of its own: queue_redraw() is a
	# request, and calling _draw() by hand is an engine error (draw_* outside
	# NOTIFICATION_DRAW), so the camera is set on one frame and the counter read
	# on the next.
	if _frame == 3:
		_arm_cull_check()
		return false
	_check_takes_no_clicks()
	_check_not_a_layer()
	_check_cull_by_count()
	_check_pause_freezes()
	_check_redraw_is_rate_limited()
	_check_convoys_store_nothing()
	_report()
	return true


## A CONVOY IS NOT A TARGET. The overlay sits over the whole map, so a mouse
## filter of anything but IGNORE takes every click on the screen -- which is
## precisely the bug V3.3f shipped for a whole tier through a CenterContainer's
## default of PASS. That one sat behind a green 80/80, so this is asserted on the
## property and not on the intent.
func _check_takes_no_clicks() -> void:
	# get(), not a direct read: a missing member on a Node RAISES rather than
	# reading null, and this file has already seen that turn the whole set of
	# checks into four SCRIPT ERRORs under an "all checks passed" and exit 0. The
	# absence of the overlay is the first thing this test has to be able to SAY.
	var flows = _main.get("_map_flows")
	if flows == null:
		_fail("main.gd built no _map_flows")
		return
	if flows.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("map_flows mouse_filter is %d, expected IGNORE -- it would eat the map's clicks" % flows.mouse_filter)


## THE OVERLAY IS A DRAW SURFACE, NOT A FIFTH LAYER. map_layers.gd's header says
## no map layer adds, removes or reorders a draw layer: LAYERS chooses a roster
## FILL from a per-nation scalar, one at a time. Arcs and convoys are additive
## marks that RIDE the trade layer; they do not become one.
func _check_not_a_layer() -> void:
	if MapLayers.LAYERS.size() != 4:
		_fail("LAYERS has %d entries, expected 4 -- a flow is a draw surface" % MapLayers.LAYERS.size())


## Puts the camera where the cull check reads it, one frame early.
func _arm_cull_check() -> void:
	var map = _main._map_view
	var flows = _main.get("_map_flows")
	if flows == null or map == null:
		return
	map.set_layer(MapLayers.TRADE)
	map.set_zoom_for_test(map.MAX_ZOOM)
	map.center_on_lonlat(2.35, 48.86)
	flows.queue_redraw()


## THE CULL IS ASSERTED BY COUNT. Same reason as the spine pass's: a per-frame
## layer that transforms first and culls second draws the identical picture and
## costs the whole roster, and no frame would say so.
func _check_cull_by_count() -> void:
	var flows = _main.get("_map_flows")
	if flows == null:
		return
	var total: int = _main._map_view.spine_count()
	if flows.spines_considered() <= 0:
		_fail("the flow overlay considered no spines at max zoom over Paris -- it is not drawing")
	elif flows.spines_considered() >= total:
		_fail("all %d spines were walked -- the overlay transforms before it culls" % total)
	elif flows.spines_considered() > int(total * 0.6):
		_fail("%d of %d spines survived the flow cull at max zoom over Paris -- not viewport-bounded" % [flows.spines_considered(), total])


## PAUSE FREEZES THE WORLD, and that is what makes tools/screenshot.gd --paused
## still able to prove pixel identity in the one block whose whole point is
## motion. The phase advances off the sim clock, not off wall time, so a paused
## game also pays no animated frames at all.
func _check_pause_freezes() -> void:
	var flows = _main.get("_map_flows")
	if flows == null:
		return
	_main._clock.paused = true
	var before: float = flows.phase_days()
	for i in 4:
		flows._process(0.25)
	if not is_equal_approx(flows.phase_days(), before):
		_fail("phase moved %f while the clock was paused" % (flows.phase_days() - before))

	_main._clock.paused = false
	_main._clock.speed = 1
	flows._process(0.5)
	if flows.phase_days() <= before:
		_fail("phase did not advance with the clock running")


## THE CAP IS WHAT MAKES TWO GATES PASS, so it is asserted and not trusted.
## Measured with the overlay redrawing every frame: G4 3.01 ms against a 1.5 ms
## gate, G5 13.73 ms against 11.0 (docs/map-platform-model.md section 4). That
## makes the CADENCE load-bearing, not just the on/off the check above covers --
## and queue_redraw() leaves nothing a headless run can read back, which is why
## map_flows lifted the decision into _redraw_due() for this check to ask.
func _check_redraw_is_rate_limited() -> void:
	var flows = _main.get("_map_flows")
	if flows == null:
		return
	var hz: float = float(flows.REDRAW_HZ)
	var frame_60: float = 1.0 / 60.0

	# 1. AT REDRAW_HZ, NOT AT THE FRAME RATE. 120 frames of 1/60 is two seconds,
	# so a still view on a running clock owes 2 * REDRAW_HZ redraws -- about half
	# the frames, which is the whole point.
	flows._since_redraw = 0.0
	var fired: int = 0
	for i in 120:
		if flows._redraw_due(frame_60, false, false):
			fired += 1
	var want: int = int(2.0 * hz)
	if absi(fired - want) > 3:
		_fail("60 fps for 2 s queued %d redraws, expected ~%d at REDRAW_HZ=%.0f" % [fired, want, hz])

	# 2. ONE LONG FRAME IS ONE REDRAW, NOT A BURST. Subtracting the interval
	# instead of fmod-ing it leaves a 0.5 s stall holding fourteen intervals of
	# backlog and paying them off on consecutive frames -- the rate limit turning
	# itself off exactly where the frame can least afford it. At 60 fps the cap
	# allows one redraw every other frame, so five frames may hold at most three.
	flows._since_redraw = 0.0
	var stalled: bool = flows._redraw_due(0.5, false, false)
	var after: int = 0
	for i in 5:
		if flows._redraw_due(frame_60, false, false):
			after += 1
	if not stalled:
		_fail("a 0.5 s frame queued no redraw")
	if after > 3:
		_fail("the 5 frames after a 0.5 s stall queued %d redraws -- the accumulator burst its backlog" % after)

	# 3. THE REMAINDER SURVIVES, so the long-run average does not drift below
	# REDRAW_HZ. 0.019 s is 52.6 fps and divides into no whole number of
	# intervals: zeroing the accumulator can then only fire every second frame,
	# 26.3 Hz -- a sixth slow, and no single frame would look wrong.
	flows._since_redraw = 0.0
	var frames: int = 300
	var d: float = 0.019
	var long_fired: int = 0
	for i in frames:
		if flows._redraw_due(d, false, false):
			long_fired += 1
	var rate: float = float(long_fired) / (float(frames) * d)
	if rate < hz - 1.0:
		_fail("over %.1f s at %.0f fps the redraw averaged %.1f Hz against REDRAW_HZ=%.0f -- the accumulator's remainder is being dropped" % [float(frames) * d, 1.0 / d, rate, hz])

	# 4. A CAMERA MOVE IS EXEMPT. The first call pins the exemption itself: an arc
	# arriving a frame after the coastline under it reads as the two layers coming
	# apart, and any ordering that let the cap gate a pan fails here, since
	# _since_redraw is 0 and one frame of 1/60 does not reach the interval.
	#
	# The second call pins something else, and it is the reason both are here: the
	# exemption is NOT one-shot. A sustained drag changes the view rect on every
	# frame, so every frame of it takes this branch and the cap is off for the
	# whole gesture -- uncapped BY CONSTRUCTION, not by accident. That is a cost,
	# and tools/frame_probe.gd's PAN rows measure it rather than leaving this
	# assertion to imply it is free (docs/map-platform-model.md section 4).
	flows._since_redraw = 0.0
	if not flows._redraw_due(frame_60, true, false):
		_fail("a camera move queued no redraw")
	if not flows._redraw_due(frame_60, true, false):
		_fail("a camera move on the very next frame queued no redraw -- the exemption is one-shot")

	# 5. PAUSE STILL FREEZES IT. _check_pause_freezes above asserts the phase
	# stops; Task 4's review noted nothing asserted the REDRAW stops, which is
	# what tools/screenshot.gd --paused actually depends on for pixel identity.
	flows._since_redraw = 0.0
	var while_paused: int = 0
	for i in 120:
		if flows._redraw_due(frame_60, false, true):
			while_paused += 1
	if while_paused != 0:
		_fail("%d redraws queued over 2 s of a paused clock with the view still" % while_paused)

	# 6. A ZERO DELTA IS INERT -- it does not fire, and it does not spend the
	# credit already banked. The engine hands out a 0.0 frame on a resumed window,
	# and an accumulator that lost its remainder to one would drift the cadence
	# down by exactly the number of them, silently.
	var interval: float = 1.0 / hz
	flows._since_redraw = interval * 0.9
	var zero_fired: int = 0
	for i in 100:
		if flows._redraw_due(0.0, false, false):
			zero_fired += 1
	if zero_fired != 0:
		_fail("%d redraws queued over 100 frames of delta 0.0" % zero_fired)
	if not flows._redraw_due(interval * 0.2, false, false):
		_fail("the 0.9 of an interval already banked did not survive 100 zero-delta frames")

	# 7. A NEGATIVE DELTA RECOVERS RATHER THAN WEDGING. Nothing is meant to hand
	# one over, which is why it is worth pinning: the accumulator goes below zero
	# and the overlay owes that debt back before it redraws again. ONE FRAME'S
	# WORTH, because the debt is proportional -- the cap does not floor it, so a
	# large negative delta would stop the overlay for as long as the real frames
	# take to repay it, and a test that fed it -1 s would be asserting a wedge
	# rather than the recovery. A single flipped frame costs one redraw out of the
	# next two seconds' sixty, which is inside assertion 1's own tolerance.
	flows._since_redraw = 0.0
	if flows._redraw_due(-frame_60, false, false):
		_fail("a negative delta queued a redraw")
	var recovered: int = 0
	for i in 120:
		if flows._redraw_due(frame_60, false, false):
			recovered += 1
	if absi(recovered - want) > 3:
		_fail("after one frame of delta %.4f, 2 s at 60 fps queued %d redraws, expected ~%d -- the accumulator did not recover" % [-frame_60, recovered, want])


## A CONVOY IS A PURE FUNCTION OF (edge, index, phase) AND STORES NOTHING. That
## is what keeps SAVE_VERSION at 33 and what makes a reloaded save show the same
## world -- V1.8's events precedent, where a hazard is a pure function of
## (nation, event, year, month) rather than a rolled-and-kept number.
## Read from the source, the way tests/test_events.gd polices the splitmix
## constants: a convoy that gained a stored position would still LOOK right and
## the save would quietly stop round-tripping.
func _check_convoys_store_nothing() -> void:
	var text := FileAccess.get_file_as_string("res://src/ui/map_flows.gd")
	var start := text.find("func _draw_convoys")
	if start < 0:
		_fail("map_flows.gd has no _draw_convoys()")
		return
	# THE PASS IS TWO FUNCTIONS AND THE REGION HAS TO COVER BOTH. _draw_convoys()
	# walks the spines; the per-direction _draw_convoy_run() it calls is where the
	# stagger and the phase actually are. Stopping at the next "func " reads the
	# caller alone, and the only "Cycle.unit" in that slice is the WORD inside
	# _draw_convoy_run()'s doc comment -- measured: with the narrow region a
	# planted randf() in _draw_convoy_run() did not fail this check, and the green
	# was prose rather than code.
	var last := text.find("func _draw_convoy_run")
	var stop := text.find("\nfunc ", maxi(start, last) + 1)
	var body := text.substr(start, stop - start if stop > start else -1)
	if not body.contains("Cycle.unit"):
		_fail("the convoy pass does not draw its stagger from Cycle.unit()")
	for forbidden in ["randf", "randi", "RandomNumberGenerator", "Time.get_"]:
		if body.contains(forbidden):
			_fail("the convoy pass reaches %s -- a convoy is a pure function of the edge and the clock" % forbidden)


func _fail(msg: String) -> void:
	_failures.append(msg)


func _report() -> void:
	if _failures.is_empty():
		print("test_map_flows: all checks passed")
		quit()
		return
	for f in _failures:
		print("FAIL: %s" % f)
	quit(1)
