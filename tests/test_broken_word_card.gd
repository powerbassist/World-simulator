extends SceneTree

## Headless test: godot --headless --script res://tests/test_broken_word_card.gd
## Non-zero exit on any failure.
##
## V5.2 c1c's interface half (docs/design/bands-v5.2.md "c1c", rule 1; Systems' #185):
## a person holding something on the president takes a refusal as a broken word, and
## Audiences.decline_price() already counts it and flags `broken_word`. The request
## card says why that refusal costs more -- and only for such a person:
##   - the same request, no evidence: no reason line;
##   - evidence left the month before it arrived: the reason line, and the price the
##     card prints is decline_price's own, broken word included.

const Audiences = preload("res://src/sim/audiences.gd")
const President = preload("res://src/sim/president.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const RequestLane = preload("res://src/ui/request_lane.gd")
const AudienceTalks = preload("res://src/ui/audience_talks.gd")
const Levers = preload("res://src/sim/levers.gd")

const REASON := "They hold something on you. Refusing them breaks your word."

## The scene's close line, caught: AudienceTalks.end() only calls show_close().
class CloseCatcher:
	var text := ""
	func show_close(_outcome: String, said: String) -> void:
		text = said


var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	_check()
	if _failures.is_empty():
		print("PASS tests/test_broken_word_card.gd")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: " + f)
		quit(1)
	return true


func _check() -> void:
	var state = _main._state
	var ns = state.player()
	var person = null
	for p in _main._loader.people.get(String(ns.id), []):
		if not p.wants.is_empty() and String(p.id) != President.leader_id(ns):
			person = p
			break
	if person == null:
		_failures.append("fixture: no person with a want")
		return
	var now: int = int(state.year) * 12 + int(state.month)
	Audiences._arrive(ns, person, person.wants[0], now, [])
	var request: Dictionary = ns.audience_requests[-1]

	var plain: Dictionary = AudienceDriver.row_of(_main, request)
	if bool(plain.get("broken_word", false)) or RequestLane._body(plain).contains(REASON):
		_failures.append("a person holding nothing gets the broken-word line")

	ns.exposure_evidence.append({"kind": "favour", "person_id": String(person.id), "size": 1.0,
		"month": int(request.get("arrived_month", now)) - 1, "leader_id": President.leader_id(ns)})
	var held: Dictionary = AudienceDriver.row_of(_main, request)
	var body := RequestLane._body(held)
	if not body.contains(REASON):
		_failures.append("an accomplice's card does not say the refusal breaks a word: '%s'" % body)
	if String(held["price"]) == String(plain["price"]):
		_failures.append("the card's decline price is the same with and without the broken word: '%s'" % held["price"])

	# An audience with the same person ended with nothing won settles as a decline,
	# which is a crossing too: the scene's close says why it cost a broken word.
	var id := String(request["id"])
	for date in Audiences.offered_dates(state, ns, id):
		if bool(date["free"]):
			Audiences.book(state, ns, _main._loader, id, date)
			state.year = int(date["year"])
			state.month = int(date["month"])
			state.day = int(date["day"])
			break
	var session: Dictionary = Levers.open(state, ns, _main._loader, id)
	if session.is_empty():
		_failures.append("fixture: the accomplice's audience did not open")
		return
	var scene := CloseCatcher.new()
	AudienceTalks.end(_main, {"session": session, "scene": scene})
	if not scene.text.contains("Refusing them broke your word."):
		_failures.append("an audience ended as a decline with an accomplice does not say it broke a word: '%s'" % scene.text)
