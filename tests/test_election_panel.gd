extends SceneTree

## Headless test: godot --headless --script res://tests/test_election_panel.gd
## Non-zero exit on any failure.
##
## Loads the actual main scene and turns the actual clock, the same shape
## test_game_loop.gd uses, so a broken signal path between the clock, the
## election tick and the panel fails here rather than in a playtest. Driven a
## frame at a time because a Control outside the scene tree has not run
## _ready() — see docs/engine-decision.md. The geometry checks run two frames
## behind the text ones for the same reason one step on: sizes are settled only
## after the panel has laid out at its real width.
##
## France runs two clocks, so this drives past two panels. First the
## presidential election of May 2027, which is the one that can end the game.
## Then June 2029, when the legislative and European Parliament elections land
## in the same month — the double-election case is the one most likely to break
## a panel written for a single result.

const OpinionK = preload("res://src/sim/opinion_constants.gd")

const EXEC_MONTHS := 16       # January 2026 to May 2027, FRA's presidential term.
const TARGET_MONTHS := 41     # January 2026 to June 2029, the Assembly's term.
const GEOMETRY_LAG := 2       # frames between a panel opening and its sizes being read.

const EXEC_TEXT_FRAME := 2
const EXEC_GEOMETRY_FRAME := EXEC_TEXT_FRAME + GEOMETRY_LAG
const NATIONAL_GEOMETRY_FRAME := EXEC_GEOMETRY_FRAME + GEOMETRY_LAG

var _failures: Array[String] = []
var _main
var _frame := 0
var _done := false


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _done or _frame < EXEC_TEXT_FRAME:
		return false  # let the scene's _ready() run, or let quit() land
	if _frame == EXEC_TEXT_FRAME:
		_run_exec_text()
	elif _frame == EXEC_GEOMETRY_FRAME:
		# One frame does both: the laid-out executive table is read, then the
		# panel is dismissed and the clock driven on — the double-election
		# panel gets its own GEOMETRY_LAG frames before its geometry is read.
		_check_exec_geometry()
		_run_national_text()
	elif _frame == NATIONAL_GEOMETRY_FRAME:
		_check_national_geometry()
		_finish()
	return false


func _run_exec_text() -> void:
	if _main._state == null:
		_fail("main scene did not build a GameState")
		_finish()
		return

	var clock: Node = _main.get_node("Clock")
	var ns = _main._state.player()

	_advance(clock, EXEC_MONTHS)

	# The presidential election must have paused the clock and opened the panel.
	if not clock.paused:
		_fail("the clock did not pause for the presidential election (clock at %d-%d)" % [clock.year, clock.month])
		_finish()
		return
	var exec_text := _collect_text(_main._election_panel)
	if not exec_text.contains("Presidential election"):
		_fail("the May 2027 panel is not labelled a presidential election: %s" % exec_text)
	if not ns.in_government:
		_fail("the incumbent lost the 2027 presidential election, so the rest of this test cannot run")
		_finish()
		return
	if not exec_text.contains("RE-ELECTED"):
		_fail("won the presidency but the panel does not say so: %s" % exec_text)

	# A presidential result allocates no seats (elections.gd leaves "seats"
	# empty there), so the table must not carry a seats column at all.
	if exec_text.contains("seats"):
		_fail("the executive table carries a seats column although the office allocates none: %s" % exec_text)

	# The panel stays open: the geometry pass GEOMETRY_LAG frames from now reads
	# it at its laid-out width before dismissing it.


func _check_exec_geometry() -> void:
	var scroll := _find_scroll(_main._election_panel)
	if scroll == null:
		_fail("the election panel has no ScrollContainer")
	elif scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		# The playtest's collapsed table: with scrolling on, the ScrollContainer
		# lays _sections out at the child's own minimum width instead of the
		# plate's — the one content panel without what every sibling sets.
		_fail("horizontal scroll is not disabled on the election panel's scroll")
	var table: Control = _main._election_panel._sections.get_child(0)
	if table.size.x <= 500.0:
		_fail("the executive results table does not fill the plate width (got %.0f)" % table.size.x)
	var grid := _find_grid(_main._election_panel)
	if grid == null:
		_fail("the executive panel renders no results grid")
	else:
		print("PROBE exec: panel.x=%.0f scroll.x=%.0f sections.x=%.0f table.x=%.0f grid.x=%.0f grid.right=%.0f" % [
			_main._election_panel.size.x, scroll.size.x, _main._election_panel._sections.size.x,
			table.size.x, grid.size.x, grid.position.x + grid.size.x])
		if grid.columns != 2:
			_fail("the executive table is not party + vote share only (grid has %d columns)" % grid.columns)
	if not _find_bars(_main._election_panel).is_empty():
		_fail("the executive table renders seat bars although the office allocates no seats")


func _run_national_text() -> void:
	# Dismiss it the way the Continue button does, and run on to June 2029.
	var clock: Node = _main.get_node("Clock")
	_main._election_panel.hide()
	clock.paused = false
	_advance(clock, TARGET_MONTHS - EXEC_MONTHS)

	var ns = _main._state.player()

	if ns.last_election.is_empty():
		_fail("no legislative election had resolved by month %d (clock at %d-%d)" % [TARGET_MONTHS, clock.year, clock.month])
		_finish()
		return
	if ns.last_ep_election.is_empty():
		_fail("no EP election had resolved alongside the national one (clock at %d-%d)" % [clock.year, clock.month])

	if not clock.paused:
		_fail("the clock did not pause when the election panel opened")
	if _main._election_panel == null or not _main._election_panel.visible:
		_fail("the election panel is not visible after a legislative election")
		_finish()
		return

	var text := _collect_text(_main._election_panel)

	if not text.contains("%d" % ns.last_election["incumbent_seats"]):
		_fail("panel text does not mention the incumbent's seat count (%d): %s" % [ns.last_election["incumbent_seats"], text])

	var vote_pct := "%.1f%%" % (float(ns.last_election["incumbent_vote_share"]) * 100.0)
	if not text.contains(vote_pct):
		_fail("panel text does not mention the incumbent's vote share (%s): %s" % [vote_pct, text])

	if not text.contains("European Parliament"):
		_fail("panel text does not mention the European Parliament result: %s" % text)

	var attribution: Array = ns.last_election["attribution"]
	if attribution.is_empty():
		_fail("national result carries no attribution")
	else:
		var issue_label: String = OpinionK.ISSUE_LABEL[attribution[0]["issue"]]
		if not text.contains(issue_label):
			_fail("panel text does not name the top issue '%s': %s" % [issue_label, text])

	# A legislative election cannot end a presidency, so this panel must name the
	# government that came out of it and must always offer Continue.
	var pm_name: String = _main._loader.person_name(ns.pm_person_id)
	if not text.contains(pm_name):
		_fail("panel text does not name the head of government ('%s'): %s" % [pm_name, text])

	var has_continue := false
	for child in _main._election_panel._footer.get_children():
		if child is Button and child.text == "Continue":
			has_continue = true
	if ns.in_government and not has_continue:
		_fail("won the election but the panel offers no Continue button")
	if not ns.in_government and has_continue:
		_fail("lost the election but the panel still offers Continue")


func _check_national_geometry() -> void:
	var scroll := _find_scroll(_main._election_panel)
	if scroll == null:
		_fail("the election panel has no ScrollContainer")
	elif scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		_fail("horizontal scroll is not disabled on the election panel's scroll")
	var table: Control = _main._election_panel._sections.get_child(0)
	if table.size.x <= 500.0:
		_fail("the results table does not fill the plate width (got %.0f)" % table.size.x)

	# The national table keeps its seats column, and each party holding seats
	# gets a bar under the grid — the readout the playtest expected and the code
	# never had. The EP table on the same panel adds its own bars on top.
	var ns = _main._state.player()
	var grid := _find_grid(_main._election_panel)
	if grid == null:
		_fail("the results panel renders no results grid")
	elif grid.columns != 3:
		_fail("the national table lost its seats column (grid has %d columns)" % grid.columns)
	var bars := _find_bars(_main._election_panel)
	if bars.size() < ns.last_election["seats"].size():
		_fail("the national table renders fewer seat bars than parties with seats (%d bars, %d parties)" % [bars.size(), ns.last_election["seats"].size()])
	var heaviest := 0.0
	for bar in bars:
		heaviest = maxf(heaviest, bar.value)
	if heaviest <= 0.0:
		_fail("every seat bar reads zero")


## Advance whole months, stopping early if an election pauses the clock.
func _advance(clock: Node, months: int) -> void:
	# V2.9: a DECISION arriving also pauses the clock now -- that used to be the
	# election's alone, and this loop's early return is how an arrival stalled
	# the drive at March 2027 with an empty panel read as its result. The player
	# the loop pretends to be answers what lands on the desk and carries on; the
	# pause that ends the drive is the one no answer exists for (the election).
	var Events := load("res://src/sim/events.gd")
	var ns = _main._state.player()
	for _month in range(months):
		for _d in range(31):
			clock.advance_one_day()
			if clock.paused:
				if Events.is_pending(ns) and not Events.pending_event(ns, _main._loader).choices.is_empty():
					Events.choose(_main._state, _main._loader, String(Events.pending_event(ns, _main._loader).choices[0]["id"]))
					clock.paused = false
					continue
				return


func _collect_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


func _find_scroll(panel) -> ScrollContainer:
	for node in _descendants(panel):
		if node is ScrollContainer:
			return node
	return null


func _find_grid(panel) -> GridContainer:
	for node in _descendants(panel):
		if node is GridContainer:
			return node
	return null


func _find_bars(panel) -> Array:
	var out: Array = []
	for node in _descendants(panel):
		if node is ProgressBar:
			out.append(node)
	return out


func _descendants(node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_descendants(child))
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	_done = true
	if _failures.is_empty():
		print("test_election_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
