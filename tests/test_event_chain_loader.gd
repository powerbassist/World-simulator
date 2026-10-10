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

	if failures.is_empty():
		print("test_event_chain_loader: all checks passed")
		quit(0)
	else:
		for f in failures:
			printerr(f)
		quit(1)
