extends RefCounted

## The chart kit's style and scale (V5.2-0a): the palette every mark draws in, the
## line height, and the round-number scale. Its own file so the mark controls
## (chart_line, chart_bars, chart_stack) and the builders (chart_kit) share one
## copy without preloading each other.

const Num = preload("res://src/ui/num.gd")

## The categorical slots, in a FIXED order that is never cycled: the dataviz
## default's dark steps. Validated against HULL (#171B1E), the surface every chart
## sits on, with the skill's validate_palette.js --mode dark: every check passes
## (worst adjacent CVD dE 8.4, normal-vision dE 19.3, all >= 3:1). A single series
## takes slot 1. Not the accent (that is "you are here") and never a STATUS tone
## (a series is identity, not good or bad news).
const SERIES: Array[Color] = [
	Color("#3987e5"), Color("#d95926"), Color("#199e70"), Color("#c98500"),
	Color("#d55181"), Color("#008300"), Color("#9085e9"), Color("#e66767"),
]

## A line chart's height in px at text size 100 %, the axis band included (the
## method's anti-pattern: a container whose height leaves the axis labels out).
const HEIGHT := 120.0
const SWATCH := 10.0


## A clean, padded range for `lo`..`hi`: rounded out to a 1-2-2.5-5 step so the
## ticks land on round numbers, never zero-width (a flat series still has a scale).
static func nice_range(lo: float, hi: float, include_zero: bool) -> Vector2:
	if include_zero:
		lo = minf(lo, 0.0)
		hi = maxf(hi, 0.0)
	if hi - lo < 1e-9:
		var pad := maxf(absf(hi) * 0.1, 1.0)
		lo -= pad
		hi += pad
	var step := _nice_step((hi - lo) / 3.0)
	return Vector2(floorf(lo / step) * step, ceilf(hi / step) * step)


## About `count` round ticks inside `range`, both ends included when they are round.
static func ticks(range: Vector2, count := 3) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	var step := _nice_step((range.y - range.x) / float(count))
	var v := ceilf(range.x / step - 1e-9) * step
	while v <= range.y + step * 1e-6:
		out.append(0.0 if absf(v) < step * 1e-6 else v)
		v += step
	return out


static func _nice_step(raw: float) -> float:
	if raw <= 0.0:
		return 1.0
	var mag := pow(10.0, floorf(log(raw) / log(10.0)))
	var n := raw / mag
	for nice in [1.0, 2.0, 2.5, 5.0, 10.0]:
		if n <= nice + 1e-9:
			return nice * mag
	return 10.0 * mag


## A figure as the charts print it: whole numbers from 100 up, one decimal below.
static func figure(value: float) -> String:
	return Num.f(value, 0 if absf(value) >= 100.0 else 1)
