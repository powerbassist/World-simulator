extends RefCounted

## One half of a real click, for the UI tests that drive a control through the
## viewport with the press and the release frames apart (V5.1's dead clicks hid
## behind one-frame pushes). Not a test: a helper the tests preload.
##
## Windowed, the real OS cursor is an input too. A motion of it between the two
## halves reaches the pressed button and sets BaseButton's pressing_inside to
## false, and the release then clicks nothing -- QA's RECORD on #168, where one
## windowed run in two failed on whichever click the cursor happened to cross. So
## each half puts the cursor on the target and pushes a motion there first, and the
## release is always inside. Headless, the warp is a no-op.


## Press (`down`) or release `button` (the left one unless named) at the centre
## of `target`.
static func half(viewport: Viewport, target: Control, down: bool, button: int = MOUSE_BUTTON_LEFT) -> void:
	var at: Vector2 = target.get_global_rect().get_center()
	viewport.warp_mouse(at)
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
