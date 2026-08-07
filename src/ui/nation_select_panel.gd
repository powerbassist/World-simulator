extends PanelContainer

## New Game's nation choice -- V1.2a -- and, since V1.2e, its start choice.
## Lists every nation the loaded data marks `playable`, whatever that count is;
## the panel does not know or care how many there are, the same way
## save_load_panel.gd does not care how many slots exist. See
## docs/data-architecture.md.
##
## Two steps, one panel. A nation with authored starts swaps this list for its
## own before emitting, rather than opening a second overlay: the choice is
## "which game am I starting", and splitting one question across two panels
## would put a Back button between the two halves of it. A nation with no
## authored start emits straight through, so the second step never appears as
## an empty list with one entry in it. See docs/scenario-model.md.
##
## Built in code, like every other panel here. Modelled on save_load_panel.gd's
## shape: a scrolling list of rows, each with a button that emits a choice back
## to the caller rather than acting on it directly.

## `scenario_id` is "" for the standard start -- the same empty-means-standard
## convention GameState.new_game() takes.
signal nation_selected(nation_id: String, scenario_id: String)
## Emitted alongside hide(), the same shape save_load_panel.gd already uses --
## the main menu hosts this in a full-rect holder it has to hide too, and
## cannot see a plain hide().
signal closed

const UiTheme = preload("res://src/ui/ui_theme.gd")

var _title: Label
var _list: VBoxContainer

var _nations: Array = []

## person id -> name, and deliberately NOT the loader. This is the one panel that
## resolves a person without holding a DataLoader, and the menu passes the map
## rather than the object it came from: the panel needs a name, not a data layer,
## and handing it the loader would let a later edit reach for anything in there.
var _person_names: Dictionary = {}
## nation id -> Array of Scenario, built once in set_nations(). Empty for a
## nation nobody has authored a start for, which is the majority case and the
## one that must stay a single click.
var _scenarios_by_nation: Dictionary = {}


func _ready() -> void:
	custom_minimum_size = Vector2(480, 420)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	_title = Label.new()
	_title.text = "CHOOSE A NATION"
	root.add_child(_title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)

	root.add_child(_build_footer())


func _build_footer() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END

	var close := Button.new()
	close.text = "Back"
	close.pressed.connect(func():
		# From the start list, Back means "pick a different nation" rather than
		# "leave New Game" -- otherwise choosing a nation is unrecoverable
		# without leaving and re-entering the whole flow.
		if _title.text != "CHOOSE A NATION":
			_show_nations()
			focus_first()
			return
		hide()
		closed.emit()
	)
	row.add_child(close)

	return row


## `nations` is an Array of the Nation objects DataLoader.nations holds for
## every nation with `playable = true`, already filtered and sorted by the
## caller -- this panel only lays them out. `scenarios` is DataLoader.scenarios
## whole; the panel indexes it by nation itself, because which nations have a
## start authored is not something the caller should have to know either.
func set_nations(nations: Array, scenarios: Dictionary = {}, person_names: Dictionary = {}) -> void:
	_nations = nations
	_person_names = person_names

	_scenarios_by_nation = {}
	var ids: Array = scenarios.keys()
	ids.sort()
	for id in ids:
		var s = scenarios[id]
		if not _scenarios_by_nation.has(s.nation_id):
			_scenarios_by_nation[s.nation_id] = []
		_scenarios_by_nation[s.nation_id].append(s)

	_show_nations()


## Put keyboard focus on the first row's Play button. Called by menu.gd when the
## panel opens, and again by this panel whenever it swaps its own list -- a
## focused control that has just been queue_free()d leaves the panel keyboard-
## dead, which is the same failure as never focusing anything.
##
## grab_focus() only works in the tree, so this is a method the caller invokes
## after add_child()/show() rather than something _ready() can do. See the
## Control-outside-the-tree gotcha in docs/engine-decision.md.
func focus_first() -> void:
	for row in _list.get_children():
		for child in row.get_children():
			if child is Button:
				child.grab_focus()
				return


func _clear() -> void:
	for child in _list.get_children():
		_list.remove_child(child)
		child.queue_free()


func _show_nations() -> void:
	_title.text = "CHOOSE A NATION"
	_clear()

	if _nations.is_empty():
		var none := Label.new()
		none.text = "No playable nation found in data/nations/."
		_list.add_child(none)
		return

	for n in _nations:
		_list.add_child(_build_nation_row(n))


func _build_nation_row(n) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var label := Label.new()
	label.text = "%s -- %s (%s)" % [
		n.nation_name, n.leader_title, String(_person_names.get(n.leader_person_id, "")),
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var play_btn := Button.new()
	play_btn.text = "Play"
	play_btn.pressed.connect(func():
		if _scenarios_by_nation.get(n.id, []).is_empty():
			nation_selected.emit(n.id, "")
			return
		_show_starts(n)
	)
	row.add_child(play_btn)

	return row


func _show_starts(n) -> void:
	_title.text = "CHOOSE A START -- %s" % n.nation_name.to_upper()
	_clear()

	# Standard first and always: it is the game every measured balance number in
	# docs/ describes, and burying it under the authored starts would make the
	# baseline look like one variant among several.
	_list.add_child(_build_start_row(
		n.id, "", "Standard",
		"The nation as it really stands. The baseline every other start varies from."
	))

	for s in _scenarios_by_nation[n.id]:
		_list.add_child(_build_start_row(n.id, s.id, s.display_name, s.description))

	focus_first()


func _build_start_row(nation_id: String, scenario_id: String, name: String, description: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	var label := Label.new()
	label.text = name
	column.add_child(label)

	var blurb := Label.new()
	blurb.text = description
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.theme_type_variation = UiTheme.CAPTION
	column.add_child(blurb)

	var play_btn := Button.new()
	play_btn.text = "Play"
	play_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	play_btn.pressed.connect(func(): nation_selected.emit(nation_id, scenario_id))
	row.add_child(play_btn)

	return row
