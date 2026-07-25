extends SceneTree

## Headless test: godot --headless --script res://tests/test_election_panel.gd
## Non-zero exit on any failure.
##
## Loads the actual main scene and turns the actual clock, the same shape
## test_game_loop.gd uses, so a broken signal path between the clock, the
## election tick and the panel fails here rather than in a playtest. Driven a
## frame at a time because a Control outside the scene tree has not run
## _ready() — see docs/engine-decision.md.
##
## Runs to June 2029, France's first scheduled election (and, the same month,
## the European Parliament's) — the double-election case is the one most likely
## to break a panel written for a single result.

const OpinionK = preload("res://src/sim/opinion_constants.gd")

const TARGET_MONTHS := 41  # January 2026 to June 2029, FRA's authored schedule.

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
		_fail("main scene did not build a GameState")
		return

	var clock: Node = _main.get_node("Clock")
	for _month in range(TARGET_MONTHS):
		for _d in range(31):
			clock.advance_one_day()
			if clock.paused:
				break

	var ns = _main._state.player()
	if ns.last_election.is_empty():
		_fail("no national election had resolved by month %d (clock at %d-%d)" % [TARGET_MONTHS, clock.year, clock.month])
		return
	if ns.last_ep_election.is_empty():
		_fail("no EP election had resolved alongside the national one (clock at %d-%d)" % [clock.year, clock.month])

	if not clock.paused:
		_fail("the clock did not pause when the election panel opened")
	if _main._election_panel == null or not _main._election_panel.visible:
		_fail("the election panel is not visible after a national election")
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

	# Continue only makes sense on a win; a defeat must not offer it.
	var has_continue := false
	for child in _main._election_panel._footer.get_children():
		if child is Button and child.text == "Continue":
			has_continue = true
	if ns.in_government and not has_continue:
		_fail("won the election but the panel offers no Continue button")
	if not ns.in_government and has_continue:
		_fail("lost the election but the panel still offers Continue")


func _collect_text(node) -> String:
	var out := ""
	if node is Label or node is Button:
		out += node.text + "\n"
	for child in node.get_children():
		out += _collect_text(child)
	return out


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_election_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
