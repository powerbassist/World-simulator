extends Control

## The Material Symbols Rounded set (Apache-2.0, filled) every window glyph
## comes from -- V2.3 lifted this out of the action bar's builder because
## register() names each window's icon too. Plain SVG text, read and rasterised by icon.gd, so a fresh clone works
## headless with no import cache.
const Labels = preload("res://src/ui/labels.gd")
const ICONS := "res://assets/icons/material/"

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")
const GameState = preload("res://src/core/game_state.gd")
const ClockCluster = preload("res://src/ui/clock_cluster.gd")
const Economy = preload("res://src/sim/economy.gd")
const Energy = preload("res://src/sim/energy.gd")
const Regions = preload("res://src/sim/regions.gd")
const Net = preload("res://src/sim/network.gd")
const Region = preload("res://src/core/region.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Cabinet = preload("res://src/sim/cabinet.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const ForeignPolicy = preload("res://src/sim/foreign_policy.gd")
const ForeignPolicyK = preload("res://src/sim/foreign_policy_constants.gd")
const Defence = preload("res://src/sim/defence.gd")
const DefenceK = preload("res://src/sim/defence_constants.gd")
const Industry = preload("res://src/sim/industry.gd")
const Programme = preload("res://src/sim/programme.gd")
const ProgrammeK = preload("res://src/sim/programme_constants.gd")
const Events = preload("res://src/sim/events.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Summits = preload("res://src/sim/summits.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Migration = preload("res://src/sim/migration.gd")
const MonthRunner = preload("res://src/ui/month_runner.gd")
const CalendarPanel = preload("res://src/ui/calendar_panel.gd")
const EventArt = preload("res://src/ui/event_art.gd")
const PeoplePanel = preload("res://src/ui/people_panel.gd")
const OutlinerPanel = preload("res://src/ui/outliner_panel.gd")
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
const MapFlows = preload("res://src/ui/map_flows.gd")
const NationPanel = preload("res://src/ui/nation_panel.gd")
const OrgsPanel = preload("res://src/ui/orgs_panel.gd")
const GovernmentPanel = preload("res://src/ui/government_panel.gd")
const SaveLoadPanel = preload("res://src/ui/save_load_panel.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const PauseMenu = preload("res://src/ui/pause_menu.gd")
const SettingsPanel = preload("res://src/ui/settings_panel.gd")
const Strings = preload("res://src/ui/strings.gd")
const Hud = preload("res://src/ui/hud.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")
const ScreenStack = preload("res://src/ui/screen_stack.gd")
const DEV_CONSOLE := "res://src/ui/dev_console.gd"
const Domains = preload("res://src/ui/domains.gd")
const Pending = preload("res://src/ui/pending.gd")
const MessageSettings = preload("res://src/ui/message_settings.gd")
const Sound = preload("res://src/ui/sound.gd")
const SoundBed = preload("res://src/ui/sound_bed.gd")
const OverviewPanel = preload("res://src/ui/overview_panel.gd")
const EconomyPanel = preload("res://src/ui/economy_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Trends = preload("res://src/ui/trends.gd")
const Num = preload("res://src/ui/num.gd")
const WorldNews = preload("res://src/ui/world_news.gd")
const DiaryDriver = preload("res://src/ui/diary_driver.gd")
const IndustryNews = preload("res://src/ui/industry_news.gd")
const AssemblyNews = preload("res://src/ui/assembly_news.gd")
const DateText = preload("res://src/ui/date_text.gd")

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

## V4.9a. Set by the loading screen (src/ui/boot_stages.gd), which built them
## across frames so the bar could move: when present, _ready() takes them
## instead of building its own. Null on a direct scene load -- every test and
## tool -- which boots exactly as it did before. Untyped for pending_load_slot's
## reason in menu.gd.
var pending_loader = null
var pending_state = null

@onready var _clock: Node = $Clock

var _state
var _loader: DataLoader
var _hud
var _windows
var _stack
var _top_bar
var _paused_for_decision := false
## V4.4: the desk is a queue, so the decision-card machinery tracks a SET. Card id
## -> the event id its buttons answer (the pressed card answers ITS row, not the
## desk's head), and the unseen set is what the arrival pause holds the clock for:
## it clears as the player answers, and the clock resumes when it empties.
var _event_cards := {}        # card id -> event id
var _unseen_events := {}      # event id -> whether it holds the clock (below)
## V4.8c: the unseen set's VALUE says whether the id holds the clock. An arrival
## whose category's pause band it meets enters as true; a quiet one enters as false
## -- unanswered, but the world keeps running -- until the lapse guard turns it
## true in its last month. The doors that erase an id are unchanged; the two clock
## checks read _unseen_holds(), not emptiness.
## The player's message settings (message_settings.gd), read from the settings
## file at boot and again whenever the settings screen closes. Cached because
## Pending.window_ids runs on the per-day path, where a file read is not free.
var _messages := {}
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
var _map_flows
var _nation_panel
var _orgs_panel
var _calendar_panel
var _people_panel
var _outliner_panel
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
## V5.1-0a. The month across frames, the clock and the windows held while it
## closes -- src/ui/month_runner.gd. A child of this node, added in _ready().
var _month_runner := MonthRunner.new()
## The news-card writers, out of this file at V5.1c (D2); `_setup_news()` hands them
## the live state, at the start and again on a load.
var _world_news := WorldNews.new()
var _industry_news := IndustryNews.new()
var _assembly_news := AssemblyNews.new()


func _ready() -> void:
	# Before anything is built. A Theme on this Control propagates to every
	# descendant, which is what lets the docked tabs, the top bar and the four
	# modal panels share one set of styles instead of three hand-built ones.
	UiTheme.apply(self)

	if pending_loader != null:
		_loader = pending_loader
	else:
		_loader = DataLoader.new()
		_loader.load_all()
	_messages = MessageSettings.load_from(SettingsPanel.CONFIG_PATH)

	if not _loader.errors.is_empty():
		for e in _loader.errors:
			push_error(e)
		return

	var ids := _loader.nations.keys()
	ids.sort()
	for id in ids:
		var n: Nation = _loader.nations[id]
		var pop_m := n.population / 1_000_000.0
		print("%s %-15s pop %5.1fM   GDP EUR %5.0fbn   debt %5.1f%%" % [n.id, n.nation_name, pop_m, n.gdp_eur_bn, n.debt_to_gdp_pct])

	_state = pending_state if pending_state != null else GameState.new_game(_loader, pending_player_id, pending_scenario_id)
	if not _state.errors.is_empty():
		for e in _state.errors:
			push_error(e)
		return
	# The accent is the played nation's own flag colour (V5.1a); the first apply()
	# above ran before there was a nation and used the fallback.
	UiTheme.apply_for(self, _loader.nations[_state.player_nation_id])
	# The distance table is warmed HERE, not on its first lazy caller: ~2 s once
	# per process is boot cost, while a lazy build makes the player's first
	# month boundary freeze. See network.gd::warm(). Behind the loading screen
	# (V4.9a) the table is already warm and this returns at once.
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
	# V5.1-c2.1. Where the centred panels' holders were added, so they draw where
	# they drew: over the HUD, under the dev console.
	_stack = ScreenStack.new()
	add_child(_stack)
	_stack.top_changed.connect(_on_stack_top_changed)
	# V4.9c. The desk's bed, rendered on a worker and swelling in once it is,
	# and the one-shot set on another (sound.gd's warm()): nothing in this
	# _ready() waits for either.
	SoundBed.start(self, "game")
	Sound.warm()
	_top_bar = _hud.top_bar
	_hud.ribbon.setup(_state, _loader)

	# register() before setup(), every time. register() is what puts the panel in
	# the tree, and a Control outside the tree has not run _ready(), so every
	# label setup() writes to is still null -- AGENTS.md's gotcha, and the same
	# order dashboard.gd's add_tab() enforced by doing both itself.
	_overview_panel = OverviewPanel.new()
	_windows.register("overview", tr("Overview"), _overview_panel, KEY_O, ICONS + "dashboard.svg")
	_overview_panel.setup(_state, _loader)

	# V4.1. The government's programme: the one window where a programme is
	# chosen and tracked (docs/programme-model.md §4). In the State cluster
	# beside the Overview it frames -- the agenda is what the term is FOR,
	# which is the sentence the Overview's other columns read against.
	_agenda_panel = AgendaPanel.new()
	_windows.register("agenda", tr("Agenda"), _agenda_panel, KEY_K, ICONS + "event.svg")
	_agenda_panel.setup(_state, _loader)
	_agenda_panel.programme_chosen.connect(_on_programme_chosen)

	_economy_panel = EconomyPanel.new()
	_windows.register("economy", tr("Economy"), _economy_panel, KEY_E, ICONS + "monitoring.svg")
	_economy_panel.setup(_state, _loader)

	# hide_close_button() still applies: these panels each build their own Close
	# button for the life they had before U2 docked them, and the window frame
	# now provides the real one. Two close buttons on one panel is worse than
	# either.
	_budget_panel = BudgetPanel.new()
	_windows.register("budget", tr("Budget"), _budget_panel, KEY_B, ICONS + "account_balance_wallet.svg")
	_budget_panel.setup(_state, _loader)
	_budget_panel.hide_close_button()
	_budget_panel.committed.connect(func(before, _pending):
		_fiscal_committed(tr("Budget change"), tr("Budget committed"), before))

	# V4.2 T5. The tax levers' new home, in the Economy cluster beside Budget:
	# the cluster grammar (panel-system.md §16) puts a surface where its
	# decision lives, and a tax rate is a budget-domain decision -- but a
	# separate DOMAIN from spending, which is why it is its own window and
	# not a row. KEY_X was the one letter left. The commit is Budget.commit()
	# -- the same verb the budget panel sends -- so the demand impulse, the
	# erosion curve and the books have one entry point however many windows
	# move a rate.
	_tax_panel = TaxPanel.new()
	_windows.register("tax", tr("Tax Code"), _tax_panel, KEY_X, ICONS + "receipt_long.svg")
	_tax_panel.setup(_state, _loader)
	_tax_panel.hide_close_button()
	# V4.2 ultra pass 2: the budget panel's proposed column and 24-month
	# projection price the Tax Code window's uncommitted edits (the panels are
	# siblings; this is a reference, not state, and the load path's setup()
	# sweep leaves it alone).
	_budget_panel.tax_panel = _tax_panel
	_tax_panel.committed.connect(func(before, _pending):
		_fiscal_committed(tr("Tax code change"), tr("Tax code committed"), before))
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
	_stack.add(ScreenStack.SCENE, _briefing, false, _briefing.hide)
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
	_windows.register("politics", tr("Politics"), _government_panel, KEY_G, ICONS + "groups.svg")
	_government_panel.setup(_state, _loader)
	_government_panel.hide_close_button()
	_government_panel.dissolved.connect(func(before):
		_queue_effect(tr("Dissolution called"), before)
	)
	_government_panel.reassigned.connect(func(before):
		_queue_effect(tr("Cabinet reassigned"), before)
	)

	_polling_panel = PollingPanel.new()
	_windows.register("society", tr("Society"), _polling_panel, KEY_P, ICONS + "forum.svg")
	# Loader from the start: the countdown names the chamber off the loader's
	# own titles, and a boot without it printed the generic "assembly" until
	# the first load put the two out of agreement.
	_polling_panel.setup(_state, _loader)
	_polling_panel.hide_close_button()

	_law_panel = LawPanel.new()
	_windows.register("legislature", tr("Legislature"), _law_panel, KEY_L, ICONS + "gavel.svg")
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
				body = tr("A referendum is already in flight.")
			else:
				body = tr("The assembly would not take it.")
		elif bool(result.get("withdrawn", false)):
			body = tr("Withdrawn.")
		elif bool(result.get("referendum_route", false)):
			body = tr("To the country -- the vote is scheduled.")
		else:
			body = (tr("Passed. Yes %d, No %d.") if bool(result.get("passed", false)) else tr("Failed. Yes %d, No %d.")) % [
				int(result.get("yes_seats", 0)), int(result.get("no_seats", 0)),
			]
		_hud.inbox.push(String(law_name), body)
		_update_top_bar()
	)

	# The nation panel loses its side-by-side pane and becomes what it always
	# behaved like: a card about whichever country was clicked. Opened by
	# _on_nation_clicked(), and reachable from the World cluster as well so the
	# diplomatic verbs are not hidden behind knowing to click the map.
	_nation_panel = NationPanel.new()
	_windows.register("diplomacy", tr("Diplomacy"), _nation_panel, KEY_D, ICONS + "handshake.svg")
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
			body = tr("Refused.") if reason.is_empty() else tr("Refused. %s") % reason
		else:
			body = tr("Agreed.")
		_hud.inbox.push(String(label), body)
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
	_windows.register("orgs", tr("Organisations"), _orgs_panel, KEY_U, ICONS + "corporate_fare.svg")
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
	_windows.register("calendar", tr("Diary"), _calendar_panel, KEY_C, ICONS + "calendar_month.svg")
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
	_windows.register("people", tr("People"), _people_panel, KEY_R, ICONS + "person.svg")
	_people_panel.setup(_state, _loader)
	_people_panel.hide_close_button()

	# V4.8b. What is pinned -- the agenda, firms in trouble, goods short, people
	# who are against the term -- as one register-driven list. A window rather
	# than a HUD plate (moving a plate moves the frames the 826 px band is
	# measured against); a row opens the window that answers it.
	_outliner_panel = OutlinerPanel.new()
	_windows.register("outliner", tr("Outliner"), _outliner_panel, KEY_Q, ICONS + "checklist.svg")
	_outliner_panel.setup(_state, _loader)
	_outliner_panel.hide_close_button()
	_outliner_panel.window_requested.connect(func(window_id: String): _windows.open(window_id))

	# V1.4a. In the Economy cluster rather than the World one: a firm is a domestic
	# actor and the verb pointed at it is a spending decision, which is why the bill
	# lands on the budget panel beside the deployment bill and not anywhere near
	# Diplomacy.
	_companies_panel = CompaniesPanel.new()
	# V1.6e renames the WINDOW and not the id: the panel now carries the state's own
	# sector programmes beside the firm register, so "Companies" had stopped being
	# what the surface is about. The id stays "companies" because it is what
	# domains.gd and tools/screenshot.gd --open both address.
	_windows.register("companies", tr("Industry"), _companies_panel, KEY_I, ICONS + "factory.svg")
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
	# window is one call plus a row in domains.gd.
	_projects_panel = ProjectsPanel.new()
	_windows.register("projects", tr("Public Works"), _projects_panel, KEY_W, ICONS + "construction.svg")
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
	_windows.register("region", tr("Regions"), _region_panel, KEY_T, ICONS + "map.svg")
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
	_windows.register("commodities", tr("Commodities"), _commodities_panel, KEY_H, ICONS + "inventory_2.svg")
	_commodities_panel.setup(_state, _loader)
	_commodities_panel.hide_close_button()

	# V2.2b, one level down, and the only V2 surface whose drawer entry is the
	# SECOND way in: the map's cross is the route, and this entry is for the
	# player who does not know that -- §16's own wording.
	_city_panel = CityPanel.new()
	_windows.register("city", tr("Cities"), _city_panel, KEY_V, ICONS + "location_city.svg")
	_city_panel.setup(_state, _loader)
	_city_panel.hide_close_button()

	# V2.8. KEY_F for fuel: E is Economy, N is Dispatches and G is Politics, so the
	# obvious letters were gone. The key rides register() itself -- V2.1c deleted the
	# seventh hand-written list of panel ids to get here, and the drawer's tooltip
	# reads the letter off the registry rather than restating it.
	_energy_panel = EnergyPanel.new()
	_windows.register("energy", tr("Energy"), _energy_panel, KEY_F, ICONS + "bolt.svg")
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
	_windows.register("campaign", tr("Campaign"), _campaign_panel, KEY_A, ICONS + "campaign.svg")
	_campaign_panel.setup(_state, _loader)
	_campaign_panel.hide_close_button()
	_campaign_panel.acted.connect(func(before, label):
		_queue_effect(label, before)
		_update_top_bar()
	)

	# V1.8. In the State cluster beside the Diary, and its own window rather than rows
	# on any existing panel. Registering one is one call plus a row in domains.gd --
	# and the reason it is a window rather than a modal is in the panel's own header:
	# a crisis the player can ignore and pay for is the whole of the deadline.
	_events_panel = EventsPanel.new()
	_windows.register("events", tr("Dispatches"), _events_panel, KEY_N, ICONS + "mail.svg")
	_events_panel.setup(_state, _loader)
	_events_panel.set_messages(_messages)
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
	_windows.register("summit", tr("Summit"), _summit_panel, KEY_NONE, ICONS + "account_balance.svg")
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

	_build_sidebar()
	_wire_hud()
	# V4.8a: an alert on the strip names the window that answers it by the title
	# its frame shows and the shortcut the window manager binds -- read here, once
	# every window is registered, so the strip never carries a hand-copied name.
	for id in _windows.panel_ids():
		var key: int = _windows.shortcut(id)
		var hint: String = _windows.title(id)
		if key != KEY_NONE:
			hint += " (%s)" % OS.get_keycode_string(key)
		_top_bar.window_hints[id] = hint
		# V5.1-c2.1. Every window is on the stack -- a domain at WORKSPACE, a
		# scene above it -- so Escape puts it away and a hotkey cannot reach past
		# a scene. Read here for the strip's reason: every window is registered.
		var layer: int = ScreenStack.SCENE if Domains.is_scene(id) else ScreenStack.WORKSPACE
		_stack.watch(layer, _windows.frame(id), _windows.close.bind(id))

	# Four panels stay modal, not docked: election results and censure land on
	# the player regardless of which tab is open, and settings/save-load are
	# reached through the pause menu rather than the rail.
	_election_panel = ElectionPanel.new()
	_stack.add(ScreenStack.SCENE, _election_panel, true)
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
	_stack.add(ScreenStack.SYSTEM, _save_load_panel, false, _save_load_panel.close)
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
	_stack.add(ScreenStack.SYSTEM, _settings_panel, false, _settings_panel.close)
	_settings_panel.hide()
	_settings_panel.closed.connect(func():
		# V4.8c: the settings screen is the register's only writer, so closing it
		# is the one moment the cached copy can go stale.
		_messages = MessageSettings.load_from(SettingsPanel.CONFIG_PATH)
		_events_panel.set_messages(_messages)
		_update_top_bar()
		_set_pause_menu_visible(true)
	)

	# Blocking, unlike every other panel: a pause menu you can click past into
	# the map underneath is not paused in any sense the player recognises.
	_pause_menu = PauseMenu.new()
	_stack.add(ScreenStack.SYSTEM, _pause_menu, true, _close_pause_menu)
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
	add_child(_month_runner)
	# V5.1-0b. Dev only, and the last child so it draws over everything: a debug
	# build or --dev-console gets F12's console, a release build gets nothing.
	# V5.1-c4.2: a guarded load(), not a preload, so an export filter can leave
	# the dev scripts out of a release entirely; install() gates the rest.
	if ResourceLoader.exists(DEV_CONSOLE): load(DEV_CONSOLE).install(self)

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
		_term_card_id = _hud.inbox.push(tr("Your term"), _term_card_body())

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


## V5.1-c2.3. The sidebar replaces U5a's action bar: one entry per domain with a
## registered tab, from domains.gd's table, so adding a surface is a register()
## call and a row there -- the drawer lists this function used to keep are gone.
## An entry opens its domain's first tab; the Inbox opens Dispatches until c3
## builds the inbox. Refused under a scene, as the keys are.
func _build_sidebar() -> void:
	_hud.sidebar.build(_windows.panel_ids())
	_hud.sidebar.navigate.connect(func(domain_id: String):
		if not _stack.accepts_hotkeys():
			return
		if domain_id == _hud.sidebar.INBOX:
			_hud.inbox.toggle_slide()
		else:
			_windows.open(String(Domains.tabs(domain_id, _windows.panel_ids())[0]))
	)


## The player's own pause/play (Space, the clock cluster's button, and since
## V5.1-d1a a speed picked on a paused clock) -- the only manual doors; the pause menu,
## the election dismissal and the holds below set it through their own paths.
## A manual toggle means the player has taken ownership of the clock, so the
## arrival flag drops: left up, a later answer or X on the last unseen card would
## run _resume_if_decision_settled() and unpause the clock against the player's
## own pause, and _decision_holds_clock() would keep holding it after an election
## dismissal or programme choice the player had already run past. The programme
## hold goes for the same reason: Space (run), Space (pause), then CHOOSE would
## otherwise unpause in _on_programme_chosen against the player's own pause. The
## card and the offer stay -- the player can still choose. Not touched:
## _unseen_events (the cards stay unseen) and an interrupt on the desk, which
## holds the clock on its own account.
func _toggle_pause_by_hand() -> void:
	# QA pre-gate. A press deferred while a month closed is replayed after its end
	# (month_runner.gd), which may have held the clock for a decision; a toggle
	# would resume it and the decision would lapse unanswered. A month closes only
	# on a running clock, so the press meant pause: on a clock already paused (a
	# hold it predates) it does nothing, otherwise it pauses below. Rejected:
	# replaying input before the month-end hooks, which would act every deferred
	# click on the pre-month UI and state.
	if _month_runner.replaying and _clock.paused: return
	# A scene owns the clock (QA on #54: the clock ran behind "RE-ELECTED"): the
	# election result holds until its Continue, by every door -- Space, the
	# cluster's play, a speed (V5.1-d1a, G4) -- not only by the key.
	if _stack != null and not _stack.accepts_hotkeys(): return
	# V5.1-0c. The offer lives only until the clock first runs in a term, so the
	# press that would forfeit it opens the Agenda instead -- once: when the Agenda
	# has shown the offer, the next press is the player declining, and runs.
	if _paused_for_programme and _clock.paused and not _agenda_panel.offer_seen(_state.player()):
		_windows.open("agenda")
		return
	_clock.toggle_pause()
	# V4.9c. By hand only: a pause the game takes (an arrival, the lapse guard)
	# already carries its own sound, the event sting, and a hold that resumes
	# itself is the world going on, not the player acting.
	Sound.cue(self, "pause" if _clock.paused else "resume")
	_paused_for_decision = false
	_paused_for_programme = false
	_update_top_bar()


## V5.1-d1a (G3, the play gate: "click on speed selection should unpause the
## game"). A speed picked on a paused clock is the player asking for time at that
## speed, so it plays -- through the same door as Space, and so with its gates:
## the programme offer, a scene that owns the clock (the election result), and a
## press replayed after a month close (#63: a deferred press never resumes).
func _set_speed_by_hand(speed: int) -> void:
	_clock.set_speed(speed)
	if _clock.paused: _toggle_pause_by_hand()
	_update_top_bar()


## V4.9c. The sound set's warm-up is a worker task, and a task the pool was
## given must be waited on before the scene that started it goes.
func _exit_tree() -> void:
	Sound.settle()


## Every signal the furniture emits, connected in one place. hud.gd builds and
## places the pieces and deliberately wires none of them -- it has no clock and
## no GameState, and giving it either would put game control in a layout file.
func _wire_hud() -> void:
	_hud.clock_cluster.pause_toggled.connect(_toggle_pause_by_hand)
	_hud.clock_cluster.speed_selected.connect(_set_speed_by_hand)
	_hud.title_bar.save_load_requested.connect(func():
		_save_from_menu = false
		_save_load_panel.show()
		_save_load_panel.mark_dirty()
	)
	_hud.title_bar.settings_requested.connect(_open_pause_menu)
	# V5.1-c2.3. Back and forward walk the window manager's path -- refused under
	# a scene, as the keys are, or back under a summit would open a tab over it.
	_hud.title_bar.back_requested.connect(func():
		if _stack.accepts_hotkeys():
			_windows.back()
	)
	_hud.title_bar.forward_requested.connect(func():
		if _stack.accepts_hotkeys():
			_windows.forward()
	)
	_hud.portrait_card.setup(_state, _loader)
	_setup_news()

	# V2.1c, and the FIRST CONSUMERS of two signals window_manager.gd has emitted
	# since U5a. The bar was the only route that marked itself: a keypress, a map
	# marker (U6c) and a message card (V1.8) each opened a window while the one
	# control that says where you are went on saying nothing. On close the mark
	# moves to whatever is still open rather than clearing, because a pinned
	# window is still where the player is.
	_windows.opened.connect(func(id: String):
		_hud.sidebar.select(Domains.domain_of(id))
		_hud.show_map_furniture(false, not Domains.is_scene(id))
	)
	# The legend is the map's, so it goes while a tab covers the map.
	_windows.closed.connect(func(_id: String):
		if _windows.open_ids().is_empty():
			_hud.sidebar.select("")
			_hud.show_map_furniture(true)
	)
	_hud.title_bar.follow(_windows, _loader.nations[_state.player_nation_id].nation_name)
	# A slid inbox is a layer: Escape slides it back, and the keys still work.
	_stack.follow_mode(ScreenStack.INBOX, _hud.inbox.slid, _hud.inbox.slide_out)

	# V1.8, and the first thing ever to connect this signal. inbox.gd has
	# emitted card_activated since U5a and nothing has listened, because until now every
	# card was a NOTIFICATION -- a foreign act, an obligation opening, a strike, a kept
	# appointment -- and there was nowhere for a click to go. An event card is a
	# QUESTION, so clicking it opens the window where it is answered. Every card routes
	# here and the window is right for all of them: whatever the player clicked, what
	# they wanted was the decision on their desk. V4.1's programme card routes to the
	# window where that choice is made instead -- the same rule, one card earlier.
	_hud.inbox.card_activated.connect(func(id: String):
		if not _programme_card_id.is_empty() and id == _programme_card_id:
			_windows.open("agenda")
			return
		# V4.7b: an industry card routes to the window where its verbs live.
		# (Focus-by-firm was deferred twice -- B2 to B3, and B3 shipped its
		# surfaces without it -- so it is an OPEN DEFERRAL, not a promise:
		# the click gets the player to the register, whose autonomy sections
		# surface the pending bid or failing firm. Recorded per the plan's
		# own rule, that a deferral is a decision and not a discovery.)
		if _industry_news.has_card(id):
			_windows.open("companies")
			return
		_windows.open("events")
	)

	# V2.9 + V4.4: a decision card's buttons answer the event THAT CARD names --
	# the same Events.answer chain Dispatches uses, with U4's before-snapshot
	# contract -- and the clock the arrival paused resumes only when nothing the
	# player has not seen is still on the desk. Only decision cards carry
	# buttons, so any card_action is a decision answer by construction.
	_hud.inbox.card_action.connect(func(id: String, index: int):
		var ns = _state.player()
		var event_id := String(_event_cards.get(id, ""))
		var ev = Events.event_by_id(_loader, event_id) if event_id != "" else null
		if ev == null or index >= ev.choices.size():
			return
		var before := Trends.snapshot_now(_state)
		var record := Events.answer(_state, _loader, event_id, String(ev.choices[index]["id"]))
		if record.is_empty():
			return
		_queue_effect("%s: %s" % [Strings.row_name("events", ev), Strings.choice_label(ev.id, ev.choices[index])], before)
		_event_cards.erase(id)
		_unseen_events.erase(event_id)
		_hud.inbox.dismiss(id)
		_resume_if_decision_settled()
		# Nothing holds now: the tab is the player's again.
		if not _decision_holds_clock(): _hud.inbox.slide_out()
		_update_top_bar()
		_windows.mark_all_dirty()
	)

	# The unseen set's second door. An X on a decision card used to strand the
	# event's id in _unseen_events: only an ANSWER erased it, so the arrival
	# pause could outlive every answer and hold the clock over an empty set. The
	# inbox's notes cap is NOT a door: it takes only the oldest NOTE (V5.1-c3.1;
	# a row with answers, or pushed with `protect`, is a decision and is never
	# evicted), so a crowd of plain cards cannot
	# "dismiss" a decision and restart the clock over it -- it reaches this
	# handler only for a plain card, whose id maps to no event. U5a's stack of
	# nothing but protected cards fell back to evicting the oldest; the inbox
	# has no such fallback, decisions are not capped. The
	# invariant, stated once across all its doors: AN ID LEAVES _unseen_events
	# WHEN IT LEAVES THE DESK OR ITS CARD IS DISMISSED. An id already taken off
	# the maps (the answer path above dismisses its own card after erasing)
	# falls through as "": both erases are no-ops and the resume is idempotent,
	# so this re-entry is harmless by construction.
	_hud.inbox.card_dismissed.connect(func(id: String):
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


## The panel alone -- `ScreenStack.add()`'s dimmed branch owns the holder and the
## dim, and it is the ONLY owner. Setting the holder here as well used to be the
## fix for a blocking CenterContainer that goes on swallowing map clicks while
## the panel inside it is invisible; now it would be a write the panel's own
## visibility_changed handler immediately reverts, because hiding a holder
## re-emits on the panel while the panel's own flag is still true. One writer,
## so the two cannot disagree and the order of two lines cannot decide whether
## the screen is clickable.
##
## `tests/test_shell.gd` still reads the HOLDER to ask whether the menu is open.
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

	# V5.1-c2.1. One question decides whether a letter may open a window: is the
	# screen still the player's to navigate -- the map, a domain, the inbox -- or
	# does a scene, a system screen or an armed reticle own it? B16's trap (with
	# the save dialog open, every letter was routed at the windows behind it) is
	# now one case of that rule rather than a flag of its own; S keeps its toggle
	# in the match below, so it can still close the dialog it opened.
	var navigable: bool = _stack == null or _stack.accepts_hotkeys()

	# V2.1c. The six letters U2 bound to tabs still open the six panels they
	# opened, and the other eight windows have a letter now -- but the map from
	# key to window lives at the register() call rather than in a match block
	# here, so the eight that were added since U5a could not have been left out.
	# A key TOGGLES rather than selects, because with no rail there is nothing
	# showing which panel is "current": pressing B twice puts the player back on
	# the map.
	if navigable and _windows != null:
		var by_key: String = _windows.id_for_key(event.keycode)
		if not by_key.is_empty():
			_toggle_window(by_key)
			return

	match event.keycode:
		KEY_ESCAPE:
			# V5.1-c2.1. The stack puts away what is on top: the save dialog
			# before the armed reticle (B16 -- a reticle CAN be armed with the
			# dialog open, its holder lets the map through), the reticle before
			# the pause menu (V2.8 -- Escape ending the thing it was offered for
			# is the mode's own contract), then a scene, then the domain. The
			# pause menu opens only when nothing there would go: the bare map,
			# or a term result, which only its own button dismisses.
			if _stack.cancel():
				return
			if _pause_menu != null:
				_open_pause_menu()
		KEY_SPACE:
			_toggle_pause_by_hand()
		KEY_1, KEY_2, KEY_3:
			_set_speed_by_hand(event.keycode - KEY_0)
		KEY_M:
			# M was the Europe tab. The map is now always underneath, so the
			# useful thing that key can do is clear everything off it -- a
			# navigation key, so not under a scene (it swept the summit away).
			if not navigable:
				return
			if _windows != null:
				_windows.close_all()
		KEY_S:
			if _save_load_panel != null:
				if _save_load_panel.visible:
					_save_load_panel.close()
				else:
					_save_from_menu = false
					_save_load_panel.show()
					_save_load_panel.mark_dirty()


## A fiscal command landed -- the Budget window's or the Tax Code's, both through
## Budget.commit(). The acknowledgment the playtest found missing: the biggest verb
## in the game used to answer with one corner number changing (F3).
func _fiscal_committed(label: String, title: String, before: Dictionary) -> void:
	_queue_effect(label, before)
	_hud.inbox.push(title, tr("Deficit now %s%% of GDP.") % Num.f(float(_state.player().deficit_pct_gdp), 2))
	_update_top_bar()


## Records a command's pre-commit baseline, to be measured once the month it
## was committed in actually elapses -- see _pending_effects and
## _on_month_elapsed()'s resolution loop.
##
## V5.1-0a: and every window is told the state moved. Every player command comes
## through here, and half of them swept nothing -- the budget window then kept its
## "now" books and forecast past a law or a subsidy, and credited the next lever
## move with the command's effect. A closed window's mark costs nothing.
func _queue_effect(label: String, before: Dictionary) -> void:
	_pending_effects.append({"label": label, "before": before})
	_windows.mark_all_dirty()


func _toggle_window(id: String) -> void:
	if _windows != null:
		_windows.toggle(id)


func _on_nation_clicked(nation_id: String) -> void:
	if _nation_panel == null or _windows == null:
		return
	# V5.1-c2.3. The mouse's route to a tab is refused under a scene, as the
	# keys are (V5.1-c2.1): a click on Germany under a summit closed the summit.
	if _stack != null and not _stack.accepts_hotkeys():
		return
	# Content before the window opens: open() places the frame by centring its
	# size, and a nation panel that has not been told which nation it is showing
	# reports the size of an empty one.
	_nation_panel.show_nation(nation_id)
	_windows.open("diplomacy")


## The panel armed a technology; the map is now waiting for the point.
var _armed_energy_action: String = ""


func _on_energy_order_armed(action_id: String) -> void:
	_armed_energy_action = action_id
	# V5.1-d1a (G6, the play gate: "as soon as placement time is enabled, the panel
	# should close to let the player put something on the map"). The order lives
	# here and on the map's reticle, so the workspace goes and the map is clear.
	_windows.close_all()
	_map_view.begin_placement()
	_stack.hold(ScreenStack.PLACEMENT, _cancel_placement)


## Escape's end of the armed mode, through the stack.
func _cancel_placement() -> void:
	_armed_energy_action = ""
	_energy_panel.clear_armed()
	_map_view.end_placement()
	_stack.release(ScreenStack.PLACEMENT)


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
	_stack.release(ScreenStack.PLACEMENT)
	var region_id := Region.region_at_lonlat(_loader.region_rings, lon, lat)
	var ns = _state.nations[_state.player_nation_id]
	var mine := false
	for region in _state.regions.get(_state.player_nation_id, []):
		if region.id == region_id:
			mine = true
	if not mine:
		# push(title, body) -- Inbox has never had a push_card(), so until the
		# V2.8 review this line raised instead of speaking, and the refusal the
		# comment above calls "loud rather than silent" reached the player as a
		# console error. The order is already consumed by here (the arm was cleared
		# above and map_view ended placement), so with nothing on screen the player
		# had to re-arm without being told why.
		_hud.inbox.push(tr("Not your ground"), tr("That point is not in %s.") % ns.nation_name)
		return

	var access: Dictionary = Regions.accessibility_for(ns, _state.regions.get(ns.id, []), _state.region_graph)
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
	var before := Trends.snapshot_now(_state)
	var result := Energy.execute(_state, ns, _loader, _loader.energy_actions, action,
		Vector2(lon, lat), region_id, "", access, pop_weights)
	if bool(result.get("applied", false)):
		_queue_effect(Strings.row_name("energy-actions", action), before)
	_windows.mark_all_dirty()
	_map_view.queue_redraw()
	_update_top_bar()


func _on_month_elapsed(year: int, month: int) -> void:
	if _state == null:
		return
	_state.year = year
	_state.month = month
	# The sim's whole month is src/sim/world_month.gd, the one copy of the order
	# every harness runs too. What stays here is the UI's half of it, threaded
	# through the step hook at the slot each card has always read from. V5.1-0a:
	# the runner spreads it over frames while real time passes, and hands the
	# report to _finish_month() once it has run.
	_month_runner.run(_state, _loader, _on_month_step.bind(year, month), _finish_month, _clock, _windows)


## The month's end, once every step has run -- in the frame the runner finishes
## it, or at once for a hand-driven day.
func _finish_month(report: Dictionary) -> void:
	# The month's sweep, moved here from the Calendar step's slot at V5.1-0a:
	# nothing draws between two steps of a month run whole, so the slot was never
	# observable -- but with the month across frames, a panel or the map redrawn
	# mid-month would show half of it. At the end it also re-syncs the budget's
	# untouched levers against the laws this month carried, not the rates before.
	_windows.mark_all_dirty()

	# U5c. The map draws only on hover, pan, zoom and resize, which was
	# complete while its colours came from a hash of the nation id and is not
	# now: relations drift every month and a trade weight moves with every
	# partner's GDP. Without this the data layers show the colours of
	# whenever the mouse last moved.
	if _map_view != null:
		# V2.6b1. The city list is rebuilt on the same monthly hook, and for a
		# sharper version of the same reason: a city's population is two live
		# shares times a live head count, and where the unions are out changes
		# with the grievance. Without this the crosses keep the sizes they had
		# at new game -- which is what V2.6a's "cities grow and shrink for
		# free" actually did on screen until the V2.6b1 screenshot pass looked
		# at a frame.
		_map_view.refresh_cities()
		_map_view.queue_redraw()

		# Same monthly hook and the same reason as the city list beside it: a
		# trade weight moves with every partner's GDP and an accessibility
		# index with every region's output share. Without this the convoys
		# keep the densities they had at new game, which is what "cities grow
		# and shrink for free" actually did on screen until a screenshot pass
		# looked.
		if _map_flows != null:
			_map_flows.refresh()

	# Elections run last, on the already-settled history entry, and can fire a
	# national and an EP result in the same month (France and Belgium, June
	# 2029). Any result pauses the clock — the player reads it before time moves
	# again, whether that reading ends in Continue or in defeat.
	var results: Array = report["election_results"]
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


## What one month's hook has captured BEFORE a step, for the card read AFTER it.
## Reset at the first step, so nothing carries from one month to the next.
var _month_capture: Dictionary = {}


## The UI's half of the month, called by WorldMonth.tick_month() before and
## after every step. Each card reads the record at the slot it always read it:
## a card that waited for the end of the month would read a register the later
## systems have moved on.
func _on_month_step(step: String, after: bool, report: Dictionary, year: int, month: int) -> void:
	if not after:
		match step:
			"Access":
				_month_capture = {}
			"Defence":
				# Counted either side of the tick so an obligation that opens can be
				# carded without src/sim/ growing a record for the UI to read. Derived
				# here rather than serialised, which is the same call V1.3f made for
				# foreign_acts in reverse: that one is state the sim already writes,
				# this one is a difference the UI can see for itself.
				_month_capture["obliged_before"] = _world_news.obliged_count()
			"Events":
				# `before` is captured for the U4 decision delta, because a default
				# arriving is a thing that happened to the player's budget with no
				# button pressed -- the class _card_appointment() already covers, and
				# the one case where the player did not even know a decision was
				# being made on their behalf.
				_month_capture["event_before"] = Trends.snapshot_now(_state)
				# V4.4: the before-state is the desk's CONTENT, not its emptiness -- a
				# resolve-and-replace month (one answered, another arrived) is
				# ordinary now, and the boolean edge detector fired neither branch on
				# exactly that month.
				var desk_before := {}
				for desk_entry in _state.player().event_queue:
					desk_before[String(desk_entry.get("event_id", ""))] = true
				_month_capture["desk_before"] = desk_before
		return

	match step:
		"Opinion":
			# V4.1. The conclusions, as cards -- deliberately AFTER Opinion and not
			# between the pair: the same-month guarantee is world_month.gd's, and
			# this hook writes neither counter. The read is safe anywhere BEFORE
			# Elections, which is the ONLY writer of the (terms_served,
			# months_in_term) pair concluded_this_month() matches against and which
			# runs last -- so the cards see exactly the conclusions the pulse was
			# priced on.
			_card_programme_conclusions()
		"History":
			# The stamped entry (year/month added), so movements_between() reads the
			# same "now" for approval's poll-noise lookup that the rest of the UI does.
			var dated_entry: Dictionary = (report["history_entry"] as Dictionary).duplicate(true)
			dated_entry["year"] = year
			dated_entry["month"] = month
			for pending in _pending_effects:
				_state.recent_effects.push_front({
					"label": pending["label"],  # i18n: row-ok an effect's label, routed when queued
					"year": year,
					"month": month,
					"movements": Trends.movements_between(pending["before"], dated_entry),
				})
			_pending_effects.clear()
			while _state.recent_effects.size() > RECENT_EFFECTS_KEPT:
				_state.recent_effects.remove_at(_state.recent_effects.size() - 1)
		"Legislature":
			# The ultra pass-4 finding: a held bill releasing writes
			# ns.last_law_result in Legislature's tick, and the assembly's own tick
			# (Statute) overwrites the same register when a private member's bill
			# divides the SAME month -- the release card was then permanently
			# unreachable, its only announcement surface read after both writers.
			# Capture the release before it can be swallowed and hand it to the
			# announcer beside the division; empty unless a release actually fired
			# (assembly_bill + released are the machine's own two keys for it).
			var assembly_release: Dictionary = {}
			var release_ns = _state.player()
			if release_ns != null:
				var release_result: Dictionary = release_ns.last_law_result
				if bool(release_result.get("assembly_bill", false)) \
						and bool(release_result.get("released", false)):
					assembly_release = release_result.duplicate(true)
			_month_capture["assembly_release"] = assembly_release
		"Statute":
			_assembly_news.announce(_month_capture.get("assembly_release", {}))
		"Defence":
			_world_news.card_obligations(int(_month_capture.get("obliged_before", 0)))
			# V1.3f: and now the nine act on their own initiative inside that tick,
			# so whatever they just did is read off the record and put in front of
			# the player.
			_world_news.card_foreign_acts(year, month)
		"Industry":
			_industry_news.announce()
		"Unrest":
			# V1.5c: the unions act inside that tick, and whatever they just did is
			# read off the record and put in front of the player.
			# _world_news.card_foreign_acts()'s split exactly -- the sim writes the record, the
			# UI decides what earns a card, and src/sim/ never reads the list back,
			# which tests/test_unrest.gd asserts over the whole directory.
			_world_news.card_unrest_acts(year, month)
		"Events":
			_card_events(year, month, _month_capture.get("desk_before", {}),
				_month_capture.get("event_before", {}))
			_enforce_interrupt()
		"Characters":
			# T5's surface: the acts go to the message stack as cards; the record is
			# not state.
			_world_news.card_character_acts(report["character_acts"])


## V1.8. What arrived on the desk this month, and what the clock decided when the
## player said nothing. The fifth caller of inbox.push() and the FIRST EVER
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
	if _hud == null or _hud.inbox == null or _state == null:
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
	var defaulted_names: Array[String] = []
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
		var named := Strings.record_event_name(record)
		var where := String(record.get("region_name", ""))
		if where != "":
			named = "%s — %s" % [named, where]
		_hud.inbox.push(tr("Decided for you"),
			tr("%s. Nobody answered, so it went the way it was always going to: %s.") % [named, Strings.record_choice_label(record)])
		defaulted_names.append(Strings.record_event_name(record))

	# The delta is queued HERE and not at the choice, because this is the one case
	# where the player made no decision -- U4's baseline still belongs against it,
	# or a budget that moved by default moves for no reason the ledger names. ONE
	# entry for the whole tick: every departure shares the same pre-tick snapshot,
	# so a queue entry per default would each claim the joint movement of all of
	# them (the cards stay one per event -- only the ledger line is merged).
	if not defaulted_names.is_empty():
		_queue_effect("; ".join(defaulted_names), before)

	# What ARRIVED: ids on the desk now that were not before. Each gets its own
	# decision card, answering its own row.
	# V4.9c: and ONE sting for the month, at the worst severity that arrived --
	# two crises in one tick are one piece of news to the ear, and two stings on
	# one frame would only be louder, not clearer. Gated on NOTIFY (author's
	# call, 2026-10-17): the sting is a notification, so a category the player
	# has told not to notify stays silent too.
	var sting_severity := 0
	for entry in ns.event_queue:
		var event_id := String(entry.get("event_id", ""))
		if desk_before.has(event_id):
			continue
		var ev = Events.event_by_id(_loader, event_id)
		if ev == null:
			continue
		# A decision the player has not seen must not expire behind their back:
		# "3 months to answer" at speed 3 is thirteen seconds, and both playtest
		# runs produced "Decided for you" records no player answered (2026-09-05).
		# Arrival pauses; the interrupt flag (V2.4b) still opens Dispatches on
		# top -- non-modal, per events-model's argument, but the clock waits
		# until everything unseen has been answered.
		# V4.8c: arrival pauses when the category's PAUSE band says so (default
		# Major+). A quiet arrival is still unseen -- it enters the set as false,
		# and _guard_lapses() holds the clock for it in its last month, so the
		# contract above is kept by name rather than by the arrival pause.
		var severity := int(entry.get("severity", 1))
		# An interrupt ignores the register entirely (message_settings.gd's
		# header; pending.gd's notify read does the same): the content says
		# "until answered", and a preference does not silence it (review pass 1).
		if bool(entry.get("interrupt", false)) \
				or MessageSettings.allows(_messages, ev.category, severity, "notify"):
			sting_severity = maxi(sting_severity, severity)
		var holds := MessageSettings.allows(_messages, ev.category, severity, "pause")
		if holds:
			_hold_for_decision()
		_unseen_events[event_id] = holds
		if MessageSettings.allows(_messages, ev.category, severity, "popup"):
			_push_decision_card(ev, entry)
	if sting_severity > 0:
		Sound.event_sting(self, sting_severity)

	# A quiet arrival's card stays up while the clock runs, so every live
	# decision card's deadline is re-read here, before the guard: a card saying
	# "3 months" beside a desk saying one is two readouts of one entry
	# disagreeing (review pass 2). Before V4.8c the arrival stopped the clock
	# and the sentence could not age under the player.
	_refresh_decision_bodies(ns)

	# After the arrivals, so a quiet arrival with one month to answer is caught
	# in the month it lands.
	_guard_lapses(ns)

	# The unseen set's third door re-check: the pause is re-judged AFTER the
	# arrivals, not beside the departure erase above -- a same-month
	# resolve-and-replace (one default fires, another crisis lands) must not
	# resume past the fresh arrival. The same three lines the card-answer path
	# runs.
	_resume_if_decision_settled()


## V4.8c, THE LAPSE GUARD -- the arrival pause's contract, kept for a quiet
## arrival. Every unanswered entry the pause band let through (false in the unseen
## set) whose countdown is down to its last month -- Events._tick_countdowns
## answers it by default on the NEXT tick -- now holds the clock, and gets its
## decision card if the popup band suppressed one: a clock stopped with nothing on
## screen saying why is the silent failure this column exists to catch. Runs every
## month, right after the tick moved the countdowns. An interrupt is not its
## business: _enforce_interrupt() holds those whatever the settings say.
func _guard_lapses(ns) -> void:
	for entry in ns.event_queue:
		var event_id := String(entry.get("event_id", ""))
		if not _unseen_events.has(event_id) or bool(_unseen_events[event_id]):
			continue
		if int(entry.get("months_left", 0)) > 1:
			continue
		var ev = Events.event_by_id(_loader, event_id)
		if ev == null:
			continue
		_unseen_events[event_id] = true
		_hold_for_decision()
		if not _event_cards.values().has(event_id):
			_push_decision_card(ev, entry)


## The decision card for one desk entry: the event's choices as buttons, the
## place in the title for a sited event, the plate beside it. One builder for the
## arrival and the lapse guard, so the guard's card is the arrival's card.
func _push_decision_card(ev, entry: Dictionary) -> void:
	if ev == null:
		return  # a desk entry whose event the content no longer has (a load)
	var event_id := String(entry.get("event_id", ""))
	var left := int(entry.get("months_left", 0))
	# The card itself is the answer surface. Since V4.8c a quiet arrival's card
	# can be answered with the clock running -- Events.answer is the same chain
	# either way; only the arrival pause used to guarantee a stopped world. The
	# default-choice marker is events_panel's own wording.
	var actions: Array = []
	for choice in ev.choices:
		actions.append({"label": "%s%s" % [
			Strings.choice_label(ev.id, choice),
			tr("   (happens if you say nothing)") if bool(choice.get("is_default", false)) else "",
		]})
	# The title names the place for a sited event -- read straight off the
	# entry, `event_name` untouched (V3.5). The name is already in the
	# register because every reader of it is a leaf over pending state.
	var title: String = Strings.row_name("events", ev)
	var where := String(entry.get("region_name", ""))
	if where != "":
		title = "%s — %s" % [title, where]
	# The same plate the Dispatches desk entry carries, on the title's side:
	# one crisis, one image, in both places it is read. Null (no art yet)
	# draws the card exactly as before -- missing art is silent.
	var art := EventArt.plate_texture(ev.category, int(entry.get("severity", 1)), event_id)
	var card_id: String = _hud.inbox.push(title, _decision_body(ev, left), actions, art)
	_event_cards[card_id] = event_id


## Every live decision card's deadline sentence, re-read off the desk. A card
## whose event has left the desk was dismissed above; one the eviction dropped is
## a set_body() no-op.
func _refresh_decision_bodies(ns) -> void:
	var left_by_id := {}
	for entry in ns.event_queue:
		left_by_id[String(entry.get("event_id", ""))] = int(entry.get("months_left", 0))
	for card_id in _event_cards.keys():
		var event_id := String(_event_cards[card_id])
		if not left_by_id.has(event_id):
			continue
		var ev = Events.event_by_id(_loader, event_id)
		if ev != null:
			_hud.inbox.set_body(String(card_id), _decision_body(ev, int(left_by_id[event_id])))


## Whether any unseen id holds the clock -- V4.8c's reading of what used to be
## "the unseen set is not empty": a quiet id is unanswered but holds nothing.
func _unseen_holds() -> bool:
	return _unseen_events.values().has(true)


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
## ORDER MATTERS (pass 16): the interrupt test comes BEFORE the programme's. With
## both pending, the programme branch used to drop the flag first; the programme's
## choice then left the interrupt held with no flag, and answering the interrupt
## found nothing to release. Interrupt pending keeps the flag whatever else holds.
func _resume_if_decision_settled() -> void:
	if not _paused_for_decision or _unseen_holds():
		return
	var ns = _state.player() if _state != null else null
	if ns != null and Events.interrupt_pending(ns):
		return
	if _paused_for_programme:
		_paused_for_decision = false
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
	if _paused_for_decision and _unseen_holds():
		return true
	var ns = _state.player() if _state != null else null
	return ns != null and Events.interrupt_pending(ns)


## Dismiss every message-stack card keyed to an event that has left the desk.
## Finds card ids in _event_cards mapping to `event_id`, dismisses each, and
## iterates a copy of the keys because `dismiss()` emits `card_dismissed` whose
## handler erases from _event_cards -- re-entry is harmless; the handler also
## erases from _unseen_events, which is a no-op when the caller already erased it.
func _dismiss_event_cards(event_id: String) -> void:
	if _hud == null or _hud.inbox == null:
		return
	for card_id in _event_cards.keys().duplicate():
		if String(_event_cards.get(card_id, "")) == event_id:
			_hud.inbox.dismiss(card_id)


## The decision card's body: the event's summary line, then the deadline -- the
## same two sentences the arrival card has always carried, now beside buttons
## that answer it (V2.9).
func _decision_body(ev, left: int) -> String:
	return tr_n("%s  You have %d month to answer.", "%s  You have %d months to answer.", left) % [
		Strings.row_summary("events", ev), left,
	]


func _setup_news() -> void:
	for writer in [_world_news, _industry_news, _assembly_news]:
		writer.setup(_state, _loader, _hud.inbox)
	_stack.tips.setup(_state, _loader)


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


## The diary's due appointments, fired by DiaryDriver (src/ui/diary_driver.gd) in the
## diary's order; each outcome's UI half lands here before the next entry fires.
func _resolve_appointments(year: int, month: int, day: int) -> void:
	var any := DiaryDriver.resolve(_state, _loader, year, month, day, func(outcome: Dictionary):
		var label := String(outcome["label"])  # i18n: row-ok DiaryDriver hands back a translated label
		if not label.is_empty():
			_queue_effect(label, outcome["before"])
		_world_news.card_appointment(outcome["entry"], label, bool(outcome["ok"]))
		if String(outcome["summit_target"]) != "":
			_open_summit(String(outcome["summit_target"]), outcome["before"])
	)
	if not any:
		return
	_windows.mark_all_dirty()
	# A booked diplomatic act moves relations, and on that map layer it is a
	# colour change the player should see the day it happens -- the same reason
	# nation_panel's own `acted` handler redraws. The arcs move on the same day
	# and for the same reason the handler refreshes them.
	if _map_view != null:
		_map_view.queue_redraw()
		if _map_flows != null:
			_map_flows.refresh()


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
	_queue_effect(tr("Summit: %s") % choice_label, _summit_before)
	_update_top_bar()




func _on_save_requested(slot: String) -> void:
	var error := SaveManager.save_game(_state, _clock, slot)
	if error.is_empty():
		_save_load_panel.report(tr("Saved '%s'.") % slot)
	else:
		_save_load_panel.report(tr("Save failed: %s") % error)
	_save_load_panel.mark_dirty()


## Loading replaces the live GameState wholesale, so every panel holding a
## reference to the old one has to be pointed at the new one -- the same
## setup() calls _ready() made the first time, not a special load path.
func _on_load_requested(slot: String) -> void:
	var result := SaveManager.load_game(slot, _loader)
	if not result["ok"]:
		_save_load_panel.report(tr("Load failed: %s") % result["error"])
		_save_load_panel.mark_dirty()
		# Shown, not merely written to. report() paints a HIDDEN panel on the menu
		# path -- _ready() has already built a new game by then, so without this a
		# failed Continue starts a fresh France and says nothing at all.
		_save_load_panel.show()
		_clock.paused = true
		return

	_state = result["state"]
	UiTheme.apply_for(self, _loader.nations[_state.player_nation_id])  # a loaded game may be another nation's
	# The announce memories and live-card maps belong to the DISCARDED game:
	# firm ids are content, so the same id failing in the loaded game would
	# be card-silent behind this session's carried entries -- the pass-15
	# fleet's reproduced find. The stack's ids are monotonic, so a card id never
	# collides across the load; the cards themselves are cleared just below.
	_industry_news.forget()
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
	_assembly_news.forget(_state.player().last_law_result)
	# The V4.4 desk's three ride the same rule -- a stale unseen id would hold
	# the clock past the load and a discarded game's decision card would route
	# Events.answer against the loaded state (the decision pause beside the
	# load's own pause below is the third).
	# The discarded game's cards leave the STACK too, ALL of them: clearing only the
	# map left decision cards' answer buttons on screen, looking live and doing
	# nothing (card_action finds no event for the id and returns silently), and
	# the plain ones -- "You hold Germany until FEB 2029" over a loaded France game
	# (V5.1-a2) -- were never in any map to begin with.
	_hud.inbox.clear()
	_term_card_id = ""
	_event_cards.clear()
	_unseen_events.clear()
	# The discarded game's programme card goes too: _enforce_term_start_programme()
	# below returns early for a mid-term load, which would leave "choose one
	# goal..." standing (and its id set) over a game with nothing to choose.
	_drop_programme_card()
	# A decision committed and not yet measured belongs to the DISCARDED game:
	# left queued, the loaded game's next History step wrote it into its own
	# recent_effects against the old game's baseline (the V5.0 fix-pass review).
	_pending_effects.clear()
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
	_hud.title_bar.set_nation(_loader.nations[_state.player_nation_id].nation_name)
	_hud.portrait_card.setup(_state, _loader)
	_setup_news()
	# The mirror is re-established here rather than waiting for the first day to
	# elapse, because a loaded game opens PAUSED: without this the diary would
	# refuse a booking for today as "that date has passed" until the player
	# unpaused, which is a rule the player cannot see and did not break.
	_state.day = _clock.day

	_windows.mark_all_dirty()

	# V5.1-c3.2. The loaded desk back in the inbox's Decisions lane: the clear
	# above took the discarded game's rows, and a pending question with no row
	# could be answered only from Dispatches (Review focus 2).
	for entry in _state.player().event_queue:
		_push_decision_card(Events.event_by_id(_loader, String(entry.get("event_id", ""))), entry)
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

	_save_load_panel.report(tr("Loaded '%s'.") % slot)
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
	# The interrupt pause IS a decision pause: raising the flag here (the load
	# path and a month's re-pause both reach this) is what lets the answer's
	# _resume_if_decision_settled() release it; without it a re-raised interrupt
	# stayed paused after being answered.
	_hold_for_decision()


## Every decision that holds the clock -- an arrival the pause band stops, the
## lapse guard's last month, an interrupt -- raises the decision pause and slides
## the inbox, where it is answered, over an open tab (the author's call 4 is "a
## decision that holds the clock", not only an interrupt: QA on #54). Not behind
## a scene or a system screen; _on_stack_top_changed() slides it when that goes.
func _hold_for_decision() -> void:
	_paused_for_decision = true
	_clock.paused = true
	if _stack != null and _stack.top() < ScreenStack.SCENE:
		_hud.inbox.slide_in()
	_hud.clock_cluster.refresh(_clock)


## The other half of the deferral above: a scene or a system screen went with an
## interrupt still on the desk, so the player now sees where it is answered -- a
## held clock with nothing on screen saying why is the failure this prevents.
func _on_stack_top_changed(from: int, to: int) -> void:
	_hud.map_legend.show_placing(to == ScreenStack.PLACEMENT)
	if from >= ScreenStack.SCENE and to < ScreenStack.SCENE and _decision_holds_clock():
		_hold_for_decision()


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
	return tr("You hold %s until %s %d -- %s. Win the vote.") % [_loader.nation_name(_state.player_nation_id), DateText.month(when.y), when.x, Trends.months_text(Trends.months_to_vote(_state, ns))]


## The monthly refresh of the opening card, from _on_month_elapsed(). The body
## is rewritten in place (set_body keeps the card's position; a dismiss-then-
## re-push would jump the stack) while there is still a vote ahead, and the
## card is TAKEN AWAY once there is not -- a "Win the vote" card standing next
## to a verdict that already held it is the same stale class B4 photographed.
## A gone id (evicted by the notes' cap, or never pushed on a load) no-ops through
## set_body and the empty-id guards here.
func _refresh_term_card() -> void:
	if _term_card_id.is_empty() or _hud == null or _hud.inbox == null:
		return
	var ns = _state.player()
	if ns == null:
		# Out of office: the verdict surface took over, the same dismiss as the
		# no-vote-left branch below, without reading a null nation.
		_hud.inbox.dismiss(_term_card_id)
		_term_card_id = ""
		return
	if Trends.months_to_vote(_state, ns) <= 0:
		_hud.inbox.dismiss(_term_card_id)
		_term_card_id = ""
		return
	_hud.inbox.set_body(_term_card_id, _term_card_body())


## The term-start card and its id go together; every door that retires one retires both.
func _drop_programme_card() -> void:
	if not _programme_card_id.is_empty():
		_hud.inbox.dismiss(_programme_card_id)
		_programme_card_id = ""


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
		# The offer is gone without a choice (the player ran the clock past the
		# term start): the hold and its card are stale. Left up, every later
		# arrival answer would take _resume_if_decision_settled()'s programme
		# branch, drop the arrival flag and never resume -- a stranded clock. Only
		# the flag and the card go; the clock stays as the player has it.
		_paused_for_programme = false
		_drop_programme_card()
		return
	_drop_programme_card()
	_programme_card_id = _hud.inbox.push(
		tr("The term's programme"),
		tr("The agenda holds the offer. Choose one goal before the clock runs -- the register prices the delivery, not the promise."),
		[], null,
		# Protected: this plain card explains a live clock hold, and a few plain
		# pushes at a term start would otherwise evict it as the oldest.
		true,
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
	var before := Trends.snapshot_now(_state)
	var result: Dictionary = Programme.choose(_state, ns, entry_id, _loader)
	if bool(result.get("refused", false)):
		_hud.inbox.push(tr("Programme refused"), _programme_refusal_text(String(result.get("reason", ""))))
		return

	# Entry open, as a card -- the register now holds the term's programme,
	# and the pulse it will pay lives on its conclusion, not here.
	var name_text := Strings.row("programme", entry_id, "name", String(result.get("name", entry_id)))
	_queue_effect(tr("Programme set: %s") % name_text, before)
	_hud.inbox.push(name_text, tr("This term's programme. Deliver it and the credit lands on the record; miss its deadline and the miss pays the same shape back."))
	_drop_programme_card()
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
			return tr("The term has already begun.")
		"already_chosen":
			return tr("This term's programme is already set.")
		"not_offerable":
			return tr("That goal is not on offer.")
	return ""


## V4.1. What concluded this month, as a card -- complete, fail and invalid
## alike, concluded_this_month()'s one read. _world_news.card_foreign_acts()'s split: the
## sim writes the record, the UI decides what earns a card, and src/sim/ never
## reads the list back. Called from _on_month_step() INSIDE the tick window
## the pulse is priced in -- see the Programme.tick_month call site in
## src/sim/world_month.gd.
func _card_programme_conclusions() -> void:
	if _hud == null or _hud.inbox == null or _state == null:
		return
	var ns = _state.player()
	if ns == null:
		return
	for entry in Programme.concluded_this_month(ns):
		var terms: Dictionary = Programme.terms_of(_loader, String(entry["entry_id"]))
		var name_text := Strings.row("programme", String(entry["entry_id"]), "name", String(terms.get("name", String(entry["entry_id"]))))
		match String(entry["status"]):
			ProgrammeK.STATUS_COMPLETE:
				_hud.inbox.push(tr("Delivered: %s") % name_text,
					tr("The goal is met, and the register marks it complete."))
			ProgrammeK.STATUS_FAIL:
				_hud.inbox.push(tr("Missed: %s") % name_text,
					tr("The goal was not met in time, and the register marks the miss."))
			_:
				_hud.inbox.push(tr("Overtaken: %s") % name_text,
					tr("The world moved on and the entry no longer applies. It concludes without a verdict."))


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
		_hud.sidebar.show_pending(Pending.window_ids(_state, _loader, _messages))
		# V5.1-c2.3. Why the clock is not running, in the title bar: a decision
		# holding it is the case a player must not have to guess.
		_hud.title_bar.set_held(tr("A decision is waiting") if _decision_holds_clock() else "")
