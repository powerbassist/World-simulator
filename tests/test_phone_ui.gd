extends SceneTree

## Headless test: godot --headless --script res://tests/test_phone_ui.gd
## Non-zero exit on any failure.
##
## V5.2b b3, the phone's UI, against the plan's two commands (v5.2b3-plan.md
## section 1: Phone.options / Phone.dial). Systems' module is not in yet, so a
## STAND-IN lives here, in the test only, and is handed to phone_driver.gd:
##   - with no phone module the request card offers no call;
##   - with one, the card's "Call them" (a real click, press and release frames
##     apart) opens the dialog on the sim's rows: a range on an offered lever, a
##     lever below the call's floor refused "too long a shot for a call", dinner
##     refused "not by phone"; the clock is held and the hold line names them;
##   - a lever dials once and says the result; Close lets the clock go, and the
##     card's Call is then refused with the sim's reason (one call a month);
##   - a right click on a person in People opens a call too, topics only when they
##     have asked for nothing.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const PhoneDriver = preload("res://src/ui/phone_driver.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")


## The plan's shapes, nothing more: options() says what may be tried, dial()
## records the try and spends the month's call.
class StandIn:
	var asker := ""
	var called := {}
	var dialed := []

	func options(state, _ns, _loader, person_id: String) -> Dictionary:
		var now: int = int(state.year) * 12 + int(state.month)
		if int(called.get(person_id, -1)) == now:
			return {"why_not": "you have called them this month", "request_id": "", "levers": [], "topics": []}
		var levers: Array = []
		if person_id == asker:
			levers = [
				{"lever": "argue", "offered": true, "why_not": "", "odds_lo": 0.2, "odds_hi": 0.5, "fog": "stranger", "spends": {}},
				{"lever": "pressure", "offered": false, "why_not": "too long a shot for a call", "odds_lo": 0.0, "odds_hi": 0.0, "fog": "stranger", "spends": {"rapport": -0.06}},
			]
		return {"why_not": "", "request_id": "", "levers": levers, "topics": [
			{"topic": "family", "offered": true, "why_not": "", "spends": {"attempt": 1}},
			{"topic": "dinner", "offered": false, "why_not": "not by phone", "spends": {"attempt": 1}},
		]}

	func dial(state, _ns, _loader, person_id: String, what: String, args := {}) -> Dictionary:
		called[person_id] = int(state.year) * 12 + int(state.month)
		dialed.append([person_id, what, args])
		return {"ok": true, "error": "", "success": false, "spent": {}, "effects": {"rapport": 0.04}}


var _failures: Array[String] = []
var _main
var _frame := 0
var _stand_in := StandIn.new()
var _request := ""
var _target: Control


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_stage_a_request()
			_check_no_phone()
			PhoneDriver.backend = _stand_in
			_main._clock.paused = false
			AudienceDriver.refresh(_main)
		5:
			_target = _answer("Call them…")
			_click(true, MOUSE_BUTTON_LEFT)
		9:
			_click(false, MOUSE_BUTTON_LEFT)
		11:
			_check_dialog()
			PhoneDriver.dialog_of(_main).verbs.lever_button("argue").pressed.emit()
		13:
			_check_dialed()
			PhoneDriver.dialog_of(_main)._close.pressed.emit()
		15:
			_check_hung_up()
			_main._windows.open("people")
		19:
			_target = _people_row()
			_click(true, MOUSE_BUTTON_RIGHT)
		23:
			_click(false, MOUSE_BUTTON_RIGHT)
		25:
			_check_people_call()
			PhoneDriver.backend = null
			_finish()
			return true
	return false


func _stage_a_request() -> void:
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	for person in _main._loader.people.get(String(ns.id), []):
		if person.wants.is_empty() or String(person.id) == String(ns.head_of_state_person_id):
			continue
		Audiences._arrive(ns, person, person.wants[0], now, [])
		_request = String(ns.audience_requests[-1]["id"])
		_stand_in.asker = String(person.id)
		break
	AudienceDriver.refresh(_main)


func _check_no_phone() -> void:
	if ResourceLoader.exists(PhoneDriver.PHONE):
		return  # Systems' module has landed: the stand-in's premise is spent
	if _answer("Call them…") != null:
		_fail("with no phone module the request card still offers a call")


func _check_dialog() -> void:
	var dialog = PhoneDriver.dialog_of(_main)
	if dialog == null or not dialog.visible:
		_fail("Call them did not open the phone")
		return
	var name: String = _main._loader.person_name(_stand_in.asker)
	if not dialog._title.text.contains(name):
		_fail("the call does not name the person: '%s'" % dialog._title.text)
	var argue: Button = dialog.verbs.lever_button("argue")
	if argue == null or argue.disabled:
		_fail("the offered lever is not live on the phone")
	var pressure: Button = dialog.verbs.lever_button("pressure")
	if pressure == null or not pressure.disabled or pressure.tooltip_text != "too long a shot for a call":
		_fail("a lever below the call's floor is not refused with its reason")
	var dinner: Button = dialog.verbs.topic_button("dinner")
	if dinner == null or not dinner.disabled or dinner.tooltip_text != "not by phone":
		_fail("dinner is not refused by phone")
	if not _main._clock.paused:
		_fail("a call does not hold the clock")
	if not HoldReason.show(_main).contains(name):
		_fail("the hold line does not name who is on the phone: '%s'" % HoldReason.show(_main))


func _check_dialed() -> void:
	var dialog = PhoneDriver.dialog_of(_main)
	if _stand_in.dialed.size() != 1 or _stand_in.dialed[0][1] != "argue":
		_fail("the lever did not reach Phone.dial once: %s" % [_stand_in.dialed])
	if not dialog._result.text.contains("not moved") or dialog.verbs.visible:
		_fail("the call's result is not said, or its verbs stayed up: '%s'" % dialog._result.text)


func _check_hung_up() -> void:
	if PhoneDriver.dialog_of(_main).visible:
		_fail("Close left the phone up")
	if _main._clock.paused and not _main._decision_holds_clock():
		_fail("hanging up did not let the clock go")
	var call := _answer("Call them…") as Button
	if call == null or not call.disabled or call.tooltip_text != "you have called them this month":
		_fail("after the month's call the card's Call is not refused with the sim's reason")


## The second face row (the first is the president, whom the real module refuses).
func _people_row() -> Control:
	var rows: Array = _main._people_panel._body.get_children().filter(func(c): return c is HBoxContainer)
	return rows[1] if rows.size() > 1 else null


func _check_people_call() -> void:
	var dialog = PhoneDriver.dialog_of(_main)
	if dialog == null or not dialog.visible:
		_fail("a right click on a person in People did not open a call")
		return
	if not dialog.verbs.find_children("Lever_*", "Button", true, false).is_empty():
		_fail("a call to someone who asked nothing offers levers")
	if not dialog._why.text.contains("asked you for nothing"):
		_fail("the call does not say why there are no levers: '%s'" % dialog._why.text)
	dialog._close.pressed.emit()


func _answer(label: String) -> Control:
	var card = _main._hud.inbox._cards.get(AudienceDriver.lane_of(_main).card_of(_request))
	if card == null:
		return null
	for b in card.find_children("*", "Button", true, false):
		if (b as Button).text == label:
			return b
	return null


func _click(down: bool, button: int) -> void:
	if _target == null:
		_fail("nothing to click (%d)" % button)
		return
	var at: Vector2 = _target.get_global_rect().get_center()
	var click := InputEventMouseButton.new()
	click.button_index = button
	click.pressed = down
	click.position = at
	click.global_position = at
	_main.get_viewport().push_input(click, true)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_phone_ui: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
