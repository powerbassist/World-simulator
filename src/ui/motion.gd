extends RefCounted

## V4.9a. Motion as feedback, in one place: a window opens rather than
## appears, a message card arrives, a figure rolls to its new value, the date
## pulses once per day -- so the pulse's own rhythm is the clock's speed.
##
## Every tween here is TIME-based (Godot's Tween runs on process delta, never a
## frame count -- V3.6's tally discipline), short enough that nothing waits on
## it, and decorative ONLY: the final value is what a reader or a test sees the
## moment motion is off, and a click that lands mid-tween lands on the real
## control. Nothing here gates input, so there is no skip path to eat a click;
## finish() exists for the ceremonies (V4.9b) that do sequence.
##
## The V5 UI rework replaces the layouts these are applied to; what it keeps is
## this file's vocabulary and interpolate_text(), which is a pure function.

const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Durations, in seconds, and why each is that long. Under ~0.1 s a fade reads
## as a flicker; over ~0.25 s a window the player asked for feels slow to come.
const OPEN_S := 0.16
## A card is news, not a request: a touch longer than a window so the eye is
## drawn to it, still well under the time it takes to read its title.
const ARRIVE_S := 0.24
## A figure rolling: long enough to see the direction of travel, short enough
## to have settled before the next day tick at the fastest speed.
const ROLL_S := 0.3
## The day pulse decays inside one day at speed 3, so consecutive pulses stay
## separate beats rather than a steady glow.
const PULSE_S := 0.22
## The scale a window grows from. 0.97 is the smallest step that reads as
## "opening" at 1080p without the content visibly swimming.
const OPEN_SCALE := 0.97
## The pulse's tint: the brass accent over the text colour, so the beat is in
## the game's one accent and no second colour enters.
const PULSE_TINT := Color(1.0, 0.86, 0.42)
## A paused date is dimmed, not hidden: still the date, visibly not moving.
const PAUSED_ALPHA := 0.55
## The most one frame may advance a motion: 1/30 s. At 60 fps it never binds;
## on a frame that stalls (a window building its content) the motion resumes
## where it was rather than having finished unseen.
const MAX_STEP_S := 1.0 / 30.0

const _META := &"motion_tween"

## -1 follows the setting (and is off under --headless, which draws nothing:
## motion there only makes label reads depend on timing, and every test reads
## labels). 0 forces off, 1 forces on -- tests/test_motion.gd and
## tools/screenshot.gd set it, the screenshot tool to OFF so a capture never
## lands mid-fade.
static var override := -1

## The setting, cached against the settings screen's save counter: the strip
## refreshes a dozen figures per day tick and a file read each is waste, while
## a save from the pause menu still governs the very next tween. A counter on
## the screen rather than a call from it, so the dependency stays one-way.
static var _setting := -1
static var _seen_revision := -1


static func enabled() -> bool:
	if override >= 0:
		return override == 1
	if DisplayServer.get_name() == "headless":
		return false
	if _setting < 0 or _seen_revision != SettingsPanel.revision:
		_setting = 1 if SettingsPanel.motion_enabled() else 0
		_seen_revision = SettingsPanel.revision
	return _setting == 1


## Completes every motion on `node` at once: final values applied, callbacks
## run. The skip path for a sequence, and how a test reads a settled state
## without waiting on wall-clock time.
static func finish(node: Node) -> void:
	if node == null or not node.has_meta(_META):
		return
	var tween: Tween = node.get_meta(_META)
	if tween != null and tween.is_valid():
		tween.custom_step(3600.0)
	node.remove_meta(_META)


static func _stop(node: Node) -> void:
	if node.has_meta(_META):
		var tween: Tween = node.get_meta(_META)
		if tween != null and tween.is_valid():
			tween.kill()
		node.remove_meta(_META)


## Fades `item` out and then calls `done` -- the loading screen's reveal. Through
## the clamped stepper, because it starts right after the game's ~0.8 s build
## frame, which a self-running tween would spend whole. Motion off: `done` now.
static func fade_out(item: CanvasItem, seconds: float, done: Callable) -> void:
	if not enabled():
		done.call()
		return
	var tween := _tween(item)
	tween.tween_property(item, "modulate:a", 0.0, seconds)
	tween.tween_callback(done)


static func _tween(node: Node) -> Tween:
	finish(node)
	var tween := node.create_tween()
	# UI motion keeps running under a paused tree; it is presentation, and a
	# window opened from the pause menu should open the same way.
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	node.set_meta(_META, tween)
	tween.finished.connect(func():
		if is_instance_valid(node) and node.get_meta(_META, null) == tween:
			node.remove_meta(_META)
	)
	_step_clamped(node, tween)
	return tween


## Stepped here, a frame at a time, with each frame's delta capped at MAX_STEP_S
## -- still time-based, never frame-counted, but a single long frame cannot eat
## the motion. Measured at V4.9a (tools/motion_frames.gd): the Budget window's
## first frame takes ~0.4 s to build its content, and a self-running tween took
## its whole 0.16 s fade inside that one frozen frame -- the window "appeared"
## exactly as before, on the windows where opening matters most. Off-tree (a
## test building a node it never adds) the tween runs itself as usual.
static func _step_clamped(node: Node, tween: Tween) -> void:
	var tree := node.get_tree()
	if tree == null:
		return
	tween.pause()
	# Weak: the stepper outlives a node freed mid-motion by one frame, and a
	# lambda holding a freed capture errors on every call.
	var ref: WeakRef = weakref(node)
	var holder: Array = []
	var stepper := func():
		var live: Node = ref.get_ref()
		if live == null or not tween.is_valid():
			if tree.process_frame.is_connected(holder[0]):
				tree.process_frame.disconnect(holder[0])
			return
		tween.custom_step(minf(live.get_process_delta_time(), MAX_STEP_S))
	holder.append(stepper)
	tree.process_frame.connect(stepper)


## A window opening: a fade and a small grow from its centre. Only for a
## control whose parent does NOT lay it out (a floating window frame) -- a
## container would overwrite the scale's pivot every sort.
static func open(control: Control) -> void:
	if not enabled():
		return
	control.pivot_offset = control.size * 0.5
	control.modulate.a = 0.0
	control.scale = Vector2(OPEN_SCALE, OPEN_SCALE)
	var tween := _tween(control)
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(control, "modulate:a", 1.0, OPEN_S)
	tween.tween_property(control, "scale", Vector2.ONE, OPEN_S)


## A card arriving in a container: fade only, because the container owns its
## position and size.
static func arrive(control: Control) -> void:
	if not enabled():
		return
	control.modulate.a = 0.0
	var tween := _tween(control)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(control, "modulate:a", 1.0, ARRIVE_S)


## One beat on a label, brass to its own colour. The three colour channels
## only: alpha stays the caller's (the clock dims a paused date through it), so
## a refresh setting alpha mid-beat neither cancels the beat nor is undone by it.
static func pulse(item: CanvasItem) -> void:
	if not enabled():
		return
	item.modulate = Color(PULSE_TINT.r, PULSE_TINT.g, PULSE_TINT.b, item.modulate.a)
	var tween := _tween(item)
	tween.set_parallel(true)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	for channel in ["modulate:r", "modulate:g", "modulate:b"]:
		tween.tween_property(item, channel, 1.0, PULSE_S)


## Sets `label` to `text`, rolling every number in it from the value it shows
## now when the two texts share a template (same words, same number count, same
## decimals). Anything else -- a reading that changed shape, motion off -- is
## set at once. The label's text is final the moment the tween finishes or is
## finished; mid-roll it is a real intermediate value, never a garbled one.
static func roll_text(label: Label, text: String) -> void:
	# A roll still running is STOPPED where it is, not finished: finishing would
	# land it on its old target, and a new reading equal to the value now shown
	# would then return below with that stale target on screen.
	_stop(label)
	var from := label.text
	if from == text:
		return
	if not enabled() or not same_template(from, text):
		finish(label)
		label.text = text
		return
	var tween := _tween(label)
	tween.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_method(func(t: float): label.text = interpolate_text(from, text, t), 0.0, 1.0, ROLL_S)
	tween.tween_callback(func(): label.text = text)


static var _number_re: RegEx

static func _numbers() -> RegEx:
	if _number_re == null:
		_number_re = RegEx.new()
		# A run of digits with an optional single decimal part. Grouping commas
		# and signs stay in the template: "-" and "+" are words of the reading
		# ("+0.4"), and a sign that flipped makes the templates differ, so the
		# figure snaps rather than rolling through a meaningless zero.
		_number_re.compile("\\d+(?:\\.\\d+)?")
	return _number_re


## True when `a` and `b` differ only in the values of their numbers, each
## number keeping its count of decimals.
static func same_template(a: String, b: String) -> bool:
	# A grouped figure ("1,234") would roll group by group, through values it
	# never takes; the strip prints none, and one that appears snaps instead.
	if _grouped(a) or _grouped(b):
		return false
	var ma := _numbers().search_all(a)
	var mb := _numbers().search_all(b)
	if ma.is_empty() or ma.size() != mb.size():
		return false
	if _numbers().sub(a, "#", true) != _numbers().sub(b, "#", true):
		return false
	for i in ma.size():
		if _decimals(ma[i].get_string()) != _decimals(mb[i].get_string()):
			return false
	return true


## `a` with every number moved fraction `t` of the way to `b`'s, printed at
## its own decimals. Pure: tests/test_motion.gd pins it.
static func interpolate_text(a: String, b: String, t: float) -> String:
	if not same_template(a, b):
		return b if t >= 1.0 else a
	var ma := _numbers().search_all(a)
	var mb := _numbers().search_all(b)
	var out := ""
	var cursor := 0
	for i in ma.size():
		var m: RegExMatch = ma[i]
		out += a.substr(cursor, m.get_start() - cursor)
		var va := m.get_string().to_float()
		var vb := mb[i].get_string().to_float()
		var places := _decimals(m.get_string())
		var v := lerpf(va, vb, clampf(t, 0.0, 1.0))
		var digits := String.num(v, places).pad_decimals(places) if places > 0 else str(roundi(v))
		# A zero-padded field ("05 JAN") keeps its width.
		var width := m.get_string().length() - (places + 1 if places > 0 else 0)
		if m.get_string().begins_with("0") and width > 1:
			digits = digits.pad_zeros(width)
		out += digits
		cursor = m.get_end()
	out += a.substr(cursor)
	return out


static var _grouped_re: RegEx

static func _grouped(text: String) -> bool:
	if _grouped_re == null:
		_grouped_re = RegEx.new()
		_grouped_re.compile("\\d,\\d")
	return _grouped_re.search(text) != null


static func _decimals(number: String) -> int:
	var dot := number.find(".")
	return 0 if dot < 0 else number.length() - dot - 1
