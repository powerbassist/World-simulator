extends SceneTree

## Headless test: godot --headless --script res://tests/test_clock_doors.gd
## Non-zero exit on any failure.
##
## V5.1-d1a, the play gate's clock items:
##   G3 "click on speed selection should unpause the game" -- a speed picked on
##      a paused clock plays, by the cluster or by a key; not for a press replayed
##      after a month close (it predates any hold the month end raised, #63), and
##      not under a scene;
##   G4 "when this is election time, the time should be paused, with a continue
##      button" -- the result holds the clock against every door (Space, the
##      cluster's play, a speed) until its Continue;
##   G6 arming a placement puts the workspace away and keeps the order: the map
##      pick in the player's own land still builds.

const Elections = preload("res://src/sim/elections.gd")
const Region = preload("res://src/core/region.gd")

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
	_check_a_speed_plays()
	_check_a_replayed_speed_keeps_the_hold()
	_check_the_election_holds()
	_check_arming_clears_the_workspace()
	_finish()
	return true


func _check_a_speed_plays() -> void:
	var clock = _main._clock
	_main._windows.close_all()
	clock.paused = true
	clock.set_speed(1)
	_main._hud.clock_cluster.speed_selected.emit(2)
	if clock.speed != 2 or clock.paused:
		_fail("a speed clicked on a paused clock: speed %d, paused %s (wanted 2, running)" % [clock.speed, clock.paused])
	clock.paused = true
	_key(KEY_3)
	if clock.speed != 3 or clock.paused:
		_fail("the 3 key on a paused clock: speed %d, paused %s (wanted 3, running)" % [clock.speed, clock.paused])
	_main._hud.clock_cluster.speed_selected.emit(1)
	if clock.speed != 1 or clock.paused:
		_fail("a speed clicked on a running clock paused it, or did not set the speed")


func _check_a_replayed_speed_keeps_the_hold() -> void:
	var clock = _main._clock
	clock.paused = true
	_main._paused_for_decision = true
	_main._month_runner.replaying = true
	_key(KEY_2)
	_main._month_runner.replaying = false
	if clock.speed != 2:
		_fail("a replayed speed key was dropped instead of setting the speed")
	if not clock.paused or not _main._paused_for_decision:
		_fail("a speed key replayed after a month close resumed the clock a decision held")
	_main._paused_for_decision = false


func _check_the_election_holds() -> void:
	var clock = _main._clock
	var ns = _main._state.player()
	var party_list: Array = _main._loader.parties.get(ns.id, [])
	var results := [Elections.resolve(ns, party_list, ns.election_system, ns.election_threshold_pct,
		"national", int(_main._state.year), int(_main._state.month))]
	# main.gd's month end, as it shows a result.
	clock.paused = true
	_main._election_panel.show_results(results)
	_main._election_panel.show()
	_key(KEY_SPACE)
	if not clock.paused:
		_fail("Space ran the clock behind the election result")
	_main._hud.clock_cluster.pause_toggled.emit()
	if not clock.paused:
		_fail("the cluster's play ran the clock behind the election result")
	_main._hud.clock_cluster.speed_selected.emit(3)
	if not clock.paused:
		_fail("a speed click ran the clock behind the election result")
	_main._election_panel.dismissed.emit()
	_main._election_panel.hide()
	# A first term's Continue may hand the clock to the programme offer instead.
	if ns.in_government and clock.paused and not _main._decision_holds_clock() and not _main._paused_for_programme:
		_fail("Continue on a won election did not run the clock")


func _check_arming_clears_the_workspace() -> void:
	var ns = _main._state.player()
	var action = null
	for a in _main._loader.energy_actions:
		action = a
		break
	if action == null:
		_fail("no energy action to arm")
		return
	_main._windows.open("energy")
	_main._energy_panel.order_armed.emit(String(action.id))
	if not _main._windows.open_ids().is_empty():
		_fail("arming a placement left the workspace open: %s" % [_main._windows.open_ids()])
	if _main._armed_energy_action != String(action.id):
		_fail("putting the workspace away dropped the armed order")
	if _main._stack.top() != _main.ScreenStack.PLACEMENT:
		_fail("the armed placement is not the top layer (top %d)" % _main._stack.top())
	# With the tab gone, the map's legend is where the armed order says what it
	# waits for -- the panel's status line used to.
	var legend = _main._hud.map_legend
	var layer_caption: String = legend.MapLayers.caption(legend._layer)
	if legend._caption.text == layer_caption:
		_fail("an armed placement left the legend saying only the layer's caption")
	_main._cancel_placement()
	if legend._caption.text != layer_caption:
		_fail("cancelling the placement left the legend's placement hint up: %s" % legend._caption.text)


func _key(keycode: Key) -> void:
	var key := InputEventKey.new()
	key.keycode = keycode
	key.physical_keycode = keycode
	key.pressed = true
	_main._unhandled_input(key)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_clock_doors: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
