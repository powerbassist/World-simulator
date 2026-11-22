extends SceneTree

## Headless test: godot --headless --script res://tests/test_works_page.gd
## Non-zero exit on any failure.
##
## G3 S4 PR 2c, Public works "A calendrier" (the author's pick, works-a-calendar.png): every
## work is a lane on one axis of years, with today and the end of the term on it; the works'
## bill by year under the same axis; the picked work's sheet beside it with the screen's one
## filled button. Every figure is read, never estimated: a work's opening is the month the
## diary gives it (Calendar.fixed_dates), an offer's is today plus its build "if started now",
## the bill is the register's (Projects.bill_pct_gdp) and the term's end is the vote's date.
##
## Driven through the real page and its buttons a frame apart.

const Projects = preload("res://src/sim/projects.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const Trends = preload("res://src/ui/trends.gd")
const WorksRows = preload("res://src/ui/works_rows.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const WindowManager = preload("res://src/ui/window_manager.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _page
var _started := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_page = _main._windows.content("projects")
			if _page == null:
				_fail("no window registered as 'projects'")
				_finish()
				return false
			_main._windows.open("projects")
		4:
			_check_offers()
			_check_page()
			_check_axes()
			_check_marks()
			_started = String(_page.picked())
			_press(_with_meta("works_go", _page))
		6:
			_check_building()
			_press(_with_meta("works_cancel_" + _started, _page))
		8:
			if not Projects.is_building(_state().player(), _started):
				_fail("Cancel... applied before its confirm")
			if _page._confirm == null or not _page._confirm.visible:
				_fail("Cancel... did not ask its confirm")
			else:
				_page._confirm.confirmed.emit()
		10:
			if Projects.is_building(_state().player(), _started):
				_fail("the confirm's yes did not cancel the work")
			_state().player().last_project_result = {"refused": true, "action_id": String(_main._loader.project_actions[0].id)}
			_page.mark_dirty()
		12:
			_check_refusal()
			_finish()
	return false


func _state():
	return _main._state


func _now() -> int:
	return int(_state().year) * 12 + int(_state().month)


## Every offer is a row: it opens "if started now" at today plus its build, its cost a year
## in bn is its share of GDP times GDP, and its region is the sim's.
func _check_offers() -> void:
	var ns = _state().player()
	var rows: Array = WorksRows.rows(_state(), _main._loader, ns)
	var offered := Projects.available(_state(), ns, _main._loader.project_actions).filter(
		func(a): return String(a.effects.get("project", {}).get("op", "")) == "start")
	var offers := rows.filter(func(r): return String(r["state"]) == WorksRows.OFFER)
	if offers.size() != offered.size() or offers.is_empty():
		_fail("%d offer rows for the sim's %d offers" % [offers.size(), offered.size()])
		return
	for r in offers:
		var terms := Projects.terms_of(_main._loader, String(r["id"]))
		if int(r["opens"]) != _now() + int(terms["build_months"]):
			_fail("%s opens at %d, not today + its build %d" % [r["id"], int(r["opens"]), _now() + int(terms["build_months"])])
		var bn := float(terms["cost_pct_gdp"]) / 100.0 * float(ns.gdp_eur_bn)
		if absf(float(r["cost_bn"]) - bn) > 1e-6 or absf(float(r["all_bn"]) - bn * int(terms["build_months"]) / 12.0) > 1e-6:
			_fail("%s costs %s a year, %s in all; the terms say %s a year" % [r["id"], r["cost_bn"], r["all_bn"], bn])
		if String(r["region"]) != _region_name(Projects.site_region(_main._loader, String(ns.id), String(r["id"]))):
			_fail("%s lands in '%s', the sim's '%s'" % [r["id"], r["region"], Projects.site_region(_main._loader, String(ns.id), String(r["id"]))])


## One lane a row, the first offer picked; the picked work's sheet carries the screen's ONE
## filled button, every row's Start is plain.
func _check_page() -> void:
	if not WindowManager.OWN_SHEETS.has("projects"):
		_fail("Public works is not a page of its own sheets")
	var rows: Array = WorksRows.rows(_state(), _main._loader, _state().player())
	if _all_with_meta("works_lane", _page).size() != rows.size():
		_fail("%d lanes for %d works" % [_all_with_meta("works_lane", _page).size(), rows.size()])
	var first := rows.filter(func(r): return String(r["state"]) == WorksRows.OFFER)
	if first.is_empty() or String(_page.picked()) != String(first[0]["id"]):
		_fail("the first offer is not picked: '%s'" % _page.picked())
	var sheet = _with_meta("works_sheet", _page)
	if sheet == null or not _text_under(sheet).contains(String(first[0]["name"]) if not first.is_empty() else "?"):
		_fail("no sheet for the picked work")
	var filled: Array = _page.find_children("*", "Button", true, false).filter(
		func(b): return b.is_visible_in_tree() and b.theme_type_variation == UiTheme.PRIMARY)
	if filled.size() != 1 or sheet == null or not sheet.is_ancestor_of(filled[0]):
		_fail("%d filled buttons; the one must be the picked work's Start" % filled.size())
	for r in first:
		var start = _with_meta("works_start_" + String(r["id"]), _page)
		if start == null or start.theme_type_variation == UiTheme.PRIMARY:
			_fail("the row %s has no plain Start" % r["id"])


## The lanes and the bill share one axis; the term's end is the vote's month; the bill's first
## step is the register's, and with the picked work it adds that work's cost.
func _check_axes() -> void:
	var axis = _with_meta("works_axis", _page)
	var bill = _with_meta("works_bill", _page)
	if axis == null or bill == null:
		_fail("no axis (%s) or no bill chart (%s)" % [axis, bill])
		return
	var m := _now() + 24
	if absf(axis.global_x(m) - bill.global_x(m)) > 1.0:
		_fail("the lanes and the bill are not on one axis: %s against %s" % [axis.global_x(m), bill.global_x(m)])
	var when := Trends.vote_date(_state().player())
	if Trends.months_until(_state(), when.x, when.y) >= 0 and axis.term_month() != when.x * 12 + when.y:
		_fail("the term's line sits at %d, the vote's month is %d" % [axis.term_month(), when.x * 12 + when.y])
	var ns = _state().player()
	var rows: Array = WorksRows.rows(_state(), _main._loader, ns)
	if absf(WorksRows.bill_at(rows, _now()) - Projects.bill_pct_gdp(ns, _main._loader)) > 1e-9:
		_fail("the bill's first step %s is not the register's %s" % [WorksRows.bill_at(rows, _now()), Projects.bill_pct_gdp(ns, _main._loader)])
	var picked: Dictionary = rows.filter(func(r): return String(r["id"]) == String(_page.picked()))[0]
	if absf(WorksRows.bill_at(rows, _now(), String(_page.picked())) - WorksRows.bill_at(rows, _now()) - float(picked["cost_pct"])) > 1e-9:
		_fail("the bill with the picked work does not add its cost")


## Design's round on #450 (gate-450.md): a mark line never strikes text, only the picked lane says
## how long after the term it opens, a legend under the lanes, one x for a lane's name and its
## sub-line, one style for the bill's two captions.
func _check_marks() -> void:
	var axis = _with_meta("works_axis", _page)
	var label: Rect2 = axis.term_label_rect() if axis.has_method("term_label_rect") else Rect2()
	if axis.term_month() > 0:
		var xt: float = axis.x_of(axis.term_month())
		if label.size.x <= 0.0:
			_fail("the term's end has no label beside its line")
		elif label.position.x < xt and label.end.x > xt:
			_fail("the term's line runs through its own label")
		elif axis.line_top() < label.end.y:
			_fail("in the axis row the term's line starts above its label's foot")
	for lane in _all_with_meta("works_lane", _page):
		var says := String(lane.tooltip_text).contains("after your term ends")
		if says and String(lane.get_meta("works_lane")) != String(_page.picked()):
			_fail("the lane %s, not picked, says how long after the term it opens" % lane.get_meta("works_lane"))
	if _with_meta("works_legend", _page) == null:
		_fail("no legend under the lanes")
	var captions: Array = []
	for l in _page.find_children("*", "Label", true, false):  # i18n: ok a class name
		if (l as Label).text in [_page.tr("Paid until the work opens."), _page.tr("Dashed: with the picked work.")]:
			captions.append(l)
	if captions.size() != 2 or captions[0].theme_type_variation != captions[1].theme_type_variation:
		_fail("the bill's two captions do not wear one style")
	var sub = _with_meta("works_sub", _page)
	var title = _with_meta("works_title", _page)
	if sub == null or title == null:
		_fail("no lane name (%s) or sub-line (%s)" % [title, sub])
	else:
		var inset: float = (title as Button).get_theme_stylebox("normal").get_margin(SIDE_LEFT)
		if absf(title.global_position.x + inset - sub.global_position.x) > 1.0:
			_fail("a lane's name sits at %s, its sub-line at %s" % [title.global_position.x + inset, sub.global_position.x])


## A refused verb is said inside the head sheet, never on the map between the sheets.
func _check_refusal() -> void:
	for l in _page.find_children("*", "Label", true, false):  # i18n: ok a class name
		if (l as Label).text.ends_with(_page.tr("refused -- it is no longer on offer.").trim_prefix("%s ")):
			if l.get_parent() == _page._body:
				_fail("the refused line sits on the map, a child of the bare body")
			return
	_fail("no refused line drawn")


## A started work: its lane opens on the diary's date, and Cancel... is a ghost that asks.
func _check_building() -> void:
	var ns = _state().player()
	if not Projects.is_building(ns, _started):
		_fail("the sheet's Start did not start %s" % _started)
		return
	var rows: Array = WorksRows.rows(_state(), _main._loader, ns)
	var row: Dictionary = rows.filter(func(r): return String(r["id"]) == _started)[0]
	if String(row["state"]) != WorksRows.BUILDING:
		_fail("%s is not a building row" % _started)
	for entry in Calendar.fixed_dates(_state()):
		if String(entry.get("kind", "")) == CalendarK.FIXED_PROJECT and String(entry.get("ref", "")) == _started:
			if int(row["opens"]) != int(entry["year"]) * 12 + int(entry["month"]):
				_fail("%s opens at %d, the diary's %d" % [_started, int(row["opens"]), int(entry["year"]) * 12 + int(entry["month"])])
	var cancel = _with_meta("works_cancel_" + _started, _page)
	if cancel == null or cancel.theme_type_variation != UiTheme.GHOST or not String(cancel.text).ends_with("…"):
		_fail("the building work has no ghost Cancel…")
	# Pass 1 on #450: one work building leaves a slot free; with the building work picked, the lead
	# must not say every slot is taken.
	var was: String = _page._picked
	_page._picked = _started
	var said: String = _page._lead(rows, -1)
	_page._picked = was
	if Projects.building_count(ns) < WorksRows.slots(_main._loader) and said == _page.tr("Every slot is taken: nothing can start until a work opens."):
		_fail("one slot is free and the lead says every slot is taken")


# --- helpers ---------------------------------------------------------------

## A region's shown name, read off the loader the way the regions screen does; "" for none.
func _region_name(id: String) -> String:
	for region in _main._loader.regions.get(_state().player().id, []):
		if String(region.id) == id:
			return String(region.region_name)
	return ""


func _press(button) -> void:
	if button == null:
		_fail("button to press not found")
		return
	if button.disabled:
		_fail("button '%s' is disabled" % button.text)
		return
	button.pressed.emit()


func _all_with_meta(key: String, from: Node) -> Array:
	var out: Array = []
	if from.has_meta(key) and from.is_visible_in_tree() and not from.is_queued_for_deletion():
		out.append(from)
	for child in from.get_children():
		out.append_array(_all_with_meta(key, child))
	return out


func _with_meta(key: String, from: Node):
	var found := _all_with_meta(key, from)
	return found[0] if not found.is_empty() else null


func _text_under(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "", true, false):
		if label is Label:
			out += (label as Label).text + " "
		elif label is Button:
			out += (label as Button).text + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_works_page: OK")
		quit(0)
	else:
		for f in _failures:
			push_error("FAIL " + f)
		quit(1)
