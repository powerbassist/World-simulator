extends Control

## One day of the Diary's month grid -- V5.2 b+ R8. Drawn, not built from a
## Button: a tint, a today ring and marks by kind would each need a stylebox
## override, which tests/test_ui_theme.gd forbids in a panel (chart_bars.gd is
## the precedent). A click picks the day; its entries are read in the grid's day
## list, and in this cell's tooltip.
##
## A mark's KIND is a shape as well as a colour (V5.1-d2: no colour-only layer):
## a booking a filled dot in the accent (the player's own), a visit's journey day
## a dash in the accent, a fixed date a hollow
## square, a commitment falling due a diamond and a request's last day to answer
## a triangle, both in the attention tone (something waits on the player).

signal picked(day: int)
## V5.3-0 (b2): a request's card from the Diary's request column dropped here, on a
## day it offers.
signal dropped(request_id: String, date: Dictionary)

const UiTheme = preload("res://src/ui/ui_theme.gd")

const SIZE := Vector2(58, 46)
const MARK := 3.5

var day := 0
var today := false
var tinted := false  # a waiting request offers this day
var selected := false
var marks: Array[String] = []  # "booking" / "away" / "fixed" / "due" / "deadline", one per entry
## request id -> the offered date {year, month, day, free, reason}: the drops this
## day takes. Filled by the grid off what it already reads; the cell knows no sim.
var offers := {}
var _down := false  # a press began on this cell: only its own release picks it


func _init() -> void:
	custom_minimum_size = SIZE * UiTheme.text_scale()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Only the left button's own events touch the press: a motion between press and
	# release (a hand's jitter) must not drop the click (QA's TAKE 1 on #153).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var click: bool = _down and not event.pressed
		_down = event.pressed
		if click:
			picked.emit(day)
			accept_event()
	elif event.is_action_pressed("ui_accept"):
		picked.emit(day)
		accept_event()


## A free day of the dragged request's takes the drop; a day it offers but the
## Diary refuses says why on the cell's hover, as the day list's button does.
func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	if not (data is Dictionary) or not (data as Dictionary).has("request"):
		return false
	var date: Dictionary = offers.get(String(data["request"]), {})
	return not date.is_empty() and bool(date.get("free", true))


func _drop_data(_at: Vector2, data: Variant) -> void:
	var id := String(data["request"])
	dropped.emit(id, offers[id])


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-1.0)
	var accent := UiTheme.accent()
	draw_rect(r, UiTheme.SLATE if selected else UiTheme.HULL)
	if tinted:
		draw_rect(r, Color(accent, 0.22))
	draw_rect(r, accent if today or has_focus() else UiTheme.EDGE, false, 2.0 if today or has_focus() else 1.0)
	var font := get_theme_default_font()
	var fs := roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())
	draw_string(font, Vector2(6.0, 4.0 + font.get_ascent(fs)), str(day), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UiTheme.TEXT if not tinted else accent.lightened(0.3))
	var x := 8.0
	var y := size.y - 9.0
	for kind in marks:
		_mark(kind, Vector2(x, y), accent)
		x += MARK * 3.0
		if x > size.x - 6.0:
			break


func _mark(kind: String, at: Vector2, accent: Color) -> void:
	match kind:
		"booking":
			draw_circle(at, MARK, accent)
		"away":
			draw_line(at - Vector2(MARK, 0), at + Vector2(MARK, 0), accent, 2.0)
		"fixed":
			draw_rect(Rect2(at - Vector2(MARK, MARK), Vector2(MARK, MARK) * 2.0), UiTheme.TEXT_DIM, false, 1.2)
		"due":
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -MARK), at + Vector2(MARK, 0), at + Vector2(0, MARK), at + Vector2(-MARK, 0)]), UiTheme.WARN)
		_:
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -MARK), at + Vector2(MARK, MARK), at + Vector2(-MARK, MARK)]), UiTheme.WARN)
