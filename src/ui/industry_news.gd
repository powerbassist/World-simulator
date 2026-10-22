extends RefCounted

## The autonomy machine's two player-facing events -- a foreign takeover bid and
## a failing firm -- as cards, kept in step with the register month by month.
##
## Out of main.gd at V5.1c (the reflection's D2: main.gd was the shell, the card
## writer, the pause and half the game's wiring). Moved whole: the wording, the
## memories and the order of pushes are the ones main.gd had. Holds no game
## state of its own beyond what it has already announced; `setup()` hands it the
## live state (again on a load) and the card column it pushes to.

const Industry = preload("res://src/sim/industry.gd")
const Num = preload("res://src/ui/num.gd")
const DataLoader = preload("res://src/core/data_loader.gd")

var _state
var _loader: DataLoader
var _stack


func setup(state, loader, stack) -> void:
	_state = state
	_loader = loader
	_stack = stack


## V4.7b: the autonomy machine's two player-facing events, as cards. The
## announced-state memory is main-side (UI): the sim stays free of the card
## stack, and a dismissed card is remembered as announced -- DISMISSAL NEVER
## ANSWERS, the bid and the window lapse on their own clocks; the card only
## has to stop repeating.
var _announced_bids := {}
var _announced_failures := {}
var _industry_card_firms := {}   # card id -> company_id; the route opens the
# companies window whole -- no focus-by-firm yet (the open deferral above) --
# so the value is carried for the day that lands, not read today.
var _bid_cards := {}             # company_id -> its LIVE bid card, taken away when the bid resolves
var _failure_cards := {}         # company_id -> its LIVE failure card, same contract

func announce() -> void:
	var ns = _state.player()
	if ns == null:
		return
	var bid: Dictionary = Industry.pending_bid(_state, ns, _loader)
	# The memory clears PER FIRM, when that firm's own bid ends -- the
	# failure branch's design below, and the pass-6 fleet's find that the
	# bid branch was still the all-clear its own comment forswore: with two
	# bids pending, answering A kept A's entry (pending_bid only shows the
	# FIRST bid), and a re-bid on A announced nothing.
	var live_bid_ids := {}
	for company_id in ns.companies.keys():
		if String(ns.companies[company_id].get("bid_bidder", "")) != "":
			live_bid_ids[company_id] = true
	for announced_id in _announced_bids.keys():
		if not live_bid_ids.has(announced_id):
			_announced_bids.erase(announced_id)
	# A resolved card is TAKEN AWAY -- PR 43's B4 contract, which these two
	# cards dishonoured until the pass-8 fleet caught it: after block, allow
	# or lapse the column still asserted an offer that no longer existed.
	for firm_id in _bid_cards.keys():
		if not live_bid_ids.has(firm_id):
			_stack.dismiss(String(_bid_cards[firm_id]))
			_bid_cards.erase(firm_id)
	if bid.is_empty():
		_announced_bids.clear()
	else:
		var bid_firm := String(bid["company_id"])
		if not _announced_bids.has(bid_firm):
			_announced_bids[bid_firm] = true
			var card_id: String = _stack.push(
				tr("Foreign takeover bid"),
				tr("%s has offered %s bn for %s. The offer lapses in %d months.") % [
					_loader.nation_name(String(bid["bidder_nation"])), Num.f(float(bid["price_eur_bn"]), 1),
					_loader.firm_name(ns.id, bid_firm), int(bid["months_left"])])
			_bid_cards[bid_firm] = card_id
			_industry_card_firms[card_id] = bid_firm
	# The window counts down on EVERY live card, read from the register --
	# not only pending_bid's first (the pass-9 fleet's find: with two bids
	# pending, the second firm's card froze at its announce-time months and
	# could lapse on stale text). The body ages IN PLACE -- the set_body
	# law, because dismiss-then-push moves the card to the bottom and the
	# position IS the card's age. A player-dismissed id is a clean no-op:
	# DISMISSAL NEVER ANSWERS, and never resurrects.
	for firm_id in _bid_cards.keys():
		if not live_bid_ids.has(firm_id):
			continue
		var entry: Dictionary = ns.companies[firm_id]
		var parts: PackedStringArray = String(entry.get("bid_bidder", "")).split("|")
		_stack.set_body(String(_bid_cards[firm_id]),
			tr("%s has offered %s bn for %s. The offer lapses in %d months.") % [
				_loader.nation_name(parts[0] if parts.size() > 0 else ""),
				Num.f(float(entry.get("bid_price_eur_bn", 0.0)), 1),
				_loader.firm_name(ns.id, String(firm_id)),
				int(entry.get("bid_months_left", 0))])
	var failing_now := Industry.failing(_state, ns, _loader)
	# The memory clears PER FIRM, when that firm's own window closes -- the
	# bid branch's design, not the all-clear the first draft used. Clearing
	# only when NO firm failed would keep a rescued firm's entry alive while
	# another window stood, and its RE-failure inside that window would then
	# be card-silent: the write-once class the comment above names.
	var failing_ids := {}
	for failure in failing_now:
		failing_ids[String(failure["company_id"])] = true
	for announced_id in _announced_failures.keys():
		if not failing_ids.has(announced_id):
			_announced_failures.erase(announced_id)
	for firm_id in _failure_cards.keys():
		if not failing_ids.has(firm_id):
			_stack.dismiss(String(_failure_cards[firm_id]))
			_failure_cards.erase(firm_id)
	for failure in failing_now:
		var company_id := String(failure["company_id"])
		var failure_body := tr("%s is failing. The rescue window stands for %d months; past it the collapse is committed.") % [
			_loader.firm_name(ns.id, company_id), int(failure["months_left"])]
		if _announced_failures.has(company_id):
			if _failure_cards.has(company_id):
				_stack.set_body(String(_failure_cards[company_id]), failure_body)
			continue
		_announced_failures[company_id] = true
		var card_id: String = _stack.push(tr("Firm in difficulty"), failure_body)
		_failure_cards[company_id] = card_id
		_industry_card_firms[card_id] = company_id


## A card this module pushed, by id: the route opens the Industry window for it.
func has_card(card_id: String) -> bool:
	return _industry_card_firms.has(card_id)


## The discarded game's memories, at a load (main.gd's load path says why).
func forget() -> void:
	_announced_bids.clear()
	_announced_failures.clear()
	_bid_cards.clear()
	_failure_cards.clear()
	_industry_card_firms.clear()
