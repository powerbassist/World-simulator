extends RefCounted

## The Sectors domain's wiring in main.gd's shell -- V5.3 screen 5, slice 1. Here rather
## than in main.gd, which is at its size ratchet (tools/check_size.py). main.gd keeps one
## literal register() per sector tab (the strip's and the outliner's tests read the
## registered window ids off those calls); this file makes the tabs and keeps their marks.

const SectorPanel = preload("res://src/ui/sector_panel.gd")
const SectorNeeds = preload("res://src/ui/sector_needs.gd")
const Pending = preload("res://src/ui/pending.gd")


## A sector's tab, set up and kept in main._sector_panels; its Needs you Go opens the
## overview. Setup only stores the state (no node is touched), so it may precede the
## register() that puts the tab in the tree.
static func tab(main, sector: String) -> Control:
	var panel = SectorPanel.new(sector)
	panel.setup(main._state, main._loader)
	panel.go_firm.connect(open_firm.bind(main))
	# Slice 2: the sheet's commands earn a decision delta, as the overview's do.
	panel.acted.connect(func(before, label) -> void:
		main._queue_effect(label, before)
		main._update_top_bar())
	# The phone's scripts are loaded at the call, not preloaded: a preload here closed a
	# script cycle that crashed the engine at exit (exit 139 after every test, found by bisecting).
	panel.call_requested.connect(func(pid: String) -> void:
		var talks = load("res://src/ui/audience_talks.gd")
		load("res://src/ui/phone_driver.gd").open_call(main, pid, talks.gossip_people(main, pid)))
	panel.map_requested.connect(func(lonlat: Vector2) -> void:
		main._windows.close_all()
		main._map_view.center_on_lonlat(lonlat.x, lonlat.y))
	main._sector_panels[sector] = panel
	return panel


## The per-day pending pass: the sidebar's counts, then the sector tabs' hourglass and
## count, both from SectorNeeds through pending.gd, so they cannot disagree.
static func show_pending(main) -> void:
	main._hud.sidebar.show_pending(Pending.window_ids(main._state, main._loader, main._messages))
	refresh_marks(main)


static func refresh_marks(main) -> void:
	var ns = main._state.player() if main._state != null else null
	main._windows.set_tab_counts(SectorNeeds.counts(main._state, main._loader, ns))


## A Needs you row's Go: the overview, with the firm's sector and its verbs opened (the
## answers live there until screen 5's slice 2).
static func open_firm(sector: String, company_id: String, main) -> void:
	main._companies_panel._open_sector = sector
	main._companies_panel._open_firm = company_id
	main._companies_panel.mark_dirty()
	main._windows.open("companies")
