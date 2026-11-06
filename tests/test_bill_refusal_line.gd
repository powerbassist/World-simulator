extends SceneTree

## An ownership bill that passes while its firm's process cannot open (a seller or the
## buyers walked inside the 24-month hold, a process is under way, a settlement stands)
## used to pass in silence: Processes.start refused it, last_company_result kept the
## reason and nobody read it. Bills.adopt now stamps that refusal `by_law`, and
## ProposalNote says it in one line that names the firm and the reason. Driven through
## Legislature.apply_effects -- the channel every adoption path ends in -- so the test
## covers the door a division, a release and a 49.3 share. The law still passes and no
## number moves: the control at the end is the same bill on a free firm.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Companies = preload("res://src/sim/companies.gd")
const Processes = preload("res://src/sim/processes.gd")
const Negotiation = preload("res://src/sim/negotiation.gd")
const Legislature = preload("res://src/sim/legislature.gd")
const ProposalNote = preload("res://src/ui/proposal_note.gd")
const ProcessAsks = preload("res://src/sim/process_asks.gd")
const Strings = preload("res://src/ui/strings.gd")

const PLAYER := "FRA"

var _loader
var _failures: Array[String] = []


## The inbox a card is pushed to: it keeps what it was handed, nothing is drawn.
class StubInbox extends RefCounted:
	var cards: Array = []

	func push(title: String, body: String, _actions: Array = [], _art = null, _protect := false, _lane := "") -> String:
		cards.append({"title": title, "body": body})
		return "card%d" % cards.size()

	func has_tag(_id: String) -> bool:
		return true


class StubHud extends RefCounted:
	var inbox := StubInbox.new()


class StubMain extends RefCounted:
	var _state
	var _loader
	var _hud := StubHud.new()


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_test_a_walked_firm_says_who_walked("full_nationalisation", Negotiation.SELLER_WALKED)
	_test_a_walked_firm_says_who_walked("privatisation", Negotiation.BUYERS_WALKED)
	_test_a_busy_firm_says_so()
	_test_a_settled_firm_says_so()
	_test_a_free_firm_says_nothing_and_starts()
	_test_a_stale_refusal_is_not_told_again()
	_test_every_door_tells_it()
	_test_a_real_walk_out_reaches_the_line("minority_stake", "full_nationalisation", Negotiation.SELLER_WALKED)
	_test_a_real_walk_out_reaches_the_line("privatisation", "privatisation", Negotiation.BUYERS_WALKED)
	_finish()


func _new_state():
	var state = GameState.new_game(_loader, PLAYER)
	state.year = 2026
	state.month = 3
	return state


func _now(state) -> int:
	return int(state.year) * 12 + int(state.month)


func _big(ns) -> String:
	var best := ""
	var share := -1.0
	for company in Companies.majors_of(_loader, ns.id):
		var s := Companies.share_of_company(ns, company)
		if s > share:
			share = s
			best = String(company.id)
	return best


func _name(firm: String) -> String:
	return _loader.firm_name(PLAYER, firm)


## A closed row of `status` on the firm, `ago` months old, with the keys the door reads.
func _closed_row(state, firm: String, action_id: String, status: String, ago: int) -> Dictionary:
	return {"id": "%s|%s|fixture" % [action_id, firm], "action_id": action_id, "company_id": firm,
		"status": status, "stage": "done", "started": _now(state) - ago - 3, "closed": _now(state) - ago}


## Adopts the bill for `action_id` on `firm` through the effects channel; returns the
## line ProposalNote has for it and checks nothing started and no number moved.
func _adopt_refused(state, ns, firm: String, action_id: String, label: String) -> String:
	var rows: int = ns.processes.size()
	var debt: float = float(ns.debt_eur_bn)
	var blocs: Dictionary = ns.bloc_offset.duplicate()
	var share: float = Companies.state_share_of(ns, firm)
	Legislature.apply_effects(state, ns, {"company_ownership": {"company_id": firm, "action_id": action_id}}, _loader)
	if ns.processes.size() != rows:
		_fail("%s: the refused bill started a process" % label)
	if float(ns.debt_eur_bn) != debt or ns.bloc_offset != blocs or Companies.state_share_of(ns, firm) != share:
		_fail("%s: the refusal moved the debt, the blocs or the state share" % label)
	return ProposalNote.ownership_line(state, ns, _loader)


func _check_line(line: String, firm: String, reason: String, label: String) -> void:
	if line == "":
		_fail("%s: an adopted bill refused at the door said nothing" % label)
		return
	if not line.contains(_name(firm)):
		_fail("%s: the line does not name the firm '%s': %s" % [label, _name(firm), line])
	if not line.contains(reason):
		_fail("%s: the line does not say why ('%s'): %s" % [label, reason, line])


func _test_a_walked_firm_says_who_walked(action_id: String, reason: String) -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	if action_id == "privatisation":
		(ns.companies[firm] as Dictionary)["state_share"] = 1.0
	# The walk-out the bill was tabled before: the side that walked is the verb's.
	var walked_verb := "minority_stake" if action_id == "full_nationalisation" else "privatisation"
	ns.processes.append(_closed_row(state, firm, walked_verb, "walked", 2))
	var line := _adopt_refused(state, ns, firm, action_id, "WALKED " + action_id)
	_check_line(line, firm, reason, "WALKED " + action_id)


func _test_a_busy_firm_says_so() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	var stake
	for action in _loader.company_actions:
		if String(action.id) == "minority_stake":
			stake = action
	if not bool(Processes.start(state, ns, _loader, stake, firm).get("applied", false)):
		_fail("BUSY: the fixture's stake did not open")
		return
	var line := _adopt_refused(state, ns, firm, "full_nationalisation", "BUSY")
	_check_line(line, firm, Processes.BUSY, "BUSY")


## A settlement is only ever written for a break-up, which no bill opens, so the row is
## a fixture for the verb the bill carries: the door's SETTLED branch is what is under test,
## not a path a player can reach today.
func _test_a_settled_firm_says_so() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	ns.processes.append(_closed_row(state, firm, "full_nationalisation", "settled", 2))
	var line := _adopt_refused(state, ns, firm, "full_nationalisation", "SETTLED")
	_check_line(line, firm, Processes.SETTLED, "SETTLED")


func _test_a_free_firm_says_nothing_and_starts() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	Legislature.apply_effects(state, ns, {"company_ownership": {"company_id": firm, "action_id": "full_nationalisation"}}, _loader)
	if Processes.live(ns, firm).is_empty():
		_fail("control: the bill on a free firm opened no process")
	if ProposalNote.ownership_line(state, ns, _loader) != "":
		_fail("control: a bill that started its process said it had not")


## The refusal stays on the record; it is one card in its month and none after.
func _test_a_stale_refusal_is_not_told_again() -> void:
	var state = _new_state()
	var ns = state.player()
	var firm := _big(ns)
	ns.processes.append(_closed_row(state, firm, "minority_stake", "walked", 2))
	_adopt_refused(state, ns, firm, "full_nationalisation", "stale")
	var main := StubMain.new()
	main._state = state
	main._loader = _loader
	ProposalNote.card_ownership_refusal(main)
	ProposalNote.card_ownership_refusal(main)
	var cards: Array = main._hud.inbox.cards
	if cards.size() != 1 or not String(cards[0]["body"]).contains(_name(firm)):
		_fail("the refusal was not one card naming the firm: %s" % [cards])
	state.month += 1
	ProposalNote.card_ownership_refusal(main)
	if main._hud.inbox.cards.size() != 1:
		_fail("a refusal from last month was told again")


## A bill is adopted at a division, a release or a press: each hook says it, once.
func _test_every_door_tells_it() -> void:
	var doors := {
		"division": func(main) -> void: ProposalNote.card_division(main, {}),
		"release": func(main) -> void: ProposalNote.card_referendum(main, ""),
		"press": func(main) -> void: ProposalNote.push(main, "A bill", {}),
	}
	for door in doors:
		var state = _new_state()
		var ns = state.player()
		var firm := _big(ns)
		ns.processes.append(_closed_row(state, firm, "minority_stake", "walked", 2))
		_adopt_refused(state, ns, firm, "full_nationalisation", door)
		var main := StubMain.new()
		main._state = state
		main._loader = _loader
		(doors[door] as Callable).call(main)
		var told := 0
		for card in main._hud.inbox.cards:
			if String(card["title"]) == Strings.t("Law passed, nothing started"):
				told += 1
		if told != 1:
			_fail("%s: told %d times, not once" % [door, told])


## No row by hand: the verb opened at the door, its price ask countered, the seeded draw
## walking away at the end of its stage, then the bill tabled before it adopted inside the
## hold. The same bill passes the month the hold ends. A walk is a draw, so firms and start
## months are tried until one walks; none walking fails, it does not pass in silence.
func _test_a_real_walk_out_reaches_the_line(walked_verb: String, bill_verb: String, reason: String) -> void:
	var label := "real walk-out, %s" % walked_verb
	var walk := _walk_out(walked_verb)
	if walk.is_empty():
		_fail("%s: no firm walked in any month tried" % label)
		return
	var state = walk["state"]
	var ns = state.player()
	var firm := String(walk["firm"])
	var closed: Array = ProcessAsks.closed_last_month(state, ns)
	if closed.size() != 1 or String(closed[0]["outcome"]) != "walked":
		_fail("%s: the month's closed line is %s" % [label, closed])
		return
	var line := _adopt_refused(state, ns, firm, bill_verb, label)
	_check_line(line, firm, reason, label)
	# The month the hold ends, the same bill starts and nothing is said.
	var ends := int(closed[0]["hold_ends"])
	state.year = floori((ends - 1) / 12.0)
	state.month = ends - state.year * 12
	Legislature.apply_effects(state, ns, {"company_ownership": {"company_id": firm, "action_id": bill_verb}}, _loader)
	if Processes.live(ns, firm).is_empty():
		_fail("%s: the bill did not start once the hold ended" % label)
	if ProposalNote.ownership_line(state, ns, _loader) != "":
		_fail("%s: a bill that started said it had not" % label)


## {state, firm} with `verb` walked out of this month, or {}.
func _walk_out(verb: String) -> Dictionary:
	var action
	for a in _loader.company_actions:
		if String(a.id) == verb:
			action = a
	for start_month in range(1, 13):
		var majors: Array = Companies.majors_of(_loader, PLAYER)
		for company in majors:
			var state = _new_state()
			state.month = start_month
			var ns = state.player()
			var firm := String(company.id)
			if verb == "privatisation":
				(ns.companies[firm] as Dictionary)["state_share"] = 1.0
			# Each through its own door: a stake at the press, a sale only by law.
			var started: Dictionary = Processes.start(state, ns, _loader, action, firm, verb == "privatisation")
			if not bool(started.get("applied", false)):
				continue
			var row: Dictionary = ns.processes[-1]
			for i in 24:
				state.month += 1
				if state.month > 12:
					state.month = 1
					state.year += 1
				Processes.tick_month(state, _loader)
				if String(row["status"]) != Processes.OPEN:
					break
				if row.has("ask") and not row.has("answer"):
					if bool(Processes.answer(state, ns, _loader, String(row["id"]), "negotiate_15").get("ok", false)) == false:
						break
			if String(row["status"]) == "walked":
				return {"state": state, "firm": firm}
	return {}


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("PASS test_bill_refusal_line")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL %s" % f)
	quit(1)
