extends SceneTree

## Headless test: godot --headless --script res://tests/test_backdrop.gd
## Non-zero exit on any failure.
##
## The modal backdrop (the author's pick, 2026-11-13: "slightly darken and blur the
## background", variant A, for EVERY modal). screen_stack.add() is the one place a
## modal gets its dim, so this test drives that one door: a panel added with
## `dim = true` gets a full-rect, click-eating backdrop whose material is the shared
## blur material, its blur and dim read off the two tokens, shown exactly while the
## panel is; a panel added without `dim` gets none.
##
## Driven a frame at a time: a Control outside the scene tree has not run _ready()
## (docs/engine-decision.md), and the stack builds its hosts there.

const ScreenStack = preload("res://src/ui/screen_stack.gd")
const Backdrop = preload("res://src/ui/backdrop.gd")

var _failures: Array[String] = []
var _frame := 0
var _stack
var _dimmed: Control
var _plain: Control


func _init() -> void:
	_stack = ScreenStack.new()
	root.add_child(_stack)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 1:
		return false  # let the stack's _ready() build its hosts
	_dimmed = _panel()
	_plain = _panel()
	_stack.add(ScreenStack.SCENE, _dimmed, true)
	_stack.add(ScreenStack.SYSTEM, _plain, false)
	_check_a_dimmed_modal_gets_the_backdrop()
	_check_a_plain_panel_gets_none()
	_check_the_backdrop_follows_the_panel()
	_check_the_tokens_are_what_is_drawn()
	_check_every_dimmed_modal_shares_one_material()
	_finish()
	return true


func _panel() -> Control:
	var panel := PanelContainer.new()
	panel.visible = false
	return panel


## The backdrops of a rank, in the order added. A plain rect with the shared material is one.
func _backdrops(rank: int) -> Array[ColorRect]:
	var out: Array[ColorRect] = []
	for child in _stack._hosts[rank].get_children():
		if child is ColorRect and Backdrop.is_applied(child):  # not by name: a second one is renamed by the engine
			out.append(child)
	return out


func _check_a_dimmed_modal_gets_the_backdrop() -> void:
	var found := _backdrops(ScreenStack.SCENE)
	if found.size() != 1:
		_fail("a modal added with dim = true got %d backdrops, want 1" % found.size())
		return
	var rect := found[0]
	if not Backdrop.is_applied(rect):
		_fail("the modal's backdrop does not wear the shared blur material")
	if rect.mouse_filter != Control.MOUSE_FILTER_STOP:
		_fail("the backdrop lets clicks through to the world behind the modal")
	if rect.anchor_right != 1.0 or rect.anchor_bottom != 1.0:
		_fail("the backdrop is not full-rect")


func _check_a_plain_panel_gets_none() -> void:
	if not _backdrops(ScreenStack.SYSTEM).is_empty():
		_fail("a panel added with dim = false got a backdrop")


func _check_the_backdrop_follows_the_panel() -> void:
	var found := _backdrops(ScreenStack.SCENE)
	if found.is_empty():
		return
	var rect := found[0]
	if rect.visible:
		_fail("the backdrop is up while its panel is hidden")
	_dimmed.visible = true
	if not rect.visible:
		_fail("the backdrop is not up while its panel is shown")
	_dimmed.visible = false
	if rect.visible:
		_fail("the backdrop stayed up after its panel was hidden")


func _check_the_tokens_are_what_is_drawn() -> void:
	var mat := Backdrop.material()
	if not is_equal_approx(float(mat.get_shader_parameter("blur_px")), Backdrop.BLUR_PX):
		_fail("the blur is not Backdrop.BLUR_PX: %s" % [mat.get_shader_parameter("blur_px")])
	var tint: Color = mat.get_shader_parameter("tint")
	if not tint.is_equal_approx(Backdrop.DIM):
		_fail("the dim is not Backdrop.DIM: %s" % [tint])
	var code := String(mat.shader.code)
	if not code.contains("hint_screen_texture") or not code.contains("textureLod"):
		_fail("the backdrop does not sample the screen texture's mips")
	# The author's pick, pinned: 4 px, 30 %.
	if not is_equal_approx(Backdrop.BLUR_PX, 4.0) or not is_equal_approx(Backdrop.DIM.a, 0.30):
		_fail("the backdrop is not the author's pick (4 px, 30 %%): %s px, %s" % [Backdrop.BLUR_PX, Backdrop.DIM.a])


func _check_every_dimmed_modal_shares_one_material() -> void:
	var second := _panel()
	_stack.add(ScreenStack.SCENE, second, true)
	var found := _backdrops(ScreenStack.SCENE)
	if found.size() != 2:
		_fail("a second dimmed modal did not add its backdrop: %d" % found.size())
		return
	if found[0].material != found[1].material:
		_fail("two modals carry two blur materials: the screen is copied twice")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_backdrop: all checks passed")
		quit(0)
		return
	for message in _failures:
		print("FAIL: " + message)
	quit(1)
