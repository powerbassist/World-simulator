extends SceneTree

## Headless test: godot --headless --script res://tests/test_law_verbs.gd
## Non-zero exit on any failure.
##
## V5.3 b, step 5 (docs/design/v5.3-ab.md 2.2, 4.3, 4.4): the two decisions on an open bill,
## driven through the real panel with real clicks. The grade picker: a row with no size shows
## nothing; a chip re-reads the forecast, the row's bar and the strip at that size; the grade
## reaches Legislature.propose through the briefing, and the strip's money is what the bill
## then books. The address: its button stands beside a tabled bill's greyed verbs; the strip
## says what the division then does, seat for seat; the bar the player reads moves (QA's merge
## gate on the UI); the diary's refusal is read before the press.

const LawGrade = preload("res://src/ui/law_grade.gd")
const LawAddress = preload("res://src/ui/law_address.gd")
const LawMagnitude = preload("res://src/core/law_magnitude.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const LK = preload("res://src/sim/legislature_constants.gd")
const Division = preload("res://src/sim/division.gd")
const Budget = preload("res://src/sim/budget.gd")
const Address = preload("res://src/sim/address.gd")
const AddressK = preload("res://src/sim/address_constants.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const CalendarK = preload("res://src/sim/calendar_constants.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _law  # the row tagged with a size
var _plain  # a row with none
var _click: Control
var _click_at := -1
var _before := {}
var _diary_repaints := 0
var _strip_before := {}


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	# A real click: scrolled into view, then press and release two frames apart.
	if _click != null and _frame == _click_at - 2:
		Click.half(root, _click, true)
	if _click != null and _frame == _click_at:
		Click.half(root, _click, false)
		_click = null
	match _frame:
		3:
			_main._windows.open("legislature")
		6:
			_stage()
		9:
			_check_a_row_with_no_size_shows_nothing()
			_check_the_address_rests_folded()
			LawAddress._fold(_list(), _plain)
		10:
			if _strip_node(LawAddress.STRIP_META) == null:
				_fail("the fold's first press did not open the strip")
			LawAddress._fold(_list(), _plain)
		11:
			if _strip_node(LawAddress.STRIP_META) != null:
				_fail("the fold's second press left the strip up")
			_list().select(String(_law.id))
		12:
			_check_the_reference_grade()
			_press(_chip(10.0))
		20:
			_check_a_chip_rereads_the_bill()
			_check_the_address_reads_the_pick()
			_check_the_money_is_what_it_books()
			_check_the_pick_survives_a_refresh()
			_check_the_grades_offered()
			_check_the_referendum_route_takes_no_grade()
			_press(_propose())
		28:
			_check_the_briefing_reads_the_grade()
			_main._briefing.propose_requested.emit(_main._briefing._law)
		34:
			_check_the_grade_reached_the_sim()
			_check_the_address_stands_beside_a_tabled_bill()
			_strip_before = Division.forecast(_main._state, _ns(), _main._loader)
			_before = _strip_of(LawAddress.STRIP_META).duplicate()
			_main._calendar_panel.diary_changed.connect(func() -> void: _diary_repaints += 1)
			_press(_air())
		42:
			_check_the_address_moved_the_forecast()
			_check_the_bill_addressed_says_so()
			_check_the_aired_line_goes_with_the_day()
		46:
			if "On air" in _detail_text():
				_fail("the page says on air today after the day turned, with nothing pressed")
			_main._state.day -= 1
			_main._law_panel._refresh()
			# A long summary, so the fold stands at the column's foot.
			_plain.summary = "word ".repeat(1500)
			_list().select(String(_plain.id))
		49:
			_press(_fold())
		58:
			_check_the_refusal_is_read_before_the_press()
			_main._state.day += 1
		62:
			_check_the_day_turning_lifts_the_refusal()
			_check_a_new_game_drops_the_picks()
			_check_the_strip_is_not_offered_a_dead_verb()
			_finish()
			return true
	return false


func _list():
	return _main._law_panel._laws


func _ns():
	return _main._state.player()


func _parties() -> Array:
	return _main._loader.parties.get(_ns().id, [])


## Tags one budget row with a size, as Content will: no row ships one yet.
func _stage() -> void:
	for law in _list()._shown:
		if _law == null and not (law.effects.get("spending_pct_gdp", {}) as Dictionary).is_empty():
			_law = law
		elif _plain == null and (law.effects.get("spending_pct_gdp", {}) as Dictionary).is_empty():
			_plain = law
	_law.magnitude = {"value": 40.0, "reference": 40.0, "unit": "lycees"}
	_list().select(String(_plain.id))


func _chips() -> Array:
	return _in_detail(func(n: Node) -> bool: return n is Button and n.has_meta(LawGrade.CHIP_META))


func _chip(step: float) -> Button:
	for chip in _chips():
		if is_equal_approx(float(chip.get_meta(LawGrade.CHIP_META)), step):
			return chip
	_fail("no chip at %s" % step)
	return Button.new()


func _propose() -> Button:
	var found := _in_detail(func(n: Node) -> bool: return n is Button and String(n.name) == "Propose")
	return found[0]


func _fold() -> Button:
	var found := _in_detail(func(n: Node) -> bool: return n is Button and n.has_meta(LawAddress.FOLD_META))
	if found.is_empty():
		_fail("no fold on the address")
		return Button.new()
	return found[0]


func _air() -> Button:
	var found := _in_detail(func(n: Node) -> bool: return n is Button and n.has_meta(LawAddress.GO_META))
	if found.is_empty():
		_fail("no address button in the detail")
		return Button.new()
	return found[0]


func _strip_node(meta: String) -> EffectsStrip:
	var found := _in_detail(func(n: Node) -> bool: return n is EffectsStrip and n.has_meta(meta))
	return found[0] if not found.is_empty() else null


func _strip_of(meta: String) -> Dictionary:
	var strip := _strip_node(meta)
	if strip == null:
		return {}
	return {"money": strip.money_label.text, "tone": strip.money_label.theme_type_variation, "bn": strip.money_bn,
		"who": strip._who.text, "when": strip._when.text}


func _in_detail(test: Callable) -> Array:
	var out := []
	var stack: Array = [_list()._detail]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if test.call(n):
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _detail_text() -> String:
	var bits := PackedStringArray()
	for n in _in_detail(func(x: Node) -> bool: return x is Label or x is RichTextLabel):
		bits.append(String(n.text))
	return " | ".join(bits)


func _press(target: Control) -> void:
	(_list()._detail.get_parent() as ScrollContainer).ensure_control_visible(target)
	_click = target
	_click_at = _frame + 4


func _row_bar(law) -> ChartStack:
	var i: int = _list()._shown.find(law)
	var row: Node = _list()._rows.get_child(_list()._rows.get_child_count() - _list()._shown.size() + i)
	for child in row.get_children():
		if child is ChartStack:
			return child
	return null


func _check_a_row_with_no_size_shows_nothing() -> void:
	if not _chips().is_empty():
		_fail("a row with no size offers %d chips" % _chips().size())
	if _strip_node(LawGrade.STRIP_META) != null:
		_fail("a row with no size draws a grade strip")


func _check_the_address_rests_folded() -> void:
	if _strip_node(LawAddress.STRIP_META) != null or not _in_detail(func(n: Node) -> bool: return n is Button and n.has_meta(LawAddress.GO_META)).is_empty():
		_fail("the address stands open at rest, on an untabled bill")
	if _fold().button_pressed:
		_fail("the fold reads open at rest")


func _check_the_reference_grade() -> void:
	if _chips().size() != LK.GRADE_STEPS.size():
		_fail("%d chips against %d grades" % [_chips().size(), LK.GRADE_STEPS.size()])
	if not _chip(1.0).button_pressed:
		_fail("a bill opens at its own size")
	if "40 lycees" not in _chip(1.0).text or "400 lycees" not in _chip(10.0).text:
		_fail("a chip names the size: %s, %s" % [_chip(1.0).text, _chip(10.0).text])
	if float(_list().grade(_law)) != 1.0:
		_fail("a bill not picked reads at 1")
	# At its own size the page says what it always said: the row itself, read as the row.
	var band: float = _main._law_panel.forecast_band(_ns(), _law.id)
	if "Forecast: " + _main._law_panel.forecast_text(_ns(), _parties(), _law, band) not in _detail_text():
		_fail("at its own size the forecast is not the row's")
	var strip := _strip_of(LawGrade.STRIP_META)
	if String(strip.get("when", "x")) != "":
		_fail("at its own size there is no size to compare: '%s'" % strip.get("when", ""))


func _check_a_chip_rereads_the_bill() -> void:
	if float(_list().grade(_law)) != 10.0:
		_fail("the chip did not pick ten times: %s" % _list().grade(_law))
	if not _chip(10.0).button_pressed:
		_fail("the picked chip is not pressed after the rebuild")
	if not _chip(10.0).has_focus():
		_fail("the rebuild dropped the picked chip's focus")
	var graded = LawMagnitude.scaled(_law, 10.0)
	var band: float = _main._law_panel.forecast_band(_ns(), _law.id)
	var text: String = _main._law_panel.forecast_text(_ns(), _parties(), graded, band)
	if "Forecast: " + text not in _detail_text():
		_fail("the detail's forecast is not the graded bill's: %s" % text)
	var counts: Dictionary = _main._law_panel.forecast_counts(_ns(), _parties(), graded, band)
	var plain: Dictionary = _main._law_panel.forecast_counts(_ns(), _parties(), _law, band)
	if int(counts["yes"]) == int(plain["yes"]) and int(counts["no"]) == int(plain["no"]):
		_fail("premise: ten times this bill reads as its reference (%s)" % _law.id)
	var bar := _row_bar(_law)
	if bar == null or bar.get_index() != LawGrade.BAR_COLUMN:
		_fail("the redrawn bar left its column")
	if bar == null or int(bar._parts[0]["value"]) != int(counts["yes"]):
		_fail("the row's bar is not at the grade: %s against %d" % [bar._parts[0]["value"] if bar != null else "none", counts["yes"]])
	var strip := _strip_of(LawGrade.STRIP_META)
	if String(strip.get("when", "")).find(str(int(counts["yes"]))) < 0 or String(strip.get("when", "")).find(str(int(plain["yes"]))) < 0:
		_fail("the strip does not compare the two sizes: %s (%d, %d)" % [strip.get("when", ""), counts["yes"], plain["yes"]])


## The address's strip is on the division the page shows: at the pick, not the row.
func _check_the_address_reads_the_pick() -> void:
	_list().address_open = String(_law.id)
	_list().select(String(_law.id))
	var at_pick := LawAddress.seats_text(Address.estimate(_main._state, _ns(), _main._loader, LawMagnitude.scaled(_law, 10.0)))
	var at_row := LawAddress.seats_text(Address.estimate(_main._state, _ns(), _main._loader, _law))
	if at_pick == at_row:
		_fail("premise: an address reads alike at the two sizes (%s)" % at_pick)
	if String(_strip_of(LawAddress.STRIP_META).get("money", "")) != at_pick:
		_fail("the address strip reads %s, the division at the pick %s" % [_strip_of(LawAddress.STRIP_META).get("money", ""), at_pick])
	_list().address_open = ""
	_list().select(String(_law.id))


## The strip's money, to the cent, against the same bill forced through on a copy of the game.
func _check_the_money_is_what_it_books() -> void:
	var strip := _strip_of(LawGrade.STRIP_META)
	var shown: float = float(strip.get("bn", 0.0))
	if shown >= -0.05:
		_fail("premise: a dearer bill shows a cost: %s" % shown)
	if strip.get("money", "") != EffectsStrip.sum_text(shown):
		_fail("the money line is not its figure: %s" % strip.get("money", ""))
	var sim = _main._state.duplicate_state()
	var before := Budget.snapshot(sim)
	var result: Dictionary = Legislature.propose(sim, _main._loader, _law, true, false, 10.0)
	if bool(result.get("refused", false)):
		_fail("premise: the forced road refused: %s" % result)
		return
	Budget.recompute(sim, sim.player())
	var booked := EffectsStrip.balance_bn(before, Budget.snapshot(sim))
	if absf(shown - booked) > 0.01:
		_fail("the strip says %.3f bn, the bill books %.3f bn" % [shown, booked])


func _check_the_pick_survives_a_refresh() -> void:
	_main._law_panel._refresh()
	if float(_list().grade(_law)) != 10.0 or not _chip(10.0).button_pressed:
		_fail("a refresh dropped the grade")


func _check_the_grades_offered() -> void:
	for step in LK.GRADE_STEPS:
		if not LawMagnitude.may_grade(_law, float(step), false):
			_fail("the sim refuses a grade the picker offers: %s" % step)


func _check_the_referendum_route_takes_no_grade() -> void:
	if float(_list().grade(_law, true)) != 1.0:
		_fail("the referendum route would carry a grade, which the sim refuses")
	if float(_list().grade(_plain)) != 1.0:
		_fail("a row with no size carries a grade")


func _check_the_briefing_reads_the_grade() -> void:
	if not _main._briefing.visible:
		_fail("Propose did not open the briefing")
		return
	if not is_same(_main._briefing._law, _law):
		_fail("the briefing must carry the row, never a graded copy: the sim grades it once")
	var all := PackedStringArray()
	var stack: Array = [_main._briefing]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Label or n is RichTextLabel:
			all.append(String(n.text))
		stack.append_array(n.get_children())
	var text := " | ".join(all)
	if "400 lycees" not in text:
		_fail("the briefing does not say the size")
	var graded = LawMagnitude.scaled(_law, 10.0)
	var band: float = _main._law_panel.forecast_band(_ns(), _law.id)
	if _main._law_panel.forecast_text(_ns(), _parties(), graded, band) not in text:
		_fail("the briefing's forecast is not the graded bill's")


func _check_the_grade_reached_the_sim() -> void:
	var tabled: Dictionary = _ns().tabled_bill
	if String(tabled.get("law_id", "")) != String(_law.id) or float(tabled.get("scale", 1.0)) != 10.0:
		_fail("the grade did not reach the sim: %s" % tabled)
	if not _chips().is_empty():
		_fail("a tabled bill's grade is settled: %d chips" % _chips().size())
	if "400 lycees" not in _detail_text():
		_fail("a tabled bill does not say its size")
	# Graded once: the bar reads the row and scales it, and a second grading would read 100 times.
	var c: Dictionary = _main._law_panel.forecast_counts(_ns(), _parties(), _law, LK.ABSTAIN_BAND)
	var v: Dictionary = Division.forecast(_main._state, _ns(), _main._loader)
	if int(c["yes"]) != int(v["yes_seats"]) or int(c["no"]) != int(v["no_seats"]):
		_fail("a tabled grade: the bar %d, %d, the division %d, %d" % [c["yes"], c["no"], v["yes_seats"], v["no_seats"]])


func _check_the_address_stands_beside_a_tabled_bill() -> void:
	if not _propose().disabled:
		_fail("premise: Propose is down on a tabled bill")
	if _air().disabled:
		_fail("the address is the tabled bill's verb, and it is greyed")
	if not _in_detail(func(n: Node) -> bool: return n is Button and n.has_meta(LawAddress.FOLD_META)).is_empty():
		_fail("a tabled bill's address stands open, and a fold would be a dead click")
	var strip := _strip_of(LawAddress.STRIP_META)
	if strip.is_empty():
		_fail("the address has no strip")
		return
	# estimate() takes the row, and reads the tabled grade itself.
	var est: Dictionary = Address.estimate(_main._state, _ns(), _main._loader, _law)
	var expect := LawAddress.seats_text(est)
	if String(strip["money"]) != expect:
		_fail("the strip reads %s, the estimate %s" % [strip["money"], expect])
	# Seats won are good news whichever way they are read: more for, or fewer against.
	var moved: Array = LawAddress.moved_seats(est)
	var net := float(int(moved[0]) - int(moved[1]))
	if float(strip["bn"]) != net or String(strip["tone"]) != EffectsStrip.cell_variation(EffectsStrip.money_tone(net)):
		_fail("the strip's tone is not the net of the seats it moved: %s, %s, net %s" % [strip["bn"], strip["tone"], net])
	if String(strip["who"]) != LawAddress.who_line(est["shifts"]):
		_fail("the strip's blocs are not the estimate's: %s" % strip["who"])
	_check_the_who_line()
	if String(strip["when"]).find(str(AddressK.FADE_MONTHS)) < 0:
		_fail("the strip does not say the shift fades: %s" % strip["when"])


## The parent's ruling on #303: the three blocs moved most, largest first, then a count.
func _check_the_who_line() -> void:
	var shifts := {"workers": 1.0, "pensioners": -6.0, "urban": 2.0, "rural": 5.0, "business": 0.0, "students": 3.0}
	var line := LawAddress.who_line(shifts)
	var expect := EffectsStrip.who_text({"pensioners": -6.0, "rural": 5.0, "students": 3.0})
	if not line.begins_with(expect):
		_fail("the who-line is not the three largest: '%s', wanted '%s'" % [line, expect])
	# Urban and workers are left; a bloc that did not move is no bloc at all.
	if not line.contains("2 more"):
		_fail("the who-line does not count the rest: '%s'" % line)
	var few := LawAddress.who_line({"workers": 1.0, "rural": -2.0})
	if few != EffectsStrip.who_text({"rural": -2.0, "workers": 1.0}):
		_fail("two blocs moved read as more: '%s'" % few)


## The bill just addressed has the day's line in place of the verb, and it goes with the day.
func _check_the_aired_line_goes_with_the_day() -> void:
	if "On air" not in _detail_text():
		_fail("premise: the aired line stands")
	_main._state.day += 1


## QA's merge gate: the forecast the player reads moves after an address, as the strip said.
func _check_the_address_moved_the_forecast() -> void:
	var after: Dictionary = Division.forecast(_main._state, _ns(), _main._loader)
	var dy: int = int(after["yes_seats"]) - int(_strip_before["yes_seats"])
	var dn: int = int(after["no_seats"]) - int(_strip_before["no_seats"])
	if dy == 0 and dn == 0:
		_fail("premise: the address moved no seat on %s" % _law.id)
	if String(_before["money"]) != LawAddress.delta_text(dy, dn):
		_fail("the strip promised %s, the division moved %d, %d" % [_before["money"], dy, dn])
	if (_ns().measure_opinion.get("measures", {}) as Dictionary).is_empty():
		_fail("the press gave no address")
	if _diary_repaints != 1:
		_fail("the diary took a row and the ribbon was asked to repaint %d times" % _diary_repaints)
	# The bar on screen, redrawn: its yes is the division's own walk at the page's band.
	var band: float = _main._law_panel.forecast_band(_ns(), _law.id)
	var counts: Dictionary = _main._law_panel.forecast_counts(_ns(), _parties(), _law, band)
	var bar := _row_bar(_law)
	if bar == null or int(bar._parts[0]["value"]) != int(counts["yes"]):
		_fail("the bar on screen did not redraw after the address")
	if "On air" not in _detail_text():
		_fail("the press has no answer on the page: %s" % _detail_text())


func _check_the_bill_addressed_says_so() -> void:
	if not _in_detail(func(n: Node) -> bool: return n is Button and n.has_meta(LawAddress.GO_META)).is_empty():
		_fail("a second address the same day is offered on the bill just addressed")
	if Address.refusal(_main._state, String(_law.id)) == "":
		_fail("premise: the day is taken")


## Another bill, the same day: the fold opens the strip, and the diary's reason stands under a
## grey button, read before any press.
func _check_the_refusal_is_read_before_the_press() -> void:
	if not _fold().has_focus():
		_fail("the fold's press dropped its focus")
	if not _air().disabled:
		_fail("another bill's address, the same day, is offered")
	var scroll: ScrollContainer = _list()._detail.get_parent()
	if scroll.scroll_vertical <= 0:
		_fail("premise: the column had room, so nothing here tests the scroll")
	if not scroll.get_global_rect().encloses(_air().get_global_rect()):
		_fail("the opened strip's button is out of the column's view")
	var other := Address.refusal(_main._state, String(_plain.id))
	if other == "" or other not in _detail_text():
		_fail("the diary's refusal is not on the page: '%s'" % other)


func _check_the_day_turning_lifts_the_refusal() -> void:
	if _air().disabled:
		_fail("the next day, the address is still refused: %s" % _detail_text())
	if "Not today" in _detail_text():
		_fail("the next day, the page still says not today")


func _check_a_new_game_drops_the_picks() -> void:
	var picked: float = _list().grade(_law)
	if picked != 10.0:
		_fail("premise: the pick stands: %s" % picked)
	_list()._game = null
	_list().fill(_ns(), _parties(), _list()._shown.duplicate())
	if float(_list().grade(_law)) != 1.0:
		_fail("a grade outlived its game")


## "A verb whose strip cannot be filled from the sim's own numbers is not offered."
func _check_the_strip_is_not_offered_a_dead_verb() -> void:
	var seen := 0
	for law in _list()._shown:
		_list().address_open = String(law.id)
		_list().select(String(law.id))
		if _strip_node(LawAddress.STRIP_META) == null:
			_fail("%s: no strip on the address" % law.id)
		seen += 1
		if seen >= 8:
			break


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	# The tag is on the loader's row, and the suite gives each test a process of its own.
	if _failures.is_empty():
		print("test_law_verbs: OK")
	else:
		print("test_law_verbs: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
