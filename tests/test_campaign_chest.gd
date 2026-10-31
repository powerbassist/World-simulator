extends SceneTree

## Headless test: godot --headless --script res://tests/test_campaign_chest.gd
## Non-zero exit on any failure.
##
## V5.2 C6's interface half (docs/design/v5.2-c6-party-campaigns.md sections 3 and 9;
## Systems' read surface on #183): the governing party pays for the campaign, so
##   - the campaign panel shows the party's chest (its money, how long it pays what
##     runs) and, on each offer, how long it pays with that effort added;
##   - a start the chest cannot pay for is a DISABLED button whose tooltip is a whole
##     sentence with the figures Campaign.execute() compares; a refused command is said
##     on a card, never a dead click;
##   - the report's `campaign_stopped` is ONE note a month in the inbox, the played
##     nation's efforts only, and never a hold;
##   - every docked panel's own Close is gone (register() hides it now, not main.gd).

const Campaign = preload("res://src/sim/campaign.gd")
const CampaignK = preload("res://src/sim/campaign_constants.gd")
const PartyMoney = preload("res://src/sim/party_money.gd")
const President = preload("res://src/sim/president.gd")
const Inbox = preload("res://src/ui/inbox.gd")
const HoldReason = preload("res://src/ui/hold_reason.gd")
const Num = preload("res://src/ui/num.gd")

var _failures: Array[String] = []
var _main
var _panel
var _ns
var _frame := 0
var _starts: Array = []


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_check_no_own_close()
			_ns = _main._state.player()
			_panel = _main._campaign_panel
			# Into the run-up without ticking a year: the vote two months out.
			var at: int = _main._state.year * 12 + (_main._state.month - 1) + 2
			_ns.next_executive_year = at / 12
			_ns.next_executive_month = at % 12 + 1
			if not Campaign.is_open(_main._state, _ns):
				_fail("the staged vote did not open the run-up")
				return _finish()
			for action in _main._loader.campaign_actions:
				if String(action.effects.get("campaign", {}).get("op", "")) == "start":
					_starts.append(action)
			_panel._site_region = String(Campaign.region_ids(_ns, _main._loader)[0])
			_set_money(-1.0)
			_main._windows.open("campaign")
			_panel.mark_dirty()
		6:
			_check_unpayable()
			_check_refusal_said()
			_set_money(1000.0)
			_run_and_stop(_starts[0])
			_panel.mark_dirty()
		9:
			_check_payable()
			_check_spent_offer()
			_check_stopped_note()
			return _finish()
	return false


## The governing party's money set to `amount` (EUR m) through the sim's own writer.
func _set_money(amount: float) -> void:
	var party := String(_ns.incumbent_party_id)
	President.adjust_party_money_eur_m(_ns, _main._loader, party, amount - PartyMoney.money_eur_m(_ns, _main._loader))


func _check_no_own_close() -> void:
	for window_id in ["budget", "tax", "politics", "society", "legislature", "diplomacy", "orgs", "calendar",
			"people", "outliner", "companies", "projects", "region", "commodities", "energy", "campaign", "events"]:
		var page = _main._windows._pages.get(window_id, null)
		var close = _find_close(page)
		if page == null:
			_fail("no window '%s'" % window_id)
		elif close != null and close.visible:
			_fail("the '%s' panel still shows its own Close" % window_id)


func _find_close(node: Node):
	if node == null:
		return null
	if "_close_button" in node and node._close_button != null:
		return node._close_button
	for child in node.get_children():
		var found = _find_close(child)
		if found != null:
			return found
	return null


func _start_buttons() -> Array:
	var names := {}
	for action in _starts:
		names[String(action.action_name)] = action
	var out := []
	for button in _panel.find_children("*", "Button", true, false):
		if names.has(button.text):
			out.append([button, names[button.text]])
	return out


func _check_unpayable() -> void:
	var text := _texts(_panel)
	if not text.to_lower().contains("the party's chest") or not text.contains("Party money"):
		_fail("the campaign panel does not show the party's chest: '%s'" % text)
	# The purse's two halves and the net, the net named by its direction in words.
	var purse := PartyMoney.purse(_ns, _main._loader, String(_ns.incumbent_party_id))
	var net := float(purse["net"])
	var net_label := "The party breaks even" if absf(net) < 0.005 else ("The party loses a year" if net < 0.0 else "The party gains a year")
	for label in ["Public funding a year", "Running costs a year", net_label]:
		if not text.contains(label):
			_fail("the purse lacks '%s': '%s'" % [label, text])
	if not text.contains("€%s m" % Num.f(absf(float(purse["net"])), 2)):
		_fail("the purse's net is not printed as money")
	var buttons := _start_buttons()
	if buttons.is_empty():
		_fail("no start button on the campaign panel inside the run-up")
	for pair in buttons:
		var button: Button = pair[0]
		var price := Campaign.price_eur_m(_ns, _main._loader, String(pair[1].effects["campaign"]["effort_id"]))
		if not button.disabled:
			_fail("'%s' is enabled with an empty chest" % button.text)
		if not button.tooltip_text.begins_with("The party cannot pay for it: it costs €%s m a month, and the party has −€" % Num.f(price, 2)):
			_fail("'%s' does not say why, with its price: '%s'" % [button.text, button.tooltip_text])


func _check_refusal_said() -> void:
	# The button is disabled, so the command is driven straight: a refusal that gets
	# through anyway is said on a card, never swallowed.
	_panel._on_act(_ns, _starts[0])
	var said := false
	for card in _main.find_children("ConfirmCard", "", true, false):
		if card.visible and _texts(card).contains("The party cannot pay for it"):
			said = true
			card.hide()
	if not said:
		_fail("a refused start was a dead click: no card said why")
	# A second refusal reuses the card rather than stacking another.
	_panel._on_act(_ns, _starts[0])
	var cards := 0
	for card in _main.find_children("ConfirmCard", "", true, false):
		if _texts(card).contains("The party cannot pay for it"):
			cards += 1
			card.hide()
	if cards != 1:
		_fail("two refusals left %d refusal cards, not one" % cards)
	if Campaign.running_count(_ns) != 0:
		_fail("a start the party cannot pay for began anyway")


func _check_payable() -> void:
	for pair in _start_buttons():
		if pair[0].disabled:
			_fail("'%s' is still disabled with a full chest: '%s'" % [pair[0].text, pair[0].tooltip_text])
	if not _texts(_panel).contains("With this added, the chest lasts"):
		_fail("an offer does not say how long the chest pays with it added")


## One effort put in the field through the sim, then stopped the way a money stop
## stops it (Campaign.tick_month(): out of campaign_running, still in campaign_started).
func _run_and_stop(action) -> void:
	var result: Dictionary = Campaign.execute(_main._state, _ns, _main._loader, action, _panel._site_region)
	if not result.get("applied", false):
		_fail("could not start an effort with a full chest: %s" % result)
		return
	var eid := String(action.effects["campaign"]["effort_id"])
	_ns.campaign_running.erase(eid)
	_ns.campaign_sites.erase(eid)


## QA's TAKE on #184: an effort that ran this run-up and stopped can never start again
## before the vote, so its offer has no months forecast and says it is spent.
func _check_spent_offer() -> void:
	var text := _texts(_panel)
	if text.count("Already used: one run per run-up.") != 1:
		_fail("the stopped effort does not say it is spent: '%s'" % text)
	var forecasts := text.count("With this added, the chest lasts")
	if forecasts != _starts.size() - 1:
		_fail("%d offers carry a months forecast; the spent one must not (%d starts)" % [forecasts, _starts.size()])


func _check_stopped_note() -> void:
	var inbox = _main._hud.inbox
	inbox.clear()
	var clock = _main._clock
	var paused: bool = clock.paused
	var reason := HoldReason.show(_main)
	var own := String(_main._state.player_nation_id)
	var e1 := String(_starts[0].effects["campaign"]["effort_id"])
	var e2 := String(_starts[1].effects["campaign"]["effort_id"])
	var stopped := [{"nation_id": own, "effort_id": e1}, {"nation_id": own, "effort_id": e2},
		{"nation_id": "ZZZ", "effort_id": e1}]
	_main._on_month_step("Campaign", true, {"campaign_stopped": stopped}, _main._state.year, _main._state.month)
	if inbox.lane_count(Inbox.NOTES) != 1:
		_fail("two efforts stopped in one month made %d notes, not one" % inbox.lane_count(Inbox.NOTES))
	var text := _texts(inbox)
	for eid in [e1, e2]:
		var name := Campaign.name_of(_main._loader, eid)
		if not text.contains(name):
			_fail("the stop note does not name '%s': '%s'" % [name, text])
	if clock.paused != paused or HoldReason.show(_main) != reason:
		_fail("a campaign stopped for money held the clock")
	inbox.clear()
	_main._on_month_step("Campaign", true, {"campaign_stopped": [{"nation_id": "ZZZ", "effort_id": e1}]}, _main._state.year, _main._state.month)
	_main._on_month_step("Campaign", true, {"campaign_stopped": []}, _main._state.year, _main._state.month)
	if inbox.lane_count(Inbox.NOTES) != 0:
		_fail("another nation's stop, or none, left a note")


func _texts(node: Node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	elif node is RichTextLabel:
		out += node.get_parsed_text() + "\n"
	for child in node.get_children():
		out += _texts(child)
	return out


func _fail(message: String) -> void:
	_failures.append(message)
	push_error("FAIL: " + message)


func _finish() -> bool:
	if _failures.is_empty():
		print("PASS tests/test_campaign_chest.gd")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: " + f)
		quit(1)
	return true
