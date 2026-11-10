extends SceneTree

## Headless test: godot --headless --script res://tests/test_decision_cards.gd
## Non-zero exit on any failure.
##
## V5.3 B7 (docs/design/v5.3-b7-density.md section 8, Interface's row): three decisions
## that already existed with no card pointing at them now each get a quiet card in the
## inbox's DECISIONS lane, with a Go. A backbench bill awaiting the president's stand
## (Statute.awaiting_endorsement), a treaty awaiting the player's assembly (Orgs'
## `ratifying`), and a council division the player's vote can swing (Orgs' stamp at the
## session's opening, `player_swings`; the author's call 4: a division the player cannot
## swing stays the Orgs tab's mark, no card). None holds the clock.
##
## Each Go is pressed by a real click, press and release frames apart, and must land
## where test_briefing_go.gd's rule says: its tab open, and an ENABLED, shown control
## there tagged with the card's subject (acts_on.gd). Each card is taken down once its
## decision is settled.

const Click = preload("res://tests/click.gd")
const ActsOn = preload("res://src/ui/acts_on.gd")
const Inbox = preload("res://src/ui/inbox.gd")
const Orgs = preload("res://src/sim/orgs.gd")
const CouncilK = preload("res://src/sim/council_constants.gd")
const CouncilCards = preload("res://src/ui/council_cards.gd")
const BriefingDriver = preload("res://src/ui/briefing_driver.gd")

var _failures: Array[String] = []
var _main
var _frame := 0
var _cases: Array = []
var _case: Dictionary = {}
var _step := 0
var _wait := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 3:
		return false
	if _frame == 3:
		_main._paused_for_programme = false
		_main._clock.paused = true
		_cases = [
			{"kind": "bill", "setup": _stage_bill},
			{"kind": "treaty", "setup": _stage_treaty},
			{"kind": "council", "setup": _stage_council},
		]
		_check_no_swing_no_card()
		return false
	if _wait > 0:
		_wait -= 1
		return false
	match _step:
		0:
			if _cases.is_empty():
				_check_settled_cards_go()
				_check_month_end_checks()
				_check_one_card_for_every_swing()
				_finish()
				return true
			_case = _cases.pop_front()
			_main._windows.close_all()
			_case["card"] = (_case["setup"] as Callable).call()
			_main._hud.inbox.slide_in()
			_step = 1
			_wait = 2  # the slide and the row's layout
		1:
			var go := _go(_case)
			if go == null:
				_fail("%s: the card has no Go" % _case["kind"])
				_step = 0
				return false
			Click.half(_main.get_viewport(), go, true)
			_step = 2
		2:
			Click.half(_main.get_viewport(), _go(_case), false)
			_step = 3
			_wait = 3  # the tab marked dirty rebuilds on its own _process
		3:
			_check_landed(_case)
			_step = 0
	return false


## The card's Go: the button the inbox tagged with the card's subject.
func _go(c: Dictionary) -> Button:
	var inbox = _main._hud.inbox
	var card := String(c["card"])
	if card == "" or not inbox._cards.has(card):
		return null
	return ActsOn.find(inbox._cards[card], String(c["subject"])) as Button


func _player_council():
	var ns = _main._state.player()
	for org in _main._loader.orgs:
		if org.council and ns.orgs.has(org.id):
			return org
	return null


## A private member's bill in its endorsement window, announced by the assembly's writer.
func _stage_bill() -> String:
	var ns = _main._state.player()
	var law = _main._loader.laws[0]
	ns.assembly_bills.clear()
	ns.assembly_bills["pmb_test"] = {"law_id": String(law.id), "months_left": 2, "backer_firm": "", "backer_chief": "", "endorse_bonus": 0.0}
	_main._assembly_news.forget({})
	_main._assembly_news.announce()
	_case["subject"] = "assembly|pmb_test"
	_case["tab"] = "legislature"
	return _card_for("assembly|pmb_test")


func _stage_treaty_state(org) -> void:
	var proposal = Orgs._next_proposal(_main._state, _main._loader, org.id)
	_main._state.orgs[org.id]["ratifying"] = {"proposal_id": String(proposal.id), "name": proposal.proposal_name, "sponsor": "",
		"months_left": CouncilK.RATIFY_WINDOW_MONTHS, "nations": {_main._state.player_nation_id: CouncilK.RATIFY_PENDING}}


## A treaty the council carried, waiting on the player's assembly.
func _stage_treaty() -> String:
	var org = _player_council()
	if org == null:
		_fail("treaty: premise, the player sits on no council")
		return ""
	_stage_treaty_state(org)
	CouncilCards.check(_main)
	_case["subject"] = "ratify|%s" % org.id
	_case["tab"] = "orgs"
	return _card_for(String(_case["subject"]))


func _pending(org, swings: bool) -> Dictionary:
	var proposal = Orgs._next_proposal(_main._state, _main._loader, org.id)
	return {"proposal_id": String(proposal.id), "name": proposal.proposal_name, "summary": proposal.summary, "org_id": org.id,
		"org_name": org.name, "months_left": 3, "player_vote": Orgs.VOTE_ABSTAIN, "opened_year": int(_main._state.year),
		"opened_month": int(_main._state.month), "sponsor": "", "player_swings": swings}


## A division opened this month that the player's vote swings (Orgs' stamp).
func _stage_council() -> String:
	var org = _player_council()
	if org == null:
		return ""
	_main._state.orgs[org.id]["ratifying"] = {}
	CouncilCards.check(_main)  # the treaty's card goes with its decision
	_main._state.orgs[org.id]["pending"] = _pending(org, true)
	CouncilCards.check(_main)
	_case["subject"] = "council"
	_case["tab"] = "orgs"
	return _card_for(String(_case["subject"]))


## The live card whose Go carries `subject`, or "".
func _card_for(subject: String) -> String:
	var inbox = _main._hud.inbox
	for id in inbox._cards:
		if ActsOn.find(inbox._cards[id], subject) != null:
			return String(id)
	return ""


func _check_landed(c: Dictionary) -> void:
	var kind := String(c["kind"])
	var inbox = _main._hud.inbox
	if String(c["card"]) == "":
		_fail("%s: no card arrived" % kind)
		return
	if not _main._windows.is_open(String(c["tab"])):
		_fail("%s: Go did not open the '%s' tab" % [kind, c["tab"]])
		return
	var hit := ActsOn.find(_main._windows.content(String(c["tab"])), String(c["subject"]))
	if hit == null:
		_fail("%s: Go to '%s' found no enabled control acting on '%s'" % [kind, c["tab"], c["subject"]])
	if inbox.lane_of(String(c["card"])) != "":
		_fail("%s: the card is still up after its Go" % kind)
	if _main._decision_holds_clock():
		_fail("%s: a quiet card holds the clock" % kind)


## The author's call 4: a division the player's vote cannot swing gets no card.
func _check_no_swing_no_card() -> void:
	var org = _player_council()
	if org == null:
		return
	_main._state.orgs[org.id]["pending"] = _pending(org, false)
	CouncilCards.check(_main)
	if _card_for("council") != "":
		_fail("council: a division the player cannot swing got a card")
	_main._state.orgs[org.id]["pending"] = {}
	CouncilCards.check(_main)


## A card whose decision settles without a Go goes: the bill endorsed, the treaty put
## to the assembly, the division held. And none of them is in the DECISIONS lane after.
func _check_settled_cards_go() -> void:
	var ns = _main._state.player()
	var inbox = _main._hud.inbox
	var bill := _stage_bill()
	if inbox.lane_of(bill) != Inbox.DECISIONS:
		_fail("bill: the card is not in the DECISIONS lane (%s)" % inbox.lane_of(bill))
	ns.assembly_bills["pmb_test"]["endorse_bonus"] = 0.1
	_main._assembly_news.announce()
	if inbox.lane_of(bill) != "":
		_fail("bill: the card stayed up once the stand was taken")
	ns.assembly_bills.clear()
	var org = _player_council()
	if org == null:
		return
	var treaty := _stage_treaty()
	if inbox.lane_of(treaty) != Inbox.DECISIONS:
		_fail("treaty: the card is not in the DECISIONS lane (%s)" % inbox.lane_of(treaty))
	_main._state.orgs[org.id]["ratifying"]["nations"][_main._state.player_nation_id] = CouncilK.RATIFY_DONE
	CouncilCards.check(_main)
	if inbox.lane_of(treaty) != "":
		_fail("treaty: the card stayed up once the assembly was asked")
	var council := _stage_council()
	if inbox.lane_of(council) != Inbox.DECISIONS:
		_fail("council: the card is not in the DECISIONS lane (%s)" % inbox.lane_of(council))
	_main._state.orgs[org.id]["pending"]["player_vote"] = Orgs.VOTE_FOR
	CouncilCards.check(_main)
	if inbox.lane_of(council) != "":
		_fail("council: the card stayed up once the player had voted")



## The month's end runs the check (BriefingDriver.open, beside the Regions arrival).
func _check_month_end_checks() -> void:
	var org = _player_council()
	if org == null:
		return
	CouncilCards._told.erase(_main.get_instance_id())
	for id in _main._hud.inbox._cards.keys():
		_main._hud.inbox.dismiss(String(id))
	_stage_treaty_state(org)
	BriefingDriver.finish_month(_main, {})
	if _card_for("ratify|%s" % org.id) == "":
		_fail("treaty: the month's end did not put up the card")
	BriefingDriver.close(_main)


## The parent's ruling on RF6 (2026-11-10): every division the player swings is ONE card,
## its title and Go only. It stays while any waits, goes when none does, and comes back
## only for a division not told before.
func _check_one_card_for_every_swing() -> void:
	var ns = _main._state.player()
	var orgs: Array = []
	for org in _main._loader.orgs:
		if org.council and ns.orgs.has(org.id):
			orgs.append(org)
	if orgs.size() < 2:
		_fail("council: premise, the player sits on fewer than two councils")
		return
	CouncilCards._told.erase(_main.get_instance_id())
	for id in _main._hud.inbox._cards.keys():
		_main._hud.inbox.dismiss(String(id))
	for org in orgs.slice(0, 2):
		_main._state.orgs[org.id]["ratifying"] = {}
		_main._state.orgs[org.id]["pending"] = _pending(org, true)
	CouncilCards.check(_main)
	var cards: Array = _main._hud.inbox._cards.keys().filter(func(id): return ActsOn.find(_main._hud.inbox._cards[id], "council") != null)
	if cards.size() != 1:
		_fail("council: two divisions the player swings made %d cards, not one" % cards.size())
		return
	var card := String(cards[0])
	if String(_main._hud.inbox._bodies[card].get_parsed_text()).strip_edges() != "":
		_fail("council: the gathered card carries a body: '%s'" % _main._hud.inbox._bodies[card].get_parsed_text())
	_main._state.orgs[orgs[0].id]["pending"] = {}
	CouncilCards.check(_main)
	if _main._hud.inbox.lane_of(card) == "":
		_fail("council: the card went while a division it gathers still waits")
	_main._state.orgs[orgs[1].id]["pending"] = {}
	CouncilCards.check(_main)
	if _main._hud.inbox.lane_of(card) != "":
		_fail("council: the card stayed once no division waits")

func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_decision_cards: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
