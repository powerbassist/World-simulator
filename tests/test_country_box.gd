extends SceneTree

## Headless test: godot --headless --script res://tests/test_country_box.gd
## Non-zero exit on any failure.
##
## V5.1-d4, G2 of the play gate. A left click on a nation opens a small box with its
## figures (and, abroad, the relationship); a right click opens the verbs the
## Diplomacy file offers, each one a press; another nation's approval is a range with
## its source, never the true figure (the author's "Une fourchette + source"), in the
## box and in the file alike.

const CountryBox = preload("res://src/ui/country_box.gd")
const ForeignReading = preload("res://src/ui/foreign_reading.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _box


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 3:
		_main._clock.set_process(false)
		for child in _main._stack.get_children():
			if child.get_script() == CountryBox:
				_box = child
		if _box == null:
			_fail("main built no country box on the screen stack")
			_finish()
			return true
		if _main._stack.get_child(_main._stack.get_child_count() - 1) != _main._stack.tips:
			_fail("the country box pushed the tooltip chain off the stack's last child")
		_check_the_fog()
		_check_the_box()
		_check_the_file_reads_the_fog()
	elif _frame == 5:
		_check_the_verbs()
	elif _frame == 7:
		_finish()
		return true
	return false


## Another nation's approval: a range holding the truth, from an embassy where the
## player has one and the press where not, narrower with the embassy; the player's
## own is their poll.
func _check_the_fog() -> void:
	var state = _main._state
	var with_embassy := ""
	var without := ""
	for id in state.nations.keys():
		if String(id) == state.player_nation_id:
			continue
		if ForeignReading.has_embassy(state, String(id)):
			with_embassy = String(id) if with_embassy == "" else with_embassy
		else:
			without = String(id) if without == "" else without
	# France holds an embassy in every capital at the start: one is staged away.
	var staged := ""
	if without == "" and with_embassy != "":
		for id in state.player().embassies:
			if String(id) != with_embassy:
				staged = String(id)
				break
		state.player().embassies.erase(staged)
		without = staged
	if with_embassy == "" or without == "":
		_fail("premise: a nation with the player's embassy and one without (%s / %s)" % [with_embassy, without])
		return
	for id in [with_embassy, without]:
		var span: Array = ForeignReading.approval_range(state, id)
		var truth: float = float(state.nations[id].overall_approval_pct)
		if span.size() != 2 or float(span[0]) > truth + 0.5 or float(span[1]) < truth - 0.5 or span[1] <= span[0]:
			_fail("%s's approval range %s does not hold the truth %.1f" % [id, str(span), truth])
	var narrow: Array = ForeignReading.approval_range(state, with_embassy)
	var wide: Array = ForeignReading.approval_range(state, without)
	if int(narrow[1]) - int(narrow[0]) >= int(wide[1]) - int(wide[0]):
		_fail("an embassy's estimate is no narrower than the press's: %s vs %s" % [str(narrow), str(wide)])
	if not ForeignReading.approval_text(state, with_embassy).contains("embassy"):
		_fail("an embassy's estimate does not say so: %s" % ForeignReading.approval_text(state, with_embassy))
	if not ForeignReading.approval_text(state, without).contains("press"):
		_fail("the press's estimate does not say so: %s" % ForeignReading.approval_text(state, without))
	if not ForeignReading.approval_text(state, state.player_nation_id).contains("a poll"):
		_fail("the player's own approval is not their poll")
	if staged != "":
		state.player().embassies.append(staged)


## The map's own left click opens the box: the figures and, abroad, the relationship.
func _check_the_box() -> void:
	_main._map_view.nation_clicked.emit("DEU")
	if not _box.visible or _box.mode != "box" or _box.nation_id != "DEU":
		_fail("a left click on Germany did not open its box (%s, %s, %s)" % [_box.visible, _box.mode, _box.nation_id])
	var text := _text_of(_box)
	if not text.contains("Relations with France") or not text.contains(ForeignReading.approval_text(_main._state, "DEU")):
		_fail("Germany's box lacks the relationship or the approval range: %s" % text)
	if _main._windows.is_open("diplomacy"):
		_fail("a left click still opened the Diplomacy file instead of the box")
	# The box holds no rank on the stack: it is not a tab, and a rank would slide
	# the inbox over it while the term's programme holds the clock.
	if _main._stack.top() != ScreenStack.MAP:
		_fail("the country box raised the screen stack's top to %d" % _main._stack.top())
	# Escape puts it away.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	_box._input(escape)
	if _box.visible:
		_fail("Escape did not put the country box away")
	# The player's own: no relationship with itself.
	_main._map_view.nation_clicked.emit(_main._state.player_nation_id)
	if _text_of(_box).contains("Relations with"):
		_fail("the player's own box reports a relationship with itself")
	_box.hide()
	# Under a scene the map's clicks reach nothing, as for the file.
	_main._stack.hold(ScreenStack.SCENE, func(): pass)
	_main._map_view.nation_clicked.emit("DEU")
	if _box.visible:
		_fail("the country box opened under a scene")
	_main._stack.release(ScreenStack.SCENE)
	# Its file button opens the file.
	_main._map_view.nation_clicked.emit("DEU")
	for b in _box.find_children("*", "Button", true, false):
		if (b as Button).text == "Open the file":
			(b as Button).pressed.emit()
	if not _main._windows.is_open("diplomacy") or _box.visible:
		_fail("the box's file button did not open the Diplomacy file")
	_main._windows.close_all()


## The file prints the same range: it used to print the true figure.
func _check_the_file_reads_the_fog() -> void:
	_main._on_nation_clicked("DEU")
	_main._nation_panel.mark_dirty()
	_main._nation_panel._process(0.0)
	var text := _text_of(_main._nation_panel)
	var truth := "Approval: %.0f%%" % float(_main._state.nations["DEU"].overall_approval_pct)
	if text.contains(truth + "\n") or not text.contains(ForeignReading.approval_text(_main._state, "DEU")):
		_fail("the Diplomacy file does not print Germany's approval as the range: %s" % text)
	_main._windows.close_all()


## The right click: the file's verbs, each a press down the row's path.
func _check_the_verbs() -> void:
	_box.show_verbs("DEU")
	if not _box.visible or _box.mode != "verbs":
		_fail("the verb menu did not open")
		return
	var expected: Array = []
	for action in _main._nation_panel.offered_actions():
		expected.append(Strings.row_name("diplomatic-actions", action))
	var shown: Array = []
	var visit: Button = null
	for b in _box.find_children("*", "Button", true, false):
		if b.is_queued_for_deletion() or (b as Button).text == "Open the file":
			continue
		shown.append((b as Button).text)
		if (b as Button).text == "State Visit":
			visit = b
	if shown != expected or expected.is_empty():
		_fail("the verb menu shows %s, the file offers %s" % [str(shown), str(expected)])
	if visit == null:
		_fail("the verb menu has no State Visit for Germany")
		return
	visit.pressed.emit()
	if _box.visible or not _main._windows.is_open("calendar"):
		_fail("State Visit from the menu did not open the Diary's form, as the file's Book does")
	_main._windows.close_all()


func _text_of(node: Node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		if not child.is_queued_for_deletion():
			out += _text_of(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_country_box: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
