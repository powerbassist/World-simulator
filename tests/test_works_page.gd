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
const Num = preload("res://src/ui/num.gd")
const WorksLane = preload("res://src/ui/works_lane.gd")
const WorksBill = preload("res://src/ui/works_bill.gd")

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
			_check_figures()
			_check_row_hugs("offers on the table")
			_check_narrow_axes()
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
			_press(_with_meta("works_start_" + _offer_ids()[0], _page))
		14:
			# One work building: pick another offer, whose sheet says it takes the last slot.
			_page._picked = _offer_ids()[0]
			_page.mark_dirty()
		16:
			_check_one_free()
			_press(_with_meta("works_go", _page))
		18:
			_check_full()
			_check_row_hugs("both slots taken")
			_finish()
	return false


## The 2K card's A (the author, 2026-11-22): the row of the lanes and the picked work's sheet hugs its
## content, both sheets ending together at the taller one's foot, and the map shows under it.
func _check_row_hugs(where: String) -> void:
	var sheet: Control = _with_meta("works_sheet", _page)
	while sheet != null and String(sheet.theme_type_variation) != UiTheme.PLATE:
		sheet = sheet.get_parent() as Control
	if sheet == null or not (sheet.get_parent() is HBoxContainer):
		_fail("%s: the picked work's sheet is not in the row" % where)
		return
	var row: Control = sheet.get_parent()
	var feet: Array = row.get_children().filter(func(c): return c is Control and c.visible).map(
		func(c): return roundf((c as Control).get_global_rect().end.y))
	if feet.max() - feet.min() > 1.0:
		_fail("%s: the row's sheets end at %s, not together" % [where, feet])
	if row.size.y > row.get_combined_minimum_size().y + 1.0:
		_fail("%s: the row is %.0f px tall for %.0f of content: its sheets stretch to the band" % [where, row.size.y, row.get_combined_minimum_size().y])
	var dock: Rect2 = _main._windows.dock().get_global_rect()
	if row.get_global_rect().end.y > dock.end.y - 40.0:
		_fail("%s: the row ends at %.0f, at the dock's foot %.0f: no map under it" % [where, row.get_global_rect().end.y, dock.end.y])


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


## QA's TAKE on #450: the figures and sentences a player reads, each against its own source.
func _check_figures() -> void:
	var ns = _state().player()
	var rows: Array = WorksRows.rows(_state(), _main._loader, ns)
	var term := _term()
	if _lead_text() != _page._lead(rows, term):
		_fail("the page's lead '%s' is not the lead for its state" % _lead_text())
	var picked: Dictionary = rows.filter(func(r): return String(r["id"]) == String(_page.picked()))[0]
	var opens := int(picked["opens"])
	# A term ending five months before the opening: the lead counts them.
	var said: String = _page._lead(rows, opens - 5)
	if said != _page.tr_n("%s would open %d month after your term ends.", "%s would open %d months after your term ends.", 5) % [picked["name"], 5]:
		_fail("an offer opening five months after the term reads '%s'" % said)
	var with := Num.f(WorksRows.bill_at(rows, _now(), String(picked["id"])), 2)
	if not _text_under(_with_meta("works_sheet", _page)).contains(_page.tr("Works' bill: %s %% of GDP. No vote.") % with):
		_fail("the sheet's works' bill is not %s with the picked offer" % with)
	if not _text_under(_with_meta("works_sheet", _page)).contains(_page.tr("It takes a free slot.")):
		_fail("with every slot free the sheet does not say it takes a free slot")
	var most := -1
	for action in JSON.parse_string(FileAccess.get_file_as_string("res://data/project-actions/projects.json"))["actions"]:
		for cond in action["preconditions"]:
			if String(cond["field"]) == "project_count" and String(cond["op"]) == "<=":
				most = maxi(most, int(cond["value"]))
	if WorksRows.slots(_main._loader) != most + 1:
		_fail("%d slots; the data's project_count <= %d allows %d" % [WorksRows.slots(_main._loader), most, most + 1])


## R2 on #452 (gate-452.md): at any text size and lane width no two year labels touch, "today"
## stands clear of "your term ends" however close the term is, and a lane's caption is never cut.
func _check_narrow_axes() -> void:
	var was := UiTheme.text_scale()
	var first := 2027 * 12 + 1
	var last := first + 12 * 12
	for scale in [0.9, 1.0]:
		UiTheme.set_text_scale(scale)
		for width in [260.0, 330.0, 480.0, 900.0]:
			for now in [first, first + 11]:
				for ahead in [1, 4, 5, 16, 60, 72]:
					var at := "text %s, %d px, today +%d, term +%d" % [scale, width, now - first, ahead]
					var axis: Control = WorksLane.new()
					root.add_child(axis)
					UiTheme.rebuild(axis)
					axis.axis(first, last, now, now + ahead)
					axis.size = Vector2(width, 60.0)
					_check_apart(axis, "lanes' years at " + at)
					var term: Rect2 = axis.term_label_rect()
					if term.intersects(axis.today_rect()):
						_fail("'today' %s sits on the term's label %s at %s" % [axis.today_rect(), term, at])
					# QA on #454: under 330 px the label may run past the row (a RECORD there).
					if width >= 330.0 and term.end.x > width + 0.01:
						_fail("the term's label ends at %.0f, past the row, at %s" % [term.end.x, at])
					if axis.line_top() < term.end.y:
						_fail("the term's line starts above its label's foot at " + at)
					axis.free()
				var bill: Control = WorksBill.new()
				root.add_child(bill)
				UiTheme.rebuild(bill)
				bill.setup([], first, last, now, "", "")
				bill.size = Vector2(width, 140.0)
				_check_apart(bill, "the bill's years at text %s, %d px" % [scale, width])
				bill.free()
				for state in [WorksRows.OFFER, WorksRows.BUILDING]:
					var lane: Control = WorksLane.new()
					root.add_child(lane)
					UiTheme.rebuild(lane)
					lane.lane({"state": state, "opens": now + 96}, first, last, now, now + 4, true)
					lane.size = Vector2(width, 50.0)
					var drawn: String = lane.caption()
					var room: float = width - lane.x_of(now) - 8.0
					var wide: float = lane.get_theme_default_font().get_string_size(drawn, HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(UiTheme.SIZE_SMALL * scale)).x
					if wide > room:
						_fail("the %s lane's caption '%s' is %.0f px in %.0f at text %s" % [state, drawn, wide, room, scale])
					if width >= 900.0 and drawn != lane._said():
						_fail("a wide %s lane's caption is not its whole sentence: '%s'" % [state, drawn])
					lane.free()
	UiTheme.set_text_scale(was)


## The years of an axis from January 2027 to January 2039: each box as wide as its own digits,
## inside the row and over its January, the first year said and none left off the end, no two closer
## than 2 px, and thinned evenly.
func _check_apart(control: Control, where: String) -> void:
	var labels: Array = control.year_labels()
	var width := control.size.x
	var font := control.get_theme_default_font()
	var fs := roundi(UiTheme.SIZE_SMALL * UiTheme.text_scale())
	if labels.size() < 2:
		_fail("%s: %d year labels" % [where, labels.size()])
		return
	if labels[0][0] != 2027:
		_fail("%s: the axis's first year is not said, it starts at %s" % [where, labels[0][0]])
	for label in labels:
		var box: Rect2 = label[1]
		var digits := font.get_string_size(str(label[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		if box.size.x < digits - 0.01:
			_fail("%s: %s is %.0f px of digits in a %.0f px box" % [where, label[0], digits, box.size.x])
			break
		if box.position.x < -0.01 or box.end.x > width + 0.01:
			_fail("%s: %s runs from %.0f to %.0f, outside the row's 0 to %.0f" % [where, label[0], box.position.x, box.end.x, width])
			break
		# 12 years on the axis, from January 2027.
		var tick: float = width * (label[0] - 2027) / 12.0
		if tick < box.position.x - 0.01 or tick > box.end.x + 0.01:
			_fail("%s: %s runs from %.0f to %.0f, off its January at %.0f" % [where, label[0], box.position.x, box.end.x, tick])
			break
	if labels[-1][0] + (labels[1][0] - labels[0][0]) <= 2039:
		_fail("%s: the axis runs to 2039, its years stop at %s" % [where, labels[-1][0]])
	for i in range(2, labels.size()):
		if labels[i][0] - labels[i - 1][0] != labels[1][0] - labels[0][0]:
			_fail("%s: the years skip unevenly, %s" % [where, labels.map(func(l): return l[0])])
			break
	for i in range(1, labels.size()):
		var gap: float = labels[i][1].position.x - labels[i - 1][1].end.x
		if gap < 2.0:
			_fail("%s: %s and %s are %.0f px apart" % [where, labels[i - 1][0], labels[i][0], gap])
			return


## One work building, an offer picked: the head's bill is the register's, the sheet takes the last slot.
func _check_one_free() -> void:
	var ns = _state().player()
	var bill: String = _page.tr("%s %%") % Num.f(Projects.bill_pct_gdp(ns, _main._loader), 3)
	if Projects.bill_pct_gdp(ns, _main._loader) <= 0.0 or not _text_under(_page).contains(bill + " "):
		_fail("the head's bill tile does not read %s" % bill)
	var sheet = _with_meta("works_sheet", _page)
	if sheet == null or not _text_under(sheet).contains(_page.tr("It takes the last free slot.")):
		_fail("one slot free and the picked offer's sheet does not say it takes the last one")


## Both slots taken: the lead says nothing can start, the tile counts them.
func _check_full() -> void:
	var ns = _state().player()
	var slots := WorksRows.slots(_main._loader)
	if Projects.building_count(ns) != slots:
		_fail("%d works building, not the %d slots" % [Projects.building_count(ns), slots])
		return
	if _lead_text() != _page.tr("Every slot is taken: nothing can start until a work opens."):
		_fail("every slot taken and the lead reads '%s'" % _lead_text())
	if not _text_under(_page).contains(_page.tr("%d of %d") % [slots, slots] + " "):
		_fail("the head's tile does not read %d of %d" % [slots, slots])


func _term() -> int:
	var when := Trends.vote_date(_state().player())
	return when.x * 12 + when.y if Trends.months_until(_state(), when.x, when.y) >= 0 else -1


func _lead_text() -> String:
	for l in _page.find_children("*", "Label", true, false):  # i18n: ok a class name
		if (l as Label).theme_type_variation == UiTheme.LEAD and l.is_visible_in_tree():
			return (l as Label).text
	return ""


func _offer_ids() -> Array:
	return WorksRows.rows(_state(), _main._loader, _state().player()).filter(
		func(r): return String(r["state"]) == WorksRows.OFFER and r["start"] != null).map(func(r): return String(r["id"]))


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
