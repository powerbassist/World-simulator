extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_flow.gd
## Non-zero exit on any failure.
##
## V5.2b, a request from arrival to the scene, through the real game and the sim's
## own commands (src/sim/audiences.gd; the UI writes no register):
##   - a pending request is a card in the REQUESTS lane and the title bar counts it;
##     its arrival does not hold the clock;
##   - Decline, a real click held for frames, closes it in the sim and prices it;
##   - Book opens the Diary on the person's offered days; a free one books it;
##   - on the booked day the diary opens the audience: a scene that holds the
##     clock and names the person on the hold line; ending it settles the request
##     and lets the clock go;
##   - a month run through main's own month runner and step hook leaves the lane
##     equal to the register: that month's lapse gone, its arrivals carded, the
##     count current (QA on #105: refreshed at Events, it was a month behind).

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _first := ""
var _second := ""
var _target: Button
var _booked_on := {}
var _lapsing := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_stage_two_requests()
			_main._clock.paused = false
			AudienceDriver.refresh(_main)
		5:
			_check_cards()
			_target = _answer(_first, 2)
			_press(true)
		9:
			_press(false)
		11:
			_check_declined()
			var book := _answer(_second, 0)
			if book != null:
				book.pressed.emit()
		13:
			_book_a_free_day()
		15:
			_reach_the_day()
		17:
			_check_scene()
			AudienceDriver.scene_of(_main).closed.emit()
		19:
			_check_ended()
			_run_a_month()
		_ when _frame > 19 and not _main._month_runner.running():
			_check_month()
			_finish()
			return true
	return false


## Two people of the played nation with a want, asking through the sim's own
## arrival (the register is the sim's; the test only stages who asks).
func _stage_two_requests() -> void:
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	var asked := 0
	for person in _main._loader.people.get(String(ns.id), []):
		if person.wants.is_empty() or asked >= 2 or String(person.id) == String(ns.head_of_state_person_id):
			continue
		Audiences._arrive(ns, person, person.wants[0], now, [])
		asked += 1
	var pending := Audiences.pending(ns)
	if pending.size() < 2:
		_fail("premise: could not stage two requests (%d)" % pending.size())
		return
	_first = String(pending[0]["id"])
	_second = String(pending[1]["id"])


func _check_cards() -> void:
	var lane = AudienceDriver.lane_of(_main)
	for id in [_first, _second]:
		if lane.card_of(id) == "":
			_fail("request %s has no card" % id)
	if not String(_main._hud.title_bar.requests_text()).contains("2 requests waiting"):
		_fail("the title bar does not count two waiting: '%s'" % _main._hud.title_bar.requests_text())
	if _main._clock.paused:
		_fail("a request's arrival held the clock")


func _check_declined() -> void:
	var ns = _main._state.player()
	if String(Audiences.request(ns, _first).get("status", "")) != "declined":
		_fail("a held click on Decline did not decline the request in the sim: %s" % Audiences.request(ns, _first))
	if AudienceDriver.lane_of(_main).card_of(_first) != "":
		_fail("the declined request kept its card")


func _book_a_free_day() -> void:
	var ns = _main._state.player()
	if not _main._windows.is_open("calendar") or _main._calendar_panel.audience.request_id() != _second:
		_fail("Book did not open the Diary on the request")
		return
	for date in Audiences.offered_dates(_main._state, ns, _second):
		if bool(date["free"]):
			_booked_on = date
			break
	if _booked_on.is_empty():
		_fail("premise: no offered day is free")
		return
	_main._calendar_panel.audience.booked.emit(_second, _booked_on)
	if String(Audiences.request(ns, _second).get("status", "")) != "booked":
		_fail("booking the free day did not book the request")


func _reach_the_day() -> void:
	if _booked_on.is_empty():
		return
	_main._clock.paused = false
	_main._resolve_appointments(int(_booked_on["year"]), int(_booked_on["month"]), int(_booked_on["day"]))


func _check_scene() -> void:
	var ns = _main._state.player()
	if not _main._windows.is_open("audience"):
		_fail("the booked day did not open the audience")
		return
	if not _main._clock.paused:
		_fail("the audience did not hold the clock")
	if String(Audiences.request(ns, _second).get("status", "")) != "held":
		_fail("the sim does not hold the audience: %s" % Audiences.request(ns, _second))
	var line := preload("res://src/ui/hold_reason.gd").show(_main)
	if not line.contains(AudienceDriver.scene_of(_main).visiting) or AudienceDriver.scene_of(_main).visiting.is_empty():
		_fail("the hold line does not name the person: '%s'" % line)


func _check_ended() -> void:
	var ns = _main._state.player()
	if _main._windows.is_open("audience"):
		_fail("ending the audience left its window open")
	if String(Audiences.request(ns, _second).get("status", "")) != "declined":
		_fail("an audience ended with no lever won did not settle as a refusal: %s" % Audiences.request(ns, _second))
	if _main._clock.paused and not _main._decision_holds_clock():
		_fail("ending the audience did not let the clock go")


## A third person's request staged to fall due next month, then that month run
## the way the clock runs one (main's handler, its runner, its step hook).
func _run_a_month() -> void:
	var ns = _main._state.player()
	var next: int = int(_main._state.year) * 12 + int(_main._state.month) + 1
	for person in _main._loader.people.get(String(ns.id), []):
		var id := String(person.id)
		if person.wants.is_empty() or id == String(ns.head_of_state_person_id) or ns.audience_asked_month.has(id):
			continue
		Audiences._arrive(ns, person, person.wants[0], next - Audiences.K.REQUEST_WINDOW_MONTHS, [])
		_lapsing = String(ns.audience_requests[-1]["id"])
		break
	AudienceDriver.refresh(_main)
	if _lapsing == "" or AudienceDriver.lane_of(_main).card_of(_lapsing) == "":
		_fail("premise: no request staged to lapse next month")
	var year := floori((next - 1) / 12.0)
	_main._on_month_elapsed(year, next - year * 12)


func _check_month() -> void:
	var ns = _main._state.player()
	var lane = AudienceDriver.lane_of(_main)
	if String(Audiences.request(ns, _lapsing).get("status", "")) != "lapsed":
		_fail("premise: the staged request did not lapse at the month: %s" % Audiences.request(ns, _lapsing))
	if lane.card_of(_lapsing) != "":
		_fail("the month's lapse kept its card after the month ran")
	var live: Array = []
	for row in Audiences.pending(ns):
		live.append(String(row["id"]))
		if lane.card_of(String(row["id"])) == "":
			_fail("request %s (arrived %d) is pending and has no card after the month" % [row["id"], int(row["arrived_month"])])
	for id in lane.request_ids():
		if not live.has(id):
			_fail("card for %s stayed though the register no longer holds it" % id)
	if Audiences.waiting_count(ns) > 0 and not String(_main._hud.title_bar.requests_text()).contains(str(Audiences.waiting_count(ns))):
		_fail("the title bar's count is not the register's after the month: '%s'" % _main._hud.title_bar.requests_text())


func _answer(request_id: String, index: int) -> Button:
	var card = _main._hud.inbox._cards.get(AudienceDriver.lane_of(_main).card_of(request_id))
	if card == null:
		return null
	var buttons: Array = []
	for b in card.find_children("*", "Button", true, false):
		if (b as Button).text != "X":
			buttons.append(b)
	return buttons[index] if index < buttons.size() else null


func _press(down: bool) -> void:
	if _target == null:
		_fail("no answer button to click")
		return
	var at: Vector2 = _target.get_global_rect().get_center()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = down
	click.position = at
	click.global_position = at
	_main.get_viewport().push_input(click, true)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_audience_flow: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
