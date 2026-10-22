extends SceneTree

## Headless test: godot --headless --script res://tests/test_load_hygiene.gd
## Non-zero exit on any failure.
##
## V5.1-a2. Two things an in-game Load left behind from the DISCARDED game, both
## seen by QA on PR #32 and both what a play gate hits the first time a player loads:
##
##   - its cards. The load path reset the announce MEMORIES and dismissed the
##     decision cards, but every other card stayed up -- "You hold Germany until
##     FEB 2029" over a loaded France game. A load drops the whole stack.
##   - its desk, put back. V5.1-c3.2: the inbox is where a decision is answered,
##     so a load that drops every row must rebuild the Decisions lane from the
##     LOADED desk -- a pending question with no row could be answered only from
##     Dispatches (Review focus 2).
##   - the ribbon's caption. The ribbon redraws only when marked dirty and
##     setup() did not mark it, so after a load it kept the old game's month while
##     the clock showed the loaded one (MAR 2026 over 20 APR 2026).
##
## Driven through main.gd's real handlers, a frame at a time (a Control is half
## dead outside the tree, docs/engine-decision.md).

const SaveManager = preload("res://src/core/save_manager.gd")

const SLOT := "__test_load_hygiene__"

var _failures: Array[String] = []
var _main
var _frame := 0
var _stale_ids: Array[String] = []
var _desk_event := ""


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		2:
			_save_in_april_then_wander_to_march()
		5:
			_premise()
			_main._on_load_requested(SLOT)
		9:
			_check_cards()
			_check_load_rebuilds_the_decisions_lane()
			_check_ribbon()
			_cleanup()
			_finish()
	return false


func _save_in_april_then_wander_to_march() -> void:
	var state = _main._state
	state.month = 4
	state.day = 20
	_main._clock.month = 4
	_main._clock.day = 20
	# One quiet question on the saved desk (not an interrupt: the lane must come
	# back for any decision, not only the one that re-raises the pause).
	var Events := load("res://src/sim/events.gd")
	var ns = state.player()
	ns.event_queue.clear()
	for ev in _main._loader.events:
		if not bool(ev.interrupt):
			_desk_event = String(ev.id)
			Events.announce(ns, ev, Events._absolute_month(4, 4), Events.region_names(ns, _main._loader))
			break
	_main._on_save_requested(SLOT)
	ns.event_queue.clear()
	# The "other game": a different month, and cards that only it would have shown.
	state.month = 3
	_main._clock.month = 3
	_main._hud.ribbon.mark_dirty()
	var stack = _main._hud.inbox
	_stale_ids.append(stack.push("Your term", "You hold Germany until FEB 2029 -- 37 months."))
	_stale_ids.append(stack.push("Firm in difficulty", "A firm of the discarded game."))
	_stale_ids.append(stack.push("A decision", "Decide.", [{"label": "Do it", "id": "x"}]))
	_stale_ids.append(stack.push("The term's programme", "Choose.", [], null, true))


func _premise() -> void:
	var title: String = _main._hud.ribbon._title.text
	if not title.begins_with("MAR"):
		_fail("premise: the ribbon shows '%s' before the load, not MAR" % title)
	if _main._hud.inbox.card_count() < _stale_ids.size():
		_fail("premise: the stack holds %d cards, fewer than the %d staged" % [_main._hud.inbox.card_count(), _stale_ids.size()])


func _check_cards() -> void:
	var stack = _main._hud.inbox
	for id in _stale_ids:
		if stack._cards.has(id):
			_fail("card '%s' of the discarded game survived the load" % id)
	if stack.card_count() > 0:
		var left: Array[String] = []
		for id in stack._cards.keys():
			left.append(String(id))
		# A loaded game may raise its own cards (a pending crisis); none of the staged ones.
		for id in left:
			if _stale_ids.has(id):
				_fail("stale card %s is still in the stack" % id)


func _check_load_rebuilds_the_decisions_lane() -> void:
	var inbox = _main._hud.inbox
	if _desk_event.is_empty():
		_fail("premise: no quiet event to stage on the saved desk")
		return
	var found := ""
	for card_id in _main._event_cards.keys():
		if String(_main._event_cards[card_id]) == _desk_event:
			found = String(card_id)
	if found.is_empty():
		_fail("the loaded desk's '%s' has no row in the inbox" % _desk_event)
	elif inbox.lane_of(found) != "decisions":
		_fail("the loaded desk's row sits in '%s', not Decisions" % inbox.lane_of(found))


func _check_ribbon() -> void:
	var title: String = _main._hud.ribbon._title.text
	if not title.begins_with("APR"):
		_fail("after loading an April save the ribbon reads '%s'" % title)


func _cleanup() -> void:
	for p in [SaveManager._path_for(SLOT), SaveManager._path_for(SLOT) + SaveManager.TEMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _fail(message: String) -> void:
	if _failures.size() < 20:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_load_hygiene: all checks passed")
		quit(0)
	else:
		for f in _failures:
			printerr(f)
		quit(1)
