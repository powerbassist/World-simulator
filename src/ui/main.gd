extends Control

## The at-icons set every window glyph and cluster glyph comes from -- V2.3
## lifted this out of _build_action_bar() because register() now names each
## window's icon too, and the same path constant serves both. Files under it
## are committed individually (git add -f, .gitignore's exception); every one
## src/ references must be, or a fresh clone fails headless.
const ICONS := "res://addons/at-icons/control/"

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")
const GameState = preload("res://src/core/game_state.gd")
const ClockCluster = preload("res://src/ui/clock_cluster.gd")
const Economy = preload("res://src/sim/economy.gd")
const Commodities = preload("res://src/sim/commodities.gd")
const Energy = preload("res://src/sim/energy.gd")
const Regions = preload("res://src/sim/regions.gd")
const Net = preload("res://src/sim/network.gd")
const Region = preload("res://src/core/region.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Statute = preload("res://src/sim/statute.gd")
const Discipline = preload("res://src/sim/discipline.gd")
const Dissolution = preload("res://src/sim/dissolution.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const ForeignPolicyK = preload("res://src/sim/foreign_policy_constants.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const Defence = preload("res://src/sim/defence.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const Companies = preload("res://src/sim/companies.gd")
const Industry = preload("res://src/sim/industry.gd")
const Investment = preload("res://src/sim/investment.gd")
const Projects = preload("res://src/sim/projects.gd")
const Campaign = preload("res://src/sim/campaign.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const Society = preload("res://src/sim/society.gd")
const Demography = preload("res://src/sim/demography.gd")
const Unrest = preload("res://src/sim/unrest.gd")
const Judiciary = preload("res://src/sim/judiciary.gd")
const Characters = preload("res://src/sim/characters.gd")
const Events = preload("res://src/sim/events.gd")
const Media = preload("res://src/sim/media.gd")
const Inflation = preload("res://src/sim/inflation.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Summits = preload("res://src/sim/summits.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Migration = preload("res://src/sim/migration.gd")
const CalendarPanel = preload("res://src/ui/calendar_panel.gd")
const EventArt = preload("res://src/ui/event_art.gd")
const PeoplePanel = preload("res://src/ui/people_panel.gd")
const CompaniesPanel = preload("res://src/ui/companies_panel.gd")
const ProjectsPanel = preload("res://src/ui/projects_panel.gd")
const RegionPanel = preload("res://src/ui/region_panel.gd")
const CommoditiesPanel = preload("res://src/ui/commodities_panel.gd")
const CityPanel = preload("res://src/ui/city_panel.gd")
const EnergyPanel = preload("res://src/ui/energy_panel.gd")
const CampaignPanel = preload("res://src/ui/campaign_panel.gd")
const AgendaPanel = preload("res://src/ui/agenda_panel.gd")
const EventsPanel = preload("res://src/ui/events_panel.gd")
const SummitPanel = preload("res://src/ui/summit_panel.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")
## V4.2 T5. The Tax Code window (the budget panel's tax levers moved there)
## and the bill briefing both surfaces open over a bill.
const TaxPanel = preload("res://src/ui/tax_panel.gd")
const Briefing = preload("res://src/ui/briefing.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const ElectionPanel = preload("res://src/ui/election_panel.gd")
const LawPanel = preload("res://src/ui/law_panel.gd")
const MapView = preload("res://src/ui/map_view.gd")
const Minimap = preload("res://src/ui/minimap.gd")
const MapFlows = preload("res://src/ui/map_flows.gd")
const NationPanel = preload("res://src/ui/nation_panel.gd")
const OrgsPanel = preload("res://src/ui/orgs_panel.gd")
const GovernmentPanel = preload("res://src/ui/government_panel.gd")
const SaveLoadPanel = preload("res://src/ui/save_load_panel.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const PauseMenu = preload("res://src/ui/pause_menu.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const Hud = preload("res://src/ui/hud.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const Pending = preload("res://src/ui/pending.gd")
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
var _paused_for_decision := false
## V4.4: the desk is a queue, so the decision-card machinery tracks a SET. Card id
## -> the event id its buttons answer (the pressed card answers ITS row, not the
## desk's head), and the unseen set is what the arrival pause holds the clock for:
## it clears as the player answers, and the clock resumes when it empties.
var _event_cards := {}        # card id -> event id
var _unseen_events := {}      # event id -> true while the player has not answered
## V4.1. The term-start programme's card and its pause -- the arrival-pause
## machinery pointed at the agenda. See _enforce_term_start_programme().
var _paused_for_programme := false
var _programme_card_id := ""
## The opening "Your term" card. Its countdown ages with the clock, so the id
## is kept and the body is rewritten in place each month -- a stale snapshot
## was playtest finding B4. Empty for a loaded save, which never receives it.
var _term_card_id := ""
var _overview_panel
var _economy_panel
var _budget_panel
var _tax_panel
var _briefing
var _polling_panel
var _election_panel
var _law_panel
var _map_view
var _minimap
var _map_flows
var _nation_panel
var _orgs_panel
var _calendar_panel
var _people_panel
var _companies_panel
var _projects_panel
var _region_panel
var _commodities_panel
var _city_panel
var _energy_panel
var _campaign_panel
var _agenda_panel
var _events_panel
var _summit_panel
var _summit_before := {}
var _government_panel
var _save_load_panel
## Whether the OPEN save dialog was reached from the pause menu (whose hidden
## state `closed` restores) or straight from the top bar (nothing to restore).
var _save_from_menu := false
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
	# The distance table is warmed HERE, not on its first lazy caller: ~2 s once
	# per process is boot cost, while a lazy build makes the player's first
	# month boundary freeze. See network.gd::warm().
	Net.warm(_state.region_graph)
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
	# U6c. A marker opens Public Works rather than saying anything itself: the map
	# says *where* a project is, and the panel already says everything else about
	# it. Registered further down, so this connects to a window that exists by the
	# time a click can happen.
	_map_view.project_clicked.connect(func(_project_id: String):
		_windows.open("projects")
	)
	# V2.2b, the register's own route. The cross names the city; the panel says
	# everything else about it. show_city() BEFORE open(), _on_nation_clicked's
	# order, so the content settles before the window sizes itself around it.
	# Same "registered further down" note as above applies.
	_map_view.city_clicked.connect(func(city_id: String):
		_city_panel.show_city(city_id)
		_windows.open("city")
	)

	# V3.4. Above the map and below the windows: the flows are drawn ON the map,
	# and a panel the player opened must still cover them. Its mouse filter is
	# IGNORE (map_flows.gd's _ready() sets it and tests/test_map_flows.gd asserts
	# it) so a full-rect control over the whole game takes no clicks -- V3.3f
	# shipped exactly that bug through a CenterContainer's default of PASS and it
	# sat behind a green suite for a tier.
	_map_flows = MapFlows.new()
	_map_flows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_map_flows)
	_map_flows.setup(_map_view, _clock, _loader, _state)

	_windows = WindowManager.new()
	add_child(_windows)

	_hud = Hud.new()
	add_child(_hud)
	_top_bar = _hud.top_bar
	_hud.ribbon.setup(_state, _loader)

	# set_minimap() puts it in the tree, so setup() comes after -- the same
	# register()-before-setup() ordering every window below follows, and for the
	# same reason: a Control outside the tree has not run _ready().
	_minimap = Minimap.new()
	_hud.clock_cluster.set_minimap(_minimap)
	_minimap.setup(_map_view, _loader, _state)

	# register() before setup(), every time. register() is what puts the panel in
	# the tree, and a Control outside the tree has not run _ready(), so every
	# label setup() writes to is still null -- AGENTS.md's gotcha, and the same
	# order dashboard.gd's add_tab() enforced by doing both itself.
	_overview_panel = OverviewPanel.new()
	_windows.register("overview", "Overview", _overview_panel, KEY_O, ICONS + "gauge.svg")
	_overview_panel.setup(_state, _loader)

	# V4.1. The government's programme: the one window where a programme is
	# chosen and tracked (docs/programme-model.md §4). In the State cluster
	# beside the Overview it frames -- the agenda is what the term is FOR,
	# which is the sentence the Overview's other columns read against.
	_agenda_panel = AgendaPanel.new()
	_windows.register("agenda", "Agenda", _agenda_panel, KEY_K, ICONS + "target.svg")
	_agenda_panel.setup(_state, _loader)
	_agenda_panel.programme_chosen.connect(_on_programme_chosen)

	_economy_panel = EconomyPanel.new()
	_windows.register("economy", "Economy", _economy_panel, KEY_E, ICONS + "pie_chart.svg")
	_economy_panel.setup(_state, _loader)

	# hide_close_button() still applies: these panels each build their own Close
	# button for the life they had before U2 docked them, and the window frame
	# now provides the real one. Two close buttons on one panel is worse than
	# either.
	_budget_panel = BudgetPanel.new()
	_windows.register("budget", "Budget", _budget_panel, KEY_B, ICONS + "briefcase.svg")
	_budget_panel.setup(_state, _loader)
	_budget_panel.hide_close_button()
	_budget_panel.committed.connect(func(before, pending):
		_queue_effect("Budget change", before)
		# The acknowledgment the playtest found missing: the biggest verb in the
		# game used to answer with one corner number changing (F3).
		_hud.message_stack.push("Budget committed", "Deficit now %.2f%% of GDP." % float(_state.player().deficit_pct_gdp))
		_update_top_bar()
	)

	# V4.2 T5. The tax levers' new home, in the Economy cluster beside Budget:
	# the cluster grammar (panel-system.md §16) puts a surface where its
	# decision lives, and a tax rate is a budget-domain decision -- but a
	# separate DOMAIN from spending, which is why it is its own window and
	# not a row. KEY_X was the one letter left. The commit is Budget.commit()
	# -- the same verb the budget panel sends -- so the demand impulse, the
	# erosion curve and the books have one entry point however many windows
	# move a rate.
	_tax_panel = TaxPanel.new()
	_windows.register("tax", "Tax Code", _tax_panel, KEY_X, ICONS + "coins.svg")
	_tax_panel.setup(_state, _loader)
	_tax_panel.hide_close_button()
	# V4.2 ultra pass 2: the budget panel's proposed column and 24-month
	# projection price the Tax Code window's uncommitted edits (the panels are
	# siblings; this is a reference, not state, and the load path's setup()
	# sweep leaves it alone).
	_budget_panel.tax_panel = _tax_panel
	_tax_panel.committed.connect(func(before, pending):
		_queue_effect("Tax code change", before)
		_hud.message_stack.push("Tax code committed", "Deficit now %.2f%% of GDP." % float(_state.player().deficit_pct_gdp))
		_update_top_bar()
	)
	# A finished draft opens the briefing on itself: the price it was quoted
	# and the drafting months are what the press just bought.
	_tax_panel.brief_requested_draft.connect(func(entry, draft_id):
		_briefing.open_for_draft(entry, draft_id, _state, _loader)
		_briefing.show()
	)

	# V4.2 T5. The bill briefing, over every bill the player can put to the
	# assembly. Not a window in the registry: it is not a surface the player
	# navigates to, it is what opens when a bill is asked for -- the summit's
	# shape, one verb earlier in the same day. The division routes back
	# through law_panel.run_proposal() so the propose path, its card and its
	# U4 baseline stay in one place whichever surface pressed the button.
	# (The law panel's own brief_requested lands beside its proposed handler
	# below -- the panel does not exist yet at this point in _ready().)
	_briefing = Briefing.new()
	_add_centered(_briefing)
	_briefing.hide()
	_briefing.propose_requested.connect(func(law):
		_briefing.hide()
		_law_panel.run_proposal(law)
	)
	_briefing.polled.connect(func(before, label):
		_queue_effect(String(label), before)
		# The forecast the purchase sharpens is the law panel's read.
		_law_panel.mark_dirty()
		_update_top_bar()
	)

	_government_panel = GovernmentPanel.new()
	_windows.register("politics", "Politics", _government_panel, KEY_G, ICONS + "cog.svg")
	_government_panel.setup(_state, _loader)
	_government_panel.hide_close_button()
	_government_panel.dissolved.connect(func(before):
		_queue_effect("Dissolution called", before)
	)
	_government_panel.reassigned.connect(func(before):
		_queue_effect("Cabinet reassigned", before)
	)

	_polling_panel = PollingPanel.new()
	_windows.register("society", "Society", _polling_panel, KEY_P, ICONS + "speech_bubble.svg")
	# Loader from the start: the countdown names the chamber off the loader's
	# own titles, and a boot without it printed the generic "assembly" until
	# the first load put the two out of agreement.
	_polling_panel.setup(_state, _loader)
	_polling_panel.hide_close_button()

	_law_panel = LawPanel.new()
	_windows.register("legislature", "Legislature", _law_panel, KEY_L, ICONS + "scales.svg")
	_law_panel.setup(_state, _loader)
	_law_panel.hide_close_button()
	# V4.2 T5. Propose opens the briefing; the division comes back through
	# run_proposal() from the briefing's own verb, so the path below is still
	# the one propose path in the game.
	_law_panel.brief_requested.connect(func(law):
		_briefing.open_for_law(law, _state, _loader)
		_briefing.show()
	)
	_law_panel.proposed.connect(func(before, law_name, result):
		_queue_effect(String(law_name), before)
		var body: String
		if bool(result.get("refused", false)):
			if bool(result.get("referendum_in_flight", false)):
				body = "A referendum is already in flight."
			else:
				body = "The assembly would not take it."
		elif bool(result.get("withdrawn", false)):
			body = "Withdrawn."
		elif bool(result.get("referendum_route", false)):
			body = "To the country -- the vote is scheduled."
		else:
			body = "%s. Yes %d, No %d." % [
				"Passed" if bool(result.get("passed", false)) else "Failed",
				int(result.get("yes_seats", 0)), int(result.get("no_seats", 0)),
			]
		_hud.message_stack.push(String(law_name), body)
		_update_top_bar()
	)

	# The nation panel loses its side-by-side pane and becomes what it always
	# behaved like: a card about whichever country was clicked. Opened by
	# _on_nation_clicked(), and reachable from the World cluster as well so the
	# diplomatic verbs are not hidden behind knowing to click the map.
	_nation_panel = NationPanel.new()
	_windows.register("diplomacy", "Diplomacy", _nation_panel, KEY_D, ICONS + "hand.svg")
	_nation_panel.setup(_state, _loader)
	_nation_panel.hide_close_button()
	# The same three lines _law_panel.proposed gets -- a diplomatic action is a
	# player command with a domestic price, so it earns a U4 decision delta on
	# exactly the same terms a law does.
	_nation_panel.acted.connect(func(before, label, result):
		_queue_effect(String(label), before)
		var body: String
		if bool(result.get("refused", false)):
			var reason := String(result.get("reason", ""))
			body = "Refused." if reason.is_empty() else "Refused. %s" % reason
		else:
			body = "Agreed."
		_hud.message_stack.push(String(label), body)
		_update_top_bar()
		# A diplomatic action moves relations, and on the relations layer that is a
		# colour change the player should see the moment they act rather than at
		# the next month's tick.
		_map_view.queue_redraw()
		# And a tariff or an agreement moves the trade weights the arcs are drawn
		# from, on the same press and for the same reason -- the overlay caches
		# them, so without this the arcs keep their pre-action widths until the
		# month rolls over.
		if _map_flows != null:
			_map_flows.refresh()
	)

	# V1.3d. Beside Diplomacy in the World cluster, and its own window rather than
	# a section of the nation panel: the council is not a nation and has no pixel
	# on the map to click, so there is nothing to select it by.
	_orgs_panel = OrgsPanel.new()
	_windows.register("orgs", "Organisations", _orgs_panel, KEY_U, ICONS + "book_open.svg")
	_orgs_panel.setup(_state, _loader)
	_orgs_panel.hide_close_button()
	# V1.6 audit, V8. A council vote binds the player whichever way it goes, so it
	# is a command like any other and earns the same U4 delta as a law or an act.
	# It was the only one of the seven player commands with no signal at all.
	_orgs_panel.voted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
	)
	_orgs_panel.acted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
	)

	# U6a. The one surface that reads dated state the game has carried since the
	# MVP and never showed anywhere -- an election date, the council's next
	# proposal, every cooldown expiry -- and the only place a booking is made.
	_calendar_panel = CalendarPanel.new()
	_windows.register("calendar", "Diary", _calendar_panel, KEY_C, ICONS + "calendar.svg")
	_calendar_panel.setup(_state, _loader)
	_calendar_panel.hide_close_button()
	# A booking commits nothing this month, so unlike `acted` and `proposed` there
	# is no baseline to queue. The repaint is all this needs: the diary is the only
	# panel whose contents just changed -- and the ribbon occupies the same days,
	# so a booking repaints both halves of the one surface that just moved.
	_calendar_panel.diary_changed.connect(func():
		_calendar_panel.mark_dirty()
		_hud.ribbon.mark_dirty()
	)

	# U6b. Read-only, and the only surface that shows the whole register rather
	# than the one person a given screen happens to be about.
	_people_panel = PeoplePanel.new()
	_windows.register("people", "People", _people_panel, KEY_R, ICONS + "clipboard.svg")
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
	_windows.register("companies", "Industry", _companies_panel, KEY_I, ICONS + "factory.svg")
	_companies_panel.setup(_state, _loader)
	_companies_panel.hide_close_button()
	# The same three lines _law_panel.proposed and _nation_panel.acted get. A
	# subsidy is a player command with a domestic price and a budget line, so it
	# earns a U4 decision delta on exactly the same terms.
	_companies_panel.acted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
	)

	# V1.6f. In the Economy cluster beside Industry, and its OWN window rather than
	# more rows on that one: a project is a dated national commitment and that panel
	# is grouped by sector, with a body already guaranteed to overflow. Registering a
	# window is one call plus one line in _build_action_bar(), which is what U5a's
	# shell was for.
	_projects_panel = ProjectsPanel.new()
	_windows.register("projects", "Public Works", _projects_panel, KEY_W, ICONS + "road.svg")
	_projects_panel.setup(_state, _loader)
	_projects_panel.hide_close_button()
	_projects_panel.acted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
	)

	# V2.2b. In the Economy cluster beside Public Works, on docs/panel-system.md
	# §16's rule that a cluster is the domain of the decision: the tier's own claim
	# is that §5 makes the economy regional, so the surfaces that partition the
	# country belong where that decision will live. Read-only -- no verb exists on
	# a region until §5 -- so no acted signal, people_panel's shape rather than
	# projects_panel's.
	_region_panel = RegionPanel.new()
	_windows.register("region", "Regions", _region_panel, KEY_T, ICONS + "map.svg")
	_region_panel.setup(_state, _loader)
	_region_panel.hide_close_button()

	# V4.6. Task 4's read-only surface over the commodity layer, in the Economy
	# cluster beside the region and city registers -- panel-system.md §16's rule
	# that a cluster is the domain of the decision, and this is the same one: what
	# the country makes, wants and buys in is an economic reading, not a
	# diplomatic one. Read-only (no acted signal, people_panel's shape): Task 4
	# ships no verb, so there is nothing here a button could do, and the two map
	# modes are reached through the legend's own switcher because they are
	# registry entries -- a second mode control on this panel would be the
	# hand-written list V2.1a spent a block deleting.
	#
	# KEY_H rather than a mnemonic: C is the Diary, K the Agenda, M the map clear,
	# S the save dialog and G Politics, so every letter this window's name
	# suggests was already taken. H was free and is used for nothing else, which
	# is the whole criterion -- the drawer's tooltip and the key press both read
	# it off this one call.
	_commodities_panel = CommoditiesPanel.new()
	_windows.register("commodities", "Commodities", _commodities_panel, KEY_H, ICONS + "crate.svg")
	_commodities_panel.setup(_state, _loader)
	_commodities_panel.hide_close_button()

	# V2.2b, one level down, and the only V2 surface whose drawer entry is the
	# SECOND way in: the map's cross is the route, and this entry is for the
	# player who does not know that -- §16's own wording.
	_city_panel = CityPanel.new()
	_windows.register("city", "Cities", _city_panel, KEY_V, ICONS + "building.svg")
	_city_panel.setup(_state, _loader)
	_city_panel.hide_close_button()

	# V2.8. KEY_F for fuel: E is Economy, N is Dispatches and G is Politics, so the
	# obvious letters were gone. The key rides register() itself -- V2.1c deleted the
	# seventh hand-written list of panel ids to get here, and the drawer's tooltip
	# reads the letter off the registry rather than restating it.
	_energy_panel = EnergyPanel.new()
	_windows.register("energy", "Energy", _energy_panel, KEY_F, ICONS + "lightning_bolt.svg")
	_energy_panel.setup(_state, _loader)
	_energy_panel.hide_close_button()
	_energy_panel.acted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
	)
	# V2.8. The panel says WHICH action is armed; main.gd holds the map and the
	# loader and does the resolving. The panel never learns that a map exists,
	# which is the same boundary Budget.commit() draws for player intent.
	_energy_panel.order_armed.connect(_on_energy_order_armed)
	_map_view.map_point_picked.connect(_on_map_point_picked)
	_map_view.plant_clicked.connect(func(plant_id: String):
		_windows.open("energy")
		_energy_panel.scroll_to_fleet()
	)

	# V1.7a. In the State cluster beside the Diary, and its OWN window rather than rows
	# on the Polling panel: that panel's contract is that every figure on it has been
	# through PollNoise, and a mobilisation figure the government is paying for is not a
	# poll -- docs/society-model.md section 11's argument for moving the delivery readout
	# off it, one block later.
	_campaign_panel = CampaignPanel.new()
	_windows.register("campaign", "Campaign", _campaign_panel, KEY_A, ICONS + "megaphone.svg")
	_campaign_panel.setup(_state, _loader)
	_campaign_panel.hide_close_button()
	_campaign_panel.acted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
	)

	# V1.8. In the State cluster beside the Diary, and its own window rather than rows
	# on any existing panel. Registering one is one call plus one line in
	# _build_action_bar(), which is what U5a's shell was for -- and the reason it is a
	# window rather than a modal is in the panel's own header: a crisis the player can
	# ignore and pay for is the whole of the deadline.
	_events_panel = EventsPanel.new()
	_windows.register("events", "Dispatches", _events_panel, KEY_N, ICONS + "envelope.svg")
	_events_panel.setup(_state, _loader)
	_events_panel.hide_close_button()
	_events_panel.acted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
		# V4.4: the panel answers by id (Events.answer), so a panel answer must
		# clear the arrival pause exactly like a card answer: ids that left the
		# desk are answered (or expired), ids still on it keep the clock held,
		# and the set is never re-grown here -- an entry that never had an
		# arrival card (a loaded save) holds the clock through the interrupt
		# path, not this one. Before V4.4 this path never resumed the clock at
		# all and the player unpaused by hand.
		var ns_after = _state.player()
		if ns_after != null:
			var still_on := {}
			for entry in ns_after.event_queue:
				still_on[String(entry.get("event_id", ""))] = true
			for unseen_id in _unseen_events.keys().duplicate():
				if not still_on.has(unseen_id):
					_unseen_events.erase(unseen_id)
					_dismiss_event_cards(unseen_id)
		_resume_if_decision_settled()
		_windows.mark_all_dirty()
	)

	# V2.4b. The summit scene, chained off V2.4a's meeting arrival. NOT in the
	# drawer and not in a cluster: a summit is not a surface the player navigates
	# to, it is what happens when a state visit lands -- the one window that
	# opens ITSELF, which is why it sits beside the modal four in spirit while
	# still being closable. The panel returns the choice it played; the effects
	# apply HERE through the applier the events path already uses, and the U4
	# baseline is taken before the panel ever opens, because a choice made over
	# dinner is a command with a delta like any other.
	_summit_panel = SummitPanel.new()
	_windows.register("summit", "Summit", _summit_panel, KEY_NONE, ICONS + "institutional_building.svg")
	_summit_panel.setup(_state, _loader)
	# No hide_close_button(): the frame's X is a live exit -- a summit walked
	# out on applies nothing, which is the ephemeris working, not a bug.
	_summit_panel.concluded.connect(func(_summit_id, choice_label):
		_resolve_summit(choice_label)
		# The scene is over, so the window goes with it. Nothing closed "summit"
		# until the V2.8 review -- the id appeared only at register() and open() --
		# so a played-out summit left a blank plate on screen as its only signal
		# that anything had happened.
		_windows.close("summit")
	)

	_build_action_bar()
	_wire_hud()

	# Four panels stay modal, not docked: election results and censure land on
	# the player regardless of which tab is open, and settings/save-load are
	# reached through the pause menu rather than the rail.
	_election_panel = ElectionPanel.new()
	_add_centered(_election_panel, true)
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
		if not _decision_holds_clock():
			_clock.paused = false
		# V4.1. A won election that started a new term left the choice open,
		# and the dismissal must not quietly resume past it. A no-op when
		# there is nothing to choose.
		_enforce_term_start_programme()
	)

	_save_load_panel = SaveLoadPanel.new()
	_add_centered(_save_load_panel)
	_save_load_panel.hide()
	_save_load_panel.save_requested.connect(_on_save_requested)
	_save_load_panel.load_requested.connect(_on_load_requested)
	# The settings panel's own contract (three lines up): closing a panel the
	# pause menu opened puts the menu back, or the player is stranded outside
	# the flow that paused the clock. Only when the menu opened it -- the top
	# bar's SAVE reaches the same panel with no menu to restore.
	_save_load_panel.closed.connect(func():
		if _save_from_menu:
			_set_pause_menu_visible(true)
		_save_from_menu = false
	)

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
		_save_from_menu = true
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

	# The one sentence the playtest found missing: a new game opens on a running
	# clock with nothing pending and no statement of what is being played for,
	# and the deadline lived four clicks deep -- when it was stated at all. The
	# opening card carries it in the stack's own voice, counted by the same
	# Trends query the top bar and the Overview count by. It sits AFTER the load
	# branch and inside the new-game case, so a loaded save never receives it.
	if pending_load_slot.is_empty():
		_term_card_id = _hud.message_stack.push("Your term", _term_card_body())

	# V4.1, after the opening card so the two land together: a new game IS an
	# unchosen term start, so the clock sits still behind the programme choice
	# until one is made. The load branch above already ran its own enforcement,
	# and this call is idempotent -- one live card either way.
	_enforce_term_start_programme()

	# AFTER the enforcement, matching the load path's own order: the programme
	# card names "agenda" in Pending.window_ids, and at boot the clock is paused
	# with no month tick to refresh the strip later -- a bar built before the
	# enforcement would leave the State-cluster mark dark on a decision the
	# desk is actively holding open.
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
	_hud.action_bar.add_cluster("state", "State", ICONS + "institutional_building.svg", [
		_entry("overview", "Overview"),
		# V4.1. The term's programme, right after the Overview it frames -- a
		# president deals with what the term is for before the machinery.
		_entry("agenda", "Agenda"),
		_entry("politics", "Politics"),
		_entry("legislature", "Legislature"),
		# A president's diary is state. One line, exactly as the comment above
		# this function predicted three sessions ago.
		_entry("calendar", "Diary"),
		# A president's people are state too, by the same argument the diary took.
		_entry("people", "People"),
		# V1.7a. One line, exactly as this function's own comment has now correctly
		# predicted for six sessions running.
		_entry("campaign", "Campaign"),
		# V1.8, and the seventh session running. What arrives on a president's desk
		# without being asked for is state, by the same argument the diary and the
		# people took.
		_entry("events", "Dispatches"),
	])
	_hud.action_bar.add_cluster("economy", "Economy", ICONS + "coins.svg", [
		_entry("economy", "Economy"),
		_entry("budget", "Budget"),
		# V4.2 T5. Beside Budget, its own window rather than rows on it: the
		# tier moved tax out of the Budget panel, and the cluster grammar puts
		# the surface where its decision lives.
		_entry("tax", "Tax Code"),
		# V1.4a. One line, exactly as this function's own comment has now correctly
		# predicted for four sessions running.
		_entry("companies", "Companies"),
		# V1.6f. One line, exactly as this function's own comment has now correctly
		# predicted for five sessions running.
		_entry("projects", "Public Works"),
		# V2.2b, and two lines where the streak said one: the register's two
		# surfaces land together because they are one partition seen from two
		# heights, and Economy is their home because §5 is about to make the
		# economy regional.
		_entry("region", "Regions"),
		_entry("city", "Cities"),
		# V4.6 Task 4, and the fourth line this function's streak has predicted.
		# The tier's own grammar puts it here: what the country makes and buys in
		# is the same domain of decision as the two registers beside it.
		_entry("commodities", "Commodities"),
		# V2.8, and the grammar is V2.1c's: a cluster is the domain of the decision
		# rather than the shape of the object, and AGENTS.md already carries the
		# ruling -- region, city and energy are Economy.
		_entry("energy", "Energy"),
	])
	_hud.action_bar.add_cluster("society", "Society", ICONS + "human.svg", [
		_entry("society", "Polling"),
	])
	_hud.action_bar.add_cluster("world", "World", ICONS + "globe.svg", [
		_entry("diplomacy", "Diplomacy"),
		_entry("orgs", "Organisations"),
	])
	_hud.action_bar.panel_requested.connect(func(id: String): _windows.open(id))


## One entry in a cluster's drawer. The shortcut AND the icon are READ OFF THE
## REGISTRY rather than written here -- V2.1c and V2.3 -- so the letter on the
## tooltip, the letter the key press uses and the glyph beside the name cannot
## disagree with the window's own registration, which is the same reason
## `bloc_offset` is read from the content rather than restated in the agenda.
func _entry(id: String, label: String) -> Dictionary:
	var key: int = _windows.shortcut(id)
	return {
		"id": id,
		"label": label,
		"key": "" if key == KEY_NONE else OS.get_keycode_string(key),
		"icon": _windows.icon_path(id),
	}


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
		_save_from_menu = false
		_save_load_panel.show()
		_save_load_panel.mark_dirty()
	)
	_hud.top_bar.settings_requested.connect(_open_pause_menu)
	_hud.portrait_card.setup(_state, _loader)

	# V2.1c, and the FIRST CONSUMERS of two signals window_manager.gd has emitted
	# since U5a. The bar was the only route that marked itself: a keypress, a map
	# marker (U6c) and a message card (V1.8) each opened a window while the one
	# control that says where you are went on saying nothing. On close the mark
	# moves to whatever is still open rather than clearing, because a pinned
	# window is still where the player is.
	_windows.opened.connect(func(id: String): _hud.action_bar.show_active(id))
	_windows.closed.connect(func(_id: String):
		var still_open: Array = _windows.open_ids()
		if still_open.is_empty():
			_hud.action_bar.clear_active()
		else:
			_hud.action_bar.show_active(String(still_open[0]))
	)

	# V1.8, and the first thing ever to connect this signal. message_stack.gd has
	# emitted card_activated since U5a and nothing has listened, because until now every
	# card was a NOTIFICATION -- a foreign act, an obligation opening, a strike, a kept
	# appointment -- and there was nowhere for a click to go. An event card is a
	# QUESTION, so clicking it opens the window where it is answered. Every card routes
	# here and the window is right for all of them: whatever the player clicked, what
	# they wanted was the decision on their desk. V4.1's programme card routes to the
	# window where that choice is made instead -- the same rule, one card earlier.
	_hud.message_stack.card_activated.connect(func(id: String):
		if not _programme_card_id.is_empty() and id == _programme_card_id:
			_windows.open("agenda")
			return
		# V4.7b: an industry card routes to the window where its verbs live.
		# (Focus-by-firm was deferred twice -- B2 to B3, and B3 shipped its
		# surfaces without it -- so it is an OPEN DEFERRAL, not a promise:
		# the click gets the player to the register, whose autonomy sections
		# surface the pending bid or failing firm. Recorded per the plan's
		# own rule, that a deferral is a decision and not a discovery.)
		if _industry_card_firms.has(id):
			_windows.open("companies")
			return
		_windows.open("events")
	)

	# V2.9 + V4.4: a decision card's buttons answer the event THAT CARD names --
	# the same Events.answer chain Dispatches uses, with U4's before-snapshot
	# contract -- and the clock the arrival paused resumes only when nothing the
	# player has not seen is still on the desk. Only decision cards carry
	# buttons, so any card_action is a decision answer by construction.
	_hud.message_stack.card_action.connect(func(id: String, index: int):
		var ns = _state.player()
		var event_id := String(_event_cards.get(id, ""))
		var ev = Events.event_by_id(_loader, event_id) if event_id != "" else null
		if ev == null or index >= ev.choices.size():
			return
		var before := Budget.snapshot(_state)
		var record := Events.answer(_state, _loader, event_id, String(ev.choices[index]["id"]))
		if record.is_empty():
			return
		_queue_effect("%s: %s" % [String(ev.event_name), String(ev.choices[index]["label"])], before)
		_event_cards.erase(id)
		_unseen_events.erase(event_id)
		_hud.message_stack.dismiss(id)
		_resume_if_decision_settled()
		_update_top_bar()
		_windows.mark_all_dirty()
	)

	# The unseen set's second door. An X on a decision card -- and the MAX_CARDS
	# eviction, which dismisses through the same signal -- used to strand the
	# event's id in _unseen_events: only an ANSWER erased it, so the arrival
	# pause could outlive every answer and hold the clock over an empty set. The
	# invariant, stated once across all its doors: AN ID LEAVES _unseen_events
	# WHEN IT LEAVES THE DESK OR ITS CARD IS DISMISSED. An id already taken off
	# the maps (the answer path above dismisses its own card after erasing)
	# falls through as "": both erases are no-ops and the resume is idempotent,
	# so this re-entry is harmless by construction.
	_hud.message_stack.card_dismissed.connect(func(id: String):
		var event_id := String(_event_cards.get(id, ""))
		_event_cards.erase(id)
		_unseen_events.erase(event_id)
		_resume_if_decision_settled()
	)

	# U5c. The legend proposes a layer, the map view holds it, and the legend is
	# then told what it now shows -- one direction, so the two cannot disagree
	# about which layer is up.
	_hud.map_legend.layer_selected.connect(func(id: String):
		_map_view.set_layer(id)
		_hud.map_legend.show_layer(_map_view.layer(), _state, _map_view.viewer_id())
	)
	_map_view.nation_hovered.connect(func(id: String):
		_hud.map_legend.show_hover(id, _state, _map_view.viewer_id())
	)


func _add_centered(panel: Control, blocking := false) -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not blocking:
		holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		# A term result is the one modal moment: dim the world behind it so the
		# verdict owns the screen, and eat clicks -- the election already paused
		# the clock; the backdrop makes the map agree (V2.9). The dim is a
		# SIBLING of the holder, not a child: a CenterContainer collapses a
		# full-rect child to its minimum size. Added before the holder so it
		# draws below the panel and above everything added earlier (the map,
		# the windows), with the HUD -- added later -- still readable above it.
		# It follows the panel's visibility, so every existing show()/hide()
		# call site keeps working unchanged.
		var dim := ColorRect.new()
		dim.color = Color(0.02, 0.03, 0.05, 0.55)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_STOP
		dim.visible = false
		add_child(dim)
		# The HOLDER follows the panel too, not just the dim. A Container
		# defaults to MOUSE_FILTER_PASS, so a full-rect blocking holder goes on
		# taking every click on the screen while the panel inside it is
		# invisible -- which is exactly what V2.9 shipped when it made the
		# election panel blocking: `_election_panel.hide()` hid the panel, the
		# holder stayed up, and a new game was dead to the mouse from its first
		# frame. `_set_pause_menu_visible()` had been hiding its own holder by
		# hand for that reason since U5a; doing it here means the next blocking
		# panel cannot forget -- and that call site now sets the PANEL only,
		# because a second writer would be reverted by this one: hiding the
		# holder re-emits visibility_changed on the panel while the panel's own
		# flag is still true, and this handler would put the holder back.
		panel.visibility_changed.connect(func():
			dim.visible = panel.visible
			holder.visible = panel.visible
		)
	holder.add_child(panel)
	add_child(holder)


## The panel alone -- `_add_centered()`'s blocking branch owns the holder and the
## dim, and it is the ONLY owner. Setting the holder here as well used to be the
## fix for a blocking CenterContainer that goes on swallowing map clicks while
## the panel inside it is invisible; now it would be a write the panel's own
## visibility_changed handler immediately reverts, because hiding a holder
## re-emits on the panel while the panel's own flag is still true. One writer,
## so the two cannot disagree and the order of two lines cannot decide whether
## the screen is clickable.
##
## `_unhandled_input()` still reads the HOLDER to ask whether the menu is open.
## That stays true: the holder now mirrors the panel by construction.
func _set_pause_menu_visible(shown: bool) -> void:
	_pause_menu.visible = shown


func _open_pause_menu() -> void:
	_paused_before_menu = _clock.paused
	_clock.paused = true
	_set_pause_menu_visible(true)
	_update_top_bar()


func _close_pause_menu() -> void:
	_set_pause_menu_visible(false)
	_settings_panel.hide()
	# Resume restores the clock the player had; a save loaded THROUGH the menu
	# folds its re-raised holds into the snapshot (_note_holds_for_pause_menu),
	# so a player who unpaused by hand over a pending interrupt keeps that choice.
	_clock.paused = _paused_before_menu
	_update_top_bar()


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return

	# B16 (playtest): with the save dialog open, every letter here was routed
	# straight at the windows behind it -- or typed into the dialog's name field
	# once it held focus -- and Escape did nothing. While the dialog is visible
	# the panel-hotkey branch is skipped (the toggle in the match below still
	# runs, so S keeps closing it) and Escape closes the dialog first, before
	# anything else in the match can eat the key.
	var save_dialog_open: bool = _save_load_panel != null and _save_load_panel.visible

	# V2.1c. The six letters U2 bound to tabs still open the six panels they
	# opened, and the other eight windows have a letter now -- but the map from
	# key to window lives at the register() call rather than in a match block
	# here, so the eight that were added since U5a could not have been left out.
	# A key TOGGLES rather than selects, because with no rail there is nothing
	# showing which panel is "current": pressing B twice puts the player back on
	# the map.
	if not save_dialog_open and _windows != null:
		var by_key: String = _windows.id_for_key(event.keycode)
		if not by_key.is_empty():
			_toggle_window(by_key)
			return

	match event.keycode:
		KEY_ESCAPE:
			# B16: the open save dialog is the topmost thing Escape can mean.
			# Checked before the armed placement and the pause menu. A placement
			# CAN be armed with the dialog open (its holder is
			# MOUSE_FILTER_IGNORE, so the map under it stays clickable) -- the
			# ordering is a choice, not an impossibility: this press closes the
			# dialog, the reticle survives it and dies on the next Escape.
			if save_dialog_open:
				# close() rather than a bare hide: the pause-menu restore hangs
				# off `closed`, and this path must not strand the menu behind.
				_save_load_panel.close()
				return
			# V2.8. An armed placement cancels FIRST and the pause menu never
			# opens -- Escape ending the thing it was offered for is the mode's
			# own contract, and a pause menu over a waiting reticle is a second
			# modal answering for the first.
			if _armed_energy_action != "":
				_armed_energy_action = ""
				_energy_panel.clear_armed()
				_map_view.end_placement()
				return
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
		KEY_M:
			# M was the Europe tab. The map is now always underneath, so the
			# useful thing that key can do is clear everything off it.
			if _windows != null:
				_windows.close_all()
			if _hud != null:
				_hud.action_bar.close_subrow()
		KEY_S:
			if _save_load_panel != null:
				if _save_load_panel.visible:
					_save_load_panel.close()
				else:
					_save_from_menu = false
					_save_load_panel.show()
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
## The panel armed a technology; the map is now waiting for the point.
var _armed_energy_action: String = ""


func _on_energy_order_armed(action_id: String) -> void:
	_armed_energy_action = action_id
	_map_view.begin_placement()


## THE POINT MUST LAND IN THE PLAYER'S OWN COUNTRY, and the refusal is loud rather
## than silent: a click in Germany while governing France is a mistake, and a verb
## that quietly does nothing is V1.3e's treaty button that refused silently and
## rendered as live.
func _on_map_point_picked(lon: float, lat: float) -> void:
	if _armed_energy_action == "":
		return
	var action_id := _armed_energy_action
	_armed_energy_action = ""
	_energy_panel.clear_armed()
	var region_id := Region.region_at_lonlat(_loader.region_rings, lon, lat)
	var ns = _state.nations[_state.player_nation_id]
	var mine := false
	for region in _state.regions.get(_state.player_nation_id, []):
		if region.id == region_id:
			mine = true
	if not mine:
		# push(title, body) -- MessageStack has never had a push_card(), so until the
		# V2.8 review this line raised instead of speaking, and the refusal the
		# comment above calls "loud rather than silent" reached the player as a
		# console error. The order is already consumed by here (the arm was cleared
		# above and map_view ended placement), so with nothing on screen the player
		# had to re-arm without being told why.
		_hud.message_stack.push(
			"Not your ground", "That point is not in %s." % ns.nation_name)
		return

	var access: Dictionary = Regions.accessibility_for(
		ns, _state.regions.get(ns.id, []), _state.region_graph)
	var pop_weights: Dictionary = {}
	for region in _state.regions.get(ns.id, []):
		pop_weights[region.id] = Migration.region_share(ns, region.id)

	var action = null
	for a in _loader.energy_actions:
		if a.id == action_id:
			action = a
	if action == null:
		return
	# The snapshot is taken BEFORE execute(), which is what a decision delta is.
	# Ordering a station is a player command with a multi-year budget line, so it
	# earns the same U4 entry a subsidy, a law and a project each get -- it had
	# neither this nor the top-bar refresh until the V2.8 review, so the one energy
	# verb the player reaches through the MAP was missing from Overview's recent
	# decisions while the panel's own decommission route was not.
	var before := Budget.snapshot(_state)
	var result := Energy.execute(_state, ns, _loader, _loader.energy_actions, action,
		Vector2(lon, lat), region_id, "", access, pop_weights)
	if bool(result.get("applied", false)):
		_queue_effect(action.action_name, before)
	_windows.mark_all_dirty()
	_map_view.queue_redraw()
	_update_top_bar()


func _on_month_elapsed(year: int, month: int) -> void:
	if _state == null:
		return
	_state.year = year
	_state.month = month
	# V2.8. The accessibility index per nation, built here because energy.gd never
	# learns that a graph exists. Same index Regions already computes, so the
	# Dijkstra rows are served from network.gd's own per-graph cache and this
	# costs a lookup. Immediately BEFORE Economy, because economy.gd READS
	# ns.energy_impulse_pct rather than computing it -- an energy tick placed after
	# the economy would price this month's mix against last month's growth, a
	# one-month lag in a channel with no reason to have one.
	var access_by_nation: Dictionary = {}
	for nation_id in _state.nations.keys():
		access_by_nation[nation_id] = Regions.accessibility_for(
			_state.nations[nation_id], _state.regions.get(nation_id, []), _state.region_graph)
	Energy.tick_month(_state, _loader, access_by_nation)
	Economy.tick_month(_state)
	# V4.6. Immediately AFTER Economy, from which it derives every nation's capacity
	# off the `sector_output` that call just settled -- a tick before it would price
	# this month's production off last month's mix. BEFORE Opinion, so a figure this
	# layer writes can be read in the SAME month rather than a month late: Inflation's
	# slot and Orgs' rule, both stated at their own calls below.
	#
	# Since V4.4 the register HAS a live sim reader: the events machine's
	# commodity_price_high hook reads `ns.commodity_state` inside Events.tick_month,
	# which runs AFTER this slot -- so the same-month read this slot exists for now
	# has its consumer, and the order is load-bearing where V4.6 could only pin it.
	# Said out loud because that is exactly when an order rots: tests/test_events.gd's
	# `_test_tick_order_pin` is what stops a later task placing Events before these
	# four modules by convenience -- its five hooks read registers Commodities,
	# Orgs, Statute and Industry wrote this same tick (the pin in
	# tests/test_commodities.gd holds only Economy < Commodities < Opinion).
	Commodities.tick_month(_state, _loader)
	Budget.tick_month(_state)
	# Between Budget and Opinion, and both halves of that are load-bearing. AFTER
	# Budget, because the burden reads the deficit that Budget has just settled and
	# charges its penalty into NEXT month's recompute -- which is what stops a rule
	# on the deficit feeding a fine that widens the deficit that deepens the breach.
	# BEFORE Opinion, because the `europe` issue reads the burden, and wired the
	# other way round every org reaction would carry a spurious extra month of lag.
	Orgs.tick_month(_state, _loader)
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
	# V4.1, immediately before Opinion: the register concludes first, so a
	# conclusion and the pulse Opinion prices off it land in the SAME month --
	# programme_pulse() reads concluded_this_month(), which matches the
	# conclusion's stamped (terms_served, months_in_term) against the live pair.
	#
	# THE TERM-BOUNDARY GUARANTEE: no code between this call and the
	# Opinion.tick_month call below writes either counter, and the ONLY writer
	# of the pair anywhere in this loop is Elections.tick_month, which runs
	# LAST -- so a conclusion landing in the election month is stamped and paid
	# before the vote can reset months_in_term. The pair cannot desync within a
	# tick by construction. If Elections ever moves between these two calls, a
	# won election stamps (T, m) and resets to (T+1, 0) between stamp and read,
	# concluded_this_month() matches nothing, and the pulse is silently unpaid --
	# move Elections back after the pair before trusting a conclusion again.
	Programme.tick_month(_state, _loader)
	Opinion.tick_month(_state)
	# V4.1. The conclusions, as cards -- deliberately AFTER Opinion and not
	# between the pair: tests/test_programme_channel.gd pins that nothing but
	# comments runs between Programme.tick_month and Opinion.tick_month, and
	# the pin is the same-month guarantee's source form. The read is safe
	# anywhere in this handler BEFORE Elections.tick_month, which is the ONLY
	# writer of the (terms_served, months_in_term) pair
	# concluded_this_month() matches against and which runs last -- so the
	# cards see exactly the conclusions the pulse was priced on, one
	# statement later.
	_card_programme_conclusions()

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

	_windows.mark_all_dirty()

	# U5c. The map draws only on hover, pan, zoom and resize, which was complete
	# while its colours came from a hash of the nation id and is not now: relations
	# drift every month and a trade weight moves with every partner's GDP. Without
	# this the data layers show the colours of whenever the mouse last moved.
	if _map_view != null:
		# V2.6b1. The city list is rebuilt on the same monthly hook, and for a
		# sharper version of the same reason: a city's population is two live shares
		# times a live head count, and where the unions are out changes with the
		# grievance. Without this the crosses keep the sizes they had at new game --
		# which is what V2.6a's "cities grow and shrink for free" actually did on
		# screen until the V2.6b1 screenshot pass looked at a frame.
		_map_view.refresh_cities()
		_map_view.queue_redraw()

		# Same monthly hook and the same reason as the city list beside it: a
		# trade weight moves with every partner's GDP and an accessibility index
		# with every region's output share. Without this the convoys keep the
		# densities they had at new game, which is what "cities grow and shrink
		# for free" actually did on screen until a screenshot pass looked.
		if _map_flows != null:
			_map_flows.refresh()

	# Discipline reads the approval Opinion has just settled, so it goes after
	# that and before anything that reads a coalition bonus or a censure vote.
	Discipline.tick_month(_state, _loader)

	# Cooldowns count down before the election check, same ordering reasoning as
	# everything else in this handler: state settles top to bottom, elections
	# read it last.
	Legislature.tick_month(_state, _loader)
	# The ultra pass-4 finding: a held bill releasing writes ns.last_law_result
	# above, and the assembly's own tick below overwrites the same register
	# when a private member's bill divides the SAME month -- the release card
	# was then permanently unreachable, its only announcement surface read
	# after both writers. Capture the release before it can be swallowed and
	# hand it to the announcer beside the division; empty unless a release
	# actually fired (assembly_bill + released are the machine's own two keys
	# for it).
	var assembly_release: Dictionary = {}
	var release_ns = _state.player()
	if release_ns != null:
		var release_result: Dictionary = release_ns.last_law_result
		if bool(release_result.get("assembly_bill", false)) \
				and bool(release_result.get("released", false)):
			assembly_release = release_result.duplicate(true)
	# V4.2 T6. The assembly's own life -- private members' bills and the
	# chiefs' lobbying -- ticks AFTER the legislature, so a bill failing its
	# division writes its authored cooldown AFTER this month's countdown pass
	# has run and keeps its full length (the V2.8 ordering, one machine down).
	Statute.tick_month(_state, _loader)
	_announce_assembly_events(assembly_release)
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
	# -> obligations -> bill. src/sim/orgs.gd makes the same call for the same reason.
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
	Industry.tick_month(_state, _loader)
	_announce_industry_events()

	# After Companies, because the city pull reads live headcount: a month in which a
	# subsidy moved a firm's hiring should move people in the same month rather than
	# the next one. After Economy for the same reason one level up -- the region pull
	# reads live regional output and unemployment, both settled in Economy's own tick.
	Migration.tick_month(_state, _loader)

	# V1.6e: the capital each sector's standing programme has bought converges toward
	# the programme's intensity, and the bill is recomputed. In Companies' slot for
	# Companies' reason, and the loop it breaks is the identical one: bill -> deficit
	# -> a PRECONDITION_FIELDS entry -> which investment actions are available -> a
	# new programme -> bill. Sixth time this argument has been made.
	Investment.tick_month(_state)

	# V1.6f: every project under construction loses a month, any that run out COMPLETE
	# and write their permanent addend, and the bill is recomputed. In Investment's
	# slot for Investment's reason, and the loop is the identical one a seventh time:
	# bill -> deficit -> a PRECONDITION_FIELDS entry -> which project actions are
	# available -> a new build -> bill. Advance, complete, then price, so a project
	# that finishes this month stops billing this month.
	Projects.tick_month(_state, _loader)

	# V1.7a: a month of every campaign effort in the field, onto the mobilisation the
	# vote reads, and the bill recomputed -- or the whole register cleared, if the
	# run-up is over. In Projects' slot for Projects' reason, and the loop is the
	# identical one an eighth time: bill -> deficit -> a PRECONDITION_FIELDS entry ->
	# which campaign actions are available -> a new effort -> bill.
	#
	# BEFORE Elections, which is what makes the month of the vote count: the window is
	# inclusive of it, so the last month of effort is accrued and read by the vote it
	# was bought for. Elections then pushes next_executive_* five years out, and NEXT
	# month this call finds the window closed and clears the register. That is the
	# whole of the clearing mechanism: a level read, so campaign.gd needs no hook at
	# the vote and elections.gd needs no knowledge of the window.
	Campaign.tick_month(_state, _loader)

	# V1.7b: every promise on the books judged against the state it named, and charged
	# for the month if it is being broken. Immediately after Campaign for the same
	# reason Campaign sits before Elections -- the last month of a term is judged, and
	# THEN the vote is held.
	#
	# There is no loop to break here and so no lag to argue about: a promise writes
	# ns.bloc_offset, which is not a spending line, not a deficit and not a
	# PRECONDITION_FIELDS entry of its own. It is also why this call is absent from
	# Budget.project(): a projection that charged a broken promise would be a budget
	# preview quietly moving approval.
	Pledges.tick_month(_state, _loader)

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

	# V1.8, immediately after Unrest and before Cabinet and Elections. AFTER Unrest
	# because `unrest_pct` is one of the fields an event may be preconditioned on and it
	# has only just settled; BEFORE Elections for the reason everything in this handler
	# sits above it -- state settles top to bottom and the vote reads it last.
	#
	# `before` is captured for the U4 decision delta, because a default arriving is a
	# thing that happened to the player's budget with no button pressed -- the class
	# _card_appointment() already covers, and the one case where the player did not even
	# know a decision was being made on their behalf.
	var event_before := Budget.snapshot(_state)
	# V4.4: the before-state is the desk's CONTENT, not its emptiness -- a
	# resolve-and-replace month (one answered, another arrived) is ordinary now,
	# and the boolean edge detector fired neither branch on exactly that month.
	var desk_before := {}
	for desk_entry in _state.player().event_queue:
		desk_before[String(desk_entry.get("event_id", ""))] = true
	Events.tick_month(_state, _loader)
	_card_events(year, month, desk_before, event_before)
	_enforce_interrupt()

	# Reads unpopularity Opinion already settled and discipline Discipline
	# already ticked -- a resignation this month is judged against this
	# month's numbers, not last month's.
	Cabinet.tick_month(_state, _loader)

	# V4.3, after Cabinet (wants read Opinion-settled state and the cabinet's
	# vacancies) and before Elections (the stamp pair's only writer still runs
	# last, and a challenge's new party leader is in place before the vote
	# prices it). The meters are read here and handed in -- the leaf law keeps
	# unrest.gd/media.gd/judiciary.gd un-preloaded in characters.gd. The acts
	# go to the message stack as cards, T5's surface; the record is not state.
	var _character_acts := Characters.tick_month(_state, _loader, {
		"grievance": float(_state.player().unrest_pct),
		"press_freedom": float(_state.player().press_freedom),
		"judicial_independence": Judiciary.independence_deviation(_state.player()),
	})
	_card_character_acts(_character_acts)

	# Elections run last, on the already-settled history entry, and can fire a
	# national and an EP result in the same month (France and Belgium, June
	# 2029). Any result pauses the clock — the player reads it before time moves
	# again, whether that reading ends in Continue or in defeat.
	var results := Elections.tick_month(_state, _loader)
	if not results.is_empty() and _election_panel != null:
		_clock.paused = true
		_election_panel.show_results(results)
		_election_panel.show()

	# B4: the opening card's countdown is rewritten (or taken) against the state
	# this tick settled, Elections included -- it runs after the pair above for
	# the same reason the programme enforcement below does.
	_refresh_term_card()

	# V4.1, last so the read is of the state this tick SETTLED: a won election
	# resets months_in_term above, and the month a new term begins is a term
	# start again. SKIPPED when a result is on screen -- the election owns the
	# pause until it is dismissed, and the dismissal handler re-runs this; two
	# pauses stacked on one tick would let the answerable one (the programme
	# card) eat the verdict's. A no-op every ordinary month -- the level read
	# closes itself.
	if results.is_empty():
		_enforce_term_start_programme()


## V4.7b: the autonomy machine's two player-facing events, as cards. The
## announced-state memory is main-side (UI): the sim stays free of the card
## stack, and a dismissed card is remembered as announced -- DISMISSAL NEVER
## ANSWERS, the bid and the window lapse on their own clocks; the card only
## has to stop repeating.
var _announced_bids := {}
var _announced_failures := {}
var _industry_card_firms := {}   # card id -> company_id; the route opens the
# companies window whole -- no focus-by-firm yet (the open deferral above) --
# so the value is carried for the day that lands, not read today.
var _bid_cards := {}             # company_id -> its LIVE bid card, taken away when the bid resolves
var _failure_cards := {}         # company_id -> its LIVE failure card, same contract

func _announce_industry_events() -> void:
	var ns = _state.player()
	if ns == null:
		return
	var bid: Dictionary = Industry.pending_bid(_state, ns, _loader)
	# The memory clears PER FIRM, when that firm's own bid ends -- the
	# failure branch's design below, and the pass-6 fleet's find that the
	# bid branch was still the all-clear its own comment forswore: with two
	# bids pending, answering A kept A's entry (pending_bid only shows the
	# FIRST bid), and a re-bid on A announced nothing.
	var live_bid_ids := {}
	for company_id in ns.companies.keys():
		if String(ns.companies[company_id].get("bid_bidder", "")) != "":
			live_bid_ids[company_id] = true
	for announced_id in _announced_bids.keys():
		if not live_bid_ids.has(announced_id):
			_announced_bids.erase(announced_id)
	# A resolved card is TAKEN AWAY -- PR 43's B4 contract, which these two
	# cards dishonoured until the pass-8 fleet caught it: after block, allow
	# or lapse the column still asserted an offer that no longer existed.
	for firm_id in _bid_cards.keys():
		if not live_bid_ids.has(firm_id):
			_hud.message_stack.dismiss(String(_bid_cards[firm_id]))
			_bid_cards.erase(firm_id)
	if bid.is_empty():
		_announced_bids.clear()
	else:
		var bid_firm := String(bid["company_id"])
		if not _announced_bids.has(bid_firm):
			_announced_bids[bid_firm] = true
			var card_id: String = _hud.message_stack.push(
				"Foreign takeover bid",
				"%s has offered %.1f bn for %s. The offer lapses in %d months." % [
					_loader.nation_name(String(bid["bidder_nation"])), float(bid["price_eur_bn"]),
					_loader.firm_name(ns.id, bid_firm), int(bid["months_left"])])
			_bid_cards[bid_firm] = card_id
			_industry_card_firms[card_id] = bid_firm
	# The window counts down on EVERY live card, read from the register --
	# not only pending_bid's first (the pass-9 fleet's find: with two bids
	# pending, the second firm's card froze at its announce-time months and
	# could lapse on stale text). The body ages IN PLACE -- the set_body
	# law, because dismiss-then-push moves the card to the bottom and the
	# position IS the card's age. A player-dismissed id is a clean no-op:
	# DISMISSAL NEVER ANSWERS, and never resurrects.
	for firm_id in _bid_cards.keys():
		if not live_bid_ids.has(firm_id):
			continue
		var entry: Dictionary = ns.companies[firm_id]
		var parts: PackedStringArray = String(entry.get("bid_bidder", "")).split("|")
		_hud.message_stack.set_body(String(_bid_cards[firm_id]),
			"%s has offered %.1f bn for %s. The offer lapses in %d months." % [
				_loader.nation_name(parts[0] if parts.size() > 0 else ""),
				float(entry.get("bid_price_eur_bn", 0.0)),
				_loader.firm_name(ns.id, String(firm_id)),
				int(entry.get("bid_months_left", 0))])
	var failing_now := Industry.failing(_state, ns, _loader)
	# The memory clears PER FIRM, when that firm's own window closes -- the
	# bid branch's design, not the all-clear the first draft used. Clearing
	# only when NO firm failed would keep a rescued firm's entry alive while
	# another window stood, and its RE-failure inside that window would then
	# be card-silent: the write-once class the comment above names.
	var failing_ids := {}
	for failure in failing_now:
		failing_ids[String(failure["company_id"])] = true
	for announced_id in _announced_failures.keys():
		if not failing_ids.has(announced_id):
			_announced_failures.erase(announced_id)
	for firm_id in _failure_cards.keys():
		if not failing_ids.has(firm_id):
			_hud.message_stack.dismiss(String(_failure_cards[firm_id]))
			_failure_cards.erase(firm_id)
	for failure in failing_now:
		var company_id := String(failure["company_id"])
		var failure_body := "%s is failing. The rescue window stands for %d months; past it the collapse is committed." % [
			_loader.firm_name(ns.id, company_id), int(failure["months_left"])]
		if _announced_failures.has(company_id):
			if _failure_cards.has(company_id):
				_hud.message_stack.set_body(String(_failure_cards[company_id]), failure_body)
			continue
		_announced_failures[company_id] = true
		var card_id: String = _hud.message_stack.push("Firm in difficulty", failure_body)
		_failure_cards[company_id] = card_id
		_industry_card_firms[card_id] = company_id

## V4.2 T6: the assembly's own events, as cards -- _announce_industry_events's
## idiom whole. The announced-state memory is main-side (the sim stays free of
## the card stack); dismissal never answers (an unendorsed bill still divides);
## and a tabling card is TAKEN AWAY when its bill resolves, its replacement
## being the division card and not a stale offer to endorse a bill the house
## has already settled.
var _announced_assembly_bills := {}
var _assembly_cards := {}         # bill_id -> its LIVE tabling card
var _assembly_result_month := -1  # absolute month whose division card was pushed
var _assembly_release_month := -1  # absolute month whose release card was pushed

func _announce_assembly_events(assembly_release: Dictionary = {}) -> void:
	var ns = _state.player()
	if ns == null:
		return
	var live_ids := {}
	for bill_id in ns.assembly_bills.keys():
		live_ids[bill_id] = true
	for announced_id in _announced_assembly_bills.keys():
		if not live_ids.has(announced_id):
			_announced_assembly_bills.erase(announced_id)
	for bill_id in _assembly_cards.keys():
		if not live_ids.has(bill_id):
			_hud.message_stack.dismiss(String(_assembly_cards[bill_id]))
			_assembly_cards.erase(bill_id)
	for bill_id in ns.assembly_bills.keys():
		var entry: Dictionary = ns.assembly_bills[bill_id]
		var body := _assembly_bill_body(entry)
		if _announced_assembly_bills.has(bill_id):
			if _assembly_cards.has(bill_id):
				_hud.message_stack.set_body(String(_assembly_cards[bill_id]), body)
			continue
		_announced_assembly_bills[bill_id] = true
		var backed := String(entry.get("backer_firm", "")) != ""
		var card_id: String = _hud.message_stack.push(
			"A chief before the assembly" if backed else "Private member's bill", body)
		_assembly_cards[bill_id] = card_id
	# The release card, handed in from _on_month_elapsed. The capture there is
	# what lets a COLLISION month -- a PMB dividing the same tick an
	# assembly-origin hold releases -- push both cards: the register read
	# below holds only the last writer. The release keeps its OWN memory slot
	# because both results of a collision carry the same
	# assembly_division_month stamp; one shared var would swallow the second
	# card of the pair exactly as the shared register did.
	if not assembly_release.is_empty() \
			and int(assembly_release.get("assembly_division_month", -1)) != _assembly_release_month:
		_assembly_release_month = int(assembly_release.get("assembly_division_month", -1))
		_hud.message_stack.push("The assembly divides", _assembly_result_body(assembly_release))
	# The division card. The assembly_bill marker on ns.last_law_result says
	# the last division was the assembly's; the memory keys the DIVISION'S OWN
	# MONTH -- the assembly_division_month stamp the machine writes into the
	# result -- and not the current month, which is what made a quiet month
	# whose tick merely found the old result still on the register re-announce
	# it every month until a new law event overwrote it. The released flag is
	# excluded since the pass-4 capture: a release that stayed on the register
	# (a month where the assembly's tick divided nothing) arrives through the
	# parameter above, and firing here too would push the same card twice.
	# The in-tray keeps no history, so the stamp is the one per-division fact
	# left once the entry is erased.
	var result: Dictionary = ns.last_law_result
	if bool(result.get("assembly_bill", false)) \
			and not bool(result.get("released", false)) \
			and int(result.get("assembly_division_month", -1)) != _assembly_result_month:
		_assembly_result_month = int(result.get("assembly_division_month", -1))
		_hud.message_stack.push("The assembly divides", _assembly_result_body(result))

func _assembly_bill_body(entry: Dictionary) -> String:
	var law_name := _law_title(String(entry.get("law_id", "")))
	var months := int(entry.get("months_left", 0))
	var firm_id := String(entry.get("backer_firm", ""))
	# The endorsement transition inside the bill's life -- the card must not
	# keep offering a stand the sim now refuses (the panel drops its button
	# for the same reason).
	if float(entry.get("endorse_bonus", 0.0)) > 0.0:
		return "%s reaches the floor in %d month%s. The president's stand is on the record -- endorsed." % [
			law_name, months, "" if months == 1 else "s"]
	if firm_id != "":
		var chief := _loader.person_name(String(entry.get("backer_chief", "")))
		return "%s's chief %s backs %s. The assembly divides in %d month%s; whether the president stands behind it is the president's to take." % [
			_loader.firm_name(_state.player_nation_id, firm_id),
			chief if chief != "" else "the chief", law_name, months, "" if months == 1 else "s"]
	return "%s reaches the floor in %d month%s. Endorse it, or let the backbench stand alone." % [
		law_name, months, "" if months == 1 else "s"]

func _assembly_result_body(result: Dictionary) -> String:
	var law_name := _law_title(String(result.get("law_id", "")))
	# A COURT STRIKE outranks every other wording, and it is checked FIRST
	# (law_panel's own order) because it fires on BOTH paths that reach this
	# builder: a release the court stopped still carries released/assembly_bill,
	# and a struck division still carries its tally. "Comes into force" and
	# "defeated, N ayes" against a bill the court stopped are both the card
	# contradicting the state it announces; the court sentence prints alone.
	if bool(result.get("struck_down", false)):
		return "The court has struck %s down." % law_name
	# A SUSPENSIVE REFUSAL IS A HOLD, not a defeat (law_panel's own reading --
	# one word for different things is the readout bug this project keeps
	# finding), and a blocked one was beaten somewhere the lower-house tally
	# below does not show. Both wordings come off the outcome keys the result
	# actually carries; only the bare false reads "defeated".
	if bool(result.get("held_by_upper", false)):
		return "The assembly carried %s and the %s has suspended it — it comes into force in %d months." % [
			law_name, String(result.get("upper_chamber", "second chamber")), int(result.get("held_months", 0))]
	if bool(result.get("blocked_by_upper", false)):
		return "The assembly carried %s and the %s has blocked it." % [
			law_name, String(result.get("upper_chamber", "second chamber"))]
	# The held bill's release: the coming-into-force event, not a division --
	# the release result carries no seat tally, and printing zeroes beside
	# "carried" would contradict its own numbers.
	if bool(result.get("released", false)):
		return "The %s's hold has run out — %s comes into force." % [
			String(result.get("upper_chamber", "second chamber")), law_name]
	return "The assembly has %s %s, %d ayes to %d noes." % [
		"carried" if bool(result.get("passed", false)) else "defeated",
		law_name, int(result.get("yes_seats", 0)), int(result.get("no_seats", 0))]

func _law_title(law_id: String) -> String:
	for law in _loader.laws:
		if law.id == law_id:
			return String(law.law_name)
	return law_id

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
	var floor_share: float = ForeignPolicy.even_share(_state) * ForeignPolicyK.CARD_MIN_STAKE_SHARE

	# Oldest first, so the newest act ends up at the top of the column: push()
	# appends and the stack drops from the front when it overflows.
	var fresh: Array = []
	for act in _state.foreign_acts:
		if int(act["year"]) != year or int(act["month"]) != month:
			break
		fresh.push_front(act)

	# Grouped by action, V2.9: four allies state-visiting in one month is ONE
	# piece of news, not four cards -- five near-identical cards were pushing
	# decisions off a six-slot column (playtest 2026-09-05). The filters below
	# are the original stake-floor gates, unchanged; only the carding is grouped.
	var by_action: Dictionary = {}
	for act in fresh:
		var actor_id := String(act["actor_id"])
		var target_id := String(act["target_id"])
		if actor_id == player_id:
			continue
		if target_id != player_id and ForeignPolicy.stake(_state, player_id, actor_id) < floor_share:
			continue

		var key := String(act["action_name"])
		if not by_action.has(key):
			by_action[key] = {"aimed": [], "elsewhere": []}
		if target_id == player_id:
			by_action[key]["aimed"].append({
				"actor": _nation_name(actor_id),
				"reason": String(act["reason"]),
			})
		else:
			by_action[key]["elsewhere"].append({
				"actor": _nation_name(actor_id),
				"body": "%s: %s." % [String(act["action_name"]), _nation_name(target_id)],
			})

	for action_name in by_action:
		var slot: Dictionary = by_action[action_name]
		var aimed: Array = slot["aimed"]
		if not aimed.is_empty():
			# An act aimed at the player names the player in the TITLE and not
			# again in the body: "Austria -> you / State Visit: France" reads as
			# though France were a third country involved somehow.
			var title: String = (
				"%s → you" % String(aimed[0]["actor"]) if aimed.size() == 1
				else "%d× %s → you" % [aimed.size(), action_name]
			)
			var who: String = (
				"%s." % String(aimed[0]["actor"]) if aimed.size() == 1
				else "%s." % ", ".join(aimed.map(func(a): return String(a["actor"])))
			)
			# The model computes a reason and this is the only place it is ever
			# read. Shipping the key unread would be V1.3b's `refused_by_partner`
			# a third time -- a field src/sim/ fills in and no surface shows,
			# which this block has now recorded twice and fixed once. The first
			# act's reason stands for the group: same action, same month.
			_hud.message_stack.push(title, "%s %s %s" % [
				action_name, who, _act_reason_text(String(aimed[0]["reason"])),
			])
		else:
			for line in slot["elsewhere"]:
				_hud.message_stack.push(String(line["actor"]), String(line["body"]))


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
		# V2.6b1. The card names the PLACE, and it reads it off the act's own record
		# rather than re-deriving it: a past act's site cannot be recovered once the
		# shares have moved, which is why unrest.gd writes it down at the moment it
		# happens. Absent -- every act on a version-29 save, and every nation with no
		# site -- the sentence falls back to the national wording it has always had,
		# so an old save reads correctly rather than printing an empty place.
		var city := String(act.get("city_name", ""))
		var region := String(act.get("region_name", ""))
		var body := "Grievance stands at %.0f of 100. Output will carry it for months." % float(act["unrest_pct"])
		if city != "" and region != "":
			body = "%s, %s. Grievance stands at %.0f of 100. Output will carry it for months." % [
				city, region, float(act["unrest_pct"]),
			]
		_hud.message_stack.push(_unrest_title(String(act["label"])), body)


## V4.3's interim surface: one card per act, named off the act's own record --
## the person's NAME is resolved here in the UI, never in src/sim/ (the
## re-key's law, still). T5's People-panel and hover-card surfaces build on
## the same records; this column's card exists so an act is never silent.
func _card_character_acts(acts: Array) -> void:
	if _hud == null or _hud.message_stack == null:
		return
	for act in acts:
		var who := _loader.person_name(String(act["person_id"]))
		var kind := String(act["act"])
		var detail: Dictionary = act.get("detail", {})
		var title := "The bench stirs"
		var body := "%s acts." % (who if who != "" else "Someone")
		match kind:
			"resign":
				title = "A resignation"
				body = "%s resigns the premiership. The party holds the office; the government pays in standing." % who
			"defect":
				title = "A defection"
				body = "%s crosses the floor. The seat stays with the whip." % who
			"challenge":
				var deposed := _loader.person_name(String(detail.get("deposed", "")))
				title = "A leadership challenge"
				body = "%s takes the leadership. %s stands down." % [
					who, deposed if deposed != "" else "The incumbent",
				]
			"brief_against":
				title = "A leak"
				body = "%s briefs against the government." % who
		_hud.message_stack.push(title, body)


## V1.8. What arrived on the desk this month, and what the clock decided when the
## player said nothing. The fifth caller of message_stack.push() and the FIRST EVER
## CONSUMER of its card_activated signal, which U5a emitted and connected to nothing.
##
## U5a's call 3 said the column ships as furniture because the thing that fills it is
## events, and that "V1.8 adds calls rather than a layout". It held: nothing on screen
## moved to make room, and the one piece of machinery this needed -- a card the player
## can click through to the decision -- was already there waiting.
##
## Two cards and they are opposite in kind. An ARRIVAL is a question, and clicking it
## opens the window where it is answered. A DEFAULT is a thing that already happened to
## the player's government with no button pressed -- _card_appointment()'s class exactly,
## and the sharper case, because with an appointment the player at least booked it.
func _card_events(year: int, month: int, desk_before: Dictionary, before: Dictionary) -> void:
	if _hud == null or _hud.message_stack == null or _state == null:
		return
	var ns = _state.player()
	if ns == null:
		return

	# What LEFT the desk this month: ids that were on it before the tick and are
	# not now. Each is a resolution, and each earns its own card -- two crises the
	# clock answered in one month is twice the news, not the same news twice.
	var after := {}
	for entry in ns.event_queue:
		after[String(entry.get("event_id", ""))] = true
	for event_id in desk_before.keys():
		if after.has(event_id):
			continue
		# The unseen set's first door, and the invariant's desk half: an id that
		# has left the desk is not unseen, whether it left by the machine's own
		# default (_tick_countdowns answered it a moment ago), the player's card
		# answer or a Dispatches answer -- and its arrival card goes with it.
		# An erase of _unseen_events missed here used to strand the id and hold
		# the clock past every later answer; a missing card purge left decision
		# buttons with no event to answer.
		_dismiss_event_cards(event_id)
		_unseen_events.erase(event_id)
		var record := {}
		for row in ns.event_history:
			if String(row.get("event_id", "")) == event_id:
				record = row
				break
		if record.is_empty():
			continue
		if not bool(record.get("defaulted", false)) or int(record.get("year", 0)) != year or int(record.get("month", 0)) != month:
			continue
		# A sited crisis names its place here too: this card and the Dispatches
		# ledger print the same record, and two readouts of one record that
		# disagree is the failure class this column keeps catching.
		var named := String(record.get("event_name", ""))
		var where := String(record.get("region_name", ""))
		if where != "":
			named = "%s — %s" % [named, where]
		_hud.message_stack.push(
			"Decided for you",
			"%s. Nobody answered, so it went the way it was always going to: %s." % [
				named, String(record.get("choice_label", "")),
			],
		)
		# The delta is queued HERE and not at the choice, because this is the one
		# case where the player made no decision -- U4's baseline still belongs
		# against it, or a budget that moved by default moves for no reason the
		# ledger names.
		_queue_effect(String(record.get("event_name", "")), before)

	# What ARRIVED: ids on the desk now that were not before. Each gets its own
	# decision card, answering its own row.
	for entry in ns.event_queue:
		var event_id := String(entry.get("event_id", ""))
		if desk_before.has(event_id):
			continue
		var ev = Events.event_by_id(_loader, event_id)
		if ev == null:
			continue
		var left := int(entry.get("months_left", 0))
		# A decision the player has not seen must not expire behind their back:
		# "3 months to answer" at speed 3 is thirteen seconds, and both playtest
		# runs produced "Decided for you" records no player answered (2026-09-05).
		# Arrival pauses; the interrupt flag (V2.4b) still opens Dispatches on
		# top -- non-modal, per events-model's argument, but the clock waits
		# until everything unseen has been answered.
		_paused_for_decision = true
		_clock.paused = true
		_hud.clock_cluster.refresh(_clock)
		_unseen_events[event_id] = true
		# And the card itself is the answer surface (the clock is stopped, so the
		# choices cannot be pressed against a running world). The default-choice
		# marker is events_panel's own wording.
		var actions: Array = []
		for choice in ev.choices:
			actions.append({"label": "%s%s" % [
				String(choice.get("label", "")),
				"   (happens if you say nothing)" if bool(choice.get("is_default", false)) else "",
			]})
		# The title names the place for a sited event -- read straight off the
		# entry, `event_name` untouched (V3.5). The name is already in the
		# register because every reader of it is a leaf over pending state.
		var title: String = ev.event_name
		var where := String(entry.get("region_name", ""))
		if where != "":
			title = "%s — %s" % [title, where]
		# The same plate the Dispatches desk entry carries, on the title's side:
		# one crisis, one image, in both places it is read. Null (no art yet)
		# draws the card exactly as before -- missing art is silent.
		var art := EventArt.plate_texture(ev.category, int(entry.get("severity", 1)), event_id)
		var card_id: String = _hud.message_stack.push(title, _decision_body(ev, left), actions, art)
		_event_cards[card_id] = event_id

	# The unseen set's third door re-check: the pause is re-judged AFTER the
	# arrivals, not beside the departure erase above -- a same-month
	# resolve-and-replace (one default fires, another crisis lands) must not
	# resume past the fresh arrival. The same three lines the card-answer path
	# runs.
	_resume_if_decision_settled()


## The one resume rule for the arrival pause, shared by all four doors (panel
## answer, card answer, card dismissal, the post-arrival re-check). Clearing the
## unseen set ends THIS pause, not every pause: an interrupt-flagged event still
## on the desk (its card's X must not release a clock the flag holds "until
## answered") and an unchosen term-start programme each own the clock
## independently, so the clock stays down. The two differ in who releases it:
## the programme's own choice does (_on_programme_chosen), so the arrival flag
## drops; an interrupt has no release of its own but the answer, so the flag
## STAYS up and the answer's call to this function is what lets the clock go --
## dropping it on an X would strand the clock after the later Dispatches answer.
func _resume_if_decision_settled() -> void:
	if not _paused_for_decision or not _unseen_events.is_empty():
		return
	if _paused_for_programme:
		_paused_for_decision = false
		return
	var ns = _state.player() if _state != null else null
	if ns != null and Events.interrupt_pending(ns):
		return
	_paused_for_decision = false
	_clock.paused = false
	_hud.clock_cluster.refresh(_clock)


## A load through the pause menu re-raises its holds AFTER the menu took its
## "was the clock running" snapshot, and closing the menu would restore that stale
## snapshot over them. Folding the holds in here -- the one place that knows a
## load just happened -- keeps _close_pause_menu a plain restore.
func _note_holds_for_pause_menu() -> void:
	if _paused_for_programme or _decision_holds_clock():
		_paused_before_menu = true


## Whether an event still owns the clock: an unseen arrival, or an interrupt on the
## desk. The programme pause and the election dismissal consult this before they
## release the clock, so choosing a programme cannot run time out from under a
## question nobody has answered.
func _decision_holds_clock() -> bool:
	if _paused_for_decision and not _unseen_events.is_empty():
		return true
	var ns = _state.player() if _state != null else null
	return ns != null and Events.interrupt_pending(ns)


## Dismiss every message-stack card keyed to an event that has left the desk.
## Finds card ids in _event_cards mapping to `event_id`, dismisses each, and
## iterates a copy of the keys because `dismiss()` emits `card_dismissed` whose
## handler erases from _event_cards -- re-entry is harmless; the handler also
## erases from _unseen_events, which is a no-op when the caller already erased it.
func _dismiss_event_cards(event_id: String) -> void:
	if _hud == null or _hud.message_stack == null:
		return
	for card_id in _event_cards.keys().duplicate():
		if String(_event_cards.get(card_id, "")) == event_id:
			_hud.message_stack.dismiss(card_id)


## The decision card's body: the event's summary line, then the deadline -- the
## same two sentences the arrival card has always carried, now beside buttons
## that answer it (V2.9).
func _decision_body(ev, left: int) -> String:
	return "%s  You have %d %s to answer." % [
		ev.summary, left, "month" if left == 1 else "months",
	]


func _unrest_title(label: String) -> String:
	match label:
		"protest": return "Demonstrations"
		"strike": return "General strike"
	return "Industrial action"


## The sentence for a ForeignPolicy.ACT_REASON_* key. src/sim/ returns keys and
## src/ui/ owns the wording, the same split nation_panel.gd has for a refusal and
## orgs_panel.gd for a vote.
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
		# carries clock.day at the payload's top level and _on_load_requested()
		# re-mirrors it, so there is exactly one record of the date.
		_state.day = day
		_resolve_appointments(year, month, day)
		# V2.4a: the ribbon's today-mark and its past-dimming both move with the
		# day, which is the one quantity no monthly surface carries.
		_hud.ribbon.mark_dirty()
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
					# execute()'s contract is `applied`, not `ok` -- V2.4a found
					# this read as false on every arrival, so a kept visit fired
					# its effects and was recorded as refused anyway.
					ok = bool(result.get("applied", false))
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

		# V2.4b: a meeting that LANDED is the summit's trigger. Only the verb
		# that opens a meeting brings a scene; a refused arrival is a journey
		# home, and day-only acts were never journeys.
		if ok and String(entry.get("kind", "")) == CalendarK.KIND_DIPLOMATIC:
			var action2 = _action_by_id(String(entry.get("action_id", "")))
			if action2 != null and action2.opens_meeting:
				_open_summit(String(entry.get("target_id", "")), before)

	_windows.mark_all_dirty()
	# A booked diplomatic act moves relations, and on that map layer it is a
	# colour change the player should see the day it happens -- the same reason
	# nation_panel's own `acted` handler redraws. The arcs move on the same day
	# and for the same reason the handler refreshes them.
	if _map_view != null:
		_map_view.queue_redraw()
		if _map_flows != null:
			_map_flows.refresh()


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


## V2.4b. The scene itself. Drawn as data from the leaf sim, handed to the
## panel, and the U4 baseline is the ARRIVAL's -- taken by the caller before
## the panel opened -- because the summit's delta is measured from the meeting,
## not from the last beat of dialogue.
func _open_summit(target_id: String, arrival_before: Dictionary) -> void:
	var summit := Summits.draw(_state, _loader, target_id)
	if summit.is_empty():
		return
	_summit_before = arrival_before
	# OPENED BEFORE show_summit(), because show_summit() can conclude SYNCHRONOUSLY --
	# a missing DialogueManager or a scene that does not compile both push_error and
	# call _conclude() before returning. With the open after it, the concluded handler's
	# _windows.close("summit") ran against a window that was not open yet (close() bails
	# on a hidden frame) and the line below then opened the blank plate the close exists
	# to prevent. Opening first makes the close land, and an ordinary summit is
	# unaffected: the frame is up either way before the first beat is drawn.
	_windows.open("summit")
	_summit_panel.show_summit(summit)


## The panel's verdict. The effects ride Legislature.apply_effects() -- the
## same applier the event choice and the law use, which is why a summit is no
## new effect channel -- and the delta is queued against the arrival's
## baseline. An empty choice (the player closed through a path with no priced
## fork) applies nothing and says nothing: a conversation happened, and it
## changed nothing, which is the honest outcome for one of those.
func _resolve_summit(choice_label: String) -> void:
	if choice_label.is_empty():
		return
	var ns = _state.player()
	var effects: Dictionary = _summit_panel._effects.get(choice_label, {})
	if effects.is_empty():
		return
	Legislature.apply_effects(_state, ns, effects, _loader)
	_queue_effect("Summit: %s" % choice_label, _summit_before)
	_update_top_bar()




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
	var result := SaveManager.load_game(slot, _loader)
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
	# The announce memories and live-card maps belong to the DISCARDED game:
	# firm ids are content, so the same id failing in the loaded game would
	# be card-silent behind this session's carried entries -- the pass-15
	# fleet's reproduced find. The stack survives (its ids are monotonic),
	# so this is a memory reset and not a clear().
	_announced_bids.clear()
	_announced_failures.clear()
	_bid_cards.clear()
	_failure_cards.clear()
	_industry_card_firms.clear()
	# The assembly's four beside them, the same rule: bill ids collide only
	# within a run, so those two maps belong to the discarded game. The two
	# month memories are NOT simply reset to -1 (the ultra pass-7 finding):
	# the stamp exists so a quiet month cannot re-announce a division already
	# on the register, and the load boundary must honour it, not reset it --
	# the first month elapsed after a save+load otherwise re-announced the
	# loaded division (or release) as news. Each slot takes the loaded stamp
	# for ITS OWN shape of result and -1 otherwise: a stale memory inherited
	# from the discarded game could swallow a real card whose stamp it
	# happened to match.
	_announced_assembly_bills.clear()
	_assembly_cards.clear()
	# The V4.4 desk's three ride the same rule -- a stale unseen id would hold
	# the clock past the load and a discarded game's decision card would route
	# Events.answer against the loaded state (the decision pause beside the
	# load's own pause below is the third).
	_event_cards.clear()
	_unseen_events.clear()
	var loaded_ns = _state.player()
	var loaded_result: Dictionary = loaded_ns.last_law_result
	var carries_bill := bool(loaded_result.get("assembly_bill", false))
	var released_load := bool(loaded_result.get("released", false))
	var loaded_stamp := int(loaded_result.get("assembly_division_month", -1))
	_assembly_result_month = loaded_stamp if carries_bill and not released_load else -1
	_assembly_release_month = loaded_stamp if carries_bill and released_load else -1
	_clock.year = _state.year
	_clock.month = _state.month
	_clock.day = int(result["day"])
	_clock.paused = true
	# The discarded game's decision pause dies here, not just its clock: the
	# loaded game's interrupt enforcement re-raises a pause if the save carries
	# one, so the flag must not survive as a second holder of it. The programme
	# pause dies with it: _enforce_term_start_programme() below re-raises it only
	# if the loaded game is at a term start, and a stale true would otherwise
	# block every later auto-resume (_resume_if_decision_settled reads it).
	_paused_for_decision = false
	_paused_for_programme = false

	_map_view.setup(_loader, _state)
	_minimap.setup(_map_view, _loader, _state)
	# A loaded game is a different _state, and an overlay left holding the
	# throwaway one built at _ready() is the same five-panel drift the V2.8
	# review found below -- setup(), not refresh(), because the reference itself
	# is what has to be replaced.
	_map_flows.setup(_map_view, _clock, _loader, _state)

	# The bill briefing is not in the registry, so the setup() sweep below never
	# reaches it -- open across a load it kept the discarded GameState, and its
	# poll verb wrote the dead run's books (the V2.8 five-panel drift class).
	_briefing.detach()

	# EVERY REGISTERED PANEL, off the registry rather than a hand-written list.
	# A panel stores `state` in its own setup(), so one omitted here keeps a
	# reference to the throwaway game built at _ready() -- an object nothing ticks
	# again. Until the V2.8 review this WAS a hand-written list, and it had drifted
	# by five: city, energy, events, region and summit. The events panel is the one
	# that made it more than a stale readout -- events_panel.gd calls
	# Events.answer(_state, _loader, ev.id, ...), so answering a crisis after a
	# load wrote the decision into the discarded state and the real event
	# defaulted at its deadline. mark_all_dirty()'s own comment predicted exactly
	# this, about
	# exactly this kind of list, which is why the fix is the same one: derive it,
	# so the omission is structurally impossible rather than remembered.
	for panel in _windows.panels():
		if panel.has_method("setup"):
			panel.setup(_state, _loader)

	# Not registered surfaces, so not reached by the loop above: the election
	# screen is opened directly rather than through a window, and the ribbon and
	# the portrait card are HUD furniture. Each stores `state` in its own setup()
	# and so needs the same rebinding -- the portrait card's approval figure and
	# the ribbon's month title were both frozen at the pre-load game's values.
	_election_panel.setup(_state, _loader)
	_hud.ribbon.setup(_state, _loader)
	_hud.portrait_card.setup(_state, _loader)
	# The mirror is re-established here rather than waiting for the first day to
	# elapse, because a loaded game opens PAUSED: without this the diary would
	# refuse a booking for today as "that date has passed" until the player
	# unpaused, which is a rule the player cannot see and did not break.
	_state.day = _clock.day

	_windows.mark_all_dirty()

	# V2.4b: the reload re-raise. An interrupt crisis pending in the save stops
	# the clock again and is put back in front of the player -- a save made mid-
	# crisis and reloaded is still mid-crisis, and the pause is the only thing
	# that stops the clock from quietly resuming past a question the player never
	# answered. (A save-scum dodge the other way -- reload to rethink -- still
	# works; the re-raise kills the silent skip, not the rethink.)
	_enforce_interrupt()
	# V4.1. A save made at an unchosen term start is still one: the same
	# reload-re-raise reasoning _enforce_interrupt() carries, one register over.
	_enforce_term_start_programme()
	_note_holds_for_pause_menu()

	_save_load_panel.report("Loaded '%s'." % slot)
	_save_load_panel.mark_dirty()
	_update_top_bar()


## V2.4b, and the reversal of a V1.8 call for one flagged class. An event with
## `interrupt: true` PAUSES the clock until answered -- docs/events-model.md's
## non-modal argument covers every event without the flag, and the flag exists
## precisely for the one the argument does not cover: an event nobody could
## reasonably choose to ignore. The pause reads the serialised register, which
## is what makes the reload re-raise the SAME code path rather than a second
## one: announce wrote the flag into the queue's entries, and both the month tick
## and a fresh load read it here. V4.4: an ANY read -- the desk can hold
## several things and any one of them carrying the flag is the pause.
##
## Every event WITHOUT the flag is untouched -- this function pauses nothing and
## opens nothing for it, and tests/test_events.gd pins that.
func _enforce_interrupt() -> void:
	if _state == null:
		return
	var ns = _state.player()
	if ns == null or not Events.is_pending(ns):
		return
	if not Events.interrupt_pending(ns):
		return
	_clock.paused = true
	# The interrupt pause IS a decision pause: raising the flag here (the load
	# path and a month's re-pause both reach this) is what lets the answer's
	# _resume_if_decision_settled() release it; without it a re-raised interrupt
	# stayed paused after being answered.
	_paused_for_decision = true
	if _events_panel != null:
		_windows.open("events")
	_hud.clock_cluster.refresh(_clock)


## V4.1, the term-start enforcement -- the arrival-pause precedent pointed at
## the programme. At a term start with the choice still open, the clock does
## not run past it: the offer is surfaced as a CARD (the decision-card shape --
## the Agenda window is the answer surface, and clicking the card opens it,
## through the card_activated routing in _wire_hud()), the clock pauses, and
## the choice resumes through _on_programme_chosen().
##
## NOT a blocking modal, on events-model's own argument one level up: the
## choice can be seen past -- the brass mark on the State cluster and the card
## on the desk both stay until it is answered -- but the clock waiting is what
## makes it a decision rather than a suggestion.
##
## Three callers, one code path: _ready() (a new game IS a term start),
## _on_load_requested() beside _enforce_interrupt() (a save made at an
## unchosen term start re-raises it), and the end of _on_month_elapsed()
## (a won election resets months_in_term; the month a new term begins is a
## term start again). Idempotent by construction: the previous card is
## dismissed before a fresh one is pushed, so repeated calls leave exactly
## one live card.
## The opening "Your term" card's sentence, built in one place so the boot push
## and every monthly refresh print the same countdown off the same query --
## the playtest's B4 was a snapshot of exactly the drift two copies would make.
func _term_card_body() -> String:
	var ns = _state.player()
	var when := Trends.vote_date(ns)
	return "You hold %s until %s %d -- %s. Win the vote." % [
		_nation_name(_state.player_nation_id),
		ClockCluster.MONTH_NAMES[when.y - 1], when.x,
		Trends.months_text(Trends.months_to_vote(_state, ns)),
	]


## The monthly refresh of the opening card, from _on_month_elapsed(). The body
## is rewritten in place (set_body keeps the card's position; a dismiss-then-
## re-push would jump the stack) while there is still a vote ahead, and the
## card is TAKEN AWAY once there is not -- a "Win the vote" card standing next
## to a verdict that already held it is the same stale class B4 photographed.
## A gone id (evicted by MAX_CARDS, or never pushed on a load) no-ops through
## set_body and the empty-id guards here.
func _refresh_term_card() -> void:
	if _term_card_id.is_empty() or _hud == null or _hud.message_stack == null:
		return
	var ns = _state.player()
	if ns == null:
		# Out of office: the verdict surface took over, the same dismiss as the
		# no-vote-left branch below, without reading a null nation.
		_hud.message_stack.dismiss(_term_card_id)
		_term_card_id = ""
		return
	if Trends.months_to_vote(_state, ns) <= 0:
		_hud.message_stack.dismiss(_term_card_id)
		_term_card_id = ""
		return
	_hud.message_stack.set_body(_term_card_id, _term_card_body())


func _enforce_term_start_programme() -> void:
	if _state == null:
		return
	var ns = _state.player()
	if ns == null:
		return
	# Programme.available() is empty everywhere but an unchosen term start,
	# structurally, before any content is consulted -- so this one read is the
	# whole gate. An empty offer pauses nothing: there is no decision to wait
	# behind, and a clock stopped with nothing on the desk is a stuck game.
	if Programme.available(_state, ns, _loader).is_empty():
		return
	if not _programme_card_id.is_empty():
		_hud.message_stack.dismiss(_programme_card_id)
	_programme_card_id = _hud.message_stack.push(
		"The term's programme",
		"The agenda holds the offer. Choose one goal before the clock runs -- the register prices the delivery, not the promise.",
	)
	_paused_for_programme = true
	_clock.paused = true
	_hud.clock_cluster.refresh(_clock)


## The panel emits; main performs. Programme.choose() refuses rather than
## half-applies, so a stale CHOOSE pressed after a choice landed lands here as
## a card that says so, and the register it could not reach is untouched.
func _on_programme_chosen(entry_id: String) -> void:
	if _state == null:
		return
	var ns = _state.player()
	if ns == null:
		return
	var before := Budget.snapshot(_state)
	var result: Dictionary = Programme.choose(_state, ns, entry_id, _loader)
	if bool(result.get("refused", false)):
		_hud.message_stack.push("Programme refused", _programme_refusal_text(String(result.get("reason", ""))))
		return

	# Entry open, as a card -- the register now holds the term's programme,
	# and the pulse it will pay lives on its conclusion, not here.
	var name_text := String(result.get("name", entry_id))
	_queue_effect("Programme set: %s" % name_text, before)
	_hud.message_stack.push(name_text,
		"This term's programme. Deliver it and the credit lands on the record;"
		+ " miss its deadline and the miss pays the same shape back.")
	if not _programme_card_id.is_empty():
		_hud.message_stack.dismiss(_programme_card_id)
		_programme_card_id = ""
	if _paused_for_programme:
		_paused_for_programme = false
		if not _decision_holds_clock():
			_clock.paused = false
			_hud.clock_cluster.refresh(_clock)
	_update_top_bar()
	_windows.mark_all_dirty()


## src/sim returns refusal keys; src/ui owns the wording -- _act_reason_text()'s
## split, so the machine can change a key without rewriting a sentence.
func _programme_refusal_text(reason: String) -> String:
	match reason:
		"not_term_start":
			return "The term has already begun."
		"already_chosen":
			return "This term's programme is already set."
		"not_offerable":
			return "That goal is not on offer."
	return ""


## V4.1. What concluded this month, as a card -- complete, fail and invalid
## alike, concluded_this_month()'s one read. _card_foreign_acts()'s split: the
## sim writes the record, the UI decides what earns a card, and src/sim/ never
## reads the list back. Called from _on_month_elapsed() INSIDE the tick window
## the pulse is priced in -- see the Programme.tick_month call site.
func _card_programme_conclusions() -> void:
	if _hud == null or _hud.message_stack == null or _state == null:
		return
	var ns = _state.player()
	if ns == null:
		return
	for entry in Programme.concluded_this_month(ns):
		var terms: Dictionary = Programme.terms_of(_loader, String(entry["entry_id"]))
		var name_text := String(terms.get("name", String(entry["entry_id"])))
		match String(entry["status"]):
			ProgrammeK.STATUS_COMPLETE:
				_hud.message_stack.push("Delivered: %s" % name_text,
					"The goal is met, and the register marks it complete.")
			ProgrammeK.STATUS_FAIL:
				_hud.message_stack.push("Missed: %s" % name_text,
					"The goal was not met in time, and the register marks the miss.")
			_:
				_hud.message_stack.push("Overtaken: %s" % name_text,
					"The world moved on and the entry no longer applies. It concludes without a verdict.")


## Everything on screen that is not inside a window. Kept under U2's name
## because ~15 call sites already say it and the job is unchanged -- the strip
## simply is not the only always-visible surface any more.
func _update_top_bar() -> void:
	if _top_bar != null:
		_top_bar.refresh(_state, _clock, _loader)
	if _hud != null:
		_hud.clock_cluster.refresh(_clock)
		_hud.portrait_card.refresh()
		# V2.1c. Here rather than in _on_month_elapsed() because a pending thing
		# also STOPS pending when the player answers it, and every command in this
		# file already ends by calling this function -- so the mark clears on the
		# press rather than a month later.
		_hud.action_bar.show_pending(Pending.window_ids(_state, _loader))
