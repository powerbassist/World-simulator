extends PanelContainer

## A right click's verbs -- V5.3 screen 4 (H14: a verb is one click away AND on a right click).
## A small plate by the pointer, one button per verb. The country box's shape (country_box.gd):
## a child of the screen stack under the tooltip chain, holding no rank, so Escape puts it away
## and a press elsewhere does too. Owns nothing of the game: the caller hands the items and a
## press runs the caller's Callable.
##
## An item is {text, enabled, reason, call}. A verb that is down stays on the plate with its
## reason as the tooltip, so the player learns why it is down instead of finding it missing
## (the table that builds the items never offers a press the sim refuses).

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")

const OFFSET := Vector2(10, 6)
const WIDTH := 300.0

var _body: VBoxContainer
var _owner: Node = null


## The plate of `from`'s screen stack, made on first use; null with no stack (a panel shown
## outside the game screen).
static func of(from: Node):
	var stack = from.get_tree().get_first_node_in_group(ScreenStack.GROUP)
	if stack == null:
		return null
	var plate = stack.get_node_or_null("VerbPlate")
	if plate == null:
		plate = new()
		plate.name = "VerbPlate"  # i18n: ok a node name, found by tests
		stack.add_child(plate)
		stack.move_child(plate, stack.tips.get_index())  # the tooltip chain stays the last child
	return plate


## Opens the plate by the pointer with `items`; `owner_node` is the panel it belongs to, so
## it goes when that panel does.
func open(owner_node: Node, items: Array) -> void:
	_owner = owner_node
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	for item in items:
		var press := Button.new()
		press.text = String(item["text"])  # i18n: row-ok the caller hands a translated string
		press.alignment = HORIZONTAL_ALIGNMENT_LEFT
		press.disabled = not bool(item.get("enabled", true))
		press.tooltip_text = String(item.get("reason", ""))
		var call: Callable = item["call"]
		press.pressed.connect(func() -> void:
			hide()
			call.call())
		_body.add_child(press)
	position = get_viewport().get_mouse_position() + OFFSET
	show()
	reset_size()
	_keep_on_screen.call_deferred()


func _init() -> void:
	theme_type_variation = UiTheme.PLATE
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	custom_minimum_size = Vector2(WIDTH, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	margin.add_child(_body)


func _process(_delta: float) -> void:
	if visible and (_owner == null or not is_instance_valid(_owner) or not _owner.is_visible_in_tree()):
		hide()


## Escape, or a press outside the plate, puts it away.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
		return
	var press := event as InputEventMouseButton
	if press != null and press.pressed and not get_global_rect().has_point(press.global_position):
		hide()


func _keep_on_screen() -> void:
	await get_tree().process_frame
	if not visible:
		return
	size = Vector2(WIDTH, 0)
	reset_size()
	var screen: Vector2 = get_viewport_rect().size
	position = Vector2(clampf(position.x, 0.0, maxf(screen.x - size.x, 0.0)),
		clampf(position.y, 0.0, maxf(screen.y - size.y, 0.0)))
