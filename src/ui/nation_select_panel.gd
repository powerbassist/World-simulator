extends PanelContainer

## New Game's nation choice -- V1.2a. Lists every nation the loaded data marks
## `playable`, whatever that count is; the panel does not know or care how many
## there are, the same way save_load_panel.gd does not care how many slots
## exist. See docs/data-architecture.md.
##
## Built in code, like every other panel here. Modelled on save_load_panel.gd's
## shape: a scrolling list of rows, each with a button that emits a choice back
## to the caller rather than acting on it directly.

signal nation_selected(nation_id: String)
## Emitted alongside hide(), the same shape save_load_panel.gd already uses --
## the main menu hosts this in a full-rect holder it has to hide too, and
## cannot see a plain hide().
signal closed

var _list: VBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(480, 420)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	var title := Label.new()
	title.text = "CHOOSE A NATION"
	root.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	root.add_child(_build_footer())


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(func():
		hide()
		closed.emit()
	)
	row.add_child(close)

	return row


## `nations` is an Array of the Nation objects DataLoader.nations holds for
## every nation with `playable = true`, already filtered and sorted by the
## caller -- this panel only lays them out.
func set_nations(nations: Array) -> void:
	for child in _list.get_children():
		child.queue_free()

	if nations.is_empty():
		var none := Label.new()
		none.text = "No playable nation found in data/nations/."
		_list.add_child(none)
		return

	for n in nations:
		_list.add_child(_build_row(n))


func _build_row(n) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "%s -- %s (%s)" % [n.nation_name, n.leader_title, n.leader_name]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var play_btn := Button.new()
	play_btn.text = "Play"
	play_btn.pressed.connect(func(): nation_selected.emit(n.id))
	row.add_child(play_btn)

	return row
