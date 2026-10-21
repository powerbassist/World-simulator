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
	_main._on_save_requested(SLOT)
	# The "other game": a different month, and cards that only it would have shown.
	state.month = 3
	_main._clock.month = 3
	_main._hud.ribbon.mark_dirty()
	var stack = _main._hud.message_stack
	_stale_ids.append(stack.push("Your term", "You hold Germany until FEB 2029 -- 37 months."))
	_stale_ids.append(stack.push("Firm in difficulty", "A firm of the discarded game."))
	_stale_ids.append(stack.push("A decision", "Decide.", [{"label": "Do it", "id": "x"}]))
	_stale_ids.append(stack.push("The term's programme", "Choose.", [], null, true))


func _premise() -> void:
	var title: String = _main._hud.ribbon._title.text
	if not title.begins_with("MAR"):
		_fail("premise: the ribbon shows '%s' before the load, not MAR" % title)
	if _main._hud.message_stack.card_count() < _stale_ids.size():
		_fail("premise: the stack holds %d cards, fewer than the %d staged" % [_main._hud.message_stack.card_count(), _stale_ids.size()])


func _check_cards() -> void:
	var stack = _main._hud.message_stack
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
