extends SceneTree

## Headless test: godot --headless --script res://tests/test_region_arrival.gd
## Non-zero exit on any failure.
##
## The Regions arrival (the block 0 gate's G6: "nothing points at the Regions tab"): a
## quiet card when the nation's worst region passes the data's threshold. It never holds
## the clock, so it spends none of the 4 + 6 a year (docs/design/decision-surfaces.md),
## its words are Regions.problem()'s, and its Go opens that region. It comes back only
## after the rule's months, and not while a fund already runs there.
##
## Driven through the real inbox and the real Go, a frame apart.

const Regions = preload("res://src/sim/regions.gd")
const RegionFunds = preload("res://src/sim/region_funds.gd")
const RegionFund = preload("res://src/ui/region_fund.gd")
const RegionArrival = preload("res://src/ui/region_arrival.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")
const Inbox = preload("res://src/ui/inbox.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const Strings = preload("res://src/ui/strings.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _worst := {}


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_check_rule()
			_check_under_threshold()
			_check_card_arrives()
		3:
			_check_once()
			_press_go()
		5:
			_check_go_landed()
			_check_rearm()
			_check_not_with_a_fund()
			_check_wired()
			_finish()
	return false


func _rule() -> Dictionary:
	return _main._loader.region_fund_rule["arrival"]


## The threshold is data, and France's worst region passes it at the start (measured
## 1.30; the premise every check below stands on).
func _check_rule() -> void:
	if float(_rule()["ratio"]) <= 1.0 or int(_rule()["rearm_months"]) < 1:
		_fail("rule: the arrival's rule reads %s" % [_rule()])
	_worst = RegionArrival.worst(_main._state, _main._state.player())
	if _worst.is_empty() or float(_worst["problem"]["ratio"]) < float(_rule()["ratio"]):
		_fail("premise: France's worst region is under the threshold (%s)" % [_worst])


## Under the data's threshold, nothing is said. A number in data, read by the rule.
func _check_under_threshold() -> void:
	var held := float(_rule()["ratio"])
	_rule()["ratio"] = float(_worst["problem"]["ratio"]) + 0.01
	RegionArrival.check(_main)
	if _card() != null:
		_fail("under the threshold: a card arrived")
	_rule()["ratio"] = held


func _check_card_arrives() -> void:
	var paused: bool = _main._clock.paused
	RegionArrival.check(_main)
	var card = _card()
	if card == null:
		_fail("arrival: no card for a region past the threshold")
		return
	if _main._clock.paused != paused or _main._clock.held:
		_fail("arrival: the card touched the clock (paused %s, held %s)" % [_main._clock.paused, _main._clock.held])
	var text := _text_under(card)
	var said: String = RegionFund.problem_text(_worst["problem"])
	if not text.contains(said):
		_fail("arrival: the card does not carry the sim's figure ('%s' not in '%s')" % [said, text])
	if not text.contains(String(_worst["region"].region_name).to_upper()):
		_fail("arrival: the card does not name %s ('%s')" % [_worst["region"].region_name, text])
	if _go() == null:
		_fail("arrival: the card has no Go")
	if not _lane_has(Inbox.DECISIONS, card):
		_fail("arrival: a card with a Go is not in the decisions lane")


## Once: the same month, and a month later, no second card.
func _check_once() -> void:
	RegionArrival.check(_main)
	_advance(1)
	RegionArrival.check(_main)
	if _cards() != 1:
		_fail("once: %d cards for one region" % _cards())


func _press_go() -> void:
	var go = _go()
	if go == null:
		_fail("Go: nothing to press")
		return
	(go as Button).pressed.emit()


func _check_go_landed() -> void:
	if not _main._windows.is_open("region"):
		_fail("Go: the Territory tab is not open")
	var panel = _main._windows.content("region")
	if String(panel._open_region) != String(_worst["region"].id):
		_fail("Go: the tab opened '%s', the card named %s" % [panel._open_region, _worst["region"].id])
	if _card() != null:
		_fail("Go: the card is still up")


## It comes back after the rule's months, not before.
func _check_rearm() -> void:
	_advance(int(_rule()["rearm_months"]) - 2)
	RegionArrival.check(_main)
	if _card() != null:
		_fail("rearm: back before its months were up")
	_advance(1)
	RegionArrival.check(_main)
	if _card() == null:
		_fail("rearm: not back when its months were up")
	else:
		_main._hud.inbox.dismiss(_card_id())


## A fund already answers it: no nag while one runs in that region.
func _check_not_with_a_fund() -> void:
	var state = _main._state
	var ns = state.player()
	_advance(int(_rule()["rearm_months"]))
	var lo := float(_main._loader.region_fund_rule["eur_bn"][0])
	var started: Dictionary = RegionFunds.start(state, ns, _main._loader, String(_worst["region"].id), lo, 1)
	if not bool(started.get("ok", false)):
		_fail("premise: the fund did not start (%s)" % [started])
	RegionArrival.check(_main)
	if _card() != null:
		_fail("fund: a card for a region a fund already runs in")
	RegionFunds.stop(state, ns, String(started.get("id", "")))


## The month's end reaches it, through the driver every month ends in.
func _check_wired() -> void:
	(RegionArrival._told[_main.get_instance_id()]["told"] as Dictionary).clear()
	var ns = _main._state.player()
	ns.in_government = false
	BriefingDriver.open(_main, {})
	ns.in_government = true
	if _card() == null:
		_fail("wired: the month's end does not bring the card")


# -- helpers --

func _advance(months: int) -> void:
	var state = _main._state
	var total: int = state.year * 12 + state.month - 1 + months
	state.year = floori(total / 12.0)
	state.month = total - state.year * 12 + 1


func _go():
	for b in _main._hud.inbox.find_children("*", "Button", true, false):
		if ActsOn.acts_on(b, RegionArrival.SUBJECT + String(_worst["region"].id)) and not _gone(b):
			return b
	return null


## The card holding the Go: its PanelContainer, the inbox's PLATE.
func _card():
	var go = _go()
	var up: Node = go
	while up != null and not (up is PanelContainer):
		up = up.get_parent()
	return up


func _card_id() -> String:
	return String(RegionArrival._told[_main.get_instance_id()]["card"])


func _cards() -> int:
	var n := 0
	for b in _main._hud.inbox.find_children("*", "Button", true, false):
		if ActsOn.acts_on(b, RegionArrival.SUBJECT + String(_worst["region"].id)) and not _gone(b):
			n += 1
	return n


func _lane_has(lane: String, card: Node) -> bool:
	return card.get_parent() == _main._hud.inbox._rows[lane]


func _gone(node: Node) -> bool:
	var up: Node = node
	while up != null:
		if up.is_queued_for_deletion():
			return true
		up = up.get_parent()
	return false


func _text_under(node: Node) -> String:
	var out := ""
	for label in node.find_children("*", "", true, false):
		if label is Label:
			out += (label as Label).text + " "
		elif label is RichTextLabel:
			out += (label as RichTextLabel).get_parsed_text() + " "
	return out


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_region_arrival: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
