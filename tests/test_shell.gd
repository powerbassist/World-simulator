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
const Budget = preload("res://src/sim/budget.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _phase := "run"
var _shut_frames := 0
var _slicing_frames := 0

## Real frames the engine runs over the month's sweep before the closed-window
## read: every panel's own _process has had its turns by then.
const SHUT_FRAMES := 3
## The sliced month's frames before the check gives up on it.
const SLICING_FRAMES_MAX := 3000


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	if _phase == "run":
		_run()
		if not _failures.is_empty() or not _begin_a_month_with_every_window_shut():
			_finish()
			return false
		_phase = "slicing"
		return false
	if _phase == "slicing":
		# The month runs across these frames, a unit budget at a time, with the
		# windows disabled; it ends with them re-enabled and the month's sweep.
		_slicing_frames += 1
		if _main._month_runner.running():
			if _slicing_frames > SLICING_FRAMES_MAX:
				_fail("the real-time month was still closing after %d frames" % SLICING_FRAMES_MAX)
				_finish()
			return false
		_phase = "shut"
		return false
	_shut_frames += 1
	if _shut_frames < SHUT_FRAMES:
		return false
	_check_the_month_left_every_closed_panel_dirty()
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
	_check_the_map_is_reachable_beside_a_domain()
	_check_breadcrumb_follows_the_tab()
	_check_title_bar_walks_the_history()
	_check_chrome_is_inert_under_a_scene()
	_check_no_dev_preload()
	_check_every_panel_registered_and_reachable()
	_check_panel_content()
	_check_sidebar_routes_to_every_domain()
	_check_keyboard_still_reaches_every_panel()
	_check_sidebar_marks_the_open_domain()
	_check_sidebar_marks_what_awaits()
	_check_headline_figures_move_with_nothing_open()
	_check_save_dialog_traps_hotkeys()
	_check_term_card_refresh()
	_check_a_closed_window_costs_nothing()
	_check_a_tax_commit_reaches_the_budget_forecast()
	_check_any_command_reaches_the_budget_forecast()


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


## V5.1-c2.2. The workspace docks left and leaves the map uncovered to its right
## -- the strip the inbox slides over. Asked as the player asks it: point there
## with a domain open and see what the pointer reaches. A dock that grew across
## the screen, or a holder behind it that eats clicks, fails silently.
func _check_the_map_is_reachable_beside_a_domain() -> void:
	_main._windows.open("budget")
	var viewport: Viewport = _main.get_viewport()
	var size: Vector2 = viewport.get_visible_rect().size
	var point := Vector2(size.x * 0.9, size.y * 0.5)
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	viewport.push_input(motion, true)
	var hit: Control = viewport.gui_get_hovered_control()
	if hit != null and hit != _main._map_view and not _main._map_view.is_ancestor_of(hit):
		_fail("with a domain open, a click at %s lands on %s (%s), not the map" % [str(point), hit.name, hit.get_class()])
	if _main._windows.dock().get_global_rect().has_point(point):
		_fail("the dock covers %s, the map's strip beside it" % str(point))
	_main._windows.close_all()


## V5.1-c2.3. Where the player is, said in the title bar: the nation, the domain
## and the tab, or the nation and the map.
func _check_breadcrumb_follows_the_tab() -> void:
	var bar = _main._hud.title_bar
	_main._windows.open("tax")
	var crumb: String = bar.crumb()
	for part in [_main._loader.nations[_main._state.player_nation_id].nation_name, _main.tr("Finances"), _main._windows.title("tax")]:
		if not crumb.contains(part):
			_fail("with the tax tab open the breadcrumb reads '%s', missing '%s'" % [crumb, part])
	_main._windows.close_all()
	crumb = bar.crumb()
	if not crumb.ends_with(_main.tr("Map")) or crumb.contains(_main.tr("Finances")):
		_fail("back on the map the breadcrumb still reads '%s'" % crumb)


## Back and forward are the title bar's, and they walk the window manager's path.
func _check_title_bar_walks_the_history() -> void:
	var bar = _main._hud.title_bar
	_main._windows.open("budget")
	_main._windows.open("economy")
	if not bar._back.visible or bar._back.disabled:
		_fail("with a step behind, the title bar's back is not live")
	bar.back_requested.emit()
	if not _main._windows.is_open("budget"):
		_fail("the title bar's back did not return to the budget (open: %s)" % str(_main._windows.open_ids()))
	if bar._forward.disabled:
		_fail("after a step back, forward is not live")
	bar.forward_requested.emit()
	if not _main._windows.is_open("economy"):
		_fail("the title bar's forward did not return to the economy (open: %s)" % str(_main._windows.open_ids()))
	_main._windows.close_all()


## The mouse routes to a window are refused under a scene, as the keys are
## (V5.1-c2.1): back, a click on a nation or a sidebar entry under a summit would
## open a tab and close the summit.
func _check_chrome_is_inert_under_a_scene() -> void:
	_main._windows.open("budget")
	_main._windows.open("summit")
	_main._hud.title_bar.back_requested.emit()
	if not _main._windows.is_open("summit"):
		_fail("the title bar's back closed the summit")
	_main._on_nation_clicked("DEU")
	if not _main._windows.is_open("summit"):
		_fail("a click on a nation closed the summit")
	_main._hud.sidebar.navigate.emit("finances")
	if not _main._windows.is_open("summit"):
		_fail("a sidebar entry closed the summit")
	_main._windows.close("summit")


## V5.1-c4.2 (someday, carried from V5.1-0b): a preload keeps the dev scripts in
## every export, inert but present. main.gd reaches the console by a guarded
## load(), so an export filter can leave them out entirely.
func _check_no_dev_preload() -> void:
	var text := FileAccess.get_file_as_string("res://src/ui/main.gd")
	if text.contains('preload("res://src/ui/dev_'):
		_fail("main.gd preloads a dev script, which ships it in every export")
	if _main.get_node_or_null("DevConsole") == null and OS.is_debug_build():
		_fail("a debug build has no dev console after the load() route")


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
## open one. test_workspace.gd proves the manager does this on
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


## V5.1-c2.3: every keyed window is reached through the sidebar -- its domain is
## listed and holds it -- every listed domain has a registered tab, the hidden
## ones (no tab yet: the author's call 1) are not listed, and an entry opens its
## domain's first tab. A window with NO KEY is a self-opening surface (the
## summit), so the guarantee binds exactly the keyed windows.
func _check_sidebar_routes_to_every_domain() -> void:
	var sidebar = _main._hud.sidebar
	var Domains = load("res://src/ui/domains.gd")
	var ids: Array = _main._windows.panel_ids()
	var listed: Array = sidebar.entry_ids()
	for id in ids:
		if _main._windows.shortcut(id) == KEY_NONE:
			continue
		var domain: String = Domains.domain_of(id)
		if not listed.has(domain):
			_fail("no sidebar entry reaches '%s' (its domain '%s' is not listed)" % [id, domain])
	for domain in ["social", "defence"]:
		if Domains.tabs(domain, ids).is_empty() and listed.has(domain):
			_fail("the sidebar lists '%s', which has no tab yet" % domain)
	for domain in listed:
		if domain == sidebar.INBOX:
			continue
		var tabs: Array = Domains.tabs(domain, ids)
		if tabs.is_empty():
			_fail("the sidebar lists '%s', which holds no registered tab" % domain)
			continue
		sidebar.navigate.emit(domain)
		if not _main._windows.is_open(String(tabs[0])):
			_fail("the '%s' entry did not open its first tab '%s' (open: %s)" % [domain, tabs[0], str(_main._windows.open_ids())])
	# V5.1-c3.2: with a tab open (the last loop left one), the Inbox entry slides
	# the inbox over it, and again slides it back.
	sidebar.navigate.emit(sidebar.INBOX)
	if not _main._hud.inbox.visible or _main._windows.open_ids().is_empty():
		_fail("the Inbox entry did not slide the inbox over the open tab")
	sidebar.navigate.emit(sidebar.INBOX)
	if _main._hud.inbox.visible:
		_fail("the Inbox entry did not slide the inbox back")
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


## The sidebar marks the domain that is open WHATEVER OPENED IT -- V2.1c's rule
## for the bar, kept: a keypress, a map marker and a message card all open a tab
## through the window manager, and the mark follows `opened`, not the click.
func _check_sidebar_marks_the_open_domain() -> void:
	var sidebar = _main._hud.sidebar
	var windows = _main._windows
	windows.close_all()
	if sidebar.selected() != "":
		_fail("the sidebar marks '%s' with nothing open" % sidebar.selected())
	_press(KEY_B)
	if sidebar.selected() != "finances":
		_fail("opening budget by keypress marked '%s', not Finances" % sidebar.selected())
	windows.open("events")
	if sidebar.selected() != "presidency":
		_fail("opening Dispatches marked '%s', not the Presidency" % sidebar.selected())
	windows.close_all()
	if sidebar.selected() != "":
		_fail("closing the last tab left '%s' marked" % sidebar.selected())


## What the resting screen says while nothing is open -- V2.1c.
##
## tools/nav_probe.gd measured fourteen years with nothing ever opened: of 74
## months in which a decision was in front of the player, the screen said nothing
## in 42 (a president who never touches a card) or 64 (one who reads a card and
## closes it). A council vote and an open campaign window were silent in 100 % of
## their months, having no card path at all.
##
## The response is a count on the domain where the answer is given (V5.1-c2.3's
## sidebar; the action bar's cluster before it), and this asserts the machinery
## both ways round -- an id that is pending marks its domain, and nothing
## pending marks nothing. Whether a given month has anything
## pending is the simulation's business, not this test's.
func _check_sidebar_marks_what_awaits() -> void:
	var sidebar = _main._hud.sidebar

	sidebar.show_pending([])
	if not sidebar.pending_domains().is_empty():
		_fail("the sidebar reports a pending domain with nothing pending")

	sidebar.show_pending(["events", "orgs"])
	var marked: Array = sidebar.pending_domains()
	if not marked.has("presidency") or not marked.has("diplomacy") or not marked.has(sidebar.INBOX):
		_fail("a pending dispatch and a pending council vote did not mark the Presidency, Diplomacy and the Inbox: %s"
			% str(marked))
	if marked.has("finances"):
		_fail("a domain with nothing pending was marked: %s" % str(marked))

	# And the reader itself: with nothing pending in the simulation it must return
	# an empty list rather than everything or nothing-shaped garbage.
	var ids: Array = Pending.window_ids(_main._state, _main._loader)
	for id in ids:
		if _main._windows.frame(String(id)) == null:
			_fail("pending.gd named '%s', which is not a registered window" % id)

	sidebar.show_pending(Pending.window_ids(_main._state, _main._loader))


func _press(keycode: int) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	_main._unhandled_input(event)


## B16's focus/hotkey trap: with the save dialog visible, the single-letter
## panel hotkeys must NOT toggle the windows behind it, and Escape must close
## the dialog. The dialog is shown through the same path the pause menu uses
## (its save_load_requested lambda), not by poking visibility from nothing.
func _check_save_dialog_traps_hotkeys() -> void:
	var panel = _main.get("_save_load_panel")
	if panel == null:
		_fail("main scene built no save/load panel")
		return
	_main._windows.close_all()

	# The pause menu's own route into the dialog.
	_main._set_pause_menu_visible(false)
	panel.show()
	panel.mark_dirty()
	if not panel.visible:
		_fail("the save dialog did not open")
		return

	_press(KEY_B)
	if _main._windows.is_open("budget"):
		_fail("a panel hotkey opened a window while the save dialog was visible")
	_main._windows.close_all()

	# S keeps its toggle so it can still CLOSE the dialog it opened.
	_press(KEY_S)
	if panel.visible:
		_fail("S no longer closes the save dialog")

	# Reopen, then Escape -- the key the playtest found doing nothing.
	panel.show()
	panel.mark_dirty()
	_press(KEY_ESCAPE)
	if panel.visible:
		_fail("Escape did not close the save dialog")
	_main._windows.close_all()

	# The restore contract behind every close path (the review's P1): a dialog
	# the PAUSE MENU opened puts the menu back -- the settings panel's own
	# contract -- and one the TOP BAR opened leaves nothing behind. Both routes
	# driven through their real signals.
	_main._pause_menu.save_load_requested.emit()
	if not panel.visible or _main._pause_menu.get_parent().visible:
		_fail("the pause menu's save route did not open the dialog over a hidden menu")
	_press(KEY_ESCAPE)
	if panel.visible:
		_fail("Escape did not close the pause-menu-opened save dialog")
	if not _main._pause_menu.get_parent().visible:
		_fail("closing a pause-menu-opened save dialog left the pause menu hidden -- the player is stranded outside the flow that paused the clock")
	_main._close_pause_menu()

	_main._hud.title_bar.save_load_requested.emit()
	if not panel.visible:
		_fail("the top bar's save route did not open the dialog")
	_press(KEY_ESCAPE)
	if panel.visible or _main._pause_menu.get_parent().visible:
		_fail("closing a top-bar-opened save dialog raised the pause menu unasked")

	panel.hide()
	_main._windows.close_all()


## B4: the opening "Your term" card is a live countdown, not a snapshot -- its
## body must change as the months pass. Two months is enough for the months
## text to move, well inside a term.
func _check_term_card_refresh() -> void:
	var stack = _main._hud.inbox
	var card_id: String = _main.get("_term_card_id")
	if card_id.is_empty():
		_fail("a new game pushed no 'Your term' card id")
		return
	if not stack._bodies.has(card_id):
		_fail("the term card id '%s' is not a live card in the stack" % card_id)
		return

	var before: String = stack._bodies[card_id].text
	var clock: Node = _main.get_node("Clock")
	for _d in range(31 * 2):
		clock.advance_one_day()
		# The opening card is the OLDEST card in the stack, so the monthly
		# ticks' own cards (foreign acts and the rest) would evict it under
		# MAX_CARDS before the refresh could be observed -- that eviction is
		# by design and is test_hud's business. Dismiss the others as they
		# arrive so this check isolates the refresh, not the cap.
		for cid in stack._cards.keys():
			if String(cid) != card_id:
				stack.dismiss(String(cid))

	if not stack._cards.has(card_id):
		_fail("the term card did not survive two simulated months")
		return
	var after: String = stack._bodies[card_id].text
	if before == after:
		_fail("the 'Your term' card body did not change after two simulated months: '%s'" % before)


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


## V5.0 fix pass: the play gate's 11-second month end -- and V5.1-0a: every
## panel, not the budget's alone. The month's sweep marks every panel dirty, and
## a panel's own `visible` stays true inside a CLOSED window, so each one
## refreshed every month with its window shut: the budget's two 24-month
## projections were ~12 s of it, the other twenty ~0.4 s (law 174 ms,
## commodities ~60, city ~57...) -- and the same ~0.4 s on every command that
## sweeps, which is what the map placement's click paid (P4). Closed, a panel
## stays dirty and runs nothing; opening its window redraws it. Asked of every
## registered window, so a panel added later is held to it without a list.
func _check_a_closed_window_costs_nothing() -> void:
	var checked := 0
	for id in _main._windows.panel_ids():
		var panel = _main._windows.frame(id)._content
		if not panel.has_method("_process") or not ("_dirty" in panel):
			continue
		_main._windows.close_all()
		_main._windows.mark_all_dirty()
		panel._process(0.0)
		if not panel._dirty:
			_fail("the '%s' panel refreshed with its window closed" % id)
		_main._windows.open(id)
		panel._process(0.0)
		if panel._dirty:
			_fail("opening the '%s' window did not redraw its panel" % id)
		checked += 1
	_main._windows.close_all()
	if checked < 20:
		_fail("only %d registered panels were checked for the closed-window gate" % checked)


## The test audit's S4: the check above calls each panel's _process by hand,
## after marking it dirty itself. This one is the game's own path: every window
## shut, every panel clean, ONE month reached by real time passing -- the sliced
## path a player gets (src/ui/month_runner.gd: the windows disabled while it
## closes, re-enabled, then main.gd's sweep), not a hand-driven day's whole
## month -- then real frames. Each panel must come out dirty -- the month's sweep reached it, so it
## redraws when its window opens -- and still dirty: none refreshed shut, in
## whatever order the engine processed it. A month end that stopped marking the
## panels (an opened window showing last month) and a panel that refreshes
## hidden both fail here.
func _begin_a_month_with_every_window_shut() -> bool:
	_main._windows.close_all()
	# Nothing in flight before the month: the forecast's projection is drained,
	# so a job found after it began with its window shut.
	_main._budget_panel._forecast.drain()
	var clock: Node = _main.get_node("Clock")
	# The engine must not advance days on its own; real time is handed in below,
	# one day of it, as test_month_runner.gd's B game takes its month.
	clock.set_process(false)
	clock.set_speed(1)
	while clock.day < clock._days_in_month(clock.month, clock.year):
		clock.advance_one_day()
	# The hand-driven days cleaned nothing and the windows are still shut; the
	# panels are cleaned HERE, so a dirty one after the month was the month's.
	_main._windows.close_all()
	for id in _main._windows.panel_ids():
		var panel = _main._windows.frame(id)._content
		if "_dirty" in panel:
			panel._dirty = false
	clock.paused = false
	clock._process(1.0 / clock.SPEED_DAYS_PER_SECOND[0])
	if not _main._month_runner.running():
		_fail("real time reaching the 1st did not run its month across frames")
		return false
	return true


func _check_the_month_left_every_closed_panel_dirty() -> void:
	var checked := 0
	for id in _main._windows.panel_ids():
		var panel = _main._windows.frame(id)._content
		if not ("_dirty" in panel) or _main._windows.is_open(id):
			continue
		if not panel._dirty:
			_fail("after a month with every window shut, the '%s' panel is clean -- it refreshed hidden, or the month never marked it" % id)
		checked += 1
	if checked < 20:
		_fail("only %d registered panels were read after the shut month" % checked)
	# The budget's forecast has a gate of its own (budget_forecast.gd's
	# is_visible_in_tree()), and the forecast test reaches it only through the
	# panel's own hide(), which a `visible` gate passes too -- P2's exact trap.
	# The month made "now" due; with the window shut it must not begin.
	if not _main._windows.is_open("budget") and _main._budget_panel._forecast._job != null:
		_fail("the budget forecast began a projection with its window shut")


## V5.1-0a review pass 1: the Tax Code window commits through Budget.commit()
## too, and the budget window's forecast -- projected off the frame, kept until
## a change of state -- must hear of it, or it shows the pre-commit budget's
## future while the books beside it show the new one.
func _check_a_tax_commit_reaches_the_budget_forecast() -> void:
	var forecast = _main._budget_panel._forecast
	_main._windows.open("budget")
	_main._budget_panel._process(0.0)
	forecast.drain()
	_main._tax_panel._on_commit()
	if not forecast.busy():
		_fail("a Tax Code commit left the budget's forecast settled on the old rates")
	_main._windows.close_all()


## V5.1-0a review (code-review pass): every player command, not only the two
## fiscal commits, moves what the budget window shows -- a subsidy, a law, a
## diplomatic act all reach its books. A pinned budget window kept its "now"
## books and forecast until a sweep, so the next lever move was credited with the
## command's effect. Asked of one command that sweeps nothing of its own.
func _check_any_command_reaches_the_budget_forecast() -> void:
	var forecast = _main._budget_panel._forecast
	_main._windows.open("budget")
	_main._budget_panel._process(0.0)
	forecast.drain()
	_main._companies_panel.acted.emit(Budget.snapshot(_main._state), "A subsidy")
	if not forecast.busy():
		_fail("a player command left the budget's forecast settled on the state before it")
	_main._windows.close_all()


func _collect_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
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
