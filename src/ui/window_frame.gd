extends PanelContainer

## The chrome around a floating panel -- U5a. A title, a pin, a close button and
## a grab handle, wrapped around a panel that knows nothing about any of it.
##
## This is deliberately dumb. It holds no game state, never reads GameState, and
## its content is whatever Control it was handed. That is what let U2's seven
## docked panels move into floating windows without one of them being edited:
## budget_panel.gd still builds the same tree it built when it was a tab.
##
## Positioning is manual, so this must be added to a plain Control -- a container
## parent would lay it out and the drag would fight the layout every frame. See
## window_manager.gd, which is that parent.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Icon = preload("res://src/ui/icon.gd")

signal close_requested
signal pin_toggled(pinned: bool)
signal grabbed

## Kept clear of the top strip and of the bottom furniture, so a window can
## never be dragged under the clock or the portrait card and stranded there --
## the title bar is the only thing that drags it back.
const TOP_MARGIN := 44.0
const BOTTOM_MARGIN := 150.0

var pinned := false

var _title_label: Label
var _pin_button: Button
var _close_button: Button
var _scroll: ScrollContainer
var _content: Control
var _dragging := false
var _folded := false

## The band the manager last handed fit_within(), and the content minimum that
## was measured against it. See _process().
var _band := Vector2.ZERO
var _fitted_from := Vector2.ZERO


func setup(title: String, content: Control, icon_path := "") -> void:
	theme_type_variation = UiTheme.PLATE
	# The window sizes to its content, not to the screen: a panel that was 820
	# wide as a tab should not become 1900 wide as a window.
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)

	column.add_child(_build_title_bar(title, icon_path))

	# Scrolled rather than sized to the panel. These panels were laid out for a
	# 1280x720 dock and several report a combined minimum size taller than the
	# band a window is allowed to occupy -- overview asks for most of 1080 on
	# its own. Without this the window grows past the bottom furniture and the
	# player cannot reach its last row at all.
	_content = content
	_scroll = ScrollContainer.new()
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	column.add_child(_scroll)

	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)

	# The fold mark is re-decided every frame the window is visible rather than on
	# a signal. Three separate things move it -- the manager sizing the window on
	# the way in, the player scrolling, and the panel rebuilding itself on its own
	# dirty flag -- and only the first two have a signal to hang off. A panel that
	# grew a row and stopped saying so is exactly the bug this exists to catch.
	set_process(true)

	# Any click anywhere on the window raises it, not only one on the title bar.
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			grabbed.emit()
	)


func _build_title_bar(title: String, icon_path := "") -> Control:
	var bar := PanelContainer.new()
	bar.theme_type_variation = UiTheme.TITLE_BAR
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_title_input)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	bar.add_child(row)

	# V2.3: the window's own glyph ahead of its name, from the same Material Symbols set
	# the bar's clusters wear and through the same bytes-then-rasterise path
	# (icon.gd). Rasterised once here at setup -- the title bar is built once per
	# session, so Icon.load_icon's no-cache cost never repeats.
	if not icon_path.is_empty():
		var glyph := TextureRect.new()
		glyph.texture = Icon.load_icon(icon_path, UiTheme.TEXT, 16)
		glyph.custom_minimum_size = Vector2(16, 16)
		glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(glyph)

	_title_label = Label.new()
	_title_label.text = title.to_upper()
	_title_label.theme_type_variation = UiTheme.HEADING
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_title_label)

	# Text glyphs rather than icons: these two are the only controls in the game
	# that appear on every panel, and a wrong icon here is wrong twenty times.
	_pin_button = Button.new()
	_pin_button.text = tr("PIN")
	_pin_button.toggle_mode = true
	_pin_button.tooltip_text = tr("Keep this panel open when another is opened")
	_pin_button.theme_type_variation = UiTheme.SUBROW_BUTTON
	_pin_button.pressed.connect(func(): set_pinned(_pin_button.button_pressed))
	row.add_child(_pin_button)

	_close_button = Button.new()
	_close_button.text = "X"
	_close_button.theme_type_variation = UiTheme.SUBROW_BUTTON
	_close_button.pressed.connect(func(): close_requested.emit())
	row.add_child(_close_button)

	return bar


func _process(_delta: float) -> void:
	if not visible:
		return
	# Re-fit when the panel's own content has changed size since the window was
	# sized, which is more often than it sounds: window_manager.open() marks the
	# panel dirty and then places the window in the same call, and the panel does
	# not rebuild until its own _process runs on the NEXT frame -- so every window
	# in this game has been sized from its content as it was BEFORE the refresh
	# that filled it. The People window opened 555px tall around a body of ~700 and
	# cut its last four rows off with nothing but a scrollbar to say so.
	# The re-fit changes the SIZE and the window keeps the position it was centred at
	# while narrow, so it is clamped again: the Companies window with a takeover bid
	# grew to x=2180 of 1920 and took its close X off the screen (QA on #49).
	if _band != Vector2.ZERO and _content != null:
		var wanted := _content.get_combined_minimum_size()
		if not wanted.is_equal_approx(_fitted_from):
			fit_within(_band)
			clamp_into_parent()

	var now := primary_action_below_fold()
	if now == _folded:
		return
	_folded = now
	theme_type_variation = UiTheme.PLATE_FOLDED if now else UiTheme.PLATE


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


func set_pinned(value: bool) -> void:
	pinned = value
	if _pin_button != null:
		_pin_button.button_pressed = value
	pin_toggled.emit(value)


func _on_title_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			grabbed.emit()
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		drag_by(event.relative)


## Sizes the window to its content, up to `available`, and scrolls beyond that.
## Called by the manager on the way in rather than at setup(), because at setup()
## the panel is an empty shell -- main.gd's own setup(state, loader) is what
## fills it, and it runs afterwards by necessity (a Control outside the tree has
## not run _ready()).
func fit_within(available: Vector2) -> void:
	if _scroll == null or _content == null:
		return
	_band = available
	# Cleared first: a stale minimum from the last fit would be included in the
	# combined size and the window would ratchet wider every time it opened.
	_scroll.custom_minimum_size = Vector2.ZERO
	var wanted := _content.get_combined_minimum_size()
	_fitted_from = wanted
	_scroll.custom_minimum_size = Vector2(
		minf(wanted.x, maxf(240.0, available.x)),
		minf(wanted.y, maxf(200.0, available.y))
	)
	reset_size()

	# Second pass, V2.1a, and it is a live bug the twenty-first screenshot pass
	# found rather than a tidy-up. `available` is the band the WINDOW may occupy,
	# and the line above spent all of it on the SCROLL -- so the title bar, the
	# separation and the plate's own content margins were added on top and every
	# window that filled its band overflowed by about fifty pixels. The Politics
	# panel ran 945px into an 886px band at the shipped size, and because
	# clamp_into_parent() only constrains POSITION, its last row sat under the
	# bottom furniture with nothing saying so.
	#
	# Taking the excess off the scroll rather than computing the chrome: the parts
	# are a title bar, a container separation and two stylebox margins, and reading
	# the difference back is one subtraction where adding them up is four lookups
	# that go stale the day the theme changes.
	var excess := size.y - available.y
	if excess > 0.0:
		_scroll.custom_minimum_size.y = maxf(200.0, _scroll.custom_minimum_size.y - excess)
		reset_size()


## Public so a headless test can drive it without synthesising mouse motion --
## the same reason map_view.gd exposes pan_by() and zoom_by().
func drag_by(delta: Vector2) -> void:
	position += delta
	clamp_into_parent()


## Called after a drag and after the manager places the window. A window whose
## title bar is off screen cannot be dragged back, because the title bar is the
## only thing that drags it.
func clamp_into_parent() -> void:
	var parent := get_parent_control()
	if parent == null:
		return
	var limit := parent.size - size
	position.x = clampf(position.x, 0.0, maxf(0.0, limit.x))
	position.y = clampf(position.y, TOP_MARGIN, maxf(TOP_MARGIN, limit.y - BOTTOM_MARGIN))
