extends PanelContainer

## The bar across the top of the screen -- V5.1-c2.3, the BUREAU board's: back
## and forward over the player's own path, where they are, why the clock is held
## when it is, the date and the speeds, save and the menu.
##
## The figures are not here. They are the strip under it (top_bar.gd, which
## keeps its name and its readings), so this bar never has to fold.
##
## Proposes, never commands: every button goes back to main.gd as a signal, and
## main.gd decides -- back under a scene is refused there, not here, because this
## bar does not know what a scene is.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Domains = preload("res://src/ui/domains.gd")

signal back_requested
signal forward_requested
signal save_load_requested
signal settings_requested

const HEIGHT := 58

var _back: Button
var _forward: Button
var _crumb: Label
var _held: Label
var _clock_slot: HBoxContainer
var _windows
var _nation := ""
var _where := ""


func _ready() -> void:
	custom_minimum_size = Vector2(0, HEIGHT)
	theme_type_variation = UiTheme.TOP_BAR_PANEL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)

	var history := HBoxContainer.new()
	history.add_theme_constant_override("separation", 4)
	row.add_child(history)
	_back = _button(history, "<", tr("Back"))
	_back.pressed.connect(func(): back_requested.emit())
	_forward = _button(history, ">", tr("Forward"))
	_forward.pressed.connect(func(): forward_requested.emit())
	set_history(false, false)

	_crumb = Label.new()
	_crumb.theme_type_variation = UiTheme.CAPTION
	_crumb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crumb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_crumb.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	row.add_child(_crumb)

	_held = Label.new()
	_held.theme_type_variation = UiTheme.BAD_TEXT
	_held.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_held.hide()
	row.add_child(_held)

	_clock_slot = HBoxContainer.new()
	row.add_child(_clock_slot)

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	row.add_child(tools)
	var save := _button(tools, tr("SAVE"), tr("Save and load (S)"))
	save.pressed.connect(func(): save_load_requested.emit())
	var menu := _button(tools, tr("MENU"), tr("Pause menu (Esc)"))
	menu.pressed.connect(func(): settings_requested.emit())


## hud.gd builds the clock cluster and hands it here, so main.gd keeps reaching it
## as `_hud.clock_cluster`.
func add_clock(cluster: Control) -> void:
	_clock_slot.add_child(cluster)


## The bar follows the window manager itself: every open and every close moves
## the breadcrumb and the history buttons. Reading, never commanding.
func follow(windows, nation_name: String) -> void:
	_windows = windows
	_nation = nation_name
	windows.opened.connect(show_where)
	windows.closed.connect(func(_id: String):
		if windows.open_ids().is_empty():
			show_where("")
	)
	show_where("")


## A loaded game may be another nation.
func set_nation(nation_name: String) -> void:
	_nation = nation_name
	show_where(_where)


## The nation, then the domain and the tab -- or the map.
func show_where(id: String) -> void:
	_where = id
	var parts: Array = [_nation]
	if id.is_empty():
		parts.append(tr("Map"))
	else:
		var domain := Domains.domain_of(id)
		if not domain.is_empty():
			parts.append(tr(Domains.title(domain)))
		parts.append(_windows.title(id))
	set_crumb(parts)
	set_history(_windows.can_back(), _windows.can_forward())


func set_history(can_back: bool, can_forward: bool) -> void:
	_back.disabled = not can_back
	_forward.disabled = not can_forward


## Parts already in the player's language, joined left to right.
func set_crumb(parts: Array) -> void:
	_crumb.text = " › ".join(PackedStringArray(parts))


func crumb() -> String:
	return _crumb.text


## Why the clock is not running, or "" when nothing holds it.
func set_held(text: String) -> void:
	_held.text = text
	_held.visible = not text.is_empty()


## No focus, as on every piece of chrome: a clicked button that kept the focus
## would take Space, the pause key, for itself (V5.1-0c's forfeited Agenda).
func _button(parent: Control, text: String, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.theme_type_variation = UiTheme.SUBROW_BUTTON
	button.focus_mode = Control.FOCUS_NONE
	parent.add_child(button)
	return button
