extends Control

## One day of the Diary's month grid -- V5.2 b+ R8, the month page since picture A (the
## author's pick, 2026-11-20), a TILE since G3 S2 (g3-spec.md section 2, "Tile" and "A day's
## contents"). The cell itself is drawn, not a Button: a tile, a today ring, a bookable place
## and the trip's capsule would each need a stylebox override, which tests/test_ui_theme.gd
## forbids in a panel (chart_bars.gd is the precedent). A click picks the day (diary_grid.gd).
##
## What the day holds is WRITTEN in it, a line an entry, each led by its kind's mark -- a shape
## as well as a colour (V5.1-d2: no colour-only layer): a booking a filled dot in the accent (the
## player's own), a fixed date a hollow square, a commitment falling due a diamond and a
## request's last day to answer a triangle, both in the attention tone. An audience is an
## APPOINTMENT: a control-grey card with the person's face and two lines. A visit's trip is the
## capsule diary_band.gd draws, one per week row. Past MAX_LINES the last line says "+N".
##
## The armed person's free day carries a BOOKABLE PLACE ("See <name>", a dashed accent outline;
## under the pointer the accent fill); a day of their window the diary holds says it is taken.
## A booking just made is FRESH: its appointment wears the accent and drains to grey (the morph,
## Motion.MORPH_S and DRAIN_S), and keeps its check. A day before the 1st or after the last is
## OUT of the month: dated, outlined, and it takes neither a click nor the keyboard.

signal picked(day: int)
## The pointer entered (true) or left a day of the trip `key`: the grid lights every day of it.
signal band_hover(key: String, on: bool)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const Band = preload("res://src/ui/diary_band.gd")
const Motion = preload("res://src/ui/motion.gd")

## px at text size 100 %: a day's floor, wide enough for a short name, tall enough for three
## lines. The cells EXPAND to fill the page; at 115 % a 100 px floor beside the people column
## outgrew the dock (pass 2 TAKE 6: a sideways scroll).
const SIZE := Vector2(76, 74)  # G3 S2: 84 -> 76, room for the tiles' gap and the sheet's padding at 115 %
const MARK := 3.5
const MAX_LINES := 3
## px at text size 100 %: a line's lead (its mark or the face) and the face itself.
const LEAD := 12.0
const FACE := Vector2(12, 16)
## px at text size 100 %: a bookable place's height, and the grid's gap a joined capsule spans.
const PLACE_H := 24.0
const GAP := 6.0

var day := 0
## Out of the shown month (a day before the 1st or after the last): dated, inert.
var outside := false
## The date as written: the day's number, or "1 Mar" on a month's first and the grid's first tile.
var caption := ""
var today := false
var tinted := false  # a free day of the armed person's window: a click books it
var selected := false
## The bookable place's words ("See Ferrand") on a free day of the armed window, else "".
var offer := ""
## The armed person's day the diary holds: the sim's reason, in words; "" otherwise.
var taken := ""
## A visit's trip covers this day (diary_band.gd): `band_label` the host on the run's first day
## and on a Monday, "" elsewhere; the capsule's ends, the leg named here, the meeting pill.
var band := false
var band_label := ""
var band_key := ""
var band_left := ""
var band_right := ""
var band_leg := ""
var band_name := ""
var band_meeting := false
var band_hot := false  # the pointer is on a day of this trip
var band_picked := false
## The day's entries, the grid's {text, mark, person}: one line each, up to MAX_LINES.
var entries: Array = []
## The appointment just booked on this day (its person's id), and the accent's drain, 0 to 1.
var fresh := false
var fresh_person := ""
var drain := 1.0
var _down := false  # a press began on this cell: only its own release picks it
var _hover := false
var _lines: VBoxContainer
var _box := StyleBoxFlat.new()  # reused per draw: a local one would be freed before the server draws it


func _init() -> void:
	custom_minimum_size = SIZE * UiTheme.text_scale()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	mouse_entered.connect(_hovered.bind(true))
	mouse_exited.connect(_hovered.bind(false))


## The lines, after add_child() (a child's anchors read this cell) and once `entries` is set.
func fill() -> void:
	if outside:
		focus_mode = Control.FOCUS_NONE
		return
	var s := UiTheme.text_scale()
	_lines = VBoxContainer.new()
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_theme_constant_override("separation", 2)
	add_child(_lines)
	_lines.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lines.offset_left = 5.0 * s
	_lines.offset_right = -4.0 * s
	# Under the date, and under the trip's capsule where one runs through the day.
	_lines.offset_top = (Band.TOP + Band.HEIGHT + 3.0 if band else 21.0) * s
	# The band holds the trip, so its journey's and its meeting's entries go to the hover.
	var shown := entries.filter(func(e: Dictionary) -> bool: return String(e["mark"]) != "away" and not (band and String(e["mark"]) == "booking" and String(e.get("person", "")) == ""))
	# Several last days to answer on one day: one line, the names on the hover (the parent, 2026-11-21).
	var due := shown.filter(func(e: Dictionary) -> bool: return String(e["mark"]) == "deadline")
	if due.size() > 1:
		shown = shown.filter(func(e: Dictionary) -> bool: return String(e["mark"]) != "deadline")
		shown.append({"text": "", "short": Strings.tn("%d answer by", "%d answer by", due.size()) % due.size(), "mark": "deadline"})
	# A place or a taken day sits at the tile's foot: one line fewer above it.
	var room := MAX_LINES - (1 if band else 0) - (1 if offer != "" or taken != "" else 0)
	for i in mini(shown.size(), room):
		if i == room - 1 and shown.size() > room:
			_line({"text": Strings.tn("+%d more", "+%d more", shown.size() - i) % (shown.size() - i), "mark": ""})
			break
		if String(shown[i].get("person", "")) != "" and String(shown[i]["mark"]) == "booking":
			_appointment(shown[i])
		else:
			_line(shown[i])
	# The tile grows to hold its lines (a card and two lines outgrow the floor, pass 2 TAKE 3), and
	# the place drawn at its foot, which must never sit on a card or a line.
	var place := (PLACE_H + 8.0) * s if offer != "" or taken != "" else 3.0 * s
	custom_minimum_size.y = maxf(SIZE.y * s, _lines.offset_top + _lines.get_combined_minimum_size().y + place)


func _line(e: Dictionary) -> void:
	var s := UiTheme.text_scale()
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 3)
	_lines.add_child(row)
	var lead := Mark.new()
	lead.kind = String(e["mark"])
	lead.custom_minimum_size = Vector2(LEAD * s, FACE.y * s)
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lead)
	row.add_child(_label(String(e.get("short", e["text"])), UiTheme.CAPTION if String(e["mark"]) == "" else UiTheme.CHIP_TEXT))  # i18n: row-ok the grid's words, translated where they were built


## An audience: the appointment card, its face and two lines (what, then who).
func _appointment(e: Dictionary) -> void:
	var s := UiTheme.text_scale()
	var card := Appointment.new()
	card.fresh = fresh and String(e["person"]) == fresh_person
	card.drain = drain
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.add_child(card)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 4)
	card.add_child(row)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 3.0 * s
	row.offset_right = -(13.0 if card.fresh else 3.0) * s  # room for the check
	var face := Portrait.framed_for(String(e["person"]), Vector2(15, 20) * s)
	ignore_mouse(face)
	face.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(face)
	var words := VBoxContainer.new()
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", -2)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	words.add_child(_label(Strings.t("Audience"), UiTheme.CHIP_TEXT))
	words.add_child(_label(String(e.get("short", e["text"])), UiTheme.CHIP_TEXT))  # i18n: row-ok the grid's words
	card.ink(drain)
	card.custom_minimum_size.y = 28.0 * s


func _label(text: String, variation: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = variation
	label.text = text  # i18n: row-ok the caller's words, translated where they were built
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


## The trip's piece on this day, from diary_band.gd's bands(): `name` the trip's (for the
## meeting pill), `picked` whether the day is the one picked.
func wear_band(b: Dictionary, name: String, picked: bool) -> void:
	band_label = String(b["label"])  # i18n: row-ok the band's words, worded in diary_band.gd
	band_key = String(b["key"])
	band_left = String(b["left"])
	band_right = String(b["right"])
	band_leg = String(b["leg"])
	band_meeting = bool(b["meeting"])
	band_name = name
	band_picked = band_meeting and picked


## The day holds the appointment just booked (the grid starts its drain only then: the redraw
## that disarms the grid comes before the booking lands).
func has_fresh_card() -> bool:
	return _lines != null and _lines.get_children().any(func(c: Node) -> bool: return c is Appointment and c.fresh)


## The booking's beats at `t` (0 to 1, the grid's clock, which outlives a redraw of this cell):
## the accent drains to grey, and the card grows into place over the first MORPH_S, overshooting.
func set_drain(t: float) -> void:
	drain = t
	for card in (_lines.get_children() if _lines != null else []):
		if card is Appointment:
			card.drain = t
			card.ink(t)
			var grow := minf(t * Motion.DRAIN_S / Motion.MORPH_S, 1.0)
			card.scale = Vector2.ONE * (0.9 + 0.1 * Tween.interpolate_value(0.0, 1.0, grow, 1.0, Tween.TRANS_BACK, Tween.EASE_OUT))
			card.pivot_offset = card.size / 2.0
			card.queue_redraw()


## A face's inner control stops the mouse by default: a press on it would never reach the cell
## (a dead click) and would not count as the day in hand (pass 1 on #434).
static func ignore_mouse(node: Node) -> void:
	if node is Control:
		(node as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		ignore_mouse(child)


func _hovered(on: bool) -> void:
	_hover = on and not outside
	if band:
		band_hover.emit(band_key, on)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_FOCUS_ENTER or what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if outside:
		return
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
	var s := UiTheme.text_scale()
	var r := Rect2(Vector2.ZERO, size)
	var accent := UiTheme.accent()
	_box.set_border_width_all(0)
	_box.set_corner_radius_all(UiTheme.R_TILE)
	if outside:
		_box.bg_color = Color(0, 0, 0, 0)
		_box.set_border_width_all(1)
		_box.border_color = UiTheme.LINE
	else:
		_box.bg_color = UiTheme.TILE_HOVER if _hover or selected else UiTheme.TILE
	if today or (has_focus() and not outside):
		# Today and the keyboard's day: a 2 px accent outline inside the tile.
		_box.set_border_width_all(2)
		_box.border_color = accent
	draw_style_box(_box, r)
	if band:
		# The grid's own gap, read live: its separation and this reach agree after a text-size change.
		Band.draw(self, _box, float(get_parent().get_theme_constant("h_separation")) if get_parent() is GridContainer else GAP * s)
	_draw_date(s, accent)
	if offer != "" or taken != "":
		_draw_place(s, accent)


func _draw_date(s: float, accent: Color) -> void:
	var font := get_theme_default_font()
	var fs := roundi(UiTheme.SIZE_SMALL * s)
	# Today's number alone goes in its disc: "1 Jan" would swell it past the tile's corner.
	var text := caption if caption != "" and not today else str(day)
	var base := 5.0 * s + font.get_ascent(fs)
	var x := 8.0 * s
	if today:
		# The date's number white on the accent fill, the word in the accent.
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var d := maxf(w + 8.0 * s, 18.0 * s)
		draw_circle(Vector2(x + d / 2.0 - 3.0 * s, base - font.get_ascent(fs) / 2.0 + 1.0), d / 2.0, UiTheme.accent_fill())
		draw_string(font, Vector2(x + (d - w) / 2.0 - 3.0 * s, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.on_accent_fill())
		draw_string(font, Vector2(x + d + 2.0 * s, base), Strings.t("Today"), HORIZONTAL_ALIGNMENT_LEFT, -1, fs, accent)
		return
	draw_string(font, Vector2(x, base), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, UiTheme.TEXT_OFF if outside else UiTheme.TEXT_DIM)


## The bookable place at the tile's foot: a dashed accent outline and its words, the accent fill
## under the pointer; or the day taken, outlined, the words struck through and the reason in amber.
func _draw_place(s: float, accent: Color) -> void:
	var font := get_theme_default_font()
	var fs := roundi(UiTheme.SIZE_SMALL * s)
	var place := Rect2(5.0 * s, size.y - (PLACE_H + 5.0) * s, size.x - 10.0 * s, PLACE_H * s)
	var mid := place.position.y + place.size.y / 2.0 + font.get_ascent(fs) / 2.0 - 1.0
	if taken != "":
		_box.set_corner_radius_all(UiTheme.R_SMALL)
		_box.bg_color = Color(0, 0, 0, 0)
		_box.set_border_width_all(1)
		_box.border_color = UiTheme.LINE_STRONG
		draw_style_box(_box, place)
		draw_string(font, Vector2(place.position.x + 6.0 * s, mid), taken, HORIZONTAL_ALIGNMENT_LEFT, place.size.x - 10.0 * s, roundi(UiTheme.SIZE_MICRO * s), UiTheme.WARN)
		return
	if _hover:
		_box.set_corner_radius_all(UiTheme.R_SMALL)
		_box.set_border_width_all(0)
		_box.bg_color = UiTheme.accent_fill()
		draw_style_box(_box, place)
	else:
		_dashed(place, accent, 1.5)
	draw_string(font, Vector2(place.position.x + 8.0 * s, mid), offer, HORIZONTAL_ALIGNMENT_LEFT, place.size.x - 12.0 * s, fs,
		UiTheme.on_accent_fill() if _hover else accent)


## A dashed rounded outline: dashes along the straight runs, arcs at the corners.
func _dashed(r: Rect2, tone: Color, width: float) -> void:
	var c := float(UiTheme.R_SMALL)
	var dash := 4.0
	draw_dashed_line(r.position + Vector2(c, 0), Vector2(r.end.x - c, r.position.y), tone, width, dash)
	draw_dashed_line(Vector2(r.position.x + c, r.end.y), r.end - Vector2(c, 0), tone, width, dash)
	draw_dashed_line(r.position + Vector2(0, c), Vector2(r.position.x, r.end.y - c), tone, width, dash)
	draw_dashed_line(Vector2(r.end.x, r.position.y + c), r.end - Vector2(0, c), tone, width, dash)
	draw_arc(r.position + Vector2(c, c), c, PI, PI * 1.5, 6, tone, width)
	draw_arc(Vector2(r.end.x - c, r.position.y + c), c, PI * 1.5, TAU, 6, tone, width)
	draw_arc(r.end - Vector2(c, c), c, 0.0, PI * 0.5, 6, tone, width)
	draw_arc(Vector2(r.position.x + c, r.end.y - c), c, PI * 0.5, PI, 6, tone, width)


## An appointment's card: CONTROL grey, R_SMALL; fresh, the accent fill draining to grey and a
## check in the good tone.
class Appointment extends Control:
	var fresh := false
	var drain := 1.0
	var _box := StyleBoxFlat.new()

	## The words' ink follows the fill: the fill's own (dark on a light accent such as Germany's
	## yellow) while fresh, back to the theme's as the accent drains (pass 2 TAKE 2). A modulate,
	## not a colour override: the theme's text tone times this.
	func ink(t: float) -> void:
		var plain := Color(1, 1, 1)  # the identity modulate: the theme's own tone
		var tone := UiTheme.on_accent_fill().lerp(plain, t) if fresh else plain
		for label in find_children("*", "Label", true, false):  # i18n: ok a class name
			(label as Label).self_modulate = tone

	func _draw() -> void:
		_box.set_corner_radius_all(UiTheme.R_SMALL)
		_box.bg_color = UiTheme.accent_fill().lerp(UiTheme.CONTROL, drain) if fresh else UiTheme.CONTROL
		draw_style_box(_box, Rect2(Vector2.ZERO, size))
		if fresh:
			var s := UiTheme.text_scale()
			var at := Vector2(size.x - 7.0 * s, size.y / 2.0)
			draw_polyline(PackedVector2Array([at + Vector2(-4, 0) * s, at + Vector2(-1.5, 2.5) * s, at + Vector2(3.5, -3) * s]), UiTheme.GOOD, 2.0, true)


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
