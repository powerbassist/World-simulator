extends SceneTree

## Headless test: godot --headless --script res://tests/test_register_panel.gd
## Non-zero exit on any failure.
##
## V5.3 c' slice 1, the construction register's order form (docs/design/v5.3-c-register.md
## section 9; the author's pick "A pour commander"): a tab under Regions where the player
## picks a unit type, how many and where, reads what the regions' figures, the money and the
## dates become, and puts the programme in the finance bill.
##
## The author's rule for it, verbatim: "i want this scalable with other data in the future".
## So every type on the sheet comes from the catalogue (data/units/): the test swaps the
## catalogue for the fixture's at run time and the sheet shows the fixture's types with no
## other change. Every figure is the sim's (Units.preview, UnitPrice.quote).
##
## Driven through the real controls a frame apart (AGENTS.md: a Control built but not shown
## fails silently).

const Units = preload("res://src/sim/units.gd")
const UnitsLoader = preload("res://src/core/loaders/units_loader.gd")
const UnitPrice = preload("res://src/sim/unit_price.gd")
const FinanceRows = preload("res://src/sim/finance_rows.gd")
const Strings = preload("res://src/ui/strings.gd")
const Num = preload("res://src/ui/num.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const FIXTURE := "res://tests/fixtures/units"

var _failures: Array[String] = []
var _main
var _panel
var _frame := 0
var _spin
var _held_stock
var _money_before := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_panel = _main._windows.content("register")
			if _panel == null:
				_fail("no window registered as 'register'")
				_finish()
				return false
			_main._windows.open("register")
		4:
			_check_types_come_from_the_catalogue()
			_check_rows_are_filled_by_need()
			_check_the_dots_are_the_sims()
			_check_the_money_is_the_quote()
			var odds = _with_meta("odds")
			if odds == null or odds.theme_type_variation != UiTheme.CHIP_WARN:
				_fail("the overrun odds are not a warning chip")
			var press = _with_meta("table")
			if press == null or press.theme_type_variation != UiTheme.PRIMARY:
				_fail("the press is not the Primary button")
			if _with_meta("stock") == null:
				_fail("the picked region's stock line is missing")
		5:
			# A hand in the count box: the value moves, the sheet waits for the box to be left.
			_spin = _with_meta("count")
			_spin.get_line_edit().grab_focus()
			_spin.value = 3
		6:
			if not is_instance_valid(_spin) or not _spin.is_inside_tree() or not _spin.get_line_edit().has_focus():
				_fail("the sheet was rebuilt under the focused count box")
			_spin.get_line_edit().release_focus()
		8:
			_check_count_refills(3)
			# A law holds the slot: the press is refused before it, and says why.
			_main._state.player().tabled_bill = {"law_id": String(_main._loader.laws[0].id), "referendum": false,
				"vote_year": 2026, "vote_month": 1, "vote_day": 31}
			_panel.mark_dirty()
		10:
			_check_refused_before_the_press()
			_main._state.player().tabled_bill = {}
			_panel.mark_dirty()
		12:
			_press(_with_meta("table"))
		14:
			_check_tabled()
			# A save reads the bill back through JSON with its counts as floats (3 becomes 3.0):
			# the loaded programme is still the one held, never a second order of it.
			var ns = _main._state.player()
			_money_before = String(_with_meta("money").text)
			ns.tabled_bill = JSON.parse_string(JSON.stringify(ns.tabled_bill))
			_panel.mark_dirty()
		16:
			_check_held_after_a_load()
		17:
			# The region sheet's door opens the register on that region, the count placed THERE
			# (a region that is not the worst, so by need would put it elsewhere).
			_main._windows.open("region")
			var region_panel = _main._windows.content("region")
			region_panel.open_region_at(_other_region())
		19:
			_press(_with_meta("register_door"))
		21:
			_check_door_opened(_other_region())
			# A nation with no stock file is not offered the tab (a rule over data).
			var ns = _main._state.player()
			_held_stock = _main._loader.unit_stock[ns.id]
			_main._loader.unit_stock.erase(ns.id)
			# What a panel offers changes while the domain stays: the workspace closes and the next
			# tab opened is in the SAME domain (the register's), so the row is read again, not kept.
			# A load swaps in a fresh main today (GameReload.swap); this pins the row for any other path.
			_main._windows.close_all()
		22:
			_main._windows.open("finances")
		23:
			if _main._windows.tab_ids().has("register"):
				_fail("the register tab is offered to a nation with no stock file")
			_main._loader.unit_stock[_main._state.player().id] = _held_stock
			_main._windows.close_all()
		24:
			_main._windows.open("finances")
		25:
			if not _main._windows.tab_ids().has("register"):
				_fail("the register tab is missing once the stock file is back")
			# A new type is a data edit: the fixture's catalogue replaces the shipped one.
			UnitsLoader.load_units(_main._loader, FIXTURE)
			_panel.setup(_main._state, _main._loader)
			_main._windows.open("register")
		27:
			_check_types_come_from_the_catalogue()
			_finish()
	return false


func _offered() -> Array:
	var out: Array = []
	var ns = _main._state.player()
	for row in Units.catalogue(_main._loader):
		if String(row.get("payoff", "")) == "capacity" and Units.offered(_main._loader, ns.id, String(row["id"])):
			out.append(String(row["id"]))
	return out


func _check_types_come_from_the_catalogue() -> void:
	var chips := _all_with_meta("type_chip")
	var ids: Array = []
	for chip in chips:
		ids.append(String(chip.get_meta("type_chip")))
	if ids != _offered():
		_fail("type chips %s are not the catalogue's offered types %s" % [ids, _offered()])
		return
	for chip in chips:
		var row: Dictionary = Units.row(_main._loader, String(chip.get_meta("type_chip")))
		if not String(chip.text).begins_with(Strings.row_name("units", row)):
			_fail("chip '%s' does not carry its type's name" % chip.text)


func _type() -> String:
	return String(_panel.selected_type())


func _check_rows_are_filled_by_need() -> void:
	var ns = _main._state.player()
	var want: Array = Units.fill_by_need(ns, _main._loader, _type(), 1)
	if _panel.rows() != want:
		_fail("the sheet's rows %s are not by need %s" % [_panel.rows(), want])


func _check_the_dots_are_the_sims() -> void:
	var ns = _main._state.player()
	var dots = _with_meta("dots")
	if dots == null:
		_fail("no dot plot")
		return
	var placed := {}
	for r in _panel.rows():
		placed[String(r["region"])] = int(r["units"])
	var after: Dictionary = Units.preview(ns, _main._loader, _type(), placed)
	var drawn: Array = dots.data()
	var holding := 0
	for region in _main._loader.regions.get(ns.id, []):
		if Units.start_capacity(_main._loader, ns.id, _type(), region.id) > 0.0:
			holding += 1
	if drawn.size() != holding:
		_fail("the dot plot draws %d regions, %d hold the type" % [drawn.size(), holding])
	for d in drawn:
		var id := String(d["id"])
		if absf(float(d["before"]) - Units.shown_figure(ns, _main._loader, _type(), id)) > 1e-9 \
				or absf(float(d["after"]) - float(after[id])) > 1e-9:
			_fail("dot for %s is not the sim's before/after" % id)


func _check_the_money_is_the_quote() -> void:
	var ns = _main._state.player()
	var q: Dictionary = UnitPrice.quote(_main._state, ns, _main._loader, {"type": _type(), "op": "build", "rows": _panel.rows()})
	var money = _with_meta("money")
	if money == null:
		_fail("no money line")
		return
	for v in [float(q["lo_eur_m"]) / 1000.0, float(q["hi_eur_m"]) / 1000.0]:
		if not String(money.text).contains(Num.f(v, 2)):
			_fail("money line '%s' lacks the quote's %s" % [money.text, Num.f(v, 2)])
	if _with_meta("cash") == null or _with_meta("range") == null:
		_fail("the money has no range bar or no bars a year")


func _set_count(n: int) -> void:
	var spin = _with_meta("count")
	if spin == null:
		_fail("no count control")
		return
	spin.value = n


func _check_count_refills(n: int) -> void:
	var total := 0
	for r in _panel.rows():
		total += int(r["units"])
	if total != n:
		_fail("count %d placed %d units" % [n, total])
	if _panel.rows() != Units.fill_by_need(_main._state.player(), _main._loader, _type(), n):
		_fail("a new count did not refill by need")


func _check_refused_before_the_press() -> void:
	var press = _with_meta("table")
	var why = _with_meta("refusal")
	if press == null or not press.disabled:
		_fail("the press is not greyed while a law holds the slot")
	if why == null or not why.visible or String(why.text) == "":
		_fail("the refusal is not said before the press")


func _check_tabled() -> void:
	var ns = _main._state.player()
	var units: Array = (ns.tabled_bill.get("finance", {}) as Dictionary).get(FinanceRows.UNITS, [])
	if units.size() != 1 or String(units[0]["type"]) != _type() or units[0]["rows"] != _panel.rows():
		_fail("the press did not table the programme: %s" % [units])
	if _with_meta("in_bill") == null:
		_fail("the sheet does not say the programme is in the finance bill")
	var press = _with_meta("table")
	if press == null or not press.disabled:
		_fail("the press stays live for a programme the bill already holds")



func _check_held_after_a_load() -> void:
	var press = _with_meta("table")
	if press == null or not press.disabled:
		_fail("after a load the press is live again for the programme the bill holds")
	var why = _with_meta("refusal")
	if why == null or not String(why.text).contains(tr("This programme is already in the finance bill.")):
		_fail("after a load the sheet does not say the programme is already held: '%s'" % ("" if why == null else why.text))
	var money = _with_meta("money")
	if money == null or String(money.text) != _money_before:
		_fail("after a load the quote counts the held programme as an earlier order: '%s' was '%s'" % ["" if money == null else money.text, _money_before])
	var line = _with_meta("in_bill")
	if line == null or String(line.text).contains(".0 "):
		_fail("the held count is printed as a float after a load")

func _worst_region() -> String:
	var rows: Array = Units.fill_by_need(_main._state.player(), _main._loader, _offered()[0], 1)
	return String(rows[0]["region"]) if not rows.is_empty() else ""


func _other_region() -> String:
	var ns = _main._state.player()
	for region in _main._loader.regions.get(ns.id, []):
		if String(region.id) != _worst_region() and Units.start_capacity(_main._loader, ns.id, _offered()[0], region.id) > 0.0:
			return String(region.id)
	return ""


func _check_door_opened(region_id: String) -> void:
	if not _main._windows.is_open("register"):
		_fail("the door did not open the register")
	if String(_panel.selected_region()) != region_id:
		_fail("the register opened on %s, not %s" % [_panel.selected_region(), region_id])
	var rows: Array = _panel.rows()
	if rows.size() != 1 or String(rows[0]["region"]) != region_id:
		_fail("Build here placed %s, not the count in %s" % [rows, region_id])


func _press(button) -> void:
	if button == null:
		_fail("button to press not found")
		return
	if button.disabled:
		_fail("button '%s' is disabled" % button.text)
		return
	button.pressed.emit()


func _all_with_meta(key: String, from: Node = null) -> Array:
	var out: Array = []
	var start: Node = from if from != null else _panel
	if start.has_meta(key) and start.is_visible_in_tree():
		out.append(start)
	for child in start.get_children():
		out.append_array(_all_with_meta(key, child))
	return out


func _with_meta(key: String):
	var found := _all_with_meta(key, _main)
	return found[0] if not found.is_empty() else null


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_register_panel: OK")
		quit(0)
	else:
		for f in _failures:
			push_error("FAIL " + f)
		quit(1)
