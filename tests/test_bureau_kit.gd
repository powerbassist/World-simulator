extends SceneTree

## Headless test: godot --headless --script res://tests/test_bureau_kit.gd
## Non-zero exit on any failure.
##
## The shared BUREAU pieces the register's order form needed and no panel had (the bureau
## audit, sections 3, 4 and 7; the parent's ruling for #420): a chip (a tone and a glyph
## beside its words, so a state is never told by colour alone), the button variations
## Primary (the one outlined action of a screen) and Small (a verb sized to the caption),
## and a segmented control (one choice among a few, the picked one outlined in the accent).
## Each is a theme variation or a PanelKit builder, never a panel's private copy.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []
var _frame := 0
var _box: VBoxContainer
var _chosen := ""
var _segments: HBoxContainer
var _chip: Control


func _init() -> void:
	var host := PanelContainer.new()
	host.size = Vector2(600, 400)
	root.add_child(host)
	UiTheme.apply(host)
	_box = VBoxContainer.new()
	host.add_child(_box)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_check_variations(_box.get_theme() if _box.get_theme() != null else (_box.get_parent() as Control).theme)
		_chip = PanelKit.chip(_box, "3 chances in 10", UiTheme.CHIP_WARN, "warning")
		_segments = PanelKit.segmented(_box, [{"id": "a", "label": "Hospital"}, {"id": "b", "label": "School"}], "b",
			func(id: String) -> void: _chosen = id)
		return false
	if _frame == 4:
		_check_chip()
		_check_segments()
		_finish()
		return true
	return false


func _check_variations(theme: Theme) -> void:
	if theme == null:
		_fail("no theme on the host")
		return
	for v in [UiTheme.PRIMARY, UiTheme.SMALL, UiTheme.SEGMENT]:
		if theme.get_type_variation_base(v) != &"Button" or not theme.has_stylebox("normal", v):
			_fail("%s is not a Button variation with its own look" % v)
	for v in [UiTheme.CHIP, UiTheme.CHIP_WARN, UiTheme.CHIP_GOOD, UiTheme.CHIP_BAD]:
		if theme.get_type_variation_base(v) != &"PanelContainer" or not theme.has_stylebox("panel", v):
			_fail("%s is not a PanelContainer variation with a panel box" % v)
	var small: StyleBoxFlat = theme.get_stylebox("normal", UiTheme.SMALL)
	var plain: StyleBoxFlat = theme.get_stylebox("normal", "Button")
	if small.content_margin_left >= plain.content_margin_left:
		_fail("Small is not tighter than a Button")
	var primary: StyleBoxFlat = theme.get_stylebox("normal", UiTheme.PRIMARY)
	if primary.border_width_left < 1 or primary.border_color == UiTheme.EDGE or primary.border_color == UiTheme.accent():
		_fail("Primary at rest has no outline of its own, or wears the accent (the accent is 'you are here')")


func _check_chip() -> void:
	if _chip == null or _chip.theme_type_variation != UiTheme.CHIP_WARN:
		_fail("the chip does not wear its tone's variation")
		return
	var glyph := _find(_chip, func(n): return n is TextureRect)
	var words := _find(_chip, func(n): return n is Label)
	if glyph == null or (glyph as TextureRect).texture == null:
		_fail("the warning chip has no glyph: a tone told by colour alone")
	if words == null or (words as Label).text != "3 chances in 10":
		_fail("the chip lost its words")


func _check_segments() -> void:
	var buttons: Array = []
	for c in _segments.get_children():
		if c is Button:
			buttons.append(c)
	if buttons.size() != 2:
		_fail("two options built %d segments" % buttons.size())
		return
	for b in buttons:
		if b.theme_type_variation != UiTheme.SEGMENT or not b.toggle_mode or b.button_group == null:
			_fail("a segment is not a grouped toggle in the Segment variation")
	if buttons[0].button_pressed or not buttons[1].button_pressed:
		_fail("the selected segment is not the pressed one")
	buttons[0].pressed.emit()
	if _chosen != "a":
		_fail("pressing a segment answered '%s'" % _chosen)


func _find(node: Node, pred: Callable) -> Node:
	for c in node.get_children():
		if pred.call(c):
			return c
		var deeper := _find(c, pred)
		if deeper != null:
			return deeper
	return null


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_bureau_kit: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
