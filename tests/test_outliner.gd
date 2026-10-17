extends SceneTree

## Headless test: godot --headless --script res://tests/test_outliner.gd
## Non-zero exit on any failure.
##
## V4.8b. The outliner is a register (src/ui/outliner_readings.gd), so its walker is
## the strip walker's shape (tests/test_strip_readings.gd): every section resolves
## and reads its state rather than a typed figure, absence is a hidden section and
## never a row of zeros, every row names a window the game really registers, and
## the one ordering and the one cap it owns are pinned.
##
## The window half is below the register's checks: the panel draws exactly the
## visible sections, a row click asks main.gd for the row's window, and main.gd
## registers the window and the action bar lists it. Driven a frame at a time
## (docs/engine-decision.md: a Control outside the tree is half-dead).

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const OutlinerReadings = preload("res://src/ui/outliner_readings.gd")
const StripReadings = preload("res://src/ui/strip_readings.gd")
const Companies = preload("res://src/sim/companies.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const OutlinerPanel = preload("res://src/ui/outliner_panel.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []
var _loader
var _frame := 0
var _full_panel
var _empty_panel
var _requested: Array[String] = []


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	if _frame == 2:
		_check_the_register()
		_build_the_panels()
		return false
	if _frame < 4:
		return false  # the panels' own _process refreshes them
	_check_the_panel()
	_check_main_registers_the_window()
	_finish()
	return false


func _check_the_register() -> void:
	_check_every_section_resolves()
	_check_absence_hides_a_section()
	_check_the_agenda_is_the_pinned_entries()
	_check_every_input_is_live()
	_check_every_row_opens_a_real_window()
	_check_goods_order_matches_the_strip()
	_check_the_row_cap()
	_check_the_people_section()


func _new_state():
	var state = GameState.new_game(_loader, "FRA")
	if not state.errors.is_empty():
		_fail("new_game reported %s" % [state.errors])
	return state


# -- Staging ------------------------------------------------------------------

## A programme entry the content pins, live on the register.
func _pinned_entry() -> Dictionary:
	for entry in _loader.programme:
		if bool(entry.get("pinned", false)):
			return entry
	_fail("no programme entry is pinned -- the agenda section has nothing to show")
	return {}


func _unpinned_entry() -> Dictionary:
	for entry in _loader.programme:
		if not bool(entry.get("pinned", false)):
			return entry
	_fail("every programme entry is pinned -- the pinned filter cannot be tested")
	return {}


func _stage_entry(ns, entry: Dictionary) -> void:
	ns.programme.append({
		"entry_id": String(entry["id"]), "chosen_term": 0, "months_live": 0,
		"status": "active", "concluded_term": -1, "concluded_term_month": -1,
	})


func _stage_failing_firm(ns) -> void:
	var major = Companies.majors_of(_loader, ns.id)[0]
	var live: Dictionary = ns.companies.get(major.id, {})
	live["failed"] = true
	live["rescue_months_left"] = 3
	ns.companies[major.id] = live


func _stage_short_good(ns, index: int, coverage_pct: float) -> String:
	var good_id := String(_loader.commodity_goods.keys()[index])
	if ns.commodity_state.is_empty():
		ns.commodity_state = {"demand": {}, "output": {}, "trade": {}}
	ns.commodity_state["demand"][good_id] = 100.0
	ns.commodity_state["output"][good_id] = coverage_pct
	ns.commodity_state["trade"][good_id] = 0.0
	return good_id


func _person_ids() -> Array:
	# person_by_id, the flat register -- loader.people is keyed by NATION.
	var ids: Array = _loader.person_by_id.keys()
	ids.sort()
	return ids


## A foreign bid on a major, the three scalars industry.gd::_bids writes
## (bid_bidder is "NATION|bidder id").
func _stage_bid(ns) -> void:
	var majors: Array = Companies.majors_of(_loader, ns.id)
	var major = majors[1] if majors.size() > 1 else majors[0]
	var live: Dictionary = ns.companies.get(major.id, {})
	live["bid_bidder"] = "DEU|walker_bidder"
	live["bid_price_eur_bn"] = 12.5
	live["bid_months_left"] = 4
	ns.companies[major.id] = live


func _stage_everything(state) -> void:
	var ns = state.player()
	_stage_entry(ns, _pinned_entry())
	_stage_failing_firm(ns)
	_stage_bid(ns)
	_stage_short_good(ns, 0, 10.0)
	ns.person_grudges[String(_person_ids()[0])] = 0.4


# -- Checks -------------------------------------------------------------------

func _check_every_section_resolves() -> void:
	var state = _new_state()
	_stage_everything(state)
	for section in OutlinerReadings.SECTIONS:
		if not OutlinerReadings.CAPTIONS.has(section):
			_fail("'%s' has no caption" % section)
		if not OutlinerReadings.INPUTS.has(section):
			_fail("'%s' declares no inputs" % section)
		var r: Dictionary = OutlinerReadings.read(section, state, _loader)
		for key in ["title", "rows", "visible"]:
			if not r.has(key):
				_fail("'%s' returned no '%s'" % [section, key])
				return
		if not bool(r["visible"]) or (r["rows"] as Array).is_empty():
			_fail("'%s' staged with something in it but shows nothing" % section)
		for row in (r["rows"] as Array):
			for key in ["text", "tone", "window"]:
				if not row.has(key):
					_fail("a '%s' row has no '%s'" % [section, key])
			if String(row["text"]).is_empty():
				_fail("a '%s' row has no text" % section)


## A new game has nothing pinned: every section is hidden, never a row of zeros.
func _check_absence_hides_a_section() -> void:
	var state = _new_state()
	for section in OutlinerReadings.SECTIONS:
		var r: Dictionary = OutlinerReadings.read(section, state, _loader)
		if bool(r["visible"]) or not (r["rows"] as Array).is_empty():
			_fail("'%s' shows %s on a fresh game -- absence must hide the section" % [section, r["rows"]])


## `pinned` is the content's flag (data/programme/*.json): a running entry that is
## not pinned does not ride the outliner.
func _check_the_agenda_is_the_pinned_entries() -> void:
	var state = _new_state()
	var ns = state.player()
	_stage_entry(ns, _unpinned_entry())
	if bool(OutlinerReadings.read("agenda", state, _loader)["visible"]):
		_fail("an unpinned running entry rides the outliner")
	_stage_entry(ns, _pinned_entry())
	var rows: Array = OutlinerReadings.read("agenda", state, _loader)["rows"]
	if rows.size() != 1:
		_fail("one pinned and one unpinned running entry give %d agenda rows, expected 1" % rows.size())
	var name_text := String(_pinned_entry().get("name", _pinned_entry()["id"]))
	if rows.size() == 1 and not String(rows[0]["text"]).begins_with(name_text):
		_fail("the agenda row reads '%s', not the entry's name '%s'" % [rows[0]["text"], name_text])


func _snapshot(section: String, state) -> String:
	return JSON.stringify(OutlinerReadings.read(section, state, _loader))


## Perturb each declared input of a staged section and require the section to
## move: a row typed rather than read from the state fails here.
func _check_every_input_is_live() -> void:
	# agenda: the figure the entry's progress reads.
	var state = _new_state()
	var ns = state.player()
	var entry := _pinned_entry()
	_stage_entry(ns, entry)
	var before := _snapshot("agenda", state)
	var field := String(entry["current_value"])
	if not (field in ns):
		_fail("the pinned entry reads '%s', which NationState does not have" % field)
	else:
		ns.set(field, float(ns.get(field)) + 9.0)
		if _snapshot("agenda", state) == before:
			_fail("agenda did not move when '%s' changed -- it is not read from it" % field)

	# firms: the rescue window counts down.
	state = _new_state()
	ns = state.player()
	_stage_failing_firm(ns)
	before = _snapshot("firms", state)
	var major = Companies.majors_of(_loader, ns.id)[0]
	ns.companies[major.id]["rescue_months_left"] = 1
	if _snapshot("firms", state) == before:
		_fail("firms did not move when the rescue window changed")

	# goods: coverage.
	state = _new_state()
	ns = state.player()
	var good_id := _stage_short_good(ns, 0, 10.0)
	before = _snapshot("goods", state)
	ns.commodity_state["output"][good_id] = 20.0
	if _snapshot("goods", state) == before:
		_fail("goods did not move when a good's output changed")

	# people: the grudge, and the loyalty, each on its own.
	state = _new_state()
	ns = state.player()
	var pid := String(_person_ids()[0])
	ns.person_grudges[pid] = 0.3
	before = _snapshot("people", state)
	ns.person_grudges[pid] = 0.6
	if _snapshot("people", state) == before:
		_fail("people did not move when a grudge changed")
	state = _new_state()
	ns = state.player()
	ns.person_loyalty[pid] = -0.3
	before = _snapshot("people", state)
	ns.person_loyalty[pid] = -0.6
	if _snapshot("people", state) == before:
		_fail("people did not move when a loyalty changed")


## Every row opens a window main.gd really registers -- read off main.gd's own
## register() calls, the strip walker's scan, so a renamed window fails here and
## not as a row that opens nothing.
func _check_every_row_opens_a_real_window() -> void:
	var registered := {}
	var src := FileAccess.get_file_as_string("res://src/ui/main.gd")
	for m in RegEx.create_from_string("_windows\\.register\\(\"([a-z_]+)\"").search_all(src):
		registered[m.get_string(1)] = true
	if registered.is_empty():
		_fail("read no window ids out of main.gd -- the scan moved")
		return
	var state = _new_state()
	_stage_everything(state)
	var firm_rows: Array = OutlinerReadings.read("firms", state, _loader)["rows"]
	if firm_rows.size() != 2:
		_fail("a standing bid and a failing major give %d firm rows, expected 2" % firm_rows.size())
	for section in OutlinerReadings.SECTIONS:
		for row in (OutlinerReadings.read(section, state, _loader)["rows"] as Array):
			if not registered.has(String(row["window"])):
				_fail("a '%s' row opens '%s', which main.gd registers no window for" % [section, row["window"]])


## Worst first: the outliner, the strip's Supplies figure and the commodities
## window's SHORTAGES section share one order.
func _check_goods_order_matches_the_strip() -> void:
	var state = _new_state()
	var ns = state.player()
	_stage_short_good(ns, 1, 20.0)
	var worst_id := _stage_short_good(ns, 0, 5.0)
	var rows: Array = OutlinerReadings.read("goods", state, _loader)["rows"]
	if rows.size() != 2:
		_fail("two short goods give %d rows" % rows.size())
		return
	var worst_name := String(_loader.commodity_goods[worst_id].name)
	if not String(rows[0]["text"]).begins_with(worst_name):
		_fail("the first short good is '%s', not the worst, %s" % [rows[0]["text"], worst_name])
	var strip_text := String(StripReadings.read("commodities", state, _loader)["text"])
	if not strip_text.begins_with(worst_name):
		_fail("the strip names '%s' as worst but the outliner's first row is %s" % [strip_text, worst_name])


func _check_the_row_cap() -> void:
	var state = _new_state()
	var ns = state.player()
	var ids := _person_ids()
	var staged := OutlinerReadings.ROW_CAP + 2
	if ids.size() < staged:
		_fail("only %d people in the content, the cap test needs %d" % [ids.size(), staged])
		return
	for i in staged:
		ns.person_grudges[String(ids[i])] = 0.2 + 0.01 * i
	var rows: Array = OutlinerReadings.read("people", state, _loader)["rows"]
	if rows.size() != OutlinerReadings.ROW_CAP + 1:
		_fail("%d worried people give %d rows, expected the cap plus one overflow row" % [staged, rows.size()])
		return
	if String(rows[-1]["text"]) != "+2 more":
		_fail("the overflow row reads '%s', not '+2 more'" % rows[-1]["text"])
	if int(rows[-1]["tone"]) != PanelKit.Tone.DIM:
		_fail("the overflow row is not dim")


func _check_the_people_section() -> void:
	var state = _new_state()
	var ns = state.player()
	var ids := _person_ids()
	ns.person_grudges[String(ids[0])] = 0.2
	ns.person_grudges[String(ids[1])] = 0.5
	ns.person_loyalty[String(ids[2])] = 0.4    # moved, but a friend: not a worry
	ns.person_loyalty[String(ids[3])] = -0.35  # turned against the term: a worry
	ns.person_grudges[String(ids[4])] = 0.01   # under MOVED_AT: not moved at all
	var r: Dictionary = OutlinerReadings.read("people", state, _loader)
	var rows: Array = r["rows"]
	if rows.size() != 3:
		_fail("three worried people give %d rows: %s" % [rows.size(), rows])
		return
	if OutlinerReadings.moved_count(ns) != 4:
		_fail("moved_count is %d, expected 4 (two grudges, a friend, a turncoat)" % OutlinerReadings.moved_count(ns))
	if not String(r["title"]).contains("4 moved"):
		_fail("the section title reads '%s' -- it should carry the moved count" % r["title"])
	var first_name: String = _loader.person_name(String(ids[1]))
	if not String(rows[0]["text"]).begins_with(first_name):
		_fail("the largest grudge is not first: '%s' (expected %s)" % [rows[0]["text"], first_name])


func _build_the_panels() -> void:
	root.theme = UiTheme.build()
	var state = _new_state()
	_stage_everything(state)
	_full_panel = OutlinerPanel.new()
	root.add_child(_full_panel)
	_full_panel.setup(state, _loader)
	_full_panel.window_requested.connect(func(id: String): _requested.append(id))
	_empty_panel = OutlinerPanel.new()
	root.add_child(_empty_panel)
	_empty_panel.setup(_new_state(), _loader)


## Every row the panel draws, in order: the Labels that take the pointer.
func _row_labels(panel) -> Array:
	var out: Array = []
	var stack: Array = [panel._body]
	while not stack.is_empty():
		var node: Node = stack.pop_front()
		for child in node.get_children():
			if child is Label and (child as Label).mouse_filter == Control.MOUSE_FILTER_STOP:
				out.append(child)
			stack.append(child)
	return out


func _check_the_panel() -> void:
	# One drawn row per register row, in section order -- the panel adds none of
	# its own and drops none.
	var state = _full_panel._state
	var expected: Array = []
	for section in OutlinerReadings.SECTIONS:
		for row in (OutlinerReadings.read(section, state, _loader)["rows"] as Array):
			expected.append(row)
	var labels := _row_labels(_full_panel)
	if labels.size() != expected.size() or expected.is_empty():
		_fail("the panel draws %d rows, the register has %d" % [labels.size(), expected.size()])
		return
	for i in labels.size():
		if (labels[i] as Label).text != String(expected[i]["text"]):
			_fail("row %d reads '%s', the register says '%s'" % [i, (labels[i] as Label).text, expected[i]["text"]])

	# A click asks for the row's window; a release or a right click does not.
	for i in labels.size():
		_requested.clear()
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		(labels[i] as Label).gui_input.emit(press)
		if _requested != [String(expected[i]["window"])]:
			_fail("clicking row %d asked for %s, expected '%s'" % [i, _requested, expected[i]["window"]])
	_requested.clear()
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	(labels[0] as Label).gui_input.emit(release)
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	(labels[0] as Label).gui_input.emit(right)
	if not _requested.is_empty():
		_fail("a release or a right click opened a window: %s" % [_requested])

	# Nothing pinned: one line that says so, and no clickable row.
	if not _row_labels(_empty_panel).is_empty():
		_fail("the empty outliner draws clickable rows")
	var said := false
	var stack: Array = [_empty_panel._body]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is Label and (node as Label).text == OutlinerPanel.NOTHING_PINNED:
			said = true
	if not said:
		_fail("the empty outliner does not say '%s'" % OutlinerPanel.NOTHING_PINNED)

	# A refresh after the state moves redraws (mark_dirty is what main.gd's month
	# tick calls); a panel that never rebuilt would show last month's firm.
	state.player().companies.clear()
	_full_panel.mark_dirty()
	_full_panel._process(0.0)
	if _row_labels(_full_panel).size() >= labels.size():
		_fail("the outliner did not redraw after mark_dirty -- it shows a firm that is gone")


func _check_main_registers_the_window() -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/main.gd")
	if not src.contains("_windows.register(\"outliner\""):
		_fail("main.gd registers no 'outliner' window")
	if not src.contains("_entry(\"outliner\""):
		_fail("the action bar does not list the outliner")
	if not src.contains("window_requested.connect"):
		_fail("main.gd does not connect the outliner's window_requested -- a row click opens nothing")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_outliner: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
