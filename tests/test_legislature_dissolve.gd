extends SceneTree

## Headless test: godot --headless --script res://tests/test_legislature_dissolve.gd
## Non-zero exit on any failure.
##
## V5.2 b+ (R3, gate b: "button disolve should be in parliament ? i looked in
## parliament but was in gov"). The Legislature carries the Dissolve verb too, read
## off the same rule as Government > Politics':
##   - live for France on a fresh game, with its price on the hover;
##   - a real click (press and release frames apart) asks first (#135 follow-up,
##     the parent's call): "Dissolve the Assembly? An election follows on <date>."
##     with Dissolve and Cancel; Cancel calls nothing;
##   - Dissolve on the card calls the dissolution in the sim and reaches main's
##     effect queue, as the Politics button does;
##   - then both buttons read the refusal (a dissolution already under way), and a
##     confirm the sim refuses announces nothing (QA's #135-1).

const Dissolution = preload("res://src/sim/dissolution.gd")
const Words = preload("res://src/ui/lever_words.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _button: Button
var _target: Control


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._windows.open("legislature")
		6:
			_button = _main._law_panel.find_child("Dissolve", true, false) as Button
			if _button == null or not _button.is_visible_in_tree():
				_fail("the Legislature has no Dissolve button on screen")
				_finish()
				return true
			if _button.disabled or not _button.tooltip_text.contains("locks out"):
				_fail("the Legislature's Dissolve is not live with its price: disabled %s, '%s'" % [_button.disabled, _button.tooltip_text])
			_target = _button
			_press(true)
		9:
			_press(false)
		12:
			var card := _card()
			var ns = _main._state.player()
			if card == null or not card.is_visible_in_tree():
				_fail("a click on Dissolve does not ask first")
				_finish()
				return true
			var due: int = int(_main._state.year) * 12 + int(_main._state.month) + int(ns.dissolution_notice_months)
			var question := "Dissolve the Assembly? An election follows on %s." % Words.when(due)
			if not _text(card).contains(question):
				_fail("the card does not ask '%s': %s" % [question, _text(card)])
			if ns.dissolution_pending:
				_fail("the click dissolved before the card was answered")
			_target = card.find_child("Cancel", true, false) as Control
			_press(true)
		15:
			_press(false)
		18:
			var ns = _main._state.player()
			if _card().is_visible_in_tree() or ns.dissolution_pending:
				_fail("Cancel left the card up or dissolved: visible %s, pending %s" % [_card().visible, ns.dissolution_pending])
			_target = _button
			_press(true)
		21:
			_press(false)
		24:
			_target = _card().find_child("Confirm", true, false) as Control
			_press(true)
		27:
			_press(false)
		30:
			var ns = _main._state.player()
			if _card().is_visible_in_tree():
				_fail("the card stays up after Dissolve")
			if not ns.dissolution_pending:
				_fail("Dissolve on the card did not call the dissolution")
			if not str(_main._pending_effects).contains("Dissolution called"):
				_fail("the Legislature's dissolution did not reach main's effect queue: %s" % [_main._pending_effects])
			_main._law_panel._refresh()
			_main._government_panel._refresh()
			for panel in [_main._law_panel, _main._government_panel]:
				var b := panel.find_child("Dissolve", true, false) as Button
				if b == null or not b.disabled or b.tooltip_text != Dissolution.refusal_reason(_main._state, ns):
					_fail("%s's Dissolve does not read the refusal after the call" % panel.name)
			# QA's #135-1: a confirm the sim refuses (one already under way) is no
			# dissolution, and nothing announces one.
			var queued := str(_main._pending_effects).count("Dissolution called")
			(_card() as Node).confirmed.emit()
			if str(_main._pending_effects).count("Dissolution called") != queued:
				_fail("a refused dissolution was announced")
			_finish()
			return true
	return false


func _press(down: bool) -> void:
	var at: Vector2 = _target.get_global_rect().get_center()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = down
	click.position = at
	click.global_position = at
	_main.get_viewport().push_input(click, true)


func _card() -> Control:
	return _main.find_child("ConfirmCard", true, false) as Control


func _text(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "Label", true, false):
		out += (label as Label).text + "
"
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_legislature_dissolve: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
