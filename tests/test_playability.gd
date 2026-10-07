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

	_check_decision_arrival_stops_the_clock()
	_check_opening_card_states_the_goal()
	_check_term_limit_reports_itself()
	_check_defeat_can_be_dismissed()
	_check_no_panel_can_destroy_its_window()
	_check_council_vote_leaves_a_record()
	_check_no_counted_nation_copy()
	_check_top_bar_budget_balance_label()
	_check_top_bar_election_clamp()


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
	# real button, so the whole chain is exercised -- card_action, Events.choose,
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
