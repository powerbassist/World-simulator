extends SceneTree

## Headless test: godot --headless --script res://tests/test_poll_card.gd
## Non-zero exit on any failure.
##
## V5.3 b, step 5 (docs/design/v5.3-ab.md 4.2): the poll on a bill, through the running game.
## The strip sells a tier's price, margin and wait; the press charges the debt that price and
## nothing else; THE DAY'S DRIVER IS QA'S MERGE GATE: on the real clock a two-week poll arrives
## in two weeks, also across a month's close, where the close alone would print it six weeks
## on. The card says the read, and opens the bill while the bill is open. The read stands on
## the briefing and on the address's strip, dated.

const MeasurePolls = preload("res://src/sim/measure_polls.gd")
const K = preload("res://src/sim/poll_constants.gd")
const PollStrip = preload("res://src/ui/poll_strip.gd")
const PollCard = preload("res://src/ui/poll_card.gd")
const LawAddress = preload("res://src/ui/law_address.gd")
const EffectsStrip = preload("res://src/ui/effects_strip.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const Calendar = preload("res://src/sim/calendar.gd")
const Trends = preload("res://src/ui/trends.gd")
const Num = preload("res://src/ui/num.gd")
const Strings = preload("res://src/ui/strings.gd")
const Click = preload("res://tests/click.gd")

var _failures: Array[String] = []
var _main
var _step := 0
var _wait := 0
var _law
var _click: Control
var _click_phase := 0
var _debt := 0.0
var _bought_on := 0
var _printed_on := -1
var _second_bought_on := 0
var _second_key := ""
var _second_printed_on := -1
var _third_key := ""
var _pre_press := {}
var _baseline := {}


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	if _wait > 0:
		_wait -= 1
		return false
	if _click != null:
		Click.half(root, _click, _click_phase == 0)
		_click_phase += 1
		_wait = 2
		if _click_phase == 2:
			_click = null
			_click_phase = 0
		return false
	_step += 1
	match _step:
		1:
			preload("res://src/ui/briefing_driver.gd").suppressed = true
			_main._clock.set_process(false)
			_wait = 3
		2:
			_main._windows.open("legislature")
			_wait = 3
		3:
			_law = _main._law_panel._laws._shown[0]
			_main._law_panel.brief_requested.emit(_law)
			_wait = 3
		4:
			_check_nothing_is_bought_yet()
			_press(_chip("standard"))
		5:
			_check_the_strip_reads_the_tier("standard")
			_press(_chip("quick"))
		6:
			_check_the_strip_reads_the_tier("quick")
			_debt = float(_ns().debt_eur_bn)
			_bought_on = _today()
			_pre_press = Trends.snapshot_now(_main._state)
			_main._briefing.polled.connect(func(before: Dictionary, _label: String) -> void: _baseline = before)
			_press(_go())
		7:
			_check_the_press_charged_the_price()
			_second_key = _main._law_panel._laws._shown[1].id
			_third_key = _main._law_panel._laws._shown[2].id
			_main._briefing.hide()
			_wait = 2
		8:
			return _run_the_clock_to_the_poll()
		9:
			_check_the_poll_arrived_on_its_day()
			_check_the_card()
			_check_the_read_stands_on_the_briefing()
		10:
			_check_the_address_reads_the_poll()
			_check_the_narrowest_read_is_the_one_shown()
			_main._briefing.hide()
			_main._law_panel._laws.select(_second_key)
			_press(_open_button())
		11:
			_check_open_lands_on_the_bill()
			_check_a_closed_measure_has_no_open()
			# Late in the month, so its two weeks cross the close.
			_buy_late_in_the_month()
		12:
			return _run_the_clock_to_the_second_poll()
		13:
			_check_the_poll_across_a_close()
			_check_the_close_road_has_a_card()
			_check_a_composed_bill_can_be_polled()
			_check_a_detached_briefing_charges_nothing()
			_finish()
			return true
	return false


func _ns():
	return _main._state.player()


func _today() -> int:
	return Calendar.day_number(int(_main._state.year), int(_main._state.month), int(_main._state.day))


func _press(target: Control) -> void:
	_click = target
	_click_phase = 0


func _all_in(node: Node, test: Callable) -> Array:
	var out := []
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if test.call(n):
			out.append(n)
		stack.append_array(n.get_children())
	return out


func _text_in(node: Node) -> String:
	var bits := PackedStringArray()
	for n in _all_in(node, func(x: Node) -> bool: return x is Label or x is RichTextLabel or x is Button):
		bits.append(String(n.text))
	return " | ".join(bits)


func _chip(tier: String) -> Button:
	for chip in _all_in(_main._briefing, func(n: Node) -> bool: return n is Button and n.has_meta(PollStrip.CHIP_META)):
		if String(chip.get_meta(PollStrip.CHIP_META)) == tier:
			return chip
	_fail("no chip for %s" % tier)
	return Button.new()


func _go() -> Button:
	var found := _all_in(_main._briefing, func(n: Node) -> bool: return n is Button and n.has_meta(PollStrip.GO_META))
	if found.is_empty():
		_fail("no Commission in the briefing")
		return Button.new()
	return found[0]


func _strip() -> EffectsStrip:
	var found := _all_in(_main._briefing, func(n: Node) -> bool: return n is EffectsStrip and n.has_meta(PollStrip.STRIP_META))
	return found[0] if not found.is_empty() else null


func _check_nothing_is_bought_yet() -> void:
	if not _main._briefing.visible:
		_fail("Propose did not open the briefing")
	var text := _text_in(_main._briefing)
	if "No poll on this yet." not in text:
		_fail("a bill with no poll does not say so: %s" % text)
	for gone in ["assembly poll", "popular poll"]:
		if gone in text:
			_fail("V4.2's %s is still sold beside the tiers" % gone)
	if _strip() == null:
		_fail("no strip before the press")
	if _all_in(_main._briefing, func(n: Node) -> bool: return n is Button and n.has_meta(PollStrip.CHIP_META)).size() != K.TIERS.size():
		_fail("a chip per tier")


func _check_the_strip_reads_the_tier(tier: String) -> void:
	var strip := _strip()
	var terms: Dictionary = K.TIERS[tier]
	if strip.money_label.text != EffectsStrip.sum_text(-float(terms["cost_eur_bn"])):
		_fail("%s: the strip's price reads %s" % [tier, strip.money_label.text])
	if str(int(terms["weeks"])) not in strip._when.text:
		_fail("%s: the strip's wait reads '%s'" % [tier, strip._when.text])
	if Num.f(float(terms["margin"]), 1) not in strip._who.text:
		_fail("%s: the strip's margin reads '%s'" % [tier, strip._who.text])
	if strip.money_bn >= 0.0:
		_fail("%s: the price does not read as a cost" % tier)
	if not _chip(tier).button_pressed:
		_fail("%s: the picked chip is not pressed" % tier)


func _check_the_press_charged_the_price() -> void:
	var cost := float(K.TIERS["quick"]["cost_eur_bn"])
	if absf(float(_ns().debt_eur_bn) - _debt - cost) > 1e-9:
		_fail("the press moved the debt by %f, the strip said %f" % [float(_ns().debt_eur_bn) - _debt, cost])
	if not MeasurePolls.bought(_ns(), String(_law.id)).has("quick"):
		_fail("the press bought nothing")
	if not _go().disabled:
		_fail("a tier bought is offered again: never a reroll")
	var text := _text_in(_main._briefing)
	if "No poll on this yet." in text:
		_fail("a poll bought and out, and the page says there is none")
	if _baseline != _pre_press:
		_fail("the effect's baseline was not taken before the purchase")
	var row: Dictionary = MeasurePolls.bought(_ns(), String(_law.id))["quick"]
	if "arrives %s" % PollStrip.arrived_text(row) not in text:
		_fail("the briefing does not say when it arrives: %s" % text)
	_chip("standard").pressed.emit()
	if _go().disabled:
		_fail("a tier not bought is down")


## One day a frame, on the game's own clock, the month running as it runs.
func _run_the_clock_to_the_poll() -> bool:
	_step = 7
	var clock = _main._clock
	if clock.held:
		return false
	if not MeasurePolls.result(_ns(), String(_law.id), "quick").is_empty():
		_printed_on = _today()
		_step = 8
		_wait = 2
		return false
	if _today() - _bought_on > 70:
		_fail("the clock ran 70 days and the poll never printed")
		_finish()
		return true
	clock.advance_one_day()
	return false


func _check_the_poll_arrived_on_its_day() -> void:
	var weeks := int(K.TIERS["quick"]["weeks"])
	if _printed_on - _bought_on != 7 * weeks:
		_fail("a %d-week poll took %d days" % [weeks, _printed_on - _bought_on])
	var ranges := MeasurePolls.result(_ns(), String(_law.id), "quick")
	var margin := float(K.TIERS["quick"]["margin"])
	for bloc in ranges:
		if float(ranges[bloc][1]) - float(ranges[bloc][0]) > 2.0 * margin + 0.21:
			_fail("%s prints wider than the margin sold: %s" % [bloc, ranges[bloc]])


func _card_title() -> String:
	return ("Poll: %s" % Strings.law_name(_law)).to_upper()


func _open_button() -> Button:
	for b in _all_in(_main._hud.inbox, func(n: Node) -> bool: return n is Button and String(n.text) == "Open"):
		if _card_holding(b):
			return b
	_fail("the card has no Open")
	return Button.new()


func _card_holding(button: Button) -> bool:
	var node: Node = button
	while node != null and node != _main._hud.inbox:
		if node is PanelContainer and _card_title() in _text_in(node):
			return true
		node = node.get_parent()
	return false


func _check_the_card() -> void:
	var text := _text_in(_main._hud.inbox)
	if _card_title() not in text:
		_fail("no card for the poll: %s" % text)
	var line := PollStrip.support_line(MeasurePolls.result(_ns(), String(_law.id), "quick"))
	if line not in text:
		_fail("the card does not carry the read: %s" % line)


func _check_the_read_stands_on_the_briefing() -> void:
	_main._law_panel.brief_requested.emit(_law)
	var text := _text_in(_main._briefing)
	var ranges := MeasurePolls.result(_ns(), String(_law.id), "quick")
	for bloc in ranges:
		if PollStrip.range_text(ranges[bloc]) not in text:
			_fail("the briefing lacks %s's range: %s" % [bloc, text])
			break
	if "As of %s" % PollStrip.arrived_text(MeasurePolls.bought(_ns(), String(_law.id))["quick"]) not in text:
		_fail("the read is not dated: a range stops bracketing once the country moves")


func _check_the_address_reads_the_poll() -> void:
	_main._law_panel._laws.address_open = String(_law.id)
	_main._law_panel._laws.select(String(_law.id))
	var line := PollStrip.support_line(MeasurePolls.result(_ns(), String(_law.id), "quick"))
	if line not in _text_in(_main._law_panel._laws._detail):
		_fail("the address's strip does not read the poll")
	_main._law_panel._laws.address_open = ""


func _check_open_lands_on_the_bill() -> void:
	_wait = 2
	if _main._law_panel._laws.selected_id() != String(_law.id):
		_fail("Open landed on %s" % _main._law_panel._laws.selected_id())
	if _card_title() in _text_in(_main._hud.inbox):
		_fail("Open left its card in the inbox")


## A poll that arrives on a bill no longer open is a note, with nothing to open.
func _check_a_closed_measure_has_no_open() -> void:
	var before: int = _main._hud.inbox.card_count()
	PollCard.arrived(_main, {"key": "no_such_bill", "tier": "quick", "ranges": {"workers": [40.0, 52.0]}})
	if _main._hud.inbox.card_count() != before + 1:
		_fail("a closed measure's poll has no card")
	for b in _all_in(_main._hud.inbox, func(n: Node) -> bool: return n is Button and String(n.text) == "Open"):
		var node: Node = b
		while node != null and node != _main._hud.inbox:
			if node is PanelContainer and "NO_SUCH_BILL" in _text_in(node):
				_fail("a closed measure's card offers Open")
			node = node.get_parent()


## QA's read of the code: bought on the 19th, due on the 2nd, the close alone prints it on the
## 1st of the month after, 41 days on. A second poll, due on the 1st itself, is the close's own
## to print, and its card comes by report["polls"].
func _buy_late_in_the_month() -> void:
	var clock = _main._clock
	var last: int = Calendar.days_in_month(int(clock.year), int(clock.month))
	while clock.day < last - 13:
		clock.advance_one_day()
	if not bool(MeasurePolls.commission(_main._state, _main._loader, _third_key, "quick")["ok"]):
		_fail("the poll due on the 1st was refused")
	clock.advance_one_day()
	_second_bought_on = _today()
	if not bool(MeasurePolls.commission(_main._state, _main._loader, _second_key, "quick")["ok"]):
		_fail("the second poll was refused")


func _run_the_clock_to_the_second_poll() -> bool:
	_step = 11
	var clock = _main._clock
	if clock.held:
		return false
	if not MeasurePolls.result(_ns(), _second_key, "quick").is_empty():
		_second_printed_on = _today()
		_step = 12
		_wait = 2
		return false
	if _today() - _second_bought_on > 70:
		_fail("the second poll never printed")
		_finish()
		return true
	clock.advance_one_day()
	return false


func _check_the_poll_across_a_close() -> void:
	var taken := _second_printed_on - _second_bought_on
	if taken != 14:
		_fail("bought on the 19th, a two-week poll took %d days" % taken)


func _check_the_close_road_has_a_card() -> void:
	if MeasurePolls.result(_ns(), _third_key, "quick").is_empty():
		_fail("the poll due on the 1st never printed")
	var title := ("Poll: %s" % Strings.law_name(_main._law_panel._find_law(_third_key))).to_upper()
	if title not in _text_in(_main._hud.inbox):
		_fail("the poll the close printed has no card: %s" % title)


## A finished draft is on the order paper under the id it carried, and V4.2 could poll it.
func _check_a_composed_bill_can_be_polled() -> void:
	var position := {"economic": 0.2, "social": 0.0}
	_ns().custom_laws["draft_7"] = {"position": position}
	if MeasurePolls.position_of(_ns(), _main._loader, "draft_7") != position:
		_fail("a composed bill has no position for a poll to read")
	_ns().custom_laws.erase("draft_7")


func _check_a_detached_briefing_charges_nothing() -> void:
	var ns = _ns()
	var debt := float(ns.debt_eur_bn)
	_main._briefing.detach()
	_main._briefing._on_poll("deep")
	if float(ns.debt_eur_bn) != debt:
		_fail("a stale press after detach charged the dead run")


## Two polls printed: the table is the narrower's, whichever was bought first.
func _check_the_narrowest_read_is_the_one_shown() -> void:
	var polls: Dictionary = _ns().measure_opinion["polls"]
	polls["stub"] = {"quick": {"ranges": {"workers": [40.0, 52.0]}, "due_day": 0}, "deep": {"ranges": {"workers": [45.0, 48.0]}, "due_day": 0}}
	if String(PollStrip.narrowest(_ns(), "stub")["tier"]) != "deep":
		_fail("the table reads the %s poll" % PollStrip.narrowest(_ns(), "stub")["tier"])
	polls.erase("stub")


func _fail(message: String) -> void:
	_failures.append(message)
	push_error(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_poll_card: OK")
	else:
		print("test_poll_card: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
