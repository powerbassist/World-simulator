extends SceneTree

## Headless test: godot --headless --script res://tests/test_diary_tiles.gd
## Non-zero exit on any failure.
##
## G3 S2, the Diary on Sheets on glass (g3-spec.md sections 2 and 5): the month as tiles.
##   - the weeks are whole: the days before the 1st and after the last are drawn, out of
##     month, dated, and take neither a click nor the keyboard;
##   - a visit's trip is one capsule per week row: round where the trip starts and ends,
##     square with a chevron where a week ends and the trip goes on; its legs are named
##     ("to <host>" on the way out, "back" on the way home) and the meeting day is a pill;
##     the pointer on any day of it lights every day of it, and only those;
##   - an armed person's free day carries a bookable place named for them ("See <name>");
##     a day of their window the diary holds says it is taken, with the reason;
##   - a booking just made is fresh: its appointment wears the check, and the accent has
##     drained (motion off headless: the final state at once);
##   - with motion on, the fresh appointment's accent drains over DRAIN_S after the booking
##     lands -- not on the redraw that disarms the grid before it (pass 1's own find);
##   - the people column's armed verb is the screen's main action (the accent fill), and
##     the file's four verbs share one button class, re-read on every redraw (RECORD H10).

const Calendar = preload("res://src/sim/calendar.gd")
const K = preload("res://src/sim/calendar_constants.gd")
const Audiences = preload("res://src/sim/audiences.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Motion = preload("res://src/ui/motion.gd")
const DiaryDay = preload("res://src/ui/diary_day.gd")
const DiaryPeople = preload("res://src/ui/diary_people.gd")
const Band = preload("res://src/ui/diary_band.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _grid
var _request := ""
var _offered := {}
var _edge_offset := 0
var _second = null


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_stage()
			AudienceDriver.refresh(_main)
			_main._windows.open("calendar")
		6:
			_grid = _main._calendar_panel.find_child("DiaryGrid", true, false)
			if _grid == null or _request == "":
				_fail("premise: no grid or no staged request")
				_finish()
				return true
			_check_whole_weeks()
			_check_november()
			_check_tile_rules()
			_check_trip()
			_check_places()
		8:
			_check_fresh()
			_check_outside_click()
			_check_class_relabel()
		12:
			# Settled through Motion.finish (the documented read of an end state), not wall time.
			Motion.finish(_grid)
			var cell = _cell(int(_offered["day"]))
			if cell == null or not is_equal_approx(float(cell.drain), 1.0):
				_fail("the fresh appointment never finished draining: %.2f" % (float(cell.drain) if cell != null else -1.0))
			# Pass 1: "just booked" -- the check goes once the day turns.
			_main._clock.advance_one_day()
		15:
			_grid.show_month(int(_offered["year"]), int(_offered["month"]))
			var cell = _cell(int(_offered["day"]))
			if cell != null and bool(cell.fresh):
				_fail("a day on, the appointment still wears the just-booked check")
			_check_summons_fresh()
			_finish()
			return true
	return false


func _stage() -> void:
	var state = _main._state
	var ns = state.player()
	var people: Array = _main._loader.people[String(ns.id)]
	for person in people.slice(4):
		var r := Audiences.invite(state, ns, _main._loader, String(person.id), "office:premiership", "wants")
		if bool(r.get("ok", false)):
			_request = String(r["request"]["id"])
			break
	var now := int(state.year) * 12 + int(state.month)
	for d in Audiences.offered_dates(state, ns, _request):
		if bool(d["free"]) and int(d["year"]) * 12 + int(d["month"]) > now:
			_offered = d
			break


## QA on #437: November's trailing days are December's, not January's.
func _check_november() -> void:
	var y := int(_main._state.year)
	_grid.show_month(y, 11)
	if _grid.page() < 0 or _grid._shown() != Vector2i(y, 11):
		return  # out of the horizon from this start: nothing to read
	var outs: Array = _grid._days.get_children().filter(func(c) -> bool: return bool(c.get("outside")) and int(c.day) < 15)
	if not outs.is_empty() and not String(outs[0].name).begins_with("Out_12_"):
		_fail("November's trailing day is '%s', not December's" % outs[0].name)


## QA on #437: a pointer on an out-of-month tile lights nothing; a place costs a line above it.
func _check_tile_rules() -> void:
	for c in _grid._days.get_children():
		if bool(c.get("outside")):
			c.mouse_entered.emit()
			if bool(c._hover):
				_fail("an out-of-month tile lights under the pointer")
			c.mouse_exited.emit()
			break
	var cell := DiaryDay.new()
	cell.day = 9
	cell.offer = "See Somebody"
	cell.entries = [{"text": "a", "mark": "fixed"}, {"text": "b", "mark": "fixed"}, {"text": "c", "mark": "fixed"}]
	root.add_child(cell)
	cell.fill()
	if cell._lines.get_child_count() > DiaryDay.MAX_LINES - 1:
		_fail("a tile with a place shows %d lines above it, past %d" % [cell._lines.get_child_count(), DiaryDay.MAX_LINES - 1])
	# QA's visual TAKE: a place's words that outgrow it are cut with an ellipsis, never mid-letter.
	var font := cell.get_theme_default_font()
	var fitted := DiaryDay.fit("See Vasseur-Montgolfier", font, 13, 60.0)
	if not fitted.ends_with("…") or font.get_string_size(fitted, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x > 60.0:
		_fail("a long place reads '%s': not cut to its width with an ellipsis" % fitted)
	if DiaryDay.fit("See Roy", font, 13, 200.0) != "See Roy":
		_fail("a place that fits was cut")
	cell.queue_free()
	# Pass 2 TAKE 2: a fresh card's words take the fill's ink -- dark on a light accent.
	var kept := UiTheme._accent
	UiTheme._accent = Color("#E8D000")
	var card := DiaryDay.Appointment.new()
	card.fresh = true
	var words := Label.new()
	card.add_child(words)
	root.add_child(card)
	card.ink(0.0)
	if UiTheme.on_accent_fill().is_equal_approx(Color.WHITE):
		_fail("premise: a yellow accent's fill takes white ink")
	elif not words.self_modulate.is_equal_approx(UiTheme.on_accent_fill()):
		_fail("a fresh card on a yellow fill writes %s, not the fill's ink %s" % [words.self_modulate, UiTheme.on_accent_fill()])
	UiTheme._accent = kept
	card.queue_free()


func _check_whole_weeks() -> void:
	var at := _month(3)
	_grid.show_month(int(at["year"]), int(at["month"]))
	var cells: Array = _grid._days.get_children()
	if cells.size() % 7 != 0:
		_fail("the month's last week is not whole: %d tiles" % cells.size())
	var first := -1
	for i in cells.size():
		if String(cells[i].name) == "Day_1":
			first = i
	if first < 0:
		_fail("no Day_1 tile")
		return
	var prev_len := Calendar.days_in_month(int(at["year"]) - (1 if int(at["month"]) == 1 else 0), 12 if int(at["month"]) == 1 else int(at["month"]) - 1)
	for i in first:
		var c = cells[i]
		if not bool(c.get("outside")):
			_fail("the tile before the 1st at %d is not out of month" % i)
		elif int(c.day) != prev_len - first + 1 + i:
			_fail("the tile before the 1st at %d reads day %d, not %d" % [i, int(c.day), prev_len - first + 1 + i])
		if (c as Control).focus_mode != Control.FOCUS_NONE:
			_fail("an out-of-month tile takes the keyboard")
	var last = cells[cells.size() - 1]
	if cells.size() > first + Calendar.days_in_month(int(at["year"]), int(at["month"])) and (not bool(last.get("outside")) or int(last.day) > 7):
		_fail("the tile after the last day is not next month's start")


## A state visit on the 14th with two days' journey: days 12-16, out on 12-13, home on 15-16.
func _check_trip() -> void:
	var state = _main._state
	var at := _month(4)
	var visit := Calendar.make_entry(K.KIND_DIPLOMATIC, int(at["year"]), int(at["month"]), 14, "state_visit", "DEU", "", "", "", "", 2)
	state.appointments.append(visit)
	_main._calendar_panel._refresh()
	_grid.show_month(int(at["year"]), int(at["month"]))
	var host := String(_main._loader.nations["DEU"].nation_name)
	for d in range(12, 17):
		var c = _cell(d)
		var col: int = _grid._days.get_children().find(c) % 7
		var left := "cap" if d == 12 else ("chevron" if col == 0 else "join")
		var right := "cap" if d == 16 else ("chevron" if col == 6 else "join")
		if String(c.band_left) != left or String(c.band_right) != right:
			_fail("day %d's capsule ends read %s/%s, not %s/%s" % [d, c.band_left, c.band_right, left, right])
	if String(_cell(12).band_leg) != tr("to %s") % host:
		_fail("the way out reads '%s', not 'to %s'" % [_cell(12).band_leg, host])
	if String(_cell(15).band_leg) != tr("back"):
		_fail("the way home reads '%s', not 'back'" % _cell(15).band_leg)
	for d in [13, 14, 16]:
		if String(_cell(d).band_leg) != "":
			_fail("day %d names a leg: '%s'" % [d, _cell(d).band_leg])
	if not bool(_cell(14).band_meeting) or bool(_cell(13).band_meeting):
		_fail("the meeting pill is not on the meeting day alone")
	# QA on #437 (Hugo's mutants): the pill names the trip mid-row; only the meeting day takes the
	# pick's outline; a travel day mid-trip draws its rail; the capsule reaches the grid's own gap.
	if String(_cell(14).band_name) != host:
		_fail("the meeting pill reads '%s', not the host '%s'" % [_cell(14).band_name, host])
	var span: Vector2 = Band.rail(_cell(13), float(_cell(13).band_gap()))
	if span.y <= span.x:
		_fail("a travel day mid-trip draws no rail: %s" % span)
	_grid._days.add_theme_constant_override("h_separation", 20)
	if not is_equal_approx(float(_cell(13).band_gap()), 20.0):
		_fail("the capsule's reach does not follow the grid's gap: %.1f" % float(_cell(13).band_gap()))
	_grid._days.add_theme_constant_override("h_separation", int(DiaryDay.GAP * UiTheme.text_scale()))
	_grid._pick(13)
	if bool(_cell(13).band_picked):
		_fail("a travel day picked took the meeting's outline")
	_grid._pick(14)
	if not bool(_cell(14).band_picked):
		_fail("the meeting day picked has no outline")
	_grid._selected = 0
	# The pointer on one day of the trip lights the whole trip, and nothing else.
	_cell(13).mouse_entered.emit()
	for d in range(12, 17):
		if not bool(_cell(d).band_hot):
			_fail("hovering the trip left day %d unlit" % d)
	if bool(_cell(11).band_hot) or bool(_cell(17).band_hot):
		_fail("hovering the trip lit a day off it")
	_cell(13).mouse_exited.emit()
	if bool(_cell(14).band_hot):
		_fail("the trip stayed lit after the pointer left")
	state.appointments.erase(visit)
	# QA on #437: a run that opens on its meeting (the way out last month) names no way out there.
	var first_meet := Calendar.make_entry(K.KIND_DIPLOMATIC, int(at["year"]), int(at["month"]), 1, "state_visit", "DEU", "", "", "", "", 2)
	state.appointments.append(first_meet)
	_main._calendar_panel._refresh()
	_grid.show_month(int(at["year"]), int(at["month"]))
	if bool(_cell(1).band) and (String(_cell(1).band_leg) != "" or String(_cell(2).band_leg) != tr("back")):
		_fail("a run opening on its meeting reads '%s' / '%s', not '' / 'back'" % [_cell(1).band_leg, _cell(2).band_leg])
	state.appointments.erase(first_meet)
	# A Saturday inside a trip joins Sunday: no chevron before the week ends.
	var sat := _day_at_col(5, 3, last_day(at) - 2)
	var satv := Calendar.make_entry(K.KIND_DIPLOMATIC, int(at["year"]), int(at["month"]), sat, "state_visit", "DEU", "", "", "", "", 2)
	state.appointments.append(satv)
	_main._calendar_panel._refresh()
	_grid.show_month(int(at["year"]), int(at["month"]))
	if String(_cell(sat).band_right) != "join":
		_fail("Saturday %d inside a trip ends '%s', not joined to Sunday" % [sat, _cell(sat).band_right])
	state.appointments.erase(satv)
	_main._calendar_panel._refresh()
	# Pass 2 TAKE 1: a trip that starts on a Monday starts round, one that ends on a Sunday ends round.
	var mon := _day_at_col(0, 1, last_day(at) - 4)
	var mv := Calendar.make_entry(K.KIND_DIPLOMATIC, int(at["year"]), int(at["month"]), mon + 2, "state_visit", "DEU", "", "", "", "", 2)
	state.appointments.append(mv)
	_main._calendar_panel._refresh()
	_grid.show_month(int(at["year"]), int(at["month"]))
	if String(_cell(mon).band_left) != "cap":
		_fail("a trip starting on Monday %d starts with '%s', not a round end" % [mon, _cell(mon).band_left])
	state.appointments.erase(mv)
	var sun := _day_at_col(6, 5, last_day(at))
	var sv := Calendar.make_entry(K.KIND_DIPLOMATIC, int(at["year"]), int(at["month"]), sun - 2, "state_visit", "DEU", "", "", "", "", 2)
	state.appointments.append(sv)
	_main._calendar_panel._refresh()
	_grid.show_month(int(at["year"]), int(at["month"]))
	if String(_cell(sun).band_right) != "cap":
		_fail("a trip ending on Sunday %d ends with '%s', not a round end" % [sun, _cell(sun).band_right])
	state.appointments.erase(sv)
	# Pass 1: a trip across the month's edge keeps a chevron there, not a round end. A month whose
	# last day is not a Sunday and whose next starts on no Monday: a row break would chevron anyway.
	for offset in range(4, 16):
		var m := _month(offset)
		var end_wd := (int(Time.get_datetime_dict_from_unix_time(int(Time.get_unix_time_from_datetime_dict({"year": int(m["year"]),
			"month": int(m["month"]), "day": Calendar.days_in_month(int(m["year"]), int(m["month"])), "hour": 0, "minute": 0, "second": 0})))["weekday"]) + 6) % 7
		if end_wd != 6:
			at = m
			_edge_offset = offset
			break
	var last := Calendar.days_in_month(int(at["year"]), int(at["month"]))
	var edge := Calendar.make_entry(K.KIND_DIPLOMATIC, int(at["year"]), int(at["month"]), last, "state_visit", "DEU", "", "", "", "", 2)
	state.appointments.append(edge)
	_main._calendar_panel._refresh()
	_grid.show_month(int(at["year"]), int(at["month"]))
	if _cell(last) == null or String(_cell(last).band_right) != "chevron":
		_fail("a trip going on into next month ends round on the month's last day")
	var nxt := _month(_edge_offset + 1)
	_grid.show_month(int(nxt["year"]), int(nxt["month"]))
	if _cell(1) == null or String(_cell(1).band_left) != "chevron":
		_fail("a trip begun last month starts round on the 1st")
	state.appointments.erase(edge)
	_main._calendar_panel._refresh()


func _check_places() -> void:
	var state = _main._state
	var ns = state.player()
	# A day of the window the diary holds: taken, with the reason.
	var held := {}
	for d in Audiences.offered_dates(state, ns, _request):
		if bool(d["free"]) and int(d["year"]) * 12 + int(d["month"]) == int(_offered["year"]) * 12 + int(_offered["month"]) and int(d["day"]) != int(_offered["day"]):
			held = d
			break
	var blocker = null
	if not held.is_empty():
		blocker = Calendar.make_entry(K.KIND_RESHUFFLE, int(held["year"]), int(held["month"]), int(held["day"]), "", "", "", "interior", "")
		state.appointments.append(blocker)
		# A second entry on the day: two lines above the place.
		_second = Calendar.make_entry(K.KIND_RESHUFFLE, int(held["year"]), int(held["month"]), int(held["day"]), "", "", "", "finance", "")
		state.appointments.append(_second)
		_main._calendar_panel._refresh()
	var see := _main._calendar_panel.find_child("See_%s" % _request, true, false) as Button
	if see == null:
		_fail("the request has no See them")
		return
	if String(see.theme_type_variation) == UiTheme.PRIMARY:
		_fail("See them wears the main action's fill before it is armed")
	see.pressed.emit()
	_grid.show_month(int(_offered["year"]), int(_offered["month"]))
	var name: String = _main._loader.person_name(String(Audiences.request(ns, _request)["person_id"]))
	var surname := name.get_slice(" ", name.get_slice_count(" ") - 1)
	var cell = _cell(int(_offered["day"]))
	if cell == null or String(cell.offer) != tr("See %s") % surname:
		_fail("the free day's bookable place reads '%s', not 'See %s'" % [cell.offer if cell != null else "", surname])
	_check_floors("the armed page")
	var s := UiTheme.text_scale()
	for c in _grid._days.get_children():
		if (String(c.get("offer")) != "" or String(c.get("taken")) != "") and c._lines != null:
			# The place is drawn PLACE_H + 5 up from the tile's foot.
			var need: float = c._lines.offset_top + c._lines.get_combined_minimum_size().y + (preload("res://src/ui/diary_day.gd").PLACE_H + 5.0) * s
			if (c as Control).custom_minimum_size.y < need:
				_fail("day %d's place would sit on its lines: floor %.0f < %.0f" % [int(c.day), c.custom_minimum_size.y, need])
				break
	if blocker != null:
		var taken = _cell(int(held["day"]))
		if taken == null or String(taken.taken) == "":
			_fail("a day of the window the diary holds does not say it is taken")
		elif String(taken.offer) != "":
			_fail("a taken day still offers a place")
		state.appointments.erase(blocker)
		state.appointments.erase(_second)
	var armed := _main._calendar_panel.find_child("See_%s" % _request, true, false) as Button
	if armed == null or String(armed.theme_type_variation) != UiTheme.PRIMARY:
		_fail("the armed See them is not the screen's main action")
	_check_verb_class()
	# Book it as the click does, motion on: the drain is a beat the player must see.
	Motion.override = 1
	_grid._on_day(int(_offered["day"]))


## RECORD H10: the file's four verbs share one class, re-read on a redraw with other labels.
func _check_verb_class() -> void:
	var verbs: Array = []
	for key in ["See", "Call", "Delegate", "Decline"]:
		var b := _main._calendar_panel.find_child("%s_%s" % [key, _request], true, false) as Button
		if b == null:
			_fail("the file has no %s verb" % key)
			return
		verbs.append(b)
	var s := UiTheme.text_scale()
	if not is_equal_approx((verbs[0] as Button).custom_minimum_size.y, roundf(PanelKit.BTN_H_ROW * s)):
		_fail("the matrix's verbs are %.0f px high, not a table row's button" % (verbs[0] as Button).custom_minimum_size.y)
	var column: Control = _main._calendar_panel.people
	if column.get_combined_minimum_size().x > DiaryPeople.WIDTH * s + 0.5:
		_fail("the people column needs %.0f px, past its %.0f: the page widens" % [column.get_combined_minimum_size().x, DiaryPeople.WIDTH * s])
	var w: float = (verbs[0] as Button).custom_minimum_size.x
	for b in verbs:
		if not is_equal_approx((b as Button).custom_minimum_size.x, w):
			_fail("the file's verbs do not share one width: %s" % [verbs.map(func(v: Button) -> float: return v.custom_minimum_size.x)])
			return
	var widths: Array = PanelKit.BTN_W.values().map(func(x: int) -> float: return roundf(x * UiTheme.text_scale()))
	if not w in widths:
		_fail("the file's verbs are %.0f px, not a button class" % w)


func _check_fresh() -> void:
	var row := Audiences.request(_main._state.player(), _request)
	if String(row.get("status", "")) != "booked":
		_fail("premise: the booking did not land: %s" % row.get("status", ""))
		return
	_grid.show_month(int(_offered["year"]), int(_offered["month"]))
	var cell = _cell(int(_offered["day"]))
	if cell == null or not bool(cell.fresh):
		_fail("the appointment just booked is not fresh")
	elif float(cell.drain) >= 1.0:
		_fail("two frames after the booking the accent has already gone: the drain played before the appointment existed")
	if cell != null and String(cell.offer) != "":
		_fail("the booked day still offers a place")
	var state = _main._state
	var extra: Array = []
	for portfolio in ["interior", "finance"]:
		extra.append(Calendar.make_entry(K.KIND_RESHUFFLE, int(_offered["year"]), int(_offered["month"]), int(_offered["day"]), "", "", "", portfolio, ""))
		state.appointments.append(extra[-1])
	_main._calendar_panel._refresh()
	_grid.show_month(int(_offered["year"]), int(_offered["month"]))
	_check_floors("a busy day")
	for e in extra:
		state.appointments.erase(e)
	_main._calendar_panel._refresh()
	# QA on #437 (T6): the fresh mark is stamped with the whole date: the same day number a month
	# on is not "the same day".
	var stamp_kept := int(state.month)
	state.month = stamp_kept % 12 + 1
	_grid._render()
	if not _grid._fresh.is_empty():
		_fail("a month on, on the same day number, the booking is still fresh")
	state.month = stamp_kept
	_grid._render()
	# Pass 2 TAKE 2: no white on the accent fill (Germany's yellow fails it); the fill's own ink.
	for path in ["res://src/ui/diary_day.gd", "res://src/ui/diary_band.gd"]:
		if FileAccess.get_file_as_string(path).contains("Color.WHITE"):
			_fail("%s writes Color.WHITE: on a light accent fill it fails 4.5:1 -- use UiTheme.on_accent_fill()" % path)


## Pass 2 TAKE 5: a summons is fresh on the day it LANDED, read from the register.
func _check_summons_fresh() -> void:
	var state = _main._state
	var ns = state.player()
	for person in _main._loader.people[String(ns.id)]:
		var pid := String(person.id)
		if not Audiences.summon_refusal(state, ns, _main._loader, pid).is_empty():
			continue
		for d in Audiences.summon_days(state, pid):
			if bool(d["free"]):
				# QA on #437 (T5): an older audience with the same person is not the one just booked.
				var older := Calendar.make_entry(K.KIND_AUDIENCE, int(d["year"]), int(d["month"]), 1 if int(d["day"]) != 1 else 2, "", pid)
				state.appointments.push_front(older)
				_grid.arm({"id": "", "person_id": pid, "person": _main._loader.person_name(pid), "summons": true})
				_grid.show_month(int(d["year"]), int(d["month"]))
				_grid._on_day(int(d["day"]))
				_main._calendar_panel._refresh()
				_grid.show_month(int(d["year"]), int(d["month"]))
				var cell = _cell(int(d["day"]))
				if cell == null or not bool(cell.fresh):
					_fail("the summons just booked is not fresh on its day")
				if int(_grid._fresh.get("day", -1)) != int(d["day"]):
					_fail("the fresh mark sits on day %d, an older audience, not the one booked (%d)" % [int(_grid._fresh.get("day", -1)), int(d["day"])])
				state.appointments.erase(older)
				return
	_fail("premise: nobody could be summoned")


## An out-of-month tile takes no click (the keyboard is checked above).
func _check_outside_click() -> void:
	var out: Control = null
	for c in _grid._days.get_children():
		if bool(c.get("outside")):
			out = c
			break
	if out == null:
		_fail("premise: no out-of-month tile on the shown page")
		return
	var hits := [0]
	out.picked.connect(func(_d: int) -> void: hits[0] += 1)
	for down in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = down
		out._gui_input(e)
	if hits[0] != 0:
		_fail("a click on an out-of-month tile picked it")


## RECORD H10: same_class re-reads the labels -- a longer one steps every button up together.
func _check_class_relabel() -> void:
	var box := HBoxContainer.new()
	root.add_child(box)
	var buttons: Array = []
	for t in ["Go", "Call", "Ask", "No"]:
		var b := Button.new()
		b.text = t
		box.add_child(b)
		buttons.append(b)
	(buttons[1] as Button).custom_minimum_size.y = 50.0
	PanelKit.same_class(buttons)
	if (buttons[1] as Button).custom_minimum_size.y < 50.0:
		_fail("same_class wiped a height the caller set")
	var before: float = (buttons[0] as Button).custom_minimum_size.x
	(buttons[2] as Button).text = "A much longer answer than any class S holds"
	PanelKit.same_class(buttons)
	for b in buttons:
		if (b as Button).custom_minimum_size.x <= before:
			_fail("a longer label did not step the whole group up a class")
			break
	(buttons[2] as Button).text = "Ask"
	PanelKit.same_class(buttons)
	if not is_equal_approx((buttons[0] as Button).custom_minimum_size.x, before):
		_fail("the group did not step back down when the long label went")
	box.queue_free()


## The first day of the shown month at weekday column `col` (Monday 0) within [lo, hi].
func _day_at_col(col: int, lo: int, hi: int) -> int:
	for d in range(lo, hi + 1):
		if _grid._days.get_children().find(_cell(d)) % 7 == col:
			return d
	return lo


func last_day(m: Dictionary) -> int:
	return Calendar.days_in_month(int(m["year"]), int(m["month"]))


## Pass 2 TAKE 3: every tile's floor holds its lines (and its place): nothing is cut under the
## next row.
func _check_floors(where: String) -> void:
	var s := UiTheme.text_scale()
	for c in _grid._days.get_children():
		if bool(c.get("outside")) or c._lines == null:
			continue
		var place: float = (DiaryDay.PLACE_H + 5.0) * s if String(c.offer) != "" or String(c.taken) != "" else 0.0
		var need: float = c._lines.offset_top + c._lines.get_combined_minimum_size().y + place
		if (c as Control).custom_minimum_size.y < need:
			_fail("%s: day %d's floor %.0f cuts its lines (needs %.0f)" % [where, int(c.day), c.custom_minimum_size.y, need])
			return


func _cell(day: int):
	return _grid.find_child("Day_%d" % day, true, false)


func _month(offset: int) -> Dictionary:
	var total: int = int(_main._state.year) * 12 + int(_main._state.month) - 1 + offset
	return {"year": total / 12, "month": total % 12 + 1}


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	Motion.override = -1
	if _failures.is_empty():
		print("test_diary_tiles: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
