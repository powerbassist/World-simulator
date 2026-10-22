extends PanelContainer

## The country box -- V5.1-d4, G2 of the play gate (the author: "diplomacy panel when
## clicking a country is useless, should be a small box resuming basic stats, if
## foreign country, basic stats plus actual relationship; a right click should open
## fast actions to take"). A left click on a nation shows a small plate by the
## pointer with its figures (and, abroad, the relationship and the fog's approval
## range); a right click shows the verbs the Diplomacy file would offer, each one a
## press. The file itself is one button away.
##
## Owns nothing of the game: the figures are read from GameState, the verbs are
## nation_panel.gd's own (offered_actions(), act()), so the box and the file cannot
## disagree, and a press goes down the row's command path. A child of the screen
## stack (under the tooltip chain) but holding no rank: Escape puts it away, and a
## scene above refuses it, as it refuses the file. attach() wires it from main.gd in
## one line.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const Diplomacy = preload("res://src/sim/diplomacy.gd")
const ForeignReading = preload("res://src/ui/foreign_reading.gd")

## How far from the pointer the box opens, so the click's own country stays in view.
const OFFSET := Vector2(14, 14)

var _main
var _body: VBoxContainer
## The nation shown, and whether as the box ("box") or the menu ("verbs").
var nation_id := ""
var mode := ""


func attach(main) -> void:
	_main = main
	theme_type_variation = UiTheme.PLATE
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 12)
	add_child(margin)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	margin.add_child(_body)

	var stack = main._stack
	stack.add_child(self)
	stack.move_child(self, stack.tips.get_index())  # the tooltip chain stays the last child
	main._map_view.nation_clicked.connect(show_box)
	main._map_view.gui_input.connect(_on_map_input)


## Escape puts the box away. Not through the stack: a rank there would make the box
## a "tab" -- the top moving to WORKSPACE slides the inbox over it while a decision
## holds -- and it is a note by the pointer, not a surface (the tooltip chain, the
## stack's last child, takes its own Escape the same way).
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if visible and key != null and key.pressed and not key.echo and key.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()


## The left click: the nation's figures, by the pointer.
func show_box(id: String) -> void:
	if not _ready_for(id):
		return
	var state = _main._state
	var n = _main._loader.nations.get(id)
	var ns = state.nations.get(id)
	_clear("box", id)
	PanelKit.heading(_body, "%s — %s" % [n.nation_name, n.capital])
	var player: String = state.player_nation_id
	if id != player:
		var home = _main._loader.nations.get(player)
		PanelKit.line(_body, tr("Relations with %s: %d / 100") % [
			home.nation_name if home != null else player, roundi(Diplomacy.score(state, player, id))], PanelKit.Tone.PLAIN)
	PanelKit.rich(_body, tr("Leader: %s (%s)") % [PanelKit.person(n.leader_person_id, _main._loader.person_name(n.leader_person_id)), n.leader_title], PanelKit.Tone.PLAIN)
	PanelKit.line(_body, tr("GDP: EUR %.0fbn   growth %s%%") % [ns.gdp_eur_bn, Num.fs(ns.growth_annual_pct, 2)], PanelKit.Tone.PLAIN)
	PanelKit.line(_body, tr("Unemployment: %s%%") % Num.f(ns.unemployment_pct, 1), PanelKit.Tone.PLAIN)
	PanelKit.line(_body, tr("Debt: %s%% of GDP") % Num.f(ns.debt_to_gdp_pct(), 1), PanelKit.Tone.PLAIN)
	PanelKit.line(_body, ForeignReading.approval_text(state, id), PanelKit.Tone.PLAIN)
	if id != player:
		PanelKit.line(_body, tr("Right-click the country for what you can do."))
	_file_button()
	_show_by_pointer()


## The right click: the verbs the file offers for this nation, each one a press.
func show_verbs(id: String) -> void:
	if not _ready_for(id):
		return
	var n = _main._loader.nations.get(id)
	_clear("verbs", id)
	PanelKit.heading(_body, n.nation_name)
	var offered: Array = []
	if id != String(_main._state.player_nation_id):
		_main._nation_panel.show_nation(id)
		offered = _main._nation_panel.offered_actions()
	for action in offered:
		var press := Button.new()
		press.text = Strings.row_name("diplomatic-actions", action)
		press.tooltip_text = Strings.row_summary("diplomatic-actions", action)
		press.alignment = HORIZONTAL_ALIGNMENT_LEFT
		press.pressed.connect(_act.bind(action))
		_body.add_child(press)
	if offered.is_empty():
		PanelKit.line(_body, tr("Nothing you can do with %s today.") % n.nation_name)
	_file_button()
	_show_by_pointer()


func _act(action) -> void:
	hide()
	_main._nation_panel.show_nation(nation_id)
	_main._nation_panel.act(action)


func _file_button() -> void:
	var file := Button.new()
	file.text = tr("Open the file")
	file.pressed.connect(func():
		hide()
		_main._on_nation_clicked(nation_id))
	_body.add_child(file)


## A press elsewhere on the map puts the box away; a right press on a nation opens
## its verbs. The left press on a nation is the map's own nation_clicked.
func _on_map_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press == null or not press.pressed:
		return
	var id: String = _main._map_view.nation_at_screen_point(press.position)
	if press.button_index == MOUSE_BUTTON_RIGHT:
		if id != "":
			show_verbs(id)
		else:
			hide()
	elif press.button_index == MOUSE_BUTTON_LEFT and id == "":
		hide()


## Under a scene or a system screen the map's clicks reach nothing (the file's own
## rule, main._on_nation_clicked), and an armed placement owns the click.
func _ready_for(id: String) -> bool:
	if _main._state == null or not _main._state.nations.has(id) or not _main._loader.nations.has(id):
		return false
	if not _main._stack.accepts_hotkeys() or _main._map_view.is_placing():
		return false
	return true


func _clear(as_mode: String, id: String) -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	mode = as_mode
	nation_id = id


func _show_by_pointer() -> void:
	position = get_viewport().get_mouse_position() + OFFSET
	show()
	reset_size()
	_keep_on_screen.call_deferred()


func _keep_on_screen() -> void:
	reset_size()
	var screen: Vector2 = get_viewport_rect().size
	position = Vector2(clampf(position.x, 0.0, maxf(screen.x - size.x, 0.0)),
		clampf(position.y, 0.0, maxf(screen.y - size.y, 0.0)))
