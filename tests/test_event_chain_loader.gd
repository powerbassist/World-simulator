extends SceneTree

## Headless test: godot --headless --script res://tests/test_event_chain_loader.gd
## Non-zero exit on any failure.
##
## V4.4's chain loader refusal: a chain target that is itself a hook event can be
## delivered twice in one tick (the armed-chain door, then the hook door -- which
## has no dedupe), so its choice effects would apply twice. Refused at LOAD.
## tests/test_events.gd already covers arming and landing; this pins the refusal.

const DataLoader = preload("res://src/core/data_loader.gd")

func _init() -> void:
	var failures: Array[String] = []

	# RED: a chain arming an event that carries on_action must be refused, naming
	# the shape (the hook door re-delivering it).
	var bad := DataLoader.new()
	bad._load_events("res://tests/fixtures/events_chain_hook_target")
	var refused := false
	for e in bad.errors:
		if e.find("loaded_hook") != -1 and e.find("re-deliver") != -1:
			refused = true
	if not refused:
		failures.append("a chain arming a hook event loaded, or was refused without naming the hook re-delivery: %s" % [bad.errors])

	# GREEN: shipped content arms only a non-hook target (deficit_ceiling_vote,
	# on_action empty), so the real book still loads clean.
	var good := DataLoader.new()
	good._load_events("res://data/events")
	if not good.errors.is_empty():
		failures.append("the shipped event book was refused: %s" % [good.errors])

	# The collision key (data_loader._load_events) carries on_action and keeps the
	# eu_member scope. Pairs sharing a subject and a gate but differing in on_action
	# (hazard vs hook), or in membership (members-only vs open), are different
	# occasions and must load; the same hook twice is still one event authored twice.
	var apart := DataLoader.new()
	apart._load_events("res://tests/fixtures/events_collision_on_action")
	if not apart.errors.is_empty():
		failures.append("events differing in on_action or eu scope were refused as one event authored twice: %s" % [apart.errors])
	if apart.events.size() != 4:
		failures.append("the on_action/eu fixture should load 4 events, loaded %d (an earlier error would show above)" % apart.events.size())

	var twin := DataLoader.new()
	twin._load_events("res://tests/fixtures/events_collision_same_action")
	var twin_refused := false
	for e in twin.errors:
		if e.find("twin_one") != -1 and e.find("twin_two") != -1 and e.find("authored twice") != -1:
			twin_refused = true
	if not twin_refused:
		failures.append("two hook events with one subject, gate and on_action were not refused as one event authored twice: %s" % [twin.errors])

	if failures.is_empty():
		print("test_event_chain_loader: all checks passed")
		quit(0)
	else:
		for f in failures:
			printerr(f)
		quit(1)
