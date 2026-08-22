extends Control

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const ForeignPolicyK = preload("res://src/sim/foreign_policy_constants.gd")
const Bloc = preload("res://src/sim/bloc.gd")
const Defence = preload("res://src/sim/defence.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const Investment = preload("res://src/sim/investment.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Media = preload("res://src/sim/media.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const CalendarPanel = preload("res://src/ui/calendar_panel.gd")
const PeoplePanel = preload("res://src/ui/people_panel.gd")
const CompaniesPanel = preload("res://src/ui/companies_panel.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const ElectionPanel = preload("res://src/ui/election_panel.gd")
const LawPanel = preload("res://src/ui/law_panel.gd")
const MapView = preload("res://src/ui/map_view.gd")
const Minimap = preload("res://src/ui/minimap.gd")
const NationPanel = preload("res://src/ui/nation_panel.gd")
const BlocPanel = preload("res://src/ui/bloc_panel.gd")
const GovernmentPanel = preload("res://src/ui/government_panel.gd")
const SaveLoadPanel = preload("res://src/ui/save_load_panel.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const PauseMenu = preload("res://src/ui/pause_menu.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const Hud = preload("res://src/ui/hud.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const OverviewPanel = preload("res://src/ui/overview_panel.gd")
const EconomyPanel = preload("res://src/ui/economy_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Trends = preload("res://src/ui/trends.gd")

const MENU_SCENE := "res://src/ui/menu.tscn"

## Set by menu.gd before this scene enters the tree, the same way
## pending_load_slot is -- see its note. Empty means "load path", where the
## value is irrelevant because load replaces the whole GameState wholesale.
##
## Defaults to France rather than staying empty so a direct scene load still
## works: tests/test_game_loop.gd and tools/*.gd load main.tscn/build a
## GameState without going through menu.gd's nation-select panel at all.
const DEFAULT_PLAYER_NATION_ID := "FRA"
var pending_player_id := DEFAULT_PLAYER_NATION_ID

## Which start scenario to begin under -- V1.2e. Set by menu.gd alongside
## pending_player_id. Empty is the standard start, which is what a direct scene
## load (tests, tools) gets and what every save written before V1.2e reads as.
var pending_scenario_id := ""

## How many decisions Overview's recent-effects list keeps -- U4. Not
## GameState.recent_effects.size(), which is unbounded in the array itself;
## trimmed here so a long session's save file does not grow one entry per
## commit forever.
const RECENT_EFFECTS_KEPT := 5

## Set by menu.gd before this scene enters the tree. Empty means a new game;
## a slot name means load that save once the new game has been built and every
## panel is wired, which is what _on_load_requested() below already expects.
## A property rather than an autoload -- see menu.gd's note.
var pending_load_slot := ""

@onready var _clock: Node = $Clock

var _state
var _loader: DataLoader
var _hud
var _windows
var _top_bar
var _overview_panel
var _economy_panel
var _budget_panel
var _polling_panel
var _election_panel
var _law_panel
var _map_view
var _minimap
var _nation_panel
var _bloc_panel
var _calendar_panel
var _people_panel
var _companies_panel
var _government_panel
var _save_load_panel
var _pause_menu
var _settings_panel
## The clock's pause state from before the pause menu opened. Resume restores
## it rather than unpausing unconditionally, so pausing to save does not also
## start the clock on a player who had deliberately stopped it.
var _paused_before_menu := false

## Decisions committed since the last month elapsed, waiting to be measured
## against the history entry the next tick produces -- U4. Not persisted:
## a save taken between committing and the next monthly tick loses the
## in-flight baseline, the same way it would lose an un-elapsed day on the
## clock. {label, before} per entry, in commit order.
var _pending_effects: Array[Dictionary] = []


func _ready() -> void:
	# Before anything is built. A Theme on this Control propagates to every
	# descendant, which is what lets the docked tabs, the top bar and the four
	# modal panels share one set of styles instead of three hand-built ones.
	UiTheme.apply(self)

	_loader = DataLoader.new()
	_loader.load_all()

	if not _loader.errors.is_empty():
		for e in _loader.errors:
			push_error(e)
		return

	var ids := _loader.nations.keys()
	ids.sort()
	for id in ids:
		var n: Nation = _loader.nations[id]
		var pop_m := n.population / 1_000_000.0
		print("%s %-15s pop %5.1fM   GDP EUR %5.0fbn   debt %5.1f%%" % [
			n.id, n.nation_name, pop_m, n.gdp_eur_bn, n.debt_to_gdp_pct
		])

	_state = GameState.new_game(_loader, pending_player_id, pending_scenario_id)
	if not _state.errors.is_empty():
		for e in _state.errors:
			push_error(e)
		return
	_state.year = _clock.year
	_state.month = _clock.month

	# Three layers, back to front -- U5a's whole structural change. U2 made the
	# map one tab among seven; here it is the background the game is played on,
	# so it is added first, full-rect, and everything else draws over it.
	#
	# Windows sit *under* the HUD on purpose. A panel the player has dragged to
	# the bottom of the screen must not cover the clock or the portrait: the
	# furniture is how the game is read at a glance, and a window is something
	# they opened and can close.
	_map_view = MapView.new()
	_map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_map_view)
	_map_view.setup(_loader, _state)
	_map_view.nation_clicked.connect(_on_nation_clicked)

	_windows = WindowManager.new()
	add_child(_windows)

	_hud = Hud.new()
	add_child(_hud)
	_top_bar = _hud.top_bar

	# set_minimap() puts it in the tree, so setup() comes after -- the same
	# register()-before-setup() ordering every window below follows, and for the
	# same reason: a Control outside the tree has not run _ready().
	_minimap = Minimap.new()
	_hud.clock_cluster.set_minimap(_minimap)
	_minimap.setup(_map_view, _loader, _state)

	# register() before setup(), every time. register() is what puts the panel in
	# the tree, and a Control outside the tree has not run _ready(), so every
	# label setup() writes to is still null -- CLAUDE.md's gotcha, and the same
	# order dashboard.gd's add_tab() enforced by doing both itself.
	_overview_panel = OverviewPanel.new()
	_windows.register("overview", "Overview", _overview_panel)
	_overview_panel.setup(_state, _loader)

	_economy_panel = EconomyPanel.new()
	_windows.register("economy", "Economy", _economy_panel)
	_economy_panel.setup(_state, _loader)

	# hide_close_button() still applies: these panels each build their own Close
	# button for the life they had before U2 docked them, and the window frame
	# now provides the real one. Two close buttons on one panel is worse than
	# either.
	_budget_panel = BudgetPanel.new()
	_windows.register("budget", "Budget", _budget_panel)
	_budget_panel.setup(_state, _loader)
	_budget_panel.hide_close_button()
	_budget_panel.committed.connect(func(before):
		_queue_effect("Budget change", before)
		_update_top_bar()
	)

	_government_panel = GovernmentPanel.new()
	_windows.register("politics", "Politics", _government_panel)
	_government_panel.setup(_state, _loader)
	_government_panel.hide_close_button()
	_government_panel.dissolved.connect(func(before):
		_queue_effect("Dissolution called", before)
	)
	_government_panel.reassigned.connect(func(before):
		_queue_effect("Cabinet reassigned", before)
	)

	_polling_panel = PollingPanel.new()
	_windows.register("society", "Society", _polling_panel)
	_polling_panel.setup(_state)
	_polling_panel.hide_close_button()

	_law_panel = LawPanel.new()
	_windows.register("legislature", "Legislature", _law_panel)
	_law_panel.setup(_state, _loader)
	_law_panel.hide_close_button()
	_law_panel.proposed.connect(func(before, law_name):
		_queue_effect(law_name, before)
		_update_top_bar()
	)

	# The nation panel loses its side-by-side pane and becomes what it always
	# behaved like: a card about whichever country was clicked. Opened by
	# _on_nation_clicked(), and reachable from the World cluster as well so the
	# diplomatic verbs are not hidden behind knowing to click the map.
	_nation_panel = NationPanel.new()
	_windows.register("diplomacy", "Diplomacy", _nation_panel)
	_nation_panel.setup(_state, _loader)
	_nation_panel.hide_close_button()
	# The same three lines _law_panel.proposed gets -- a diplomatic action is a
	# player command with a domestic price, so it earns a U4 decision delta on
	# exactly the same terms a law does.
	_nation_panel.acted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
		# A diplomatic action moves relations, and on the relations layer that is a
		# colour change the player should see the moment they act rather than at
		# the next month's tick.
		_map_view.queue_redraw()
	)

	# V1.3d. Beside Diplomacy in the World cluster, and its own window rather than
	# a section of the nation panel: the council is not a nation and has no pixel
	# on the map to click, so there is nothing to select it by.
	_bloc_panel = BlocPanel.new()
	_windows.register("bloc", "The Union", _bloc_panel)
	_bloc_panel.setup(_state, _loader)
	_bloc_panel.hide_close_button()
	# V1.6 audit, V8. A council vote binds the player whichever way it goes, so it
	# is a command like any other and earns the same U4 delta as a law or an act.
	# It was the only one of the seven player commands with no signal at all.
	_bloc_panel.voted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
	)

	# U6a. The one surface that reads dated state the game has carried since the
	# MVP and never showed anywhere -- an election date, the council's next
	# proposal, every cooldown expiry -- and the only place a booking is made.
	_calendar_panel = CalendarPanel.new()
	_windows.register("calendar", "Diary", _calendar_panel)
	_calendar_panel.setup(_state, _loader)
	_calendar_panel.hide_close_button()
	# A booking commits nothing this month, so unlike `acted` and `proposed` there
	# is no baseline to queue. The repaint is all this needs: the diary is the only
	# panel whose contents just changed.
	_calendar_panel.diary_changed.connect(func(): _calendar_panel.mark_dirty())

	# U6b. Read-only, and the only surface that shows the whole register rather
	# than the one person a given screen happens to be about.
	_people_panel = PeoplePanel.new()
	_windows.register("people", "People", _people_panel)
	_people_panel.setup(_state, _loader)
	_people_panel.hide_close_button()

	# V1.4a. In the Economy cluster rather than the World one: a firm is a domestic
	# actor and the verb pointed at it is a spending decision, which is why the bill
	# lands on the budget panel beside the deployment bill and not anywhere near
	# Diplomacy.
	_companies_panel = CompaniesPanel.new()
	# V1.6e renames the WINDOW and not the id: the panel now carries the state's own
	# sector programmes beside the firm register, so "Companies" had stopped being
	# what the surface is about. The id stays "companies" because it is what
	# _build_action_bar() and tools/screenshot.gd --open both address.
	_windows.register("companies", "Industry", _companies_panel)
	_companies_panel.setup(_state, _loader)
	_companies_panel.hide_close_button()
	# The same three lines _law_panel.proposed and _nation_panel.acted get. A
	# subsidy is a player command with a domestic price and a budget line, so it
	# earns a U4 decision delta on exactly the same terms.
	_companies_panel.acted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
	)

	_build_action_bar()
	_wire_hud()

	# Four panels stay modal, not docked: election results and censure land on
	# the player regardless of which tab is open, and settings/save-load are
	# reached through the pause menu rather than the rail.
	_election_panel = ElectionPanel.new()
	_add_centered(_election_panel)
	_election_panel.setup(_state, _loader)
	_election_panel.hide()
	# V1.6 audit, V2. Dismissing a WON election resumes play; dismissing a LOST one
	# leaves office, because there is nothing behind that plate to go back to --
	# Elections.tick_month() skips a nation out of government, so the clock would
	# run on forever with no election able to resolve and nothing saying why.
	_election_panel.dismissed.connect(func():
		var ns = _state.player()
		if ns != null and not ns.in_government:
			get_tree().change_scene_to_file(MENU_SCENE)
			return
		_clock.paused = false
	)

	_save_load_panel = SaveLoadPanel.new()
	_add_centered(_save_load_panel)
	_save_load_panel.hide()
	_save_load_panel.save_requested.connect(_on_save_requested)
	_save_load_panel.load_requested.connect(_on_load_requested)

	_settings_panel = SettingsPanel.new()
	_add_centered(_settings_panel)
	_settings_panel.hide()
	_settings_panel.closed.connect(func(): _set_pause_menu_visible(true))

	# Blocking, unlike every other panel: a pause menu you can click past into
	# the map underneath is not paused in any sense the player recognises.
	_pause_menu = PauseMenu.new()
	_add_centered(_pause_menu, true)
	_set_pause_menu_visible(false)
	_pause_menu.resumed.connect(_close_pause_menu)
	_pause_menu.save_load_requested.connect(func():
		_set_pause_menu_visible(false)
		_save_load_panel.show()
		_save_load_panel.mark_dirty()
	)
	_pause_menu.settings_requested.connect(func():
		_set_pause_menu_visible(false)
		_settings_panel.show()
	)
	_pause_menu.main_menu_requested.connect(func():
		get_tree().change_scene_to_file(MENU_SCENE)
	)

	_clock.day_advanced.connect(_on_day_advanced)
	_clock.month_elapsed.connect(_on_month_elapsed)

	# Loading reuses the whole existing load path rather than a separate
	# start-from-save branch: a new game is built first, then replaced. That
	# costs one throwaway GameState and buys one code path to keep correct.
	if not pending_load_slot.is_empty():
		_on_load_requested(pending_load_slot)

	_update_top_bar()


## Screen-filling CenterContainer per panel, which is the one placement mechanism
## that works before a panel's children exist — an anchor preset computed in
## _ready() reads a minimum size of zero and lands in the corner. One container
## each, so hiding one panel does not move the other. Only the four modal
## panels use this now; the rest are docked by dashboard.gd.
##
## Placement only, since U3: the opaque background these panels need is the
## theme's PanelContainer style, inherited from this scene's root.
## The four clusters, in the order a president spends a day in rather than
## alphabetically. Every entry names a panel already registered above; the bar
## itself never sees a panel, so adding V1.3c's tariffs or U6's calendar is one
## register() and one line in this list.
func _build_action_bar() -> void:
	const ICONS := "res://addons/at-icons/control/"
	_hud.action_bar.add_cluster("state", "State", ICONS + "institutional_building.svg", [
		{"id": "overview", "label": "Overview"},
		{"id": "politics", "label": "Politics"},
		{"id": "legislature", "label": "Legislature"},
		# A president's diary is state. One line, exactly as the comment above
		# this function predicted three sessions ago.
		{"id": "calendar", "label": "Diary"},
		# A president's people are state too, by the same argument the diary took.
		{"id": "people", "label": "People"},
	])
	_hud.action_bar.add_cluster("economy", "Economy", ICONS + "coins.svg", [
		{"id": "economy", "label": "Economy"},
		{"id": "budget", "label": "Budget"},
		# V1.4a. One line, exactly as this function's own comment has now correctly
		# predicted for four sessions running.
		{"id": "companies", "label": "Companies"},
	])
	_hud.action_bar.add_cluster("society", "Society", ICONS + "human.svg", [
		{"id": "society", "label": "Polling"},
	])
	_hud.action_bar.add_cluster("world", "World", ICONS + "globe.svg", [
		{"id": "diplomacy", "label": "Diplomacy"},
		{"id": "bloc", "label": "The Union"},
	])
	_hud.action_bar.panel_requested.connect(func(id: String): _windows.open(id))


## Every signal the furniture emits, connected in one place. hud.gd builds and
## places the pieces and deliberately wires none of them -- it has no clock and
## no GameState, and giving it either would put game control in a layout file.
func _wire_hud() -> void:
	_hud.clock_cluster.pause_toggled.connect(func():
		_clock.toggle_pause()
		_update_top_bar()
	)
	_hud.clock_cluster.speed_selected.connect(func(s: int):
		_clock.set_speed(s)
		_update_top_bar()
	)
	_hud.top_bar.save_load_requested.connect(func():
		_save_load_panel.show()
		_save_load_panel.mark_dirty()
	)
	_hud.top_bar.settings_requested.connect(_open_pause_menu)
	_hud.portrait_card.setup(_state, _loader)

	# U5c. The legend proposes a layer, the map view holds it, and the legend is
	# then told what it now shows -- one direction, so the two cannot disagree
	# about which layer is up.
	_hud.map_legend.layer_selected.connect(func(id: String):
		_map_view.set_layer(id)
		_hud.map_legend.show_layer(_map_view.layer())
	)
	_map_view.nation_hovered.connect(func(id: String):
		_hud.map_legend.show_hover(id, _state, _map_view.viewer_id())
	)


func _add_centered(panel: Control, blocking := false) -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not blocking:
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(panel)
	add_child(holder)


## The pause menu's *holder* is what is shown and hidden, not the panel. It is
## the one holder built blocking, and a full-rect blocking CenterContainer goes
## on swallowing map clicks while the panel inside it is invisible.
func _set_pause_menu_visible(shown: bool) -> void:
	_pause_menu.get_parent().visible = shown
	_pause_menu.visible = shown


func _open_pause_menu() -> void:
	_paused_before_menu = _clock.paused
	_clock.paused = true
	_set_pause_menu_visible(true)
	_update_top_bar()


func _close_pause_menu() -> void:
	_set_pause_menu_visible(false)
	_settings_panel.hide()
	_clock.paused = _paused_before_menu
	_update_top_bar()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			if _pause_menu == null:
				return
			if _pause_menu.get_parent().visible:
				_close_pause_menu()
			else:
				_open_pause_menu()
		KEY_SPACE:
			_clock.toggle_pause()
			_update_top_bar()
		KEY_1:
			_clock.set_speed(1)
			_update_top_bar()
		KEY_2:
			_clock.set_speed(2)
			_update_top_bar()
		KEY_3:
			_clock.set_speed(3)
			_update_top_bar()
		# The same letters U2 bound to tabs, now opening windows. A key that
		# toggles rather than selects, because with no rail there is no longer
		# anything showing which panel is "current" -- pressing B twice should
		# put the player back on the map.
		KEY_O:
			_toggle_window("overview")
		KEY_E:
			_toggle_window("economy")
		KEY_B:
			_toggle_window("budget")
		KEY_G:
			_toggle_window("politics")
		KEY_P:
			_toggle_window("society")
		KEY_L:
			_toggle_window("legislature")
		KEY_M:
			# M was the Europe tab. The map is now always underneath, so the
			# useful thing that key can do is clear everything off it.
			if _windows != null:
				_windows.close_all()
			if _hud != null:
				_hud.action_bar.close_subrow()
		KEY_S:
			if _save_load_panel != null:
				_save_load_panel.visible = not _save_load_panel.visible
				if _save_load_panel.visible:
					_save_load_panel.mark_dirty()


## Records a command's pre-commit baseline, to be measured once the month it
## was committed in actually elapses -- see _pending_effects and
## _on_month_elapsed()'s resolution loop.
func _queue_effect(label: String, before: Dictionary) -> void:
	_pending_effects.append({"label": label, "before": before})


func _toggle_window(id: String) -> void:
	if _windows != null:
		_windows.toggle(id)


func _on_nation_clicked(nation_id: String) -> void:
	if _nation_panel == null or _windows == null:
		return
	# Content before the window opens: open() places the frame by centring its
	# size, and a nation panel that has not been told which nation it is showing
	# reports the size of an empty one.
	_nation_panel.show_nation(nation_id)
	_windows.open("diplomacy")


## The simulation's whole entry point. Economy first so budget percentages apply
## to this month's GDP; opinion last, so it reacts to figures that have already
## settled rather than to last month's. See docs/economy-model.md.
##
## The history entry is the two snapshots merged. Opinion is deliberately not
## folded into Budget.snapshot(): Budget.project() runs only the economy and
## budget ticks on its copy, so a snapshot carrying approval would make the
## projection-equals-reality test compare a real month against a stale one.
func _on_month_elapsed(year: int, month: int) -> void:
	if _state == null:
		return
	_state.year = year
	_state.month = month
	Economy.tick_month(_state)
	Budget.tick_month(_state)
	# Between Budget and Opinion, and both halves of that are load-bearing. AFTER
	# Budget, because the burden reads the deficit that Budget has just settled and
	# charges its penalty into NEXT month's recompute -- which is what stops a rule
	# on the deficit feeding a fine that widens the deficit that deepens the breach.
	# BEFORE Opinion, because the `europe` issue reads the burden, and wired the
	# other way round every bloc reaction would carry a spurious extra month of lag.
	Bloc.tick_month(_state, _loader)
	# V1.5d, and BEFORE Opinion rather than after it, which is the opposite of where
	# Society and Unrest sit. Those two write a load Opinion consumes next month on
	# purpose, to break a loop that runs through approval. This one reads
	# coalition_position, which Elections and Government rewrite AFTER Opinion in this
	# same sequence -- so it is already reading last month's government and the loop
	# approval -> censure -> re-formation -> framing -> approval is broken structurally,
	# for free.
	# V1.6b. AFTER Economy, which settled the unemployment it reads, and BEFORE Opinion,
	# which prices it in the SAME month -- unlike Society and Unrest below, which sit
	# after Opinion and are read on the following one. Said here because a reader
	# comparing the two will otherwise assume symmetry.
	#
	# Every harness that ticks a system must make this call, and there are seven:
	# here, tests/test_balance.gd, tools/balance_probe.gd, src/sim/budget.gd's
	# project(), tests/test_budget.gd's mirror of it, and four probes.
	# tests/test_inflation.gd reads the source of the first four and fails if the call
	# is missing, because V1.5d cost a session to two harnesses that never called
	# Media.tick_month() and therefore agreed about nothing.
	Inflation.tick_month(_state)

	Media.tick_month(_state, _loader)
	Opinion.tick_month(_state)

	var entry := Budget.snapshot(_state)
	entry.merge(Opinion.snapshot(_state))
	_state.append_history(entry)

	# The stamped entry (year/month added), so movements_between() reads the
	# same "now" for approval's poll-noise lookup that the rest of the UI does.
	var dated_entry := entry.duplicate(true)
	dated_entry["year"] = year
	dated_entry["month"] = month
	for pending in _pending_effects:
		_state.recent_effects.push_front({
			"label": pending["label"],
			"year": year,
			"month": month,
			"movements": Trends.movements_between(pending["before"], dated_entry),
		})
	_pending_effects.clear()
	while _state.recent_effects.size() > RECENT_EFFECTS_KEPT:
		_state.recent_effects.remove_at(_state.recent_effects.size() - 1)

	# U6a prunes resolved bookings older than the strip can reach. The register is
	# the diary's whole memory, so this is what keeps a save file finite.
	Calendar.tick_month(_state)

	_mark_all_dirty()

	# U5c. The map draws only on hover, pan, zoom and resize, which was complete
	# while its colours came from a hash of the nation id and is not now: relations
	# drift every month and a trade weight moves with every partner's GDP. Without
	# this the data layers show the colours of whenever the mouse last moved.
	if _map_view != null:
		_map_view.queue_redraw()

	# Discipline reads the approval Opinion has just settled, so it goes after
	# that and before anything that reads a coalition bonus or a censure vote.
	Discipline.tick_month(_state, _loader)

	# Cooldowns count down before the election check, same ordering reasoning as
	# everything else in this handler: state settles top to bottom, elections
	# read it last.
	Legislature.tick_month(_state)
	Dissolution.tick_month(_state)

	# Relations drift and diplomatic cooldowns, alongside the other cooldown
	# ticks. After Opinion, which has already read the bloc offsets an action
	# wrote last month, and before Elections, which runs last on settled state.
	Diplomacy.tick_month(_state, _loader)

	# V1.3g: capability converges, and alliance obligations are reconciled against
	# the measures Diplomacy has just finished writing. AFTER Diplomacy so the
	# obligation arrives in the month the measure did -- that is the one thing here
	# with no lag, and it is what the whole feature is about. Both PRICES then lag by
	# exactly one month together, because Budget has already closed this month's
	# books: a same-month bill with a next-month opinion cost would be two lags where
	# one will do, and they would disagree about which month the deployment started.
	#
	# The lag also breaks a real loop structurally rather than by iterating: bill ->
	# deficit -> a PRECONDITION_FIELDS entry -> which verbs are available -> measures
	# -> obligations -> bill. src/sim/bloc.gd makes the same call for the same reason.
	# Counted either side of the tick so an obligation that opens can be carded
	# without src/sim/ growing a record for the UI to read. Derived here rather than
	# serialised, which is the same call V1.3f made for foreign_acts in reverse: that
	# one is state the sim already writes, this one is a difference the UI can see
	# for itself.
	var obliged_before := _obliged_count()
	Defence.tick_month(_state)
	_card_obligations(obliged_before)

	# V1.3f: and now the nine act on their own initiative inside that tick, so
	# whatever they just did is read off the record and put in front of the player.
	_card_foreign_acts(year, month)

	# V1.4a: subsidised firms take share from their named rivals, and all three firm
	# prices are recomputed. In Defence's slot and for Defence's reason -- Budget has
	# closed this month's books, so the bill and both deviation channels lag by
	# exactly one month TOGETHER rather than one of them lagging alone, and the lag
	# breaks the same loop structurally: bill -> deficit -> a PRECONDITION_FIELDS
	# entry -> which verbs are available -> a new subsidy -> bill.
	Companies.tick_month(_state, _loader)

	# V1.6e: the capital each sector's standing programme has bought converges toward
	# the programme's intensity, and the bill is recomputed. In Companies' slot for
	# Companies' reason, and the loop it breaks is the identical one: bill -> deficit
	# -> a PRECONDITION_FIELDS entry -> which investment actions are available -> a
	# new programme -> bill. Sixth time this argument has been made.
	Investment.tick_month(_state)

	# V1.5a: services converge on what the country actually spends on them, delivered.
	# In Companies' slot for Companies' reason and not for the general tick-order one:
	# quality reaches `overall_approval_pct`, which is a PRECONDITION_FIELDS entry, so
	# quality -> approval -> which laws are available -> a `society` law -> corruption
	# -> quality closes exactly the loop the one-month lag exists to break. Fifth time
	# this argument has been made, and the first where the loop runs through opinion
	# rather than through the deficit.
	# V1.5b, immediately before Society: the quality stock divides by this layer's
	# dependency factor, so demography must have settled before quality reads it.
	Demography.tick_month(_state)
	Society.tick_month(_state)
	# V1.5c, immediately after Society: the grievance target reads the `health` and
	# `pensions` satisfactions, which read the quality stock the line above just settled.
	# It stays after Opinion for the same reason the two above it do, and the loop it
	# breaks is a second one -- `unrest_pct` is itself a PRECONDITION_FIELDS entry, so
	# unrest -> which laws are available -> a settlement law -> the stance -> unrest.
	Unrest.tick_month(_state)
	# V1.5c: the unions act inside that tick, and whatever they just did is read off
	# the record and put in front of the player. _card_foreign_acts()'s split exactly --
	# the sim writes the record, the UI decides what earns a card, and src/sim/ never
	# reads the list back, which tests/test_unrest.gd asserts over the whole directory.
	_card_unrest_acts(year, month)

	# Reads unpopularity Opinion already settled and discipline Discipline
	# already ticked -- a resignation this month is judged against this
	# month's numbers, not last month's.
	Cabinet.tick_month(_state, _loader)

	# Elections run last, on the already-settled history entry, and can fire a
	# national and an EP result in the same month (France and Belgium, June
	# 2029). Any result pauses the clock — the player reads it before time moves
	# again, whether that reading ends in Continue or in defeat.
	var results := Elections.tick_month(_state, _loader)
	if not results.is_empty() and _election_panel != null:
		_clock.paused = true
		_election_panel.show_results(results)
		_election_panel.show()


## The player's obliged deployments, right now. Only the obliged ones: a chosen
## deployment is a command the player just issued and does not need a card telling
## them they issued it.
func _obliged_count() -> int:
	if _state == null:
		return 0
	var n := 0
	for ally_id in Defence.deployments_of(_state, _state.player_nation_id).keys():
		if Defence.deployment_kind(_state, _state.player_nation_id, String(ally_id)) == DefenceK.DEPLOYMENT_OBLIGED:
			n += 1
	return n


## V1.3g. An alliance obligation opening is the one thing in this game that puts a
## standing charge on the player's budget with no command behind it, so it is
## exactly the thing that must not arrive silently -- the player would otherwise see
## a deficit move for a reason nothing on screen names, which is the class of
## failure docs/trade-model.md's unread `refused_by_partner` belongs to.
func _card_obligations(before: int) -> void:
	if _hud == null or _hud.message_stack == null:
		return
	var now := _obliged_count()
	if now <= before:
		return

	var ns = _state.player()
	_hud.message_stack.push(
		"Alliance obligation",
		"Forces are committed under a defensive pact. The budget carries %.2f%% of GDP for as long as it stands, and only abandoning the pact ends it." % (
			0.0 if ns == null else ns.deployment_bill_pct_gdp
		),
	)


## Put this month's foreign acts in the message column. V1.3f, and the first thing
## in the game that ever calls message_stack.push().
##
## U5a shipped that column as furniture with a stated reason -- the thing that
## fills it is events, which docs/tiers/v1.md schedules at V1.8, and wiring it to
## invented content would have cost that argument. An act by a simulated nation is
## not invented content; it is state src/sim/ just wrote. So this spends nothing:
## V1.8 still adds calls rather than a column.
##
## The sim writes the record and the UI decides what is worth showing, which is the
## data -> sim -> ui direction engine-decision.md rule 2 states. src/sim/ never
## touches this file and GameState.foreign_acts is never read back inside src/sim/
## -- tests/test_foreign_policy.gd asserts that, because a decision consulting it
## would be the grievance ledger docs/foreign-policy-model.md is built without.
##
## Filtered, and it has to be: nine nations on a cadence produce more acts than the
## column's six slots, and an unfiltered feed would push a sanction aimed at the
## player off the bottom before they read it. Anything aimed AT the player always
## cards; anything between two other nations needs the player to have a real stake
## in the actor. The threshold reuses the model's own stake vector rather than
## inventing a second notion of "relevant".
func _card_foreign_acts(year: int, month: int) -> void:
	if _hud == null or _hud.message_stack == null:
		return

	var player_id: String = _state.player_nation_id
	var floor_share: float = ForeignPolicyK.EVEN_SHARE * ForeignPolicyK.CARD_MIN_STAKE_SHARE

	# Oldest first, so the newest act ends up at the top of the column: push()
	# appends and the stack drops from the front when it overflows.
	var fresh: Array = []
	for act in _state.foreign_acts:
		if int(act["year"]) != year or int(act["month"]) != month:
			break
		fresh.push_front(act)

	for act in fresh:
		var actor_id := String(act["actor_id"])
		var target_id := String(act["target_id"])
		if actor_id == player_id:
			continue
		if target_id != player_id and ForeignPolicy.stake(_state, player_id, actor_id) < floor_share:
			continue

		# An act aimed at the player names the player in the TITLE and not again in
		# the body: "Austria -> you / State Visit: France" reads as though France
		# were a third country involved somehow.
		var aimed_here: bool = target_id == player_id
		var title: String = (
			"%s → you" % _nation_name(actor_id) if aimed_here else _nation_name(actor_id)
		)
		var body: String = (
			"%s." % String(act["action_name"]) if aimed_here
			else "%s: %s." % [String(act["action_name"]), _nation_name(target_id)]
		)
		# The model computes a reason and this is the only place it is ever read.
		# Shipping the key unread would be V1.3b's `refused_by_partner` a third time
		# -- a field src/sim/ fills in and no surface shows, which this block has now
		# recorded twice and fixed once.
		_hud.message_stack.push(title, "%s %s" % [body, _act_reason_text(String(act["reason"]))])


## V1.5c. What the unions did this month, as a card.
##
## No filter, unlike _card_foreign_acts() above, and the asymmetry is the content rather
## than an oversight: nine nations on a cadence produce more acts than the column has
## slots, where the player's own country strikes at most once a year. Every act is
## aimed at the player by definition, so there is nothing to be relevant ABOUT.
##
## The LABEL is read here and nowhere in src/sim/ -- unrest_constants.ACT_LABELS carries
## `protest` and `strike`, the sim picks one off the stock, and this file owns the
## wording. That is the same split nation_panel.gd has for a refusal and
## _act_reason_text() below has for a reason, and it is what makes one machine with two
## names honest rather than two machines wearing the row's vocabulary.
func _card_unrest_acts(year: int, month: int) -> void:
	if _hud == null or _hud.message_stack == null:
		return
	for act in _state.unrest_acts:
		if int(act["year"]) != year or int(act["month"]) != month:
			continue
		if String(act["nation_id"]) != _state.player_nation_id:
			continue
		_hud.message_stack.push(
			_unrest_title(String(act["label"])),
			"Grievance stands at %.0f of 100. Output will carry it for months." % float(act["unrest_pct"])
		)


func _unrest_title(label: String) -> String:
	match label:
		"protest": return "Demonstrations"
		"strike": return "General strike"
	return "Industrial action"


## The sentence for a ForeignPolicy.ACT_REASON_* key. src/sim/ returns keys and
## src/ui/ owns the wording, the same split nation_panel.gd has for a refusal and
## bloc_panel.gd for a vote.
func _act_reason_text(key: String) -> String:
	match key:
		ForeignPolicy.ACT_REASON_INTEREST: return "Their interests run this way."
		ForeignPolicy.ACT_REASON_GOODWILL: return "Mending what had soured."
		ForeignPolicy.ACT_REASON_GRIEVANCE: return "Answering a grievance."
	return ""


func _nation_name(nation_id: String) -> String:
	var n = _loader.nations.get(nation_id)
	return String(n.nation_name) if n != null else nation_id


## U6a, and the first time anything but the top bar has cared what day it is.
##
## ORDERING, stated rather than inherited from emission order: clock.gd emits
## month_elapsed BEFORE day_advanced on a rollover, so on the 1st of a month the
## whole monthly pipeline has already run by the time this fires. An appointment
## booked for the 1st therefore acts AFTER that month's tick, which is the reading
## that matches the fiction -- the month begins, and then the president spends it.
func _on_day_advanced(year: int, month: int, day: int) -> void:
	if _state != null:
		# The mirror. game_state.gd does not serialise this; save_manager.gd
		# carries clock.day at the payload's top level, and _on_load_requested()
		# re-mirrors it, so there is exactly one record of the date.
		_state.day = day
		_resolve_appointments(year, month, day)
	_update_top_bar()


## The dispatcher. src/sim/calendar.gd hands back entries and knows nothing about
## what they mean; this fires the command. Every system named here was already
## preloaded by this file, so the diary added no dependency to it -- and composing
## two systems' effects is the orchestrator's job, which is the call
## docs/cabinet-model.md records for Cabinet.seat() and the reason a scheduler
## reaching into three systems was refused.
##
## The `match` is a fixed, small set of system verbs -- the same class as
## _act_reason_text()'s key-to-wording map -- not per-nation or per-law content,
## so docs/engine-decision.md Rule 1 holds.
func _resolve_appointments(year: int, month: int, day: int) -> void:
	var due: Array = Calendar.due(_state, year, month, day)
	if due.is_empty():
		return

	var ns = _state.player()
	var party_list: Array = _loader.parties.get(_state.player_nation_id, [])

	for entry in due:
		# THE BASELINE IS TAKEN HERE, not when the player booked. U4's decision
		# delta measures a command against the next history entry, and a booking
		# commits nothing in the month it is made -- measured from the press, a
		# deferred act would report the movements of a month in which it did not
		# happen. _pending_effects is also documented as not persisted, so a save
		# across a booking would lose a baseline taken at the press entirely.
		var before := Budget.snapshot(_state)
		before.merge(Opinion.snapshot(_state))

		var label := ""
		var ok := false
		match String(entry.get("kind", "")):
			CalendarK.KIND_DIPLOMATIC:
				var action = _action_by_id(String(entry.get("action_id", "")))
				if action != null:
					var result := Diplomacy.execute(
						_state, _loader.diplomatic_actions, action,
						_state.player_nation_id, String(entry.get("target_id", "")),
					)
					ok = bool(result.get("ok", false))
					label = String(action.action_name)
			CalendarK.KIND_LAW:
				var law = _law_by_id(String(entry.get("law_id", "")))
				if law != null:
					var result := Legislature.propose(_state, _loader, law)
					ok = bool(result.get("passed", false))
					label = String(law.law_name)
			CalendarK.KIND_RESHUFFLE:
				var portfolio := String(entry.get("portfolio", ""))
				var party_id := String(entry.get("party_id", ""))
				if ns != null and Cabinet.can_assign(ns, portfolio, party_id):
					Cabinet.assign(_state, portfolio, party_id, party_list)
					ok = true
				label = portfolio.capitalize()

		Calendar.resolve(_state, Calendar.verb_key(entry), ok)
		if not label.is_empty():
			_queue_effect(label, before)
		_card_appointment(entry, label, ok)

	_mark_all_dirty()
	# A booked diplomatic act moves relations, and on that map layer it is a
	# colour change the player should see the day it happens -- the same reason
	# nation_panel's own `acted` handler redraws.
	if _map_view != null:
		_map_view.queue_redraw()


## A kept appointment is something that happened to the player's government with
## no button pressed that day, so it is exactly the class of event the message
## column exists for -- alongside an alliance obligation opening and a foreign
## act. An act that REFUSED on arrival matters more, not less: it is the one
## outcome the player could not have predicted when they booked it.
func _card_appointment(entry: Dictionary, label: String, ok: bool) -> void:
	if _hud == null or _hud.message_stack == null:
		return
	if label.is_empty():
		_hud.message_stack.push(
			"Appointment lapsed",
			"Something booked for today no longer exists to be done.",
		)
		return

	var kind := String(entry.get("kind", ""))
	var where := ""
	if kind == CalendarK.KIND_DIPLOMATIC:
		where = " with %s" % _nation_name(String(entry.get("target_id", "")))
	_hud.message_stack.push(
		"Kept: %s" % label,
		"%s%s, as booked.%s" % [
			label, where, "" if ok else " It did not carry.",
		],
	)


func _action_by_id(id: String):
	for action in _loader.diplomatic_actions:
		if String(action.id) == id:
			return action
	return null


func _law_by_id(id: String):
	for law in _loader.laws:
		if String(law.id) == id:
			return law
	return null


func _on_save_requested(slot: String) -> void:
	var error := SaveManager.save_game(_state, _clock, slot)
	if error.is_empty():
		_save_load_panel.report("Saved '%s'." % slot)
	else:
		_save_load_panel.report("Save failed: %s" % error)
	_save_load_panel.mark_dirty()


## Loading replaces the live GameState wholesale, so every panel holding a
## reference to the old one has to be pointed at the new one -- the same
## setup() calls _ready() made the first time, not a special load path.
func _on_load_requested(slot: String) -> void:
	var result := SaveManager.load_game(slot)
	if not result["ok"]:
		_save_load_panel.report("Load failed: %s" % result["error"])
		_save_load_panel.mark_dirty()
		# Shown, not merely written to. report() paints a HIDDEN panel on the menu
		# path -- _ready() has already built a new game by then, so without this a
		# failed Continue starts a fresh France and says nothing at all.
		_save_load_panel.show()
		_clock.paused = true
		return

	_state = result["state"]
	_clock.year = _state.year
	_clock.month = _state.month
	_clock.day = int(result["day"])
	_clock.paused = true

	_map_view.setup(_loader, _state)
	_minimap.setup(_map_view, _loader, _state)
	_overview_panel.setup(_state, _loader)
	_economy_panel.setup(_state, _loader)
	_budget_panel.setup(_state, _loader)
	_polling_panel.setup(_state)
	_election_panel.setup(_state, _loader)
	_law_panel.setup(_state, _loader)
	_nation_panel.setup(_state, _loader)
	_government_panel.setup(_state, _loader)
	_bloc_panel.setup(_state, _loader)
	_people_panel.setup(_state, _loader)
	_companies_panel.setup(_state, _loader)

	_calendar_panel.setup(_state, _loader)
	# The mirror is re-established here rather than waiting for the first day to
	# elapse, because a loaded game opens PAUSED: without this the diary would
	# refuse a booking for today as "that date has passed" until the player
	# unpaused, which is a rule the player cannot see and did not break.
	_state.day = _clock.day

	_mark_all_dirty()

	_save_load_panel.report("Loaded '%s'." % slot)
	_save_load_panel.mark_dirty()
	_update_top_bar()


## Every panel that reads GameState, marked for one repaint. Extracted at U6a
## from the three places that had grown identical copies of this list -- the
## monthly tick, the load path, and now an appointment resolving on a day nothing
## else happens. A fourth copy is how a panel gets forgotten, and tools/screenshot.gd
## found exactly that class of bug one session ago.
func _mark_all_dirty() -> void:
	for panel in [
		_overview_panel, _economy_panel, _budget_panel, _polling_panel,
		_law_panel, _nation_panel, _government_panel, _bloc_panel, _calendar_panel,
		# `_people_panel` was missing from this list from U6b until V1.4a found it,
		# which is the failure the comment above predicted happening to the panel that
		# was added in the same session the comment was written. It refreshed once, on
		# the frame it was built, and then never again: a censure that changed the head
		# of government, a reshuffle that changed a portfolio and every seat count after
		# an election were all stale on it until the game was reloaded.
		_people_panel, _companies_panel,
	]:
		if panel != null:
			panel.mark_dirty()


## Everything on screen that is not inside a window. Kept under U2's name
## because ~15 call sites already say it and the job is unchanged -- the strip
## simply is not the only always-visible surface any more.
func _update_top_bar() -> void:
	if _top_bar != null:
		_top_bar.refresh(_state, _clock)
	if _hud != null:
		_hud.clock_cluster.refresh(_clock)
		_hud.portrait_card.refresh()
