extends PanelContainer

## The energy readout and the order form -- V2.8. Model: docs/energy-model.md.
##
## THE VERBS SIT ABOVE THE READOUT, V2.1b's politics-panel lesson made
## structural: no height clears 945px of content, so the fold contract is met by
## putting what the player presses where the plate can always see it rather than
## by tuning a height.
##
## PRESSING AN ORDER BUTTON DOES NOT COMMIT. It arms placement mode -- the map
## click is the commit -- and the section's own line says so. There is
## deliberately NO region OptionButton fallback: two routes to one verb is two
## things to keep in step, and this block exists to make the click the way you
## build. `decommission` is the exception and takes a plant OptionButton,
## because a station that already exists is picked from a list rather than
## pointed at twice.
##
## The panel never learns that a map exists: it emits `order_armed` and
## main.gd holds the map, resolves the click and executes -- Budget.commit()'s
## boundary for player intent, one window over.

signal closed
signal acted(before, label)
signal order_armed(action_id: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Trends = preload("res://src/ui/trends.gd")
const Energy = preload("res://src/sim/energy.gd")
const Num = preload("res://src/ui/num.gd")

var _state
var _loader
var _dirty := true

## The action the player has armed but not yet placed. "" is nothing armed.
var _armed_id := ""

var _title: Label
var _body: VBoxContainer
var _close_button: Button
var _status: Label
var _primary: Control

## The fleet section's own container, kept so a map click on a glyph can bring it
## above the fold -- the project marker's route into Public Works, one pass over.
var _fleet_group: Control = null
## V5.1-0a. The map's route asked for the fleet section. A panel builds only while
## its window shows, and the route opens the window and asks in the same frame --
## so the ask waits for the section to exist and be laid out (_process()).
var _fleet_wanted := false
var _scroll: ScrollContainer = null


func _ready() -> void:
	custom_minimum_size = Vector2(600, 720)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.LEAD
	root.add_child(_title)

	# Kept rather than discarded: ensure_control_visible() is a ScrollContainer
	# method, and scroll_to_fleet() below is the map's own route into this panel.
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(_scroll)
	var scroll := _scroll

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 4)
	scroll.add_child(_body)

	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	# A frame after the build, so the containers have laid the section out.
	if _fleet_wanted and not _dirty and _fleet_group != null and is_instance_valid(_fleet_group):
		_fleet_wanted = false
		_scroll.ensure_control_visible(_fleet_group)
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


## main.gd's answer to a pick, a cancel or an Escape: the armed action is
## un-armed and the section's line goes back to its rest state.
func clear_armed() -> void:
	if _armed_id != "":
		_armed_id = ""
		_dirty = true


## The control this panel exists to let the player press -- V2.1a's fold contract.
## Duck-typed: tab_page.gd asks through has_method(), so a panel with nothing
## to press simply does not implement this and never draws the fold mark. The
## FIRST enabled order is the answer rather than the last, because a panel whose
## first verb has scrolled off is already a panel whose verbs are hidden.
func primary_action() -> Control:
	return _primary if is_instance_valid(_primary) else null


func _refresh() -> void:
	for child in _body.get_children():
		child.queue_free()

	var ns = _state.player()
	if ns == null:
		return
	var nation = _loader.nations.get(ns.id)
	if nation == null:
		return

	_title.text = tr("The electricity of %s") % nation.nation_name

	_primary = null
	_build_order(ns)
	_build_mix(ns)
	_build_dependency(ns)
	_build_emissions(ns)
	_build_fleet(ns)


func _build_order(ns) -> void:
	var group := PanelKit.section(_body, tr("Order"))

	_status = PanelKit.plain_line(group, _armed_line(), PanelKit.Tone.PLAIN)

	var offered := 0
	for action in Energy.available(_state, ns, _loader.energy_actions):
		var terms: Dictionary = action.effects.get("energy", {})
		if String(terms.get("op", "")) != "order":
			continue
		var source = _loader.energy_sources.get(String(terms.get("source_id", "")))
		if source == null:
			continue
		offered += 1
		PanelKit.line(group, tr("%s · %s · %d months · %s %% of GDP a year to build, %s %% of GDP a year to run") % [
			source.source_name, source.branch, source.build_months,
			Num.f(source.build_cost_pct_gdp, 3), Num.f(source.run_cost_pct_gdp, 3),
		])
		var button := PanelKit.sized(Button.new())
		button.text = Strings.row_name("energy-actions", action)
		button.tooltip_text = Strings.row_summary("energy-actions", action)
		button.pressed.connect(func(): _on_order(action.id))
		if _primary == null:
			_primary = button
		group.add_child(button)
	if offered == 0:
		PanelKit.line(group, tr("Nothing can be ordered right now -- the deficit precondition is not met."))

	# DECOMMISSION IS THE EXCEPTION AND TAKES A LIST. A station that exists is
	# picked from the fleet; the run cost stops when it closes, which is the whole
	# reason the off switch is a verb rather than a clock.
	var built: Array = []
	for plant_id in ns.plants.keys():
		built.append(String(plant_id))
	if built.is_empty():
		return
	var pick := OptionButton.new()
	for plant_id in built:
		pick.add_item(plant_label(ns, plant_id, _loader))
	var close := Button.new()
	close.text = tr("Close a station")
	close.pressed.connect(func(): _on_decommission(ns, String(built[pick.get_selected_id()])))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(pick)
	row.add_child(close)
	group.add_child(row)


func _armed_line() -> String:
	if _armed_id == "":
		return tr("Pick a technology. The next click on the map places it.")
	return tr("Click where it goes. Escape to cancel.")


func _on_order(action_id: String) -> void:
	_armed_id = action_id
	_dirty = true
	order_armed.emit(action_id)


func _on_decommission(ns, plant_id: String) -> void:
	var action = null
	for a in _loader.energy_actions:
		if String(a.effects.get("energy", {}).get("op", "")) == "decommission":
			action = a
	if action == null or not ns.plants.has(plant_id):
		return
	var before := Trends.snapshot_now(_state)
	var entry: Dictionary = ns.plants[plant_id]
	# A close reads no geography: the connection was a build-time fact and the
	# siting price was charged once, when the station was ordered.
	var result := Energy.execute(_state, ns, _loader, _loader.energy_actions, action,
		Vector2(float(entry.get("lon", 0.0)), float(entry.get("lat", 0.0))),
		String(entry.get("region_id", "")), plant_id, {}, {})
	if not bool(result.get("applied", false)):
		return
	_dirty = true
	acted.emit(before, Strings.row_name("energy-actions", action))


func _build_mix(ns) -> void:
	var group := PanelKit.section(_body, tr("The mix"))
	var live: Dictionary = Energy.mix(ns, _loader)
	var rows: Array = []
	for branch in ["fossil", "nuclear", "renewable"]:
		var now: float = float(live.get(branch, 0.0))
		var start: float = float(ns.start_energy_mix.get(branch, 0.0))
		rows.append([
			Labels.energy_branch(branch),
			"%s%%" % Num.f((now * 100.0), 2),
			PanelKit.delta((now - start) * 100.0, tr(" pts"), 2),
		])
	PanelKit.ledger(group, rows)


func _build_dependency(ns) -> void:
	var group := PanelKit.section(_body, tr("Import dependency"))
	# NEVER SILENT, V1.7c's electoral-method line: every country in Europe imports
	# energy, so a line that disappeared at zero would only ever appear when
	# something was wrong -- the opposite of a readout.
	var moved: float = Energy.dependency_deviation_pct(ns, _loader)
	PanelKit.figure(group, "%s%%" % Num.f(ns.import_dependency_pct, 1), tr("of the energy the country uses, it buys abroad"))
	PanelKit.row(group, tr("Since the term began"), PanelKit.delta(moved, tr(" pts"), 2),
		PanelKit.tone_for(moved, true))
	PanelKit.line(group, tr("Above 100 is possible: a country that re-exports fuel buys more than it burns."))


func _build_emissions(ns) -> void:
	var group := PanelKit.section(_body, tr("Emissions"))
	# NEVER SILENT, the dependency figure's rule one section over: at an empty
	# fleet this prints the measured baseline and that is the truth the panel
	# exists for -- a line that appeared only once the mix had moved would be a
	# warning light wired to stay dark until it should shine. Divided to Mt here
	# rather than printed raw: a national total in tonnes is six zeroes the eye
	# cannot read, and %.1f Mt is one digit of headroom the fleet cannot exhaust
	# (the dirtiest plausible fleet moves France by single Mt, not hundreds).
	PanelKit.figure(group, tr("%s Mt") % Num.f((Energy.emissions_tonnes(ns, _loader) / 1.0e6), 1),
		tr("of CO2e the country emits in a year, every gas on one scale"))
	PanelKit.row(group, tr("Per head"), "%s t" % Num.f(ns.co2e_per_capita_t, 1))
	# The delta rides the PER-CAPITA form, not the national total, because the
	# per-capita figure is the one the accord's ceiling constrains -- a row about
	# a different quantity than the one the politics reads would be a second
	# answer to the same question (V1.6d's class, at panel scale).
	var moved: float = ns.co2e_per_capita_t - ns.start_co2e_per_capita_t
	PanelKit.row(group, tr("Since the term began"), PanelKit.delta(moved, " t", 2),
		PanelKit.tone_for(moved, true))


func _build_fleet(ns) -> void:
	var group := PanelKit.section(_body, tr("The fleet"))
	_fleet_group = group
	if ns.plants.is_empty():
		PanelKit.line(group, tr("Nothing ordered. The mix above is the measured one."))
		return
	var base: float = Energy.national_twh(ns)
	var built: Dictionary = Energy.built_twh(ns, _loader)
	var total: float = base
	for branch in built.keys():
		total += float(built[branch])
	var rows: Array = []
	for plant_id in ns.plants.keys():
		var source = _loader.energy_sources.get(String(ns.plants[plant_id].get("source_id", "")))
		if source == null:
			continue
		var months_left: int = int(ns.plants[plant_id].get("months_left", 0))
		var share: float = 0.0
		if total > 0.0:
			share = 100.0 * source.output_twh / total
		rows.append([
			plant_label(ns, String(plant_id), _loader),
			region_name(ns, String(ns.plants[plant_id].get("region_id", ""))),
			tr("running") if bool(ns.plants[plant_id].get("done", false)) else tr_n("%d month left", "%d months left", months_left) % months_left,
			"%s%%" % Num.f(share, 2),
		])
	PanelKit.ledger(group, rows)


## The fleet ledger's own name for a register entry: what was ordered, not the
## generated key the save uses -- the diary's project_name lesson, one register
## over.
static func plant_label(ns, plant_id: String, loader) -> String:
	var entry: Dictionary = ns.plants.get(plant_id, {})
	var source = loader.energy_sources.get(String(entry.get("source_id", "")))
	var name: String = source.source_name if source != null else String(plant_id)
	var seq: int = int(String(plant_id).get_slice("#", 1)) if String(plant_id).contains("#") else 0
	return "%s #%d" % [name, seq] if seq > 0 else name


## The map's route: a clicked glyph brings the fleet section into view.
func scroll_to_fleet() -> void:
	# ensure_control_visible() belongs to the SCROLL CONTAINER, not to the control
	# being revealed. Called as _fleet_group.ensure_control_on_screen() until the
	# V2.8 review -- a method that exists on nothing in Godot 4 -- so every click on
	# a plant glyph raised, and the window opened at the top with the fleet section,
	# the entire point of that route, never brought into view.
	if _scroll != null and is_instance_valid(_scroll):
		_fleet_wanted = true


func region_name(ns, region_id: String) -> String:
	for region in _loader.regions.get(ns.id, []):
		if region.id == region_id:
			return String(region.region_name)
	return region_id
