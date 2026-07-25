extends Control

const DataLoader = preload("res://src/core/data_loader.gd")
const Nation = preload("res://src/core/nation.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const Elections = preload("res://src/sim/elections.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const BudgetPanel = preload("res://src/ui/budget_panel.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const ElectionPanel = preload("res://src/ui/election_panel.gd")
const LawPanel = preload("res://src/ui/law_panel.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const MapView = preload("res://src/ui/map_view.gd")
const NationPanel = preload("res://src/ui/nation_panel.gd")
const SaveLoadPanel = preload("res://src/ui/save_load_panel.gd")
const SaveManager = preload("res://src/core/save_manager.gd")

const PLAYER_NATION_ID := "FRA"

@onready var _clock: Node = $Clock
@onready var _hud: Label = $HUD

const MONTH_NAMES: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

var _state
var _loader: DataLoader
var _budget_panel
var _polling_panel
var _election_panel
var _law_panel
var _map_view
var _nation_panel
var _save_load_panel


func _ready() -> void:
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

	_state = GameState.new_game(_loader, PLAYER_NATION_ID)
	if not _state.errors.is_empty():
		for e in _state.errors:
			push_error(e)
		return
	_state.year = _clock.year
	_state.month = _clock.month

	# The map is a full-screen background layer, not a modal panel like the
	# other three -- added first, then moved to sibling index 0 so the HUD
	# (already in the scene from main.tscn) and every panel below draw on
	# top of it rather than the map drawing over everything else.
	_map_view = MapView.new()
	add_child(_map_view)
	move_child(_map_view, 0)
	_map_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_view.setup(_loader, _state)
	_map_view.nation_clicked.connect(_on_nation_clicked)

	_budget_panel = BudgetPanel.new()
	_add_centered(_budget_panel)
	_budget_panel.setup(_state)
	_budget_panel.hide()
	_budget_panel.committed.connect(_update_hud)

	_polling_panel = PollingPanel.new()
	_add_centered(_polling_panel)
	_polling_panel.setup(_state)
	_polling_panel.hide()

	_election_panel = ElectionPanel.new()
	_add_centered(_election_panel)
	_election_panel.setup(_state, _loader)
	_election_panel.hide()
	_election_panel.dismissed.connect(func(): _clock.paused = false)

	_law_panel = LawPanel.new()
	_add_centered(_law_panel)
	_law_panel.setup(_state, _loader)
	_law_panel.hide()
	_law_panel.proposed.connect(_update_hud)

	_nation_panel = NationPanel.new()
	_add_centered(_nation_panel)
	_nation_panel.setup(_state, _loader)
	_nation_panel.hide()

	_save_load_panel = SaveLoadPanel.new()
	_add_centered(_save_load_panel)
	_save_load_panel.hide()
	_save_load_panel.save_requested.connect(_on_save_requested)
	_save_load_panel.load_requested.connect(_on_load_requested)

	_clock.day_advanced.connect(_on_day_advanced)
	_clock.month_elapsed.connect(_on_month_elapsed)
	_update_hud()


## Screen-filling CenterContainer per panel, which is the one placement mechanism
## that works before a panel's children exist — an anchor preset computed in
## _ready() reads a minimum size of zero and lands in the corner. One container
## each, so hiding one panel does not move the other.
func _add_centered(panel: Control) -> void:
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(panel)
	add_child(holder)

	# The default panel style is translucent, so the HUD reads through a screen
	# full of figures. Opaque until S10 gives the game an actual theme.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.11, 0.12, 0.13)
	style.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", style)


func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_SPACE:
			_clock.toggle_pause()
			_update_hud()
		KEY_1:
			_clock.set_speed(1)
			_update_hud()
		KEY_2:
			_clock.set_speed(2)
			_update_hud()
		KEY_3:
			_clock.set_speed(3)
			_update_hud()
		KEY_B:
			if _budget_panel != null:
				_budget_panel.visible = not _budget_panel.visible
				if _budget_panel.visible:
					_budget_panel.mark_dirty()
		KEY_P:
			if _polling_panel != null:
				_polling_panel.visible = not _polling_panel.visible
				if _polling_panel.visible:
					_polling_panel.mark_dirty()
		KEY_L:
			if _law_panel != null:
				_law_panel.visible = not _law_panel.visible
				if _law_panel.visible:
					_law_panel.mark_dirty()
		KEY_S:
			if _save_load_panel != null:
				_save_load_panel.visible = not _save_load_panel.visible
				if _save_load_panel.visible:
					_save_load_panel.mark_dirty()


func _on_nation_clicked(nation_id: String) -> void:
	if _nation_panel == null:
		return
	_nation_panel.show_nation(nation_id)
	_nation_panel.show()


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
	Opinion.tick_month(_state)

	var entry := Budget.snapshot(_state)
	entry.merge(Opinion.snapshot(_state))
	_state.append_history(entry)

	if _budget_panel != null:
		_budget_panel.mark_dirty()
	if _polling_panel != null:
		_polling_panel.mark_dirty()
	if _law_panel != null:
		_law_panel.mark_dirty()
	if _nation_panel != null:
		_nation_panel.mark_dirty()

	# Cooldowns count down before the election check, same ordering reasoning as
	# everything else in this handler: state settles top to bottom, elections
	# read it last.
	Legislature.tick_month(_state)

	# Elections run last, on the already-settled history entry, and can fire a
	# national and an EP result in the same month (France and Belgium, June
	# 2029). Any result pauses the clock — the player reads it before time moves
	# again, whether that reading ends in Continue or in defeat.
	var results := Elections.tick_month(_state, _loader)
	if not results.is_empty() and _election_panel != null:
		_clock.paused = true
		_election_panel.show_results(results)
		_election_panel.show()


func _on_day_advanced(_year: int, _month: int, _day: int) -> void:
	_update_hud()


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
		return

	_state = result["state"]
	_clock.year = _state.year
	_clock.month = _state.month
	_clock.day = int(result["day"])
	_clock.paused = true

	_map_view.setup(_loader, _state)
	_budget_panel.setup(_state)
	_polling_panel.setup(_state)
	_election_panel.setup(_state, _loader)
	_law_panel.setup(_state, _loader)
	_nation_panel.setup(_state, _loader)

	_budget_panel.mark_dirty()
	_polling_panel.mark_dirty()
	_law_panel.mark_dirty()
	_nation_panel.mark_dirty()

	_save_load_panel.report("Loaded '%s'." % slot)
	_save_load_panel.mark_dirty()
	_update_hud()


func _update_hud() -> void:
	var month_name: String = MONTH_NAMES[_clock.month - 1]
	var state_text := "paused" if _clock.paused else "speed %d" % _clock.speed
	var line := "%s %d, %d — %s" % [month_name, _clock.day, _clock.year, state_text]

	if _state != null:
		var ns = _state.player()
		line += "\nGDP EUR %.0fbn   growth %+.2f%%   unemployment %.1f%%" % [
			ns.gdp_eur_bn, ns.growth_annual_pct, ns.unemployment_pct
		]
		line += "\ndebt %.1f%% of GDP   deficit %+.2f%% of GDP" % [
			ns.debt_to_gdp_pct(), -ns.deficit_pct_gdp
		]
		# The polled figure, not the true one — the HUD must not leak what the
		# polling panel is deliberately blurring.
		var poll := PollNoise.displayed(
			PollNoise.poll_id(_state.year, _state.month),
			PollingPanel.HEADLINE_KEY,
			ns.overall_approval_pct
		)
		line += "\napproval %.0f%% (poll)   [B] budget   [P] polling   [L] legislature" % poll

	_hud.text = line
