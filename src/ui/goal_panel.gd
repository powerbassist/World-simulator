extends VBoxContainer

## The goal panel -- V5.3 screen 4 (the author picked laws direction B, "goal first"). Above the
## Bills catalogue: the goals the player is judged on as tiles (the balance, unemployment, one
## bloc's support, a promise on the books) and, under the picked one, every measure that moves it,
## best first -- the laws open to propose, each spending line and each tax rate by one step -- with
## what it does to the goal, and whether the Assembly would pass it or, greyed, why it cannot be
## tabled now. "Catalogue" shows the old list of laws instead.
##
## The numbers are GoalRead's (src/sim/goal_read.gd), a read over copies of the live state that
## writes nothing. The list is read ONE measure a frame (a copy is about 30 ms and cannot be
## sliced), kept for the month, and RANKED live at each redraw, so a bill tabled since greys the
## rows that can no longer be tabled.

## `focus` names a tax kind to put the cursor on in the window opened ("" for none).
signal go_requested(window_id: String, focus: String)

const GoalRead = preload("res://src/sim/goal_read.gd")
const GoalRows = preload("res://src/ui/goal_rows.gd")
const GoalTile = preload("res://src/ui/goal_tile.gd")
const Pledges = preload("res://src/sim/pledges.gd")
const OpinionK = preload("res://src/sim/opinion_constants.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")
const Num = preload("res://src/ui/num.gd")

## The goal the rows are for, and whether the page shows "What moves it" or the catalogue.
var goal := "deficit"
var _moves := true
## Which bloc the third tile follows: its place in the blocs by approval, weakest first. A second
## press on the tile walks to the next one.
var _bloc_rank := 0
## Whether the list shows every measure or its best few (goal_rows.gd); a new goal starts short.
var _all := false
var _list
var _tiles: HBoxContainer
var _group := ButtonGroup.new()
var _caption: Label
var _scroll: ScrollContainer
var _box: VBoxContainer
var _read = null
var _stamp := ""


func _init(list) -> void:
	_list = list
	name = "Goals"  # i18n: ok a node name, found by tests
	add_theme_constant_override("separation", PanelKit.ROW_SEPARATION)
	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", 8)
	add_child(_tiles)
	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	add_child(modes)
	var shown := ButtonGroup.new()
	for entry in [[true, Strings.t("What moves it")], [false, Strings.t("Catalogue")]]:
		var mode := PanelKit.sized(Button.new())
		mode.text = entry[1]
		mode.toggle_mode = true
		mode.button_group = shown
		mode.button_pressed = entry[0] == _moves
		mode.pressed.connect(_set_mode.bind(entry[0]))
		modes.add_child(mode)
	_caption = Label.new()
	_caption.theme_type_variation = PanelKit.UiTheme.CAPTION
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_caption)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_box)


func _set_mode(moves: bool) -> void:
	_moves = moves
	_stamp = ""


func _process(_delta: float) -> void:
	var panel = _list._panel
	if panel._state == null or not is_visible_in_tree():
		return
	# The catalogue's own parts follow the mode; this page's rows are the other half.
	var catalogue := not _moves
	_list._filters.visible = catalogue
	_list._header.get_parent().visible = catalogue
	_list._rows.get_parent().visible = catalogue
	_caption.visible = _moves
	_scroll.visible = _moves
	# The rows take the column's height while they are shown; the catalogue's own list takes it otherwise.
	size_flags_vertical = Control.SIZE_EXPAND_FILL if _moves else Control.SIZE_SHRINK_BEGIN
	if not _moves:
		return
	var stamp := _signature(panel._state)
	if stamp != _stamp:
		_stamp = stamp
		_redraw(panel)
	elif _read != null and not _read.done():
		GoalRead.step(_read)
		if _read.done():
			_stamp = ""
		else:
			_progress()


## What a redraw depends on, cheap enough for each frame: the day, the slot and the queue, the goal.
func _signature(state) -> String:
	var ns = state.player()
	return "%d|%d|%d|%s|%s|%s|%d|%d" % [state.year, state.month, state.day, goal, str(ns.tabled_bill), str(ns.bill_queue), _bloc_rank, ns.pledges.size()]


func _redraw(panel) -> void:
	var state = panel._state
	_read = GoalRead.list_for(_read, state, panel._loader)
	_rebuild_tiles(state, panel._loader)
	_caption.text = GoalRows.caption_of(goal)
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	if not _read.done():
		PanelKit.line(_box, "", PanelKit.Tone.DIM)
		_progress()
		return
	var rows := GoalRead.rank(_read.reads, goal, state, panel._loader)
	GoalRows.build(_box, rows, goal, state, panel._find_law, _pick, _all, _show_all)


## The list fills a measure a frame: say how far it has got.
func _progress() -> void:
	(_box.get_child(0) as Label).text = Strings.t("Reading the options: %s") % ("%d/%d" % [_read.reads.size(), _read.measures.size()])


## The tiles: the balance, unemployment, one bloc, and each promise on the books.
func _rebuild_tiles(state, loader) -> void:
	var ns = state.player()
	for child in _tiles.get_children():
		_tiles.remove_child(child)
		child.queue_free()
	var blocs: Array = OpinionK.BLOC_KEYS.duplicate()
	blocs.sort_custom(func(a, b) -> bool: return float(ns.bloc_approval.get(a, 0.0)) < float(ns.bloc_approval.get(b, 0.0)))
	var bloc: String = blocs[_bloc_rank % blocs.size()]
	var tiles := [
		["deficit", Strings.t("Deficit"), Strings.t("%s %%") % Num.f(float(ns.deficit_pct_gdp), 2), Strings.t("The budget deficit, % of GDP.")],
		["unemployment", Strings.t("Unemployment"), Strings.t("%s %%") % Num.f(float(ns.unemployment_pct), 2), Strings.t("The unemployment rate.")],
		["bloc:" + bloc, Labels.bloc(bloc), Strings.t("%s %%") % Num.f(float(ns.bloc_approval.get(bloc, 0.0)), 0), Strings.t("Support in this bloc. Press again for the next weakest.")],
	]
	for entry in Pledges.on_the_books(ns):
		var kept := not Pledges.in_breach(state, ns, entry)
		tiles.append(["field:" + String(entry["field"]), Strings.noun("pledges", loader.pledges, "pledge", "pledge_id", String(entry["pledge_id"]), "pledge_name", Pledges.name_of(loader, String(entry["pledge_id"]))),
			Strings.t("kept") if kept else Strings.t("broken"), Strings.t("A promise on the books.")])
	# The bloc tile follows the rank: a second press walks to the next weakest bloc and the goal with it.
	if goal.begins_with("bloc:"):
		goal = "bloc:" + bloc
	if not tiles.any(func(t) -> bool: return t[0] == goal):
		goal = "deficit"
	for t in tiles:
		var tile := GoalTile.new(t[0], t[1], t[2], t[3])
		tile.button_group = _group
		tile.button_pressed = t[0] == goal
		tile.pressed.connect(_pick_goal.bind(t[0]))
		_tiles.add_child(tile)


func _show_all() -> void:
	_all = true
	_stamp = ""


func _pick_goal(picked: String) -> void:
	# A second press on the bloc tile walks to the next weakest bloc.
	if picked == goal and picked.begins_with("bloc:"):
		_bloc_rank += 1
	goal = picked
	_all = false
	_stamp = ""


## A row pressed: a law opens its sheet beside the list; a budget line is set on the Budget tab and a
## tax rate in the Tax Code, on that tax's own row (the parent's ruling on QA's TAKE, #358).
func _pick(measure: Dictionary) -> void:
	if String(measure["kind"]) == "law":
		_list.select(String(measure["id"]))
	else:
		if String(measure["kind"]) == "rate":
			go_requested.emit("tax", String(measure["key"]))
		else:
			go_requested.emit("budget", "")
