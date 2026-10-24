extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_load.gd
## Non-zero exit on any failure.
##
## V5.2b b2, a load while an audience is open (QA's R3 on #117). Levers' rule is
## that a session is never left unclosed (Systems' R3 on #113):
##   - the audience is closed in the game it was opened in, the discarded one;
##   - the scene comes down and the hold line no longer names the person;
##   - the loaded game is the save's: a save made mid-audience holds the request,
##     and the sim's no-show prices it -- the UI opens no session on it.
## The gossip picker (QA's R1 on #117) lists the people the president knows
## first, then by name.

const Audiences = preload("res://src/sim/audiences.gd")
const President = preload("res://src/sim/president.gd")
const SaveManager = preload("res://src/core/save_manager.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")

const SLOT := "audience_load_test"

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
			_save_and_load()
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
	for i in range(2, pick.item_count):
		if pick.get_item_text(i).naturalnocasecmp_to(pick.get_item_text(i - 1)) < 0:
			_fail("the strangers are not in name order: '%s' after '%s'" % [pick.get_item_text(i), pick.get_item_text(i - 1)])
			return


func _save_and_load() -> void:
	_before = _main._state
	var error := SaveManager.save_game(_main._state, _main._clock, SLOT)
	if error != "":
		_fail("premise: the save failed: %s" % error)
		return
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
	if String(Audiences.request(_main._state.player(), _request).get("status", "")) != "held":
		_fail("the save made mid-audience did not keep the request held: %s" % Audiences.request(_main._state.player(), _request))


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_audience_load: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
