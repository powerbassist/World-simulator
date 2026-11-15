extends SceneTree

## Headless test: godot --headless --script res://tests/test_scroll_gap.gd
## Non-zero exit on any failure.
##
## The author, 2026-11-15: "sliders in some panels are too close from the text", then "scroll bar": a scrolled
## panel's text sat flush against its vertical scroll bar. In Godot 4.7 the space between a ScrollContainer's
## VERTICAL bar and its content is `scrollbar_h_separation` (the horizontal bar's is `scrollbar_v_separation`), set
## once in the theme (ScrollBars.SCROLL_GAP_PX): one place, every panel. QA's TAKE on #366: the first version set
## the wrong constant and the bar's own boxes carried the gap, which widened the bar's input area.
##
## Pinned THROUGH THE LAYOUT, not through the constant: the content a themed ScrollContainer gives its child is
## exactly the gap narrower than the same container with the constant at 0, the vertical bar stays where it was, the
## bar's own width is untouched, and the gap is not zero. Setting SCROLL_GAP_PX to 0 therefore fails the width check.
## The engine's own limit is pinned too: a child whose minimum width is wider than the container gets no gap.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const ScrollBars = preload("res://src/ui/scroll_bars.gd")

const VIEW := Vector2(300, 200)
## What a gap must be at least, whatever the constant says: the layout check cannot pass by both sides being 0.
const MIN_GAP := 4.0

var _failures: Array[String] = []
var _frame := 0
var _themed: ScrollContainer
var _bare: ScrollContainer
var _wide: ScrollContainer


func _init() -> void:
	var theme := UiTheme.build()
	var bare := UiTheme.build()
	bare.set_constant("scrollbar_h_separation", "ScrollContainer", 0)
	_themed = _scroller(theme, Vector2(10, 1000))
	_bare = _scroller(bare, Vector2(10, 1000))
	# A child with a minimum width wider than the view: the engine adds no gap there (4.7 docs, scrollbar_h_separation).
	_wide = _scroller(theme, Vector2(900, 1000))
	_wide.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


func _scroller(theme: Theme, content: Vector2) -> ScrollContainer:
	var scroller := ScrollContainer.new()
	scroller.theme = theme
	scroller.size = VIEW
	var child := Control.new()
	child.custom_minimum_size = content
	child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroller.add_child(child)
	root.add_child(scroller)
	return scroller


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 4:
		if ScrollBars.SCROLL_GAP_PX < 4.0:
			_fail("the scroll gap is %s px: the text is back against the bar" % ScrollBars.SCROLL_GAP_PX)
		var themed_child: Control = _themed.get_child(0)
		var bare_child: Control = _bare.get_child(0)
		var narrower := bare_child.size.x - themed_child.size.x
		if narrower < MIN_GAP or absf(narrower - ScrollBars.SCROLL_GAP_PX) > 0.5:
			_fail("the content is %s px narrower than with no gap, the gap is %s" % [narrower, ScrollBars.SCROLL_GAP_PX])
		var themed_bar := _themed.get_v_scroll_bar()
		var bare_bar := _bare.get_v_scroll_bar()
		if absf(themed_bar.position.x - bare_bar.position.x) > 0.5:
			_fail("the gap moved the vertical bar from x=%s to x=%s" % [bare_bar.position.x, themed_bar.position.x])
		if absf(themed_bar.get_combined_minimum_size().x - ScrollBars.BAR_WIDTH_PX) > 0.5:
			_fail("the vertical bar is %s px wide, it is drawn %s" % [themed_bar.get_combined_minimum_size().x, ScrollBars.BAR_WIDTH_PX])
		if absf(_wide.get_child(0).size.x - _wide.get_child(0).get_combined_minimum_size().x) > 0.5:
			_fail("a child wider than its view was given a gap anyway")
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
