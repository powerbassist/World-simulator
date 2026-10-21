extends PanelContainer

## The day ribbon, V2.4a — a few committed blocks on an otherwise open line.
##
## docs/tiers/v2.md section 4's own call: "a ribbon, not a grid", because thirty
## equal boxes is the template answer and a president's month is not one. One
## row of days, travel days HATCHED and the meeting itself solid brass — travel
## is time you spend without choosing it, and the two marks say so without a
## word. Not a drawer entry and not a window (V2.1c settled that when it placed
## this surface): it is furniture, the bottom-most plate, always on.
##
## Read-only over sim state like every surface since U2: Calendar.day_cells()
## is the whole rule about blocks, drawn here without re-derivation, so the
## ribbon and the diary cannot disagree about what occupies a day. The tooltip
## names the act from the register by verb_key; the diary prints the richer
## sentence, and the two share no figure that could round apart.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const ClockCluster = preload("res://src/ui/clock_cluster.gd")

## Cell and strip geometry. The strip is 44px: enough for a day number over a
## 12px block, small enough to sit under the action bar without becoming a
## second panel.
const STRIP_HEIGHT := 44
const BLOCK_HEIGHT := 12.0
const MEETING_HEIGHT := 15.0
const LABEL_WIDTH := 130.0

var _state
var _loader
var _cells: Control
var _title: Label
var _dirty := true
var _hover_day := -1


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	custom_minimum_size = Vector2(0, STRIP_HEIGHT)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	add_child(row)

	_title = Label.new()
	_title.theme_type_variation = UiTheme.MICRO
	_title.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title)

	_cells = Control.new()
	_cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_cells.mouse_filter = Control.MOUSE_FILTER_PASS
	_cells.draw.connect(_draw_cells)
	_cells.gui_input.connect(_on_cells_input)
	row.add_child(_cells)


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
	if not _dirty or _state == null or not visible:
		return
	_dirty = false
	_title.text = ("%s %d" % [
		tr(ClockCluster.MONTH_NAMES[_state.month - 1]), _state.year,
	]).to_upper()
	_cells.queue_redraw()


## --- drawing ----------------------------------------------------------------

func _draw_cells() -> void:
	if _state == null:
		return
	var cells: Array = Calendar.day_cells(_state, _state.year, _state.month)
	if cells.is_empty():
		return

	var font := _cells.get_theme_default_font()
	var font_size := _cells.get_theme_default_font_size()
	var area: Vector2 = _cells.size
	var cell_w := area.x / cells.size()
	var today := int(_state.day)

	for i in cells.size():
		var cell: Dictionary = cells[i]
		var day := int(cell["day"])
		var x := i * cell_w
		var is_today := day == today
		var is_past := day < today

		# The open line: a baseline with a small tick per day, dimmer behind
		# today. A month with nothing booked reads as exactly that, which is
		# information — the whole argument for a ribbon over a grid.
		var tick := UiTheme.EDGE
		if is_past:
			tick = Color(UiTheme.EDGE, 0.4)
		_cells.draw_rect(
			Rect2(x + cell_w * 0.5 - 1.0, area.y - 6.0, 2.0, 4.0), tick
		)

		var number_color := UiTheme.TEXT_DIM if not is_past else Color(UiTheme.TEXT_DIM, 0.45)
		if is_today:
			number_color = UiTheme.accent()
		_cells.draw_string(
			font, Vector2(x + cell_w * 0.5 - 8.0, area.y - 12.0), "%02d" % day,
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size - 1, number_color
		)

		if bool(cell["meeting"]):
			# Solid brass, the one accent: the meeting is the day you chose.
			# Slightly taller than a travel cell so a block reads as travelling
			# TOWARD something even where the two touch.
			var h := MEETING_HEIGHT
			_cells.draw_rect(
				Rect2(x + 2.0, area.y - 10.0 - h, cell_w - 4.0, h), UiTheme.accent()
			)
		elif bool(cell["travel"]):
			# Hatched, not filled: travel is time the journey spends, not time
			# the president chose. The hatch is drawn as lines rather than a
			# stylebox pattern because 31 cells redraw only when the day moves.
			var rect := Rect2(x + 2.0, area.y - 10.0 - BLOCK_HEIGHT, cell_w - 4.0, BLOCK_HEIGHT)
			_cells.draw_rect(rect, UiTheme.SLATE)
			var step := 5.0
			var yy := rect.position.y
			var y_end := rect.position.y + rect.size.y
			var xx := rect.position.x - rect.size.y
			while xx < rect.position.x + rect.size.x:
				var x0: float = maxf(xx, rect.position.x)
				var y0: float = yy + (x0 - xx)
				var x1: float = minf(xx + rect.size.y, rect.position.x + rect.size.x)
				var y1: float = yy + (x1 - xx)
				if y1 > y_end:
					x1 -= y1 - y_end
					y1 = y_end
				_cells.draw_line(
					Vector2(x0, y0), Vector2(x1, y1), UiTheme.EDGE, 1.0
				)
				xx += step

		if is_today:
			# Today's underline, brass, across the whole cell — the mark says
			# where on the line the president is standing.
			_cells.draw_rect(
				Rect2(x + 2.0, area.y - 4.0, cell_w - 4.0, 2.0), UiTheme.accent()
			)
		elif _hover_day == day and String(cell["key"]) != "":
			_cells.draw_rect(
				Rect2(x + 2.0, area.y - 10.0 - MEETING_HEIGHT, cell_w - 4.0, MEETING_HEIGHT + 8.0),
				Color(UiTheme.SLATE, 0.5)
			)


## --- hover ------------------------------------------------------------------

## The tooltip names the booking under the pointer. Resolved from the register
## by verb_key — the same identity the diary cancels by — so the ribbon cannot
## invent an act the diary does not know about. Names only; the diary owns the
## fuller sentence, and no figure is printed in both places.
func _on_cells_input(event: InputEvent) -> void:
	if _state == null:
		return
	if event is InputEventMouseMotion:
		var cells: Array = Calendar.day_cells(_state, _state.year, _state.month)
		if cells.is_empty():
			return
		var cell_w := _cells.size.x / cells.size()
		var idx := int(clampf(event.position.x / cell_w, 0, cells.size() - 1))
		var cell: Dictionary = cells[idx]
		if int(cell["day"]) == _hover_day:
			return
		_hover_day = int(cell["day"])
		_cells.queue_redraw()
		var key := String(cell["key"])
		if key.is_empty():
			_cells.tooltip_text = ""
			return
		for e in _state.appointments:
			if Calendar.verb_key(e) == key:
				_cells.tooltip_text = "%02d %s — %s" % [
					int(e.get("day", 1)),
					tr(ClockCluster.MONTH_NAMES[int(e.get("month", 1)) - 1]),
					_booking_name(e),
				]
				return
		_cells.tooltip_text = ""


func _booking_name(entry: Dictionary) -> String:
	match String(entry.get("kind", "")):
		"diplomatic":
			var action_name := String(entry.get("action_id", ""))
			var nation = _loader.nations.get(String(entry.get("target_id", "")))
			if nation != null:
				for action in _loader.diplomatic_actions:
					if String(action.id) == String(entry.get("action_id", "")):
						action_name = String(action.action_name)
						break
				return "%s — %s" % [action_name, String(nation.nation_name)]
			return action_name
		"law":
			return "A law is proposed"
		"reshuffle":
			return "A portfolio changes hands"
	return String(entry.get("kind", ""))
