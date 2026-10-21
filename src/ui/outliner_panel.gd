extends PanelContainer

const PanelKit = preload("res://src/ui/panel_kit.gd")
const OutlinerReadings = preload("res://src/ui/outliner_readings.gd")

## V4.8b. The outliner window: whatever outliner_readings.gd says is pinned, one
## section per register entry, each row a line that opens the window which answers
## it. This file knows no section by name -- it draws SECTIONS in order, hides the
## empty ones, and says so when all are empty. A window rather than a HUD plate
## because a plate means moving the frames the 826 px band is measured against;
## the player can pin the window open like any other.
##
## Read-only over state, the shape of people_panel.gd: setup(), mark_dirty() on the
## month tick (main.gd's mark_all_dirty), _refresh() only while visible.

signal closed
## A row was clicked: main.gd opens that window through the window manager.
signal window_requested(window_id: String)

const NOTHING_PINNED := "Nothing pinned."  # i18n: msgid

var _state
var _loader
var _dirty := true

var _body: VBoxContainer
var _close_button: Button


func _ready() -> void:
	# Narrow and short: a margin note, not a report. Inside U5a's ~886 px band.
	custom_minimum_size = Vector2(400, 360)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", PanelKit.SECTION_SEPARATION)
	scroll.add_child(_body)

	_close_button = Button.new()
	_close_button.text = tr("Close")
	_close_button.pressed.connect(func(): closed.emit())
	root.add_child(_close_button)


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	_dirty = true


## Docked-tab mode -- see budget_panel.gd's hide_close_button() for why.
func hide_close_button() -> void:
	_close_button.hide()


func _process(_delta: float) -> void:
	if not _dirty or not is_visible_in_tree() or _state == null:
		return
	_dirty = false
	_refresh()


func mark_dirty() -> void:
	_dirty = true


func _refresh() -> void:
	if _state.player() == null:
		return
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	var shown := 0
	for section in OutlinerReadings.SECTIONS:
		var r: Dictionary = OutlinerReadings.read(section, _state, _loader)
		if not bool(r["visible"]):
			continue
		shown += 1
		var box := PanelKit.section(_body, String(r["title"]))
		for row in (r["rows"] as Array):
			_draw_row(box, row)
	if shown == 0:
		PanelKit.line(_body, tr(NOTHING_PINNED))


## A row is a Label that takes the pointer: the tone is the label's own (what
## PanelKit.line sets), and a Button would have replaced it with the button look.
func _draw_row(parent: Control, row: Dictionary) -> void:
	var label := PanelKit.line(parent, String(row["text"]), int(row["tone"]))
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	label.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var window := String(row["window"])
	label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			window_requested.emit(window))
