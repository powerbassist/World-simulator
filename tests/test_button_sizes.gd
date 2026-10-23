extends SceneTree

## Headless test: godot --headless --script res://tests/test_button_sizes.gd
## Non-zero exit on any failure.
##
## V5.1's closing gate (N10, the author: "government - politics, meme probleme dans
## energie, le boutton est super large !"): a Button added straight to a vertical box
## fills the box's width, so a one-word verb (Dissolve, an order) was a 1 200 px slab.
## An action button is sized to its label: a row of verbs goes through
## `PanelKit.buttons()`, a lone one through `PanelKit.action()`. This opens every
## window and fails a visible plain Button that fills a vertical box far past its
## label. (Deliberately full-width controls -- an OptionButton, a toggle -- are
## other classes and stay out, and so do left-aligned list rows and fold headers.)

## A button may be this much wider than its label before it reads as a slab:
## the theme's padding and a little air, not a layout.
const SLACK := 160.0

var _failures: Array[String] = []
var _main
var _frame := 0
var _ids: Array = []
var _at := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _ids.is_empty():
		_ids = _main._windows.panel_ids()
	if _at > 0 and _at <= _ids.size():
		_scan(_main._windows, String(_ids[_at - 1]))
	if _at < _ids.size():
		_main._windows.close_all()
		_main._windows.open(String(_ids[_at]))
		_at += 1
		return false
	_finish()
	return true


func _scan(node: Node, where: String) -> void:
	for child in _all(node):
		if child.get_class() != "Button" or not (child as Control).is_visible_in_tree():
			continue
		var button := child as Button
		var parent := button.get_parent()
		if not (parent is BoxContainer and (parent as BoxContainer).vertical):
			continue
		if button.size_flags_horizontal & Control.SIZE_FILL == 0:
			continue
		# A left-aligned label is a list row or a disclosure header (a fold's title),
		# full width on purpose; a slab is a centred one-word verb.
		if button.alignment == HORIZONTAL_ALIGNMENT_LEFT:
			continue
		var font := button.get_theme_font("font")
		var size := button.get_theme_font_size("font_size")
		var label := font.get_string_size(button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		if button.size.x > label + SLACK:
			_fail("%s: the '%s' button is %.0f px wide for a %.0f px label (a slab in %s)" % [where, button.text, button.size.x, label, parent.name])


func _all(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out


func _fail(message: String) -> void:
	if not _failures.has(message):
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_button_sizes: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
