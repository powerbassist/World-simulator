extends SceneTree

## Headless test: godot --headless --script res://tests/test_nation_panel.gd
## Non-zero exit on any failure.
##
## V1.3a gave the Europe tab's nation panel the block's player verbs. It had
## been a read-only panel with no test at all, which was safe while it only
## printed labels and is not once pressing something inside it mutates the game.
##
## Loads the actual main scene, the shape test_law_panel.gd uses, and drives it
## a frame at a time -- a Control outside the scene tree has not run _ready(),
## so everything it builds is null. See docs/engine-decision.md.
##
## Every assertion here is a MUTATION check scoped to this panel. A "some button
## exists" or "something has focus" assertion passes against furniture the panel
## did not build.

const Relations = preload("res://src/core/relations.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")

const TARGET := "DEU"

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		return
	if _main._nation_panel == null:
		_fail("main scene did not build a nation panel")
		return

	var panel = _main._nation_panel
	var state = _main._state

	_check_own_nation_offers_nothing(panel, state)
	_check_other_nation_offers_verbs(panel, state)
	_check_pressing_act_moves_relations(panel, state)
	_check_acted_signal_carries_a_baseline(panel, state)


## The player's own nation is not a pair, so there is nothing to score and
## nothing to act on. Asserted before the positive case, so a panel that simply
## never builds anything cannot pass the next check by accident.
func _check_own_nation_offers_nothing(panel, state) -> void:
	_show(panel, state.player_nation_id)
	if _button_count(panel) != 0:
		_fail("the panel offered %d diplomatic buttons against the player's own nation" % _button_count(panel))


func _check_other_nation_offers_verbs(panel, state) -> void:
	_show(panel, TARGET)
	if _button_count(panel) == 0:
		_fail("the panel offered no diplomatic buttons against %s" % TARGET)

	# The relations figure has to be on screen, or the verbs are acting on a
	# number the player cannot see.
	var score := Diplomacy.score(state, state.player_nation_id, TARGET)
	if not _panel_text(panel).contains("%.0f" % score):
		_fail("the panel does not show the %s-%s relations figure" % [state.player_nation_id, TARGET])


## The check that matters: pressing the button changes the game. A disabled
## button is skipped rather than pressed, so this measures a verb that was
## actually offered.
func _check_pressing_act_moves_relations(panel, state) -> void:
	_show(panel, TARGET)
	var button: Button = _first_enabled_button(panel)
	if button == null:
		_fail("every diplomatic button against %s was disabled at game start" % TARGET)
		return

	var key := Relations.key(state.player_nation_id, TARGET)
	var before: float = float(state.relations[key])
	button.pressed.emit()

	if is_equal_approx(float(state.relations[key]), before):
		_fail("pressing a diplomatic button did not move the %s pair" % key)
	if state.player().last_diplomatic_result.is_empty():
		_fail("pressing a diplomatic button recorded no result for the panel to read")


## U4's decision-delta plumbing reads `before` as a Trends snapshot. A signal
## that fires with an empty baseline produces a "recent effect" measuring
## nothing, which is the silent-UI-failure class CLAUDE.md asks for a test on.
func _check_acted_signal_carries_a_baseline(panel, state) -> void:
	_show(panel, TARGET)
	var button: Button = _first_enabled_button(panel)
	if button == null:
		return

	var seen := []
	panel.acted.connect(func(before, label): seen.append({"before": before, "label": label}))
	button.pressed.emit()

	if seen.is_empty():
		_fail("pressing a diplomatic button emitted no `acted` signal")
		return
	if typeof(seen[0]["before"]) != TYPE_DICTIONARY or seen[0]["before"].is_empty():
		_fail("`acted` carried an empty baseline, so its recent-effect entry would measure nothing")
	if not str(seen[0]["label"]).contains(TARGET):
		_fail("`acted` label '%s' does not name the nation acted on" % seen[0]["label"])


# --- helpers -------------------------------------------------------------------

## _process() is what rebuilds the rows, and the panel skips it while hidden.
func _show(panel, nation_id: String) -> void:
	panel.show()
	panel.show_nation(nation_id)
	panel.mark_dirty()
	panel._process(0.0)


## Scoped to the panel's own actions container, not to the whole scene: a
## get_children() walk from the scene root would count the tab rail's buttons
## and pass no matter what this panel built.
func _buttons(panel) -> Array:
	var out: Array = []
	for row in panel._actions.get_children():
		for child in row.get_children() if row is HBoxContainer else []:
			if child is Button:
				out.append(child)
	return out


func _button_count(panel) -> int:
	return _buttons(panel).size()


func _first_enabled_button(panel):
	for button in _buttons(panel):
		if not button.disabled:
			return button
	return null


func _panel_text(panel) -> String:
	var text := ""
	for container in [panel._body, panel._actions]:
		for node in container.get_children():
			if node is Label:
				text += node.text + "\n"
			else:
				for child in node.get_children():
					if child is Label:
						text += child.text + "\n"
	return text


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_nation_panel: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
