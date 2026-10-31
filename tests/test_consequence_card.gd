extends SceneTree

## Headless test: godot --headless --script res://tests/test_consequence_card.gd
## Non-zero exit on any failure.
##
## V5.1-d1b, G10 of the play gate: "je n'ai pas bcp de retour des conséquences".
## A decision was measured at the next month's close into recent_effects, which
## only the Overview read. Now that close also puts a card in the inbox's notes:
## the decision's name and its biggest movements, the same reading the Overview
## shows, so the consequence reaches the player where the question did.

const Events = preload("res://src/sim/events.gd")
const Trends = preload("res://src/ui/trends.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false
	_check_an_answer_comes_back_as_a_card()
	_finish()
	return true


func _check_an_answer_comes_back_as_a_card() -> void:
	var ns = _main._state.player()
	var inbox = _main._hud.inbox
	var ev = null
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt) and not candidate.choices.is_empty():
			ev = candidate
			break
	if ev == null:
		_fail("no quiet event with choices to answer")
		return
	ns.event_queue.clear()
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	_main._pending_effects.clear()
	_main._events_panel._on_choose(ev, ev.choices[0])
	var label := String(_main._pending_effects[0]["label"])
	var before: Array = inbox._cards.keys()

	# Spec 3.3 (#220): on a month the briefing shows, it says the consequence and the
	# card is held back; this is the month it does not show, where the card stays.
	preload("res://src/ui/briefing_driver.gd").suppressed = true
	var clock = _main._clock
	clock.set_process(false)
	var month: int = clock.month
	while clock.month == month:
		clock.advance_one_day()

	var effect: Dictionary = _main._state.recent_effects[0]
	if String(effect["label"]) != label:
		_fail("premise: the newest recent effect is '%s', not the answer '%s'" % [effect["label"], label])
		return
	var card_text := ""
	for id in inbox._cards:
		if before.has(id) or inbox.lane_of(id) != inbox.NOTES:
			continue
		var text := _text_of(inbox._cards[id])
		if text.to_lower().contains(label.to_lower()):  # card titles are drawn in capitals
			card_text = text
	if card_text.is_empty():
		_fail("the month that measured '%s' put no card naming it in the notes" % label)
		return
	# Its biggest movement, as the Overview words it.
	var biggest := {}
	for m in effect["movements"]:
		if not is_nan(float(m["severity"])) and (biggest.is_empty() or absf(float(m["severity"])) > absf(float(biggest["severity"]))):
			biggest = m
	if biggest.is_empty():
		if not card_text.contains("nothing moved"):
			_fail("a decision that moved nothing did not say so: %s" % card_text)
	elif not card_text.contains(String(biggest["label"])):
		_fail("the card does not name the decision's biggest movement '%s': %s" % [biggest["label"], card_text])


func _text_of(node: Node) -> String:
	var out := ""
	if node is Label:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		out += _text_of(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_consequence_card: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
