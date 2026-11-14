extends SceneTree

## Headless test: godot --headless --script res://tests/test_acknowledgments.gd
## Non-zero exit on any failure.
##
## V2.9 (from the playtest, finding F3): "the world computes consequences but
## never announces them." A committed budget answered with one corner number
## changing; a law vote resolved as a text swap inside its own panel; a
## diplomatic act refused itself in silence. This file drives the three verbs
## the way a player reaches them and asserts the message stack gains one card
## per verb whose text names the outcome.
##
## Driven a frame at a time -- a Control outside the scene tree has not run
## _ready(), so everything it builds is null. See docs/engine-decision.md.

const Division = preload("res://src/sim/division.gd")
const FinanceBill = preload("res://src/sim/finance_bill.gd")

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the scene's _ready() run

	_run()
	_finish()
	return false


func _run() -> void:
	if _main._state == null:
		_fail("main scene did not produce a running game")
		return

	_check_budget_commit_answers()
	_check_withdraw_answers()
	_check_law_proposal_answers()
	_check_diplomatic_act_answers()


## Committing a real lever change tables the finance bill (docs/design/finance-bill.md)
## and must answer with a card saying so and when it is voted.
func _check_budget_commit_answers() -> void:
	var before_count: int = _main._hud.inbox.card_count()
	var panel = _main._budget_panel
	panel._pending["spending_pct_gdp"]["health"] = float(_main._state.player().spending_pct_gdp["health"]) + 1.0
	panel._on_commit()
	if _main._hud.inbox.card_count() != before_count + 1:
		_fail("a committed budget pushed no acknowledgment card")
		return
	var text := _stack_text()
	if not text.contains("FINANCE BILL TABLED"):
		_fail("the budget card is not titled for the verb: '%s'" % text)
	if not text.to_lower().contains("month's end"):
		_fail("the budget card does not say when the bill is voted: '%s'" % text)
	# The bill holds the month's slot: divide it, so the law check below meets an empty one.
	_divide()


## Withdrawing the finance bill (QA's T1 on #331) frees the slot and answers with a card.
## The verb shows only while a finance bill is tabled: no dead button, and the Tax Code's
## prose budget (test_prose_budget) is read with no bill in the slot.
func _check_withdraw_answers() -> void:
	_main._tax_panel._refresh()
	if _main._tax_panel._withdraw_button.visible:
		_fail("'Withdraw the bill' shows with no finance bill tabled")
	FinanceBill.table(_main._state, _main._loader, {"tax_rates_pct": {"income": 5.0}})
	_main._tax_panel._refresh()
	if not _main._tax_panel._withdraw_button.visible:
		_fail("'Withdraw the bill' is hidden while a finance bill is tabled")
	var before_count: int = _main._hud.inbox.card_count()
	for child in _main._tax_panel.find_children("*", "Button", true, false):
		if (child as Button).text == tr("Withdraw the bill"):
			(child as Button).pressed.emit()
	if _main._hud.inbox.card_count() != before_count + 1 or not _stack_text().contains("FINANCE BILL WITHDRAWN"):
		_fail("withdrawing the finance bill pushed no card saying so: '%s'" % _stack_text())
	if not _main._state.player().tabled_bill.is_empty():
		_fail("withdrawing the finance bill left it in the slot")


## Proposing a law must answer with a card titled with the law and carrying the
## division -- the outcome is deterministic for a fixed seed, so this asserts
## the shape (law name + passed/failed + numbers) and not which way it goes.
func _check_law_proposal_answers() -> void:
	var before_count: int = _main._hud.inbox.card_count()
	var law = _main._law_panel._find_law("workplace_safety_act")
	if law == null:
		_fail("the law fixture workplace_safety_act is not in the loader")
		return
	# V4.2 T5: _on_propose opens the bill briefing; the division -- and the
	# card this test pins -- is run_proposal(), the verb the briefing's own
	# button routes into.
	_main._law_panel.run_proposal(law)
	if _main._hud.inbox.card_count() != before_count + 1:
		_fail("a proposed law pushed no acknowledgment card")
		return
	_divide()
	# V5.2 b+ R2: the division sets its verdict on the tabling's card, in place.
	if _main._hud.inbox.card_count() != before_count + 1:
		_fail("the tabled law's division gave %d cards, not the tabling's one" % (_main._hud.inbox.card_count() - before_count))
		return
	var text := _stack_text()
	if not text.contains(String(law.law_name).to_upper()):
		_fail("the law card is not titled with the law: '%s'" % text)
	# V5.2 b+ R2: the verdict reads Carried or Defeated, the division in for and against.
	if not (text.contains("CARRIED") or text.contains("DEFEATED")):
		_fail("the law card does not carry the outcome: '%s'" % text)
	if not text.contains(" FOR,"):
		_fail("the law card carries no division: '%s'" % text)


## A refused act must SAY it is refused -- the playtest's silent-grey-row
## finding. State visit at month one is behind the meeting precondition, so the
## refusal branch is the deterministic one to assert on.
func _check_diplomatic_act_answers() -> void:
	var before_count: int = _main._hud.inbox.card_count()
	var panel = _main._nation_panel
	panel.show_nation("DEU")
	var action = null
	# Not a meeting verb: since V5.1-d1b2 (G13) those book a visit through the Diary
	# rather than act, and their acknowledgment is the diary's own.
	for candidate in _main._loader.diplomatic_actions:
		if not candidate.opens_meeting:
			action = candidate
			break
	if action == null:
		_fail("no instant diplomatic action in the loader")
		return
	panel._on_act(action)
	if _main._hud.inbox.card_count() != before_count + 1:
		_fail("a diplomatic act pushed no acknowledgment card, refused or not")
		return
	var text := _stack_text()
	if not text.contains(String(action.action_name).to_upper()):
		_fail("the diplomacy card is not titled with the action: '%s'" % text)
	if not text.contains("REFUSED") and not text.contains("AGREED"):
		_fail("the diplomacy card carries no outcome: '%s'" % text)


## Every Label under the stack. Cards are freed only on dismiss, so on this
## fresh boot the texts present are the ones the verbs just pushed.
func _stack_text() -> String:
	return _collect_labels(_main._hud.inbox).to_upper()


func _collect_labels(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label:
			out += child.text + " "
		elif child is RichTextLabel:  # V5.1-c: the inbox body is a rich line
			out += child.get_parsed_text() + " "
		out += _collect_labels(child)
	return out

## V5.2 b+ R2: the tabled bill divides at the month's close -- through main's own
## Division hook, so the division's card is the one the game pushes.
func _divide() -> void:
	var report := {"division": Division.divide(_main._state, _main._loader)}
	_main._on_month_step("Division", true, report, _main._state.year, _main._state.month)


func _fail(msg: String) -> void:
	_failures.append(msg)
	push_error("FAIL: " + msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_acknowledgments: all checks passed")
		quit(0)
	else:
		for f in _failures:
			print("FAIL: " + f)
		print("test_acknowledgments: %d failures" % _failures.size())
		quit(1)
