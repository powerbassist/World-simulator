extends SceneTree

## Headless test: godot --headless --script res://tests/test_play_gate_terms.gd
## Non-zero exit on any failure.
##
## The V5.1 play gate's terms, on the screens a first term reaches: "Article 49.3"
## in the Politics window and "approval" in the Diplomacy window a map click
## opens. Each must draw as a hoverable term (a TermText carrying term:<id>), and
## no line in either window may print a raw [g=...] tag -- what a UI line marked
## in its msgid but left a Label would show.
##
## Driven through the real game: a panel builds its body in _process once it is
## visible, so a check on a panel that was never opened would read nothing.

const TermText = preload("res://src/ui/term_text.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_main._windows.open("politics")
	elif _frame == 5:
		_check(_main._government_panel, "article_49_3", "Politics")
		_main._on_nation_clicked(String(_main._state.player().id))
	elif _frame == 8:
		_check(_main._nation_panel, "approval", "Diplomacy")
		_finish()
		return true
	return false


func _check(panel: Node, id: String, window: String) -> void:
	var terms := 0
	for node in _all(panel):
		if node.get_script() == TermText and String(node.text).contains(TermText.META_PREFIX + id):
			terms += 1
		if (node is Label or node is RichTextLabel) and String(node.get("text")).contains("[g="):
			_fail("%s prints a raw tag: %s" % [window, node.get("text")])
	if terms == 0:
		_fail("the %s window draws no %s term" % [window, id])


func _all(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out.append_array(_all(child))
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_play_gate_terms: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
