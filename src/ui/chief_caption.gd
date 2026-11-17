extends PanelContainer

## The chief's line as a caption under his mark -- G1, chief-briefing-brief.md 2: when
## he has something to say (the situation changed, or a line is new) the line drops
## under the mark for the length of it, over the running clock: no dim, no key, and
## the mouse goes through it to whatever it covers (below the figure strip since #418:
## the top of the map or the docked page, for a few seconds).
## voice.gd requires the line on screen while it is said; this is where it is. A line
## queued behind a messenger starts after this caption's timer: ChiefMarkView puts it back.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const TitleBar = preload("res://src/ui/title_bar.gd")
const TopBar = preload("res://src/ui/top_bar.gd")

## Reading time when no clip says how long the line is (voices off, a language the
## clip was not voiced in): a speaking pace, held between a floor and a ceiling.
const SECONDS_PER_CHAR := 0.07
const MIN_SECONDS := 4.0
const MAX_SECONDS := 12.0
const WIDTH_PX := 560
const GAP_PX := 6

var _line: Label
var _timer: Timer


func _ready() -> void:
	theme_type_variation = UiTheme.PLATE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line = Label.new()
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_line)
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide)
	add_child(_timer)
	hide()


## Shows `line` under `anchor` (the mark), right edges aligned, for `seconds` (<= 0:
## the reading time of the line).
func say(line: String, anchor: Control, seconds := 0.0) -> void:
	if line.is_empty():
		hide()
		return
	_line.text = line
	var width := WIDTH_PX * UiTheme.text_scale()
	# An autowrapped Label measures its height at its CURRENT width: at 0 it wraps every
	# character and the plate ran down the screen (the first windowed frame did). So the
	# label gets its width before the plate is measured, and is measured again once laid out.
	var box := get_theme_stylebox("panel")
	var inner := width - (box.get_minimum_size().x if box != null else 0.0)
	_line.custom_minimum_size.x = inner
	_line.size = Vector2(inner, 0)
	custom_minimum_size.x = width
	_settle(anchor)
	# The mark was just filled and is laid out at the end of the frame: settle again then.
	_settle.call_deferred(anchor)
	show()
	_timer.start(seconds if seconds > 0.0 else reading_seconds(line))


func _settle(anchor: Control) -> void:
	size = Vector2(custom_minimum_size.x, 0)
	reset_size()
	_place(anchor)


## Under the figure strip, not over it (#418 pass 2): the strip's tiles grew rightward with
## top bar A, and a line dropped from the mark covered the unrest and majority tiles.
func _place(anchor: Control) -> void:
	var rect := anchor.get_global_rect()
	var top := maxf(rect.end.y, TitleBar.HEIGHT + TopBar.BAR_HEIGHT)
	global_position = Vector2(maxf(0.0, rect.end.x - size.x), top + GAP_PX)


func text() -> String:
	return _line.text if visible else ""


func clear() -> void:
	_timer.stop()
	hide()


static func reading_seconds(line: String) -> float:
	return clampf(line.length() * SECONDS_PER_CHAR, MIN_SECONDS, MAX_SECONDS)
