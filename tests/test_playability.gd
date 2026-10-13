extends SceneTree

## Headless test: godot --headless --script res://tests/test_playability.gd
## Non-zero exit on any failure.
##
## The playability audit's regressions. Twenty-plus sessions shipped simulation
## depth behind a green suite that tests systems in isolation; this file is what
## came back from the first pass that tried to PLAY the game -- boot the menu,
## press every verb, run to the election, and lose. Nine defects, five of which
## broke a playthrough. Written up in docs/playability-audit.md.
##
## The checks were first written the other way round: each asserted the BROKEN
## behaviour, so the suite stayed green while the bug sat on the record and the
## check would turn red the moment somebody fixed it. That is what happened --
## all eight went red in one run, each naming its own fix -- so they are now
## rewritten as ordinary regressions guarding the repair.
##
## Five of the nine are guarded here. V4 (a failed load from the menu starting a
## new game in silence) needs a save file to be corrupted on disk, V5 needs a
## fresh clone, and V7 and V9 are not runtime behaviour at all.
##
## Loads the actual main scene and drives it a frame at a time -- a Control
## outside the scene tree has not run _ready(), so everything it builds is null.
## See docs/engine-decision.md.

const GameState = preload("res://src/core/game_state.gd")
const Elections = preload("res://src/sim/elections.gd")
const Programme = preload("res://src/sim/programme.gd")

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
	if _main._state == null or _main._loader == null:
		_fail("main.tscn did not produce a running game")
		return

	# The boot may leave the clock held by the term-start programme; these checks
	# drive bare arrivals, so release every independent owner once, up front. Each
	# check still stages and asserts its own pause.
	_main._paused_for_programme = false
	_main._paused_for_decision = false
	_main._state.player().event_queue.clear()
	_main.get_node("Clock").paused = false

	_check_decision_arrival_stops_the_clock()
	_check_departed_and_dismissed_events_leave_the_unseen_set()
	_check_event_cards_follow_their_event()
	_check_interrupt_card_x_keeps_the_clock()
	_check_programme_then_interrupt_releases_the_clock()
	_check_manual_toggle_takes_the_clock()
	_check_eviction_spares_decision_cards()
	_check_protected_plain_card_survives_eviction()
	_check_stale_programme_hold_clears()
	_check_same_month_defaults_queue_one_effect()
	_check_opening_card_states_the_goal()
	_check_term_limit_reports_itself()
	_check_defeat_can_be_dismissed()
	_check_no_panel_can_destroy_its_window()
	_check_council_vote_leaves_a_record()
	_check_no_counted_nation_copy()
	_check_top_bar_budget_balance_label()
	_check_top_bar_election_clamp()


## X dismissal must not release independent interrupt or programme clock owner.
func _check_interrupt_card_x_keeps_the_clock() -> void:
	var Events := load("res://src/sim/events.gd")
	var ns = _main._state.player()
	var clock: Node = _main.get_node("Clock")
	var month: int = Events._absolute_month(int(_main._state.year), int(_main._state.month))
	var regions: Dictionary = Events.region_names(ns, _main._loader)
	var interrupt_ev = Events.event_by_id(_main._loader, "blackout_night")
	if interrupt_ev == null or not bool(interrupt_ev.interrupt):
		_fail("blackout_night missing or not interrupt")
		return
	ns.event_queue.clear()
	_main._unseen_events.clear()
	_main._event_cards.clear()
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	clock.paused = false
	Events.announce(ns, interrupt_ev, month, regions)
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	var card_id := ""
	for id in _main._event_cards:
		if String(_main._event_cards[id]) == String(interrupt_ev.id):
			card_id = String(id)
	if card_id == "":
		_fail("interrupt arrival did not create linked card")
	else:
		_main._hud.message_stack.dismiss(card_id)
		if not clock.paused or ns.event_queue.is_empty():
			_fail("X dismissal released clock or removed interrupt still on desk")
		# And the ANSWER must still let the clock go: the X dropped the card, not
		# the interrupt, so the arrival flag has to survive it or no later answer
		# has a pause left to release (pass 12's find).
		var answered: Dictionary = Events.answer(_main._state, _main._loader, String(interrupt_ev.id), String(interrupt_ev.choices[0]["id"]))
		if answered.is_empty():
			_fail("could not answer the interrupt after its card was dismissed")
		_main._resume_if_decision_settled()
		if clock.paused:
			_fail("answering an interrupt whose card was X-closed left the clock paused")

	ns.event_queue.clear()
	_main._unseen_events.clear()
	_main._event_cards.clear()
	_main._paused_for_decision = false
	_main._paused_for_programme = true
	clock.paused = false
	var ordinary_ev = null
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt):
			ordinary_ev = candidate
			break
	if ordinary_ev == null:
		_fail("no non-interrupt event for programme clock pin")
	else:
		Events.announce(ns, ordinary_ev, month, regions)
		_main._card_events(_main._state.year, _main._state.month, {}, {})
		card_id = ""
		for id in _main._event_cards:
			if String(_main._event_cards[id]) == String(ordinary_ev.id):
				card_id = String(id)
		if card_id == "":
			_fail("non-interrupt arrival did not create linked card")
		else:
			_main._hud.message_stack.dismiss(card_id)
			if not clock.paused:
				_fail("X dismissal released programme-owned clock")
	# The programme's own release (choosing the term's programme) must not run the
	# clock out from under an unanswered event: _decision_holds_clock() is the guard
	# _on_programme_chosen and the election dismissal both consult. Staged directly
	# as the state those doors read -- an unseen arrival, the programme flag up.
	ns.event_queue.clear()
	_main._event_cards.clear()
	_main._unseen_events.clear()
	_main._paused_for_decision = true
	_main._unseen_events["pin_unseen_event"] = true
	if not _main._decision_holds_clock():
		_fail("an unseen arrival under the decision pause did not hold the clock")
	_main._unseen_events.clear()
	_main._paused_for_decision = false
	if _main._decision_holds_clock():
		_fail("nothing unseen and nothing interrupting still held the clock")
	Events.announce(ns, interrupt_ev, month, regions)
	if not _main._decision_holds_clock():
		_fail("an interrupt event on the desk did not hold the clock")
	# And the pause menu's own close path honours the hold: Resume over a save
	# loaded through the menu must not restore a snapshot that predates it.
	_main._open_pause_menu()
	_main._note_holds_for_pause_menu()
	_main._close_pause_menu()
	if not clock.paused:
		_fail("closing the pause menu released a clock an interrupt on the desk holds after a load")
	# And without a load the snapshot rules: a player who unpaused by hand keeps it.
	clock.paused = false
	_main._open_pause_menu()
	_main._close_pause_menu()
	if clock.paused:
		_fail("the pause menu's Resume re-paused a clock the player had running")
	ns.event_queue.clear()

	_main._state.player().event_queue.clear()
	# Dismiss only the cards this check pushed: clear() would also take the boot's
	# "YOUR TERM" opening card, which a later check reads.
	for leftover in _main._event_cards.keys().duplicate():
		_main._hud.message_stack.dismiss(leftover)
	_main._event_cards.clear()
	_main._unseen_events.clear()
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	clock.paused = false


## Pass 16: a term-start programme AND an interrupt both pending. The programme's
## choice leaves the interrupt holding the clock; answering the interrupt must then
## release it. With the programme branch tested first, the first resume dropped the
## arrival flag, and the later answer's resume returned at its first line -- the
## clock stayed down for ever. Staged as the state the doors read, then driven
## through the same Events.answer / _resume_if_decision_settled calls the answer
## paths make.
func _check_programme_then_interrupt_releases_the_clock() -> void:
	var Events := load("res://src/sim/events.gd")
	var ns = _main._state.player()
	var clock: Node = _main.get_node("Clock")
	var month: int = Events._absolute_month(int(_main._state.year), int(_main._state.month))
	var regions: Dictionary = Events.region_names(ns, _main._loader)
	var interrupt_ev = Events.event_by_id(_main._loader, "blackout_night")
	if interrupt_ev == null or not bool(interrupt_ev.interrupt):
		_fail("blackout_night missing or not interrupt")
		return
	ns.event_queue.clear()
	_main._unseen_events.clear()
	_main._event_cards.clear()
	Events.announce(ns, interrupt_ev, month, regions)
	_main._paused_for_programme = true
	_main._paused_for_decision = true
	clock.paused = true
	_main._resume_if_decision_settled()
	if not _main._paused_for_decision:
		_fail("the resume dropped the arrival flag while an interrupt was still pending")
	if not clock.paused:
		_fail("the resume released the clock over a pending interrupt and an open programme")
	# _on_programme_chosen's exit state: the programme flag down, the clock kept down
	# by the interrupt (its _decision_holds_clock guard).
	_main._paused_for_programme = false
	if not _main._decision_holds_clock():
		_fail("with the programme flag down the pending interrupt should still hold the clock")
	var answered: Dictionary = Events.answer(_main._state, _main._loader, String(interrupt_ev.id), String(interrupt_ev.choices[0]["id"]))
	if answered.is_empty():
		_fail("could not answer the interrupt after the programme was chosen")
	_main._resume_if_decision_settled()
	if clock.paused:
		_fail("answering the interrupt after the programme choice left the clock paused")

	ns.event_queue.clear()
	_main._unseen_events.clear()
	_main._event_cards.clear()
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	clock.paused = false


## Pass 19 (item 1): the arrival pause belongs to the player until they touch the
## clock. Arrival -> the player runs past it (cluster button) and pauses again
## (Space) -> X on the last unseen card must leave the clock paused: the stale
## arrival flag used to let _resume_if_decision_settled() unpause against the
## player's own pause. Both manual paths are driven through their real doors (the
## cluster's signal, a real key event). The unseen mark must survive the toggles --
## the cards are still unseen, only the clock's ownership moved.
func _check_manual_toggle_takes_the_clock() -> void:
	var Events := load("res://src/sim/events.gd")
	var clock: Node = _main.get_node("Clock")
	var ns = _main._state.player()
	var ev = null
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt):
			ev = candidate
			break
	if ev == null:
		_fail("no non-interrupt event in the loader to stage the manual-toggle arrival with")
		return
	ns.event_queue.clear()
	_main._unseen_events.clear()
	for leftover in _main._event_cards.keys().duplicate():
		_main._hud.message_stack.dismiss(leftover)
	_main._event_cards.clear()
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	clock.paused = false
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	if not clock.paused or not _main._paused_for_decision or not _main._unseen_events.has(String(ev.id)):
		_fail("the manual-toggle staging did not arm the arrival pause")
		return
	var card_id := ""
	for id in _main._event_cards:
		if String(_main._event_cards[id]) == String(ev.id):
			card_id = String(id)
	if card_id == "":
		_fail("the manual-toggle arrival made no linked card")
		return
	# Each door pinned on its own: the programme hold is staged beside the arrival
	# flag, the cluster's button is pressed and BOTH must drop; then both are
	# re-armed and Space must drop both again -- so a door reverted to a bare
	# toggle fails on its own line instead of hiding behind the other.
	_main._paused_for_programme = true
	_main._hud.clock_cluster.pause_toggled.emit()
	if clock.paused:
		_fail("the cluster's pause button did not run the clock")
	if _main._paused_for_decision:
		_fail("the cluster's pause button left the arrival flag up")
	if _main._paused_for_programme:
		_fail("the cluster's pause button left the programme hold up")
	_main._paused_for_decision = true
	_main._paused_for_programme = true
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	_main._unhandled_input(space)
	if not clock.paused:
		_fail("Space did not pause the clock")
	if _main._paused_for_decision:
		_fail("Space left the arrival flag up")
	if _main._paused_for_programme:
		_fail("Space left the programme hold up")
	if not _main._unseen_events.has(String(ev.id)):
		_fail("a manual toggle erased the unseen mark (the card is still unseen)")
	_main._hud.message_stack.dismiss(card_id)
	if not clock.paused:
		_fail("closing the last unseen card unpaused a clock the player had paused by hand")

	# B: Space (run), Space (pause), then CHOOSE the programme -- the choice must not
	# unpause against the player's pause. The real choose path; its trace (register,
	# chosen-term scalar, stock, queued ledger entry, new cards) is undone after.
	var avail: Array = Programme.available(_main._state, ns, _main._loader)
	if avail.is_empty():
		_fail("no term-start offer to pin the programme choice on")
	else:
		var saved_programme: Array = ns.programme.duplicate(true)
		var saved_term: int = int(ns.programme_chosen_term)
		var saved_stock: float = float(ns.programme_stock)
		var effects_before: int = _main._pending_effects.size()
		var cards_before: Array = _main._hud.message_stack._cards.keys()
		_main._enforce_term_start_programme()  # the hold and card a real term start raises
		_main._toggle_pause_by_hand()  # run
		_main._toggle_pause_by_hand()  # pause
		if not clock.paused:
			_fail("the staging toggles left the clock running")
		_main._on_programme_chosen(String(avail[0]["id"]))
		if int(ns.programme_chosen_term) != int(ns.terms_served):
			_fail("the programme choice did not land (nothing to pin the pause on)")
		if not clock.paused:
			_fail("choosing the programme unpaused a clock the player had paused by hand")
		ns.programme = saved_programme
		ns.programme_chosen_term = saved_term
		ns.programme_stock = saved_stock
		while _main._pending_effects.size() > effects_before:
			_main._pending_effects.pop_back()
		for card in _main._hud.message_stack._cards.keys().duplicate():
			if not cards_before.has(card):
				_main._hud.message_stack.dismiss(card)
		_main._programme_card_id = ""

	ns.event_queue.clear()
	_main._unseen_events.clear()
	for leftover in _main._event_cards.keys().duplicate():
		_main._hud.message_stack.dismiss(leftover)
	_main._event_cards.clear()
	_main._paused_for_decision = false
	_main._paused_for_programme = false
	clock.paused = false


## Pass 19 (item 2): a plain card pushed with `protect` survives MAX_CARDS plain
## pushes (the term-start programme card explains a live clock hold and used to be
## the oldest plain card, so a few pushes evicted it), and main.gd pushes the
## programme card protected. Fresh stack for the generic leg so the boot's "YOUR
## TERM" card is not consumed.
func _check_protected_plain_card_survives_eviction() -> void:
	var stack = load("res://src/ui/message_stack.gd").new()
	root.add_child(stack)
	var kept: String = stack.push("kept", "body", [], null, true)
	var plain: Array[String] = []
	for i in range(stack.MAX_CARDS * 2):
		plain.append(stack.push("plain %d" % i, "body"))
	if not stack._cards.has(kept):
		_fail("a protected plain card was evicted by plain pushes")
	if stack.card_count() != stack.MAX_CARDS:
		_fail("the protected stack holds %d cards, expected MAX_CARDS" % stack.card_count())
	# All protected: nothing to spare, the oldest of all is the net.
	var wall = load("res://src/ui/message_stack.gd").new()
	root.add_child(wall)
	var first: String = wall.push("p0", "body", [], null, true)
	for i in range(wall.MAX_CARDS):
		wall.push("p%d" % (i + 1), "body", [], null, true)
	if wall._cards.has(first) or wall.card_count() != wall.MAX_CARDS:
		_fail("with every card protected the oldest should be the fallback eviction")
	stack.queue_free()
	wall.queue_free()

	# The real wiring: the programme card main.gd pushes is protected.
	var clock: Node = _main.get_node("Clock")
	_main._enforce_term_start_programme()
	if String(_main._programme_card_id).is_empty():
		_fail("the term start staged no programme card (nothing to pin the protection on)")
	elif not _main._hud.message_stack._protected.has(_main._programme_card_id):
		_fail("main.gd pushed the programme card unprotected")
	if not String(_main._programme_card_id).is_empty():
		_main._hud.message_stack.dismiss(_main._programme_card_id)
		_main._programme_card_id = ""
	_main._paused_for_programme = false
	_main._paused_for_decision = false
	clock.paused = false


## Pass 19 (follow-up A): the player runs the clock past a term start. The offer
## goes empty with no choice, and the (protected) programme card plus the
## programme hold are stale -- left up, every later arrival answer takes the
## programme branch of _resume_if_decision_settled(), drops the arrival flag and
## never resumes. _enforce_term_start_programme() (it runs every month end) must
## clear both. Staged by marking the term's programme chosen, which is the
## structural reason Programme.available() is empty; undone after.
func _check_stale_programme_hold_clears() -> void:
	var ns = _main._state.player()
	var clock: Node = _main.get_node("Clock")
	var saved_term: int = int(ns.programme_chosen_term)
	ns.programme_chosen_term = int(ns.terms_served)
	if not Programme.available(_main._state, ns, _main._loader).is_empty():
		_fail("the staged state still offers a programme (nothing to pin the stale hold on)")
	_main._programme_card_id = _main._hud.message_stack.push("stale programme", "body", [], null, true)
	var stale_card: String = _main._programme_card_id
	_main._paused_for_programme = true
	_main._enforce_term_start_programme()
	if _main._paused_for_programme:
		_fail("the stale programme hold survived a month end with no offer")
	if _main._hud.message_stack._cards.has(stale_card):
		_fail("the stale programme card survived a month end with no offer")
	if not String(_main._programme_card_id).is_empty():
		_fail("the stale programme card id was not cleared")
	ns.programme_chosen_term = saved_term
	_main._paused_for_programme = false
	_main._paused_for_decision = false
	clock.paused = false


## Pass 16: the MAX_CARDS eviction is not the player dismissing a decision. A
## paused player who triggers a crowd of plain cards (budget, tax, law results)
## must not lose the decision card -- main.gd reads every card_dismissed as "the
## card is gone" and would restart the clock over the unanswered crisis. Run on a
## FRESH stack so the boot's "YOUR TERM" card, which a later check reads, is not
## consumed by the eviction.
func _check_eviction_spares_decision_cards() -> void:
	var stack = load("res://src/ui/message_stack.gd").new()
	root.add_child(stack)  # in the tree: _ready() must have run
	var dismissed: Array[String] = []
	stack.card_dismissed.connect(func(id: String): dismissed.append(id))
	var decision: String = stack.push("A decision", "body", [{"label": "Yes"}, {"label": "No"}])
	var plain: Array[String] = []
	for i in range(stack.MAX_CARDS):
		plain.append(stack.push("plain %d" % i, "body"))
	if stack.card_count() != stack.MAX_CARDS:
		_fail("the stack holds %d cards, expected MAX_CARDS" % stack.card_count())
	if dismissed.has(decision) or not stack._cards.has(decision):
		_fail("the MAX_CARDS eviction took the decision card (a card carrying answer buttons)")
	if dismissed.size() != 1 or dismissed[0] != plain[0]:
		_fail("the eviction should have taken exactly the oldest plain card, took %s" % [dismissed])
	if not stack._cards.has(plain[1]):
		_fail("a newer plain card was evicted instead of the oldest")
	# Answer buttons on every card: nothing to spare, so the oldest of all goes.
	var all_actions = load("res://src/ui/message_stack.gd").new()
	root.add_child(all_actions)
	var first: String = all_actions.push("d0", "body", [{"label": "Yes"}])
	for i in range(all_actions.MAX_CARDS):
		all_actions.push("d%d" % (i + 1), "body", [{"label": "Yes"}])
	if all_actions._cards.has(first):
		_fail("with every card carrying buttons the oldest should be the fallback eviction")
	if all_actions.card_count() != all_actions.MAX_CARDS:
		_fail("the all-decisions stack exceeded MAX_CARDS")
	# A PLAIN newcomer into a stack of nothing but decisions evicts itself: the
	# newcomer is a candidate, so no decision card is taken and none is "dismissed".
	var crowded = load("res://src/ui/message_stack.gd").new()
	root.add_child(crowded)
	var crowded_dismissed: Array[String] = []
	crowded.card_dismissed.connect(func(id: String): crowded_dismissed.append(id))
	var decisions: Array[String] = []
	for i in range(crowded.MAX_CARDS):
		decisions.append(crowded.push("d%d" % i, "body", [{"label": "Yes"}]))
	var newcomer: String = crowded.push("plain", "body")
	for d in decisions:
		if not crowded._cards.has(d):
			_fail("a plain push into an all-decision stack evicted decision card %s" % d)
	if crowded._cards.has(newcomer):
		_fail("the plain newcomer should have evicted itself from an all-decision stack")
	if crowded_dismissed.size() != 1 or crowded_dismissed[0] != newcomer:
		_fail("only the plain newcomer should have been dismissed, got %s" % [crowded_dismissed])
	stack.queue_free()
	all_actions.queue_free()
	crowded.queue_free()


## Pass 16 (item 3): two defaults in one tick share ONE pre-tick snapshot, so a
## ledger entry per default would each claim the joint movement. The departures
## earn one "Decided for you" card each, but ONE pending effect for the tick.
func _check_same_month_defaults_queue_one_effect() -> void:
	var ns = _main._state.player()
	var year: int = int(_main._state.year)
	var month: int = int(_main._state.month)
	var history_size: int = ns.event_history.size()
	var effects_before: int = _main._pending_effects.size()
	var cards_before: Array = _main._hud.message_stack._cards.keys()
	# The live queue is snapshotted and put back below: this check stages on an
	# empty desk but must hand the player's real queue to later checks intact.
	var queue_before: Array = ns.event_queue.duplicate(true)
	ns.event_queue.clear()
	var ids := ["pin_default_a", "pin_default_b"]
	for event_id in ids:
		ns.event_history.append({
			"event_id": event_id, "event_name": "Pin %s" % event_id, "defaulted": true,
			"year": year, "month": month, "choice_label": "carry on", "region_name": "",
		})
	_main._card_events(year, month, {ids[0]: true, ids[1]: true}, {})
	if _main._pending_effects.size() != effects_before + 1:
		_fail("two same-month defaults queued %d ledger entries, expected exactly 1" % (_main._pending_effects.size() - effects_before))
	elif not String(_main._pending_effects[effects_before]["label"]).contains("; "):
		_fail("the merged ledger entry should name both events joined by '; ', got '%s'" % _main._pending_effects[effects_before]["label"])
	var new_cards := 0
	for card_id in _main._hud.message_stack._cards.keys().duplicate():
		if not cards_before.has(card_id):
			new_cards += 1
			_main._hud.message_stack.dismiss(card_id)
	if new_cards != 2:
		_fail("each default should still earn its own card, got %d" % new_cards)
	# Clean up: only what this check added.
	while _main._pending_effects.size() > effects_before:
		_main._pending_effects.pop_back()
	while ns.event_history.size() > history_size:
		ns.event_history.pop_back()
	ns.event_queue.clear()
	ns.event_queue.append_array(queue_before)


## V2.9 (from the playtest, F4): "3 months to answer" at speed 3 is thirteen
## seconds, and both playtest runs produced "Decided for you" records no player
## answered. A decision ARRIVING must stop the clock -- interrupt or not; the
## flag's own extra behaviour (opening Dispatches) stays interrupt-only. Staged
## through the real register (Events.announce) and the real arrival branch
## (_card_events with an empty desk_before), so a wiring break fails here.
func _check_decision_arrival_stops_the_clock() -> void:
	var Events := load("res://src/sim/events.gd")
	var clock: Node = _main.get_node("Clock")
	var ns = _main._state.player()
	var ev = null
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt):
			ev = candidate
			break
	if ev == null:
		_fail("no non-interrupt event in the loader to stage the arrival with")
		return
	clock.paused = false
	# The announce signature grew the month and the name map at V3.5; the staged
	# event is non-sited, so both are inert -- filled as tick_month fills them.
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	# V4.4: the third argument is the desk's BEFORE-CONTENT, not the old was-
	# pending boolean -- the staged event is on no desk before this call, so the
	# empty dictionary is false's exact successor, and the arrival branch fires.
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	if not clock.paused:
		_fail("a decision arrived and the clock kept running")
		return

	# Task 6: the card itself answers, and the clock resumes. Pressed through the
	# real button, so the whole chain is exercised -- card_action, Events.answer,
	# the unpause rule's single writer.
	var stack = _main._hud.message_stack
	var action_buttons: Array = []
	for card in stack.get_children():
		for b in card.find_children("*", "Button", true, false):
			if b.text != "X":
				action_buttons.append(b)
	if action_buttons.size() < 2:
		_fail("the decision card rendered %d choice buttons, expected at least 2" % action_buttons.size())
		return
	action_buttons[0].pressed.emit()
	if Events.is_pending(ns):
		_fail("answering from the card left the decision pending")
		return
	if clock.paused:
		_fail("the decision was answered and the clock is still stopped")


## V4.4 wave 3 (the unseen-set ghost): an id must leave _unseen_events when it
## leaves the desk or its card is dismissed. Three doors used to strand it --
## an expiry's "Decided for you" push touched nothing, card_dismissed was
## connected to nothing, and a stranded id meant the arrival pause could never
## lift (the resume gate needs the set empty) -- the clock paused over nothing.
## Driven through the real wiring: the arrival check's staging, then the
## machine's own countdown tick for the expiry door, then the card's real X
## for the dismissal door.
func _check_departed_and_dismissed_events_leave_the_unseen_set() -> void:
	var Events := load("res://src/sim/events.gd")
	var clock: Node = _main.get_node("Clock")
	var ns = _main._state.player()
	var ev = null
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt):
			ev = candidate
			break
	if ev == null:
		_fail("no non-interrupt event in the loader to stage the doors with")
		return

	# Door 1, the desk: stage the arrival, fire the default through the machine's
	# own countdown tick (the expiry a sleeping player suffers), then run the
	# month handler with the id on the BEFORE-desk and off the now one.
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	if not _main._unseen_events.has(String(ev.id)):
		_fail("the staged arrival never armed its unseen mark")
		return
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) == String(ev.id):
			entry["months_left"] = 1
	Events._tick_countdowns(_main._state, ns, _main._loader,
		Events._absolute_month(int(_main._state.year), int(_main._state.month)))
	_main._card_events(_main._state.year, _main._state.month, {String(ev.id): true}, {})
	if _main._unseen_events.has(String(ev.id)):
		_fail("an expired event's id stayed in _unseen_events -- the ghost")
		return
	if _main._paused_for_decision or clock.paused:
		_fail("the desk emptied and the clock stayed paused over nothing")

	# The same default must also dismiss the event's arrival card -- the two
	# are linked by _event_cards (card id -> event id) and a card whose event
	# has left the desk carries dead buttons that no-op against an empty desk.
	for card_id in _main._event_cards:
		if String(_main._event_cards[card_id]) == String(ev.id):
			_fail("the defaulted event's arrival card is still in _event_cards")
			return

	# Door 2, the X: the card's dismissal must take the unseen mark with it and
	# resume the clock by the same rule. Pressed through the real button, so a
	# missing connect fails here. (The MAX_CARDS eviction also dismisses through
	# this signal but never takes a decision card -- pinned in
	# _check_eviction_spares_decision_cards.)
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	if not clock.paused or not _main._unseen_events.has(String(ev.id)):
		_fail("the second staged arrival did not re-arm the pause")
		return
	var stack = _main._hud.message_stack
	var x_button: Button = null
	for card in stack.get_children():
		var has_actions := false
		var card_x: Button = null
		for b in card.find_children("*", "Button", true, false):
			if b.text == "X":
				card_x = b
			else:
				has_actions = true
		# LAST match, not first: door 1's default pushes a "Decided for you" card
		# (no actions) and this second arrival pushes a fresh decision card, and
		# push() appends -- so the newest action-carrying card is the last child.
		# The defaulted event's OWN arrival card no longer lingers here: V4.4 wave
		# 4 dismisses it at the departure door (_dismiss_event_cards), so this
		# loop is choosing among live cards, not routing around a stale one.
		if has_actions and card_x != null:
			x_button = card_x
	if x_button == null:
		_fail("the decision card rendered no X to dismiss it with")
		return
	x_button.pressed.emit()
	if _main._unseen_events.has(String(ev.id)):
		_fail("a dismissed card left its event's id in _unseen_events")
		return
	if _main._paused_for_decision or clock.paused:
		_fail("the last unseen card was dismissed and the clock is still stopped")


## V4.4 wave 4: a card linked to an event (_event_cards) must go when that event
## leaves the desk, whether the player answered it through Dispatches or the
## machine defaulted it from under them. Two doors used to leave the card behind;
## a stale card's buttons called Events.answer on an id off the desk, got {} from
## a missing entry, and silently did nothing. Driven through the real panel's
## _on_choose for the answer door, and the machine's countdown + month handler
## for the default door.
func _check_event_cards_follow_their_event() -> void:
	var Events := load("res://src/sim/events.gd")
	var ns = _main._state.player()
	var stack = _main._hud.message_stack
	# Sweep the desk of entries prior tests left pending, so each pin stages on a
	# clean slate -- an id in the queue twice confuses the arrival loop and the
	# answer() search (duplicate events are not the test's subject).
	ns.event_queue.clear()

	var ev = null
	for candidate in _main._loader.events:
		if not bool(candidate.interrupt):
			ev = candidate
			break
	if ev == null:
		_fail("no non-interrupt event in the loader to stage the card doors with")
		return

	# Pin (1), the Dispatches answer path. Stage the arrival, then answer it
	# through the panel's own _on_choose -- the path Dispatches buttons and
	# main.gd's `acted` handler ride. The handler now calls _dismiss_event_cards
	# for ids no longer on the desk.
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	var card_ids_before: Array = []
	for card_id in _main._event_cards:
		if String(_main._event_cards[card_id]) == String(ev.id):
			card_ids_before.append(card_id)
	if card_ids_before.is_empty():
		_fail("pin 1: the staged arrival left no card for its event")
		return
	_main._events_panel._on_choose(ev, ev.choices[0])
	for card_id in card_ids_before:
		if _main._event_cards.has(card_id):
			_fail("pin 1: the Dispatches answer left its card in _event_cards")
			return
		if stack._cards.has(card_id):
			_fail("pin 1: the Dispatches answer left its card in the message stack")
			return

	# Pin (2), the machine's default/expiry door. Stage a fresh arrival, force
	# the desk entry to expire through the countdown tick, run the month handler
	# with the id on the BEFORE-desk and off the now one. The "Decided for you"
	# card that the departure loop pushes may remain -- it carries no actions.
	ns.event_queue.clear()
	Events.announce(ns, ev, Events._absolute_month(int(_main._state.year), int(_main._state.month)),
		Events.region_names(ns, _main._loader))
	_main._card_events(_main._state.year, _main._state.month, {}, {})
	var default_card_ids: Array = []
	for card_id in _main._event_cards:
		if String(_main._event_cards[card_id]) == String(ev.id):
			default_card_ids.append(card_id)
	if default_card_ids.is_empty():
		_fail("pin 2: the staged arrival left no card for its event")
		return
	for entry in ns.event_queue:
		if String(entry.get("event_id", "")) == String(ev.id):
			entry["months_left"] = 1
	Events._tick_countdowns(_main._state, ns, _main._loader,
		Events._absolute_month(int(_main._state.year), int(_main._state.month)))
	_main._card_events(_main._state.year, _main._state.month, {String(ev.id): true}, {})
	for card_id in default_card_ids:
		if _main._event_cards.has(card_id) or stack._cards.has(card_id):
			_fail("pin 2: the defaulted event's arrival card survived its own default")
			return


## V2.9 (from the playtest): nothing anywhere said what is being played for. A
## new game opens on a running clock with nothing pending; the stack's first
## card must state the office, the deadline and the count, read off the same
## Trends query the top bar and the Overview count by. The load path cannot
## reach the push (it sits inside the new-game branch of _ready, one code path
## to keep correct), so no save-file harness is built to assert its absence.
func _check_opening_card_states_the_goal() -> void:
	var Trends := load("res://src/ui/trends.gd")
	var ns = _main._state.player()
	var when: Vector2i = Trends.vote_date(ns)
	var months: int = Trends.months_to_vote(_main._state, ns)

	var stack_text := _collect_labels(_main._hud.message_stack)
	if not stack_text.contains("YOUR TERM"):
		_fail("the opening card is missing -- a new game never states its goal (stack: '%s')" % stack_text)
		return
	if not stack_text.contains(str(months)) or not stack_text.contains(str(when.x)):
		_fail("the opening card does not carry the deadline (count %d, year %d): '%s'" % [months, when.x, stack_text])


## Every Label text under a node, deepest-first queue_free caveat aside -- the
## stack is built once per card, so on this fresh boot no stale labels exist.
func _collect_labels(node: Node) -> String:
	var out := ""
	for child in node.get_children():
		if child is Label:
			out += child.text + " "
		out += _collect_labels(child)
	return out


# V1. The term-limit branch used to set in_government = false and append NOTHING,
# and main.gd gates the result screen on a non-empty Array -- so the one event
# that ends a French presidency rendered no screen, no pause and no card, and
# Elections.tick_month() then skipped the nation for good, leaving a clock running
# with no election able to resolve and nothing anywhere saying why.
func _check_term_limit_reports_itself() -> void:
	var loader = _main._loader
	var state = GameState.new_game(loader, "FRA")
	if not state.errors.is_empty():
		_fail("V1: new_game reported %s" % [state.errors])
		return

	var ns = state.player()
	if ns.term_limit <= 0:
		_fail("V1: FRA no longer carries a term limit -- this check needs rewriting")
		return

	# Stand the player on the last month of their last permitted term, and move
	# the Assembly's own clock out of the way so only the executive branch fires.
	ns.terms_served = ns.term_limit
	ns.next_executive_year = state.year
	ns.next_executive_month = state.month
	ns.next_election_year = state.year + 50

	var results := Elections.tick_month(state, loader)

	if ns.in_government:
		_fail("V1: a termed-out president stayed in government")

	var termed := 0
	for r in results:
		# Its own kind, deliberately: a termed-out notice is not an election, and
		# test_balance.gd counts by kind to assert the limit BARS a third executive
		# election. See elections.gd.
		if r.get("kind", "") == "termed_out":
			termed += 1

	if termed != 1:
		_fail(
			"V1 REGRESSED: a term limit reported %d termed-out result(s), so the screen the player sees is empty again"
			% termed
		)


# V2. The Continue button used to be built only in the not-defeated branch, and
# main.gd unpauses only on `dismissed`. That left a plate with nothing to press
# over a HUD that stayed live -- _add_centered() defaults to non-blocking, so the
# holder is MOUSE_FILTER_IGNORE -- and Space resumed a run the player had lost.
func _check_defeat_can_be_dismissed() -> void:
	var panel = _main._election_panel
	if panel == null:
		_fail("V2: main.gd built no election panel")
		return

	var state = _main._state
	var ns = state.player()
	var party_list: Array = _main._loader.parties.get(ns.id, [])

	# Force the verdict rather than playing eleven years to earn it. The panel's
	# `defeated` test reads exactly these two.
	var result := Elections.resolve_executive(ns, party_list, state.year, state.month)
	result["incumbent_largest"] = false
	ns.in_government = false

	panel.show_results([result])

	if panel._title.text != "DEFEATED":
		_fail("V2: the forced result did not render as a defeat (title was %s)" % panel._title.text)

	var buttons: Array = []
	for child in panel._footer.get_children():
		if child is Button:
			buttons.append(child)

	if buttons.is_empty():
		_fail("V2 REGRESSED: the defeat screen offers no control at all, so the clock stays paused for good")
	elif not panel.dismissed.get_connections().is_empty():
		# Deliberately NOT pressed: main.gd's handler leaves office by changing
		# scene, which would tear this test's own tree out from under it. That the
		# button exists and `dismissed` is wired is the whole of the regression.
		pass
	else:
		_fail("V2 REGRESSED: nothing is connected to `dismissed`, so the button leads nowhere")

	# A won election must still say Continue and must NOT offer to leave office.
	result["incumbent_largest"] = true
	ns.in_government = true
	panel.show_results([result])
	# LAST match, not any match: show_results() clears the footer with queue_free(),
	# which is deferred, so within this one frame the container still holds the
	# "Leave office" button built moments ago. test_nation_panel.gd:60-69 records
	# the same trap -- only presence assertions are valid here, and only the last.
	var latest := ""
	for child in panel._footer.get_children():
		if child is Button:
			latest = child.text
	if latest != "Continue":
		_fail("V2: a WON election offers `%s` rather than Continue" % latest)

	panel.hide()


# V3 and V6. Five panels built their own Close button and no two behaved the same
# way: three called hide() on the panel's own content while window_manager.open()
# only ever shows the FRAME -- so Diplomacy, The Union and the Diary were
# permanently blanked by one click, and reopening was the action that proved it --
# and two emitted an unconnected signal and did nothing at all.
#
# main.gd now calls hide_close_button() for all five, as it always had for the
# other four. The check is that NO docked panel shows a Close button of its own.
func _check_no_panel_can_destroy_its_window() -> void:
	var by_window := {
		"diplomacy": "_nation_panel",
		"orgs": "_orgs_panel",
		"calendar": "_calendar_panel",
		"companies": "_companies_panel",
		"people": "_people_panel",
		"budget": "_budget_panel",
		"politics": "_government_panel",
		"society": "_polling_panel",
		"legislature": "_law_panel",
	}
	for window_id in by_window:
		var panel = _main.get(by_window[window_id])
		if panel == null:
			_fail("V3: main.gd built no %s" % by_window[window_id])
			continue

		_main._windows.open(window_id)

		var close := _visible_close_button(panel)
		if close != null:
			_fail(
				"V3/V6 REGRESSED: %s shows its own Close button. Either it blanks the window for good or it does nothing; there is no third option."
				% by_window[window_id]
			)
			continue

		# The window frame's X is the real control, and it must leave the content
		# alone so the window can be reopened.
		_main._windows.close(window_id)
		_main._windows.open(window_id)
		if not panel.visible:
			_fail("V3 REGRESSED: %s did not come back when its window was reopened" % by_window[window_id])


# V8. Every other player command carries a signal main.gd turns into a U4 effect
# delta -- budget `committed`, law `proposed`, diplomacy and companies `acted`,
# government `dissolved` and `reassigned`. bloc_panel carried only `closed`, so a
# council vote, binding on the player whichever way it goes, never reached the one
# surface built to say what you did.
func _check_council_vote_leaves_a_record() -> void:
	var orgs_panel = _main._orgs_panel
	if orgs_panel == null:
		_fail("V8: main.gd built no orgs panel")
		return

	if not orgs_panel.has_signal("voted"):
		_fail("V8 REGRESSED: orgs_panel has no command signal, so a council vote is unrecorded again")
		return

	# A signal nothing listens to is the same silence with more code in it.
	if orgs_panel.voted.get_connections().is_empty():
		_fail("V8 REGRESSED: bloc_panel.voted is connected to nothing, so no effect delta is queued")

	# State the comparison rather than asserting the presence alone: this check is
	# about bloc_panel matching the other six, so it has to know they still exist.
	for pair in [
		["_budget_panel", "committed"],
		["_law_panel", "proposed"],
		["_nation_panel", "acted"],
		["_companies_panel", "acted"],
		["_government_panel", "dissolved"],
		["_government_panel", "reassigned"],
	]:
		var panel = _main.get(pair[0])
		if panel != null and not panel.has_signal(pair[1]):
			_fail("V8: %s lost its `%s` signal -- this check's comparison is stale" % [pair[0], pair[1]])


## The panel's OWN Close button, ignoring the window frame's X and anything the
## action bar built. Scoped the way test_nation_panel.gd scopes its button walk: a
## whole-scene search finds furniture the panel did not build and passes for the
## wrong reason.
func _visible_close_button(panel) -> Button:
	var found: Button = null
	for node in _descendants(panel):
		if node is Button and node.text == "Close" and node.visible:
			found = node
	return found


func _descendants(node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out


## B5 (playtest 2026-09-16). "The ten the game simulates" was a hardcoded count
## in player-visible copy, and it went stale once already -- the roster has been
## 29 nations since V3.3 when the copy still said ten. The fix is count-free, so
## this scan forbids the fragment anywhere under src/ui/ rather than pinning the
## two repaired files: a source scan is the only form that also catches the next
## session reintroducing it in a third place. String literals only by convention
## -- comment lines are stripped first, the same discipline the geography
## register scan adopted after it fired on a docstring.
func _check_no_counted_nation_copy() -> void:
	var dir := DirAccess.open("res://src/ui")
	if dir == null:
		_fail("could not open res://src/ui for the copy scan")
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir() and name.ends_with(".gd"):
			var lines: PackedStringArray = FileAccess.open(
				"res://src/ui/" + name, FileAccess.READ
			).get_as_text().split("\n")
			for i in lines.size():
				var line := lines[i]
				var hash := line.find("#")
				if hash != -1:
					line = line.substr(0, hash)
				if line.contains("The ten "):
					_fail("stale nation count in player copy: src/ui/%s:%d" % [name, i + 1])
		name = dir.get_next()


func _fail(message: String) -> void:
	_failures.append(message)


## B10 (playtest 2026-09-16): the figure was titled "DEFICIT" while its value was
## signed -- a surplus printed "+2.1%", a deficit "-10.5%", so "DEFICIT +10.50%"
## sat on screen contradicting itself. The label is a balance now.
func _check_top_bar_budget_balance_label() -> void:
	var top_bar = _main._top_bar
	if top_bar == null:
		_fail("B10: main.gd built no top bar")
		return
	var found := false
	for node in _descendants(top_bar):
		if node is Label and node.text == "BUDGET BALANCE":
			found = true
	if not found:
		_fail("B10 REGRESSED: the top bar carries no BUDGET BALANCE label -- the deficit figure reverted to its self-contradicting title")


## B1/B3 (playtest 2026-09-16): the election figure printed the raw int, and two
## ten-year captures showed "NEXT VOTE -44 mo" -- months_to_vote can legally go
## negative once the vote date has passed. The figure must clamp like its own
## tooltip already does, and the tooltip must name WHICH clock it counts
## (executive where one exists) beside the polling panel's assembly one.
func _check_top_bar_election_clamp() -> void:
	var top_bar = _main._top_bar
	if top_bar == null:
		_fail("B1: main.gd built no top bar")
		return

	var state = GameState.new_game(_main._loader, "FRA")
	if not state.errors.is_empty():
		_fail("B1: new_game reported %s" % [state.errors])
		return
	var ns = state.player()

	# > 0: the ordinary countdown, "%d mo".
	top_bar.refresh(state, _main._clock, _main._loader)
	var positive: String = top_bar._figure_values["election"].text
	if not positive.ends_with("mo"):
		_fail("B1: a future vote printed '%s', expected the '%d mo' countdown form" % [positive, ns.next_election_year])

	# == 0: the vote is this month.
	ns.next_executive_year = state.year
	ns.next_executive_month = state.month
	top_bar.refresh(state, _main._clock, _main._loader)
	if top_bar._figure_values["election"].text != "now":
		_fail("B1: a vote due this month printed '%s', expected 'now'" % top_bar._figure_values["election"].text)

	# < 0: the date has passed and the schedule has not rolled -- the -44 capture.
	ns.next_executive_month -= 44
	top_bar.refresh(state, _main._clock, _main._loader)
	if top_bar._figure_values["election"].text != "—":
		_fail("B1 REGRESSED: a stale vote date printed '%s' -- the raw negative that captured as 'NEXT VOTE -44 mo'" % top_bar._figure_values["election"].text)
	var tip: String = top_bar._figure_values["election"].tooltip_text
	if tip != "The vote that ends your term has been held.":
		_fail("B1: the past-vote tooltip reads '%s'" % tip)


func _finish() -> void:
	if _failures.is_empty():
		print("test_playability: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
