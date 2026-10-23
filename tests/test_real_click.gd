extends SceneTree

## Headless test: godot --headless --script res://tests/test_real_click.gd
## Non-zero exit on any failure.
##
## V5.1 pre-gate 2 (the author's gate, blocked): on 2a7db7dd no real mouse click
## fired any button. d2's "a click parks no focus" released the pressed button's focus
## with a call_deferred on the PRESS; BaseButton cancels its press on FOCUS_EXIT, and
## in the default release action mode it fires only on the release, so a real click
## (down, frames pass, up) lost its press before the up. Every earlier test pushed the
## down and the up in the same frame, before the deferred call ran. This one holds the
## button down for several frames, as a hand does.

var _failures: Array[String] = []
var _main
var _frame := 0
var _button: Button
var _fired := 0
var _point := Vector2(700, 400)


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_button = Button.new()
			_button.text = "click me"
			_button.position = _point - Vector2(40, 15)
			_button.size = Vector2(80, 30)
			_button.pressed.connect(func(): _fired += 1)
			_main._stack.add_child(_button)
		5:
			_mouse(true)
		9:
			# Four frames down: long enough for any deferred call to have run.
			if _fired != 0:
				_fail("the button fired on the press (release action mode fires on the up)")
			_mouse(false)
		11:
			if _fired != 1:
				_fail("a click held for frames did not fire the button (fired %d times)" % _fired)
			if _main.get_viewport().gui_get_focus_owner() == _button:
				_fail("the click left the keyboard on the button: the next Space would press it again")
			_finish()
			return true
	return false


func _mouse(pressed: bool) -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = pressed
	click.position = _point
	click.global_position = _point
	_main.get_viewport().push_input(click, true)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_real_click: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
