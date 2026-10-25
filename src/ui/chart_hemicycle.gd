extends Control

## The assembly as a hemicycle (chart_kit.gd's `hemicycle()`) -- V5.2 b+ R6, the
## author: "the Assembly as a hemicycle, one dot per seat". The seats are laid in
## concentric half-rings, each ring holding seats in proportion to its length, and
## then read left to right by angle, so each party takes one wedge in the parts'
## fixed order (the colour follows the party, as in a stack). A marker (a 0-1
## share, a majority) is a radial line at the seat it falls on. Like every chart
## in the kit the dots carry no text: the legend under it names every party with
## its seats, and a hover names the wedge under the pointer.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const ChartStyle = preload("res://src/ui/chart_style.gd")

const HEIGHT := 170.0
## The floor in the middle, as a share of the outer radius: the rows start here.
const INNER := 0.38
const PAD := 6.0

var _parts: Array = []
var _unit := ""
var _markers: Array = []
var _places := -1
var _colors: Array = ChartStyle.SERIES
var _seats := PackedVector2Array()
var _owners: Array[int] = []


func setup(parts: Array, opts := {}) -> void:
	_parts = parts
	_unit = String(opts.get("unit", ""))
	_markers = opts.get("markers", [opts["marker"]] if opts.has("marker") else [])
	_places = int(opts.get("places", -1))
	_colors = opts.get("colors", ChartStyle.SERIES)
	_owners = owners(parts)
	_seats = seats(_owners.size())
	custom_minimum_size = Vector2(0.0, HEIGHT * UiTheme.text_scale())
	mouse_filter = Control.MOUSE_FILTER_PASS
	queue_redraw()


## `n` seats in the upper half of the unit disc (y up is negative, as on screen),
## ordered left to right by angle, ties inner ring first. The ring count grows
## with the square root of the seats so a dot stays about as wide as a ring is
## deep; each ring takes its share by length (largest remainder, so the total is
## exactly `n`).
static func seats(n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	if n <= 0:
		return out
	var rows := ring_count(n)
	var radii: Array[float] = []
	var total := 0.0
	for i in rows:
		var r := 0.7 if rows == 1 else INNER + (0.94 - INNER) * float(i) / float(rows - 1)
		radii.append(r)
		total += r
	var counts: Array[int] = []
	var rest: Array = []
	var given := 0
	for i in rows:
		var exact := float(n) * radii[i] / total
		counts.append(floori(exact))
		given += counts[i]
		rest.append([exact - floorf(exact), i])
	rest.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] > b[1]))
	for k in n - given:
		counts[int(rest[k][1])] += 1
	var placed: Array = []  # [angle, ring, point]
	for i in rows:
		for k in counts[i]:
			var angle := PI / 2.0 if counts[i] == 1 else PI * (1.0 - float(k) / float(counts[i] - 1))
			placed.append([angle, i, Vector2(cos(angle), -sin(angle)) * radii[i]])
	placed.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	for p in placed:
		out.append(p[2])
	return out


## The rings for `n` seats: grows with the square root so a dot stays about as
## wide as a ring is deep.
static func ring_count(n: int) -> int:
	return clampi(ceili(sqrt(float(n)) / 2.0), 1, 16)


## The part each seat belongs to, in order: the first part's seats first.
static func owners(parts: Array) -> Array[int]:
	var out: Array[int] = []
	for i in parts.size():
		for k in maxi(roundi(float(parts[i]["value"])), 0):
			out.append(i)
	return out


func has_marker() -> bool:
	return not _markers.is_empty()


func seat_count() -> int:
	return _seats.size()


func _radius() -> float:
	return maxf(minf(size.x / 2.0, size.y - PAD) - PAD, 1.0)


func _center() -> Vector2:
	return Vector2(size.x / 2.0, PAD + _radius())


func _draw() -> void:
	if _seats.is_empty():
		return
	var radius := _radius()
	var center := _center()
	var rows := ring_count(_seats.size())
	var ring := (0.94 - INNER) * radius / maxf(float(rows - 1), 1.0)
	var dot := clampf(ring * 0.42, 1.2, 6.0)
	for i in _seats.size():
		draw_circle(center + _seats[i] * radius, dot, _colors[mini(_owners[i], _colors.size() - 1)])
	for share in _markers:
		var at := clampi(int(ceil(float(share) * _seats.size())) - 1, 0, _seats.size() - 1)
		var dir := _seats[at].normalized()
		draw_line(center + dir * radius * (INNER - 0.08), center + dir * radius, UiTheme.TEXT, 1.0)


func _get_tooltip(at: Vector2) -> String:
	if _seats.is_empty():
		return ""
	var local := (at - _center()) / _radius()
	if local.y > 0.05 or local.length() > 1.05 or local.length() < INNER - 0.08:
		return ""
	# The nearest dot, not the nearest angle: at a wedge's edge two rings' seats
	# at one angle belong to two parties.
	var nearest := 0
	for i in _seats.size():
		if _seats[i].distance_squared_to(local) < _seats[nearest].distance_squared_to(local):
			nearest = i
	var p: Dictionary = _parts[_owners[nearest]]
	return "%s  %s%s" % [String(p["label"]), ChartStyle.figure(float(p["value"]), _places), _unit]  # i18n: row-ok chart data, the caller passes shown text
