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
## V5.3 screen 4 (Health's finding): the choice is priced by the response's STABLE ID
## (`[#id:...]` tag, response.tags), never by its text. The whole walk runs twice, the
## second time with every response translated: the buttons read the translation and the
## concluded summit STILL applies its effects (a choice keyed by its English text lost them).
## Driven a few frames a beat: the dialogue manager's next line is awaited.

const Trends = preload("res://src/ui/trends.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _step := 0
var _wait := 0
var _effects_before := 0
var _pass := 0
var _translation: Translation = null


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
			if _pass == 1:
				_install_translation()
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
				_fail("the summit's choice was not applied%s (%d effects queued)" % [" in translation" if _pass == 1 else "", _main._pending_effects.size() - _effects_before])
			if _pass == 1 and not String(_main._summit_panel.chosen_label).begins_with("«"):
				_fail("the translated run read '%s', not the translation: the premise failed" % _main._summit_panel.chosen_label)
			if _pass == 0:
				_pass = 1
				_step = -1
				_wait = 5
				_main._clock.paused = false
			else:
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
			if _pass == 1 and not (button as Button).text.begins_with("«"):
				_fail("a response is not translated on the translated run: '%s'" % (button as Button).text)
			button.pressed.emit()
			return
	_fail("no choice on the summit's line '%s'" % panel._line_label.text)


## Every DEU response read through tr() as "«TEXT»": what dialogue_manager does with a French
## table loaded, without needing one.
func _install_translation() -> void:
	_translation = Translation.new()
	_translation.locale = TranslationServer.get_locale()
	for summit in _main._loader.summits["DEU"]:
		for line in String(summit.dialogue_text).split("\n"):
			if not line.strip_edges().begins_with("- "):
				continue
			var text := line.strip_edges().substr(2).split(" [#id:")[0]
			_translation.add_message(text, "«" + text.to_upper() + "»")
	TranslationServer.add_translation(_translation)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> bool:
	if _translation != null:
		TranslationServer.remove_translation(_translation)
	if _failures.is_empty():
		print("test_summit_flow: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
	return true
