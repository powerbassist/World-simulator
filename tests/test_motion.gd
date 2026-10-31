extends SceneTree

## V4.9a. The motion vocabulary (src/ui/motion.gd): the pure figure roll, the
## off switch that keeps every other test's label reads timing-free, the
## finish() skip path, and that the tweens are TIME-based -- they settle on
## wall-clock time without finish(), never on a frame count. Plus the wiring:
## a window opens through it, the clock beats through it.

const Strings = preload("res://src/ui/strings.gd")
const Motion = preload("res://src/ui/motion.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const ClockCluster = preload("res://src/ui/clock_cluster.gd")
const Clock = preload("res://src/core/clock.gd")

var _failures: Array[String] = []
var _frame := 0
var _timed: Control
var _timed_stepped := 0.0
var _stalled: Control
var _fading: Control
var _faded := false
var _manager
var _cluster
var _clock


func _init() -> void:
	_check_interpolate()
	_check_template()
	_check_decimal_comma()
	_check_headless_is_off()


func _process(delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			Motion.override = 1
			_check_roll()
			_check_open_and_finish()
			_check_arrive_and_pulse()
			_check_window_manager_opens_through_motion()
			_check_clock_beats()
			# A stalled frame: a window building heavy content stops the main
			# thread like this, and the motion must not finish inside it.
			_stalled = Control.new()
			root.add_child(_stalled)
			Motion.open(_stalled)
			# The loading screen's reveal starts right after the game's long
			# build frame: it must survive one too.
			_fading = Control.new()
			root.add_child(_fading)
			Motion.fade_out(_fading, 0.2, func(): _faded = true)
			OS.delay_msec(300)
			return false
		2:
			# Tweens step after _process, so the stalled frame's delta is spent
			# in the frame after this one: read on frame 3.
			return false
		3:
			# Unclamped, the 300 ms frame would have finished the 0.16 s open.
			if _stalled.modulate.a > 0.99:
				_fail("one 300 ms frame finished Motion.open() -- a long frame ate the motion")
			if _faded:
				_fail("one 300 ms frame finished Motion.fade_out() -- the loading screen's reveal would vanish in a frame")
			# Started after the stall, and read on the motion's own stepped time below
			# (each frame's delta capped at Motion.MAX_STEP_S): a frame-counted tween
			# would settle after N frames whatever their length, and a wall-clock
			# deadline flakes when the suite's parallel load stretches the frames
			# (V5.1b2).
			_timed = Control.new()
			root.add_child(_timed)
			Motion.open(_timed)
			_timed_stepped = 0.0
			return false
		_:
			_timed_stepped += minf(delta, Motion.MAX_STEP_S)
			if _timed_stepped < Motion.OPEN_S + 0.15:
				return false
			if not is_equal_approx(_timed.modulate.a, 1.0) or not _timed.scale.is_equal_approx(Vector2.ONE):
				_fail("Motion.open() had not settled %.2f stepped seconds after OPEN_S on its own (a=%.3f scale=%s)" % [
					0.15, _timed.modulate.a, _timed.scale])
			Motion.override = -1
			_report()
			return true


func _check_interpolate() -> void:
	var cases := [
		["41%", "45%", 0.5, "43%"],
		["41%", "45%", 0.0, "41%"],
		["41%", "45%", 1.0, "45%"],
		["+0.40%", "+0.50%", 0.5, "+0.45%"],
		["2600 Bn ^", "2700 Bn ^", 0.25, "2625 Bn ^"],
		["05 JAN 2027", "06 JAN 2027", 0.0, "05 JAN 2027"],
		["05 JAN 2027", "06 JAN 2027", 1.0, "06 JAN 2027"],
		["12 pending", "3 pending", 1.0, "3 pending"],
		# A changed shape snaps at the end of the roll rather than garbling.
		["Oil 80%", "Gas 80%", 0.5, "Oil 80%"],
		["Oil 80%", "Gas 80%", 1.0, "Gas 80%"],
	]
	for c in cases:
		var got := Motion.interpolate_text(c[0], c[1], c[2])
		if got != c[3]:
			_fail("interpolate_text(%s, %s, %.2f) = '%s', expected '%s'" % [c[0], c[1], c[2], got, c[3]])


## A French figure prints its decimals with a comma ("7,40"): the roll must read the comma
## as the decimal mark, not as grouping ("1,234" in English still snaps), or every French
## figure would jump instead of rolling.
func _check_decimal_comma() -> void:
	Strings.set_language("fr")
	var got := Motion.interpolate_text("7,40%", "7,60%", 0.5)
	if got != "7,50%":
		_fail("a French decimal should roll: interpolate_text('7,40%%', '7,60%%', 0.5) = '%s'" % got)
	if not Motion.same_template("7,40%", "7,60%"):
		_fail("'7,40%' and '7,60%' differ only in their numbers in French")
	if Motion.same_template("7,40%", "7,6%"):
		_fail("a changed count of decimals should still snap in French")
	Strings.set_language("en")
	if Motion.same_template("1,234", "1,240"):
		_fail("a grouped English figure should still be refused")


func _check_template() -> void:
	var cases := [
		["41%", "45%", true],
		["+0.4%", "-0.4%", false],   # a sign flip snaps rather than rolling through zero
		["41%", "41.5%", false],     # decimals changed
		["1,234", "1,240", false],   # grouped figures roll group by group: refused
		["12 pending", "3 pending", true],
		["", "41%", false],          # a first value snaps
		["Oil 80%", "Gas 80%", false],
	]
	for c in cases:
		if Motion.same_template(c[0], c[1]) != c[2]:
			_fail("same_template('%s', '%s') should be %s" % [c[0], c[1], c[2]])


## Every other test reads labels the moment they are set; under --headless motion
## must be off without anyone asking, or those reads would race a tween.
func _check_headless_is_off() -> void:
	Motion.override = -1
	if Motion.enabled():
		_fail("Motion.enabled() is true under --headless with no override")
	var label := Label.new()
	label.text = "10%"
	Motion.roll_text(label, "20%")
	if label.text != "20%":
		_fail("roll_text() with motion off left '%s', expected the final text at once" % label.text)
	label.free()


func _check_roll() -> void:
	var label := Label.new()
	root.add_child(label)
	label.text = "10%"
	Motion.roll_text(label, "20%")
	if label.text == "20%":
		_fail("roll_text() with motion on set the final text at once -- nothing rolled")
	Motion.finish(label)
	if label.text != "20%":
		_fail("finish() left a rolling figure at '%s', expected '20%%'" % label.text)
	# A new reading equal to the value shown MID-roll must stop there, not let
	# the roll run on to its old target.
	label.text = "10%"
	Motion.roll_text(label, "20%")
	var rolling: Tween = label.get_meta(&"motion_tween")
	rolling.custom_step(Motion.ROLL_S * 0.5)
	var shown := label.text
	if shown == "10%" or shown == "20%":
		_fail("half a roll shows '%s', expected an intermediate value" % shown)
	Motion.roll_text(label, shown)
	Motion.finish(label)
	if label.text != shown:
		_fail("a reading equal to the mid-roll value ended at '%s', expected '%s' (stale target)" % [label.text, shown])
	# A second roll interrupting the first starts from the shown value and ends final.
	Motion.roll_text(label, "30%")
	Motion.roll_text(label, "40%")
	Motion.finish(label)
	if label.text != "40%":
		_fail("an interrupted roll ended at '%s', expected '40%%'" % label.text)
	# #222 QA TAKE B: the same reading again (the HUD's daily refresh) mid-roll and
	# mid-flash lets the flash land -- it used to stop the roll and reset the tint.
	label.text = "10%"
	Motion.roll_text(label, "20%", Color(1, 0, 0))
	(label.get_meta(&"motion_tween") as Tween).custom_step(Motion.ROLL_S * 0.5)
	Motion.roll_text(label, "20%", Color(1, 0, 0))
	if not label.has_meta(&"motion_tween"):
		_fail("the same reading mid-roll stopped the roll")
	else:
		(label.get_meta(&"motion_tween") as Tween).custom_step(Motion.ROLL_S * 0.5 + 0.01)
		Motion.roll_text(label, "20%", Color(1, 0, 0))
		if label.modulate.g > 0.9:
			_fail("the same reading mid-flash reset the tint (g=%.2f): the strip never flashes" % label.modulate.g)
	Motion.finish(label)
	if label.text != "20%" or label.modulate.g < 0.99:
		_fail("the flash did not land on its final text and colour ('%s', g=%.2f)" % [label.text, label.modulate.g])
	label.queue_free()


func _check_open_and_finish() -> void:
	var c := Control.new()
	root.add_child(c)
	c.size = Vector2(200, 100)
	Motion.open(c)
	if c.modulate.a > 0.01 or is_equal_approx(c.scale.x, 1.0):
		_fail("Motion.open() did not start from transparent and small (a=%.2f scale=%s)" % [c.modulate.a, c.scale])
	if not c.pivot_offset.is_equal_approx(Vector2(100, 50)):
		_fail("Motion.open() grows from %s, expected the centre" % c.pivot_offset)
	Motion.finish(c)
	if not is_equal_approx(c.modulate.a, 1.0) or not c.scale.is_equal_approx(Vector2.ONE):
		_fail("finish() did not land Motion.open() on its final values (a=%.2f scale=%s)" % [c.modulate.a, c.scale])
	c.queue_free()


func _check_arrive_and_pulse() -> void:
	var card := PanelContainer.new()
	root.add_child(card)
	Motion.arrive(card)
	if card.modulate.a > 0.01:
		_fail("Motion.arrive() did not start transparent")
	Motion.finish(card)
	if not is_equal_approx(card.modulate.a, 1.0):
		_fail("Motion.arrive() finished at alpha %.2f" % card.modulate.a)
	card.queue_free()

	var label := Label.new()
	root.add_child(label)
	label.modulate.a = 0.8
	Motion.pulse(label)
	if label.modulate.is_equal_approx(Color(1, 1, 1, 0.8)):
		_fail("Motion.pulse() did not tint the label")
	Motion.finish(label)
	if not label.modulate.is_equal_approx(Color(1, 1, 1, 0.8)):
		_fail("Motion.pulse() settled at %s, expected white at the label's own alpha" % label.modulate)
	label.queue_free()


## The wiring that fails silently: a window that stopped opening through
## Motion still opens, just without the motion.
func _check_window_manager_opens_through_motion() -> void:
	_manager = WindowManager.new()
	_manager.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_manager)
	var content := Control.new()
	content.custom_minimum_size = Vector2(300, 200)
	_manager.register("motion_probe", "Motion probe", content)
	_manager.open("motion_probe")
	# The dock rises from the map since V5.1-c2.2, not a frame per window.
	var frame: Control = _manager.dock()
	if frame.modulate.a > 0.01:
		_fail("window_manager.open() did not open through Motion (dock alpha %.2f)" % frame.modulate.a)
	Motion.finish(frame)
	# Raising a window that is already open must not re-run the opening.
	_manager.open("motion_probe")
	if frame.modulate.a < 0.99:
		_fail("re-opening an open window re-ran its opening (alpha %.2f)" % frame.modulate.a)
	_manager.close("motion_probe")
	if frame.visible:
		_fail("window_manager.close() no longer hides at once")


func _check_clock_beats() -> void:
	_cluster = ClockCluster.new()
	root.add_child(_cluster)
	_clock = Clock.new()
	_cluster.refresh(_clock)
	var label: Label = _cluster._date_label
	if not label.modulate.is_equal_approx(Color.WHITE):
		_fail("the first date the clock shows pulsed (%s); only a day passing should" % label.modulate)
	_clock.day += 1
	_cluster.refresh(_clock)
	if label.modulate.is_equal_approx(Color.WHITE):
		_fail("a day passing did not beat the clock's date")
	# The same day refreshed again (a month boundary, any command) keeps the beat.
	_cluster.refresh(_clock)
	if label.modulate.is_equal_approx(Color.WHITE):
		_fail("a second refresh the same day cancelled the clock's beat")
	_clock.paused = true
	_cluster.refresh(_clock)
	if not is_equal_approx(label.modulate.a, Motion.PAUSED_ALPHA):
		_fail("a paused clock's date reads alpha %.2f, expected %.2f" % [label.modulate.a, Motion.PAUSED_ALPHA])
	# Let the running beat land, then: a date set while paused starts none.
	Motion.finish(label)
	_clock.day += 1
	_cluster.refresh(_clock)
	if not label.modulate.is_equal_approx(Color(1, 1, 1, Motion.PAUSED_ALPHA)):
		_fail("a date set while paused beat (%s); a paused clock does not tick" % label.modulate)
	_clock.free()


func _fail(message: String) -> void:
	_failures.append(message)


func _report() -> void:
	if _failures.is_empty():
		print("test_motion: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
