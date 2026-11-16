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
##
## V5.2 b+ (gate b: "les graphiques m'aident ... pourrai s'etendre a d'autres
## panneaux"): the Budget also draws revenue against spending over the term, Society
## what the country is thinking about as bars (Regions' share-of-output bars left at
## screen 6) -- every value the history's or the state's, never computed here.

const ChartLine = preload("res://src/ui/chart_line.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const ChartHemicycle = preload("res://src/ui/chart_hemicycle.gd")
const ElectionK = preload("res://src/sim/election_constants.gd")
const ChartBars = preload("res://src/ui/chart_bars.gd")
const Opinion = preload("res://src/sim/opinion.gd")
const PollNoise = preload("res://src/ui/poll_noise.gd")

## Which of main.gd's panels each window id is.
const PANELS := {"economy": "_economy_panel", "society": "_polling_panel",
	"legislature": "_law_panel", "region": "_region_panel"}

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
			_main._windows.open("economy")
		5:
			_check_fresh()
			var console = _console()
			if console != null:
				console.run_command("skip 4")
			_main._windows.open("society")
			_main._windows.open("economy")
		9:
			_check_lines("economy", 4)
			_check_revenue_against_spending()
			_main._windows.open("society")
		11:
			_check_lines("society", 7)
			_check_society_polls()
			_check_issues()
			_main._windows.open("legislature")
		13:
			pass
		15:
			_check_seats()
			_main._windows.open("region")
		17:
			_check_regions()
			_load_a_twin()
		20:
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
	var charts := _charts("economy")
	if charts == null:
		_fail("the economy has no charts")
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


## Moved here with the Budget tab (Finances slice 5): the term's revenue against its spending, two series, ending at the
## history's last month.
func _check_revenue_against_spending() -> void:
	var charts := _charts("economy")
	var flows: Array = _all(charts, ChartLine).filter(func(c) -> bool: return c._series.size() == 2) if charts != null else []
	var last: Dictionary = _main._state.history[-1]
	if flows.size() != 1:
		_fail("the economy has no revenue-against-spending line (%d two-series charts)" % flows.size())
		return
	var ends := [float(flows[0]._series[0]["values"][-1]), float(flows[0]._series[1]["values"][-1])]
	if absf(ends[0] - float(last["total_revenue_pct_gdp"])) > 1e-9 or absf(ends[1] - float(last["total_spending_pct_gdp"])) > 1e-9:
		_fail("the revenue-against-spending line ends at %s, not the history's revenue and spending" % [ends])


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


## Society's bars are the live salience of the issues it lists, in points.
func _check_issues() -> void:
	var charts := _charts("society")
	var bars := _all(charts, ChartBars) if charts != null else []
	if bars.size() != 1:
		_fail("society has %d bar charts, not the issues' one" % bars.size())
		return
	var top: Array = Opinion.top_issues(_main._state.player(), bars[0]._rows.size())
	if top.is_empty() or absf(float(bars[0]._rows[0]["value"]) - float(top[0][1]) * 100.0) > 1e-6:
		_fail("the issues bars do not lead with the most salient issue's share: %s" % [bars[0]._rows])


## Regions: the share-of-output bars left the tab at screen 6 (Gameplay's regions brief,
## section 3's cut list): the region's own sheet and the map say where it stands.
func _check_regions() -> void:
	var charts := _charts("region")
	if charts != null and not _all(charts, ChartBars).is_empty():
		_fail("the regions tab still draws the share-of-output bars")


func _check_seats() -> void:
	# V5.3 screen 4: the chamber left the page; it is the forecast bar's hover (law_seats_tip.gd).
	if _charts("legislature") != null:
		_fail("the Bills tab still draws the chamber on the page")
	var tip: Control = preload("res://src/ui/law_seats_tip.gd").build(_main._law_panel)
	# R6: the assembly is a hemicycle, one dot per seat.
	var stacks := _all(tip, ChartHemicycle)
	if stacks.size() != 1 or not stacks[0].has_marker():
		_fail("the hovered chamber has no hemicycle with its majority marked")
		tip.free()
		return
	var ns = _main._state.player()
	# Seated left to right as an assembly sits: the economic axis plus half the
	# social one (ElectionK.SLOT_POSITION); a party keeps its colour whatever its seat.
	var slot := {}
	for party in _main._loader.parties.get(String(ns.id), []):
		slot[String(party.party_name)] = String(party.ideology_slot)
	var last := -INF
	for p in stacks[0]._parts:
		var pos: Dictionary = ElectionK.SLOT_POSITION[slot[String(p["label"])]]
		var x := float(pos["economic"]) + float(pos["social"]) / 2.0
		if x < last:
			_fail("the hemicycle seats %s right of a party further right" % p["label"])
		last = x
	var seats := 0.0
	for p in stacks[0]._parts:
		seats += float(p["value"])
	if int(seats) != int(ns.assembly_seats):
		_fail("the seat share counts %d seats, the assembly has %d" % [int(seats), ns.assembly_seats])
	tip.free()


## QA on #93: a load swaps the panel's state for another game; one with the same
## history length and term month must still redraw. A twin of this game, its
## unemployment set to 30 in every month, loaded the way main.gd does (setup() on the
## kept panel), must show 30 at the line's end.
func _load_a_twin() -> void:
	var twin = _main._state.get_script().from_dict(_main._state.to_dict())
	for entry in twin.history:
		entry["unemployment_pct"] = 30.0
	_main._economy_panel.setup(twin, _main._loader)
	_main._windows.open("economy")


func _check_the_twin() -> void:
	var charts := _charts("economy")
	for line in _all(charts, ChartLine):
		if String(line._series[0]["label"]) == "Unemployment":
			var values: PackedFloat64Array = line._series[0]["values"]
			if values.is_empty() or absf(values[-1] - 30.0) > 1e-9:
				_fail("after loading a game of the same length the Unemployment line still ends at %s, not the loaded 30" % [values[-1] if not values.is_empty() else "nothing"])
			return
	_fail("the economy has no Unemployment line after a load")


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
