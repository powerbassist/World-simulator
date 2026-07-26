extends PanelContainer

## The in-game pause menu, on Escape. Until U1 there was no way out of a
## running game at all -- no route back to the main menu, and no quit that was
## not the window's close button.
##
## Emits intent and owns nothing, the same shape as every other panel here:
## main.gd holds the Clock and the GameState, so main.gd is what pauses, saves,
## and swaps the scene. Quit is the one exception, because there is no state to
## coordinate on the way out.
##
## Built in code, like every other panel here -- see budget_panel.gd's
## placement note.

signal resumed
signal save_load_requested
signal settings_requested
signal main_menu_requested


func _ready() -> void:
	custom_minimum_size = Vector2(300, 260)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_add_entry(column, "Resume", func(): resumed.emit())
	_add_entry(column, "Save / Load", func(): save_load_requested.emit())
	_add_entry(column, "Settings", func(): settings_requested.emit())
	_add_entry(column, "Main Menu", func(): main_menu_requested.emit())
	_add_entry(column, "Quit", func(): get_tree().quit())


func _add_entry(column: VBoxContainer, text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(240, 32)
	button.pressed.connect(action)
	column.add_child(button)
