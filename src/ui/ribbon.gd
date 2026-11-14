extends PanelContainer

## The horizon -- the bottom plate, V2.4a's day ribbon rebuilt at V5.3 (the author
## picked bar C of the pictures; gate H5, "the day bar is outdated"). Three calendar
## months on one line: this month by days with today's playhead, the next two
## compressed, and on the line the things that are DATED -- what is booked, and what
## falls due (a request lapsing, a desk decision deciding itself) -- so what pulls the
## player into next month is always in sight. The clock (date, pause, speeds) sits at
## its left end and the vote that ends the term at its right.
##
## Read-only over sim state like every surface since U2. The dated things are
## horizon_items.gd's read (the registers already carry them); Calendar.day_cells
## stays the whole rule about which days a booking occupies, so the horizon and the
## diary cannot disagree. A due is month-granular in the sim and is drawn at its
## month's END; a booking is day-exact.
##
## **Names are links.** A person on a chip is marked [p=id]Name[/p], so a hover shows
## their card (person_tip.gd), the same card every name in the game opens.

const Strings = preload("res://src/ui/strings.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const AudienceK = preload("res://src/sim/audience_constants.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Icon = preload("res://src/ui/icon.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Items = preload("res://src/ui/horizon_items.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")

## The plate's height (the workspace's dock reads it): one lane of chips, the line, the day
## numbers. 88 holds the largest text size (130 %) without the plate growing past the dock.
const STRIP_HEIGHT := 88
## The months' shares of the line: this month by days, then two compressed.
const SHARES: Array[float] = [0.5, 0.25, 0.25]
const LINE_Y := 40.0
const LANE_Y := 0.0
const CHIP_GAP := 6.0
const CLOCK_WIDTH := 480
const BLOCK_HEIGHT := 6.0
const ICON_PX := 14

var _state
var _loader
var _clock_slot: HBoxContainer
var _cells: Control
var _title: Label
var _vote_box: VBoxContainer
var _vote_value: Label
var _vote_months: Label
var _dirty := true
var _signature_seen: Array = []
var _items := {}
var _chips: Array[Control] = []


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	custom_minimum_size = Vector2(0, STRIP_HEIGHT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)

	_clock_slot = HBoxContainer.new()
	_clock_slot.custom_minimum_size = Vector2(CLOCK_WIDTH, 0)
	_clock_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_clock_slot)
	row.add_child(_rule())

	_cells = Control.new()
	_cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cells.mouse_filter = Control.MOUSE_FILTER_PASS
	_cells.clip_contents = true
	_cells.draw.connect(_draw_cells)
	_cells.resized.connect(func(): _dirty = true)
	row.add_child(_cells)
	_title = Label.new()
	_title.theme_type_variation = UiTheme.MICRO
	_title.position = Vector2(30, LINE_Y + 3)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cells.add_child(_title)

	row.add_child(_rule())
	_vote_box = VBoxContainer.new()
	_vote_box.add_theme_constant_override("separation", -3)
	_vote_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_vote_box.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(_vote_box)
	var caption := Label.new()
	caption.text = tr("NEXT VOTE")
	caption.theme_type_variation = UiTheme.MICRO
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vote_box.add_child(caption)
	var value_row := HBoxContainer.new()
	value_row.add_theme_constant_override("separation", 8)
	value_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vote_box.add_child(value_row)
	_vote_value = Label.new()
	_vote_value.theme_type_variation = UiTheme.FIGURE
	_vote_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_row.add_child(_vote_value)
	_vote_months = Label.new()
	_vote_months.theme_type_variation = UiTheme.CAPTION
	_vote_months.mouse_filter = Control.MOUSE_FILTER_IGNORE
	value_row.add_child(_vote_months)


func _rule() -> Control:
	var rule := ColorRect.new()
	rule.color = UiTheme.EDGE
	rule.custom_minimum_size = Vector2(1, 0)
	rule.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rule


## hud.gd builds the clock cluster and hands it here, so main.gd keeps reaching it as
## `_hud.clock_cluster`.
func add_clock(cluster: Control) -> void:
	_clock_slot.add_child(cluster)
	cluster.size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(state, loader) -> void:
	_state = state
	_loader = loader
	# A new state is a new month and day: the title and the cells only redraw when
	# dirty, and a load that rebinds without marking left the discarded game's
	# month on screen beside the clock's (MAR 2026 over 20 APR 2026).
	_dirty = true


func mark_dirty() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if _state == null or not visible or _cells.size.x < 10.0:
		return
	# What the horizon shows changes when a request is answered or a decision made, not
	# only on the day tick main.gd marks it for: a cheap signature of the registers it
	# reads, compared each frame, keeps it from showing a lapse that was answered.
	var signature := _signature()
	if signature != _signature_seen:
		_signature_seen = signature
		_dirty = true
	if not _dirty:
		return
	_dirty = false
	_title.text = DateText.month_long(_state.month).to_upper()
	_items = Items.read(_state, _loader)
	_rebuild_chips()
	_refresh_vote()
	_cells.queue_redraw()
	# The month's name moves aside for today's mark rather than printing under it.
	var today_x := _day_x(int(_state.year), int(_state.month), int(_state.day))
	var x := 30.0
	if today_x > x - 16.0 and today_x < x + _title.get_minimum_size().x + 6.0:
		x = today_x + 18.0
	_title.position.x = x


## What the horizon reads, in a handful of integers: the day, the diary's size, the
## desk's, and the requests still waiting with their deadlines.
func _signature() -> Array:
	var ns = _state.player()
	if ns == null:
		return []
	var waiting := 0
	var deadlines := 0
	for row in ns.audience_requests:
		if String(row.get("status", "")) == AudienceK.STATUS_PENDING:
			waiting += 1
			deadlines += int(row.get("deadline_month", 0))
	var desk := 0
	for entry in ns.event_queue:
		desk += 1 + int(entry.get("months_left", 0))
	return [int(_state.year), int(_state.month), int(_state.day), _state.appointments.size(), waiting, deadlines, desk]


## --- geometry --------------------------------------------------------------

## The span of the line a month index (0 this month, 1, 2) takes, in `_cells` pixels.
func _segment(index: int) -> Vector2:
	var width := _cells.size.x
	var start := 0.0
	for i in index:
		start += width * SHARES[i]
	return Vector2(start, start + width * SHARES[index])


## The x of the middle of a day, which may fall in a later month. A date outside the
## three months has no x (-1).
func _day_x(year: int, month: int, day: int) -> float:
	var index := (year * 12 + month) - (int(_state.year) * 12 + int(_state.month))
	if index < 0 or index >= SHARES.size():
		return -1.0
	var span := _segment(index)
	var days := DateText.days_in(month, year)
	return span.x + (span.y - span.x) * (float(day) - 0.5) / float(days)


## The month `offset` after today's, as {year, month}.
func _month_at(offset: int) -> Dictionary:
	var index := int(_state.year) * 12 + int(_state.month) - 1 + offset
	return {"year": floori(index / 12.0), "month": index % 12 + 1}


## --- chips -----------------------------------------------------------------

func _rebuild_chips() -> void:
	for chip in _chips:
		chip.queue_free()
	_chips.clear()
	var wanted: Array[Dictionary] = []
	for b in (_items["bookings"] as Array):
		# A booking's chip sits on its meeting day; its travel days are only the hatch.
		var x := _day_x(int(b["year"]), int(b["month"]), int(b["day"]))
		if x >= 0.0:
			wanted.append({"x": x, "right": false, "text": Items.booking_text(b), "icon": "", "warn": false,
				"tip": "%s — %s" % [DateText.day_month(int(b["day"]), int(b["month"])), String(b["act"])]})
	for due in (_items["dues"] as Array):
		var month := (int(due["abs_month"]) - 1) % 12 + 1
		var year := floori((int(due["abs_month"]) - 1) / 12.0)
		var index := int(due["abs_month"]) - (int(_state.year) * 12 + int(_state.month))
		var span := _segment(index)
		wanted.append({"x": span.y - 4.0, "right": true, "text": Items.due_text(due),
			"icon": "res://assets/icons/material/%s.svg" % ("person" if due["kind"] == "request" else "mail"), "warn": true,
			"tip": tr("By %s") % DateText.day_month(DateText.days_in(month, year), month)})
	wanted.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
	var edge := -1.0e9
	var folded: Array[String] = []
	for want in wanted:
		var chip := _chip(want)
		_cells.add_child(chip)
		var width := chip.get_combined_minimum_size().x
		var left := float(want["x"]) - (width if bool(want["right"]) else 8.0)
		left = clampf(left, 0.0, maxf(_cells.size.x - width, 0.0))
		if left < edge + CHIP_GAP:
			folded.append(String(want["tip"]))
			chip.queue_free()
			continue
		chip.position = Vector2(left, LANE_Y)
		chip.size = Vector2(width, chip.get_combined_minimum_size().y)
		edge = left + width
		_chips.append(chip)
	if not folded.is_empty():
		var more := _chip({"text": "+%d" % folded.size(), "icon": "", "warn": false, "tip": "\n".join(folded)})
		_cells.add_child(more)
		more.position = Vector2(minf(edge + CHIP_GAP, _cells.size.x - 32.0), LANE_Y)
		more.size = more.get_combined_minimum_size()
		_chips.append(more)


## A plate with a glyph and one line; its words mark a person when one is the whole
## subject, so the name opens their card.
func _chip(want: Dictionary) -> Control:
	var chip := PanelContainer.new()
	chip.theme_type_variation = UiTheme.PLATE
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	# A chip that links a person has no tooltip of its own: an ancestor's tip would
	# draw over the person's card (term_text.gd's note).
	if not String(want["text"]).contains("[p="):
		chip.tooltip_text = String(want["tip"])
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(box)
	if String(want["icon"]) != "":
		var glyph := TextureRect.new()
		glyph.texture = Icon.load_icon(String(want["icon"]), UiTheme.WARN if bool(want["warn"]) else UiTheme.TEXT_DIM, ICON_PX)
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(glyph)
	var line := PanelKit.line(box, String(want["text"]), PanelKit.Tone.PLAIN)
	if line is RichTextLabel:
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.mouse_filter = Control.MOUSE_FILTER_PASS
	elif line is Label:
		line.autowrap_mode = TextServer.AUTOWRAP_OFF
		line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return chip


func _refresh_vote() -> void:
	var vote: Dictionary = _items["vote"]
	if vote.is_empty() or int(vote["months"]) < 0:
		_vote_box.hide()
		return
	_vote_box.show()
	_vote_value.text = Items.vote_text(vote)
	_vote_months.text = Strings.tn("%d month", "%d months", int(vote["months"])) % int(vote["months"]) \
		if int(vote["months"]) > 0 else Strings.t("this month")
	var lines: Array = StripReadings.read("election", _state, _loader)["lines"]
	var tip: Array[String] = []
	for entry in lines:
		tip.append(String(entry["text"]))
	_vote_box.tooltip_text = "\n".join(tip)


## --- drawing ----------------------------------------------------------------

func _draw_cells() -> void:
	if _state == null:
		return
	var font := _cells.get_theme_default_font()
	var font_size := _cells.get_theme_default_font_size()
	var width := _cells.size.x
	var today_x := _day_x(int(_state.year), int(_state.month), int(_state.day))
	# The line, dim behind today (what has gone), edge-coloured ahead.
	_cells.draw_rect(Rect2(0, LINE_Y, width, 2), UiTheme.EDGE)
	_cells.draw_rect(Rect2(0, LINE_Y, today_x, 2), UiTheme.TEXT_DIM)
	for i in SHARES.size():
		var span := _segment(i)
		if i > 0:
			_cells.draw_rect(Rect2(span.x, 0, 1, LINE_Y + font_size + 8), UiTheme.EDGE)
			var at := _month_at(i)
			_cells.draw_string(font, Vector2(span.x + 14, LINE_Y + 3 + font_size), DateText.month_long(int(at["month"])).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, UiTheme.TEXT_DIM)
	# Day numbers: the first of every week of this month, and today, a filled mark.
	var days := DateText.days_in(int(_state.month), int(_state.year))
	for d in [1, 8, 15, 22, 29]:
		if d > days or absi(d - int(_state.day)) <= 1:
			continue
		_draw_number(font, font_size, _day_x(int(_state.year), int(_state.month), d), str(d), UiTheme.TEXT_DIM)
	_cells.draw_rect(Rect2(today_x - 1.0, 0, 2, LINE_Y), UiTheme.accent())
	var mark := str(int(_state.day))
	var mark_w := font.get_string_size(mark, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2).x + 10.0
	_cells.draw_rect(Rect2(today_x - mark_w / 2.0, LINE_Y + 5, mark_w, font_size + 4), UiTheme.accent())
	_cells.draw_string(font, Vector2(today_x - mark_w / 2.0 + 5.0, LINE_Y + 3 + font_size), mark, HORIZONTAL_ALIGNMENT_LEFT, -1,
		font_size - 2, UiTheme.INK)
	# Bookings on the line: the meeting solid, its travel days hatched, as the diary draws them.
	for b in (_items.get("bookings", []) as Array):
		var meet := _day_x(int(b["year"]), int(b["month"]), int(b["day"]))
		if meet < 0.0:
			continue
		var cell := _cell_width(int(b["year"]), int(b["month"]))
		for leg in range(-int(b["travel_days"]), int(b["travel_days"]) + 1):
			var rect := Rect2(meet + leg * cell - cell / 2.0 + 2.0, LINE_Y - 2.0 - BLOCK_HEIGHT, maxf(cell - 4.0, 2.0), BLOCK_HEIGHT)
			if leg == 0:
				_cells.draw_rect(rect, UiTheme.TEXT)
			else:
				_hatch(rect)
	# The deadlines: a WARN tick on the line at the month's end.
	for due in (_items.get("dues", []) as Array):
		var index := int(due["abs_month"]) - (int(_state.year) * 12 + int(_state.month))
		_cells.draw_rect(Rect2(_segment(index).y - 4.0, LINE_Y - 9, 2, 20), UiTheme.WARN)


func _draw_number(font: Font, font_size: int, x: float, text: String, colour: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2).x
	_cells.draw_string(font, Vector2(x - w / 2.0, LINE_Y + 3 + font_size), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 2, colour)


## One day's width in its month's segment.
func _cell_width(year: int, month: int) -> float:
	var index := (year * 12 + month) - (int(_state.year) * 12 + int(_state.month))
	var span := _segment(clampi(index, 0, SHARES.size() - 1))
	return (span.y - span.x) / float(DateText.days_in(month, year))


## Travel is time the journey spends, not time the president chose: hatched, not
## filled. Drawn as lines because the cells only redraw when something moves.
func _hatch(rect: Rect2) -> void:
	_cells.draw_rect(rect, UiTheme.SLATE)
	var xx := rect.position.x - rect.size.y
	while xx < rect.position.x + rect.size.x:
		var x0: float = maxf(xx, rect.position.x)
		var x1: float = minf(xx + rect.size.y, rect.position.x + rect.size.x)
		_cells.draw_line(Vector2(x0, rect.position.y + (x0 - xx)), Vector2(x1, rect.position.y + (x1 - xx)), UiTheme.EDGE, 1.0)
		xx += 5.0


## The act a booking names, in words (the diary's tooltip words).
func _booking_name(entry: Dictionary) -> String:
	return Items.booking_name(entry, _loader)
