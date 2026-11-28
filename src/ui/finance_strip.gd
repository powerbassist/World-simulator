extends HBoxContainer

## The finance bill folded to ONE line -- G3 S4, Design's gate T1 on #443 (works-a-calendar.png). While the inbox shows
## beside the workspace, the bill's rail (finance_foot.gd) becomes a slim sheet under the header, the workspace's width:
## the bill's name, what it holds, the deficit before and after, the Assembly's verdict in words, then the rail's own
## date tag and verbs, docked here so there is one of each (a second "Table the bill" would be two buttons for one act).
## The table under it keeps the page's full width. Its chevron puts the inbox away, which shows the whole rail (R1, the
## parent's ruling on #443: one surface owns the screen, no rail over the page).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const ControlStyle = preload("res://src/ui/control_style.gd")

var _title: Label
var _line: Label
var _verdict: Label
## Where the rail's date tag and verbs sit while folded.
var _slot: HBoxContainer

signal unfold_pressed


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	_title = Label.new()
	_title.theme_type_variation = ControlStyle.STRONG
	_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_title)
	_line = Label.new()
	_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_line)
	_verdict = Label.new()
	_verdict.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_verdict.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_verdict.clip_text = true
	_verdict.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_verdict.mouse_filter = Control.MOUSE_FILTER_PASS  # a Label ignores the mouse, so its hover would never show
	add_child(_verdict)
	_slot = HBoxContainer.new()
	_slot.add_theme_constant_override("separation", 10)
	_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(_slot)
	var unfold := Button.new()
	unfold.name = "Unfold"  # i18n: ok a node name, found by tests
	unfold.text = "›"  # i18n: ok a glyph
	unfold.theme_type_variation = UiTheme.GHOST
	unfold.tooltip_text = tr("The whole bill: puts the inbox away")
	unfold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	unfold.pressed.connect(unfold_pressed.emit)
	add_child(unfold)


## The line: the bill's name, what it holds (`line`), and the verdict in its tone (`good` the good-news tone, `bad` the
## bad, neither the caption's; `warn`, amber, over `bad`: a refusal beside a verb that still queues). A vote's verdict
## carries its glyph, and a refusal's tone follows its verb, live or greyed, so the tone is never alone.
func say(title: String, line: String, verdict: String, good: bool, bad: bool, warn := false) -> void:
	_title.text = title
	_line.text = line
	_line.visible = line != ""
	_verdict.text = verdict
	_verdict.tooltip_text = verdict
	var toned := UiTheme.WARN_TEXT if warn else (UiTheme.BAD_SMALL if bad else UiTheme.CAPTION)
	_verdict.theme_type_variation = UiTheme.GOOD_SMALL if good else toned


## Moves `nodes` (the rail's date tag, its verbs one by one) into the line, in order: a flow container in a row wraps
## its buttons into a column, so the buttons come without it.
func dock(nodes: Array) -> void:
	for node in nodes:
		(node as Node).reparent(_slot, false)


func line_text() -> String:
	return _line.text


func verdict_text() -> String:
	return _verdict.text
