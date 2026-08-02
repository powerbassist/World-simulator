extends VBoxContainer

## The bottom-centre command bar -- U5a, replacing dashboard.gd's tab rail.
##
## Four clusters, each opening a sub-row of the panels under it. The clusters
## are themed rather than one-per-panel on purpose: this game gains surfaces
## every session (V1.3c tariffs, V1.3d the bloc, V1.3f defence, U6's calendar),
## and a flat row of one button per panel has to be redesigned the first time a
## seventh arrives. A cluster absorbs a new entry with a one-line edit in
## main.gd.
##
## Emits an id and nothing else. What that id opens is window_manager.gd's
## business -- this file never sees a panel, which is why the sub-row can list a
## surface that does not exist yet without this file knowing.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")

signal panel_requested(id: String)

const ICON_PX := 22

var _subrow: HBoxContainer
var _cluster_row: HBoxContainer
var _cluster_buttons := {}   # cluster id -> Button
var _entries := {}           # cluster id -> Array[Dictionary]
var _open_cluster := ""


func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_END
	add_theme_constant_override("separation", 6)

	# The sub-row sits above the clusters and is its own plate, so an open
	# cluster reads as a drawer pulled out of the bar rather than as the bar
	# having grown taller.
	var subrow_holder := PanelContainer.new()
	subrow_holder.theme_type_variation = UiTheme.PLATE
	subrow_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(subrow_holder)

	_subrow = HBoxContainer.new()
	_subrow.add_theme_constant_override("separation", 2)
	subrow_holder.add_child(_subrow)
	subrow_holder.hide()

	var cluster_holder := PanelContainer.new()
	cluster_holder.theme_type_variation = UiTheme.PLATE
	cluster_holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	add_child(cluster_holder)

	_cluster_row = HBoxContainer.new()
	_cluster_row.add_theme_constant_override("separation", 2)
	cluster_holder.add_child(_cluster_row)


## `entries` is an Array of {id, label}. The order of add_cluster() calls is the
## order along the bar, and main.gd's call order is the order a president spends
## a day in rather than alphabetical.
func add_cluster(cluster_id: String, label: String, icon_path: String, entries: Array) -> void:
	var button := Button.new()
	button.theme_type_variation = UiTheme.CLUSTER_BUTTON
	button.toggle_mode = true
	button.text = label.to_upper()
	button.icon = Icon.load_icon(icon_path, UiTheme.TEXT, ICON_PX)
	button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.expand_icon = false
	# Icon above the label rather than beside it: four clusters side by side
	# with horizontal icons is twice as wide as the reference's bar.
	button.add_theme_constant_override("h_separation", -ICON_PX)
	button.custom_minimum_size.x = 92
	button.pressed.connect(func(): _toggle_cluster(cluster_id))

	_cluster_row.add_child(button)
	_cluster_buttons[cluster_id] = button
	_entries[cluster_id] = entries


## Public so Escape and a click on the map can both shut the drawer, and so a
## headless test can assert it closed without synthesising a click.
func close_subrow() -> void:
	_open_cluster = ""
	for id in _cluster_buttons.keys():
		_cluster_buttons[id].button_pressed = false
	_subrow.get_parent().hide()


func open_cluster() -> String:
	return _open_cluster


func _toggle_cluster(cluster_id: String) -> void:
	if _open_cluster == cluster_id:
		close_subrow()
		return

	_open_cluster = cluster_id
	for id in _cluster_buttons.keys():
		_cluster_buttons[id].button_pressed = (id == cluster_id)

	for child in _subrow.get_children():
		child.queue_free()
		_subrow.remove_child(child)

	for entry in _entries[cluster_id]:
		var button := Button.new()
		button.theme_type_variation = UiTheme.SUBROW_BUTTON
		button.text = str(entry["label"]).to_upper()
		var id := str(entry["id"])
		button.pressed.connect(func(): panel_requested.emit(id))
		_subrow.add_child(button)

	_subrow.get_parent().show()
