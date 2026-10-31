extends RefCounted

## One half of a real click, for the UI tests that drive a control through the
## viewport with the press and the release frames apart (V5.1's dead clicks hid
## behind one-frame pushes). Not a test: a helper the tests preload.
##
## Windowed, the real OS cursor is an input too. A motion of it between the two
## halves reaches the pressed button and sets BaseButton's pressing_inside to
## false, and the release then clicks nothing -- QA's RECORD on #168, where one
## windowed run in two failed on whichever click the cursor happened to cross. So
## each half pushes a motion onto the target first, and the release is always
## inside; and the hand cannot add one of its own, because the window is moved off
## every monitor (OsCursor.quiet_window()).
## Warping the pointer onto the target, which this used to do on every half, dragged
## the author's cursor across the desk on each click: it now happens only under
## NATION_OS_CURSOR=1 (tools/os_cursor.gd), where the window keeps the real mouse
## and the warp pins it as before. Headless there is no pointer and neither applies.


const OsCursor = preload("res://tools/os_cursor.gd")


## Press (`down`) or release `button` (the left one unless named) at the centre
## of `target`.
static func half(viewport: Viewport, target: Control, down: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var at: Vector2 = target.get_global_rect().get_center()
	OsCursor.quiet_window()
	OsCursor.warp(viewport, at)
	var move := InputEventMouseMotion.new()
	move.position = at
	move.global_position = at
	viewport.push_input(move, true)
	var click := InputEventMouseButton.new()
	click.button_index = button as MouseButton
	click.pressed = down
	click.position = at
	click.global_position = at
	viewport.push_input(click, true)
