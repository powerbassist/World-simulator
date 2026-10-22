extends SceneTree

## Headless test: godot --headless --script res://tests/test_inbox_stays.gd
## Non-zero exit on any failure.
##
## V5.1-d1a, G1 of the play gate: "the inbox disappear as soon as i click
## something on the left panel". Opening a tab docked the inbox off the map and
## hid it, so a sidebar click took the messages away. The inbox the player had
## in front of them now rides over the tab and stays, from tab to tab, until
## they put it away (Escape, the sidebar's Inbox) or answer what held it; put
## away, it stays away until the map has it back.

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check()
	_finish()
	return true


func _check() -> void:
	var windows = _main._windows
	var inbox = _main._hud.inbox
	windows.close_all()
	if not inbox.visible or inbox.is_slid():
		_fail("premise: on the bare map the inbox is not docked there (visible %s, slid %s)" % [inbox.visible, inbox.is_slid()])
		return

	windows.open("budget")
	if not inbox.visible or not inbox.is_slid():
		_fail("opening a tab took the inbox away (visible %s, slid %s)" % [inbox.visible, inbox.is_slid()])
	windows.open("politics")
	if not inbox.visible or not inbox.is_slid():
		_fail("a second tab took the inbox away (visible %s, slid %s)" % [inbox.visible, inbox.is_slid()])

	inbox.slide_out()
	if inbox.visible:
		_fail("putting the inbox away left it on screen")
	windows.open("society")
	if inbox.visible:
		_fail("a tab opened after the inbox was put away brought it back")

	windows.close_all()
	if not inbox.visible or inbox.is_slid():
		_fail("back on the map the inbox is not docked there (visible %s, slid %s)" % [inbox.visible, inbox.is_slid()])

	# A scene is not a tab: the inbox goes away under it, as it always did.
	windows.open("summit")
	if inbox.visible or inbox.is_slid():
		_fail("a scene carried the inbox under it (visible %s, slid %s)" % [inbox.visible, inbox.is_slid()])
	windows.close_all()


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_inbox_stays: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
