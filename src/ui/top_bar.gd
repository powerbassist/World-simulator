extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const StripChanges = preload("res://src/ui/strip_changes.gd")
const StripChildren = preload("res://src/ui/strip_children.gd")
const TipPopup = preload("res://src/ui/tip_popup.gd")
const Motion = preload("res://src/ui/motion.gd")

## The thin strip along the top edge -- U2, rebuilt at U5a, made ONE THING at V4.8a,
## regrouped at V5.3 (the author picked bar C; gate H6, "info bar text not aligned,
## some info useless or unclear").
##
## It is the HOST of strip_readings.gd's register: one figure per reading, drawing
## whatever the register returns. A new reading is a register entry, never a branch
## here. What changed at V5.3 is WHICH it draws and how: the standing figures
## (StripReadings.ON_STRIP) left-aligned at the workspace's edge, each with its own
## change beside it; the CHIPS (desk, Europe, programme, supplies) on the right only
## while something waits; approval and the vote are still read but drawn elsewhere
## (the portrait card, the horizon), so their boxes are built and kept hidden.
##
## V4.8b: a figure's tooltip is the two-level TipPopup, not Godot's own -- the
## built-in one cannot be hovered into, so a line that opens a breakdown needs
## its own. tooltip_text stays empty on the strip (a non-empty one would draw a
## second tooltip beside ours); tip_of(id) is the plain text a test or a reader
## can still get.
##
## Reads state, never writes it. Save and the menu moved to the title bar
## (V5.1-c2.3), so the strip is the figures alone.

## The strip's slot under the title bar: the BUREAU board's 58 px, which holds
## the stacked figures up to the largest text size (they need 54 at 130 %,
## V5.1-c2.4). The workspace starts below it.
const BAR_HEIGHT := 58
## The programme caption's width: "PROGRAMME" itself, so the strip's measured
## width is the same with or without one running.
const PROGRAMME_CAPTION_PX := 104
## Caption-to-value gap inside a stacked figure; negative pulls the two lines
## together so the bar stays above the workspace dock.
const FIGURE_LINE_GAP := -4
const FIGURE_GAP := 26
const FIGURE_GAP_MIN := 6
## The left edge of the first figure: the workspace's own edge (sidebar's width 232 is
## this strip's x), a gutter in.
const LEFT_GUTTER := 16

var _figure_values := {}
## Each figure's caption label, by the same key as _figure_values -- kept so the
## live tooltip goes on both hover targets, and the programme can name itself.
var _figure_captions := {}
## Reading id -> the whole figure (caption over the value row): what hides and shows.
var _boxes := {}
## Reading id -> its change label (beside the value); empty for a figure with none.
var _changes := {}
## Reading id -> its level-1 lines as last refreshed, alert line included.
var _tips := {}
var _popup
## The state and loader the last refresh read, so a level-2 breakdown is answered
## from the same world the figure shows.
var _state
var _loader
## Window id -> "Dispatches (N)": the frame's title and bound key, filled once by
## main.gd after every window is registered, so an alert names the window the way
## the shell does (the review caught "the events window" for Dispatches).
var window_hints := {}

## The row the standing figures sit in -- read by the walker test's width check.
var _figures: HBoxContainer
## The waiting chips, right-aligned.
var _chips: HBoxContainer
## The gap between the figures as last set, so a day that changes nothing does not
## re-lay the bar.
var _gap := FIGURE_GAP
## V5.1-c2.3. The "+N" the lowest-priority figures fold behind when the strip's
## slot cannot hold them all, and their ids, in ON_STRIP order.
var _more: Label
var _folded: Array = []


func _ready() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	# Square corners and its own padding, because this one sits flush against
	# the window edge; every other panel takes the theme's default.
	theme_type_variation = UiTheme.TOP_BAR_PANEL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	row.add_child(_gutter(LEFT_GUTTER))
	_figures = HBoxContainer.new()
	_figures.add_theme_constant_override("separation", FIGURE_GAP)
	row.add_child(_figures)
	for id in StripReadings.ORDER:
		var box := _build_figure(id, tr(String(StripReadings.CAPTIONS[id])))
		if StripReadings.ON_STRIP.has(id):
			_figures.add_child(box)
		else:
			box.hide()
			row.add_child(box)  # kept so the reading's text exists; never shown here
	_more = Label.new()
	_more.theme_type_variation = UiTheme.FIGURE
	_more.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_more.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_more.mouse_filter = Control.MOUSE_FILTER_PASS
	_more.hide()
	_figures.add_child(_more)

	row.add_child(_gutter(0, true))
	_chips = HBoxContainer.new()
	_chips.add_theme_constant_override("separation", FIGURE_GAP)
	row.add_child(_chips)
	for id in StripReadings.CHIPS:
		_boxes[id].get_parent().remove_child(_boxes[id])
		_chips.add_child(_boxes[id])
	row.add_child(_gutter(LEFT_GUTTER))
	# A window that changes shape refits the strip at once, not on the next day's
	# refresh (V5.1-c Review focus 5: a window gone 21:9 mid-game).
	get_viewport().size_changed.connect(refit)

	_popup = TipPopup.new()
	add_child(_popup)


## Caption above, value and its change beside it below. U5a put them on one line to
## get the strip to 40px; at V4.8a's thirteen readings one line needed 2219 px of a 1920
## screen, so they stack again -- with a negative separation so the two lines sit inside
## the dock's top.
func _build_figure(key: String, title: String) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_theme_constant_override("separation", FIGURE_LINE_GAP)

	var label := Label.new()
	label.text = title.to_upper()
	label.theme_type_variation = UiTheme.MICRO
	_hoverable(label, key)
	box.add_child(label)

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 7)
	box.add_child(line)
	var value := Label.new()
	value.theme_type_variation = UiTheme.FIGURE
	_hoverable(value, key)
	line.add_child(value)
	var change := Label.new()
	change.theme_type_variation = UiTheme.CAPTION
	change.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	change.size_flags_vertical = Control.SIZE_SHRINK_END
	change.hide()
	_hoverable(change, key)
	line.add_child(change)
	_figure_values[key] = value
	_figure_captions[key] = label
	_boxes[key] = box
	_changes[key] = change
	# The programme's caption is its NAME (V4.1), which content writes and no width
	# bounds -- clipped with an ellipsis, the full name in the tip, so one long
	# programme cannot push the strip off the screen.
	if key == "programme":
		label.custom_minimum_size.x = PROGRAMME_CAPTION_PX
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return box


## A Label defaults to MOUSE_FILTER_IGNORE in Godot 4, so it never sees the
## pointer and no hover reaches the popup. PASS makes the Label a hover target
## while still propagating the event, so a click on the strip is not swallowed
## (STOP would).
func _hoverable(label: Label, key: String) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.mouse_entered.connect(_on_figure_entered.bind(key, label))
	label.mouse_exited.connect(_on_figure_exited.bind(key))


func _on_figure_entered(key: String, _anchor: Label) -> void:
	if not _tips.has(key):
		return
	# Anchored to the figure's box, so the popup hangs from the caption's left edge
	# whichever label the pointer touched.
	_popup.figure_entered(key, _boxes[key], _tips[key], func(child_id: String) -> Dictionary:
		return StripChildren.child(key, child_id, _state, _loader))


func _on_figure_exited(key: String) -> void:
	_popup.figure_exited(key)


## The figure's box (caption over value): what a reading's visibility shows and hides.
func figure_box(id: String) -> Control:
	return _boxes[id]


## The plain text of a reading's tooltip, alert line included: the lines the
## popup draws, joined.
func tip_of(id: String) -> String:
	var texts: Array[String] = []
	for line in (_tips.get(id, []) as Array):
		texts.append(String(line["text"]))
	return "\n".join(texts)


func _gutter(width: int, expand := false) -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size.x = width
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL if expand else Control.SIZE_FILL
	return spacer


## Called every day -- cheap enough that main.gd calls it unconditionally rather
## than gating it behind a dirty flag like the floating panels. The loader is
## optional so the two-argument call still works; without one, the readings that
## need content (the programme, Supplies) stay hidden.
##
## A bad player_nation_id gives player() == null (playability-audit Register B's
## crash row: it crashed here on the next day tick) -- nothing to read, so nothing
## is drawn.
func refresh(state, _clock: Node, loader = null) -> void:
	if state == null or state.player() == null:
		return
	_state = state
	_loader = loader
	# The readings set every figure's visibility afresh, so nothing is folded
	# until refit() decides again below.
	_folded.clear()
	for id in StripReadings.ORDER:
		var r: Dictionary = StripReadings.read(id, state, loader)
		var value: Label = _figure_values[id]
		var caption: Label = _figure_captions[id]
		var drawn := bool(r["visible"]) and not StripReadings.OFF_STRIP.has(id) \
			and not (StripReadings.CHIPS.has(id) and StripReadings.is_resting(r))
		_boxes[id].visible = drawn
		if not bool(r["visible"]):
			continue
		# V4.9a. Rolls to the new value when only its numbers moved; a reading
		# that changed shape snaps. Final the moment motion is off (headless).
		Motion.roll_text(value, String(r["text"]), flash_tone(id, value.text, String(r["text"])))
		if r.has("caption"):
			caption.text = String(r["caption"]).to_upper()
		var alert := String(r["alert_window"])
		value.theme_type_variation = UiTheme.FIGURE if alert.is_empty() else UiTheme.FIGURE_ALERT
		_show_change(id, state)
		var lines: Array = (r["lines"] as Array).duplicate()
		if not alert.is_empty():
			lines.append({"text": tr("Open %s.") % _window_hint(alert), "child_id": ""})
		_tips[id] = lines
		_popup.update_lines(id, lines)
	refit()


## The figure's own movement beside it, in a status tone with its glyph (never colour
## alone); nothing when history has none to show.
func _show_change(id: String, state) -> void:
	var label: Label = _changes[id]
	var c := StripChanges.change(id, state)
	label.visible = not c.is_empty()
	if c.is_empty():
		return
	label.text = String(c["text"])
	label.theme_type_variation = UiTheme.GOOD_TEXT if bool(c["good"]) else UiTheme.BAD_TEXT


## V5.3-0 4.5: the tone a figure flashes when it moves from `before` to `after`:
## GOOD when it went its good direction, BAD the other, none for a figure with no
## verdict or a reading that changed shape. The word stays the figure; the
## flash is never the only sign (the tooltip names the change).
static func flash_tone(id: String, before: String, after: String) -> Color:
	var dir := Motion.moved(before, after)
	if dir == 0 or not StripReadings.GOOD_WHEN_RISING.has(id):
		return Color(0, 0, 0, 0)
	return UiTheme.GOOD if (dir > 0) == bool(StripReadings.GOOD_WHEN_RISING[id]) else UiTheme.BAD


## The strip in its slot -- the screen right of the sidebar. The gaps between the
## figures give way first (at 26 px they are 286 px of the bar; V5.1b); then the
## LOWEST-PRIORITY standing figures, the tail of StripReadings.ON_STRIP, fold behind
## a "+N" whose tip names them (V5.1-c2.3), until what is left fits beside the
## waiting chips. A longer language, a larger text size or a game whose every reading
## speaks at once can ask for more than the slot, and a strip that grew past it would
## push the chrome off the screen.
##
## Measured off each figure's own minimum rather than the row's, because the
## row's cached minimum lags a visibility change by a frame.
func refit() -> void:
	for id in _folded:
		_boxes[id].show()
	_folded.clear()
	_more.hide()
	var available: float = get_viewport_rect().size.x - global_position.x - get_theme_stylebox("panel").get_minimum_size().x \
		- LEFT_GUTTER * 2 - _chips_width()
	var shown: Array = []
	for id in StripReadings.ON_STRIP:
		if _boxes[id].visible:
			shown.append(id)
	var gap := FIGURE_GAP
	var over := _width_of(shown, FIGURE_GAP, 0.0) - available
	if over > 0.0:
		gap = maxi(FIGURE_GAP_MIN, FIGURE_GAP - ceili(over / maxi(shown.size() - 1, 1)) - 1)
	while shown.size() > 1 and _width_of(shown, gap, _more_width(_folded.size())) > available:
		var id: String = shown.pop_back()
		_boxes[id].hide()
		_folded.push_front(id)
	if not _folded.is_empty():
		var tip: Array[String] = []
		for id in _folded:
			tip.append("%s %s" % [_figure_captions[id].text, _figure_values[id].text])
		_more.text = "+%d" % _folded.size()
		_more.tooltip_text = "\n".join(tip)
		_more.show()
	if gap != _gap:
		_gap = gap
		_figures.add_theme_constant_override("separation", gap)


## The chips' own width (they never fold: each is something waiting), gaps and all.
func _chips_width() -> float:
	var total := 0.0
	var count := 0
	for id in StripReadings.CHIPS:
		if _boxes[id].visible:
			total += _boxes[id].get_combined_minimum_size().x
			count += 1
	return total + FIGURE_GAP * maxi(count - 1, 0)


## A new theme -- the text size changed -- resizes every figure, so the fold is
## decided again once the sizes have settled.
func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and _more != null:
		refit.call_deferred()


## The figures held back, lowest priority last, in ON_STRIP order.
func folded_ids() -> Array:
	return _folded.duplicate()


func _width_of(ids: Array, gap: int, more: float) -> float:
	var total := 0.0
	for id in ids:
		total += _boxes[id].get_combined_minimum_size().x
	total += gap * maxi(ids.size() - 1, 0)
	if more > 0.0:
		total += gap + more
	return total


## The "+N" label's width for `count` folded figures, 0 for none.
func _more_width(count: int) -> float:
	if count == 0:
		return 0.0
	_more.text = "+%d" % count
	return _more.get_combined_minimum_size().x


## "Economy (E)" -- the hint main.gd read off the window manager; the bare id only
## for a bar refreshed before main.gd filled the hints (a test harness).
func _window_hint(window_id: String) -> String:
	return String(window_hints.get(window_id, window_id))
