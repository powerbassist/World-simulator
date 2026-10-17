extends SceneTree

## V4.9a. Measures the menu -> game boot stage by stage, through the SAME
## boot_stages.gd the loading screen drives, and prints each stage's cost
## beside the weight BootStages.STAGES gives it -- the bar's fill is those
## weights, so this is the instrument that keeps the bar honest. Copy the
## measured column back into STAGES when a stage drifts.
##
## The menu is up first, as in play: it has already compiled the scripts it
## shares with the game (the map, the state), so the "scene" stage measures
## what is left, not a cold compile.
##
##   godot --path . --script res://tools/boot_stages_probe.gd            (windowed, the real number)
##   godot --headless --path . --script res://tools/boot_stages_probe.gd (headless, no draw cost)

const BootStages = preload("res://src/ui/boot_stages.gd")

## Work per frame, the loading screen's own (loading_screen.gd BUDGET_USEC).
const BUDGET_USEC := 50_000

var _menu: Node
var _boot
var _frame := 0
var _frames_booting := 0
var _t0 := 0


func _init() -> void:
	_menu = load("res://src/ui/menu.tscn").instantiate()
	root.add_child(_menu)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_t0 = Time.get_ticks_usec()
		_boot = BootStages.new("FRA", "", "")
		return false
	if _boot == null:
		return false
	if not _boot.ready_to_enter():
		_boot.step(BUDGET_USEC)
		_frames_booting += 1
		return false
	var t := Time.get_ticks_usec()
	_menu.queue_free()
	root.add_child(_boot.game)
	_boot.record_enter(Time.get_ticks_usec() - t)
	_report()
	return true


func _report() -> void:
	var wall_ms := (Time.get_ticks_usec() - _t0) / 1000.0
	var measured_total := 0.0
	var weight_total := 0.0
	for s in BootStages.STAGES:
		measured_total += float(_boot.timings.get(s["id"], 0)) / 1000.0
		weight_total += float(s["ms"])
	print("stage      measured ms   share   weight ms   share")
	for s in BootStages.STAGES:
		var ms := float(_boot.timings.get(s["id"], 0)) / 1000.0
		print("%-9s %12.0f %6.1f%% %11d %6.1f%%" % [
			s["id"], ms, 100.0 * ms / maxf(measured_total, 1.0),
			int(s["ms"]), 100.0 * float(s["ms"]) / weight_total])
	print("sum of stages %.0f ms, wall %.0f ms over %d boot frames" % [
		measured_total, wall_ms, _frames_booting])
