extends SceneTree

## Headless test: godot --headless --script res://tests/test_chart_kit.gd
## Non-zero exit on any failure.
##
## V5.2-0a, the chart kit (the author at the V5.1 gate: "i think i need graph,
## diagrams, to make data more digest"). The marks' geometry and the rules the
## dataviz method fixes: a scale that is never zero-width and lands on round
## ticks, a zero line when a sign matters, no line from fewer than two months
## (and a caption saying why), a legend only from two series, bars no thicker than
## the method's cap, a stack's 2px gaps summing to its width, at most eight parts
## (the palette's slots, the tail folded into "Others"), and a hover that names
## what is under the pointer.

const ChartKit = preload("res://src/ui/chart_kit.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")
const ChartLine = preload("res://src/ui/chart_line.gd")
const ChartBars = preload("res://src/ui/chart_bars.gd")
const ChartStack = preload("res://src/ui/chart_stack.gd")
const ChartHemicycle = preload("res://src/ui/chart_hemicycle.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

var _failures: Array[String] = []
var _frame := 0
var _box: VBoxContainer


func _init() -> void:
	var host := PanelContainer.new()
	host.size = Vector2(600, 800)
	root.add_child(host)
	UiTheme.apply(host)
	_box = VBoxContainer.new()
	_box.custom_minimum_size = Vector2(600, 0)
	host.add_child(_box)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame == 2:
		_check_nice_range()
		_check_points()
		_check_segments()
		_check_fold()
		_check_hemicycle()
		_build_charts()
		return false
	if _frame == 4:
		_check_charts()
		_finish()
		return true
	return false


func _check_nice_range() -> void:
	var flat := ChartStyle.nice_range(2.0, 2.0, false)
	if not flat.y > flat.x:
		_fail("a flat series got a zero-width range %s" % flat)
	var signed := ChartStyle.nice_range(-1.2, 3.4, true)
	if signed.x > 0.0 or signed.y < 3.4:
		_fail("a range including zero for -1.2..3.4 is %s" % signed)
	var mid := ChartStyle.nice_range(40.0, 60.0, false)
	if mid.x > 40.0 or mid.y < 60.0:
		_fail("40..60 is not inside its range %s" % mid)
	if ChartStyle.ticks(Vector2(116, 124)).size() < 3:
		_fail("116..124 drew fewer than three ticks: %s" % [ChartStyle.ticks(Vector2(116, 124))])
	for t in ChartStyle.ticks(Vector2(0, 100)):
		if fmod(t, 10.0) != 0.0:
			_fail("a tick on 0..100 is not round: %s" % t)


## V5.2 b+ R6: one dot per seat in a half-ring, every seat in the upper half and
## inside the unit radius, ordered left to right so each party takes one wedge,
## and the wedges' seat counts are the parts' values.
func _check_hemicycle() -> void:
	for n in [0, 1, 3, 31, 577, 650]:
		var pts := ChartHemicycle.seats(n)
		if pts.size() != n:
			_fail("a hemicycle of %d seats lays %d dots" % [n, pts.size()])
			continue
		for i in pts.size():
			if pts[i].y > 1e-6 or pts[i].length() > 1.0 + 1e-6:
				_fail("seat %d of %d lies outside the upper half-disc: %s" % [i, n, pts[i]])
				break
		for i in range(1, pts.size()):
			# 1e-5: the points are float32 (Vector2), and two seats on one ray differ
			# by a few 1e-9 once stored.
			if _angle(pts[i]) > _angle(pts[i - 1]) + 1e-5:
				_fail("the %d-seat hemicycle is not ordered left to right at seat %d" % [n, i])
				break
	var owners := ChartHemicycle.owners([{"label": "a", "value": 300.0}, {"label": "b", "value": 0.0}, {"label": "c", "value": 277.0}])
	if owners.size() != 577 or owners.count(0) != 300 or owners.count(1) != 0 or owners.count(2) != 277 or owners[0] != 0 or owners[-1] != 2:
		_fail("577 seats split 300 / 0 / 277 are owned %d / %d / %d" % [owners.count(0), owners.count(1), owners.count(2)])


## A seat's angle from the left end of the floor: pi on the left, 0 on the right.
func _angle(p: Vector2) -> float:
	return atan2(-p.y, p.x)


func _check_points() -> void:
	var pts := ChartLine.points(PackedFloat64Array([0.0, 10.0]), Rect2(0, 0, 100, 50), Vector2(0, 10))
	if pts.size() != 2 or not pts[0].is_equal_approx(Vector2(0, 50)) or not pts[1].is_equal_approx(Vector2(100, 0)):
		_fail("points of [0, 10] over a 100x50 plot are %s" % [pts])


func _check_segments() -> void:
	var parts := [{"label": "a", "value": 1.0}, {"label": "b", "value": 1.0}, {"label": "c", "value": 2.0}]
	var rects := ChartStack.segments(parts, 102.0)
	var widths := [rects[0].size.x, rects[1].size.x, rects[2].size.x]
	if absf(widths[0] - 24.5) > 0.01 or absf(widths[1] - 24.5) > 0.01 or absf(widths[2] - 49.0) > 0.01:
		_fail("segments of 1:1:2 over 102 px are %s, not 24.5/24.5/49 with two 2 px gaps" % [widths])
	if absf(rects[2].end.x - 102.0) > 0.01:
		_fail("the segments and gaps end at %.2f, not the bar's 102 px" % rects[2].end.x)


func _check_fold() -> void:
	var parts: Array = []
	for i in 9:
		parts.append({"label": "p%d" % i, "value": 1.0 + i})
	var folded := ChartStack.fold(parts, "Others")
	if folded.size() != 8 or String(folded[7]["label"]) != "Others" or absf(float(folded[7]["value"]) - 17.0) > 1e-9:
		_fail("nine parts folded to %d, last %s" % [folded.size(), folded[-1]])


var _empty: VBoxContainer
var _one: VBoxContainer
var _two: VBoxContainer
var _signed: VBoxContainer
var _bars: VBoxContainer
var _stack: VBoxContainer
var _spark: Control


func _build_charts() -> void:
	var months := [[2026, 1], [2026, 2], [2026, 3]]
	_empty = ChartKit.line(_box, "Empty", [{"label": "a", "values": PackedFloat64Array([5.0])}], [[2026, 1]])
	_one = ChartKit.line(_box, "One", [{"label": "a", "values": PackedFloat64Array([1.0, 2.0, 3.5])}], months, {"unit": "%"})
	_two = ChartKit.line(_box, "Two", [
		{"label": "a", "values": PackedFloat64Array([1.0, 2.0, 3.0])},
		{"label": "b", "values": PackedFloat64Array([3.0, 2.0, 1.0])}], months)
	_signed = ChartKit.line(_box, "Signed", [{"label": "g", "values": PackedFloat64Array([-1.0, 2.0])}],
		[[2026, 1], [2026, 2]], {"zero": true})
	_bars = ChartKit.bars(_box, "Bars", [{"label": "x", "value": 3.0}, {"label": "y", "value": 9.0}])
	_spark = ChartKit.spark(_box, PackedFloat64Array([1.0, 3.0, 2.0]), months)
	_stack = ChartKit.stack(_box, "Stack", [{"label": "a", "value": 1.0}, {"label": "b", "value": 3.0}], {"marker": 0.5})


func _chart(box: Node, script: Script) -> Control:
	for c in box.get_children():
		if c.get_script() == script:
			return c
	return null


func _text(box: Node) -> String:
	var out := ""
	for c in box.get_children():
		if c is Label:
			out += (c as Label).text + "\n"
	return out


func _check_charts() -> void:
	var empty := _chart(_empty, ChartLine)
	if empty == null or empty.has_line():
		_fail("one month drew a line")
	if not _text(_empty).contains("Fills in as the months pass."):
		_fail("a chart with one month does not say why it is empty: %s" % _text(_empty))
	if _one.get_node_or_null("Legend") != null:
		_fail("a single series carries a legend box")
	var legend := _two.get_node_or_null("Legend")
	if legend == null or legend.get_child_count() != 2:
		_fail("two series have no two-entry legend")
	var one := _chart(_one, ChartLine)
	var tip: String = one._get_tooltip(Vector2(one.size.x - 1.0, 10.0))
	if not tip.contains("3.5%") or not tip.contains("2026"):
		_fail("the hover at the right edge reads '%s', not the last month and 3.5%%" % tip)
	var signed := _chart(_signed, ChartLine)
	var plot: Rect2 = signed.plot_rect()
	var zy: float = signed.zero_y()
	if zy < plot.position.y or zy > plot.end.y:
		_fail("a series spanning zero has no zero line in its plot (y %.1f, plot %s)" % [zy, plot])
	var bars := _chart(_bars, ChartBars)
	for r in bars.bar_rects():
		if r.size.y > 24.0:
			_fail("a bar is %.0f px thick, past the 24 px cap" % r.size.y)
	var stack := _chart(_stack, ChartStack)
	if not stack.has_marker():
		_fail("the stack lost its marker")
	var seg_b := ChartStack.segments([{"label": "a", "value": 1.0}, {"label": "b", "value": 3.0}], stack.size.x)[1]
	if not String(stack._get_tooltip(seg_b.get_center())).begins_with("b"):
		_fail("the hover over the second segment does not name it")
	if _stack.get_node_or_null("Legend") == null:
		_fail("a stack has no legend")
	if not _spark.has_line() or _spark.size.y > 40.0:
		_fail("a sparkline drew no line or is %.0f px tall" % _spark.size.y)


func _fail(message: String) -> void:
	_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("test_chart_kit: all checks passed")
		quit(0)
		return
	for f in _failures:
		printerr("FAIL: %s" % f)
	quit(1)
