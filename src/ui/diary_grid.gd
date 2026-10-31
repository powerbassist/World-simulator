extends VBoxContainer

## The Diary as a month grid -- V5.2 b+ R8 (docs/design/v5.2-bplus-spec.md, the
## author: "a full agenda grid"). Seven columns by weeks, paged across the
## booking horizon (BOOKING_HORIZON_MONTHS), today ringed in the accent. Every
## day carries a mark per entry (diary_day.gd): the register's bookings and the
## fixed dates the panel hands in, a commitment falling due and a waiting
## request's last day to answer, read here. A day a waiting request offers is
## tinted, and a click on any day lists its entries -- with "Book here" where a
## request offered it.
##
## The day list is `day_list`, which the panel places inside its scroll: a list
## that changes height must not move the booking form under it (the form's own
## rule, calendar_panel.gd). A player bill's vote day (R2) joins the marks once
## the sim tables bills; today a bill divides the day it is proposed.
##
## Reads sim state, writes none: a booking goes out as `booked` (the Diary's
## audience wiring calls Audiences.book), a cancel as `cancel_requested`.

signal booked(request_id: String, date: Dictionary)
signal cancel_requested(key: String)

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const DiaryDay = preload("res://src/ui/diary_day.gd")
const Words = preload("res://src/ui/lever_words.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const President = preload("res://src/sim/president.gd")

## Monday first, as a European diary is ruled.
const WEEKDAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]  # i18n: msgid

var day_list := VBoxContainer.new()
var _state
var _loader
var _items: Array = []  # the panel's: {year, month, day, text, mark, cancel}
## The shown month, absolute (year x 12 + month), not an offset from today: when
## the month turns, the page and the picked day stay where the player left them.
var _month_abs := 0
var _selected := 0  # the picked day of the shown month, 0 for none
var _drawn_day := 0  # the state's day at the last render: a new day redraws (today, offers)
var _title: Label
var _days: GridContainer


func _init() -> void:
	name = "DiaryGrid"  # i18n: ok a node name, found by tests
	add_theme_constant_override("separation", 4)
	day_list.name = "DayList"  # i18n: ok a node name, found by tests
	day_list.add_theme_constant_override("separation", 4)


func _ready() -> void:
	var head := HBoxContainer.new()
	add_child(head)
	var back := PanelKit.sized(Button.new())
	back.text = "<"  # i18n: ok a glyph
	back.tooltip_text = tr("Previous month")
	back.pressed.connect(page_by.bind(-1))
	head.add_child(back)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.HEADING
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_title)
	var on := PanelKit.sized(Button.new())
	on.text = ">"  # i18n: ok a glyph
	on.tooltip_text = tr("Next month")
	on.pressed.connect(page_by.bind(1))
	head.add_child(on)
	var names := GridContainer.new()
	names.columns = 7
	add_child(names)
	for wd in WEEKDAYS:
		var label := Label.new()
		label.text = tr(wd)
		label.theme_type_variation = UiTheme.CAPTION
		label.custom_minimum_size.x = DiaryDay.SIZE.x * UiTheme.text_scale()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		names.add_child(label)
	_days = GridContainer.new()
	_days.columns = 7
	add_child(_days)


func show_items(state, loader, items: Array) -> void:
	_state = state
	_loader = loader
	_items = items
	var kept := clampi(_month_abs, _now(), _now() + K.BOOKING_HORIZON_MONTHS)
	if kept != _month_abs:
		_selected = 0
	_month_abs = kept
	_render()


## The clock runs with the Diary open, and the panel is redrawn on a month, never a
## day: today's ring and the offered days follow the day here (QA's TAKE 2 on #153).
func _process(_delta: float) -> void:
	if _state != null and _days != null and int(_state.day) != _drawn_day and is_visible_in_tree():
		_render()


func page() -> int:
	return _month_abs - _now()


func page_by(delta: int) -> void:
	_month_abs = clampi(_month_abs + delta, _now(), _now() + K.BOOKING_HORIZON_MONTHS)
	_selected = 0
	_render()


## The page that holds (year, month), clamped to the horizon.
func show_month(year: int, month: int) -> void:
	_month_abs = clampi(year * 12 + month, _now(), _now() + K.BOOKING_HORIZON_MONTHS)
	_selected = 0
	_render()


## The page that holds (year, month), its `day` picked: a request's Days, so the
## day list under the grid carries that day's "Book here".
func pick(year: int, month: int, day: int) -> void:
	show_month(year, month)
	_pick(day)


func _now() -> int:
	return int(_state.year) * 12 + int(_state.month)


func _shown() -> Vector2i:
	var year := floori((_month_abs - 1) / 12.0)
	return Vector2i(year, _month_abs - year * 12)


func _render() -> void:
	if _state == null or _days == null or _state.player() == null:
		return
	_drawn_day = int(_state.day)
	var ym := _shown()
	_title.text = DateText.month_year(ym.y, ym.x)
	for child in _days.get_children():
		_days.remove_child(child)
		child.queue_free()
	var entries := _entries(ym.x, ym.y)
	var offered := _offered(ym.x, ym.y)
	# Monday-first: the engine's weekday is 0 for Sunday.
	var first: int = (int(Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_datetime_dict(
		{"year": ym.x, "month": ym.y, "day": 1, "hour": 0, "minute": 0, "second": 0})))["weekday"]) + 6) % 7
	for i in first:
		var gap := Control.new()
		gap.custom_minimum_size = DiaryDay.SIZE * UiTheme.text_scale()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_days.add_child(gap)
	var is_now := _month_abs == _now()
	for d in range(1, Calendar.days_in_month(ym.x, ym.y) + 1):
		var cell := DiaryDay.new()
		cell.name = "Day_%d" % d
		cell.day = d
		cell.today = is_now and d == int(_state.day)
		cell.selected = d == _selected
		cell.tinted = offered.has(d)
		var texts := PackedStringArray()
		for e in entries.get(d, []):
			cell.marks.append(String(e["mark"]))
			texts.append(String(e["text"]))
		cell.tooltip_text = "\n".join(texts)
		for o in offered.get(d, []):
			cell.offers[String(o["id"])] = o["date"]
		cell.picked.connect(_pick)
		cell.dropped.connect(func(id: String, date: Dictionary) -> void: booked.emit(id, date))
		_days.add_child(cell)
	_render_list(entries.get(_selected, []), offered.get(_selected, []))


func _pick(d: int) -> void:
	_selected = d
	_render()
	# The re-render freed the picked cell: its successor takes the focus, so a
	# keyboard player keeps their place (QA's RECORD on #153).
	var cell := _days.get_node_or_null("Day_%d" % d) as Control
	if cell != null:
		cell.grab_focus()


## Day -> [{text, mark, cancel}] for the shown month.
func _entries(year: int, month: int) -> Dictionary:
	var out := {}
	for e in _items:
		if int(e["year"]) == year and int(e["month"]) == month:
			_add(out, int(e["day"]), e)
	# A visit's journey either side of its meeting: the diary refuses those days
	# too (Calendar.day_cells, the ribbon's own read).
	for cell in Calendar.day_cells(_state, year, month):
		if bool(cell["travel"]):
			_add(out, int(cell["day"]), {"text": Strings.t("Away: travelling to or from a visit"), "mark": "away", "cancel": ""})
	var ns = _state.player()
	var abs_month := year * 12 + month
	# A commitment is judged as its month begins (Levers.tick_month), so its mark
	# is the first day.
	for row in President.commitments(ns):
		if int(row["due_month"]) == abs_month:
			var who: String = _loader.person_name(String(row["person_id"]))
			var want := PersonCard.object_text(_loader, ns, String(row["object"]), {})
			_add(out, 1, {"text": Words.commitment_text(String(row["kind"]), who, want, int(row["due_month"])), "mark": "due", "cancel": ""})
	# A request lapses as its deadline month begins (Audiences._overdue), so the
	# last day to answer is the end of the month before -- the card's "Answer by".
	for row in Audiences.pending(ns):
		if int(row["deadline_month"]) - 1 == abs_month:
			_add(out, Calendar.days_in_month(year, month), {"text": Strings.t("Last day to answer %s") % _loader.person_name(String(row["person_id"])),
				"mark": "deadline", "cancel": ""})
	return out


## Day -> [{request id, person, date}] a waiting request offers in the shown month.
func _offered(year: int, month: int) -> Dictionary:
	var out := {}
	var ns = _state.player()
	for row in Audiences.pending(ns):
		var rid := String(row["id"])
		for date in Audiences.offered_dates(_state, ns, rid):
			if int(date["year"]) == year and int(date["month"]) == month:
				_add(out, int(date["day"]), {"id": rid, "person": _loader.person_name(String(row["person_id"])), "date": date})
	return out


func _add(out: Dictionary, d: int, row: Dictionary) -> void:
	if not out.has(d):
		out[d] = []
	out[d].append(row)


func _render_list(entries: Array, offered: Array) -> void:
	for child in day_list.get_children():
		day_list.remove_child(child)
		child.queue_free()
	if _selected == 0:
		return
	var ym := _shown()
	PanelKit.heading(day_list, DateText.day_month_year(_selected, ym.y, ym.x))
	if entries.is_empty() and offered.is_empty():
		PanelKit.line(day_list, tr("Nothing on this day."))
	for e in entries:
		var row := HBoxContainer.new()
		day_list.add_child(row)
		var text := PanelKit.line(row, String(e["text"]), PanelKit.Tone.PLAIN)
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if String(e["cancel"]) != "":
			var cancel := PanelKit.sized(Button.new())
			cancel.text = tr("Cancel")
			cancel.pressed.connect(func() -> void: cancel_requested.emit(String(e["cancel"])))
			row.add_child(cancel)
	for o in offered:
		var date: Dictionary = o["date"]
		var book := PanelKit.sized(Button.new())
		# One per offering request: two requests can offer the same day, and a
		# second "BookHere" would be renamed "@Button@N" and lost to find_child.
		book.name = "BookHere_%s" % String(o["id"])  # i18n: ok a node name, found by tests
		book.text = tr("Book here: %s") % String(o["person"])
		book.disabled = not bool(date.get("free", true))
		var why := String(date.get("reason", ""))
		book.tooltip_text = Strings.t(why) if why != "" else ""  # i18n: row-ok the sim's reason, its English the msgid
		book.pressed.connect(func() -> void: booked.emit(String(o["id"]), date))
		day_list.add_child(book)
