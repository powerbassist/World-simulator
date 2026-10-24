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
const DateText = preload("res://src/ui/date_text.gd")

var _name_field: LineEdit
var _status: Label
var _slot_list: VBoxContainer
var _save_row: HBoxContainer
var _dirty := true
var _save_btn: Button
var _blocked := ""


func _ready() -> void:
	custom_minimum_size = Vector2(520, 420)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	PanelKit.line(root, tr("SAVE / LOAD"), PanelKit.Tone.PLAIN)

	_save_row = HBoxContainer.new()
	_save_row.add_theme_constant_override("separation", 8)
	root.add_child(_save_row)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = tr("save name")
	_name_field.text = tr("quicksave")
	_name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_row.add_child(_name_field)

	_save_btn = Button.new()
	_save_btn.text = tr("Save")
	_save_btn.pressed.connect(_on_save_pressed)
	_save_row.add_child(_save_btn)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	root.add_child(_status)
	block_save(_blocked)

	PanelKit.line(root, tr("Saved games:"), PanelKit.Tone.PLAIN)

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

	var close_btn := Button.new()
	close_btn.text = tr("Close")
	close_btn.pressed.connect(close)
	row.add_child(close_btn)

	return row


## The one close path. Escape and the S toggle in main.gd come through here
## too, so every way of putting this panel away emits `closed` -- the signal
## the pause-menu restore hangs off. A close that bypasses it (a bare
## visible=false) leaves a pause menu hidden behind nothing.
func close() -> void:
	hide()
	closed.emit()


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
		PanelKit.line(_slot_list, tr("No saved games yet."), PanelKit.Tone.PLAIN)
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
		# Local time (QA #48: UTC read two hours early in Paris). Today's bias, so
		# a save from the other side of a summer-time change reads an hour off --
		# the OS gives the current offset, not the one the file was written under.
		stamp.text = DateText.local_stamp(mtime, int(Time.get_time_zone_from_system()["bias"]))
	row.add_child(stamp)

	var load_btn := Button.new()
	load_btn.text = tr("Load")
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
	del_btn.text = tr("Delete")
	del_btn.set_meta("armed", false)
	del_btn.pressed.connect(func():
		if not bool(del_btn.get_meta("armed")):
			del_btn.set_meta("armed", true)
			del_btn.text = tr("Delete?")
			return
		if SaveManager.delete_slot(slot):
			_status.text = tr("deleted '%s'") % slot
		else:
			_status.text = tr("could not delete '%s'") % slot
		_dirty = true
	)
	return del_btn


## V5.2b: why saving is refused right now, "" when it is not. An open audience's
## session is never saved (spec C11), so a save made mid-audience would load as a
## no-show priced as a decline -- and a save and a load must never cost the player
## (the parent's call, 2026-10-24). The audience's wiring sets and clears it.
func block_save(reason: String) -> void:
	# Said on the panel, not only on the hover: a dimmed Save alone does not say why.
	if _status != null and (reason != "" or _status.text == _blocked):
		_status.text = reason
	_blocked = reason
	if _save_btn != null:
		_save_btn.disabled = reason != ""
		_save_btn.tooltip_text = reason


func save_blocked() -> String:
	return _blocked


func _on_save_pressed() -> void:
	if _blocked != "":
		_status.text = _blocked
		return
	var slot := _name_field.text.strip_edges()
	if slot.is_empty():
		_status.text = tr("enter a save name first")
		return
	# Refused here rather than only inside SaveManager so the player learns at
	# the field; the manager refuses again as the boundary (delete trusts it).
	if not SaveManager.valid_slot_name(slot):
		_status.text = tr("a save name is one line of text -- no slashes or dots")
		return
	save_requested.emit(slot)
