extends Control

## One bar split into its parts (chart_kit.gd's `stack()`): part-to-whole at a
## glance, each part in its fixed categorical slot, a 2px gap of the surface between
## segments instead of a drawn border. The segments carry no text of their own --
## the legend under the bar names every part with its value -- so nothing is ever
## clipped inside a thin segment.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")

const BAR := 18.0
const GAP := 2.0
## Seven parts and an "Others": the categorical palette's eight slots, never a
## generated ninth hue.
const MAX_PARTS := 8

var _parts: Array = []
var _unit := ""
var _marker := -1.0


func setup(parts: Array, opts := {}) -> void:
	_parts = parts
	_unit = String(opts.get("unit", ""))
	_marker = float(opts.get("marker", -1.0))
	custom_minimum_size = Vector2(0.0, BAR + 8.0)
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()


## More than MAX_PARTS parts keeps the first seven and folds the rest into one.
static func fold(parts: Array, others_label: String) -> Array:
	if parts.size() <= MAX_PARTS:
		return parts
	var out: Array = parts.slice(0, MAX_PARTS - 1)
	var rest := 0.0
	for p in parts.slice(MAX_PARTS - 1):
		rest += float(p["value"])
	out.append({"label": others_label, "value": rest})
	return out


## The segments across `width`: proportional to the values, a GAP between each,
## the widths and gaps summing to `width`. A part of zero has no segment width
## but keeps its slot (and its gap is dropped), so colours never shift.
static func segments(parts: Array, width: float) -> Array[Rect2]:
	var total := 0.0
	var shown := 0
	for p in parts:
		total += maxf(float(p["value"]), 0.0)
		if float(p["value"]) > 0.0:
			shown += 1
	var room := maxf(width - GAP * maxf(float(shown - 1), 0.0), 0.0)
	var out: Array[Rect2] = []
	var x := 0.0
	for p in parts:
		var v := maxf(float(p["value"]), 0.0)
		var w := room * v / total if total > 0.0 else 0.0
		out.append(Rect2(x, 0.0, w, BAR))
		if w > 0.0:
			x += w + GAP
	return out


func _draw() -> void:
	var rects := segments(_parts, size.x)
	for i in _parts.size():
		var r: Rect2 = rects[i]
		if r.size.x > 0.0:
			draw_rect(Rect2(r.position + Vector2(0.0, 4.0), r.size), ChartStyle.SERIES[mini(i, ChartStyle.SERIES.size() - 1)])
	if _marker >= 0.0:
		var x := size.x * _marker
		draw_line(Vector2(x, 0.0), Vector2(x, BAR + 8.0), UiTheme.TEXT, 1.0)


func has_marker() -> bool:
	return _marker >= 0.0


func _get_tooltip(at: Vector2) -> String:
	var rects := segments(_parts, size.x)
	for i in _parts.size():
		var r: Rect2 = rects[i]
		if r.size.x > 0.0 and at.x >= r.position.x and at.x <= r.end.x + GAP:
			return "%s  %s%s" % [String(_parts[i]["label"]), ChartStyle.figure(float(_parts[i]["value"])), _unit]
	return ""
