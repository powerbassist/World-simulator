extends SceneTree

## Headless test: godot --headless --script res://tests/test_polling_panel.gd
## Non-zero exit on any failure.
##
## The S5 done-when condition nobody else covers: displayed poll numbers differ
## from the true values by a bounded, random amount that changes between polls —
## while the simulation itself stays free of randomness, which is what keeps the
## budget projection provably exact.
##
## Driven a frame at a time through MainLoop's _process, because a Control that is
## not inside the scene tree has not had _ready() run, so everything it builds is
## null. See docs/engine-decision.md.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Economy = preload("res://src/sim/economy.gd")
const Budget = preload("res://src/sim/budget.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const PollingPanel = preload("res://src/ui/polling_panel.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")
const K = preload("res://src/sim/opinion_constants.gd")

const POLLS := 120

var _failures: Array[String] = []
var _state
var _panel
var _frame := 0


func _init() -> void:
	var loader := DataLoader.new()
	loader.load_all()
	if not loader.errors.is_empty():
		_failures.append("data did not load cleanly: %s" % [loader.errors])
		_finish()
		return

	_state = GameState.new_game(loader, "FRA")
	if not _state.errors.is_empty():
		_failures.append("new_game reported %s" % [_state.errors])
		_finish()
		return

	# The noise checks are pure and need no scene tree.
	_check_bounded()
	_check_changes_between_polls()
	_check_deterministic()
	_check_unbiased()

	_panel = PollingPanel.new()
	root.add_child(_panel)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		1:
			_setup_panel()
		2:
			_check_panel_shows_noised_values()
			_check_countdown_names_the_chamber_clock()
		3:
			_check_panel_holds_still_within_a_month()
			_finish()
	return false


# --- The noise function ------------------------------------------------------

## Bounded: no displayed figure is ever further from the truth than the stated
## margin of error.
func _check_bounded() -> void:
	var truth := 47.3
	for id in range(POLLS):
		for bloc in K.BLOC_KEYS:
			var shown := PollNoise.displayed(id, bloc, truth)
			if absf(shown - truth) > PollNoise.NOISE_MAX_PCT + 1.0e-9:
				_fail("poll %d, %s: displayed %.4f against a true %.4f, outside the ±%.1f margin" % [
					id, bloc, shown, truth, PollNoise.NOISE_MAX_PCT
				])
				return

	# And the clamp holds at the ends of the scale, where a raw offset would push
	# a figure outside 0-100.
	for id in range(POLLS):
		if PollNoise.displayed(id, "workers", 0.5) < 0.0 or PollNoise.displayed(id, "workers", 99.5) > 100.0:
			_fail("poll %d: a displayed figure escaped 0-100 near the ends of the scale" % id)
			return


## Random: the same bloc reads differently from one poll to the next, rather than
## carrying a fixed per-bloc bias that a player could learn and subtract.
func _check_changes_between_polls() -> void:
	for bloc in K.BLOC_KEYS:
		var seen := {}
		for id in range(POLLS):
			seen[snappedf(PollNoise.offset(id, bloc), 0.01)] = true
		if seen.size() < POLLS / 2:
			_fail("%s: only %d distinct offsets over %d polls — the noise barely moves" % [
				bloc, seen.size(), POLLS
			])

	# Blocs must not all move together either, or the noise is one number wearing
	# six hats and the bloc ordering on screen would never change.
	var identical := 0
	for id in range(POLLS):
		if absf(PollNoise.offset(id, "workers") - PollNoise.offset(id, "students")) < 1.0e-6:
			identical += 1
	if identical > 1:
		_fail("workers and students drew the same offset in %d of %d polls" % [identical, POLLS])


## Deterministic: the same question about the same poll always gets the same
## answer. This is what keeps S5 compatible with a simulation that contains no
## RNG at all, and what makes the figures survive S9's save and reload.
func _check_deterministic() -> void:
	for id in range(POLLS):
		for bloc in K.BLOC_KEYS:
			var first := PollNoise.displayed(id, bloc, 51.7)
			var second := PollNoise.displayed(id, bloc, 51.7)
			if first != second:
				_fail("poll %d, %s: two calls returned %.6f and %.6f" % [id, bloc, first, second])
				return


## Unbiased: over many polls the error averages out, so a player reading the
## trend is not being systematically lied to.
func _check_unbiased() -> void:
	for bloc in K.BLOC_KEYS:
		var total := 0.0
		for id in range(POLLS):
			total += PollNoise.offset(id, bloc)
		var mean := total / float(POLLS)
		if absf(mean) > 0.6:
			_fail("%s: mean poll error over %d polls is %+.3f points, not centred on zero" % [
				bloc, POLLS, mean
			])


# --- The panel ---------------------------------------------------------------

func _setup_panel() -> void:
	# A few months so approval is somewhere other than its starting value.	Budget.commit(_state, {"spending_pct_gdp": {"pensions": 11.0}})
	for _i in range(6):
		Economy.tick_month(_state)
		Budget.tick_month(_state)
		Opinion.tick_month(_state)
		_state.month += 1
		if _state.month > 12:
			_state.month = 1
			_state.year += 1

	_panel.setup(_state)
	_panel.show()
	_panel._refresh()


## Every figure on screen is the true one plus this poll's error — never the true
## one, and never a figure from a different poll.
## B3 (playtest 2026-09-16): the top bar counts the executive clock, this panel
## the assembly's -- both correct, so each now NAMES its clock and the two
## countdowns stop reading as a contradiction. Without a loader (main.gd's first
## setup passes only state) the generic "assembly" wording ships.
func _check_countdown_names_the_chamber_clock() -> void:
	var Trends := load("res://src/ui/trends.gd")
	var text: String = _panel._election_countdown.text
	if not text.begins_with("Next assembly election: "):
		_fail("B3: the countdown label reads '%s', expected the 'Next assembly election: ...' form" % text)
		return

	# The count after the label must still be this panel's own assembly arithmetic
	# expressed through the shared Trends.months_text query.
	var ns = _state.player()
	var months: int = (int(ns.next_election_year) - _state.year) * 12 + (int(ns.next_election_month) - _state.month)
	var expected := "Next assembly election: %s" % Trends.months_text(months)
	if text != expected:
		_fail("B3: countdown reads '%s', expected '%s' (assembly months %d)" % [text, expected, months])


func _check_panel_shows_noised_values() -> void:
	var ns = _state.player()
	var id := PollNoise.poll_id(_state.year, _state.month)

	for bloc in K.BLOC_KEYS:
		var shown_text: String = _bloc_cell(bloc, 2)
		if shown_text.is_empty():
			_fail("%s row is blank after refresh" % bloc)
			return
		var shown := float(shown_text.trim_suffix("%"))
		var truth := float(ns.bloc_approval[bloc])
		var expected := PollNoise.displayed(id, bloc, truth)
		if absf(shown - snappedf(expected, 1.0)) > 1.0e-6:
			_fail("%s shows %.2f, expected this poll's %.2f (true %.2f)" % [bloc, shown, expected, truth])

	if _first_issue_text().is_empty():
		_fail("the top-issues list did not populate")

	# The panel is read-only: rendering must not have touched the simulation.
	if absf(float(ns.bloc_approval["pensioners"]) - float(_state.player().bloc_approval["pensioners"])) > 0.0:
		_fail("the panel mutated live state while rendering")


## Repainting inside the same month must not re-roll. A poll is a published
## figure, not a fresh sample every frame.
func _check_panel_holds_still_within_a_month() -> void:
	var before := {}
	for bloc in K.BLOC_KEYS:
		before[bloc] = _bloc_cell(bloc, 2)

	_panel._refresh()
	_panel._refresh()

	for bloc in K.BLOC_KEYS:
		if _bloc_cell(bloc, 2) != before[bloc]:
			_fail("%s changed from %s to %s on a repaint within the same month" % [
				bloc, before[bloc], _bloc_cell(bloc, 2)
			])
			return

	# And the next month's poll is a different poll.
	var id := PollNoise.poll_id(_state.year, _state.month)
	var moved := 0
	for bloc in K.BLOC_KEYS:
		if absf(PollNoise.offset(id, bloc) - PollNoise.offset(id + 1, bloc)) > 0.05:
			moved += 1
	if moved == 0:
		_fail("no bloc's poll error changed between consecutive months")


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_polling_panel: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)


## V2.1b. Both tables are PanelKit.ledger() grids rebuilt on every refresh rather
## than the retained Label pairs this test used to reach through `_bloc_rows` and
## `_issue_rows`, so the figures are read back out of the grid by the caption in
## their own first column. Read by text on purpose: what this file asserts is what
## the player is shown, and a lookup by index would pass on a table whose rows had
## silently reordered.
func _bloc_cell(bloc: String, column: int) -> String:
	var wanted: String = K.BLOC_LABEL[bloc]
	for grid in _grids(_panel):
		var columns: int = grid.columns
		var cells: Array = grid.get_children()
		for i in range(0, cells.size(), columns):
			if cells[i] is Label and cells[i].text == wanted:
				return (cells[i + column] as Label).text
	return ""


func _first_issue_text() -> String:
	var grids := _grids(_panel)
	if grids.size() < 2:
		return ""
	var last: GridContainer = grids[grids.size() - 1]
	return (last.get_child(0) as Label).text if last.get_child_count() > 0 else ""


func _grids(node: Node) -> Array:
	var out: Array = []
	if node is GridContainer:
		out.append(node)
	for child in node.get_children():
		out.append_array(_grids(child))
	return out
