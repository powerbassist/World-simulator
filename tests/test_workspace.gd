extends SceneTree

## Headless test: godot --headless --script res://tests/test_workspace.gd
## Non-zero exit on any failure.
##
## V5.1-c2.2's docked workspace, tested on its own rather than through main.tscn
## -- U5a's test_window_frame.gd, renamed with the thing it tests. The manager
## holds no game state and every panel it shows is just a Control, so a test
## that built the whole game to check a tab switch would be measuring the wrong
## thing.
##
## What this pins down is the rule the dock rests on: **one tab is open at a
## time, its domain's other tabs beside it, and back and forward walk the
## player's own path.** The floating windows' pin, cascade and drag are gone by
## design (the author's call 3, 2026-10-21), and their checks with them.
##
## Driven a frame at a time -- a Control outside the tree has not run _ready(),
## so everything it builds is null. See docs/engine-decision.md.

const WindowManager = preload("res://src/ui/window_manager.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const BOUNDS := Vector2(1920, 1080)

var _failures: Array[String] = []
var _manager
var _contents := {}
var _frame := 0

## The fold checks need frames of their own: a Control reports the height it
## needed at its PREVIOUS width, so imposing a size and reading the result in the
## same call measures the size before it. V2.1a step 0's finding.
var _stage := 0
var _tall: Control
var _verb: Button


## The manager goes inside an explicitly-sized host rather than straight under
## the root window. Headless, the root window is 64x64 and a full-rect Control
## added to it reports 1920x1920 -- neither of which is the 1920x1080 the shell is
## laid out against. In the game the manager's parent is main.tscn's root
## Control, which is exactly what this host stands in for.
func _init() -> void:
	var host := Control.new()
	root.add_child(host)
	host.size = BOUNDS

	_manager = WindowManager.new()
	host.add_child(_manager)


func _process(_delta: float) -> bool:
	_frame += 1

	if _stage == 1:
		_open_the_tall_panel()
		_stage = 2
		return false
	if _stage == 2:
		_check_the_fold_mark_fires()
		_stage = 3
		return false
	if _stage == 3:
		_check_the_fold_mark_clears()
		_check_workspace_docks_left()
		_finish()
		return false

	if _frame < 2:
		return false  # let _ready() run on the manager and everything under it

	_register()
	_check_closed_at_start()
	_check_tab_switch_keeps_one_open()
	_check_tab_switch_never_shows_the_map()
	_check_a_window_in_no_row_is_its_own_domain()
	_check_a_scene_takes_the_dock()
	_check_a_tab_cannot_displace_a_scene()
	_check_history_back_forward()
	_check_history_is_twenty_deep()
	_check_content_survives_close()
	_check_a_panel_with_no_verb_never_wears_the_fold_mark()
	# Opened here and measured after a frame of layout, in stage 3.
	_manager.open("budget")
	_stage = 1
	return false


## Real tab ids, so the domain table places them: Finances holds budget and tax
## (projects is not registered here, so it shows no tab), Economy holds economy.
## Plus two windows in no row and one scene.
func _register() -> void:
	for id in ["budget", "tax", "economy", "alpha", "beta", "summit"]:
		var content := Label.new()
		content.text = "content of %s" % id
		content.custom_minimum_size = Vector2(300, 200)
		_contents[id] = content
		_manager.register(id, id.to_upper(), content)


## Nothing is open and the dock is down: a dock left visible with no tab in it
## is a plate over the map that eats every click.
func _check_closed_at_start() -> void:
	if not _manager.open_ids().is_empty():
		_fail("registering a panel opened it: %s" % str(_manager.open_ids()))
	if _manager.dock().visible:
		_fail("the dock is visible with nothing open")


func _check_tab_switch_keeps_one_open() -> void:
	_manager.open("budget")
	if _manager.open_ids() != ["budget"]:
		_fail("opening budget left %s open" % str(_manager.open_ids()))
	if not _manager.dock().visible:
		_fail("opening a tab did not raise the dock")
	if _manager.tab_ids() != ["budget", "tax"]:
		_fail("Finances shows tabs %s, not its two registered ones" % str(_manager.tab_ids()))
	if _manager.domain_title() != "Finances":
		_fail("the budget's domain is titled '%s', not Finances" % _manager.domain_title())

	_manager.open("tax")
	if _manager.open_ids() != ["tax"]:
		_fail("switching to the tax tab left %s open" % str(_manager.open_ids()))
	if _manager.tab_ids() != ["budget", "tax"]:
		_fail("a switch inside Finances changed its tabs to %s" % str(_manager.tab_ids()))

	_manager.open("economy")
	if _manager.open_ids() != ["economy"]:
		_fail("opening another domain left %s open" % str(_manager.open_ids()))
	if _manager.domain_title() != "Economy" or _manager.tab_ids() != ["economy"]:
		_fail("the economy opened under '%s' with tabs %s" % [_manager.domain_title(), str(_manager.tab_ids())])
	_manager.close_all()
	if _manager.dock().visible:
		_fail("closing the last tab left the dock up")


## The new tab shows before the old one hides, so nothing watching visibility
## (the screen stack, c2.3's sidebar mark) ever sees the bare map mid-switch.
func _check_tab_switch_never_shows_the_map() -> void:
	_manager.open("budget")
	var counts: Array = []
	var watch := func(): counts.append(_manager.open_ids().size())
	for id in ["budget", "tax", "economy"]:
		_manager.frame(id).visibility_changed.connect(watch)
	_manager.open("tax")
	_manager.open("economy")
	for id in ["budget", "tax", "economy"]:
		_manager.frame(id).visibility_changed.disconnect(watch)
	if counts.has(0):
		_fail("a tab switch passed through nothing open: %s" % str(counts))
	_manager.close_all()


## A window the domain table does not list is not lost: it opens as its own
## one-tab domain under its own title.
func _check_a_window_in_no_row_is_its_own_domain() -> void:
	_manager.open("alpha")
	if _manager.open_ids() != ["alpha"]:
		_fail("a window in no row did not open: %s" % str(_manager.open_ids()))
	if _manager.domain_title() != "ALPHA" or _manager.tab_ids() != ["alpha"]:
		_fail("a window in no row opened under '%s' with tabs %s" % [_manager.domain_title(), str(_manager.tab_ids())])
	_manager.close_all()


## A scene displaces the open tab and wears no tabs of its own; closing it
## leaves the map, and it is not a step back can return to.
func _check_a_scene_takes_the_dock() -> void:
	_manager.open("budget")
	_manager.open("summit")
	if _manager.open_ids() != ["summit"]:
		_fail("the summit shares the dock with %s" % str(_manager.open_ids()))
	if not _manager.tab_ids().is_empty():
		_fail("a scene shows tabs %s" % str(_manager.tab_ids()))
	_manager.close("summit")
	if not _manager.open_ids().is_empty() or _manager.dock().visible:
		_fail("closing the summit left %s open" % str(_manager.open_ids()))
	_manager.back()
	if _manager.is_open("summit"):
		_fail("back returned to a scene")
	_manager.close_all()


## QA #54, TAKE 1: a map marker clicked beside a docked summit opened its tab
## and hid the summit, losing its dialogue and its priced choice. A scene leaves
## the dock only by its own close (its Continue, Escape, Back to the map); a tab
## open -- from any caller, gated or not -- and back/forward wait for it.
func _check_a_tab_cannot_displace_a_scene() -> void:
	_manager.open("budget")
	_manager.open("tax")
	_manager.open("summit")
	_manager.open("economy")
	if _manager.open_ids() != ["summit"]:
		_fail("opening a tab beside the summit left %s open" % str(_manager.open_ids()))
	_manager.back()
	_manager.forward()
	if _manager.open_ids() != ["summit"]:
		_fail("back/forward beside the summit left %s open" % str(_manager.open_ids()))
	_manager.close("summit")
	_manager.back()
	if _manager.open_ids() != ["tax"]:
		_fail("back after the summit reached %s, not the tab before it" % str(_manager.open_ids()))
	_manager.close_all()


## The map is a destination: back from it returns to the last tab, and a new
## destination cuts the forward path, as a browser does.
func _check_history_back_forward() -> void:
	_manager.open("budget")
	_manager.open("tax")
	_manager.open("economy")
	_manager.back()
	if _manager.open_ids() != ["tax"]:
		_fail("back from economy reached %s, not tax" % str(_manager.open_ids()))
	_manager.back()
	if _manager.open_ids() != ["budget"]:
		_fail("back from tax reached %s, not budget" % str(_manager.open_ids()))
	_manager.forward()
	if _manager.open_ids() != ["tax"]:
		_fail("forward from budget reached %s, not tax" % str(_manager.open_ids()))
	_manager.open("alpha")
	if _manager.can_forward():
		_fail("a new destination kept the forward path")
	_manager.close("alpha")
	_manager.back()
	if _manager.open_ids() != ["alpha"]:
		_fail("back from the map reached %s, not the tab just closed" % str(_manager.open_ids()))
	_manager.close_all()


func _check_history_is_twenty_deep() -> void:
	for i in 25:
		_manager.open("budget" if i % 2 == 0 else "tax")
	var steps := 0
	while _manager.can_back() and steps < 100:
		_manager.back()
		steps += 1
	if steps != WindowManager.HISTORY_DEPTH - 1:
		_fail("back walked %d steps after 25 opens, not %d" % [steps, WindowManager.HISTORY_DEPTH - 1])
	_manager.close_all()


## Closing hides a panel, it does not free it. Every panel in this game holds a
## setup(state, loader) and a signal connection made once at startup; freeing one
## on close would mean rebuilding and rewiring it on every open.
func _check_content_survives_close() -> void:
	_manager.open("beta")
	_manager.close("beta")
	var content: Control = _contents["beta"]
	if not is_instance_valid(content):
		_fail("closing a panel freed its content")
		return
	if content.text != "content of beta":
		_fail("closing a panel disturbed its content")
	if _manager.frame("beta").visible:
		_fail("closing a panel left its page visible")


## V2.1a's fold contract: the mark says ONE thing -- the panel's primary action
## is not on screen -- and not "there is more below", which is the scrollbar's
## job. So a panel that scrolls and has no verb at all must never draw it.
func _check_a_panel_with_no_verb_never_wears_the_fold_mark() -> void:
	_manager.open("alpha")
	var page = _manager.frame("alpha")
	if page.primary_action_below_fold():
		_fail("a panel that implements no primary_action() reported a fold")
	page._process(0.0)
	if page.theme_type_variation != UiTheme.PLATE:
		_fail("a panel with no verb wears '%s'" % page.theme_type_variation)
	_manager.close_all()


## A panel taller than its band with its one button at the bottom, which is
## nation_panel.gd at V1.3e and again at V1.3g.
func _open_the_tall_panel() -> void:
	_tall = VBoxContainer.new()
	var filler := Control.new()
	filler.custom_minimum_size = Vector2(300, 1400)
	_tall.add_child(filler)
	_verb = Button.new()
	_verb.text = "Act"
	_tall.add_child(_verb)
	_tall.set_script(load("res://tests/fixtures/panel_with_a_verb.gd"))
	_tall.primary = _verb

	_manager.register("tall", "TALL", _tall)
	_manager.open("tall")
	_manager.frame("tall").fit_within(Vector2(600, 400))


func _check_the_fold_mark_fires() -> void:
	var page = _manager.frame("tall")
	if not page.primary_action_below_fold():
		_fail("a verb 1400px down a 400px page did not report as below the fold")
	page._process(0.0)
	if page.theme_type_variation != UiTheme.PLATE_FOLDED:
		_fail("the page did not put on the fold mark, it wears '%s'" % page.theme_type_variation)
	# Scrolled here and read on the NEXT frame: the mark is about what is on
	# screen now rather than about how tall the panel is.
	page._scroll.scroll_vertical = 4000


func _check_the_fold_mark_clears() -> void:
	var page = _manager.frame("tall")
	if page.primary_action_below_fold():
		_fail("scrolling the verb into view did not clear the fold")
	page._process(0.0)
	if page.theme_type_variation != UiTheme.PLATE:
		_fail("the fold mark did not come off, the page wears '%s'" % page.theme_type_variation)
	_manager.close_all()


## The board's geometry at the 1920x1080 reference: the dock's left edge at the
## sidebar's right edge, 1240 wide, under the strip, and the map uncovered to its
## right (test_shell.gd hit-tests that half in the real scene).
func _check_workspace_docks_left() -> void:
	_manager.open("budget")
	var rect: Rect2 = _manager.dock().get_global_rect()
	if not is_equal_approx(rect.position.x, WindowManager.DOCK_LEFT):
		_fail("the dock's left edge is at %.0f, not the sidebar's %.0f" % [rect.position.x, WindowManager.DOCK_LEFT])
	if not is_equal_approx(rect.size.x, WindowManager.DOCK_WIDTH):
		_fail("the dock is %.0f wide, not %.0f" % [rect.size.x, WindowManager.DOCK_WIDTH])
	if rect.end.x >= BOUNDS.x - 100.0:
		_fail("the dock ends at %.0f and leaves no map to its right" % rect.end.x)
	if not is_equal_approx(rect.position.y, WindowManager.DOCK_TOP):
		_fail("the dock's top is at %.0f, not under the strip at %.0f" % [rect.position.y, WindowManager.DOCK_TOP])
	var page: Control = _manager.frame("budget")
	if page.get_global_rect().end.x > rect.end.x + 0.5 or page.size.x < rect.size.x - 40.0:
		_fail("the open page (%s) does not fill the dock (%s)" % [str(page.get_global_rect()), str(rect)])
	_manager.close_all()


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_workspace: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
