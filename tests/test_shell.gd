extends SceneTree

## Headless test: godot --headless --script res://tests/test_shell.gd
## Non-zero exit on any failure.
##
## U2's test_dashboard.gd, rewritten for U5a's shell. The intent is unchanged
## and is the reason this file kept the old one's checks rather than starting
## over: **every surface the player needs is reachable, and the always-visible
## figures move on their own.** Only the mechanism changed -- a tab rail became
## a bottom bar and a set of floating windows.
##
## What is new here is the thing the rail made impossible and so never needed
## testing: the map is now permanently underneath everything, and a HUD that
## swallows input would leave the player unable to click a country. That is
## checked directly, because it fails silently -- the map simply stops
## responding and nothing errors.
##
## Driven a frame at a time because a Control outside the scene tree has not run
## _ready() -- see docs/engine-decision.md.

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
	for name in ["_windows", "_hud", "_top_bar", "_map_view"]:
		if _main.get(name) == null:
			_fail("main scene did not build %s" % name)
	if _failures.size() > 0:
		return

	_check_no_blocking_holder_at_start()
	_check_map_is_the_background()
	_check_hud_lets_the_map_through()
	_check_every_panel_registered_and_reachable()
	_check_panel_content()
	_check_action_bar_routes_to_windows()
	_check_keyboard_still_reaches_every_panel()
	_check_headline_figures_move_with_nothing_open()


## The pause menu's holder is the one full-rect blocking CenterContainer -- if
## it is visible before the player ever opens it, every click on the bottom bar
## and every drag on the map is swallowed.
func _check_no_blocking_holder_at_start() -> void:
	if _main._pause_menu == null:
		_fail("main scene did not build a pause menu")
		return
	if _main._pause_menu.get_parent().visible:
		_fail("the pause menu holder is visible at start, blocking the whole screen")


## U5a's structural claim in one assertion: the map is not in a tab, it is the
## thing everything else is drawn on.
func _check_map_is_the_background() -> void:
	if _main._map_view.get_parent() != _main:
		_fail("the map is not a direct child of the game scene, so it is not the background")
		return

	var map_index: int = _main._map_view.get_index()
	for other in [_main._windows, _main._hud]:
		if other.get_index() < map_index:
			_fail("%s draws behind the map" % other)

	# Windows under the furniture: a panel dragged to the bottom of the screen
	# must not cover the clock or the portrait.
	if _main._windows.get_index() > _main._hud.get_index():
		_fail("floating windows draw over the HUD furniture")


## Fails silently in the real game -- the map just stops responding -- so it is
## asserted rather than looked at. The structural boxes that arrange the
## furniture cover the whole screen; only the plates themselves may be solid.
func _check_hud_lets_the_map_through() -> void:
	var hud = _main._hud
	if hud.mouse_filter != Control.MOUSE_FILTER_IGNORE:
		_fail("the HUD root stops mouse input, so the map can never be clicked")

	var solid := _collect_solid_containers(hud, "")
	if not solid.is_empty():
		_fail("HUD layout containers that swallow map input: %s" % ", ".join(solid))

	# The other half of the same rule: the furniture must be solid where it is
	# actually drawn, or a click on the portrait card pans Europe.
	var portrait = hud.portrait_card
	if portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		_fail("the portrait card passes clicks through to the map underneath")
	if not hud.is_over_furniture(portrait.global_position + portrait.size / 2.0):
		_fail("is_over_furniture() does not report the centre of the portrait card")
	# A point in the middle of the screen is map, not furniture.
	if hud.is_over_furniture(hud.size / 2.0):
		_fail("is_over_furniture() reports the middle of the map as furniture")

	# U5c's plate, sitting directly above the portrait card. A new piece of
	# furniture that nobody adds to is_over_furniture()'s list is a drag on the
	# legend that pans the map underneath it -- the failure this whole check
	# exists for, one plate later.
	var legend = hud.map_legend
	if legend == null:
		_fail("the HUD did not build the map legend")
	elif not hud.is_over_furniture(legend.global_position + legend.size / 2.0):
		_fail("is_over_furniture() does not report the centre of the map legend")


## Every Container under the HUD is layout, and layout must never be solid. The
## leaves -- the plates -- are PanelContainers, which is how they are told apart.
func _collect_solid_containers(node: Node, path: String) -> Array:
	var out: Array = []
	for child in node.get_children():
		if not child is Control:
			continue
		var child_path := "%s/%s" % [path, child.get_class()]
		if child is Container and not child is PanelContainer:
			if child.mouse_filter == Control.MOUSE_FILTER_STOP:
				out.append(child_path)
			out.append_array(_collect_solid_containers(child, child_path))
	return out


const EXPECTED_PANELS: Array[String] = [
	"overview", "economy", "budget", "politics", "society", "legislature", "diplomacy",
]


## The rail's exclusivity rule, restated for windows: opening one closes the
## open unpinned one. test_window_frame.gd proves the manager does this on
## synthetic panels; this proves main.gd registered the real ones under it.
func _check_every_panel_registered_and_reachable() -> void:
	var windows = _main._windows
	if not windows.open_ids().is_empty():
		_fail("the game opens with a panel already showing: %s" % str(windows.open_ids()))

	for id in EXPECTED_PANELS:
		if windows.frame(id) == null:
			_fail("no '%s' panel is registered" % id)
			continue
		windows.open(id)
		if not windows.is_open(id):
			_fail("opening '%s' did not show it" % id)
		if windows.open_ids().size() != 1:
			_fail("opening '%s' left %d panels open, expected 1" % [id, windows.open_ids().size()])

	windows.close_all()


## Every panel that used to be a tab still shows the figures the player relied
## on that tab for. Carried over from test_dashboard.gd unchanged, because what
## it checks is the panels' content and that is what U5a did not touch.
func _check_panel_content() -> void:
	var windows = _main._windows
	var ns = _main._state.player()

	windows.open("overview")
	_main._overview_panel._process(0.0)
	var overview_text := _collect_text(_main._overview_panel)
	for heading in ["OVERVIEW", "GOVERNMENT", "NEXT ELECTION", "WHAT THE COUNTRY WANTS", "MOVING"]:
		if not overview_text.contains(heading):
			_fail("overview panel has no '%s' section: %s" % [heading, overview_text])

	windows.open("economy")
	_main._economy_panel._process(0.0)
	var economy_text := _collect_text(_main._economy_panel)
	for heading in ["ECONOMY", "LABOUR", "PUBLIC FINANCES", "OUTPUT BY SECTOR"]:
		if not economy_text.contains(heading):
			_fail("economy panel has no '%s' section: %s" % [heading, economy_text])

	windows.open("budget")
	_main._budget_panel._process(0.0)
	if not _collect_text(_main._budget_panel).contains("BUDGET"):
		_fail("budget panel does not render its heading")
	# The frame provides the close button now; the panel's own stays hidden.
	if _main._budget_panel._close_button.visible:
		_fail("budget panel shows its own Close button beside the frame's")

	windows.open("politics")
	_main._government_panel._process(0.0)
	if not _collect_text(_main._government_panel).contains(ns.pm_name):
		_fail("politics panel does not name the head of government '%s'" % ns.pm_name)

	windows.open("society")
	_main._polling_panel._process(0.0)
	if not _collect_text(_main._polling_panel).contains("Approval"):
		_fail("society panel does not render approval")

	windows.open("legislature")
	_main._law_panel._process(0.0)
	if not _collect_text(_main._law_panel).contains("LEGISLATURE"):
		_fail("legislature panel does not render its heading")

	windows.close_all()


## The bottom bar is the rail's replacement, so the thing the rail guaranteed --
## every panel has a way in that does not require knowing a keyboard shortcut --
## has to hold. Every registered panel must be named by exactly one cluster.
func _check_action_bar_routes_to_windows() -> void:
	var bar = _main._hud.action_bar
	var listed: Array = []
	for cluster_id in bar._entries.keys():
		for entry in bar._entries[cluster_id]:
			listed.append(str(entry["id"]))

	for id in EXPECTED_PANELS:
		if not listed.has(id):
			_fail("no cluster on the bottom bar opens '%s'" % id)
	for id in listed:
		if _main._windows.frame(id) == null:
			_fail("the bottom bar offers '%s', which is not a registered panel" % id)

	# And the routing itself is connected, not merely listed.
	bar.panel_requested.emit("budget")
	if not _main._windows.is_open("budget"):
		_fail("the bottom bar's panel_requested is not wired to the window manager")
	_main._windows.close_all()


## U2's seven letters still work, and now toggle rather than select -- with no
## rail there is nothing showing which panel is current, so pressing the same
## key twice must put the player back on the map.
func _check_keyboard_still_reaches_every_panel() -> void:
	var bindings := {
		KEY_O: "overview", KEY_E: "economy", KEY_B: "budget",
		KEY_G: "politics", KEY_P: "society", KEY_L: "legislature",
	}
	for key in bindings.keys():
		_press(key)
		if not _main._windows.is_open(bindings[key]):
			_fail("key %s did not open '%s'" % [OS.get_keycode_string(key), bindings[key]])
		_press(key)
		if _main._windows.is_open(bindings[key]):
			_fail("key %s did not close '%s' on a second press" % [OS.get_keycode_string(key), bindings[key]])

	# M was the Europe tab. With the map always underneath, it clears the view.
	_press(KEY_B)
	_press(KEY_M)
	if not _main._windows.open_ids().is_empty():
		_fail("M left panels open: %s" % str(_main._windows.open_ids()))


func _press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_main._unhandled_input(event)


## The done-when line U2's own test satisfied by accident, extended: the top
## strip *and* the portrait card must both move on a monthly tick with nothing
## open. The portrait is new and carries approval, which used to be on the strip
## -- if it were refreshed only when a panel opened, the player's own standing
## would be the one stale number on screen.
func _check_headline_figures_move_with_nothing_open() -> void:
	_main._windows.close_all()

	var clock: Node = _main.get_node("Clock")
	var strip_before := _collect_text(_main._top_bar)
	var portrait_before := _collect_text(_main._hud.portrait_card)
	var clock_before := _collect_text(_main._hud.clock_cluster)

	for _d in range(31 * 3):
		clock.advance_one_day()

	if _collect_text(_main._top_bar) == strip_before:
		_fail("top strip figures did not change after three simulated months")
	if _collect_text(_main._hud.portrait_card) == portrait_before:
		_fail("the portrait card's approval did not change after three simulated months")
	if _collect_text(_main._hud.clock_cluster) == clock_before:
		_fail("the clock cluster's date did not change after three simulated months")


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
		print("test_shell: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
