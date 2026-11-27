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
var _capped
var _rail: Control
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
		# The void pass (d): a short page's plate hugs it. Measured after a frame of layout.
		_manager.open("calendar")
		_stage = 4
		return false
	if _stage == 4:
		_check_a_short_page_hugs_its_content("calendar")
		_manager.open("diplomacy")
		_stage = 45
		return false
	if _stage == 45:
		_check_a_short_page_hugs_its_content("diplomacy")
		_manager.open("tall")
		_stage = 5
		return false
	if _stage == 5:
		_check_a_tall_page_takes_the_whole_dock()
		_manager.open("fraction")
		_stage = 6
		return false
	if _stage == 6:
		_check_a_fractional_page_does_not_scroll()
		_open_a_capped_page()
		_stage = 7
		return false
	if _stage == 7:
		_check_the_capped_page(900.0)
		_capped.cap = INF
		_stage = 8
		return false
	if _stage == 8:
		_check_the_capped_page(INF)
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
	_check_dock_width_follows_the_domain()
	_check_wanted_height_shapes()
	# Opened here and measured after a frame of layout, in stage 3.
	_manager.open("finances")
	_stage = 1
	return false


## Real tab ids, so the domain table places them: Finances holds the Books page and projects, Economy holds economy.
## Plus two windows in no row and one scene.
func _register() -> void:
	for id in ["finances", "projects", "economy", "alpha", "beta", "summit", "calendar", "diplomacy", "orgs",
			"energy", "fraction"]:
		var content := Label.new()
		content.text = "content of %s" % id
		# T7 (#400 pass 2): a page whose wanted height is not a whole pixel.
		content.custom_minimum_size = Vector2(300, 200.4 if id == "fraction" else 200.0)
		var page: Control = content
		if id == "diplomacy":
			# Built the way the Agenda, Diplomacy and Energy panels are: a scroll that takes the
			# height left (EXPAND), holding content shorter than the dock.
			page = VBoxContainer.new()
			var scroll := ScrollContainer.new()
			scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
			page.add_child(scroll)
			scroll.add_child(content)
		_contents[id] = content
		_manager.register(id, id.capitalize(), page)


## Nothing is open and the dock is down: a dock left visible with no tab in it
## is a plate over the map that eats every click.
func _check_closed_at_start() -> void:
	if not _manager.open_ids().is_empty():
		_fail("registering a panel opened it: %s" % str(_manager.open_ids()))
	if _manager.dock().visible:
		_fail("the dock is visible with nothing open")


func _check_tab_switch_keeps_one_open() -> void:
	_manager.open("finances")
	if _manager.open_ids() != ["finances"]:
		_fail("opening budget left %s open" % str(_manager.open_ids()))
	if not _manager.dock().visible:
		_fail("opening a tab did not raise the dock")
	if _manager.tab_ids() != ["finances", "projects"]:
		_fail("Finances shows tabs %s, not its two registered ones" % str(_manager.tab_ids()))
	if _manager.domain_title() != "Finances":
		_fail("the budget's domain is titled '%s', not Finances" % _manager.domain_title())

	_manager.open("projects")
	if _manager.open_ids() != ["projects"]:
		_fail("switching to the tax tab left %s open" % str(_manager.open_ids()))
	if _manager.tab_ids() != ["finances", "projects"]:
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
	_manager.open("finances")
	var counts: Array = []
	var watch := func(): counts.append(_manager.open_ids().size())
	for id in ["finances", "projects", "economy"]:
		_manager.frame(id).visibility_changed.connect(watch)
	_manager.open("projects")
	_manager.open("economy")
	for id in ["finances", "projects", "economy"]:
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
	if _manager.domain_title() != "Alpha" or _manager.tab_ids() != ["alpha"]:
		_fail("a window in no row opened under '%s' with tabs %s" % [_manager.domain_title(), str(_manager.tab_ids())])
	_manager.close_all()


## A scene displaces the open tab and wears no tabs of its own; closing it
## leaves the map, and it is not a step back can return to.
func _check_a_scene_takes_the_dock() -> void:
	_manager.open("finances")
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
	_manager.open("finances")
	_manager.open("projects")
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
	if _manager.open_ids() != ["projects"]:
		_fail("back after the summit reached %s, not the tab before it" % str(_manager.open_ids()))
	_manager.close_all()


## The map is a destination: back from it returns to the last tab, and a new
## destination cuts the forward path, as a browser does.
func _check_history_back_forward() -> void:
	_manager.open("finances")
	_manager.open("projects")
	_manager.open("economy")
	_manager.back()
	if _manager.open_ids() != ["projects"]:
		_fail("back from economy reached %s, not tax" % str(_manager.open_ids()))
	_manager.back()
	if _manager.open_ids() != ["finances"]:
		_fail("back from tax reached %s, not budget" % str(_manager.open_ids()))
	_manager.forward()
	if _manager.open_ids() != ["projects"]:
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
		_manager.open("finances" if i % 2 == 0 else "projects")
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


## G3 S1, decision 9 (the author, 2026-11-21: "Toujours plein"): the workspace's sheets always fill
## it, from the sidebar's pane to GAP_PANE short of the screen's right edge, at every text size. The one
## narrow tab is Regions, whose place is the map it tints (window_manager.gd DOCK_WIDTHS).
func _check_dock_width_follows_the_domain() -> void:
	var full: float = BOUNDS.x - UiTheme.GAP_PANE - WindowManager.DOCK_LEFT
	for scale in [1.0, 1.15, 0.9]:
		UiTheme.set_text_scale(scale)
		for id in ["calendar", "diplomacy", "orgs", "energy", "finances", "projects", "economy"]:
			_manager.open(id)
			var rect: Rect2 = _manager.dock().get_global_rect()
			if not is_equal_approx(rect.size.x, full) or not is_equal_approx(rect.end.x, BOUNDS.x - UiTheme.GAP_PANE):
				_fail("at text %d %% the %s tab docks %.0f wide to %.0f, not the full %.0f to %.0f" % [
					roundi(scale * 100), id, rect.size.x, rect.end.x, full, BOUNDS.x - UiTheme.GAP_PANE])
	UiTheme.set_text_scale(1.0)
	# The fit tests' band is the width BESIDE the inbox, the narrowest a full tab gets (#439 pass 1).
	if not is_equal_approx(WindowManager.dock_width("finances"), full - WindowManager.Inbox.WIDTH - UiTheme.GAP_PANE):
		_fail("dock_width() gives %.0f, not the band beside the inbox" % WindowManager.dock_width("finances"))
	UiTheme.set_text_scale(1.0)
	_manager.close_all()


## W2: a page in columns stops at its cap (window_manager.gd _past_cap) and its aside stands against it; the header
## keeps the band. Opened a frame before it is read: the body is laid out by then.
func _open_a_capped_page() -> void:
	_capped = Capped.new()
	_capped.cap = 900.0
	_manager.register("capped", "Capped", _capped)
	_rail = Control.new()
	_rail.custom_minimum_size.x = 200.0
	_manager.set_aside(WindowManager.Domains.domain_of("capped"), _rail)
	_manager.open("capped")


func _check_the_capped_page(cap: float) -> void:
	var held: Rect2 = _manager.frame("capped").get_global_rect()
	var beside: Rect2 = _rail.get_global_rect()
	var full: float = BOUNDS.x - UiTheme.GAP_PANE - WindowManager.DOCK_LEFT
	var wanted: float = minf(cap, full - 200.0 - UiTheme.GAP_PANE)
	if not is_equal_approx(held.size.x, wanted) or not is_equal_approx(beside.position.x, held.end.x + UiTheme.GAP_PANE) or not is_equal_approx(beside.size.x, 200.0):
		_fail("capped at %s the page is %s and its rail %s, wanted a %.0f page with the rail a gap past it" % [cap, held, beside, wanted])
	if not is_equal_approx(_manager.dock().size.x, full):
		_fail("a capped page narrowed the header band to %.0f" % _manager.dock().size.x)


class Capped extends Control:
	var cap := INF

	func page_cap() -> float:
		return cap


## #400 pass 2, T2: a page's wanted height is its content shown whole, scrolls unscrolled. Summed
## only DOWN a column, the tallest of a row (two scrolls side by side were summed: 800 for a 500 px
## page), and never on top of a height floor that already holds the scroll (the mid-term Agenda's
## ~300 px of blank under its last line).
func _check_wanted_height_shapes() -> void:
	var TabPage = load("res://src/ui/tab_page.gd")
	var shapes := {
		"header, scroll, footer": [_column([_box(50.0), _scroll_of(300.0), _box(40.0)]), -1.0],
		"two scrolls side by side": [_row([_scroll_of(300.0), _scroll_of(500.0)]), 500.0],
		"a scroll beside a static column": [_row([_scroll_of(500.0), _box(400.0)]), 500.0],
		"a 520 px floor over a 340 px column": [_column([_box(40.0), _scroll_of(300.0)], 520.0), 520.0],
		# A wrapper (a panel, a margin) shows its children over each other: the tallest growth, not the sum.
		"two scrolls in one panel": [_panel([_scroll_of(300.0), _scroll_of(500.0)]), -2.0],
	}
	for name in shapes:
		var content: Control = shapes[name][0]
		var page = TabPage.new()
		_manager.add_child(page)
		page.setup(content)
		var want: float = shapes[name][1]
		if want == -2.0:
			want = content.get_minimum_size().y + 500.0 - content.get_child(1).get_combined_minimum_size().y
		elif want < 0.0:
			# The column's own minimum (header, footer, separations) with the scroll shown whole.
			want = content.get_combined_minimum_size().y + 300.0 - content.get_child(1).get_combined_minimum_size().y
		var plate: float = page.get_theme_stylebox("panel").get_minimum_size().y
		var got: float = page.wanted_height() - plate
		if absf(got - want) > 1.0:
			_fail("a page of %s wants %.0f px of content height, not %.0f" % [name, got, want])
		page.free()


func _box(height: float) -> Control:
	var box := Control.new()
	box.custom_minimum_size = Vector2(100, height)
	return box


func _scroll_of(height: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(_box(height))
	return scroll


func _column(children: Array, floor_height := 0.0) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.custom_minimum_size.y = floor_height
	for child in children:
		column.add_child(child)
	return column


func _panel(children: Array) -> PanelContainer:
	var panel := PanelContainer.new()
	for child in children:
		panel.add_child(child)
	return panel


func _row(children: Array) -> HBoxContainer:
	var line := HBoxContainer.new()
	for child in children:
		line.add_child(child)
	return line


## (d), the author's call: a page whose content is shorter than the dock is a plate as tall as its
## content over the map, not a full-height page with a blank bottom.
func _check_a_short_page_hugs_its_content(id: String) -> void:
	var dock: Rect2 = _manager.dock().get_global_rect()
	var full: float = BOUNDS.y - WindowManager.DOCK_TOP - WindowManager.DOCK_BOTTOM
	if dock.size.y > full - 200.0:
		_fail("a 200 px page (%s) sits in a %.0f px dock: the plate did not hug its content" % [id, dock.size.y])
	var content: Rect2 = (_contents[id] as Control).get_global_rect()
	if content.end.y > dock.end.y + 0.5:
		_fail("the hugging plate (%s) cuts its content (%s)" % [str(dock), str(content)])
	_manager.close_all()


## T7 (#400 pass 2): a page that wants a fractional height gets a dock at least that tall, and no bar.
func _check_a_fractional_page_does_not_scroll() -> void:
	var page = _manager.frame("fraction")
	var header: float = (_manager.dock().get_child(0) as Control).get_combined_minimum_size().y
	var dock: Rect2 = _manager.dock().get_global_rect()
	if dock.size.y < header + page.wanted_height() - 0.001:
		_fail("a page wanting %.2f px sits in a %.2f px dock body" % [page.wanted_height(), dock.size.y - header])
	if dock.size.y != floorf(dock.size.y):
		_fail("the hugging dock is %.2f px tall, not a whole pixel" % dock.size.y)
	if page._scroll.get_v_scroll_bar().visible:
		_fail("a page wanting %.2f px shows a vertical bar in its hugging plate" % page.wanted_height())
	_manager.close_all()


func _check_a_tall_page_takes_the_whole_dock() -> void:
	var dock: Rect2 = _manager.dock().get_global_rect()
	var full: float = BOUNDS.y - WindowManager.DOCK_TOP - WindowManager.DOCK_BOTTOM
	if not is_equal_approx(dock.size.y, full):
		_fail("a page taller than the dock got a %.0f px dock, not the whole %.0f" % [dock.size.y, full])
	_manager.close_all()


## G3 S1's geometry at the 1920x1080 reference: the workspace starts GAP_PANE right of the sidebar's
## pane and GAP_PANE under the top strip's, ends GAP_PANE short of the screen's edge, and has no pane of
## its own: its header is the first sheet, the page a second one, GAP_PANE apart. The tabs are a
## segmented control in the header, in sentence case.
func _check_workspace_docks_left() -> void:
	_manager.open("finances")
	var rect: Rect2 = _manager.dock().get_global_rect()
	var gap := float(UiTheme.GAP_PANE)
	if not is_equal_approx(WindowManager.DOCK_LEFT, gap + WindowManager.Sidebar.WIDTH + gap):
		_fail("DOCK_LEFT is %.0f, not a gap either side of the %d px sidebar" % [WindowManager.DOCK_LEFT, WindowManager.Sidebar.WIDTH])
	if not is_equal_approx(rect.position.x, WindowManager.DOCK_LEFT):
		_fail("the dock's left edge is at %.0f, not the sidebar's %.0f" % [rect.position.x, WindowManager.DOCK_LEFT])
	if not is_equal_approx(rect.end.x, BOUNDS.x - gap):
		_fail("the dock ends at %.0f, not a gap short of the screen's %.0f" % [rect.end.x, BOUNDS.x])
	if not is_equal_approx(WindowManager.DOCK_TOP, gap + WindowManager.TopBar.BAR_HEIGHT + gap):
		_fail("DOCK_TOP is %.0f, not a gap either side of the %d px strip" % [WindowManager.DOCK_TOP, WindowManager.TopBar.BAR_HEIGHT])
	if not is_equal_approx(rect.position.y, WindowManager.DOCK_TOP):
		_fail("the dock's top is at %.0f, not under the strip at %.0f" % [rect.position.y, WindowManager.DOCK_TOP])
	var header: Control = _manager.dock().get_child(0)
	if header.theme_type_variation != UiTheme.PLATE:
		_fail("the workspace's header wears '%s', not a sheet" % header.theme_type_variation)
	var page: Control = _manager.frame("finances")
	if page.get_global_rect().end.x > rect.end.x + 0.5 or page.size.x < rect.size.x - 40.0:
		_fail("the open page (%s) does not fill the dock (%s)" % [str(page.get_global_rect()), str(rect)])
	if not is_equal_approx(page.get_global_rect().position.y - header.get_global_rect().end.y, gap):
		_fail("the header and the page are %.0f px apart, not GAP_PANE" % (page.get_global_rect().position.y - header.get_global_rect().end.y))
	var tabs: Array = _manager.tab_buttons()
	if tabs.is_empty():
		_fail("the Finances header shows no tabs")
	# A tab with something waiting wears the count and the hourglass, and loses both when it clears.
	_manager.set_tab_counts({"finances": 2})
	var counted: Button = tabs.filter(func(b): return String(b.get_meta("tab")) == "finances")[0]
	if not counted.text.ends_with("  2") or counted.icon == null:
		_fail("a tab with two waiting reads '%s' (icon %s)" % [counted.text, counted.icon])
	_manager.set_tab_counts({})
	if counted.text != _manager.title("finances") or counted.icon != null:
		_fail("a cleared tab still reads '%s'" % counted.text)
	for button in tabs:
		if (button as Button).theme_type_variation != UiTheme.SEGMENT:
			_fail("the tab '%s' is not a segment" % (button as Button).text)
		if (button as Button).text == (button as Button).text.to_upper() and (button as Button).text != (button as Button).text.to_lower():
			_fail("the tab '%s' is in capitals, not sentence case" % (button as Button).text)
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
