extends SceneTree

## V4.9b. Election night (src/ui/election_night.gd + the election panel's
## count): the regions declare smallest first, the running figures end on
## exactly the result's own, the verdict is held back until the count is in,
## and every way out -- a click, the footer button, a rebuild, wall-clock time,
## motion off -- lands somewhere honest. Motion is forced on (override = 1) for
## the sequence; headless it is off, which is its own check at the end.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Elections = preload("res://src/sim/elections.gd")
const Motion = preload("res://src/ui/motion.gd")
const ElectionNight = preload("res://src/ui/election_night.gd")
const ElectionPanel = preload("res://src/ui/election_panel.gd")

var _failures: Array[String] = []
var _loader
var _state
var _results: Array = []
var _panel
var _frame := 0
var _started := 0
var _seconds := 0.0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load: %s" % [_loader.errors])
		return
	_state = GameState.new_game(_loader, "FRA")
	var ns = _state.player()
	var party_list: Array = _loader.parties.get(ns.id, [])
	_results = [Elections.resolve(ns, party_list, ns.election_system, ns.election_threshold_pct, "national", 2029, 6)]
	_check_count_model()


func _process(_delta: float) -> bool:
	_frame += 1
	if not _failures.is_empty() and _frame == 1:
		_report()
		return true
	match _frame:
		1:
			Motion.override = 1
			_panel = ElectionPanel.new()
			root.add_child(_panel)
			_panel.setup(_state, _loader)
			_check_night_holds_the_verdict()
			_check_skip_lands_on_the_result()
			_check_dismiss_retires_the_count()
			_check_rebuild_retires_the_count()
			_started = Time.get_ticks_msec()
			_seconds = minf(float(_panel._night.size()) * Motion.DECLARE_S, Motion.NIGHT_MAX_S)
			return false
		_:
			if Time.get_ticks_msec() - _started < int(_seconds * 1000.0) + 300:
				# One frame of slack on the early side: the frame the count was
				# built in is stepped with that frame's own delta (capped at
				# Motion.MAX_STEP_S), time the clock here had not started on.
				if _panel._revealed and Time.get_ticks_msec() - _started < int(_seconds * 1000.0) - 100:
					_fail("the count revealed its verdict %d ms in, before its %.2f s ran" % [
						Time.get_ticks_msec() - _started, _seconds])
					_finish()
					return true
				return false
			# Wall-clock, not frames: the night settles on its own time.
			if not _panel._revealed:
				_fail("the count had not revealed its verdict %.2f s after it started" % (_seconds + 0.3))
			_check_figures_final("after the count ran out on its own")
			_check_motion_off()
			_finish()
			return true


## The pure half: declaration order, the count's weight, and that the end of
## the count IS the result.
func _check_count_model() -> void:
	var night = ElectionNight.new(_state, _results)
	var n: int = night.size()
	if n != _state.regions.get("FRA", []).size():
		_fail("the night counts %d regions, France has %d" % [n, _state.regions.get("FRA", []).size()])
		return
	for i in range(1, n):
		if float(night.order[i]["weight"]) < float(night.order[i - 1]["weight"]):
			_fail("region %s declares before a smaller one" % night.order[i - 1]["id"])
	if not is_same(night.shares_at(0, float(n)), _results[0]["vote_share"]):
		_fail("the finished count is not the result's own vote shares")
	if night.counted_weight(float(n)) != 1.0 or night.counted_weight(0.0) != 0.0:
		_fail("the count's weight runs %.6f to %.6f, not 0 to 1" % [night.counted_weight(0.0), night.counted_weight(float(n))])
	var last := -1.0
	for step in range(0, n * 4 + 1):
		var w: float = night.counted_weight(float(step) / 4.0)
		if w < last:
			_fail("the counted weight fell at %.2f regions" % (float(step) / 4.0))
			break
		last = w
	if night.latest(0.0) != "" or night.latest(1.0) != String(night.order[0]["name"]):
		_fail("latest() names '%s' at the first declaration, expected '%s'" % [night.latest(1.0), night.order[0]["name"]])
	# The lead moves: halfway through, the incumbent's running share is not
	# yet the national one.
	var incumbent := String(_results[0]["incumbent_party_id"])
	var half: Dictionary = night.shares_at(0, float(n) / 2.0)
	if absf(float(half[incumbent]) - float(_results[0]["vote_share"][incumbent])) < 0.0005:
		_fail("halfway through the count the incumbent already reads the national share -- nothing moves")


func _check_night_holds_the_verdict() -> void:
	_panel.show_results(_results)
	if _panel._title.text != ElectionPanel.NIGHT_TITLE:
		_fail("the count opened titled '%s', not '%s' -- the verdict came first" % [_panel._title.text, ElectionPanel.NIGHT_TITLE])
	for node in _panel._verdict_nodes:
		if node.visible:
			_fail("a verdict line is shown before the count")
			break
	for cell in _panel._cells:
		if cell["share"].text != "0.0%":
			_fail("before any region declares, %s reads '%s'" % [cell["party"], cell["share"].text])
			break
		if cell["bar"] != null and float(cell["bar"].value) > 0.0:
			_fail("a seat bar starts the count at %.2f" % cell["bar"].value)
			break
	# Half the count: real intermediate figures, the ticker naming the latest.
	var tween: Tween = _panel.get_meta(&"motion_tween")
	var seconds := minf(float(_panel._night.size()) * Motion.DECLARE_S, Motion.NIGHT_MAX_S)
	tween.custom_step(seconds * 0.5)
	if not _panel._ticker.text.contains(" of %d regions declared" % _panel._night.size()):
		_fail("mid-count the ticker reads '%s'" % _panel._ticker.text)
	if _panel._title.text != ElectionPanel.NIGHT_TITLE or _panel._revealed:
		_fail("the verdict was revealed halfway through the count")
	var moved := false
	for cell in _panel._cells:
		var final_text := "%.1f%%" % (float(_results[0]["vote_share"][cell["party"]]) * 100.0)
		if cell["share"].text != final_text and cell["share"].text != "0.0%":
			moved = true
	if not moved:
		_fail("halfway through the count every figure reads empty or final")


func _check_skip_lands_on_the_result() -> void:
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	_panel._gui_input(ev)
	_check_figures_final("after a click on the plate")
	for node in _panel._verdict_nodes:
		if not node.visible or node.modulate.a < 0.99:
			_fail("after a skip a verdict line is hidden or fading (visible %s, alpha %.2f)" % [node.visible, node.modulate.a])
			break


## Every figure is the result's own: the title the verdict, shares printed from
## the result, seats its seats, bars full, the ticker done.
func _check_figures_final(when: String) -> void:
	if _panel._title.text == ElectionPanel.NIGHT_TITLE:
		_fail("%s the plate is still titled '%s'" % [when, ElectionPanel.NIGHT_TITLE])
	var result: Dictionary = _results[0]
	for cell in _panel._cells:
		var final_text := "%.1f%%" % (float(result["vote_share"][cell["party"]]) * 100.0)
		if cell["share"].text != final_text:
			_fail("%s %s reads '%s', the result says '%s'" % [when, cell["party"], cell["share"].text, final_text])
			return
		if cell["seats"] != null and cell["seats"].text != str(result["seats"][cell["party"]]):
			_fail("%s %s holds '%s' seats, the result says %d" % [when, cell["party"], cell["seats"].text, result["seats"][cell["party"]]])
			return
		if cell["bar"] != null and absf(float(cell["bar"].value) - float(cell["final_bar"])) > 0.005:
			_fail("%s a seat bar reads %.4f against %.4f" % [when, cell["bar"].value, cell["final_bar"]])
			return
	if not _panel._ticker.text.begins_with("All "):
		_fail("%s the ticker reads '%s'" % [when, _panel._ticker.text])


## Continue mid-count dismisses, and the count it leaves behind never reveals
## (or sounds) a verdict behind the closed plate.
func _check_dismiss_retires_the_count() -> void:
	_panel.show()
	_panel.show_results(_results)
	var button: Button = _panel._footer.get_child(_panel._footer.get_child_count() - 1)
	button.pressed.emit()
	if _panel.visible:
		_fail("Continue mid-count did not dismiss the plate")
	Motion.finish(_panel)
	if _panel._revealed:
		_fail("a count dismissed mid-way revealed its verdict afterwards")
	_panel.show()


## A rebuild mid-count (two results in a row) starts a fresh count; the old one
## steps into nothing. Left running: the wall-clock check reads this count.
func _check_rebuild_retires_the_count() -> void:
	_panel.show_results(_results)
	_panel.show_results(_results)
	if _panel._revealed or _panel._title.text != ElectionPanel.NIGHT_TITLE:
		_fail("rebuilding mid-count revealed a verdict (the old count's last step ran into the new plate)")


func _check_motion_off() -> void:
	Motion.override = 0
	_panel.show_results(_results)
	if not _panel._revealed:
		_fail("with motion off the plate opened unrevealed")
	_check_figures_final("with motion off")
	Motion.override = -1


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	Motion.override = -1
	_report()


func _report() -> void:
	if _failures.is_empty():
		print("test_election_night: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
