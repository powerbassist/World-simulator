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

const Pending = preload("res://src/ui/pending.gd")

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
	# `get()` rather than `_main._state`, because a main.gd that fails to PARSE
	# instantiates as a bare Control -- and reading a property off one raises a
	# script error that this suite went on to report as "all checks passed".
	# Found by breaking main.gd while writing V2.1c, which is also why
	# tools/run_tests.sh now fails the run on a SCRIPT ERROR.
	if _main.get("_state") == null:
		_fail("main scene did not build a GameState")
		return
	for name in ["_windows", "_hud", "_top_bar", "_map_view"]:
		if _main.get(name) == null:
			_fail("main scene did not build %s" % name)
	if _failures.size() > 0:
		return

	_check_no_blocking_holder_at_start()
	_check_the_pause_menu_still_opens_and_closes()
	_check_map_is_the_background()
	_check_hud_lets_the_map_through()
	_check_every_panel_registered_and_reachable()
	_check_panel_content()
	_check_action_bar_routes_to_windows()
	_check_keyboard_still_reaches_every_panel()
	_check_the_bar_marks_the_open_window()
	_check_the_bar_marks_what_awaits_the_player()
	_check_headline_figures_move_with_nothing_open()


## A modal's holder is a full-rect CenterContainer, and a Container defaults to
## MOUSE_FILTER_PASS -- solid enough to take every click on the screen while the
## panel inside it is invisible. This used to name the pause menu alone, which
## is why V2.9 could make the election panel blocking too and ship a game where
## nothing was clickable after the first frame: the panel was hidden, its holder
## was not, and the check only ever looked at the other one.
##
## So it is asked as the player asks it -- point at the screen, see what the
## click reaches -- rather than by naming holders. A modal nobody opened must
## never be the answer, whichever modal it is.
func _check_no_blocking_holder_at_start() -> void:
	if _main._pause_menu == null:
		_fail("main scene did not build a pause menu")
		return
	if _main._pause_menu.get_parent().visible:
		_fail("the pause menu holder is visible at start, blocking the whole screen")

	# Fractions of whatever the viewport is, not shipped pixel positions: a
	# headless run reports 1920x1920 where the window ships 1920x1080, so a
	# point picked to land on the bottom bar would not. The claim being made is
	# aspect-independent -- a holder that covers the screen covers all four --
	# and that is the whole of what this check asserts.
	var viewport: Viewport = _main.get_viewport()
	var size: Vector2 = viewport.get_visible_rect().size
	var reachable: Array = [_main._map_view, _main._windows, _main._hud, _main._top_bar]
	for fraction in [Vector2(0.5, 0.5), Vector2(0.2, 0.3), Vector2(0.8, 0.7), Vector2(0.5, 0.9)]:
		var point := Vector2(size.x * fraction.x, size.y * fraction.y)
		var motion := InputEventMouseMotion.new()
		motion.position = point
		motion.global_position = point
		viewport.push_input(motion, true)

		var hit: Control = viewport.gui_get_hovered_control()
		if hit == null:
			continue  # nothing solid there: the click falls through to the map
		var ok := false
		for surface in reachable:
			if surface != null and (hit == surface or surface.is_ancestor_of(hit)):
				ok = true
				break
		if not ok:
			_fail("a click at %s lands on %s (%s), which is neither the map, a window, nor the HUD"
				% [str(point), hit.name, hit.get_class()])


## The other direction of the same rule, and the reason `_set_pause_menu_visible()`
## may set the panel alone: a holder that never comes UP is a pause menu that
## cannot be opened, which a start-state check cannot tell apart from a holder
## that is correctly down. Asserted as a mutation -- open, look, close, look.
func _check_the_pause_menu_still_opens_and_closes() -> void:
	var holder: Control = _main._pause_menu.get_parent()
	_main._open_pause_menu()
	if not holder.visible:
		_fail("the pause menu holder stays hidden when the menu opens, so nothing blocks the map behind it")
	if not _main._pause_menu.visible:
		_fail("the pause menu panel stays hidden when the menu opens")

	_main._close_pause_menu()
	if holder.visible:
		_fail("the pause menu holder stays visible after closing, blocking the whole screen")
	if _main._pause_menu.visible:
		_fail("the pause menu panel stays visible after closing")


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


## The seven surfaces U2 shipped as tabs. Kept as a FLOOR rather than as the
## list -- V2.1a derives the real set from the registry, and this exists so a
## registry that silently loses a panel still turns something red.
const FOUNDING_PANELS: Array[String] = [
	"overview", "economy", "budget", "politics", "society", "legislature", "diplomacy",
]


## The rail's exclusivity rule, restated for windows: opening one closes the
## open unpinned one. test_window_frame.gd proves the manager does this on
## synthetic panels; this proves main.gd registered the real ones under it.
##
## V2.1a: iterates the REGISTRY rather than a hand-written list. The list this
## replaced held seven of fourteen, so bloc, calendar, people, companies,
## projects, campaign and dispatches -- every surface added since U5a -- were
## never checked for registration, reachability or exclusivity at all. A check
## that silently covers less than it appears to is `check_names.sh`'s U6b failure
## and `run_tests.sh`'s `test_companies.gd` failure in a third place.
func _check_every_panel_registered_and_reachable() -> void:
	var windows = _main._windows
	if not windows.open_ids().is_empty():
		_fail("the game opens with a panel already showing: %s" % str(windows.open_ids()))

	var registered: Array = windows.panel_ids()
	for id in FOUNDING_PANELS:
		if not registered.has(id):
			_fail("'%s' is no longer registered at all" % id)

	for id in registered:
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
	var pm_name: String = _main._loader.person_name(ns.pm_person_id)
	if not _collect_text(_main._government_panel).contains(pm_name):
		_fail("politics panel does not name the head of government '%s'" % pm_name)

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

	for id in _main._windows.panel_ids():
		# A window with NO KEY is a self-opening surface by definition -- it is
		# not navigated to, it happens (V2.4b's summit is the first: the scene
		# a meeting lands into, reachable by booking a visit and nothing else).
		# The drawer guarantee therefore binds exactly the keyed windows, which
		# keeps the rule structural instead of naming exceptions in a list --
		# the failure class V2.1a spent a whole block deleting.
		if _main._windows.shortcut(id) == KEY_NONE:
			continue
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


## U2's letters still work, every window has a route, and the map from key to
## window is the REGISTRY rather than a list here -- V2.1c.
##
## The list this replaced was six ids in a literal dictionary, matching a match
## block in main.gd that bound the same six. Eight of the fourteen windows had no
## key at all and this check could not say so, because a list cannot test itself:
## `EXPECTED_PANELS` at seven of fourteen in a seventh place, and one the
## `test_panel_kit.gd` scanner structurally could not see, since it looks for
## panel VARIABLE names in src/ui/ and tools/ and these were ids in tests/.
func _check_keyboard_still_reaches_every_panel() -> void:
	var windows = _main._windows

	# U2's six letters, which are the only ones a player already knows. Named
	# here as a FLOOR the way FOUNDING_PANELS is, not as the list of bindings.
	for pair in [[KEY_O, "overview"], [KEY_B, "budget"], [KEY_L, "legislature"]]:
		if windows.id_for_key(int(pair[0])) != String(pair[1]):
			_fail("key %s no longer opens '%s'" % [OS.get_keycode_string(int(pair[0])), pair[1]])

	var seen := {}
	for id in windows.panel_ids():
		var key: int = windows.shortcut(id)
		if key == KEY_NONE:
			continue
		if seen.has(key):
			_fail("key %s is bound to both '%s' and '%s'" % [
				OS.get_keycode_string(key), seen[key], id,
			])
		seen[key] = id

		_press(key)
		if not _main._windows.is_open(id):
			_fail("key %s did not open '%s'" % [OS.get_keycode_string(key), id])
		_press(key)
		if _main._windows.is_open(id):
			_fail("key %s did not close '%s' on a second press" % [OS.get_keycode_string(key), id])

	# Every window has a key now, and if one ever loses it the bar is still the
	# guarantee -- so this reports the count rather than demanding fourteen.
	var unbound: Array = []
	for id in windows.panel_ids():
		if windows.shortcut(id) == KEY_NONE:
			unbound.append(id)
	if not unbound.is_empty():
		print("test_shell: %d windows have no shortcut: %s" % [unbound.size(), str(unbound)])

	# M was the Europe tab. With the map always underneath, it clears the view.
	_press(KEY_B)
	_press(KEY_M)
	if not _main._windows.open_ids().is_empty():
		_fail("M left panels open: %s" % str(_main._windows.open_ids()))


## The bar marks the window that is open WHATEVER OPENED IT -- V2.1c. Three of the
## four routes (a keypress, a map marker, a message card) left the bar saying
## nothing, because `WindowManager.opened` had no consumer from U5a until now.
func _check_the_bar_marks_the_open_window() -> void:
	var bar = _main._hud.action_bar
	var windows = _main._windows
	windows.close_all()

	if bar._cluster_buttons["economy"].button_pressed:
		_fail("the Economy cluster is marked with nothing open")

	# By key, not by button: the route that had no mark at all.
	_press(KEY_B)
	if bar.cluster_of("budget") != "economy":
		_fail("the bar does not place 'budget' under the Economy cluster")
	if not bar._cluster_buttons["economy"].button_pressed:
		_fail("opening budget by keypress did not mark its cluster")

	# And by the message card's route, which is a plain open() on another cluster.
	windows.open("events")
	if not bar._cluster_buttons["state"].button_pressed:
		_fail("opening dispatches did not mark the State cluster")
	if bar._cluster_buttons["economy"].button_pressed:
		_fail("the Economy cluster stayed marked after another window opened")

	windows.close_all()
	if bar._cluster_buttons["state"].button_pressed:
		_fail("closing the last window left its cluster marked")


## What the resting screen says while nothing is open -- V2.1c.
##
## tools/nav_probe.gd measured fourteen years with nothing ever opened: of 74
## months in which a decision was in front of the player, the screen said nothing
## in 42 (a president who never touches a card) or 64 (one who reads a card and
## closes it). A council vote and an open campaign window were silent in 100 % of
## their months, having no card path at all.
##
## The response is a mark on the cluster where the answer is given, and this
## asserts the machinery both ways round -- an id that is pending marks its
## cluster, and nothing pending marks nothing. Whether a given month has anything
## pending is the simulation's business, not this test's.
func _check_the_bar_marks_what_awaits_the_player() -> void:
	var bar = _main._hud.action_bar

	bar.show_pending([])
	if not bar.pending_clusters().is_empty():
		_fail("the bar reports a pending cluster with nothing pending")

	bar.show_pending(["events", "orgs"])
	var marked: Array = bar.pending_clusters()
	if not marked.has("state") or not marked.has("world"):
		_fail("a pending dispatch and a pending council vote did not mark State and World: %s"
			% str(marked))
	if marked.has("economy"):
		_fail("a cluster with nothing pending was marked: %s" % str(marked))

	# And the reader itself: with nothing pending in the simulation it must return
	# an empty list rather than everything or nothing-shaped garbage.
	var ids: Array = Pending.window_ids(_main._state, _main._loader)
	for id in ids:
		if _main._windows.frame(String(id)) == null:
			_fail("pending.gd named '%s', which is not a registered window" % id)

	bar.show_pending(Pending.window_ids(_main._state, _main._loader))


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
