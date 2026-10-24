extends SceneTree

## Headless test: godot --headless --script res://tests/test_summit_flow.gd
## Non-zero exit on any failure.
##
## V5.1-d1b2 fix round, QA on #70 (TAKE 1) and the parent's ruling: a booked
## visit's summit
##   - HOLDS the clock while it is open -- a booked scene is modal (QA's summit
##     sat open from Jan 5 to Oct 1 with the clock running behind it);
##   - CONCLUDES on Continue: the spoken line's Continue walked back to the
##     dialogue's start (it asked for the line after "", the first), so every
##     path looped to the opening line, `concluded` never fired and the choice
##     was never applied -- very likely the author's "state visit toujours cassé";
##   - releases the hold when it concludes, and applies the choice.
## Driven a few frames a beat: the dialogue manager's next line is awaited.

const Trends = preload("res://src/ui/trends.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _step := 0
var _wait := 0
var _effects_before := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame > 400:
		_fail("the summit did not conclude within 400 frames (stuck at step %d)" % _step)
		return _finish()
	if _wait > 0:
		_wait -= 1
		return false
	var panel = _main._summit_panel
	match _step:
		0:
			_main._paused_for_programme = false
			_main._clock.set_process(false)
			_main._clock.paused = false
			_effects_before = _main._pending_effects.size()
			_main._open_summit("DEU", Trends.snapshot_now(_main._state))
			if not _main._windows.is_open("summit"):
				_fail("premise: no summit opened for Germany")
				return _finish()
			if not _main._clock.paused:
				_fail("an open summit left the clock running behind it")
		1:
			_press_first_choice(panel)
		2:
			_press_first_choice(panel)
		3:
			if not panel._continue_button.visible:
				_fail("the closing line offers no Continue")
				return _finish()
			panel._continue_button.pressed.emit()
		4:
			if _main._windows.is_open("summit"):
				_fail("Continue on the closing line did not end the summit: '%s'" % panel._line_label.text)
				return _finish()
			if _main._clock.paused:
				_fail("the concluded summit did not release the clock")
			if _main._pending_effects.size() != _effects_before + 1:
				_fail("the summit's choice was not applied (%d effects queued)" % (_main._pending_effects.size() - _effects_before))
			return _finish()
	_step += 1
	_wait = 5
	return false


## The first offered choice. The German pool holds several scenes now and the
## draw picks one, so the flow is walked by position, not by one scene's labels:
## every scene's first branch ends on a priced response, so the effect lands.
func _press_first_choice(panel) -> void:
	for button in panel._choices_box.get_children():
		if button is Button:
			button.pressed.emit()
			return
	_fail("no choice on the summit's line '%s'" % panel._line_label.text)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	if _failures.is_empty():
		print("test_summit_flow: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
