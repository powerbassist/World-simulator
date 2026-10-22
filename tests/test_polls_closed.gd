extends SceneTree

## Headless test: godot --headless --script res://tests/test_polls_closed.gd
## Non-zero exit on any failure.
##
## V5.1-d1b2, G4 of the play gate: "when this is election time, the time should
## be paused, with a continue button to make suspense" -- and the author's answer
## to where the beat goes: "Oui, un temps avant". Election day stops on the polls
## closing, BEFORE the count: a plate that says the polls have closed, holds the
## clock like any decision (Space, the cluster's play and a speed cannot slip past
## it), and shows nothing of the result until Continue starts the count.

const Elections = preload("res://src/sim/elections.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_main._clock.set_process(false)
	_main._paused_for_programme = false
	_check_month_end_opens_on_the_polls()
	_check_the_beat_holds_and_hides()
	_finish()
	return true


func _check_month_end_opens_on_the_polls() -> void:
	var source := FileAccess.get_file_as_string("res://src/ui/main.gd")
	if not source.contains("_election_panel.show_polls_closed(results)"):
		_fail("the month end shows the result at once, not the polls closing first")


func _check_the_beat_holds_and_hides() -> void:
	var clock = _main._clock
	var panel = _main._election_panel
	var ns = _main._state.player()
	var results := [Elections.resolve(ns, _main._loader.parties.get(ns.id, []), ns.election_system,
		ns.election_threshold_pct, "national", int(_main._state.year), int(_main._state.month))]
	clock.paused = true
	panel.show_polls_closed(results)
	panel.show()
	var shown := _text_of(panel)
	if not shown.contains("POLLS CLOSED"):
		_fail("the beat's plate does not say the polls have closed: %s" % shown)
	for word in ["RE-ELECTED", "DEFEATED", "NEW ASSEMBLY", "COHABITATION", "remains the largest party", "is no longer the largest party"]:
		if shown.contains(word):
			_fail("the polls-closed plate already shows the result ('%s')" % word)

	var dismissed := [0]
	panel.dismissed.connect(func(): dismissed[0] += 1)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	_main._unhandled_input(space)
	_main._hud.clock_cluster.pause_toggled.emit()
	_main._hud.clock_cluster.speed_selected.emit(3)
	if not clock.paused:
		_fail("a door ran the clock past the polls closing")
	# A click on the plate ends a count; on the beat there is no count to end.
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	panel._gui_input(click)
	if not _text_of(panel).contains("POLLS CLOSED"):
		_fail("a click on the plate skipped the polls-closed beat")

	panel._cont.pressed.emit()
	# QA on #70 (TAKE 4): a double-click's second half lands on the button the
	# count put in Continue's place; it must not skip the count, nor dismiss.
	panel._cont.pressed.emit()
	if not panel.visible or dismissed[0] != 0:
		_fail("a double-click on the beat's Continue went past the count (dismissed %d)" % dismissed[0])
	var after := _text_of(panel)
	if after.contains("POLLS CLOSED"):
		_fail("Continue on the beat did not start the count")
	if dismissed[0] != 0:
		_fail("Continue on the beat dismissed the result before it was shown")
	if not clock.paused:
		_fail("the count started with the clock running")


func _text_of(node: Node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	for child in node.get_children():
		out += _text_of(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_polls_closed: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
