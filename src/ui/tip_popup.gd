extends Control

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")

## V4.8b. The strip's two-level tooltip. Godot's own tooltip cannot be hovered
## into -- it closes the moment the pointer leaves the control that asked for it --
## so a line that opens a second level needs a popup the pointer can travel
## through. Level 1 hangs under the figure; a level-1 line that carries a child_id
## opens level 2 beside it, flush, so the pointer crosses no gap on the way.
##
## Dismissal is one rule, stays_open(): the pointer is on the figure, on level 1 or
## on level 2. Off all three for GRACE_S and both close. The grace exists for the
## diagonal move (figure corner to popup corner) where the pointer is briefly on
## none of them. OPEN_DELAY_S is the dwell before level 1 appears, so sweeping the
## pointer along the strip does not strobe a popup per figure. Both are felt
## numbers with no simulation meaning, which is why they sit here and not in a
## *_constants.gd.
##
## The popup knows no reading. It is handed `lines` ({text, child_id}) and a
## Callable that answers a child_id with {title, lines}; the host (top_bar.gd)
## supplies StripChildren.child. Nothing here reads GameState.
##
## Driven through figure_entered / line_entered / popup_entered and tick() so a
## headless test can walk the same state machine the real mouse signals do.

const OPEN_DELAY_S := 0.3
const GRACE_S := 0.2
const L1_WIDTH := 340.0
const L2_WIDTH := 300.0
const EDGE := 8.0
## A level-1 line that opens something says so; the glyph is the affordance.
const CHILD_MARK := " ▸"

var level1_visible := false
var level2_visible := false
var open_child_id := ""
var figure_key := ""

var _lines: Array = []
var _provider := Callable()
var _figure: Control
var _over_figure := false
var _over_l1 := false
var _over_l2 := false
var _hover_line := -1
var _open_left := -1.0
var _grace_left := 0.0
var _l1: PanelContainer
var _l1_body: VBoxContainer
var _l1_labels: Array[Label] = []
var _l2: PanelContainer
var _l2_body: VBoxContainer
## Frames left to re-fit the panels. A wrapping Label reports its minimum height
## for the width it had BEFORE the panel was laid out (one word a line), so a
## panel sized on the frame it was built is several times too tall -- the first
## windowed capture showed a 600 px popup around three lines. Re-fitting after the
## layout pass has given the labels their width fixes it; two frames, because the
## label's own height settles one pass after its width does.
var _refit := 0


## The single dismissal rule, static so the test can state it without a scene.
static func stays_open(over_figure: bool, over_l1: bool, over_l2: bool) -> bool:
	return over_figure or over_l1 or over_l2


func _ready() -> void:
	# Out of the bar's container layout and above every window frame.
	top_level = true
	z_index = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_l1 = _make_panel(L1_WIDTH, 1)
	_l1_body = _l1.get_child(0)
	_l2 = _make_panel(L2_WIDTH, 2)
	_l2_body = _l2.get_child(0)
	set_process(false)


func _make_panel(width: float, level: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = UiTheme.PLATE
	panel.custom_minimum_size = Vector2(width, 0)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_entered.connect(popup_entered.bind(level))
	panel.mouse_exited.connect(popup_exited.bind(level))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	panel.add_child(body)
	add_child(panel)
	return panel


func _process(delta: float) -> void:
	tick(delta)
	if _refit > 0:
		_refit -= 1
		_fit()


# -- Events -------------------------------------------------------------------

func figure_entered(key: String, figure: Control, lines: Array, provider: Callable) -> void:
	_over_figure = true
	_figure = figure
	_lines = lines
	_provider = provider
	if level1_visible and key == figure_key:
		return
	var switching := level1_visible
	figure_key = key
	if switching:
		# Pointer moved figure to figure with a popup already up: swap at once, a
		# dwell between neighbours would make the strip feel dead.
		_show_level1()
	else:
		_open_left = OPEN_DELAY_S
		set_process(true)


func figure_exited(key: String) -> void:
	if key != figure_key and level1_visible:
		return  # the exit of the figure we just left, after the next one's entry
	_over_figure = false
	if not level1_visible:
		_open_left = -1.0


func popup_entered(level: int) -> void:
	if level == 1:
		_over_l1 = true
	else:
		_over_l2 = true


func popup_exited(level: int) -> void:
	if level == 1:
		_over_l1 = false
	else:
		_over_l2 = false


## The pointer reached level-1 line `index`: open its child, or close level 2 when
## the line has none.
func line_entered(index: int) -> void:
	if index < 0 or index >= _lines.size():
		return
	_hover_line = index
	var child_id := String(_lines[index]["child_id"])
	if child_id.is_empty():
		_hide_level2()
		return
	if level2_visible and child_id == open_child_id:
		return
	var child: Dictionary = _provider.call(child_id) if _provider.is_valid() else {}
	if child.is_empty():
		_hide_level2()
		return
	open_child_id = child_id
	_show_level2(child, index)


func tick(delta: float) -> void:
	if _open_left >= 0.0 and _over_figure and not level1_visible:
		_open_left -= delta
		if _open_left <= 0.0:
			_open_left = -1.0
			_show_level1()
	if not level1_visible:
		if _open_left < 0.0:
			set_process(false)
		return
	if stays_open(_over_figure, _over_l1, _over_l2):
		_grace_left = GRACE_S
		return
	_grace_left -= delta
	if _grace_left <= 0.0:
		hide_all()


func hide_all() -> void:
	level1_visible = false
	_hide_level2()
	if _l1 != null:
		_l1.visible = false
	_over_figure = false
	_over_l1 = false
	_over_l2 = false
	_hover_line = -1
	_open_left = -1.0
	figure_key = ""
	set_process(false)


## Fresh text for the figure the popup is already showing, rewritten in place
## when the shape is unchanged. Rebuilding the rows under a stationary pointer
## would fire exit/enter pairs and flicker the child open and shut every day.
func update_lines(key: String, lines: Array) -> void:
	if not level1_visible or key != figure_key:
		return
	var same := lines.size() == _lines.size()
	if same:
		for i in lines.size():
			if String(lines[i]["child_id"]) != String(_lines[i]["child_id"]):
				same = false
				break
	_lines = lines
	if same:
		for i in lines.size():
			_l1_labels[i].text = _line_text(lines[i])
	else:
		_build_level1()


# -- Drawing ------------------------------------------------------------------

func _line_text(line: Dictionary) -> String:
	var text := String(line["text"])
	return text + CHILD_MARK if not String(line["child_id"]).is_empty() else text


func _show_level1() -> void:
	_build_level1()
	_l1.visible = true
	level1_visible = true
	_grace_left = GRACE_S
	_place_level1()
	_refit = 2
	set_process(true)


func _build_level1() -> void:
	_clear(_l1_body)
	_l1_labels.clear()
	for i in _lines.size():
		var line: Dictionary = _lines[i]
		var has_child := not String(line["child_id"]).is_empty()
		# A line that opens something is plain (bright), one that does not is dim --
		# the affordance a ▸ alone would leave to the glyph.
		var label := PanelKit.plain_line(_l1_body, _line_text(line), PanelKit.Tone.PLAIN if has_child else PanelKit.Tone.DIM)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
		label.mouse_entered.connect(line_entered.bind(i))
		_l1_labels.append(label)
	_l1.reset_size()


func _show_level2(child: Dictionary, index: int) -> void:
	_clear(_l2_body)
	PanelKit.heading(_l2_body, String(child["title"]))
	for text in (child["lines"] as Array):
		var label := PanelKit.plain_line(_l2_body, String(text), PanelKit.Tone.PLAIN)
		label.mouse_filter = Control.MOUSE_FILTER_PASS
	_l2.reset_size()
	_l2.visible = true
	level2_visible = true
	_place_level2(index)
	_refit = 2


func _hide_level2() -> void:
	level2_visible = false
	open_child_id = ""
	_over_l2 = false
	if _l2 != null:
		_l2.visible = false


func _fit() -> void:
	if level1_visible:
		_l1.reset_size()
		_place_level1()
	if level2_visible:
		_l2.reset_size()
		var index := _hover_line if _hover_line >= 0 else 0
		_place_level2(index)


func _clear(box: Control) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()


func _viewport_size() -> Vector2:
	return get_viewport_rect().size


func _place_level1() -> void:
	var size_now := _l1.get_combined_minimum_size()
	var x := _figure.global_position.x if _figure != null else EDGE
	var y := (_figure.global_position.y + _figure.size.y + 2.0) if _figure != null else EDGE
	x = clampf(x, EDGE, maxf(EDGE, _viewport_size().x - size_now.x - EDGE))
	_l1.position = Vector2(x, y)


## Beside level 1 and flush with it, top aligned with the line that opened it;
## flipped to the left when it would leave the screen.
func _place_level2(index: int) -> void:
	var size_now := _l2.get_combined_minimum_size()
	var line_top := _l1_labels[index].global_position.y if index < _l1_labels.size() else _l1.position.y
	var x := _l1.position.x + _l1.get_combined_minimum_size().x
	if x + size_now.x > _viewport_size().x - EDGE:
		x = _l1.position.x - size_now.x
	var y := minf(line_top, _viewport_size().y - size_now.y - EDGE)
	_l2.position = Vector2(maxf(x, EDGE), maxf(y, EDGE))
