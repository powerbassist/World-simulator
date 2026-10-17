extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")

## The thin strip along the top edge -- U2, rebuilt at U5a, made ONE THING at V4.8a.
##
## U2 put six things here because there was nowhere else to put them; U5a gave the
## clock its own corner cluster and left this the job a permanent top strip is good
## at -- the numbers that are true about the country regardless of what the player
## is looking at. V4.1-V4.7 each landed an interim figure here (programme, people,
## desk, Europe); V4.8a moved every reading into strip_readings.gd's register, so
## this file is the HOST: one figure per ORDER entry, drawing whatever the register
## returns. A new reading is a register entry, never a branch here.
##
## Reads state, never writes it. The gear and save buttons emit; main.gd decides
## what they open, the same shape as every other panel here.

signal settings_requested
signal save_load_requested

const BAR_HEIGHT := 40
## The programme caption's width: "PROGRAMME" itself, so the strip's measured
## width is the same with or without one running.
const PROGRAMME_CAPTION_PX := 104
## Caption-to-value gap inside a stacked figure; negative pulls the two lines
## together so the bar stays inside window_frame.gd's TOP_MARGIN.
const FIGURE_LINE_GAP := -4

var _figure_values := {}
## Each figure's caption label, by the same key as _figure_values -- kept so the
## live tooltip goes on both hover targets, and the programme can name itself.
var _figure_captions := {}
## Window id -> its shortcut's key string ("E"), filled once by main.gd after every
## window is registered, so an alert names the key the shell really binds.
var window_keys := {}
## The row the figures sit in -- read by the walker test's width check.
var _figures: HBoxContainer
var _tools: HBoxContainer


func _ready() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	# Square corners and its own padding, because this one sits flush against
	# the window edge; every other panel takes the theme's default.
	theme_type_variation = UiTheme.TOP_BAR_PANEL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	row.add_child(_spacer())

	_figures = HBoxContainer.new()
	_figures.add_theme_constant_override("separation", 26)
	row.add_child(_figures)
	for id in StripReadings.ORDER:
		_figures.add_child(_build_figure(id, String(StripReadings.CAPTIONS[id])))

	row.add_child(_spacer())

	_tools = HBoxContainer.new()
	_tools.add_theme_constant_override("separation", 4)
	row.add_child(_tools)

	var save := Button.new()
	save.text = "SAVE"
	save.theme_type_variation = UiTheme.SUBROW_BUTTON
	save.tooltip_text = "Save and load (S)"
	save.pressed.connect(func(): save_load_requested.emit())
	_tools.add_child(save)

	var settings := Button.new()
	settings.text = "MENU"
	settings.theme_type_variation = UiTheme.SUBROW_BUTTON
	settings.tooltip_text = "Pause menu (Esc)"
	settings.pressed.connect(func(): settings_requested.emit())
	_tools.add_child(settings)


## Caption above value. U5a put them on one line to get the strip to 40px; at
## V4.8a's thirteen readings one line needed 2219 px of a 1920 screen, so they
## stack again -- with a negative separation so the two lines sit inside the
## frames' TOP_MARGIN, which is what keeps the 826px window band unchanged.
func _build_figure(key: String, title: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", FIGURE_LINE_GAP)

	var label := Label.new()
	label.text = title.to_upper()
	label.theme_type_variation = UiTheme.MICRO
	_hoverable(label)
	box.add_child(label)

	var value := Label.new()
	value.theme_type_variation = UiTheme.FIGURE
	_hoverable(value)
	box.add_child(value)
	_figure_values[key] = value
	_figure_captions[key] = label
	# The programme's caption is its NAME (V4.1), which content writes and no width
	# bounds -- clipped with an ellipsis, the full name in the tip, so one long
	# programme cannot push the strip off the screen.
	if key == "programme":
		label.custom_minimum_size.x = PROGRAMME_CAPTION_PX
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return box


## A Label defaults to MOUSE_FILTER_IGNORE in Godot 4, so the hovered control
## under a figure is its HBoxContainer -- which carries no tooltip -- and a
## tooltip_text set on the Label never appears. PASS makes the Label a hover
## target while still propagating the event, so a click on the strip is not
## swallowed (STOP would).
func _hoverable(label: Label) -> void:
	label.mouse_filter = Control.MOUSE_FILTER_PASS


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
	for id in StripReadings.ORDER:
		var r: Dictionary = StripReadings.read(id, state, loader)
		var value: Label = _figure_values[id]
		var caption: Label = _figure_captions[id]
		value.get_parent().visible = bool(r["visible"])
		if not bool(r["visible"]):
			continue
		value.text = String(r["text"])
		if r.has("caption"):
			caption.text = String(r["caption"]).to_upper()
		var alert := String(r["alert_window"])
		value.theme_type_variation = UiTheme.FIGURE if alert.is_empty() else UiTheme.FIGURE_ALERT
		var tip := String(r["tip"])
		if not alert.is_empty():
			tip += "\nOpen %s." % _window_hint(alert)
		value.tooltip_text = tip
		caption.tooltip_text = tip


## "the economy window (E)" -- the key read from the window manager at startup,
## so an alert cannot name a shortcut the shell does not bind.
func _window_hint(window_id: String) -> String:
	var key := String(window_keys.get(window_id, ""))
	if key.is_empty():
		return "the %s window" % window_id
	return "the %s window (%s)" % [window_id, key]
