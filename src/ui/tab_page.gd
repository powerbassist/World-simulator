extends PanelContainer

## One tab of the docked workspace: a scroll around a panel that knows nothing
## about it, and the fold mark -- V5.1-c2.2, out of U5a's window_frame.gd. The
## floating window's title bar, pin, close button and drag went with the author's
## call 3 (one domain open at a time); the dock above this page carries the
## domain's title, its tabs and the way back to the map.
##
## This is deliberately dumb. It holds no game state, never reads GameState, and
## its content is whatever Control it was handed. That is what let U2's docked
## panels become windows and then tabs without one of them being edited:
## budget_panel.gd still builds the same tree it built when it was a tab in U2.
##
## The page is the plate, not the dock: the fold mark is the page's own variation,
## so it says which tab has its verb out of sight.

const UiTheme = preload("res://src/ui/ui_theme.gd")

var _scroll: ScrollContainer
var _content: Control
var _folded := false
var _fill_decided := false


func setup(content: Control) -> void:
	theme_type_variation = UiTheme.PLATE

	# Scrolled rather than sized to the panel. These panels were laid out for a
	# 1280x720 dock and several report a combined minimum size taller than the
	# band a page may occupy -- overview asks for most of 1080 on its own.
	_content = content
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	add_child(_scroll)

	# As wide as the page, and as tall as the panel's own minimum: a floating
	# window sized itself to that minimum, so every panel drew at it, and
	# test_panel_kit.gd holds the reported minimum to the drawn height. A page is
	# the dock's height whatever its content, and an EXPAND here would stretch a
	# short panel's last box down to the bottom of the plate.
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_FILL
	_scroll.add_child(content)

	# The fold mark is re-decided every frame the page is visible rather than on a
	# signal. Three separate things move it -- the dock sizing the page, the
	# player scrolling, and the panel rebuilding itself on its own dirty flag --
	# and only the first two have a signal to hang off. A panel that grew a row
	# and stopped saying so is exactly the bug this exists to catch.
	set_process(true)


func _process(_delta: float) -> void:
	if not visible:
		return
	if not _fill_decided:
		_fill_decided = true
		if _scrolls_inside(_content):
			_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var now := primary_action_below_fold()
	if now == _folded:
		return
	_folded = now
	theme_type_variation = UiTheme.PLATE_FOLDED if now else UiTheme.PLATE


## QA #54 RECORD, the Legislature list that stopped two thirds down the dock -- and
## the frames showed Dispatches, the Agenda, Industry, Organisations, Regions and
## Energy doing the same: a panel whose own ScrollContainer is built to take the
## height left (EXPAND) was laid at its minimum, so its list ended mid-plate. Such
## a panel fills the page; every other one keeps its own height, as above. Asked
## on the first visible frame, after the panel's _ready has built its tree.
static func _scrolls_inside(node: Node) -> bool:
	for child in node.get_children():
		if child is ScrollContainer:
			if (child as Control).size_flags_vertical & Control.SIZE_EXPAND:
				return true
			continue
		if _scrolls_inside(child):
			return true
	return false


## Whether the panel's primary control is currently outside the visible band --
## V2.1a, and the whole of the fold contract's runtime half.
##
## A panel declares its own primary control by implementing `primary_action()`.
## Duck-typed through has_method(), which is `mark_dirty()`'s idiom exactly, so a
## panel with nothing to press -- settings, credits, save/load, the read-only
## readouts -- implements nothing and never draws the mark. There is no base
## class and no registry of which panels have verbs.
##
## Measured against the SCROLL's rect rather than the content's, which is what
## makes the answer follow the player: scrolling the button into view clears the
## mark, because the mark is about what is on screen now and not about how tall
## the panel is.
func primary_action_below_fold() -> bool:
	if _content == null or _scroll == null:
		return false
	if not _content.has_method("primary_action"):
		return false

	var action = _content.primary_action()
	if action == null or not is_instance_valid(action) or not action is Control:
		return false
	if not action.is_visible_in_tree():
		return false

	var bottom: float = action.global_position.y + action.size.y - _scroll.global_position.y
	return bottom > _scroll.size.y


## The page takes the whole band it is given. In the dock it fills the dock's
## body by its anchors and nothing calls this; a test or a probe calls it to
## impose the 1920x1080 reference band on a headless screen that reports
## 1920x1920, so the fold is measured where the player meets it.
##
## The anchors go to the top-left corner first: a size set on a full-rect page is
## an offset from its body, and the body's first layout (the dock's first show)
## would add the body's whole size to it. The next open() anchors it back.
##
## U5a's window sized itself to its content up to the band (min of the two on
## each axis); a docked page is as wide as the dock whatever its content, so a
## narrow panel no longer shrinks the plate around it.
func fit_within(available: Vector2) -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = available
