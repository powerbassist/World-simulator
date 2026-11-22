extends SceneTree

## Headless test: godot --headless --script res://tests/test_finance_lever.gd
## Non-zero exit on any failure.
##
## G3 S4, Books in C ("the bill is the page"): each line's bar is its own lever. The bar is drawn to ONE
## money scale shared by every row (bn a year), so a press at the bar's end must land on the rate whose
## money is under the pointer, not on a linear rate track; the rate snaps to the row's step; the ring
## stays at today and the dot follows the draft; a row at vote or not set here takes no press; the
## keyboard still steps it (an HSlider underneath, so the editor and the goal panel's Go reach it as before).

const FinanceLever = preload("res://src/ui/finance_lever.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []
var _frame := 0
var _lever: FinanceLever
var _locked: FinanceLever
var _changes := 0


func _init() -> void:
	var host := PanelContainer.new()
	host.size = Vector2(600, 200)
	root.add_child(host)
	UiTheme.apply(host)
	var box := VBoxContainer.new()
	host.add_child(box)
	_lever = FinanceLever.new()
	_lever.custom_minimum_size = Vector2(412, 20)
	_lever.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(_lever)
	# 10 bn a year per point; the shared scale is 400 bn; today 20 %, so 200 bn; steps of 0.5 between 0 and 30.
	_lever.setup(10.0, 400.0, 20.0, Color("#d95926"))
	_lever.min_value = 0.0
	_lever.max_value = 30.0
	_lever.step = 0.5
	_lever.value = 20.0
	_lever.value_changed.connect(func(_v: float) -> void: _changes += 1)
	_locked = FinanceLever.new()
	_locked.custom_minimum_size = Vector2(412, 20)
	_locked.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(_locked)
	_locked.setup(10.0, 400.0, 20.0, Color("#56616A"))
	_locked.max_value = 30.0
	_locked.value = 20.0
	_locked.lock()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_check_geometry()
		_check_press_maps_money()
		_check_locked()
		_check_keys()
		_check_off_grid()
		_finish()
		return true
	return false


func _check_geometry() -> void:
	# Today's 200 bn is half of the 400 bn scale: the ring is half way along the bar's inner width.
	var mid: float = FinanceLever.PAD + (_lever.size.x - 2.0 * FinanceLever.PAD) * 0.5
	if absf(_lever.x_of(20.0) - mid) > 0.5:
		_fail("today's 200 bn sits at %s, not half way (%s)" % [_lever.x_of(20.0), mid])
	if absf(_lever.x_of(0.0) - FinanceLever.PAD) > 0.5:
		_fail("a rate of 0 is not at the bar's start: %s" % _lever.x_of(0.0))
	# A value past the scale is drawn at the bar's end, never past the control.
	if _lever.x_of(80.0) > _lever.size.x - FinanceLever.PAD + 0.5:
		_fail("800 bn on a 400 bn scale is drawn past the end: %s" % _lever.x_of(80.0))
	if not _lever.is_moved():
		_lever.value = 22.0
		if not _lever.is_moved():
			_fail("a draft at 22 against 20 today is not moved")
		_lever.value = 20.0
	if _lever.is_moved():
		_fail("the draft at today's value reads as moved")



## A press at the x of 300 bn sets 30 % (300 bn / 10 bn a point); a press between steps snaps.
func _check_press_maps_money() -> void:
	_changes = 0
	_click(_lever, _lever.x_of(26.0))
	if not is_equal_approx(_lever.value, 26.0):
		_fail("a press at 260 bn's x set %s, not 26" % _lever.value)
	if _changes != 1:
		_fail("one press emitted %d value_changed" % _changes)
	# Pass 1 on #443: a mouse hand lets go with the button; a focus kept held the Books page's rebuild off.
	if _lever.has_focus() or _lever.is_dragging():
		_fail("a released press left the lever focused or dragging")
	_click(_lever, _lever.x_of(24.2))
	if not is_equal_approx(_lever.value, 24.0):
		_fail("a press at 24.2's x did not snap to the 0.5 step: %s" % _lever.value)
	# A drag carries the value with the pointer.
	_press(_lever, _lever.x_of(24.0), true)
	var move := InputEventMouseMotion.new()
	move.position = _lever.get_global_rect().position + Vector2(_lever.x_of(12.0), 10.0)
	move.global_position = move.position
	move.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(move, true)
	_press(_lever, _lever.x_of(12.0), false)
	if not is_equal_approx(_lever.value, 12.0):
		_fail("a drag to 120 bn's x left %s, not 12" % _lever.value)
	_lever.value = 20.0
	if not is_equal_approx(_lever.ring_x(), _lever.x_of(20.0)):
		_fail("the ring is not at today")


func _check_locked() -> void:
	_click(_locked, _locked.x_of(10.0))
	if not is_equal_approx(_locked.value, 20.0):
		_fail("a locked lever took a press: %s" % _locked.value)
	if _locked.focus_mode != Control.FOCUS_NONE:
		_fail("a locked lever takes the keyboard")


func _check_keys() -> void:
	_lever.grab_focus()
	var key := InputEventKey.new()
	key.keycode = KEY_RIGHT
	key.physical_keycode = KEY_RIGHT
	key.pressed = true
	root.push_input(key, true)
	if not is_equal_approx(_lever.value, 20.5):
		_fail("the right arrow did not step the lever by 0.5: %s" % _lever.value)


func _check_off_grid() -> void:
	# Gate round on #443: a rate today off the step grid (Germany's 20.83 %) is not a move -- the slider snaps its value,
	# the dot draws the draft's.
	var odd := FinanceLever.new()
	odd.custom_minimum_size = Vector2(412, 20)
	_lever.get_parent().add_child(odd)
	odd.setup(10.0, 400.0, 20.83, Color.WHITE)
	odd.max_value = 30.0
	odd.step = 0.5
	odd.value = 20.83
	odd.shown = 20.83
	if odd.is_moved():
		_fail("a rate today off the step grid reads as moved (the snapped %s against %s)" % [odd.value, 20.83])
	odd.queue_free()


func _click(control: Control, x: float) -> void:
	_press(control, x, true)
	_press(control, x, false)


func _press(control: Control, x: float, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = down
	event.position = control.get_global_rect().position + Vector2(x, 10.0)
	event.global_position = event.position
	root.push_input(event, true)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_finance_lever")
		quit(0)
		return
	for message in _failures:
		printerr("FAIL: " + message)
	quit(1)
