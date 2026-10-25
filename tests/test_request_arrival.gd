extends SceneTree

## Headless test: godot --headless --script res://tests/test_request_arrival.gd
## Non-zero exit on any failure.
##
## V5.2 pre-gate B (QA's TAKE 1 and the author's "Ralentir à l'arrivée",
## 2026-10-24), through the real game:
##   - a request card's "Answer by" names the LAST month an answer is taken: the
##     sim lapses a pending request AS its deadline month begins
##     (Audiences._overdue), so the card names the month before it;
##   - a month that brings a request drops the clock to speed 1 -- not a stop (a
##     request never holds the clock) -- and a month that only lapses one does not;
##   - the "requests waiting" mark is a button: a real click (press and release
##     frames apart) brings the inbox back over a tab and raises the OLDEST
##     request's card to the top of its lane.

const Audiences = preload("res://src/sim/audiences.gd")
const AudienceDriver = preload("res://src/ui/audience_driver.gd")
const Words = preload("res://src/ui/lever_words.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _oldest := ""
var _newest := ""
var _arrived: Array = []
var _target: Control


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_stage_three_requests()
			AudienceDriver.refresh(_main)
		4:
			_check_answer_by()
			_check_slows_on_arrival()
			_check_lapse_alone_keeps_speed()
			# A tab open and the inbox put away: the mark is the way back.
			_main._windows.open("budget")
		5:
			_main._hud.inbox.slide_out()
			_target = _main._hud.title_bar._requests
		6:
			if _main._hud.inbox.visible:
				_fail("premise: the inbox is still up over the tab")
			_press(true)
		9:
			_press(false)
		11:
			_check_oldest_raised()
			_finish()
			return true
	return false


## Three asks in the register's order newest, OLDEST, newest: the oldest is
## neither the register's first row nor the lane's top card (each push goes on
## top), so only a pick by arrival month raises the right one.
func _stage_three_requests() -> void:
	var ns = _main._state.player()
	var now: int = int(_main._state.year) * 12 + int(_main._state.month)
	var months := [now, now - 1, now]
	var asked := 0
	for person in _main._loader.people.get(String(ns.id), []):
		if person.wants.is_empty() or asked >= 3 or String(person.id) == String(ns.head_of_state_person_id):
			continue
		Audiences._arrive(ns, person, person.wants[0], months[asked], _arrived)
		asked += 1
	if _arrived.size() < 3:
		_fail("premise: could not stage three requests (%d)" % _arrived.size())
		return
	_oldest = String(_arrived[1]["id"])
	_newest = String(_arrived[2]["id"])


func _check_answer_by() -> void:
	var ns = _main._state.player()
	var raw: Dictionary = {}
	for row in ns.audience_requests:
		if String(row["id"]) == _oldest:
			raw = row
	if raw.is_empty():
		_fail("premise: the staged request is not in the register")
		return
	var deadline := int(raw["deadline_month"])
	# The rule the card must agree with: still answerable in the month before the
	# deadline, lapsed as the deadline month begins.
	if Audiences._overdue(raw, deadline - 1) or not Audiences._overdue(raw, deadline):
		_fail("premise: the sim no longer lapses a request as its deadline month begins")
	var last := Words.when(deadline - 1)
	var row := AudienceDriver.row_of(_main, Audiences.request(ns, _oldest))
	if String(row["by"]) != last:
		_fail("the card says 'Answer by %s'; the last month it is taken is %s" % [row["by"], last])
	var card = _main._hud.inbox._cards.get(AudienceDriver.lane_of(_main).card_of(_oldest))
	if card == null or not _text(card).contains("Answer by %s" % last):
		_fail("the card's body does not name %s as the last month" % last)


## The step hook the month runs (WorldMonth's "Audiences" step, after), with the
## sim's own arrival rows in the sim's report shape.
func _check_slows_on_arrival() -> void:
	_main._clock.paused = false
	_main._clock.set_speed(3)
	_main._on_month_step("Audiences", true, {"audience_requests": {"arrived": _arrived, "lapsed": []}}, int(_main._state.year), int(_main._state.month))
	if _main._clock.speed != 1:
		_fail("a month that brought a request left the clock at speed %d" % _main._clock.speed)
	if _main._clock.paused:
		_fail("a request's arrival stopped the clock: it slows, it never holds")
	if not _main._hud.clock_cluster._speed_buttons[1].button_pressed:
		_fail("the clock's speed buttons do not show the drop to speed 1")


func _check_lapse_alone_keeps_speed() -> void:
	_main._clock.set_speed(3)
	_main._on_month_step("Audiences", true, {"audience_requests": {"arrived": [], "lapsed": [_arrived[0]]}}, int(_main._state.year), int(_main._state.month))
	if _main._clock.speed != 3:
		_fail("a month with a lapse and no arrival slowed the clock to %d" % _main._clock.speed)


func _check_oldest_raised() -> void:
	var inbox = _main._hud.inbox
	if not inbox.visible:
		_fail("a click on the requests mark did not bring the inbox back")
	var top: Control = inbox._rows[inbox.REQUESTS].get_child(0)
	var want = inbox._cards.get(AudienceDriver.lane_of(_main).card_of(_oldest))
	if want == null or top != want:
		_fail("the click did not raise the oldest request's card to the top of its lane")


func _press(down: bool) -> void:
	if _target == null or not _target.is_visible_in_tree():
		_fail("the requests mark is not on screen to click")
		return
	Click.half(_main.get_viewport(), _target, down)


func _text(node: Node) -> String:
	var out := ""
	if node is RichTextLabel:
		out += (node as RichTextLabel).get_parsed_text() + "\n"
	elif node is Label:
		out += (node as Label).text + "\n"
	for child in node.get_children():
		out += _text(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_request_arrival: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
