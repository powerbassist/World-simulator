extends SceneTree

## Headless test: godot --headless --script res://tests/test_ui_fit.gd
## Non-zero exit on any failure.
##
## V5.1a's QA sweep, kept as a test. Swapping the interface to Archivo made text
## wider than the Barlow every popup was sized against, and a popup with a fixed
## width and a scroll view clips what no longer fits -- silently: the bill
## briefing's two "Commission ... poll" buttons sat in one row of 716 px inside a
## 646 px view, and every right-aligned figure (each bloc's price and poll
## reading) landed in the cut-off strip, so the player saw the names and no
## numbers. The shape of the check is QA's: a ScrollContainer's content minimum
## width must not exceed its view. The headless root is 64x64, so a popup is given
## its own minimum size first and the comparison is like for like.

var _failures: Array[String] = []
var _main
var _frame := 0
var _briefing
var _law_id := ""
var _opened := false


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_open_briefing()
	if _frame == 5:
		_check_briefing()
		_finish()
	return false


func _open_briefing() -> void:
	_briefing = _main._briefing
	var laws: Array = _main._loader.laws
	if laws.is_empty():
		_fail("no authored law to brief on")
		return
	_law_id = String(laws[0].id)
	_briefing.open_for_law(laws[0], _main._state, _main._loader)
	_opened = true
	_briefing.show()
	_briefing.size = _briefing.custom_minimum_size


func _check_briefing() -> void:
	if not _opened:
		_fail("the briefing was never opened, so there is nothing to measure")
		return
	var scrolls := _scrolls_in(_briefing)
	if scrolls.is_empty():
		_fail("the briefing has no ScrollContainer")
	for scroll in scrolls:
		var body: Control = scroll.get_child(0)
		var need := body.get_combined_minimum_size().x
		if need > scroll.size.x + 0.5:
			_fail("the briefing for '%s' needs %.0f px but its view is %.0f: right-hand figures are clipped" % [_law_id, need, scroll.size.x])


func _scrolls_in(node: Node) -> Array[ScrollContainer]:
	var out: Array[ScrollContainer] = []
	if node is ScrollContainer:
		out.append(node)
	for child in node.get_children():
		out.append_array(_scrolls_in(child))
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_ui_fit: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
