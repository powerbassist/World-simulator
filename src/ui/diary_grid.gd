extends VBoxContainer

## The Diary as a month grid -- V5.2 b+ R8 (docs/design/v5.2-bplus-spec.md, the
## author: "a full agenda grid"). Seven columns by weeks, paged across the
## booking horizon (BOOKING_HORIZON_MONTHS), today ringed in the accent. Every
## day carries a mark per entry (diary_day.gd): the register's bookings and the
## fixed dates the panel hands in, a commitment falling due and a waiting
## request's last day to answer, read here. The month page (picture A, the author's pick):
## a person is ARMED -- a request's See them or Go, a summons' See them (diary_people.gd)
## -- and every free day of their window is tinted; a click on one books it, the mouse's
## and the keyboard's path alike. Any other click lists the day's entries, and a day of the
## window the diary cannot take says why there.
##
## The day list is `day_list`, which the panel places inside its scroll: a list
## that changes height must not move the booking form under it (the form's own
## rule, calendar_panel.gd). A player bill's vote day (R2) joins the marks once
## the sim tables bills; today a bill divides the day it is proposed.
##
## Reads sim state, writes none: a booking goes out as `booked` (the Diary's
## audience wiring calls Audiences.book), a cancel as `cancel_requested`.

signal booked(request_id: String, date: Dictionary)
## A summons' day picked: the president asks to see `person_id` (Audiences.summon).
signal summoned(person_id: String, date: Dictionary)
## The armed person changed, or none is: the column's See them reads it.
signal armed_changed
signal cancel_requested(key: String)
## A commitment's "Call": the Diary's verb on a word falling due (pre-gate RF3).
signal call_requested(person_id: String)
## The day list was rebuilt (deferred to the frame's end, past every early return):
## a pending booking puts the focus back (diary_booking.gd, QA's TAKE on #221).
signal listed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const DateText = preload("res://src/ui/date_text.gd")
const DiaryDay = preload("res://src/ui/diary_day.gd")
const Band = preload("res://src/ui/diary_band.gd")
const Furniture = preload("res://src/ui/diary_furniture.gd")
const Words = preload("res://src/ui/lever_words.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const President = preload("res://src/sim/president.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const DealWords = preload("res://src/ui/deal_words.gd")

## Monday first, as a European diary is ruled.
const WEEKDAYS := ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]  # i18n: msgid
## px at text size 100 %: the day list's floor -- its date heading, a "Book here"
## and one entry row. The list's scroll is the Diary's only flexible region, and
## everything else grows: a card a pending request beside the grid, "Your word"
## under it, the text size. Without a floor they squeezed it to nothing and "Book
## here" fell out of view (#231's QA round: 4 requests at 100 %, any at the former 130 %); with
## one, the Diary grows past the dock instead and its page scrolls as one.
const LIST_ROOM_PX := 96.0

var day_list := VBoxContainer.new()
## Where the president's word sits, under the grid: the panel places it, as it does day_list.
var promise_slot := VBoxContainer.new()
## The day list's scroll, which the panel places (list_scroll()).
var _list_scroll: ScrollContainer
var _state
var _loader
var _items: Array = []  # the panel's: {year, month, day, text, mark, cancel}
## The shown month, absolute (year x 12 + month), not an offset from today: when
## the month turns, the page and the picked day stay where the player left them.
var _month_abs := 0
var _selected := 0  # the picked day of the shown month, 0 for none
var _drawn_day := 0  # the state's day at the last render: a new day redraws (today, offers)
## A pick asked for before the panel's first refresh handed in a state (a briefing
## Go opens the Diary and picks the due day in one frame): applied by show_items.
var _wanted := Vector3i.ZERO
var _title: Label
## The three counters over the month, each [figure, caption] (diary_furniture.gd).
var _waiting: Array
var _next: Array
var _due: Array
## Next month's strip under the grid.
var _next_strip: HFlowContainer
## The armed person's window in words, over the month (armed_line()); hidden when none is.
var _armed_label: Label
var _days: GridContainer
var _later: Button
## The person a click on a free day books: {id (the request's, "" for a summons), person_id,
## person (the shown name), summons}; {} for none. arm() sets it; a booking clears it.
var armed := {}
## The armed person's window, read once a render: the days and why one is refused.
var _armed_dates: Array = []
## G3 S2: the day just booked, {abs month, day, person id}, whose appointment drains from the
## accent once (`played`) and keeps its check until the next booking.
var _fresh := {}


func _init() -> void:
	name = "DiaryGrid"  # i18n: ok a node name, found by tests
	add_theme_constant_override("separation", 4)
	day_list.name = "DayList"  # i18n: ok a node name, found by tests
	day_list.add_theme_constant_override("separation", 4)


func _ready() -> void:
	_armed_label = Label.new()
	_armed_label.name = "ArmedLine"  # i18n: ok a node name, found by tests
	_armed_label.theme_type_variation = UiTheme.WARN_TEXT
	_armed_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_armed_label)
	var head := HBoxContainer.new()
	add_child(head)
	var back := PanelKit.sized(Button.new())
	back.text = "<"  # i18n: ok a glyph
	back.tooltip_text = tr("Previous month")
	back.pressed.connect(page_by.bind(-1))
	head.add_child(back)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.FIGURE  # G3: the month's name at the figure size
	_title.custom_minimum_size.x = 150.0 * UiTheme.text_scale()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_title)
	_later = PanelKit.sized(Button.new())
	_later.name = "Later"  # i18n: ok a node name, found by tests
	_later.text = ">"  # i18n: ok a glyph
	_later.tooltip_text = tr("Next month")
	_later.pressed.connect(page_by.bind(1))
	head.add_child(_later)
	var spring := Control.new()
	spring.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spring)
	_waiting = Furniture.counter(head, "Waiting")  # i18n: ok a node name, found by tests
	_next = Furniture.counter(head, "NextUp")
	_due = Furniture.counter(head, "FirstDue")
	Furniture.legend(self)
	var names := GridContainer.new()
	names.columns = 7
	names.add_theme_constant_override("h_separation", int(DiaryDay.GAP * UiTheme.text_scale()))
	add_child(names)
	for wd in WEEKDAYS:
		var label := Label.new()
		label.text = tr(wd)
		label.theme_type_variation = UiTheme.CAPTION
		label.custom_minimum_size.x = DiaryDay.SIZE.x * UiTheme.text_scale()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		names.add_child(label)
	_days = GridContainer.new()
	_days.columns = 7
	for sep in ["h_separation", "v_separation"]:
		_days.add_theme_constant_override(sep, int(DiaryDay.GAP * UiTheme.text_scale()))
	add_child(_days)
	_next_strip = HFlowContainer.new()
	_next_strip.name = "NextMonth"  # i18n: ok a node name, found by tests
	_next_strip.add_theme_constant_override("h_separation", 12)
	add_child(_next_strip)


## The scroll the panel puts the day list in: it takes the panel's slack (EXPAND,
## which TabPage reads to fill the dock) down to LIST_ROOM_PX, and follows the
## keyboard onto a "Book here" below its fold.
func list_scroll() -> ScrollContainer:
	_list_scroll = ScrollContainer.new()
	_list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list_scroll.follow_focus = true
	_list_scroll.custom_minimum_size.y = LIST_ROOM_PX * UiTheme.text_scale()
	return _list_scroll


## Arm a person: their window is tinted and a click on a free day books it. {} disarms.
func arm(target: Dictionary) -> void:
	armed = target
	armed_changed.emit()
	_render()


func show_items(state, loader, items: Array) -> void:
	_state = state
	_loader = loader
	_items = items
	var kept := clampi(_month_abs, _now(), _now() + K.BOOKING_HORIZON_MONTHS)
	if kept != _month_abs:
		_selected = 0
	_month_abs = kept
	_render()
	if _wanted != Vector3i.ZERO:
		pick(_wanted.x, _wanted.y, _wanted.z)


## The clock runs with the Diary open, and the panel is redrawn on a month, never a
## day: today's ring and the offered days follow the day here (QA's TAKE 2 on #153).
func _process(_delta: float) -> void:
	if _state != null and _days != null and int(_state.day) != _drawn_day and is_visible_in_tree() and not _in_hand():
		_render()


## A day the pointer is on while a person is armed, or anything in the day list the pointer
## is on (#431 pass 2, TAKE 2): the daily redraw frees every cell and row, which would drop a
## click mid-press. It waits, so today's ring can lag until the pointer leaves; a booking still
## redraws, and a day pressed as the clock turns it into today books the first free one
## (audience_driver.gd). The keyboard alone holds nothing: after a Go it stands on a day for
## good, and diary_booking's _refocus puts it back after a redraw.
func _in_hand() -> bool:
	var viewport := get_viewport()
	if viewport == null:
		return false
	var hovered := viewport.gui_get_hovered_control()
	return (hovered is DiaryDay and not armed.is_empty()) \
			or (hovered != null and day_list != null and day_list.is_ancestor_of(hovered))


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
	_wanted = Vector3i(year, month, day) if _state == null else Vector3i.ZERO
	if _state == null:
		return
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
	_title.text = DateText.month_long_year(ym.y, ym.x)
	for child in _days.get_children():
		_days.remove_child(child)
		child.queue_free()
	var entries := _entries(ym.x, ym.y)
	var offered := _offered(ym.x, ym.y)
	# Monday-first: the engine's weekday is 0 for Sunday.
	var first: int = (int(Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_datetime_dict(
		{"year": ym.x, "month": ym.y, "day": 1, "hour": 0, "minute": 0, "second": 0})))["weekday"]) + 6) % 7
	# G3 S2: whole weeks -- the days before the 1st and after the last, out of the month.
	var before := Vector2i(ym.x - (1 if ym.y == 1 else 0), 12 if ym.y == 1 else ym.y - 1)
	var before_len := Calendar.days_in_month(before.x, before.y)
	for i in first:
		_outside(before_len - first + 1 + i, before.y, i == 0)
	var is_now := _month_abs == _now()
	var trips: Array = Calendar.day_cells(_state, ym.x, ym.y)
	var bands := Band.bands(trips, entries, first)
	var who := String(armed.get("person", ""))
	var place := tr("See %s") % who.get_slice(" ", who.get_slice_count(" ") - 1)
	for d in range(1, Calendar.days_in_month(ym.x, ym.y) + 1):
		var cell := DiaryDay.new()
		cell.name = "Day_%d" % d
		cell.day = d
		cell.caption = DateText.day_mon(1, ym.y) if d == 1 else ""
		cell.today = is_now and d == int(_state.day)
		cell.selected = d == _selected
		cell.band = bands.has(d)
		if cell.band:
			var b: Dictionary = bands[d]
			cell.band_label = String(b["label"])  # i18n: row-ok the band's words, worded in diary_band.gd
			cell.band_key = String(b["key"])
			cell.band_left = String(b["left"])
			cell.band_right = String(b["right"])
			cell.band_leg = String(b["leg"])
			cell.band_meeting = bool(b["meeting"])
			cell.band_name = _band_name(bands, d)
			cell.band_picked = cell.band_meeting and d == _selected
			cell.band_hover.connect(_light_trip)
		# Only a day that books takes the tint: a taken day of the window read as free (#431 R10).
		cell.tinted = offered.has(d) and bool((offered[d][0]["date"] as Dictionary).get("free", false))
		cell.offer = place if cell.tinted else ""
		cell.taken = Strings.t(String((offered[d][0]["date"] as Dictionary).get("reason", ""))) if offered.has(d) and not cell.tinted else ""  # i18n: row-ok the sim's reason, its English the msgid
		cell.fresh = not _fresh.is_empty() and int(_fresh["at"]) == _month_abs and int(_fresh["day"]) == d
		cell.fresh_person = String(_fresh.get("person", ""))
		var texts := PackedStringArray()
		cell.entries = entries.get(d, [])
		for e in cell.entries:
			texts.append(String(e["text"]))
		for o in offered.get(d, []):
			# A refused day of the window says why on its hover, as the day list does.
			var why := String((o["date"] as Dictionary).get("reason", ""))
			if why != "":
				texts.append("%s: %s" % [String(armed["person"]), Strings.t(why)])  # i18n: row-ok the sim's reason, its English the msgid
		cell.tooltip_text = "\n".join(texts)
		cell.picked.connect(_on_day)
		_days.add_child(cell)
		cell.fill()
		if cell.fresh and not bool(_fresh.get("played", false)):
			_fresh["played"] = true
			cell.play_fresh()
	var after := 1
	while _days.get_child_count() % 7 != 0:
		_outside(after, 1 if ym.y == 12 else ym.y + 1, after == 1)
		after += 1
	_render_furniture(ym)
	_render_list(entries.get(_selected, []), offered.get(_selected, []))
	_armed_label.text = armed_line()
	_armed_label.visible = _armed_label.text != ""


## A day out of the shown month: dated ("23 Feb" on the grid's first tile and a month's 1st), inert.
func _outside(d: int, month: int, named: bool) -> void:
	var cell := DiaryDay.new()
	cell.name = "Out_%d_%d" % [month, d]  # i18n: ok a node name
	cell.outside = true
	cell.day = d
	cell.caption = DateText.day_mon(d, month) if named else ""
	_days.add_child(cell)
	cell.fill()


## The trip's name on its meeting pill: the run's label, read back from its first day.
func _band_name(bands: Dictionary, d: int) -> String:
	while d > 1 and bands.has(d - 1) and String(bands[d - 1]["key"]) == String(bands[d]["key"]) and String(bands[d]["label"]) == "":  # i18n: row-ok the band's words, worded in diary_band.gd
		d -= 1
	return String(bands[d]["label"])  # i18n: row-ok the band's words, worded in diary_band.gd


## The pointer on one day of a trip lights every day of it, every row; leaving it, none.
func _light_trip(key: String, on: bool) -> void:
	for cell in _days.get_children():
		if cell is DiaryDay and cell.band and cell.band_key == key and cell.band_hot != on:
			cell.band_hot = on
			cell.queue_redraw()


## The counters and next month's strip, off the same reads as the cells.
func _render_furniture(ym: Vector2i) -> void:
	var ns = _state.player()
	_waiting[0].text = str(Audiences.waiting_count(ns))
	_waiting[1].text = tr("waiting")
	var today := int(_state.year) * 10000 + int(_state.month) * 100 + int(_state.day)
	var soonest := {}
	for e in _items:
		var at := int(e["year"]) * 10000 + int(e["month"]) * 100 + int(e["day"])
		if String(e["mark"]) == "booking" and at > today and (soonest.is_empty() or at < int(soonest["at"])):
			soonest = e.merged({"at": at})
	_next[0].text = DateText.day_mon(int(soonest["day"]), int(soonest["month"])) if not soonest.is_empty() else PanelKit.MISSING
	# The short words, as a cell's: the full line in a caption that does not wrap widened the grid.
	_next[1].text = String(soonest.get("short", soonest.get("text", tr("next"))))  # i18n: row-ok the grid's words
	var due := -1
	for row in Audiences.pending(ns):
		due = Audiences.answer_by(row) if due < 0 else mini(due, Audiences.answer_by(row))
	var y := floori((due - 1) / 12.0)
	_due[0].text = DateText.day_mon(Calendar.days_in_month(y, due - y * 12), due - y * 12) if due > 0 else PanelKit.MISSING
	_due[1].text = tr("first answer-by")
	_due[1].theme_type_variation = UiTheme.WARN_TEXT if due > 0 else UiTheme.CAPTION
	var next := Vector2i(ym.x + (1 if ym.y == 12 else 0), 1 if ym.y == 12 else ym.y + 1)
	var rows: Array = []
	var later := _entries(next.x, next.y)
	var days := later.keys()
	days.sort()
	for d in days:
		for e in later[d]:
			if String(e["mark"]) != "away":
				rows.append({"day": d, "text": String(e["text"])})
	Furniture.next_month(_next_strip, DateText.month_year(next.y, next.x), rows)


## A click on a day: a free day of the armed person's window books; any other is picked.
func _on_day(d: int) -> void:
	var date := _armed_on(d)
	# Nobody armed (a load cleared it before the redraw): a stale tint books nothing.
	if armed.is_empty() or not bool(date.get("free", false)):
		_pick(d)
		return
	var target := armed
	_fresh = {"at": _month_abs, "day": d, "person": String(target.get("person_id", ""))}
	# arm() redraws: a refused summons leaves no stale tint, so no second click books on an
	# empty target (pass 2 TAKE 4).
	arm({})
	if bool(target.get("summons", false)):
		summoned.emit(String(target["person_id"]), date)
	else:
		booked.emit(String(target["id"]), date)


## Day `d` of the shown month in the armed person's window, {} when it is not in it.
func _armed_on(d: int) -> Dictionary:
	var ym := _shown()
	for date in _armed_dates:
		if int(date["year"]) == ym.x and int(date["month"]) == ym.y and int(date["day"]) == d:
			return date
	return {}


func _pick(d: int) -> void:
	_selected = d
	# Only a keyboard already on a day keeps one: a pick from a click elsewhere (See them) must
	# not hand Space to a day (pass 2 TAKE 8, the #427 ruling); diary_booking focuses a Go's day.
	var viewport := get_viewport()
	var owner: Control = viewport.gui_get_focus_owner() if viewport != null else null
	var keep := owner is DiaryDay and _days != null and _days.is_ancestor_of(owner)
	# A new day reads from its date: an offset left from scrolling the last one (or
	# LATER) would hide the "Book here" listed first. Not on the daily redraw.
	if _list_scroll != null:
		_list_scroll.scroll_vertical = 0
	_render()
	# The re-render freed the picked cell: its successor takes the focus, so a
	# keyboard player keeps their place (QA's RECORD on #153).
	var cell := _days.get_node_or_null("Day_%d" % d) as Control
	if cell != null and keep:
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
			_add(out, int(cell["day"]), {"text": Strings.t("Away: travelling to or from a visit"), "mark": "away", "cancel": "", "short": Strings.t("Travel")})
	var ns = _state.player()
	var abs_month := year * 12 + month
	# A commitment is judged as its month begins (Levers.tick_month), so its mark
	# is the first day.
	for row in President.commitments(ns):
		if int(row["due_month"]) == abs_month:
			var who: String = _loader.person_name(String(row["person_id"]))
			var want := PersonCard.object_text(_loader, ns, String(row["object"]), {})
			# The briefing's subject for this word (priorities.gd _commitments), so a
			# commitment's Go lands on its Call here.
			_add(out, 1, {"text": Words.commitment_text(String(row["kind"]), who, want, int(row["due_month"])), "mark": "due", "cancel": "", "short": Strings.t("Word due"),
				"call": String(row["person_id"]), "subject": "%s|%s|%s" % [row["kind"], row["person_id"], row["object"]]})
	# What people owe the president under a deal, as its month begins too.
	for row in President.owed(ns):
		if int(row["due_month"]) == abs_month:
			_add(out, 1, {"text": DealWords.owed_text(_loader, ns, row), "mark": "due", "cancel": "", "short": Strings.t("Owed you")})
	# A request lapses as its deadline month begins (Audiences._overdue), so the
	# last day to answer is the end of the month before -- the card's "Answer by".
	for row in Audiences.pending(ns):
		if Audiences.answer_by(row) == abs_month:
			_add(out, Calendar.days_in_month(year, month), {"text": Strings.t("Last day to answer %s") % _loader.person_name(String(row["person_id"])),
				"mark": "deadline", "cancel": "", "short": Strings.t("Answer by")})
	return out


## Day -> [{date}] the armed person can be seen on in the shown month, each with `free` and
## the sim's words for a refused one. The window is re-read every render: a day the clock
## turned or a booking took drops out on its own.
func _offered(year: int, month: int) -> Dictionary:
	var out := {}
	var ns = _state.player()
	_armed_dates = []
	if bool(armed.get("summons", false)):
		_armed_dates = Audiences.summon_days(_state, String(armed["person_id"]))
	elif not armed.is_empty():
		if String(Audiences.request(ns, String(armed["id"])).get("status", "")) != "pending":
			# Answered elsewhere, lapsed or booked: nothing is left to book.
			armed = {}
			armed_changed.emit.call_deferred()
		else:
			_armed_dates = Audiences.offered_dates(_state, ns, String(armed["id"]))
	for date in _armed_dates:
		if int(date["year"]) == year and int(date["month"]) == month:
			_add(out, int(date["day"]), {"date": date})
	var later := 0
	for row in Audiences.pending(ns):
		for date in Audiences.offered_dates(_state, ns, String(row["id"])):
			if int(date["year"]) * 12 + int(date["month"]) > year * 12 + month:
				later += 1
				break
	_later.text = "> %d" % later if later > 0 else ">"  # i18n: ok a glyph and a count
	# No column lists the requests any more: the button says some have days further on.
	_later.tooltip_text = tr_n("Next month: %d request offers a later day", "Next month: %d requests offer later days", later) % later if later > 0 else tr("Next month")
	return out


func _add(out: Dictionary, d: int, row: Dictionary) -> void:
	if not out.has(d):
		out[d] = []
	out[d].append(row)


func _render_list(entries: Array, offered: Array) -> void:
	listed.emit.call_deferred()
	for child in day_list.get_children():
		day_list.remove_child(child)
		child.queue_free()
	# Re-read on every redraw: the player can change the text size mid-game (#221 RECORD 8).
	if _list_scroll != null:
		_list_scroll.custom_minimum_size.y = LIST_ROOM_PX * UiTheme.text_scale()
	if _selected == 0:
		return
	var ym := _shown()
	PanelKit.heading(day_list, DateText.day_month_year(_selected, ym.y, ym.x))
	if entries.is_empty() and offered.is_empty():
		PanelKit.line(day_list, tr("Nothing on this day."))
	# A day of the armed person's window the diary cannot take: why, under the date.
	for o in offered:
		var why := String((o["date"] as Dictionary).get("reason", ""))
		if why != "":
			PanelKit.plain_line(day_list, "%s: %s" % [String(armed["person"]), Strings.t(why)], PanelKit.Tone.DIM)  # i18n: row-ok the sim's reason, its English the msgid
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
		# A word falling due: the president cannot do the minister's work from here,
		# but can talk to the person it was given to before it is judged.
		if String(e.get("call", "")) != "":
			var call := PanelKit.sized(Button.new())
			call.text = tr("Call")
			call.tooltip_text = tr("Call %s before this is judged") % _loader.person_name(String(e["call"]))
			var pid := String(e["call"])
			call.pressed.connect(func() -> void: call_requested.emit(pid))
			row.add_child(ActsOn.tag(call, [String(e["subject"])]))


## The armed person's window in words, for the line over the grid: "" when nobody is armed or
## no day of it is free (a refused day says why on its own hover).
func armed_line() -> String:
	if armed.is_empty() or not _armed_dates.any(func(d: Dictionary) -> bool: return bool(d.get("free", false))):
		return ""
	var last: Dictionary = _armed_dates[_armed_dates.size() - 1]
	return tr("Click a free day to see %s: any free day until %s.") % [String(armed["person"]),
		DateText.day_month_year(int(last["day"]), int(last["month"]), int(last["year"]))]
