extends SceneTree

## Headless test: godot --headless --script res://tests/test_request_lane.gd
## Non-zero exit on any failure.
##
## V5.2b, the request side of an audience, on rows in the sim's shapes
## (.superpowers/sdd/v5.2b-plan.md "THE COMMAND SURFACE"):
##   - each pending request is one card in the inbox's REQUESTS lane, and an
##     answered or lapsed one is taken down when the rows say so;
##   - a card never holds the clock, and the title bar says how many wait;
##   - Book refused (no offered day free) stays on the card disabled with its
##     reason, Delegate and Decline live (B2); the price of saying no is in words;
##   - a real click on an answer (press and release frames apart) emits that
##     answer for that request;
##   - the Diary's audience block offers the person's days, a taken one disabled
##     with the Diary's reason, and a free one books that day.

const RequestLane = preload("res://src/ui/request_lane.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _lane: RequestLane
var _asked := []
var _booked := []
var _target: Button


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _rows(both: bool) -> Array:
	var rows := [{"id": "req_1", "person": "Cécile Aumont", "ask": "She wants the pension age held.",
		"by": "MAR 2026", "price": "her grudge +0.12, her rapport -0.10",
		"book": {"ok": false, "reason": "Both days she offers are taken."},
		"delegate": {"ok": true, "reason": ""}, "decline": {"ok": true, "reason": ""}}]
	if both:
		rows.append({"id": "req_2", "person": "Daniel Moucron", "ask": "He wants a portfolio.",
			"by": "APR 2026", "price": "his grudge +0.12",
			"book": {"ok": true, "reason": ""}, "delegate": {"ok": true, "reason": ""}, "decline": {"ok": true, "reason": ""}})
	return rows


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._clock.paused = false
			_lane = RequestLane.new()
			_lane.attach(_main._hud.inbox)
			for sig in ["book_requested", "delegate_requested", "decline_requested"]:
				_lane.connect(sig, func(id: String) -> void: _asked.append([sig, id]))
			_lane.show_requests(_rows(true))
			_main._hud.title_bar.set_requests(2)
		5:
			_check_cards()
			_target = _answer_button("req_2", 1)
			_press(true)
		9:
			_press(false)
		11:
			if _asked != [["delegate_requested", "req_2"]]:
				_fail("a held click on Delegate emitted %s, not delegate for req_2" % [_asked])
			_lane.show_requests(_rows(false))
		13:
			if _lane.card_of("req_2") != "" or _main._hud.inbox._cards.size() == 0:
				_fail("a request gone from the rows kept its card, or the lane lost the other")
			_check_booking()
			_finish()
			return true
	return false


func _check_cards() -> void:
	var inbox = _main._hud.inbox
	for id in ["req_1", "req_2"]:
		var card_id := _lane.card_of(id)
		if card_id == "" or inbox.lane_of(card_id) != inbox.REQUESTS:
			_fail("request %s has no card in the REQUESTS lane" % id)
	if _main._clock.paused:
		_fail("a request card held the clock")
	if not String(_main._hud.title_bar.requests_text()).contains("2 requests waiting"):
		_fail("the title bar does not say two requests wait: '%s'" % _main._hud.title_bar.requests_text())
	var book := _answer_button("req_1", 0)
	if book == null or not book.disabled or not book.tooltip_text.contains("taken"):
		_fail("a refused Book is not disabled with its reason")
	for i in [1, 2]:
		var other := _answer_button("req_1", i)
		if other == null or other.disabled:
			_fail("Delegate or Decline went out with Book (B2)")
	var text := _text(inbox._cards[_lane.card_of("req_1")])
	if not text.contains("grudge +0.12") or not text.contains("MAR 2026"):
		_fail("the card does not say the price or the deadline: %s" % text)


func _check_booking() -> void:
	# A booking block of its own: the game's is wired to the sim (audience_driver).
	var booking = preload("res://src/ui/audience_booking.gd").new()
	_main.add_child(booking)
	booking.booked.connect(func(id: String, date: Dictionary) -> void: _booked.append([id, date]))
	booking.open_for({"id": "req_2", "person": "Daniel Moucron", "ask": "He wants a portfolio."}, [
		{"year": 2026, "month": 2, "day": 3, "free": false, "reason": "This day is taken."},
		{"year": 2026, "month": 2, "day": 10, "free": true, "reason": ""}])
	var days: Array = booking.find_children("*", "Button", true, false)
	if days.size() != 2 or not days[0].disabled or days[0].tooltip_text != "This day is taken." or days[1].disabled:
		_fail("the Diary's audience days are not one taken (with its reason) and one free")
		return
	days[1].pressed.emit()
	if _booked != [["req_2", {"year": 2026, "month": 2, "day": 10}]]:
		_fail("booking the free day emitted %s" % [_booked])


func _answer_button(request_id: String, index: int) -> Button:
	var card = _main._hud.inbox._cards.get(_lane.card_of(request_id))
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
		print("test_request_lane: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
