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
