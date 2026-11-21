extends Control

## One day of the Diary's month grid -- V5.2 b+ R8, the month page since picture A (the
## author's pick, 2026-11-20). The cell itself is drawn, not a Button: a tint, a today ring
## and a travel band would each need a stylebox override, which tests/test_ui_theme.gd
## forbids in a panel (chart_bars.gd is the precedent). A click picks the day (diary_grid.gd).
##
## What the day holds is WRITTEN in it, a line an entry (picture A: "Address to the nation",
## "Audience Bruno Lachapelle"), each line led by its kind's mark -- a shape as well as a
## colour (V5.1-d2: no colour-only layer): a booking a filled dot in the accent (the player's
## own), a fixed date a hollow square, a commitment falling due a diamond and a request's last
## day to answer a triangle, both in the attention tone. An audience's line is led by the
## person's face instead. A visit's trip (its journey and its meeting) is one plain band across the
## cells, its host named once a row, so the trip reads as one bar. Past MAX_LINES the last line says "+N".
##
## A free day of the armed person's window is tinted, and the grid books it on the click
## (diary_grid.gd _on_day).

signal picked(day: int)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Portrait = preload("res://src/ui/portrait.gd")

## px at text size 100 %: a day wide enough for a short name, tall enough for three lines.
const SIZE := Vector2(100, 74)
const MARK := 3.5
const MAX_LINES := 3
## px at text size 100 %: a line's lead (its mark or the face) and the face itself.
const LEAD := 12.0
const FACE := Vector2(12, 16)

var day := 0
var today := false
var tinted := false  # a free day of the armed person's window: a click books it
var selected := false
## A visit's trip covers this day (its journey or its meeting): the band, plain, edge to edge,
## so one trip reads as one bar along the week; `band_label` is "" past the row's first day.
var band := false
var band_label := ""
## The day's entries, the grid's {text, mark, person}: one line each, up to MAX_LINES.
var entries: Array = []
var _down := false  # a press began on this cell: only its own release picks it
var _lines: VBoxContainer


func _init() -> void:
	custom_minimum_size = SIZE * UiTheme.text_scale()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL


## The lines, after add_child() (a child's anchors read this cell) and once `entries` is set.
func fill() -> void:
	var s := UiTheme.text_scale()
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 1)
	add_child(_lines)
	_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines.offset_left = 4.0
	_lines.offset_right = -3.0
	_lines.offset_top = 20.0 * s
	# The band's own line holds the trip, so its journey's and its meeting's entries go to the hover.
	var shown := entries.filter(func(e: Dictionary) -> bool: return String(e["mark"]) != "away" and not (band and String(e["mark"]) == "booking" and String(e.get("person", "")) == ""))
	# Several last days to answer on one day: one line, the names on the hover (the parent, 2026-11-21).
	var due := shown.filter(func(e: Dictionary) -> bool: return String(e["mark"]) == "deadline")
	if due.size() > 1:
		shown = shown.filter(func(e: Dictionary) -> bool: return String(e["mark"]) != "deadline")
		shown.append({"text": "", "short": Strings.tn("%d answer by", "%d answer by", due.size()) % due.size(), "mark": "deadline"})
	if band:
		_line({"text": band_label, "mark": ""})
	var room := MAX_LINES - (1 if band else 0)
	for i in mini(shown.size(), room):
		if i == room - 1 and shown.size() > room:
			_line({"text": Strings.tn("+%d more", "+%d more", shown.size() - i) % (shown.size() - i), "mark": ""})
			break
		_line(shown[i])


func _line(e: Dictionary) -> void:
	var s := UiTheme.text_scale()
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	_lines.add_child(row)
	var lead: Control
	if String(e.get("person", "")) != "":
		lead = Portrait.framed_for(String(e["person"]), FACE * s)
	else:
		lead = Mark.new()
		(lead as Mark).kind = String(e["mark"])
	lead.custom_minimum_size = Vector2(LEAD * s, FACE.y * s)
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lead)
	var label := Label.new()
	label.theme_type_variation = UiTheme.CAPTION if String(e["mark"]) == "" else UiTheme.CHIP_TEXT
	label.text = String(e.get("short", e["text"]))  # i18n: row-ok the grid's words, translated where they were built
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)


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


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size).grow(-1.0)
	var accent := UiTheme.accent()
	draw_rect(r, UiTheme.SLATE if selected else UiTheme.HULL)
	if tinted:
		draw_rect(r, Color(accent, 0.22))
	var s := UiTheme.text_scale()
	if band:
		# Edge to edge, so a trip's days join into one bar along the week (Design's kit restyles it).
		draw_rect(Rect2(0.0, 19.0 * s, size.x, FACE.y * s + 2.0), Color(accent, 0.30))
	draw_rect(r, accent if today or has_focus() else UiTheme.EDGE, false, 2.0 if today or has_focus() else 1.0)
	var font := get_theme_default_font()
	var fs := roundi(UiTheme.SIZE_SMALL * s)
	draw_string(font, Vector2(6.0, 3.0 + font.get_ascent(fs)), str(day), HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
		UiTheme.TEXT if not tinted else accent.lightened(0.3))
	if today:
		draw_string(font, Vector2(10.0 + font.get_string_size(str(day), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x, 3.0 + font.get_ascent(fs)),
			Strings.t("Today"), HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(UiTheme.SIZE_MICRO * s), accent)


## A line's lead: its entry's kind as a shape (the header's list), drawn.
class Mark extends Control:
	var kind := ""

	func _draw() -> void:
		var at := size / 2.0
		var m := 3.5
		var accent := UiTheme.accent()
		match kind:
			"booking":
				draw_circle(at, m, accent)
			"away", "":
				pass
			"fixed":
				draw_rect(Rect2(at - Vector2(m, m), Vector2(m, m) * 2.0), UiTheme.TEXT_DIM, false, 1.2)
			"due":
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -m), at + Vector2(m, 0), at + Vector2(0, m), at + Vector2(-m, 0)]), UiTheme.WARN)
			_:
				draw_colored_polygon(PackedVector2Array([at + Vector2(0, -m), at + Vector2(m, m), at + Vector2(-m, m)]), UiTheme.WARN)
