extends PanelContainer

## The save/load screen. A slot-name field and Save button, a list of existing
## slots each with a Load button, and a status line for the result.
##
## Doesn't touch SaveManager itself -- like every other panel it reads state
## and never writes it (docs/engine-decision.md Rule 2). Saving and loading
## are commands that go back to main.gd via signal, same shape
## Budget.commit()/BudgetPanel.committed uses; main.gd is the one place that
## owns both the GameState and the Clock, which loading has to replace/rewind
## together.
##
## Built in code, like every other panel here.

signal save_requested(slot: String)
signal load_requested(slot: String)
## Emitted alongside hide(), the same shape nation_panel.gd and
## government_panel.gd already use. The main menu hosts this panel in a
## full-rect holder it has to hide too, and cannot see a plain hide().
signal closed

const PanelKit = preload("res://src/ui/panel_kit.gd")
const SaveManager = preload("res://src/core/save_manager.gd")

var _name_field: LineEdit
var _status: Label
var _slot_list: VBoxContainer
var _save_row: HBoxContainer
var _dirty := true


func _ready() -> void:
	custom_minimum_size = Vector2(520, 420)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	PanelKit.line(root, "SAVE / LOAD", PanelKit.Tone.PLAIN)

	_save_row = HBoxContainer.new()
	_save_row.add_theme_constant_override("separation", 8)
	root.add_child(_save_row)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "save name"
	_name_field.text = "quicksave"
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_row.add_child(_name_field)

	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.pressed.connect(_on_save_pressed)
	_save_row.add_child(save_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status)

	PanelKit.line(root, "Saved games:", PanelKit.Tone.PLAIN)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_slot_list = VBoxContainer.new()
	_slot_list.add_theme_constant_override("separation", 6)
	_slot_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_slot_list)

	root.add_child(_build_footer())


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func():
		hide()
		closed.emit()
	)
	row.add_child(close)

	return row


## Load-only mode, for the main menu: there is no game in progress to save, so
## the save row would be a control that cannot work rather than one that is
## merely disabled.
func hide_save_row() -> void:
	_save_row.hide()


func _process(_delta: float) -> void:
	if not _dirty or not visible:
		return
	_dirty = false
	_refresh_slot_list()


func mark_dirty() -> void:
	_dirty = true


## Called by main.gd after a save/load attempt, so the panel reports the
## outcome without deciding for itself whether one succeeded.
func report(message: String) -> void:
	_status.text = message
	_dirty = true


func _refresh_slot_list() -> void:
	for child in _slot_list.get_children():
		child.queue_free()

	var slots := SaveManager.list_slots()
	if slots.is_empty():
		PanelKit.line(_slot_list, "No saved games yet.", PanelKit.Tone.PLAIN)
		return

	for slot in slots:
		_slot_list.add_child(_build_slot_row(slot))


func _build_slot_row(slot: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	name_label.text = slot
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	# B16: a slot list without dates cannot tell quicksave from quicksave -- the
	# newest-first order is the only ordering the player is shown and nothing
	# explains it. An unreadable stamp prints the missing-figure em dash rather
	# than a confident zero-time (V1.6d's rule).
	var stamp := Label.new()
	var mtime: int = SaveManager.slot_mtime(slot)
	if mtime <= 0:
		stamp.text = "--"
	else:
		var dt := Time.get_datetime_dict_from_unix_time(mtime)
		stamp.text = "%04d-%02d-%02d %02d:%02d" % [
			dt.year, dt.month, dt.day, dt.hour, dt.minute]
	row.add_child(stamp)

	var load_btn := Button.new()
	load_btn.text = "Load"
	load_btn.pressed.connect(func(): load_requested.emit(slot))
	row.add_child(load_btn)

	row.add_child(_build_delete_button(slot))

	return row


## Deleting is destructive and this game has no undo, no trash and no second
## copy -- so the first click only ARMS: the button re-labels "Delete?" and the
## second click, and only the second, removes the file. Any list rebuild builds
## a fresh button, which is the disarm -- a click anywhere else in the panel
## (a save, a load) puts the guard back up.
func _build_delete_button(slot: String) -> Button:
	var del_btn := Button.new()
	del_btn.text = "Delete"
	del_btn.set_meta("armed", false)
	del_btn.pressed.connect(func():
		if not bool(del_btn.get_meta("armed")):
			del_btn.set_meta("armed", true)
			del_btn.text = "Delete?"
			return
		if SaveManager.delete_slot(slot):
			_status.text = "deleted '%s'" % slot
		else:
			_status.text = "could not delete '%s'" % slot
		_dirty = true
	)
	return del_btn


func _on_save_pressed() -> void:
	var slot := _name_field.text.strip_edges()
	if slot.is_empty():
		_status.text = "enter a save name first"
		return
	save_requested.emit(slot)
