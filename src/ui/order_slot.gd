extends PanelContainer

## One place on the order paper -- V5.3 screen 4. The month's slot, or one of the queue's three:
## "2 · FEBRUARY", the day it divides, the bill's name. A queued place can be dragged onto
## another queued place (or onto a free one, which means "to the end"), and a right click asks
## for its verbs. It owns nothing: it says what happened (moved, menu_requested) and the paper
## runs the BillQueue command.

signal moved(from: int, to: int)
signal menu_requested(index: int)

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")

const HANDLE := "res://assets/icons/ui/drag.svg"
const HANDLE_PX := 16
const DRAG_KEY := "order_paper"

## The queue index this place stands for, or -1 for the month's slot.
var index := -1
## Where a bill dropped here goes: this place's own index, or the last queued one on a free
## place. -1 for the month's slot, which takes no drop (a bill reaches it by the close).
var drop_to := -1
var _title: Label
var _date: Label
var _name: Label


func _init() -> void:
	theme_type_variation = UiTheme.PLATE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	margin.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	column.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.MICRO
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	_date = Label.new()
	_date.theme_type_variation = UiTheme.CAPTION
	head.add_child(_date)
	_name = Label.new()
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	column.add_child(_name)


## `title` and `date` are the caption line, `name` the bill ("" for a free place), `tip` its
## hover. `handle` shows the drag grip (a queued bill).
func show_place(title: String, date: String, name_text: String, tip: String, handle: bool) -> void:
	_title.text = title
	_date.text = date
	_name.text = name_text if name_text != "" else "—"
	_name.theme_type_variation = "" if name_text != "" else UiTheme.CAPTION
	tooltip_text = tip
	if handle:
		var grip := TextureRect.new()
		grip.name = "Handle"  # i18n: ok a node name, found by tests
		grip.texture = Icon.load_icon(HANDLE, UiTheme.TEXT_DIM, HANDLE_PX)
		grip.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		grip.mouse_filter = Control.MOUSE_FILTER_PASS
		(_date.get_parent() as HBoxContainer).add_child(grip)


func place_name() -> String:
	return _name.text


func _gui_input(event: InputEvent) -> void:
	var press := event as InputEventMouseButton
	if press != null and press.pressed and press.button_index == MOUSE_BUTTON_RIGHT and index >= 0:
		menu_requested.emit(index)
		accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if index < 0:
		return null
	var ghost := Label.new()
	ghost.text = _name.text
	set_drag_preview(ghost)
	return {DRAG_KEY: index}


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return drop_to >= 0 and data is Dictionary and (data as Dictionary).has(DRAG_KEY)


func _drop_data(_at: Vector2, data: Variant) -> void:
	moved.emit(int((data as Dictionary)[DRAG_KEY]), drop_to)
