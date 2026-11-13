extends SceneTree

## Headless test: godot --headless --script res://tests/test_audience_levers.gd
## Non-zero exit on any failure.
##
## V5.2b b2, the audience's levers through the real game and the sim's own
## commands (src/sim/levers.gd; the UI writes no register):
##   - the booked day opens Levers' session: the scene's ranges are the ones
##     Levers.offered() prints, before and after a verb;
##   - a real click on a lever (press and release frames apart) reaches
##     Levers.attempt(): an attempt is spent and the result is said;
##   - a promise made from the scene is a commitment in the register AND a line in
##     the Diary with its date, whether or not the lever worked ("parole donnée");
##     a lever that already won leaves the others down with the sim's reason;
##   - a topic spends an attempt and says what was learnt;
##   - End closes it in the sim (promised, settled or declined as the session
##     says) and keeps the scene up; Leave takes it down and frees the clock;
##   - a promise falling due is judged at the month, through main's own runner,
##     and the verdict is a card naming the person; the Diary drops it.

const Audiences = preload("res://src/sim/audiences.gd")
const Levers = preload("res://src/sim/levers.gd")
const DealK = preload("res://src/sim/deal_constants.gd")
const President = preload("res://src/sim/president.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Words = preload("res://src/ui/lever_words.gd")
const AudienceTalks = preload("res://src/ui/audience_talks.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _request := ""
var _person := ""
var _due_person := ""
var _delegated_person := ""
var _promised_due := -1


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_open_an_audience()
		5:
			_check_open()
			_pick_a_day()
			_press(true)
		9:
			_press(false)
		11:
			_check_attempt()
			_promise()
		13:
			_check_promise()
			AudienceTalks.ask(_main, AudienceDriver._games[_main.get_instance_id()], "family", "family", {})
		15:
			_check_topic()
			_scene()._end.pressed.emit()
		17:
			_check_end()
			_scene()._end.pressed.emit()
		19:
			_check_left()
			_run_a_month_with_a_promise_due()
		_ when _frame > 19 and not _main._month_runner.running():
			_check_verdict()
			_finish()
			return true
	return false


func _scene():
	return AudienceDriver.scene_of(_main)


func _session() -> Dictionary:
	return AudienceDriver._games[_main.get_instance_id()]["session"]


## One request, booked through the sim's command on its first free day, and that
## day reached through the game's own day door.
func _open_an_audience() -> void:
	var state = _main._state
	var ns = state.player()
	var now: int = int(state.year) * 12 + int(state.month)
	for person in _main._loader.people.get(String(ns.id), []):
		if person.wants.is_empty() or String(person.id) == String(ns.head_of_state_person_id):
			continue
		Audiences._arrive(ns, person, person.wants[0], now, [])
		_request = String(ns.audience_requests[-1]["id"])
		_person = String(person.id)
		break
	var day := {}
	for date in Audiences.offered_dates(state, ns, _request):
		if bool(date["free"]):
			day = date
			break
	if day.is_empty() or not bool(Audiences.book(state, ns, _main._loader, _request, day).get("ok", false)):
		_fail("premise: could not book the request")
		return
	state.year = int(day["year"])
	state.month = int(day["month"])
	_main._on_day_advanced(int(day["year"]), int(day["month"]), int(day["day"]))


func _check_open() -> void:
	if not _main._windows.is_open("audience") or _session().is_empty():
		_fail("the booked day did not open Levers' session in the scene")


## The Counter's day, picked on the field: a day inside the window the row gives.
func _pick_a_day() -> void:
	var field = _scene().cards.date_pick
	if field == null:
		_fail("no Counter field on the question")
		return
	_promised_due = field._first + 2
	field.choose(10, _promised_due)


## The word binds only when she took the Counter (the author's ruling, Systems' #323): both
## sides of that rule read the same, so this holds on either side of it.
var _won_promise := false


func _check_attempt() -> void:
	_won_promise = String(_session().get("won", "")) == "promise_date"
	if int(_session().get("attempts_left", 0)) != 2:
		_fail("a held click on Counter did not reach Deal.bargain(): %s" % [_session()])
	if _scene()._result.text == "":
		_fail("the attempt's result is not said")
	# One counter per audience (the parent's ruling, QA #324): a Counter she did not take closes the
	# Counter's button AND its date field, and leaves Grant and Refuse open.
	if not _won_promise:
		var counter: Button = _scene().cards.find_child("CounterButton", true, false) as Button
		if counter == null or not counter.disabled:
			_fail("the Counter stayed open after a Counter she did not take")
		if _scene().cards.date_pick == null or not _scene().cards.date_pick.disabled:
			_fail("the Counter's date field stayed open after a Counter she did not take")


func _promise() -> void:
	pass


func _check_promise() -> void:
	if _promised_due < 0:
		return
	var ns = _main._state.player()
	var found := false
	for row in President.commitments_with(ns, _person):
		found = found or (String(row["kind"]) == "promise" and int(row["due_month"]) == _promised_due)
	# The author's ruling of 2026-11-13 (#323): a promise the person refused binds nothing.
	if not _won_promise:
		if found:
			_fail("a refused promise wrote a commitment: %s" % [ns.commitments])
		return
	if not found:
		_fail("the promise made in the scene is not a commitment in the register: %s" % [ns.commitments])
	if not _diary_has(_main._loader.person_name(_person), Words.when(_promised_due)):
		_fail("the Diary does not show the promise with its date: %s" % [_diary()])


func _check_topic() -> void:
	var left := 1  # the Counter and the topic: two of the three attempts
	if int(_session().get("attempts_left", -1)) != left:
		_fail("the topic did not spend an attempt: %s" % [_session()])
	if not _scene()._result.text.contains("know them better"):
		_fail("the topic does not say what was learnt: '%s'" % _scene()._result.text)


func _check_end() -> void:
	var ns = _main._state.player()
	var won := String(_session().get("won", ""))
	var want := "declined" if won == "" else ("promised" if won == "promise_date" else "settled")
	if String(Audiences.request(ns, _request).get("status", "")) != want:
		_fail("End did not close the audience as %s: %s" % [want, Audiences.request(ns, _request)])


func _check_left() -> void:
	if _main._windows.is_open("audience"):
		_fail("Leave left the audience open")
	if _main._clock.paused and not _main._decision_holds_clock():
		_fail("leaving the audience did not let the clock go")
	if _promised_due > 0 and _won_promise and not _diary_has(_main._loader.person_name(_person), Words.when(_promised_due)):
		_fail("a promise binds whatever the outcome, and the Diary dropped it")


## A second person promised something due next month (staged through the sim's
## own writer), then that month run the way the clock runs one.
func _run_a_month_with_a_promise_due() -> void:
	var state = _main._state
	var ns = state.player()
	var next: int = int(state.year) * 12 + int(state.month) + 1
	for person in _main._loader.people.get(String(ns.id), []):
		var id := String(person.id)
		if person.wants.is_empty() or id == _person or id == String(ns.head_of_state_person_id):
			continue
		if _due_person == "" and President.commit(state, ns, _main._loader, "promise", id, String(person.wants[0]["object"]), next):
			_due_person = id
		elif _due_person != "" and id != _due_person 				and President.commit(state, ns, _main._loader, "delegated", id, String(person.wants[0]["object"]), next):
			_delegated_person = id
			break
	AudienceDriver.refresh(_main)
	if _delegated_person == "" or not _diary_has(_main._loader.person_name(_delegated_person), "minister"):
		_fail("premise: no delegation staged due next month, or the Diary does not list it as a minister's")
	if _due_person == "" or not _diary_has(_main._loader.person_name(_due_person), Words.when(next)):
		_fail("premise: no promise staged due next month, or the Diary does not list it")
	var year := floori((next - 1) / 12.0)
	_main._on_month_elapsed(year, next - year * 12)


func _check_verdict() -> void:
	var name: String = _main._loader.person_name(_due_person)
	var carded := false
	for card in _main._hud.inbox._cards.values():
		var text := _text_of(card)
		carded = carded or (text.to_lower().contains("your word") and text.contains(name))  # the inbox uppercases a title
	if not carded:
		_fail("the promise judged at the month has no verdict card naming %s" % name)
	if not President.commitments_with(_main._state.player(), _due_person).is_empty():
		_fail("the judged promise is still in the register")
	# Given, it read "Your word to X, due ..."; judged, it is a verdict, dated.
	var judged_on := Words.when(int(_main._state.year) * 12 + int(_main._state.month))
	var verdict := false
	for line in _diary():
		if line.contains(name) and line.contains(", due "):
			_fail("the Diary still lists the judged promise as given: %s" % [_diary()])
		verdict = verdict or (line.contains(name) and line.begins_with(judged_on)
			and (line.contains("kept your word") or line.contains("revealed a lie")))
	if not verdict:
		_fail("the Diary does not show the promise's verdict, dated %s: %s" % [judged_on, _diary()])
	# A delegation judged is a minister's verdict, never the president's lie (QA on
	# #121: it fell into the promise's wording).
	var delegated := false
	for line in _diary():
		if line.contains(_main._loader.person_name(_delegated_person)) and line.begins_with(judged_on):
			delegated = true
			if line.contains("lie") or not line.contains("minister"):
				_fail("a judged delegation reads as the president's word: %s" % line)
	if not delegated:
		_fail("the Diary does not show the delegation's verdict: %s" % [_diary()])


func _diary() -> PackedStringArray:
	return AudienceDriver._games[_main.get_instance_id()]["promises"].lines()


func _diary_has(who: String, when: String) -> bool:
	for line in _diary():
		if line.contains(who) and line.contains(when):
			return true
	return false


func _text_of(node: Node) -> String:
	var parts := PackedStringArray()
	for c in node.find_children("*", "", true, false):
		if c is Label:
			parts.append((c as Label).text)
		elif c is RichTextLabel:
			parts.append((c as RichTextLabel).get_parsed_text())
	return " ".join(parts)


func _press(down: bool) -> void:
	var target: Button = _scene().cards.find_child("CounterButton", true, false) as Button if _scene() != null else null
	if target == null:
		_fail("no Counter button to click")
		return
	Click.half(_main.get_viewport(), target, down)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_audience_levers: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
