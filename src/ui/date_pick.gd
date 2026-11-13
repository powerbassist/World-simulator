extends Button

## A date field that opens on DAYS -- the audience's Counter (V5.3, H2). The old picker was a
## menu of months ("a year out" its default); this is the field itself, written as the clock
## writes a date ("Fri 16/04/2027"), and a month grid under it with the weekday over each
## column. The choice lives in `date` and is only ever changed by a click on a day, so a redraw
## of the card around it (H3: no choice resets on a press) leaves it where it was.
##
## The grid is a Popup window with a themed plate in it, not a PopupMenu: a menu cannot hold a
## grid. The window opens on the field and closes on any click outside.

signal picked(date: Dictionary)
signal opened
signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")
const DateText = preload("res://src/ui/date_text.gd")
const Strings = preload("res://src/ui/strings.gd")
const Icon = preload("res://src/ui/icon.gd")
const ICON := "res://assets/icons/material/calendar_month.svg"

## {year, month, day}: what the field shows and what Counter sends.
var date := {}
var _first := 0
var _last := 0
## The absolute month the grid shows.
var _shown := 0
var _popup: Popup
var _title: Label
var _grid: GridContainer
var _back: Button
var _forward: Button


func _ready() -> void:
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	icon = Icon.load_icon(ICON, UiTheme.TEXT, 18)
	pressed.connect(_open)
	_popup = Popup.new()
	_popup.popup_hide.connect(func() -> void: closed.emit())
	add_child(_popup)
	var plate := PanelContainer.new()
	plate.theme_type_variation = UiTheme.PLATE
	_popup.add_child(plate)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	plate.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_back = Button.new()
	_back.text = "◀"  # i18n: ok a glyph
	_back.pressed.connect(func() -> void: _show(_shown - 1))
	head.add_child(_back)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(_title)
	_forward = Button.new()
	_forward.text = "▶"  # i18n: ok a glyph
	_forward.pressed.connect(func() -> void: _show(_shown + 1))
	head.add_child(_forward)
	_grid = GridContainer.new()
	_grid.columns = 7
	box.add_child(_grid)


## The months the field may reach (absolute, inclusive) and where it stands: `current` {} takes
## the first day of the earliest month.
func setup(earliest: int, latest: int, current: Dictionary) -> void:
	_first = earliest
	_last = maxi(earliest, latest)
	date = current if not current.is_empty() else {"year": _year_of(earliest), "month": _month_of(earliest), "day": 1}
	_refresh()


## The month a day belongs to, as an absolute month.
func absolute_month() -> int:
	return int(date["year"]) * 12 + int(date["month"])


## One day chosen: what a click on its cell does.
func choose(day: int, absolute: int) -> void:
	date = {"year": _year_of(absolute), "month": _month_of(absolute), "day": day}
	_refresh()
	_popup.hide()
	picked.emit(date)


func _open() -> void:
	_show(absolute_month())
	_popup.popup(Rect2i(Vector2i(get_screen_position()) + Vector2i(0, int(size.y)), Vector2i.ZERO))
	opened.emit()


func _show(absolute: int) -> void:
	_shown = clampi(absolute, _first, _last)
	_back.disabled = _shown <= _first
	_forward.disabled = _shown >= _last
	_title.text = "%s %d" % [DateText.month_long(_month_of(_shown)), _year_of(_shown)]
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	var year := _year_of(_shown)
	var month := _month_of(_shown)
	# Monday first: the engine's weekday is 0 for Sunday (diary_grid.gd's rule).
	for d in range(1, 8):
		var heading := Label.new()
		heading.theme_type_variation = UiTheme.CAPTION
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		heading.text = Strings.t(DateText.WEEKDAYS[d % 7])  # i18n: row-ok a weekday msgid
		_grid.add_child(heading)
	var lead := (DateText.weekday_index(1, month, year) + 6) % 7
	for i in lead:
		_grid.add_child(Control.new())
	for day in range(1, _days_in(month, year) + 1):
		var cell := Button.new()
		cell.text = str(day)
		cell.custom_minimum_size = Vector2(38, 0)
		cell.name = "Day%d" % day  # i18n: ok a node name, found by tests
		cell.pressed.connect(choose.bind(day, _shown))
		if int(date["year"]) == year and int(date["month"]) == month and int(date["day"]) == day:
			cell.toggle_mode = true
			cell.button_pressed = true
		_grid.add_child(cell)


func _refresh() -> void:
	text = DateText.weekday_full(int(date["day"]), int(date["month"]), int(date["year"]))


static func _year_of(absolute: int) -> int:
	return floori((absolute - 1) / 12.0)


static func _month_of(absolute: int) -> int:
	return absolute - _year_of(absolute) * 12


static func _days_in(month: int, year: int) -> int:
	var next := Time.get_unix_time_from_datetime_dict({"year": year + (1 if month == 12 else 0), "month": 1 if month == 12 else month + 1, "day": 1, "hour": 0, "minute": 0, "second": 0})
	return int(Time.get_datetime_dict_from_unix_time(next - 86400)["day"])
