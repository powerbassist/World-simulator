extends HBoxContainer

## Left tab rail plus content dock -- U2. Rail is folded into this file rather
## than split out: it is seven buttons and one selection variable, not a system
## in its own right (docs/engine-decision.md Rule 3 -- a narrow job stays one
## file). The dock holds every tab's root control as a child and shows exactly
## one at a time; main.gd owns what each tab actually contains.

const UiTheme = preload("res://src/ui/ui_theme.gd")

signal tab_selected(id: String)

const RAIL_WIDTH := 150

var _rail: VBoxContainer
var _dock: MarginContainer
var _buttons := {}   # id -> Button
var _panels := {}    # id -> Control
var _current := ""


func _ready() -> void:
	_rail = VBoxContainer.new()
	_rail.custom_minimum_size.x = RAIL_WIDTH
	_rail.add_theme_constant_override("separation", 2)
	add_child(_rail)

	_dock = MarginContainer.new()
	_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		_dock.add_theme_constant_override("margin_%s" % side, 12)
	add_child(_dock)


## Registers a tab and docks its root control. Order of calls is rail order.
## The panel's own geometry gets overridden here -- the dock owns layout, not
## whatever custom_minimum_size the panel set for its old centred-overlay life.
func add_tab(id: String, title: String, panel: Control) -> void:
	var button := Button.new()
	button.text = title
	button.toggle_mode = true
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	# Flat until selected, where an accent bar marks the open tab -- a rail of
	# seven raised buttons reads as seven widgets rather than as one list.
	button.theme_type_variation = UiTheme.RAIL_BUTTON
	button.pressed.connect(func(): select_tab(id))
	_rail.add_child(button)
	_buttons[id] = button

	# Godot focuses nothing by default, and grab_focus() only works once the
	# node is in the tree -- true here because dashboard.gd is only ever
	# constructed after it, or its holder, is already added to the scene. Same
	# reasoning as menu.gd's first.grab_focus().
	if _buttons.size() == 1:
		button.grab_focus()

	panel.hide()
	# add_child() first: the panel's own _ready() runs synchronously here and
	# sets its old centred-overlay custom_minimum_size (e.g. 820x520). Overriding
	# before add_child() would just get clobbered the moment _ready() runs.
	_dock.add_child(panel)
	panel.custom_minimum_size = Vector2.ZERO
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_panels[id] = panel

	if _current == "":
		select_tab(id)


func select_tab(id: String) -> void:
	if not _panels.has(id) or _current == id:
		return
	if _current != "":
		_panels[_current].hide()
		_buttons[_current].button_pressed = false
	_current = id
	_panels[id].show()
	_buttons[id].button_pressed = true
	if _panels[id].has_method("mark_dirty"):
		_panels[id].mark_dirty()
	tab_selected.emit(id)


func current_tab() -> String:
	return _current
