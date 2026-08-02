extends PanelContainer

const UiTheme = preload("res://src/ui/ui_theme.gd")

## The thin strip along the top edge -- U2, rebuilt at U5a.
##
## U2 put six things here because there was nowhere else to put them: the date,
## pause, three speeds and four figures. U5a gives the clock its own corner
## cluster and gives approval to the portrait card, which leaves this doing the
## one job a permanent top strip is good at -- the two or three numbers that are
## true about the country regardless of what the player is looking at.
##
## Deficit, GDP and unemployment, in that order, matching the reference. Not
## approval (the portrait carries it, and a president reads their own standing
## off their own face) and not government standing, which is a Politics-panel
## question the player checks rather than monitors.
##
## Reads state, never writes it. The gear and save buttons emit; main.gd decides
## what they open, the same shape as every other panel here.

signal settings_requested
signal save_load_requested

const BAR_HEIGHT := 40

var _figure_values := {}


func _ready() -> void:
	custom_minimum_size = Vector2(0, BAR_HEIGHT)
	# Square corners and its own padding, because this one sits flush against
	# the window edge; every other panel takes the theme's default.
	theme_type_variation = UiTheme.TOP_BAR_PANEL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	row.add_child(_spacer())

	var figures := HBoxContainer.new()
	figures.add_theme_constant_override("separation", 34)
	row.add_child(figures)

	figures.add_child(_build_figure("deficit", "Budget deficit"))
	figures.add_child(_build_figure("gdp", "GDP"))
	figures.add_child(_build_figure("unemployment", "Unemployment"))

	row.add_child(_spacer())

	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 4)
	row.add_child(tools)

	var save := Button.new()
	save.text = "SAVE"
	save.theme_type_variation = UiTheme.SUBROW_BUTTON
	save.tooltip_text = "Save and load (S)"
	save.pressed.connect(func(): save_load_requested.emit())
	tools.add_child(save)

	var settings := Button.new()
	settings.text = "MENU"
	settings.theme_type_variation = UiTheme.SUBROW_BUTTON
	settings.tooltip_text = "Pause menu (Esc)"
	settings.pressed.connect(func(): settings_requested.emit())
	tools.add_child(settings)


## Label and value on one line rather than stacked, which is what lets the strip
## be 40px instead of U2's 64 and still read at a glance.
func _build_figure(key: String, title: String) -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 7)

	var label := Label.new()
	label.text = title.to_upper()
	label.theme_type_variation = UiTheme.MICRO
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(label)

	var value := Label.new()
	value.theme_type_variation = UiTheme.FIGURE
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(value)
	_figure_values[key] = value

	return box


func _spacer() -> Control:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer


## Called every day -- cheap enough that main.gd calls it unconditionally rather
## than gating it behind a dirty flag like the floating panels, matching the HUD
## it replaces.
func refresh(state, _clock: Node) -> void:
	if state == null:
		return
	var ns = state.player()

	# Signed the way a player reads it: a deficit is a negative number.
	_figure_values["deficit"].text = "%+.2f%%" % -ns.deficit_pct_gdp
	_figure_values["gdp"].text = "%.0f Bn" % ns.gdp_eur_bn
	_figure_values["unemployment"].text = "%.2f%%" % ns.unemployment_pct
