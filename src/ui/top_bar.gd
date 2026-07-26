extends PanelContainer

const PollNoise = preload("res://src/ui/poll_noise.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

## Persistent top bar, replacing main.tscn's five-line HUD Label -- U2. Date and
## pause/speed on the left, the four headline figures the player is actually
## playing against on the right: approval (the election), government standing
## (censure), deficit (fiscal room), unemployment (the blame the public feels).
## GDP, growth and debt still exist but move to the Economy tab -- see
## ROADMAP.md U2.
##
## Reads state and clock, never writes them. Pause and speed changes go back to
## main.gd as signals, same shape as Budget.commit() -- the panel proposes,
## main.gd is the one holding _clock.

signal pause_toggled
signal speed_selected(speed: int)

const MONTH_NAMES: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun",
	"Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]

var _date_label: Label
var _pause_button: Button
var _speed_buttons := {}
var _figure_values := {}


func _ready() -> void:
	custom_minimum_size = Vector2(0, 64)
	# Square corners and its own padding, because this one sits flush against the
	# window edge; every other PanelContainer takes the theme's default.
	theme_type_variation = UiTheme.TOP_BAR_PANEL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	add_child(row)

	row.add_child(_build_clock_group())

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	row.add_child(_build_figure("approval", "Approval"))
	row.add_child(_build_figure("government", "Government"))
	row.add_child(_build_figure("deficit", "Deficit"))
	row.add_child(_build_figure("unemployment", "Unemployment"))


func _build_clock_group() -> Control:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	_date_label = Label.new()
	_date_label.custom_minimum_size.x = 160
	_date_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(_date_label)

	_pause_button = Button.new()
	_pause_button.text = "Pause (Space)"
	_pause_button.pressed.connect(func(): pause_toggled.emit())
	box.add_child(_pause_button)

	for s in [1, 2, 3]:
		var b := Button.new()
		b.text = "%dx" % s
		b.toggle_mode = true
		b.pressed.connect(func(): speed_selected.emit(s))
		box.add_child(b)
		_speed_buttons[s] = b

	return box


func _build_figure(key: String, title: String) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 110
	col.add_theme_constant_override("separation", 2)

	var label := Label.new()
	label.text = title
	label.theme_type_variation = UiTheme.FIGURE_LABEL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(label)

	var value := Label.new()
	value.theme_type_variation = UiTheme.FIGURE
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(value)
	_figure_values[key] = value

	return col


## Called every day (was _update_hud()'s job) -- cheap enough that main.gd calls
## it unconditionally rather than gating it behind a dirty flag like the docked
## panels, matching the HUD it replaces.
func refresh(state, clock: Node) -> void:
	var month_name: String = MONTH_NAMES[clock.month - 1]
	_date_label.text = "%s %d, %d" % [month_name, clock.day, clock.year]

	_pause_button.text = "Resume (Space)" if clock.paused else "Pause (Space)"
	for s in _speed_buttons.keys():
		_speed_buttons[s].button_pressed = (not clock.paused) and clock.speed == s

	if state == null:
		return
	var ns = state.player()

	_figure_values["approval"].text = "%.0f%%" % PollNoise.displayed(
		PollNoise.poll_id(state.year, state.month), PollingPanel.HEADLINE_KEY, ns.overall_approval_pct
	)

	var standing := "cohabitation" if ns.is_cohabitation else ("minority" if ns.is_minority else "majority")
	_figure_values["government"].text = "%d/%d" % [ns.coalition_seats, ns.assembly_seats]
	_figure_values["government"].tooltip_text = standing.capitalize()

	_figure_values["deficit"].text = "%+.1f%%" % -ns.deficit_pct_gdp
	_figure_values["unemployment"].text = "%.1f%%" % ns.unemployment_pct
