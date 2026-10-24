extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_load.gd
## Non-zero exit on any failure.
##
## V5.2b b2, saving and loading around an open audience.
##   - SAVING IS REFUSED while the scene is open (the parent's call, 2026-10-24: a
##     save made mid-audience reloaded as a no-show priced as a decline, and a save
##     and a load must never cost the player): the panel's Save is disabled with the
##     reason, a press anyway writes no slot, the dev console's save refuses too;
##   - a load while it is open (QA's R3 on #117), of a save made before the day:
##     the audience is closed in the discarded game (Levers' rule: never left
##     unclosed), the scene comes down, the hold line no longer names the person,
##     the loaded request is booked again, and saving is open again.
## The gossip picker (QA's R1 on #117) lists the people the president knows
## first, then by name.

const Audiences = preload("res://src/sim/audiences.gd")
const President = preload("res://src/sim/president.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")
const Capital = preload("res://src/core/capital.gd")

const SLOT := "audience_load_test"
const MID := "audience_mid_test"

var _failures: Array[String] = []
var _main
var _frame := 0
var _request := ""
var _name := ""
var _known := ""
var _before


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_open_an_audience()
		5:
			_check_picker()
			_check_save_refused()
			_load()
		8:
			_check_loaded()
			_finish()
			return true
	return false


## One request booked on its first free day and opened through the day's door,
## after the president has come to know someone late in the alphabet.
func _open_an_audience() -> void:
	var state = _main._state
	var ns = state.player()
	var loader = _main._loader
	var now: int = int(state.year) * 12 + int(state.month)
	var people: Array = loader.people.get(String(ns.id), [])
	for person in people:
		if person.wants.is_empty() or String(person.id) == String(ns.head_of_state_person_id):
			continue
		Audiences._arrive(ns, person, person.wants[0], now, [])
		_request = String(ns.audience_requests[-1]["id"])
		_name = loader.person_name(String(person.id))
		break
	for person in people:
		var id := String(person.id)
		if id != String(Audiences.request(ns, _request)["person_id"]) and President.covers(state, ns, loader, id) \
				and (_known == "" or loader.person_name(id) > loader.person_name(_known)):
			_known = id
	President.learn(state, ns, loader, _known, 0.5)
	for date in Audiences.offered_dates(state, ns, _request):
		if bool(date["free"]):
			Audiences.book(state, ns, loader, _request, date)
			# Saved while booked, before the day: the load below goes back to it.
			if SaveManager.save_game(state, _main._clock, SLOT) != "":
				_fail("premise: the save before the day failed")
			state.year = int(date["year"])
			state.month = int(date["month"])
			_main._on_day_advanced(int(date["year"]), int(date["month"]), int(date["day"]))
			break
	if not _main._windows.is_open("audience"):
		_fail("premise: the audience did not open")


func _check_picker() -> void:
	var gossip: Button = AudienceDriver.scene_of(_main).verbs.topic_button("gossip")
	var pick: OptionButton = gossip.get_parent().find_child("About", false, false) if gossip != null else null
	if pick == null or pick.item_count < 2:
		_fail("premise: no gossip picker with people in it")
		return
	if String(pick.get_item_metadata(0)) != _known:
		_fail("the person the president knows is not first in the gossip picker: %s" % pick.get_item_text(0))
	# Name order folds case and accents (QA on #120): an "É" name sorts among
	# the E's, between the D's and the F's, not after every Z.
	var accented := 0
	for i in range(1, pick.item_count):
		var here := Capital.fold(pick.get_item_text(i))
		if i >= 2 and here < Capital.fold(pick.get_item_text(i - 1)):
			_fail("the strangers are not in name order: '%s' after '%s'" % [pick.get_item_text(i), pick.get_item_text(i - 1)])
			return
		if pick.get_item_text(i).begins_with("É"):
			accented += 1
			var after := Capital.fold(pick.get_item_text(i + 1)) if i + 1 < pick.item_count else "f"
			if not (Capital.fold(pick.get_item_text(i - 1)) <= here and after.substr(0, 1) >= "e"):
				_fail("'%s' does not sort among the E's" % pick.get_item_text(i))
	if accented == 0:
		_fail("premise: no name with an accented capital in the picker to pin the fold")


func _check_save_refused() -> void:
	var panel = _main._save_load_panel
	var reason := "Finish the audience first"
	if panel.save_blocked() != reason or not panel._save_btn.disabled or panel._save_btn.tooltip_text != reason 			or panel._status.text != reason:
		_fail("Save is not refused with its reason while the audience is open: '%s'" % panel.save_blocked())
	panel._name_field.text = MID
	panel._save_btn.pressed.emit()
	var console = _console()
	if console == null:
		_fail("premise: the game scene has no dev console in a debug build")
	var said: String = console.run_command("save " + MID) if console != null else ""
	if SaveManager.list_slots().has(MID):
		_fail("a save was written while the audience was open")
		SaveManager.delete_slot(MID)
	if console != null and not said.contains(reason):
		_fail("the dev console's save did not refuse with the reason: '%s'" % said)


func _console():
	for child in _main.get_children():
		if child.has_method("run_command"):
			return child
	return null


func _load() -> void:
	_before = _main._state
	_main._on_load_requested(SLOT)


func _check_loaded() -> void:
	if _main._state == _before:
		_fail("premise: the load did not replace the game")
		return
	if String(Audiences.request(_before.player(), _request).get("status", "")) != "declined":
		_fail("the discarded game's audience was left unclosed: %s" % Audiences.request(_before.player(), _request))
	if _main._windows.is_open("audience") or AudienceDriver.scene_of(_main).visiting != "":
		_fail("the scene stayed up over the loaded game")
	if not AudienceDriver._games[_main.get_instance_id()]["session"].is_empty():
		_fail("the discarded game's session survived the load")
	if HoldReason.show(_main).contains(_name):
		_fail("the hold line still names the person after the load: '%s'" % HoldReason.show(_main))
	if String(Audiences.request(_main._state.player(), _request).get("status", "")) != "booked":
		_fail("the load did not bring back the booked request: %s" % Audiences.request(_main._state.player(), _request))
	if _main._save_load_panel.save_blocked() != "" or _main._save_load_panel._save_btn.disabled:
		_fail("saving stayed refused after the audience came down")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	SaveManager.delete_slot(SLOT)
	if _failures.is_empty():
		print("test_audience_load: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
