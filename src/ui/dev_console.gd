extends Control

## THE IN-GAME DEV CONSOLE (V5.1-0b). DEV ONLY: a play gate's crash shows its error
## in the game, a repro is a line of text, and an agent drives the game by command
## rather than by simulated clicks (the V5.0 gates lost hours to both).
##
##   F12         opens and closes the panel -- F12 because the author's AZERTY keyboard
##               has no free `~` (it is AltGr+e-acute there)
##   counter     errors and warnings the Logger has heard, always on screen; click it
##               for the Errors tab
##   perf        `perf` shows frame time (now, worst of the last few seconds) and the
##               last month's cost per system -- src/ui/dev_perf.gd
##   commands    src/ui/dev_registry.gd's table; `help` lists it
##   run_command(text) -> String
##               the ONE entry an agent needs: the godot-mcp-toolkit's `execute_code` on
##               the runtime channel (node_call_method is editor-only and cannot reach
##               a running game -- docs/tooling.md). The line and its answer land in
##               the panel too, so a human watching sees what the agent did.
##
## NOTHING OF IT IN A RELEASE BUILD: install() returns before it builds a node or
## registers the Logger unless the build is a debug build or `--dev-console` was
## asked for. main.gd's whole footprint is that one call.
##
## It writes nothing to the game. State goes through src/sim/dev_commands.gd (the
## registry's only door); the clock, windows and save screen are moved the way the
## player moves them, through main.gd's own handlers. main.gd's variables are read
## by name (`main._clock`): main.gd is what V5.1c dissolves, and this one class is
## what follows it.

const DevRegistry = preload("res://src/ui/dev_registry.gd")
const DevLog = preload("res://src/ui/dev_log.gd")
const DevPerf = preload("res://src/ui/dev_perf.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Budget = preload("res://src/sim/budget.gd")
const SaveManager = preload("res://src/core/save_manager.gd")

const FLAG := "--dev-console"
const TOGGLE_KEY := KEY_F12
const OVERLAY_REFRESH_SEC := 0.25
const HISTORY_MAX := 50
const OUTPUT_PARAGRAPHS_MAX := 600
## A month's day loop cannot run longer than this many days; a guard, not a rule.
const MONTH_DAYS_MAX := 40

var _main: Control
var _registry
var _log := DevLog.new()
var _perf := DevPerf.new()
var _panel: PanelContainer
var _tabs: TabContainer
var _output: RichTextLabel
var _errors_view: RichTextLabel
var _input: LineEdit
var _counter: Label
var _overlay: Label
var _history: Array[String] = []
var _history_at := 0
var _overlay_age := 0.0
var _shown_counts := Vector2i(-1, -1)


static func enabled(debug_build: bool, args) -> bool:
	return debug_build or FLAG in args


## Adds the console to `host` (the game scene) and returns it, or returns null and
## adds nothing in a release build.
static func install(host: Control, debug_build: bool = OS.is_debug_build(), args = null) -> Control:
	if not enabled(debug_build, OS.get_cmdline_args() + OS.get_cmdline_user_args() if args == null else args):
		return null
	var console: Control = new()
	console._main = host
	# A fixed name, so an agent's path to run_command() is stable (docs/tooling.md).
	console.name = "DevConsole"
	host.add_child(console)
	return console


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_registry = DevRegistry.new(MainHost.new(_main, self))
	_log.install()
	_build()
	_update_counter()


func _exit_tree() -> void:
	_log.uninstall()


func _build() -> void:
	_overlay = Label.new()
	_overlay.theme_type_variation = UiTheme.CAPTION
	# Top right under the counter: the left column is the message cards'.
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_overlay.offset_left = -640.0
	_overlay.offset_top = 66.0
	_overlay.offset_right = -10.0
	_overlay.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_overlay.visible = false
	add_child(_overlay)

	_counter = Label.new()
	_counter.mouse_filter = Control.MOUSE_FILTER_STOP
	_counter.tooltip_text = "Errors and warnings logged this run -- click to read them (F12 opens the console)"
	_counter.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_counter.offset_left = -170.0
	_counter.offset_top = 44.0
	_counter.offset_right = -10.0
	_counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_counter.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			show_errors()
	)
	add_child(_counter)

	_panel = PanelContainer.new()
	# The theme's default panel, opaque: the PLATE's glass lets the map through, and
	# a log is read, not glanced at.
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.anchor_top = 0.5
	_panel.anchor_bottom = 0.97
	_panel.offset_top = 0.0
	_panel.offset_bottom = 0.0
	_panel.visible = false
	add_child(_panel)

	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 8)
	_panel.add_child(margin)
	_tabs = TabContainer.new()
	margin.add_child(_tabs)

	var console_tab := VBoxContainer.new()
	console_tab.name = "Console"
	_tabs.add_child(console_tab)
	_output = _text_view()
	console_tab.add_child(_output)
	_input = LineEdit.new()
	_input.placeholder_text = "type help  --  Up/Down recalls, F12 or Esc closes"
	_input.text_submitted.connect(_submit)
	_input.gui_input.connect(_on_input_key)
	console_tab.add_child(_input)

	_errors_view = _text_view()
	_errors_view.name = "Errors"
	_tabs.add_child(_errors_view)


func _text_view() -> RichTextLabel:
	var view := RichTextLabel.new()
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.scroll_following = true
	view.selection_enabled = true
	view.focus_mode = Control.FOCUS_CLICK
	return view


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == TOGGLE_KEY:
		toggle()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	_perf.record(delta * 1000.0, Time.get_ticks_msec() / 1000.0)
	var heard := _log.poll()
	if heard > 0 or Vector2i(_log.errors, _log.warnings) != _shown_counts:
		_update_counter()
		if _panel.visible and _tabs.current_tab == 1:
			_fill_errors()
	if _overlay.visible:
		_overlay_age += delta
		if _overlay_age >= OVERLAY_REFRESH_SEC:
			_overlay_age = 0.0
			_overlay.text = _perf.overlay_text(_month_costs())


func _month_costs() -> Dictionary:
	return _main._month_runner.last_month_costs if _main != null else {}


## THE AGENT'S ENTRY. Runs one console line and returns what it printed.
func run_command(text: String) -> String:
	if not text.strip_edges().is_empty():
		_print("> " + text)
	var answer: String = _registry.run(text)
	if not answer.is_empty():
		_print(answer)
	return answer


func toggle() -> void:
	if _panel.visible:
		_panel.visible = false
		_input.release_focus()
		return
	_panel.visible = true
	if _output.get_paragraph_count() == 0:
		_print("dev console -- type help. F12 closes it. Commands change the game; the month must not be closing.")
	_tabs.current_tab = 0
	_input.grab_focus.call_deferred()


func show_errors() -> void:
	_panel.visible = true
	_tabs.current_tab = 1
	_fill_errors()


func set_perf(mode: String) -> String:
	_overlay.visible = (not _overlay.visible) if mode.is_empty() else mode == "on"
	_overlay_age = OVERLAY_REFRESH_SEC
	return "perf overlay %s" % ("on" if _overlay.visible else "off")


func clear_output() -> void:
	_output.clear()


func is_open() -> bool:
	return _panel.visible


func _submit(text: String) -> void:
	_input.clear()
	if text.strip_edges().is_empty():
		return
	if _history.is_empty() or _history[-1] != text:
		_history.append(text)
		if _history.size() > HISTORY_MAX:
			_history.pop_front()
	_history_at = _history.size()
	run_command(text)


func _on_input_key(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed:
		return
	match event.keycode:
		KEY_ESCAPE:
			toggle()
			_input.accept_event()
		KEY_UP, KEY_DOWN:
			_history_at = clampi(_history_at + (-1 if event.keycode == KEY_UP else 1), 0, _history.size())
			_input.text = "" if _history_at >= _history.size() else _history[_history_at]
			_input.caret_column = _input.text.length()
			_input.accept_event()


func _print(line: String) -> void:
	_output.add_text(line + "\n")
	if _output.get_paragraph_count() > OUTPUT_PARAGRAPHS_MAX:
		_output.remove_paragraph(0)


func _update_counter() -> void:
	_shown_counts = Vector2i(_log.errors, _log.warnings)
	_counter.text = "ERR %d  WARN %d" % [_log.errors, _log.warnings]
	_counter.theme_type_variation = UiTheme.BAD_TEXT if _log.errors > 0 else UiTheme.CAPTION


func _fill_errors() -> void:
	_errors_view.clear()
	if _log.entries.is_empty():
		_errors_view.add_text("No errors or warnings logged this run.\n")
	for entry in _log.entries:
		_errors_view.add_text(DevLog.format_entry(entry) + "\n")


## The registry's Host over the running game (main.gd). The state is read fresh on
## every call: loading a save replaces it.
class MainHost extends DevRegistry.Host:
	var main
	var console

	func _init(game, owner_console) -> void:
		main = game
		console = owner_console

	func state():
		return main._state

	func loader():
		return main._loader

	func busy() -> bool:
		return main._month_runner.running() or main._clock.held

	func refresh() -> void:
		main._update_top_bar()
		main._windows.mark_all_dirty()
		main._map_view.queue_redraw()

	## Whole days until the month turns: a hand-driven day, so its month is run
	## whole through main.gd's own month handler -- the real month, not a copy.
	func advance_month() -> void:
		var clock = main._clock
		var month: int = clock.month
		var guard := 0
		while clock.month == month and guard < MONTH_DAYS_MAX:
			clock.advance_one_day()
			guard += 1

	func date_text() -> String:
		var clock = main._clock
		return "%d-%02d-%02d" % [clock.year, clock.month, clock.day]

	func set_speed(n: int) -> String:
		main._clock.set_speed(n)
		main._update_top_bar()
		return "speed %d" % n

	func set_paused(mode: String) -> String:
		if mode.is_empty() or (mode == "on") != main._clock.paused:
			main._toggle_pause_by_hand()
		main._update_top_bar()
		return "clock paused" if main._clock.paused else "clock running"

	func open_panel(id: String) -> String:
		var ids: Array = main._windows.panel_ids()
		if not ids.has(id):
			return "no panel '%s' -- the ids are %s" % [id, ", ".join(PackedStringArray(ids))]
		main._windows.open(id)
		return "" if main._windows.is_open(id) else "'%s' waits: a scene holds the dock until it closes" % id

	func save_game(slot: String) -> String:
		if not SaveManager.valid_slot_name(slot):
			return "'%s' is not a usable slot name" % slot
		var error: String = SaveManager.save_game(main._state, main._clock, slot)
		main._save_load_panel.mark_dirty()
		return error

	func load_game(slot: String) -> String:
		if not SaveManager.valid_slot_name(slot) or not SaveManager.list_slots().has(slot):
			return "no save in slot '%s'" % slot
		var live = main._state
		main._on_load_requested(slot)
		# A load that fails leaves the live game in place and says so on the save
		# screen; the console must not report it as done.
		return "" if main._state != live else "the save in '%s' would not load -- the save screen says why" % slot

	## The way an arrival from the month's tick is noticed: the card, the sting, the
	## pause the message settings ask for.
	func event_staged(desk_before: Dictionary) -> void:
		main._card_events(main._clock.year, main._clock.month, desk_before, Budget.snapshot(main._state))
		# The month's own arrival path ends here too: an interrupt event holds the
		# clock and opens Dispatches.
		main._enforce_interrupt()

	func term_started() -> void:
		main._enforce_term_start_programme()

	func perf(mode: String) -> String:
		return console.set_perf(mode)

	func clear_output() -> void:
		console.clear_output()

	func dev_log() -> DevLog:
		return console._log
