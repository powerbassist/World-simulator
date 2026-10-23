extends SceneTree

## Headless test: godot --headless --script res://tests/test_panel_charts.gd
## Non-zero exit on any failure.
##
## V5.2-0a, the charts on the five first panels, in the real game. On a new game a
## term chart has no line and says it fills in; after real months (the console's
## `skip`, WorldMonth.tick_month() itself) the Overview draws its four lines over
## the term, the Economy its three, Society the poll and the six blocs -- every
## approval point the poll published that month, never the truth -- the Budget one
## stacked share that adds up to the whole of spending, and the Legislature the
## assembly by party with the majority marked.

const ChartLine = preload("res://src/ui/chart_line.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")

## Which of main.gd's panels each window id is.
const PANELS := {"overview": "_overview_panel", "economy": "_economy_panel", "society": "_polling_panel",
	"budget": "_budget_panel", "legislature": "_law_panel"}

var _failures: Array[String] = []
var _main
var _frame := 0


func _init() -> void:
	_main = load("res://src/ui/main.tscn").instantiate()
	root.add_child(_main)


func _process(_delta: float) -> bool:
	_frame += 1
	match _frame:
		3:
			_main._windows.open("overview")
		5:
			_check_fresh()
			var console = _console()
			if console != null:
				console.run_command("skip 4")
			_main._windows.open("overview")
		7:
			_check_lines("overview", 4)
			_main._windows.open("economy")
		9:
			_check_lines("economy", 3)
			_main._windows.open("society")
		11:
			_check_lines("society", 7)
			_check_society_polls()
			_main._windows.open("budget")
		13:
			_check_budget()
			_main._windows.open("legislature")
		15:
			_check_seats()
			_load_a_twin()
		18:
			_check_the_twin()
			_finish()
			return true
	return false


func _console():
	for child in _main.get_children():
		if child.has_method("run_command"):
			return child
	_fail("the game scene has no dev console to skip months with")
	return null


func _charts(id: String) -> Node:
	var panel: Node = _main.get(PANELS[id])
	return panel.find_child("Charts", true, false) if panel != null else null


func _all(node: Node, script: Script) -> Array:
	var out: Array = []
	if node.get_script() == script:
		out.append(node)
	for child in node.get_children():
		out.append_array(_all(child, script))
	return out


func _check_fresh() -> void:
	var charts := _charts("overview")
	if charts == null:
		_fail("the overview has no charts")
		return
	if _main._state.history.size() >= 2:
		return  # a new game with history already: nothing to say about the empty case
	for line in _all(charts, ChartLine):
		if line.has_line():
			_fail("a new game drew a term line from %d month(s)" % _main._state.history.size())


func _check_lines(id: String, want: int) -> void:
	var charts := _charts(id)
	if charts == null:
		_fail("%s has no charts" % id)
		return
	var lines := _all(charts, ChartLine)
	var drawn := 0
	for line in lines:
		if line.has_line():
			drawn += 1
	if lines.size() != want or drawn != want:
		_fail("%s holds %d line charts, %d with a line, after four months (want %d)" % [id, lines.size(), drawn, want])


func _check_society_polls() -> void:
	var charts := _charts("society")
	if charts == null:
		return
	var overall: Node = _all(charts, ChartLine)[0]
	var values: PackedFloat64Array = overall._series[0]["values"]
	var entries: Array = _main._state.history.slice(_main._state.history.size() - values.size())
	for i in values.size():
		var e: Dictionary = entries[i]
		var poll := PollNoise.displayed(PollNoise.poll_id(int(e["year"]), int(e["month"])), "overall", float(e["overall_approval_pct"]))
		if absf(values[i] - poll) > 1e-9:
			_fail("society plots %.3f for %d-%d, not the poll published (%.3f)" % [values[i], e["year"], e["month"], poll])
			return


func _check_budget() -> void:
	var charts := _charts("budget")
	var stacks := _all(charts, ChartStack) if charts != null else []
	if stacks.size() != 1:
		_fail("the budget has %d stacked shares, not one" % stacks.size())
		return
	var ns = _main._state.player()
	var total := 0.0
	for p in stacks[0]._parts:
		total += float(p["value"])
	if absf(total - float(ns.total_spending_pct_gdp)) > 0.05:
		_fail("the spending parts add to %.2f %% of GDP, spending is %.2f" % [total, ns.total_spending_pct_gdp])


func _check_seats() -> void:
	var charts := _charts("legislature")
	var stacks := _all(charts, ChartStack) if charts != null else []
	if stacks.size() != 1 or not stacks[0].has_marker():
		_fail("the legislature has no seat share with its majority marked")
		return
	var ns = _main._state.player()
	var seats := 0.0
	for p in stacks[0]._parts:
		seats += float(p["value"])
	if int(seats) != int(ns.assembly_seats):
		_fail("the seat share counts %d seats, the assembly has %d" % [int(seats), ns.assembly_seats])


## QA on #93: a load swaps the panel's state for another game; one with the same
## history length and term month must still redraw. A twin of this game, its
## unemployment set to 30 in every month, loaded the way main.gd does (setup() on the
## kept panel), must show 30 at the line's end.
func _load_a_twin() -> void:
	var twin = _main._state.get_script().from_dict(_main._state.to_dict())
	for entry in twin.history:
		entry["unemployment_pct"] = 30.0
	_main._overview_panel.setup(twin, _main._loader)
	_main._windows.open("overview")


func _check_the_twin() -> void:
	var charts := _charts("overview")
	for line in _all(charts, ChartLine):
		if String(line._series[0]["label"]) == "Unemployment":
			var values: PackedFloat64Array = line._series[0]["values"]
			if values.is_empty() or absf(values[-1] - 30.0) > 1e-9:
				_fail("after loading a game of the same length the Unemployment line still ends at %s, not the loaded 30" % [values[-1] if not values.is_empty() else "nothing"])
			return
	_fail("the overview has no Unemployment line after a load")


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_panel_charts: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
