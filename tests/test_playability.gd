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

	_check_term_limit_reports_itself()
	_check_defeat_can_be_dismissed()
	_check_no_panel_can_destroy_its_window()
	_check_council_vote_leaves_a_record()


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
		"bloc": "_bloc_panel",
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
	var bloc_panel = _main._bloc_panel
	if bloc_panel == null:
		_fail("V8: main.gd built no bloc panel")
		return

	if not bloc_panel.has_signal("voted"):
		_fail("V8 REGRESSED: bloc_panel has no command signal, so a council vote is unrecorded again")
		return

	# A signal nothing listens to is the same silence with more code in it.
	if bloc_panel.voted.get_connections().is_empty():
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


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_playability: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
