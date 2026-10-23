extends SceneTree

## Headless test: godot --headless --script res://tests/test_placement_points.gd
## Non-zero exit on any failure.
##
## The author's live gate, two placement bugs:
##   N1 -- a wind farm ordered off France (the Gulf of Lion) read `ns.nation_name`,
##   a field NationState does not have; the editor's debugger broke on it and the game
##   froze. A refused point must say "Not your ground" through the loader's name.
##   N2 -- "the target marker ... dont update when mouse moves, only when zoom moves":
##   the reticle was drawn in the map's own _draw, which a mouse move never redraws
##   (a full redraw is ~73 ms). It follows the pointer now, as its own node.

var _failures: Array[String] = []
var _main
var _frame := 0
var _cards_before := 0
var _map


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_check_a_point_in_the_sea()
			_arm_and_move(Vector2(300, 300))
		5:
			_check_reticle_at(Vector2(300, 300), "after the first move")
			_move(Vector2(640, 220))
		7:
			_check_reticle_at(Vector2(640, 220), "after a second move, with no zoom")
			_map.end_placement()
			if _map.get_node("Reticle").visible:
				_fail("the reticle stayed up after the placement ended")
			_finish()
			return true
	return false


func _action_id() -> String:
	for a in _main._loader.energy_actions:
		return String(a.id)
	return ""


func _check_a_point_in_the_sea() -> void:
	var action_id := _action_id()
	if action_id == "":
		_fail("no energy action to arm")
		return
	_main._armed_energy_action = action_id
	var before: int = _main._hud.inbox.card_count()
	_main._on_map_point_picked(4.163, 42.719)  # the Gulf of Lion
	if _main._hud.inbox.card_count() != before + 1:
		_fail("a point in the sea left no 'Not your ground' card (cards %d -> %d)" % [before, _main._hud.inbox.card_count()])


func _arm_and_move(at: Vector2) -> void:
	_map = _main._map_view
	_map.begin_placement()
	_move(at)


func _move(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	root.push_input(motion, true)


func _check_reticle_at(at: Vector2, when: String) -> void:
	var reticle = _map.get_node_or_null("Reticle")
	if reticle == null:
		_fail("the map has no placement reticle")
		return
	if not reticle.visible:
		_fail("the reticle is not shown while placing (%s)" % when)
	var want: Vector2 = at - _map.get_global_rect().position
	if reticle.drawn_at.distance_to(want) > 1.0:
		_fail("the reticle was drawn at %s, the pointer is at %s (%s)" % [reticle.drawn_at, want, when])


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_placement_points: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
