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
	_check_law_proposal_answers()
	_check_diplomatic_act_answers()


## Committing a real lever change must answer with a card naming the deficit.
func _check_budget_commit_answers() -> void:
	var before_count: int = _main._hud.inbox.card_count()
	var panel = _main._budget_panel
	panel._pending["income_tax"] = 25.0
	panel._on_commit()
	if _main._hud.inbox.card_count() != before_count + 1:
		_fail("a committed budget pushed no acknowledgment card")
		return
	var text := _stack_text()
	if not text.contains("BUDGET COMMITTED"):
		_fail("the budget card is not titled for the verb: '%s'" % text)
	if not text.to_lower().contains("deficit"):
		_fail("the budget card does not name the deficit: '%s'" % text)


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
