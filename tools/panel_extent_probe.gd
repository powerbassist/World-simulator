extends SceneTree

## V2.1b step 0. Run: godot --headless --script res://tools/panel_extent_probe.gd
##
## ONE QUESTION: is `get_combined_minimum_size()` the truth about a panel?
##
## [[docs/panel-system.md]] section 7 hands V2.1b two numbers and says it is not,
## in both directions -- `economy_panel` reporting 928px for roughly 500px of
## rendered prose, `people_panel` reporting 520px and rendering about 550. This
## measures both against the panel's own drawn extent.
##
## **THE ANSWER IS THAT IT IS THE TRUTH, AND BOTH NUMBERS WERE STALE READS.** A
## panel that has never been shown has never been laid out at the width it will
## really have, so its minimum is the answer for a width nothing will draw --
## which is V2.1a's OWN step-0 finding (*the minimum-size cache lags one
## invalidation*) one level up, applied to the panel instead of to the Label. Show
## the window, let a few frames pass, and every one of the fourteen reports its
## drawn extent to the pixel.
##
## So there is no correction to make and none is shipped: V2.1a's deleted
## grow-to-the-band heuristic was right to be deleted, and the structural fix
## V2.1b's plan booked for `window_frame.gd` was written, measured against this
## table, found to change nothing, and deleted too.
##
## Measures and prints. The assertion lives in tests/test_panel_kit.gd.

const USABLE_BAND := Vector2(1840, 886)

var _main
var _frame := 0
var _cold := {}


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame < 2:
		return false

	# Cold: never shown, never fitted, never laid out at a real width. This is the
	# read tools/fold_probe.gd's table (a) takes, and it is where section 7's two
	# numbers came from.
	if _frame == 2:
		for id in _main._windows.panel_ids():
			_cold[id] = _main._windows.frame(id)._content.get_combined_minimum_size().y
		_main._nation_panel.show_nation("DEU")
		_main._windows.mark_all_dirty()
		for id in _main._windows.panel_ids():
			var frame = _main._windows.frame(id)
			frame.show()
			frame.fit_within(USABLE_BAND)
		return false

	# Warm: shown, fitted, and given several frames for the labels to re-wrap at
	# the width they were actually given.
	if _frame < 8:
		for id in _main._windows.panel_ids():
			_main._windows.frame(id).fit_within(USABLE_BAND)
		return false

	print("")
	print("=== reported minimum against drawn extent, cold and warm ===")
	print("%-14s %8s %8s %8s %8s %8s" % ["panel", "cold", "warm", "drawn", "warm-drawn", "width"])
	var wrong := 0
	var stale := 0
	for id in _main._windows.panel_ids():
		var panel: Control = _main._windows.frame(id)._content
		var warm := panel.get_combined_minimum_size().y
		var drawn := _deepest(panel, panel.global_position.y)
		if absf(warm - drawn) > 0.5:
			wrong += 1
		if absf(float(_cold[id]) - warm) > 0.5:
			stale += 1
		print("%-14s %8.0f %8.0f %8.0f %8.0f %8.0f" % [
			id, float(_cold[id]), warm, drawn, warm - drawn, panel.size.x,
		])
	print("")
	print("cold read differs from warm read: %d of %d" % [stale, _main._windows.panel_ids().size()])
	print("warm read differs from drawn:     %d of %d" % [wrong, _main._windows.panel_ids().size()])
	quit(0)
	return true


## Does not descend into a panel's OWN ScrollContainer: what is below the fold of
## an inner scroll is scrollable rather than clipped, and counting it makes every
## panel that has one look broken. The first run of this probe did count it and
## reported legislature 3070px short of itself.
func _deepest(node: Node, top: float) -> float:
	var out := 0.0
	if node is Control and node.visible:
		var c: Control = node
		out = c.global_position.y + c.size.y - top
	if node is ScrollContainer:
		return out
	for child in node.get_children():
		out = maxf(out, _deepest(child, top))
	return out
