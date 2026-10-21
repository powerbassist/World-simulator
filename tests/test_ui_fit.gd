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
##
## The same open briefing carries a second, textual check (QA #50): its effect
## sentence was the lines joined with ". " plus a final ".", over lines that each
## end in their own full stop, so every one read "... of GDP.." on screen.

const BriefingUi = preload("res://src/ui/briefing.gd")

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
		_check_briefing_full_stops()
		_finish()
	return false


## The first law whose briefing has two effect lines or more: the join is what the
## text check is about, and one line has nothing to join.
func _open_briefing() -> void:
	_briefing = _main._briefing
	var laws: Array = _main._loader.laws
	var pick = null
	for law in laws:
		if BriefingUi.effect_lines(law.effects, _main._state.player()).size() >= 2:
			pick = law
			break
	if pick == null:
		_fail("no authored law has two effect lines to brief on")
		return
	_law_id = String(pick.id)
	_briefing.open_for_law(pick, _main._state, _main._loader)
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


## No label of the open briefing holds a doubled full stop (an ellipsis is three).
func _check_briefing_full_stops() -> void:
	if not _opened:
		return
	var doubled := RegEx.create_from_string(r"(?<!\.)\.\.(?!\.)")
	for label in _briefing.find_children("*", "Label", true, false):
		var text := String((label as Label).text)
		if doubled.search(text) != null:
			_fail("the briefing for '%s' prints a doubled full stop: %s" % [_law_id, text])


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
