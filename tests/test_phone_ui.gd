extends SceneTree

## Headless test: godot --headless --script res://tests/test_phone_ui.gd
## Non-zero exit on any failure.
##
## V5.2b b3, the phone's UI over Systems' src/sim/phone.gd (the UI writes nothing):
##   - a request card's "Call them" (a real click, press and release frames apart)
##     opens the call on Phone.options()'s rows, row for row: each lever live or
##     refused with the sim's reason (the call's floor among them), dinner refused
##     by phone; the clock is held and the hold line names them;
##   - a lever pressed reaches Phone.dial() once (the month's call is spent) and its
##     result is said; Close lets the clock go, and the card's Call is then refused
##     with the sim's reason;
##   - a right click on a person in People opens a call too; with no open request
##     the levers are left off and the dialog says why;
##   - a visiting head's ask reads "wants your measure on <nation> lifted";
##   - a load during a call puts the call down (QA on #125): the dialog goes, no
##     one is on the line, the hold line no longer names them.

const Audiences = preload("res://src/sim/audiences.gd")
const Phone = preload("res://src/sim/phone.gd")
const Strings = preload("res://src/ui/strings.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const PhoneDriver = preload("res://src/ui/phone_driver.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")
const PersonCard = preload("res://src/ui/person_card.gd")
const Relations = preload("res://src/core/relations.gd")
const Words = preload("res://src/ui/lever_words.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const ResultTone = preload("res://src/ui/result_tone.gd")
const LK = preload("res://src/sim/lever_constants.gd")
const Cycle = preload("res://src/sim/cycle.gd")
const Click = preload("res://tests/click.gd")

const SLOT := "phone_ui_test"

var _failures: Array[String] = []
var _main
var _frame := 0
var _request := ""
var _asker := ""
var _target: Control
var _rang := ""
var _opening := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_stage_a_request()
			_check_visitor_words()
			_main._clock.paused = false
		5:
			_target = _answer("Call them…")
			_click(true, MOUSE_BUTTON_LEFT)
		9:
			_click(false, MOUSE_BUTTON_LEFT)
		11:
			_check_dialog()
			_press_a_verb()
		13:
			_check_dialed()
			_check_won_call_tone()
			PhoneDriver.dialog_of(_main)._close.pressed.emit()
		15:
			_check_hung_up()
			_main._windows.open("people")
			# The default view lists only who needs you; the politicians' group lists people.
			_main._people_panel._pick_chip("politicians")
		19:
			_target = _people_row()
			_click(true, MOUSE_BUTTON_RIGHT)
		23:
			# The press focused the line and the roster rebuilt under it: release on the new one.
			_target = _people_row()
			_click(false, MOUSE_BUTTON_RIGHT)
		25:
			# Rework 1: a right click on a roster line opens its verbs; Call is one of them.
			_press_plate_call()
		27:
			_check_people_call()
			_call_then_load()
		29:
			_check_loaded()
			_finish()
			return true
	return false


## The call's wiring with a catcher for a dialog: what tone the result is said in,
## and the feelings after the call (V5.3-0 (e): the mood line reads them).
class ToneCatcher:
	var tone := "unset"
	var feel = null
	func show_result(_text: String, _titles: Array = [], _extra := {}, said_tone := "", after := {}) -> void:
		tone = said_tone
		feel = after


## QA's TAKE 1 on #209, the phone's half: a WON lever's call carries the GOOD tag.
## A second person asks; the call is rigged to win through the sim's own seeded
## roll (Phone.dial), under the offered lever's floor -- the true odds are inside
## the shown range, so the try cannot fail. A bargain (its currency) is left out.
func _check_won_call_tone() -> void:
	var state = _main._state
	var ns = state.player()
	var now: int = int(state.year) * 12 + int(state.month)
	var pid := ""
	for person in _main._loader.people.get(String(ns.id), []):
		if pid == "" and not person.wants.is_empty() and String(person.id) != _asker and String(person.id) != String(ns.head_of_state_person_id):
			Audiences._arrive(ns, person, person.wants[0], now, [])
			pid = String(person.id)
	var best := {}
	for row in Phone.options(state, ns, _main._loader, pid)["levers"]:
		if bool(row["offered"]) and String(row["lever"]) != "bargain" and float(row.get("odds_lo", 0.0)) > float(best.get("odds_lo", 0.0)):
			best = row
	if best.is_empty():
		_fail("premise: no lever a second caller could win")
		return
	var lever := String(best["lever"])
	for seed in range(1, 20000):
		if Cycle.unit_pair(pid, Cycle.salted("%s:%s" % [LK.SALT_PHONE, lever], seed), now) < float(best["odds_lo"]):
			ns.draw_seed = seed
			break
	var catcher := ToneCatcher.new()
	var args := {"due_month": now + LK.PROMISE_MIN_MONTHS} if lever == "promise_date" else {}
	PhoneDriver._dial(_main, {"person_id": pid, "dialog": catcher, "on_change": func() -> void: pass}, lever, args)
	if catcher.tone != ResultTone.GOOD:
		_fail("a won call's result is not said in the good tone: '%s'" % catcher.tone)
	if not (catcher.feel is Dictionary) or not (catcher.feel as Dictionary).has("rapport"):
		_fail("the call's result carries no feelings after it, so a band it crossed is never said: %s" % str(catcher.feel))


func _stage_a_request() -> void:
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	for person in _main._loader.people.get(String(ns.id), []):
		if person.wants.is_empty() or String(person.id) == String(ns.head_of_state_person_id):
			continue
		Audiences._arrive(ns, person, person.wants[0], now, [])
		_request = String(ns.audience_requests[-1]["id"])
		_asker = String(person.id)
		break
	AudienceDriver.refresh(_main)


## Audiences' visitor grammar (audience_triggers.gd): "measure:<directed key>".
func _check_visitor_words() -> void:
	var ns = _main._state.player()
	var other := ""
	for id in _main._loader.nations.keys():
		if String(id) != String(ns.id):
			other = String(id)
			break
	var object := "measure:%s" % Relations.directed_key(String(ns.id), other)
	var line := "%s %s" % [PersonCard.stance_label("want"), PersonCard.object_text(_main._loader, ns, object, {"object": object})]
	var want := "wants your measure on %s lifted" % String(_main._loader.nations[other].nation_name)
	if line != want:
		_fail("a visitor's ask reads '%s', not '%s'" % [line, want])


func _check_dialog() -> void:
	var dialog = PhoneDriver.dialog_of(_main)
	if dialog == null or not dialog.visible:
		_fail("Call them did not open the phone")
		return
	var name: String = _main._loader.person_name(_asker)
	if not dialog._title.text.contains(name):
		_fail("the call does not name the person: '%s'" % dialog._title.text)
	var o := Phone.options(_main._state, _main._state.player(), _main._loader, _asker)
	for row in o["levers"]:
		var b: Button = dialog.verbs.lever_button(String(row["lever"]))
		if b == null:
			_fail("lever %s has no button on the phone" % row["lever"])
		elif b.disabled == bool(row["offered"]) or (not bool(row["offered"]) and b.tooltip_text != Words.reason(String(row["why_not"]))):
			_fail("lever %s shows %s '%s', the sim says offered=%s '%s'" % [row["lever"], "down" if b.disabled else "live", b.tooltip_text, row["offered"], row["why_not"]])
	var dinner: Button = dialog.verbs.topic_button("dinner")
	if dinner == null or not dinner.disabled or not dinner.tooltip_text.begins_with("not by phone"):
		_fail("dinner is not refused by phone: '%s'" % (dinner.tooltip_text if dinner != null else "none"))
	if not _main._clock.paused:
		_fail("a call does not hold the clock")
	if not HoldReason.show(_main).contains(name):
		_fail("the hold line does not name who is on the phone: '%s'" % HoldReason.show(_main))
	# Content's phone_opening (#126): every variant names the ask.
	var ns = _main._state.player()
	var request := Audiences.request(ns, _request)
	var ask := PersonCard.object_text(_main._loader, ns, String(request["object"]), request)
	if not dialog._line.text.contains(ask):
		_fail("the call does not open on the person's phone line about '%s': '%s'" % [ask, dialog._line.text])
	_opening = dialog._line.text


## The first offered lever, else a topic: what the sim lets this call try.
func _press_a_verb() -> void:
	var dialog = PhoneDriver.dialog_of(_main)
	for row in Phone.options(_main._state, _main._state.player(), _main._loader, _asker)["levers"]:
		if bool(row["offered"]):
			_rang = String(row["lever"])
			dialog.verbs.lever_button(_rang).pressed.emit()
			return
	_rang = "family"
	dialog.verbs.topic_button("family").pressed.emit()


func _check_dialed() -> void:
	var dialog = PhoneDriver.dialog_of(_main)
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	if int(ns.phone_calls.get(_asker, -1)) != now:
		_fail("pressing %s did not reach Phone.dial(): %s" % [_rang, ns.phone_calls])
	if dialog._result.text == "" or dialog.verbs.visible:
		_fail("the call's result is not said, or its verbs stayed up: '%s'" % dialog._result.text)
	if dialog._line.text == "" or dialog._line.text == _opening:
		_fail("the call does not end in the person's own words: '%s'" % dialog._line.text)
	# V5.2 close R5: a lever's call result carries its toned word, agreeing with it.
	if _rang != "family":
		var won: bool = dialog._result.text.begins_with(dialog.tr("They agree: the request is answered by phone."))
		var tag: Array = ResultTone.TAG[ResultTone.GOOD if won else ResultTone.BAD]
		if not dialog._tone.visible or dialog._tone.theme_type_variation != String(tag[0]) or dialog._tone.text != dialog.tr(String(tag[1])):
			_fail("the call's lever result carries no tone, or the wrong one: '%s'" % dialog._tone.text)


func _check_hung_up() -> void:
	if PhoneDriver.dialog_of(_main).visible:
		_fail("Close left the phone up")
	if _main._clock.paused and not _main._decision_holds_clock():
		_fail("hanging up did not let the clock go")
	# A lever that worked answers the request by phone: the card goes. Otherwise
	# it stays, and its Call is refused with the sim's own reason.
	if String(Audiences.request(_main._state.player(), _request).get("status", "")) != "pending":
		if AudienceDriver.lane_of(_main).card_of(_request) != "":
			_fail("a request answered by phone kept its card")
		return
	var call := _answer("Call them…") as Button
	var why := String(Phone.options(_main._state, _main._state.player(), _main._loader, _asker)["why_not"])
	if why == "" or call == null or not call.disabled or call.tooltip_text != Words.reason(why):
		_fail("after the month's call the card's Call is not refused with the sim's reason: '%s'" % why)


## A person's line on the roster (rework 1): its press target, the button under the cells.
func _people_row() -> Control:
	for node in _main._people_panel._body.find_children("*", "Button", true, false):
		var wrap: Node = node.get_parent()
		if node.has_meta("line") and wrap.has_meta("person"):
			return node
	return null


## The rework pass's C: the right click picked the line and lit its verbs (the strip under it, no focus): press its Call.
func _press_plate_call() -> void:
	var people = _main._people_panel
	var focus = _main.get_viewport().gui_get_focus_owner()
	var strip = null
	for node in people.find_children("*", "", true, false):
		if node.has_meta("verb_block") and (node as Control).is_visible_in_tree():
			strip = node
	if strip == null:
		_fail("a right click on a person in People did not light its verbs")
		return
	if focus != null and people.is_ancestor_of(focus):
		_fail("a right click on a person in People gave the keyboard to %s" % focus)
	for button in strip.find_children("*", "Button", true, false):
		if (button as Button).text.begins_with(Strings.t("Call: no day, worse odds").get_slice(":", 0)):
			(button as Button).pressed.emit()
			return
	_fail("the right click's verbs offer no Call")


func _check_people_call() -> void:
	var dialog = PhoneDriver.dialog_of(_main)
	if dialog == null or not dialog.visible:
		_fail("the roster's Call did not open a call")
		return
	var pid := String(PhoneDriver._games[_main.get_instance_id()]["person_id"])
	var o := Phone.options(_main._state, _main._state.player(), _main._loader, pid)
	if String(o["why_not"]) != "":
		if dialog._why.text != Words.reason(String(o["why_not"])):
			_fail("a refused call does not open on the sim's reason: '%s'" % dialog._why.text)
	elif String(o["request_id"]) == "":
		if not dialog.verbs.find_children("Lever_*", "Button", true, false).is_empty() or not dialog._why.text.contains("asked you for nothing"):
			_fail("a call to someone with no open request shows levers, or does not say why: '%s'" % dialog._why.text)
	dialog._close.pressed.emit()


func _call_then_load() -> void:
	if SaveManager.save_game(_main._state, _main._clock, SLOT) != "":
		_fail("premise: the save failed")
		return
	PhoneDriver.open_call(_main, _asker, [])
	if not PhoneDriver.dialog_of(_main).visible:
		_fail("premise: the call did not open before the load")
	_main = _main._on_load_requested(SLOT)


func _check_loaded() -> void:
	var name: String = _main._loader.person_name(_asker)
	if PhoneDriver.dialog_of(_main).visible or PhoneDriver.calling(_main) != "":
		_fail("a load left the call up over the loaded game")
	if HoldReason.show(_main).contains(name):
		_fail("the hold line still names the caller after the load: '%s'" % HoldReason.show(_main))


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
	Click.half(_main.get_viewport(), _target, down, button)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	SaveManager.delete_slot(SLOT)
	if _failures.is_empty():
		print("test_phone_ui: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
