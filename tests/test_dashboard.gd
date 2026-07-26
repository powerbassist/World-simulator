extends SceneTree

## Headless test: godot --headless --script res://tests/test_dashboard.gd
## Non-zero exit on any failure.
##
## U2's shell test. Loads the actual main scene, same shape test_law_panel.gd
## and test_map_view.gd use, driven a frame at a time because a Control outside
## the scene tree has not run _ready() -- see docs/engine-decision.md.
##
## Checks the done-when list in ROADMAP.md's U2 section: every former keypress
## panel opens as a tab showing its figures, exactly one tab is visible at a
## time, the top bar updates with nothing open, and nothing blocks input at
## start.

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
	if _main._dashboard == null:
		_fail("main scene did not build a dashboard")
		return
	if _main._top_bar == null:
		_fail("main scene did not build a top bar")
		return

	_check_no_blocking_holder_at_start()
	_check_tabs_registered_and_exclusive()
	_check_tab_content()
	_check_top_bar_updates_with_nothing_open()


## The pause menu's holder is the one full-rect blocking CenterContainer -- if
## it is visible before the player ever opens it, every click on the rail and
## every tab underneath is swallowed.
func _check_no_blocking_holder_at_start() -> void:
	if _main._pause_menu == null:
		_fail("main scene did not build a pause menu")
		return
	if _main._pause_menu.get_parent().visible:
		_fail("the pause menu holder is visible at start, blocking the whole dashboard")


const EXPECTED_TABS: Array[String] = [
	"overview", "economy", "budget", "politics", "society", "legislature", "europe",
]


func _check_tabs_registered_and_exclusive() -> void:
	var dash = _main._dashboard
	for id in EXPECTED_TABS:
		if not dash._panels.has(id):
			_fail("dashboard has no '%s' tab registered" % id)
			continue

		dash.select_tab(id)
		var visible_count := 0
		for other_id in dash._panels.keys():
			if dash._panels[other_id].visible:
				visible_count += 1
		if visible_count != 1:
			_fail("selecting '%s' left %d dock children visible, expected 1" % [id, visible_count])
		if not dash._panels[id].visible:
			_fail("selecting '%s' did not make its own panel visible" % id)


## Every panel that used to open with a keypress now opens as a tab and shows
## the figure a player relied on that keypress for.
func _check_tab_content() -> void:
	var dash = _main._dashboard
	var ns = _main._state.player()

	# Section headings rather than a single figure, since U3: what these two tabs
	# have to keep is the hierarchy, and a regression to a flat list of every
	# field would still contain any one figure the check named.
	dash.select_tab("overview")
	dash._panels["overview"]._process(0.0)
	var overview_text := _collect_text(dash._panels["overview"])
	for heading in ["OVERVIEW", "GOVERNMENT", "NEXT ELECTION", "WHAT THE COUNTRY WANTS", "MOVING"]:
		if not overview_text.contains(heading):
			_fail("overview tab has no '%s' section: %s" % [heading, overview_text])

	dash.select_tab("economy")
	dash._panels["economy"]._process(0.0)
	var economy_text := _collect_text(dash._panels["economy"])
	for heading in ["ECONOMY", "LABOUR", "PUBLIC FINANCES", "OUTPUT BY SECTOR"]:
		if not economy_text.contains(heading):
			_fail("economy tab has no '%s' section: %s" % [heading, economy_text])

	dash.select_tab("budget")
	dash._panels["budget"]._process(0.0)
	var budget_text := _collect_text(dash._panels["budget"])
	if not budget_text.contains("BUDGET"):
		_fail("budget tab does not render its heading: %s" % budget_text)
	if _main._budget_panel._close_button.visible:
		_fail("budget tab's Close button is still visible while docked")

	dash.select_tab("politics")
	dash._panels["politics"]._process(0.0)
	var politics_text := _collect_text(dash._panels["politics"])
	if not politics_text.contains(ns.pm_name):
		_fail("politics tab does not name the head of government '%s': %s" % [ns.pm_name, politics_text])

	dash.select_tab("society")
	dash._panels["society"]._process(0.0)
	var society_text := _collect_text(dash._panels["society"])
	if not society_text.contains("Approval"):
		_fail("society tab does not render approval: %s" % society_text)
	if _main._polling_panel._close_button.visible:
		_fail("society tab's Close button is still visible while docked")

	dash.select_tab("legislature")
	dash._panels["legislature"]._process(0.0)
	var legislature_text := _collect_text(dash._panels["legislature"])
	if not legislature_text.contains("LEGISLATURE"):
		_fail("legislature tab does not render its heading: %s" % legislature_text)
	if _main._law_panel._close_button.visible:
		_fail("legislature tab's Close button is still visible while docked")

	dash.select_tab("europe")
	if _main._map_view == null:
		_fail("europe tab has no map view")
	elif _main._map_view.get_parent() != dash._panels["europe"]:
		_fail("map view is not hosted inside the europe tab")
	if _main._nation_panel == null:
		_fail("europe tab has no nation detail pane")
	elif _main._nation_panel.get_parent() != dash._panels["europe"]:
		_fail("nation panel is not hosted inside the europe tab")


## The done-when line the old HUD satisfied by accident: the headline figures
## must move on a monthly tick with no panel opened at all.
func _check_top_bar_updates_with_nothing_open() -> void:
	var dash = _main._dashboard
	dash.select_tab("overview")  # a tab has to be open; the top bar must not

	var clock: Node = _main.get_node("Clock")
	var before := _collect_text(_main._top_bar)

	for _d in range(31 * 3):
		clock.advance_one_day()

	var after := _collect_text(_main._top_bar)
	if before == after:
		_fail("top bar text did not change after three simulated months")


func _collect_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_dashboard: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
