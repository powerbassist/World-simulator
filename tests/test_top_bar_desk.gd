extends SceneTree

## Headless test: godot --headless --script res://tests/test_top_bar_desk.gd
## Non-zero exit on any failure.
##
## V4.4 T7: the desk figure on the top bar -- the interim V4.8 obligation. The
## assertions are the ones that can fail silently:
##
##   - the EMPTY desk reads a clear state, never a confident zero (V1.6d's
##     em-dash discipline), and the figure is VISIBLE while clear -- the
##     programme figure hides when empty on purpose; the desk must not;
##   - the count is the QUEUE's size, and the worst severity is the queue's MAX
##     -- a hand-written "worst event" or a head-only read would both pass a
##     count check and lie about severity;
##   - the tooltip names a critical outright, and counts majors/minors when the
##     worst is lower;
##   - the brass mark keys on the same queue read the figure does (the strip and
##     the mark cannot disagree about whether something is on the desk).
##
## The bar is built the way main.gd builds it (the script, _ready and all), not
## torn off a scene: a Control outside the tree has not run _ready() and
## everything it builds is null -- docs/engine-decision.md's gotcha, so the bar
## joins the root and a frame passes before anything is read.

const DataLoader = preload("res://src/core/data_loader.gd")
const GameState = preload("res://src/core/game_state.gd")
const Events = preload("res://src/sim/events.gd")
const Pending = preload("res://src/ui/pending.gd")

## Named rather than picked off the loader by property: this test is about the
## STRIP, not about which crises the content fields -- it needs one event per
## severity, and the shipped book carries each. A rename fails loudly here and
## the fix is one word.
const SEV1 := "procurement_scandal"
const SEV2 := "emergency_budget_demand"
const SEV3 := "blackout_night"

var _failures: Array[String] = []
var _loader
var _bar
var _frame := 0


func _init() -> void:
	_loader = DataLoader.new()
	_loader.load_all()
	if not _loader.errors.is_empty():
		_fail("data did not load cleanly: %s" % [_loader.errors])
		_finish()
		return
	_bar = load("res://src/ui/top_bar.gd").new()
	root.add_child(_bar)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false  # let the bar's _ready() run
	if _failures.is_empty() and _bar._figure_values.is_empty():
		_fail("the bar built no figures -- _ready() never ran")
		_finish()
		return false
	_run()
	_finish()
	return false


func _run() -> void:
	var state = GameState.new_game(_loader, "FRA")
	var ns = state.player()

	# THE CLEAR STATE. The figure exists, is visible, says the desk is clear and
	# never prints a count for an empty register.
	_bar.refresh(state, null, _loader)
	var value = _bar._figure_values.get("desk")
	if value == null:
		_fail("the bar has no desk figure")
		return
	if not value.get_parent().visible:
		_fail("the desk figure hides when the desk is clear -- an empty desk is a reading, not an absence")
	if value.text.is_empty():
		_fail("the desk figure's clear state is an empty string")
	elif value.text.contains("pending") or value.text.contains("0"):
		_fail("the clear desk reads '%s' -- a count or a zero, where the state is nothing pending" % value.text)
	elif not value.text.contains("clear"):
		_fail("the clear desk reads '%s' -- it should say so" % value.text)

	# THE COUNT IS THE QUEUE'S. Two entries: one minor, one critical. The count
	# must be the register's size and the tooltip must name the WORST, not the
	# head, the first announced, or any other accidental answer.
	_announce(state, _event(SEV1))
	_announce(state, _event(SEV3))
	_bar.refresh(state, null, _loader)
	if ns.event_queue.size() != 2:
		_fail("the staging left %d entries, expected both" % ns.event_queue.size())
		return
	if String(value.text) != "2 pending":
		_fail("two entries read '%s', expected the queue's own count" % value.text)
	var tip := String(value.tooltip_text)
	if not tip.contains("critical"):
		_fail("a critical on the desk and the tooltip says '%s' -- the worst severity must be named outright" % tip)

	# Answering the critical leaves one minor: the tooltip drops to the count
	# form, and no major line may remain.
	Events.answer(state, _loader, SEV3, _default_choice_id(SEV3))
	_bar.refresh(state, null, _loader)
	if String(value.text) != "1 pending":
		_fail("one entry reads '%s', expected 1 pending" % value.text)
	tip = String(value.tooltip_text)
	if not tip.contains("minor") or tip.contains("major") or tip.contains("critical"):
		_fail("one minor on the desk and the tooltip says '%s' -- expected the count-by-severity form" % tip)

	# One major beside the minor: both counted, worst named as the count.
	_announce(state, _event(SEV2))
	_bar.refresh(state, null, _loader)
	tip = String(value.tooltip_text)
	if not (tip.contains("1 major") and tip.contains("1 minor")):
		_fail("a major and a minor on the desk and the tooltip says '%s'" % tip)

	# THE MARK AND THE STRIP AGREE. Something on the desk: the events window is
	# pending. Desk cleared: it is not.
	var ids: Array = Pending.window_ids(state, _loader)
	if not ids.has("events"):
		_fail("a loaded desk and pending.gd names no events window: %s" % [ids])
	Events.answer(state, _loader, SEV2, _default_choice_id(SEV2))
	Events.answer(state, _loader, SEV1, _default_choice_id(SEV1))
	_bar.refresh(state, null, _loader)
	if Events.is_pending(ns):
		_fail("the desk did not clear after every entry was answered")
	ids = Pending.window_ids(state, _loader)
	if ids.has("events"):
		_fail("a clear desk and pending.gd still marks the events window")


func _announce(state, ev) -> void:
	var ns = state.player()
	Events.announce(
		ns, ev,
		Events._absolute_month(int(state.year), int(state.month)),
		{})
	# The stub region map is legal here: none of the three staging events is
	# sited, and the sited pair's place keys are pinned in test_events.gd.


func _event(id: String):
	var ev = Events.event_by_id(_loader, id)
	if ev == null:
		_fail("the staging event '%s' is not in the content" % id)
	return ev


func _default_choice_id(id: String) -> String:
	var ev = _event(id)
	if ev == null:
		return ""
	return String(ev.default_choice().get("id", ""))


func _fail(msg: String) -> void:
	_failures.append(msg)


func _finish() -> void:
	if _failures.is_empty():
		print("test_top_bar_desk: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL: %s" % f)
		quit(1)
