extends SceneTree

## Headless test: godot --headless --script res://tests/test_scroll_gap.gd
## Non-zero exit on any failure.
##
## The author, 2026-11-15: "sliders in some panels are too close from the text", then "scroll bar": a scrolled
## panel's text sat flush against its vertical scroll bar. ScrollContainer's scrollbar_v_separation does nothing in
## 4.7.2, so the gap is part of the theme's bars (ScrollBars.SCROLL_GAP_PX): one place, every panel. Pinned: the
## vertical bar is that much wider than its drawn width, the content a ScrollContainer gives its child is that much
## narrower than with a bare bar, the horizontal bar has the same gap above it, and the gap is not zero.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const ScrollBars = preload("res://src/ui/scroll_bars.gd")

var _failures: Array[String] = []
var _frame := 0
var _vertical: ScrollContainer
var _tall: Control


func _init() -> void:
	var theme := UiTheme.build()
	_vertical = _scroller(theme, Vector2(10, 1000), ScrollContainer.SCROLL_MODE_DISABLED)
	_vertical.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tall = _vertical.get_child(0)


func _scroller(theme: Theme, content: Vector2, _unused: int) -> ScrollContainer:
	var scroller := ScrollContainer.new()
	scroller.theme = theme
	scroller.size = Vector2(300, 200)
	var child := Control.new()
	child.custom_minimum_size = content
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	child.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroller.add_child(child)
	root.add_child(scroller)
	return scroller


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 4:
		if ScrollBars.SCROLL_GAP_PX < 4.0:
			_fail("the scroll gap is %s px: the text is back against the bar" % ScrollBars.SCROLL_GAP_PX)
		# The gap is drawn as nothing, not as a fatter bar: the track and the grabber sit back inside their old width.
		var theme := UiTheme.build()
		for part in ["scroll", "grabber", "grabber_highlight", "grabber_pressed"]:
			var box := theme.get_stylebox(part, "VScrollBar") as StyleBoxFlat
			if box == null or not is_equal_approx(box.expand_margin_left, -ScrollBars.SCROLL_GAP_PX):
				_fail("the vertical bar's '%s' is not drawn back inside its gap" % part)
		var bar := _vertical.get_v_scroll_bar()
		var want := ScrollBars.BAR_WIDTH_PX + ScrollBars.SCROLL_GAP_PX
		if absf(bar.get_combined_minimum_size().x - want) > 0.5:
			_fail("the vertical bar is %s px wide, the drawn bar plus its gap is %s" % [bar.get_combined_minimum_size().x, want])
		if absf(_tall.size.x - (300.0 - want)) > 0.5:
			_fail("the text column is %s px wide beside the bar, %s with the gap" % [_tall.size.x, 300.0 - want])
		_finish()
	return false


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: %s" % message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_scroll_gap: all checks passed")
		quit(0)
	else:
		print("test_scroll_gap: %d failure(s)" % _failures.size())
		quit(1)
