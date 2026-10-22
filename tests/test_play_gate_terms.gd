extends SceneTree

## Headless test: godot --headless --script res://tests/test_play_gate_terms.gd
## Non-zero exit on any failure.
##
## The V5.1 play gate's terms, on the screens a first term reaches: "Article 49.3"
## in the Politics window and "approval" on the Society window's polling headline
## -- the one approval line whose figure is the glossary's live value (the
## headline poll); the Diplomacy window's true figure for any nation would sit
## beside a plate quoting the player's poll. Each must draw as a hoverable term
## (a TermText carrying term:<id>), and no line in either window may print a raw
## [g=...] tag -- what a UI line marked in its msgid but left a Label would show.
##
## Driven through the real game: a panel builds its body in _process once it is
## visible, so a check on a panel that was never opened would read nothing.

const TermText = preload("res://src/ui/term_text.gd")
const GameState = preload("res://src/core/game_state.gd")
const GovernmentPanel = preload("res://src/ui/government_panel.gd")

## The line exists only under a constitution with Article 49.3 (FRA's), and
## must not show for the parliamentary systems the author plays.
const FORCE_LINE := {"FRA": true, "DEU": false, "GBR": false, "POL": false}

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
		_main._windows.open("society")
	elif _frame == 8:
		_check(_main._polling_panel, "approval", "Society")
		_check_force_line_follows_the_constitution()
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


## The Politics window of a game played as each nation: the 49.3 tally is the
## French constitution's, so it follows the formation method the system carries,
## never the nation id.
func _check_force_line_follows_the_constitution() -> void:
	for nation_id in FORCE_LINE:
		var state = GameState.new_game(_main._loader, nation_id)
		var panel = GovernmentPanel.new()
		root.add_child(panel)
		panel.setup(state, _main._loader)
		panel._refresh()
		var shown := false
		for node in _all(panel):
			if node.get_script() == TermText and String(node.text).contains(TermText.META_PREFIX + "article_49_3"):
				shown = true
		if shown != FORCE_LINE[nation_id]:
			_fail("%s: the Article 49.3 line %s" % [nation_id, "is missing" if FORCE_LINE[nation_id] else "shows, with no 49.3 in its constitution"])
		panel.free()


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
