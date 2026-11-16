extends SceneTree

## Headless test: godot --headless --script res://tests/test_sectors_retro.gd
## Non-zero exit on any failure.
##
## A sector's tab, five finds of the retro UI review (2026-11-17):
##   - item 6: the goods table's trade column said "this month" over a figure a year (the
##     month's trade times twelve, GoodsRead.trade_eur_bn_year);
##   - item 10: a good filtered on that the table no longer shows (a month later it left the
##     rows) emptied the table under its headings;
##   - item 8: a press on the programme's slider rebuilt the tab and freed the slider under
##     the drag;
##   - item 9: "Put it in the finance bill" stood disabled with no reason while a programme
##     runs (every stop in data asks for no programme running);
##   - item 7: a load kept the discarded game's filter, firm, picked stop and refusal.
## Driven through the real main scene, a frame at a time.

const SaveManager = preload("res://src/core/save_manager.gd")
const SectorGoods = preload("res://src/ui/sector_goods.gd")
const SectorProgramme = preload("res://src/ui/sector_programme.gd")
const Strings = preload("res://src/ui/strings.gd")

const SLOT := "__test_sectors_retro__"
const TAB := "sector_industry"

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _slider: HSlider
## A freed Object compares equal to null: whether a slider was found is kept apart.
var _found := false
var _drag_value := -1


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._windows.content(TAB)
			_main._windows.open(TAB)
		4:
			_check_trade_caption()
			_panel._good_filter = "__a_good_no_longer_shown__"
			_panel._dirty = true
		6:
			_check_filter_off_the_rows()
			_start_drag()
		8:
			_check_drag_kept_its_slider()
			if is_instance_valid(_slider):
				# Captured before the release: the rebuild frees the slider, and a check that
				# returned on a freed slider never asserted (#393 pass 2, T8).
				_drag_value = int(_slider.value)
				_slider.drag_ended.emit(true)
		10:
			_check_drag_end_rebuilds()
			_check_disabled_go_says_why()
			_check_hidden_mid_drag_releases()
			_check_unmoved_drag_picks_nothing()
			_step_focused("slider")
		12:
			_check_focus_kept("slider")
			_step_focused("box")
		14:
			_check_focus_kept("box")
			_check_live_readouts()
		16:
			var companies = _main._windows.content("companies")
			companies._last_refusal = "refused in the old game"
			companies._open_sector = "x"
			companies._open_firm = "x"
			companies._open_body = "x"
			companies._open_ledger = "x"
			companies._focus_verb = "x"
			_panel._good_filter = "x"
			_panel._firm_id = "x"
			_panel._prog_pick = 1
			_panel._last_refusal = "refused in the old game"
			var error := SaveManager.save_game(_main._state, _main._clock, SLOT)
			if error != "":
				_fail("could not save: %s" % error)
			_main._on_load_requested(SLOT)
			_check_load_forgets()
			if companies._last_refusal != "" or companies._open_sector != "" or companies._open_firm != "" 					or companies._open_body != "" or companies._open_ledger != "" or companies._focus_verb != "":
				_fail("a load keeps the discarded game's Companies picks or refusal")
			_cleanup()
			_main.queue_free()
		18:
			_finish()
			return true
	return false


func _grid() -> GridContainer:
	for node in _panel.find_children("*", "GridContainer", true, false):
		if (node as GridContainer).columns == 4:
			return node
	return null


func _check_trade_caption() -> void:
	var grid := _grid()
	if grid == null:
		_fail("premise: the industry tab has no goods table")
		return
	var caption := (grid.get_child(2) as Label).text
	if caption.contains("month") or not caption.contains("year"):
		_fail("the trade column reads '%s' over a figure a year" % caption)


func _check_filter_off_the_rows() -> void:
	var grid := _grid()
	if grid == null or grid.get_child_count() <= 4:
		_fail("a filter on a good the table no longer shows empties the table")
	if _panel._good_filter != "":
		_fail("the filter on a good no longer shown stays set ('%s'): no chip shows it pressed" % _panel._good_filter)


func _start_drag() -> void:
	for node in _panel.find_children("*", "HSlider", true, false):
		if node.has_meta("programme"):
			_slider = node
	if _slider == null:
		_fail("premise: the industry tab has no programme slider")
		return
	_found = true
	_slider.drag_started.emit()
	_slider.value = 1.0 if _slider.value != 1.0 else 2.0


func _check_drag_kept_its_slider() -> void:
	if not _found:
		return
	if not is_instance_valid(_slider) or not _slider.is_inside_tree() or _slider.is_queued_for_deletion():
		_fail("the programme's slider was freed under the drag")


func _check_drag_end_rebuilds() -> void:
	if not _found:
		return
	if _panel._prog_pick != _drag_value:
		_fail("the drag's end did not keep the picked stop (%d, slider at %d)" % [_panel._prog_pick, _drag_value])
	if is_instance_valid(_slider) and not _slider.is_queued_for_deletion():
		_fail("the drag's end did not rebuild the tab for the picked stop")


func _check_disabled_go_says_why() -> void:
	var ns = _main._state.player()
	var list: Array = SectorProgramme.stops(_main._loader, "industry")
	var before: Dictionary = (ns.sector_investment["industry"] as Dictionary).duplicate()
	ns.sector_investment["industry"] = {"intensity": float(list[1]["intensity"]), "capital": 0.0}
	_panel._prog_pick = list.size() - 1
	_panel._refresh()
	var go: Button = null
	for node in _panel.find_children("*", "Button", true, false):
		if node.has_meta("table_programme"):
			go = node
	if go == null:
		_fail("premise: no 'Put it in the finance bill' for another stop")
	elif not go.disabled:
		_fail("premise: 'Put it in the finance bill' is open while a programme runs")
	else:
		var said := false
		for node in _panel.find_children("*", "Label", true, false):
			if (node as Label).has_meta("programme_refusal") and (node as Label).text != "":
				said = true
		if not said:
			_fail("'Put it in the finance bill' is disabled and nothing says why")
	ns.sector_investment["industry"] = before
	_panel._prog_pick = -1


## A tab hidden while its slider is held never sees the release: it must not stay frozen.
func _check_hidden_mid_drag_releases() -> void:
	for node in _panel.find_children("*", "HSlider", true, false):
		if node.has_meta("programme"):
			(node as HSlider).drag_started.emit()
	_main._windows.open("companies")
	_main._windows.open(TAB)
	if _panel._dragging:
		_fail("a tab hidden under a held slider stays frozen (no rebuild until a load)")


func _programme(meta: String) -> Control:
	for node in _panel.find_children("*", "", true, false):
		if node.has_meta(meta) and not (node as Node).is_queued_for_deletion():
			return node
	return null


## T4: a press and release that moved nothing picks nothing (the stop "as it stands" stays).
func _check_unmoved_drag_picks_nothing() -> void:
	var slider := _programme("programme") as HSlider
	if slider == null:
		_fail("premise: no programme slider to press")
		return
	_panel._prog_pick = -1
	slider.drag_started.emit()
	slider.drag_ended.emit(false)
	if _panel._prog_pick != -1:
		_fail("a press on the slider that moved nothing picked stop %d" % _panel._prog_pick)
	if _panel._dragging:
		_fail("a release that moved nothing left the tab held")


## T5: a keyboard step (or a SpinBox arrow) rebuilds the tab; the new control takes the focus.
func _step_focused(which: String) -> void:
	if which == "slider":
		var slider := _programme("programme") as HSlider
		slider.grab_focus()
		slider.value = slider.value + 1.0 if slider.value < slider.max_value else slider.value - 1.0
	else:
		var box := _programme("programme_box") as SpinBox
		box.get_line_edit().grab_focus()
		box.value = box.value + box.step


func _check_focus_kept(which: String) -> void:
	var owner: Control = _panel.get_viewport().gui_get_focus_owner()
	var ok := false
	if owner != null and _panel.is_ancestor_of(owner):
		ok = owner.has_meta("programme") if which == "slider" else (owner.get_parent() is SpinBox and owner.get_parent().has_meta("programme_box"))
	if not ok:
		_fail("a keyboard step on the programme's %s lost the focus to %s" % [which, owner])


## T5: under a mouse drag the tab does not rebuild, so the price and the stop's name follow live.
func _check_live_readouts() -> void:
	var slider := _programme("programme") as HSlider
	var box := _programme("programme_box") as SpinBox
	var name := _programme("programme_name") as Label
	if slider == null or box == null or name == null:
		_fail("the programme row has no price box or no stop name to follow the drag")
		return
	var ns = _main._state.player()
	var list: Array = SectorProgramme.stops(_main._loader, "industry")
	var to := 0 if int(slider.value) != 0 else 1
	slider.drag_started.emit()
	slider.value = to
	var want := SectorProgramme.price(_main._state, _main._loader, ns, list, "industry", to)
	if absf(box.value - want) > 0.011:
		_fail("under a drag the price stays %s, not the dragged stop's %s" % [box.value, want])
	var word := Strings.row_name("investment-actions", list[to]["action"]) if to > 0 else Strings.t("No programme")
	if name.text != word:
		_fail("under a drag the stop's name reads '%s', not '%s'" % [name.text, word])
	slider.drag_ended.emit(true)


func _check_load_forgets() -> void:
	if _panel._good_filter != "" or _panel._firm_id != "" or _panel._prog_pick != -1 or _panel._last_refusal != "":
		_fail("a load keeps the discarded game's filter, firm, picked stop or refusal")


func _cleanup() -> void:
	for p in [SaveManager._path_for(SLOT), SaveManager._path_for(SLOT) + SaveManager.TEMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_sectors_retro: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
