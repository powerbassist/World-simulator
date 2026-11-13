extends SceneTree
## V5.3 the audience's states live in one table (src/ui/audience_flow.gd); the old scene kept them in
## scattered flags and H3 ("no choice resets on a press") was the cost. Headless, no scene.
##
##   - Every state is reachable from the question by the table's events alone.
##   - Refuse goes to its own state and from there only to the end: no line can be asked after a
##     refusal (the author's second ruling), and no event leads from REFUSED to the deal's states.
##   - ENDED is terminal; an event a state has no row for changes nothing and says so.
##   - The sim's `struck` takes the question (and its open date grid) to GRANTED, and nothing else.
##   - What the player chose lives beside the state and no event touches it (H3).
const AudienceFlow = preload("res://src/ui/audience_flow.gd")

const S = AudienceFlow.S

var _failures: Array[String] = []


func _init() -> void:
	_check_every_state_is_reachable()
	_check_refuse_is_an_end()
	_check_ended_is_terminal_and_illegal_events_do_nothing()
	_check_the_sims_struck_takes_the_question_to_the_deal()
	_check_choices_survive_every_event()
	_check_the_talk_is_open_only_after_a_deal()
	_finish()


## Breadth first over NEXT from QUESTION: the set reached is every state.
func _check_every_state_is_reachable() -> void:
	var seen := {S.QUESTION: true}
	var queue: Array = [S.QUESTION]
	while not queue.is_empty():
		var here: int = queue.pop_front()
		for event in AudienceFlow.NEXT[here]:
			var there: int = AudienceFlow.NEXT[here][event]
			if not seen.has(there):
				seen[there] = true
				queue.append(there)
	for name in S.keys():
		_ok(seen.has(S[name]), "state %s is not reachable from the question" % name)


func _check_refuse_is_an_end() -> void:
	var flow := AudienceFlow.new()
	_ok(flow.fire("refuse") and flow.state == S.REFUSED, "Refuse did not reach its own state")
	_ok(not flow.fire("ask") and not flow.ask("gossip"), "a line was asked after Refuse")
	_ok(not flow.fire("deal_struck") and flow.state == S.REFUSED, "a deal was struck after Refuse")
	_ok(not flow.in_talk(), "the talk is open after Refuse")
	_ok(flow.asked.is_empty() and flow.answer == "", "a refusal left a line marked asked")
	_ok(flow.fire("end") and flow.state == S.ENDED, "the refusal's way out did not end the audience")
	# Reachability, the other way: no path from REFUSED touches GRANTED or ANSWERED.
	var seen := {}
	var queue: Array = [S.REFUSED]
	while not queue.is_empty():
		var here: int = queue.pop_front()
		for event in AudienceFlow.NEXT[here]:
			var there: int = AudienceFlow.NEXT[here][event]
			if not seen.has(there):
				seen[there] = true
				queue.append(there)
	_ok(not seen.has(S.GRANTED) and not seen.has(S.ANSWERED) and not seen.has(S.QUESTION), "REFUSED leads back to a live state: %s" % [seen.keys()])


func _check_ended_is_terminal_and_illegal_events_do_nothing() -> void:
	_ok((AudienceFlow.NEXT[S.ENDED] as Dictionary).is_empty(), "ENDED has an exit")
	var flow := AudienceFlow.new()
	for event in ["ask", "end", "close_date", "nonsense"]:
		_ok(not flow.fire(event) and flow.state == S.QUESTION, "the question took the event '%s' it has no row for" % event)
	flow.fire("abandon")
	_ok(flow.state == S.ENDED, "abandon (the frame's X) did not end the question")
	_ok(not flow.fire("open_date") and flow.state == S.ENDED, "an ended audience took an event")


func _check_the_sims_struck_takes_the_question_to_the_deal() -> void:
	var flow := AudienceFlow.new()
	flow.sync(false)
	_ok(flow.state == S.QUESTION, "a deal not struck moved the flow")
	flow.fire("open_date")
	flow.sync(true)
	_ok(flow.state == S.GRANTED, "a struck deal left the open date grid up: %s" % flow.name_of(flow.state))
	flow.ask("family")
	flow.sync(true)
	_ok(flow.state == S.ANSWERED, "sync moved the talk")
	var refused := AudienceFlow.new()
	refused.fire("refuse")
	refused.sync(true)
	_ok(refused.state == S.REFUSED, "sync reopened a refusal")


## H3: a date, a face and the lines asked belong to the flow, not to the widgets, and no event resets them.
func _check_choices_survive_every_event() -> void:
	var flow := AudienceFlow.new()
	flow.date = {"year": 2027, "month": 4, "day": 16}
	flow.fire("open_date")
	flow.fire("close_date")
	flow.fire("open_date")
	flow.fire("deal_struck")
	flow.lines = [{"id": "gossip"}, {"id": "family"}]
	flow.pick("gossip", "FRA_x")
	_ok(flow.ask("gossip") and flow.ask("family"), "the talk would not take two lines")
	_ok(flow.date == {"year": 2027, "month": 4, "day": 16}, "an event reset the date")
	_ok(flow.picked.get("gossip", "") == "FRA_x" and flow.asked.has("gossip") and flow.asked.has("family"), "an event reset the face or the lines asked")
	_ok(flow.lines.size() == 2, "an event re-ranked the talk")


func _check_the_talk_is_open_only_after_a_deal() -> void:
	var flow := AudienceFlow.new()
	_ok(not flow.in_talk(), "the question counts as the talk")
	flow.fire("open_date")
	_ok(not flow.in_talk(), "an open date grid counts as the talk")
	flow.fire("deal_struck")
	_ok(flow.in_talk() and flow.state == S.GRANTED, "a deal struck did not open the talk")
	flow.fire("end")
	_ok(not flow.in_talk() and flow.state == S.ENDED, "the end left the talk open")


func _ok(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_audience_states: OK")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		print("test_audience_states: FAIL (%d)" % _failures.size())
		quit(1)
