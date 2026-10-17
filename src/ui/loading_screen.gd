extends Control

## V4.9a. The menu -> game crossing, drawn. Before this the window froze for
## ~7 s on New Game with the menu still showing; now the boot runs a stage per
## frame (boot_stages.gd) and this draws what it reports: the stage in words
## and a bar whose fill is the measured share of the boot already done. No
## tween on the bar -- it moves exactly as fast as the work.
##
## Opaque, and it takes the keyboard focus: a menu button left focused behind
## it would otherwise start a second game on Enter.

## Emitted once the game node is in the tree. The menu frees itself on it; this
## screen has already moved itself to the root by then, so it outlives the menu
## long enough to fade off the game it opened.
signal entered(game: Node)

const BootStages = preload("res://src/ui/boot_stages.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Motion = preload("res://src/ui/motion.gd")

## Work per frame. Well above a frame (16 ms) on purpose: a loading screen
## needs to look alive, not to run at 60 fps, and every frame drawn is time the
## boot did not get. Measured windowed (tools/boot_stages_probe.gd): 30 ms
## spent ~1.2 s of an 8.1 s boot drawing frames; 50 ms (~20 fps) halves that.
const BUDGET_USEC := 50_000

## The fade off the game once it is up. Motion's OPEN_S family, a little
## longer: this one reveals the whole screen.
const REVEAL_S := 0.3

var boot

var _bar: ProgressBar
var _stage_label: Label
var _percent: Label


## Call after add_child() -- _ready() builds the labels this fills.
func start(nation_id: String, scenario_id: String, load_slot: String) -> void:
	boot = BootStages.new(nation_id, scenario_id, load_slot)
	_refresh()


func _ready() -> void:
	# Its own copy of the theme: it is reparented to the root at the end, out
	# from under the menu's, and must not change face mid-fade.
	UiTheme.apply(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL

	var ground := ColorRect.new()
	ground.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ground.color = UiTheme.INK
	ground.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ground)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)

	var title := Label.new()
	title.text = "NATION SIMULATOR"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)

	_bar = ProgressBar.new()
	_bar.min_value = 0.0
	_bar.max_value = 1.0
	_bar.step = 0.0
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(480, 6)
	column.add_child(_bar)

	var row := HBoxContainer.new()
	column.add_child(row)

	_stage_label = Label.new()
	_stage_label.theme_type_variation = UiTheme.CAPTION
	_stage_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stage_label)

	_percent = Label.new()
	_percent.theme_type_variation = UiTheme.CAPTION
	row.add_child(_percent)

	grab_focus()


func _gui_input(event: InputEvent) -> void:
	accept_event()


func _process(_delta: float) -> void:
	if boot == null:
		return
	# The step that reaches "enter" returns, so the frame draws the last stage
	# before the next one spends it inside main.gd's _ready().
	if not boot.ready_to_enter():
		boot.step(BUDGET_USEC)
		_refresh()
		return
	_enter()


func _refresh() -> void:
	if boot == null or _bar == null:
		return
	var p: float = boot.progress()
	_bar.value = p
	_stage_label.text = boot.label().to_upper()
	_percent.text = "%d%%" % floori(p * 100.0)


func _enter() -> void:
	set_process(false)
	var game: Node = boot.game
	var tree := get_tree()
	var t0 := Time.get_ticks_usec()
	tree.root.add_child(game)
	boot.record_enter(Time.get_ticks_usec() - t0)
	tree.current_scene = game
	# Last child of the root draws on top: the game is under this screen now.
	reparent(tree.root, false)
	_bar.value = 1.0
	_percent.text = "100%"
	# The game's own controls take the keyboard from here.
	release_focus()
	focus_mode = Control.FOCUS_NONE
	entered.emit(game)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Motion.fade_out(self, REVEAL_S, queue_free)
