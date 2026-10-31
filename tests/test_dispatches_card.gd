extends SceneTree

## Headless test: godot --headless --script res://tests/test_dispatches_card.gd
## Non-zero exit on any failure.
##
## V5.3-0 (b), R10: a Dispatches desk entry is one card whose choices open their
## own text on select.
##   - with nothing selected, no choice's summary is on screen, and no Choose;
##   - a real click (press and release frames apart) on a choice opens ITS summary
##     and a Choose, and nothing is answered yet;
##   - a click on Choose answers that choice (the desk entry leaves the queue and
##     the ledger records it), and the record's meaning rides the answer's hover.

const Click = preload("res://tests/click.gd")
const Strings = preload("res://src/ui/strings.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

var _failures: Array[String] = []
var _main
var _panel
var _ev
var _choice: Dictionary
var _frame := 0
var _target: Control


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_panel = _main._events_panel
			_stage()
			_main._windows.open("events")
		6:
			_check_closed()
			_target = _button(Strings.choice_label(_ev.id, _choice))
			_press(true)
		9:
			_press(false)
		12:
			_check_open()
			_target = _button("Choose")
			_press(true)
		15:
			_press(false)
		18:
			_check_answered()
			_finish()
			return true
	return false


## A non-default choice of the first event with three, alone on the desk.
func _stage() -> void:
	for candidate in _main._loader.events:
		if candidate.choices.size() >= 2:
			_ev = candidate
			break
	for choice in _ev.choices:
		if not bool(choice.get("is_default", false)):
			_choice = choice
			break
	var ns = _main._state.player()
	ns.event_queue.clear()
	ns.event_queue.append({"event_id": String(_ev.id), "months_left": 3, "severity": 2})
	_panel.mark_dirty()


func _summary(choice: Dictionary) -> String:
	return PanelKit.TermText.plain(Strings.choice_summary(_ev.id, choice)).left(30)


func _check_closed() -> void:
	var text := _text(_panel._body)
	for choice in _ev.choices:
		if _summary(choice) != "" and text.contains(_summary(choice)):
			_fail("a choice's summary is on screen before any choice was selected")
	if _button("Choose") != null:
		_fail("a Choose is on screen before any choice was selected")


func _check_open() -> void:
	var text := _text(_panel._body)
	if _summary(_choice) != "" and not text.contains(_summary(_choice)):
		_fail("selecting a choice did not open its summary")
	for choice in _ev.choices:
		if choice != _choice and _summary(choice) != "" and text.contains(_summary(choice)):
			_fail("selecting one choice opened another's summary too")
	if not _main._state.player().event_queue.size() == 1:
		_fail("selecting a choice answered it")


func _check_answered() -> void:
	var ns = _main._state.player()
	if not ns.event_queue.is_empty():
		_fail("Choose did not answer the desk entry")
		return
	var last: Dictionary = ns.event_history.back() if not ns.event_history.is_empty() else {}
	if String(last.get("choice_id", "")) != String(_choice.get("id", "")):
		_fail("the ledger recorded %s, not the chosen %s" % [last.get("choice_id", ""), _choice.get("id", "")])
	var hovered := false
	for label in _panel._body.find_children("*", "Label", true, false):
		if (label as Label).text == Strings.choice_label(_ev.id, _choice) and (label as Label).tooltip_text != "":
			hovered = true
	if not hovered and _summary(_choice) != "":
		_fail("the timeline's answer carries no meaning on hover")


func _button(text: String) -> Button:
	for b in _panel._body.find_children("*", "Button", true, false):
		if (b as Button).text.begins_with(text) and (b as Button).is_visible_in_tree() and not b.is_queued_for_deletion():
			return b
	return null


func _text(node: Node) -> String:
	var out := ""
	if node.is_queued_for_deletion():
		return out
	if node is Label or node is Button:
		out += String(node.text) + "\n"
	elif node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	for child in node.get_children():
		out += _text(child)
	return out


func _press(down: bool) -> void:
	if _target == null:
		_fail("no control to click at frame %d" % _frame)
		return
	Click.half(_main.get_viewport(), _target, down)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_dispatches_card: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
