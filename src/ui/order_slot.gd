extends PanelContainer

## One place on the order paper -- V5.3 screen 4. The month's slot, or one of the queue's three:
## "2 · FEB" and the bill's name. G3 S5 (Design's T3): a tile with no outline; only the bill before
## the Assembly carries a date, the amber deadline tag (hourglass, "31 Jan"); a queued bill is its
## kicker and name; the first free place, the one "Propose" names, is a dashed accent place that
## says "Free", and a later free place is an empty tile. A queued place can be dragged onto
## another queued place (or onto a free one, which means "to the end"), and a right click asks
## for its verbs. It owns nothing: it says what happened (moved, menu_requested) and the paper
## runs the BillQueue command.

signal moved(from: int, to: int)
signal menu_requested(index: int)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")

const HANDLE := "res://assets/icons/ui/drag.svg"
const HANDLE_PX := 16
const HOURGLASS := "res://assets/icons/ui/hourglass.svg"
const DRAG_KEY := "order_paper"

## The queue index this place stands for, or -1 for the month's slot.
var index := -1
## Where a bill dropped here goes: this place's own index, or the last queued one on a free
## place. -1 for the month's slot, which takes no drop (a bill reaches it by the close).
var drop_to := -1
var _title: Label
var _date: Label
var _tag: HBoxContainer
var _name: Label
var _free: Label
var _first_free := false


func _init() -> void:
	theme_type_variation = UiTheme.TILE_PANEL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)
	# G3 S5 (Bills = C): one line -- "2 · FEBRUARY", the bill's name, the day it divides.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	margin.add_child(head)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.MICRO
	head.add_child(_title)
	_name = Label.new()
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_name)
	_free = Label.new()
	_free.visible = false
	_free.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_free)
	# The deadline tag: an hourglass and the day, amber because this one waits on the Assembly.
	_tag = HBoxContainer.new()
	_tag.add_theme_constant_override("separation", 4)
	_tag.visible = false
	head.add_child(_tag)
	var glass := TextureRect.new()
	glass.texture = Icon.load_icon(HOURGLASS, UiTheme.WARN, roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale()))
	glass.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tag.add_child(glass)
	_date = Label.new()
	_date.theme_type_variation = UiTheme.WARN_TEXT
	_tag.add_child(_date)


## `title` is the kicker, `date` the deadline tag ("" for every place but the bill before the
## Assembly), `name_text` the bill ("" for a free place), `tip` its hover. `handle` shows the drag
## grip (a queued bill); `first_free` marks the place the next Propose takes.
func show_place(title: String, date: String, name_text: String, tip: String, handle: bool, first_free := false) -> void:
	_title.text = title
	_date.text = date
	_tag.visible = date != ""
	_name.text = name_text
	_name.visible = name_text != ""
	_first_free = first_free and name_text == ""
	_free.visible = _first_free
	if _first_free:
		_free.text = tr("Free")
		# The kicker and the word are the accent's: "you are here", the place the press books.
		_free.add_theme_color_override("font_color", UiTheme.accent())
	tooltip_text = tip
	queue_redraw()
	if handle:
		var grip := TextureRect.new()
		grip.name = "Handle"  # i18n: ok a node name, found by tests
		grip.texture = Icon.load_icon(HANDLE, UiTheme.TEXT_DIM, HANDLE_PX)
		grip.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
		grip.mouse_filter = Control.MOUSE_FILTER_PASS
		(_date.get_parent() as HBoxContainer).add_child(grip)


func place_name() -> String:
	return _name.text


## True for the dashed place a Propose would take.
func is_first_free() -> bool:
	return _first_free


## The dashed accent edge of the bookable place; every other place is a plain tile.
func _draw() -> void:
	if not _first_free:
		return
	var r := Rect2(Vector2.ZERO, size).grow(-0.5)
	var c := UiTheme.accent()
	for edge in [[r.position, Vector2(r.end.x, r.position.y)], [Vector2(r.end.x, r.position.y), r.end],
			[r.end, Vector2(r.position.x, r.end.y)], [Vector2(r.position.x, r.end.y), r.position]]:
		draw_dashed_line(edge[0], edge[1], c, 1.0, 4.0)


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
