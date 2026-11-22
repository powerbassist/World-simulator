extends Control

## Design's T16 on #441: a page that lays out its own sheets (window_manager.gd OWN_SHEETS) keeps them
## on the header sheet's edges whether or not it scrolls. A ScrollContainer reserves its bar's width
## (and the theme's separation) out of its content, so a scrolling page's right-hand sheets ended
## 18 px in. Every scroll that holds sheets -- no sheet between it and its page -- hides its own bar
## (SCROLL_MODE_SHOW_NEVER: still scrolls, takes no width), and a thin bar of this layer stands in the
## gap at the scroll's right, sharing its range (Range.share). A scroll inside a sheet keeps its own
## bar: it moves no sheet's edge.
##
## The window manager's last child, full rect, mouse-transparent; each bar takes the pointer itself.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const ScrollBars = preload("res://src/ui/scroll_bars.gd")

## On a gap bar: the scroll it moves.
const META := "gap_bar_for"

var _bars := {}  # ScrollContainer -> VScrollBar


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Takes over the bars of `page`'s sheet-holding scrolls; a scroll already taken is left as it is.
func adopt(page: Control) -> void:
	for node in page.find_children("*", "ScrollContainer", true, false):
		var scroll := node as ScrollContainer
		if _bars.has(scroll) or scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED or _in_sheet(scroll, page):
			continue
		scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
		var bar := VScrollBar.new()
		bar.theme_type_variation = ScrollBars.GAP_BAR
		bar.set_meta(META, scroll)
		bar.hide()
		add_child(bar)
		var inner := scroll.get_v_scroll_bar()
		# share() links later changes, not the values already set: a scroll adopted after its last
		# layout would leave this bar at the Range defaults (0 to 100, page 0) until the next one.
		bar.min_value = inner.min_value
		bar.max_value = inner.max_value
		bar.page = inner.page
		bar.value = inner.value
		bar.share(inner)
		_bars[scroll] = bar


## The gap bar standing for `scroll`, or null (a test's reader; `windows` is the window manager).
static func bar_for(windows: Node, scroll: ScrollContainer) -> VScrollBar:
	for node in windows.find_children("*", "VScrollBar", true, false):
		if node.has_meta(META) and node.get_meta(META) == scroll:
			return node as VScrollBar
	return null


## Whether `scroll` has more than it shows. A reader that asked its own bar's `visible` goes silent on
## a page whose bar stands in the gap (SHOW_NEVER hides it); the range is the same in both.
static func scrolls(scroll: ScrollContainer) -> bool:
	var bar := scroll.get_v_scroll_bar()
	return bar.max_value - bar.page > 0.5


static func _in_sheet(scroll: Node, page: Node) -> bool:
	var up := scroll.get_parent()
	while up != null and up != page:
		if up is Control and (up as Control).theme_type_variation == UiTheme.PLATE:
			return true
		up = up.get_parent()
	return false


## Placed every frame, like the dock it follows (window_manager._process): a page rebuilds and moves
## on its own dirty flag and nothing signals it.
func _process(_delta: float) -> void:
	for scroll in _bars.keys():
		var bar: VScrollBar = _bars[scroll]
		if not is_instance_valid(scroll):
			bar.queue_free()
			_bars.erase(scroll)
			continue
		bar.visible = scroll.is_visible_in_tree() and scrolls(scroll)  # the scroll's own range, the truth
		if bar.visible:
			var rect: Rect2 = scroll.get_global_rect()
			bar.position = Vector2(rect.end.x + (UiTheme.GAP_PANE - ScrollBars.GAP_BAR_WIDTH_PX) / 2.0, rect.position.y) - global_position
			bar.size = Vector2(ScrollBars.GAP_BAR_WIDTH_PX, rect.size.y)
