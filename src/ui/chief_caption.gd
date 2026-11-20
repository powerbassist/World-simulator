extends PanelContainer

## The chief's line as a caption in the top bar -- G1, chief-briefing-brief.md 2, and since
## top bar A (the author's pick, redone at #422 pass 2) a CHILD OF THE BAR'S OWN ROW, in the
## slot between the tiles and the chips: when he has something to say (the situation
## changed, or a line is new) it shows for the length of it, and hides when he is silent so
## the tiles get the room back. The row lays it out -- on a refit, F11, a window or theme
## change -- so nothing here measures or places it; it needs only a minimum width.
## voice.gd requires the line on screen while it is said; this is where it is. A line too
## long for two lines is cut with an ellipsis and whole in the tooltip. A line queued behind
## a messenger starts after this caption's timer: ChiefMarkView puts it back.

const UiTheme = preload("res://src/ui/ui_theme.gd")

## Reading time when no clip says how long the line is (voices off, a language the
## clip was not voiced in): a speaking pace, held between a floor and a ceiling.
const SECONDS_PER_CHAR := 0.07
const MIN_SECONDS := 4.0
const MAX_SECONDS := 12.0
const MAX_LINES := 2
const MIN_WIDTH_PX := 240

var _line: Label
var _timer: Timer


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	mouse_filter = Control.MOUSE_FILTER_PASS  # the tooltip carries the whole line
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.max_lines_visible = MAX_LINES
	_line.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_line)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide)
	add_child(_timer)
	custom_minimum_size.x = min_width()
	hide()


## Shows `line` for `seconds` (<= 0: the reading time of the line). `_anchor` is the chief's
## mark, which the caption used to hang under and no longer needs: kept so the callers stay.
func say(line: String, _anchor: Control = null, seconds := 0.0) -> void:
	if line.is_empty():
		hide()
		return
	_line.text = line
	show()
	_timer.start(seconds if seconds > 0.0 else reading_seconds(line))


## The room the row keeps for it while it shows (the tiles fold to leave it): the wrap
## starts at this width, so it never asks for more.
func min_width() -> float:
	return MIN_WIDTH_PX * UiTheme.text_scale()


func text() -> String:
	return _line.text if visible else ""


func clear() -> void:
	_timer.stop()
	hide()


## The whole line as a tooltip only when the two lines cut it: a line shown whole would
## repeat itself. Read when the tooltip is asked for, not stored: a text-size change can
## re-wrap the line without moving the label's size, and a stored tooltip would go stale.
func _get_tooltip(_at: Vector2) -> String:
	return _line.text if _line.get_line_count() > MAX_LINES else ""


## A new theme -- the text size changed -- moves the minimum width with it.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _line != null:
		custom_minimum_size.x = min_width()


static func reading_seconds(line: String) -> float:
	return clampf(line.length() * SECONDS_PER_CHAR, MIN_SECONDS, MAX_SECONDS)
