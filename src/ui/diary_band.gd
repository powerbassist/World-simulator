extends RefCounted

## G3 S2, the trip band (g3-spec.md section 2): a visit's trip -- its journey out, the meeting,
## the journey home -- as ONE capsule per week row in a lane under the date. Round where the trip
## starts and ends; square with a chevron where a week ends and the trip goes on, and the next row
## starts square with the same chevron. A travel day is a rail across the capsule, the first day of
## each leg carries a plane and the leg's name ("to Berlin", "back"); the meeting day is a pill
## with the host's name. Drawn by the day cells (diary_day.gd calls draw()), not one control per
## day, so the capsule's pieces join across the grid's gap.
##
## Out of diary_grid.gd at G3 S2 (its size ratchet): the read of the trip's days moved with it.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")

## px at text size 100 %: the lane's top (under the date), the capsule's height, the meeting
## pill's inset and the chevron's half-size.
const TOP := 21.0
const HEIGHT := 22.0
const PILL_INSET := 3.0
const CHEVRON := 3.5
## A run's end: round (the trip starts or ends), square with a chevron (a row break), or joined.
const CAP := "cap"
const CHEVRON_END := "chevron"
const JOIN := "join"


## Day -> {label, left, right, leg, meeting, key} for every day a visit's trip covers (its
## journey and its meeting). `label` is the host on the run's first day and again on a Monday
## (where the band starts a row), "" elsewhere; `first` the month's first weekday, Monday 0.
## `on_before` / `on_after`: the trip on the 1st (the last day) goes on into the month before
## (after), so that end is a chevron, not a cap -- the shape follows the trip, not the page.
static func bands(trips: Array, entries: Dictionary, first: int, on_before := false, on_after := false) -> Dictionary:
	var out := {}
	var d := 1
	while d <= trips.size():
		if not on_trip(trips, d):
			d += 1
			continue
		var start := d
		var key := String(trips[d - 1]["key"])
		var label := Strings.t("Travel")
		var meeting := 0
		# Only a journey day, or a meeting with a journey beside it: an appointment the day after a
		# trip ends is not part of its band (pass 1 on #434). One trip's days only: a second trip out
		# the day after the first ends is its own band.
		while d <= trips.size() and on_trip(trips, d) and String(trips[d - 1]["key"]) == key:
			if bool(trips[d - 1]["meeting"]):
				meeting = d
				for e in entries.get(d, []):
					if String(e["mark"]) == "booking":
						label = String(e.get("short", e["text"]))
			d += 1
		var end := d - 1
		for day in range(start, d):
			var col := (first + day - 1) % 7
			var leg := ""
			if meeting == 0:
				leg = label if day == start else ""
			elif day == start and day < meeting:
				leg = Strings.t("to %s") % label
			elif day == meeting + 1:
				leg = Strings.t("back")
			out[day] = {"label": label if day == start or col == 0 else "", "key": key, "leg": leg,
				"meeting": day == meeting,
				# The trip's own start and end come first: a Monday start is round, not a row break's
				# chevron (pass 2 TAKE 1); only the month's edge, where the trip goes on, beats them.
				"left": CHEVRON_END if day == 1 and on_before else (CAP if day == start else (CHEVRON_END if col == 0 else JOIN)),
				"right": CHEVRON_END if day == trips.size() and on_after else (CAP if day == end else (CHEVRON_END if col == 6 else JOIN))}
	return out


static func on_trip(trips: Array, d: int) -> bool:
	# A journey day, or a meeting whose journey (the same act's key) lies beside it.
	var c: Dictionary = trips[d - 1]
	if bool(c["travel"]):
		return true
	for n in [d - 2, d]:
		if bool(c["meeting"]) and n >= 0 and n < trips.size() and bool(trips[n]["travel"]) and String(trips[n]["key"]) == String(c["key"]):
			return true
	return false


## Whether this month's day `at` and the neighbour month's day `there` belong to one trip.
static func goes_on(trips: Array, other: Array, at: int, there: int) -> bool:
	if trips.is_empty() or other.is_empty():
		return false
	var key := String(trips[at]["key"])
	return key != "" and String(other[there]["key"]) == key


## The trip's name on its meeting pill: the run's label, read back from its first day.
static func name_of(bands: Dictionary, d: int) -> String:
	while d > 1 and bands.has(d - 1) and String(bands[d - 1]["key"]) == String(bands[d]["key"]) and String(bands[d]["label"]) == "":  # i18n: row-ok the band's words, worded above
		d -= 1
	return String(bands[d]["label"])  # i18n: row-ok the band's words, worded above


## The pointer on one day of a trip lights every day of it, every row; leaving it, none.
static func light(key: String, on: bool, days: Control) -> void:
	for cell in days.get_children():
		if cell.get("band") and String(cell.band_key) == key and cell.band_hot != on:
			cell.band_hot = on
			cell.queue_redraw()


## The cell's piece of the capsule. `gap` the grid's separation, half of which each joined end
## reaches into so the pieces meet; `box` the cell's own StyleBoxFlat, reused per draw.
static func draw(cell: Control, box: StyleBoxFlat, gap: float) -> void:
	var s := UiTheme.text_scale()
	var y := TOP * s
	var h := HEIGHT * s
	var r := h / 2.0
	var ends := _ends(cell, gap)
	var x0 := ends.x
	var x1 := ends.y
	box.bg_color = UiTheme.CONTROL_HOVER if cell.band_hot else UiTheme.BAND
	box.border_width_left = 0
	box.border_width_right = 0
	box.border_width_top = 0
	box.border_width_bottom = 0
	box.corner_radius_top_left = int(r) if cell.band_left == CAP else 0
	box.corner_radius_bottom_left = box.corner_radius_top_left
	box.corner_radius_top_right = int(r) if cell.band_right == CAP else 0
	box.corner_radius_bottom_right = box.corner_radius_top_right
	cell.draw_style_box(box, Rect2(x0, y, x1 - x0, h))
	var mid := y + h / 2.0
	var font := cell.get_theme_default_font()
	var fs := roundi(UiTheme.SIZE_SMALL * s)
	if cell.band_left == CHEVRON_END:
		_chevron(cell, Vector2(6.0 * s, mid), s)
	if cell.band_right == CHEVRON_END:
		_chevron(cell, Vector2(cell.size.x - 6.0 * s, mid), s)
	if cell.band_meeting:
		var pill := Rect2(x0 + PILL_INSET * s, y + PILL_INSET * s * 0.5, x1 - x0 - 2.0 * PILL_INSET * s, h - PILL_INSET * s)
		box.bg_color = UiTheme.BAND_MEETING
		box.set_corner_radius_all(int(pill.size.y / 2.0))
		if cell.band_picked:
			box.set_border_width_all(2)
			box.border_color = UiTheme.accent()
		cell.draw_style_box(box, pill)
		var bold := cell.get_theme_font("font", UiTheme.LEAD)
		cell.draw_string(bold if bold != null else font, Vector2(pill.position.x + 8.0 * s, mid + font.get_ascent(fs) / 2.0 - 1.0),
			cell.band_name, HORIZONTAL_ALIGNMENT_LEFT, pill.size.x - 12.0 * s, fs, UiTheme.TEXT)
		return
	# A travel day: the leg's plane and name where a leg begins, then the rail.
	if cell.band_leg != "":
		var lead := x0 + _inset(cell.band_left, s)
		_plane(cell, Vector2(lead + 5.0 * s, mid), s)
		cell.draw_string(font, Vector2(lead + 14.0 * s, mid + font.get_ascent(fs) / 2.0 - 1.0), cell.band_leg,
			HORIZONTAL_ALIGNMENT_LEFT, maxf(x1 - lead - 18.0 * s, 1.0), fs, UiTheme.TEXT)
	var span := rail(cell, gap)
	if span != Vector2.ZERO:
		cell.draw_line(Vector2(span.x, mid), Vector2(span.y, mid), UiTheme.BAND_RAIL, 2.0)


## The rail's run across a travel day, Vector2(from, to) in the cell's x, after the leg's plane and
## name; ZERO where nothing is left to draw (a leg's name filling the day). A joined end runs it to
## the capsule's edge, so the rail is one line across the grid's gap.
static func rail(cell: Control, gap: float) -> Vector2:
	var s := UiTheme.text_scale()
	var ends := _ends(cell, gap)
	var rail_from: float = ends.x + _inset(cell.band_left, s)
	if cell.band_leg != "":
		var fs := roundi(UiTheme.SIZE_SMALL * s)
		rail_from += 14.0 * s + cell.get_theme_default_font().get_string_size(cell.band_leg, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 6.0 * s
	var rail_to: float = ends.y - _inset(cell.band_right, s)
	return Vector2(rail_from, rail_to) if rail_to > rail_from else Vector2.ZERO


## The capsule's x span in the cell: in from a round end, out by half the gap at a joined one.
static func _ends(cell: Control, gap: float) -> Vector2:
	var x0: float = 4.0 if cell.band_left == CAP else (-gap / 2.0 if cell.band_left == JOIN else 0.0)
	var x1: float = cell.size.x - (4.0 if cell.band_right == CAP else (-gap / 2.0 if cell.band_right == JOIN else 0.0))
	return Vector2(x0, x1)


static func _inset(end: String, s: float) -> float:
	return 0.0 if end == JOIN else (14.0 if end == CHEVRON_END else 6.0) * s


static func _chevron(cell: Control, at: Vector2, s: float) -> void:
	var c := CHEVRON * s
	# Points the way the trip goes on: right at a row's end, and the next row starts with the same.
	cell.draw_polyline(PackedVector2Array([at + Vector2(-c * 0.5, -c), at + Vector2(c * 0.5, 0), at + Vector2(-c * 0.5, c)]), UiTheme.TEXT_DIM, 1.5, true)


## A plane seen from above, nose to the right: the leg's mark beside its name.
static func _plane(cell: Control, at: Vector2, s: float) -> void:
	var u := 1.1 * s
	cell.draw_colored_polygon(PackedVector2Array([
		at + Vector2(5, 0) * u, at + Vector2(1, -1) * u, at + Vector2(-1, -5) * u, at + Vector2(-2.5, -5) * u,
		at + Vector2(-1, -1) * u, at + Vector2(-4, -1) * u, at + Vector2(-5, -3) * u, at + Vector2(-5.5, -3) * u,
		at + Vector2(-5, 0) * u, at + Vector2(-5.5, 3) * u, at + Vector2(-5, 3) * u, at + Vector2(-4, 1) * u,
		at + Vector2(-1, 1) * u, at + Vector2(-2.5, 5) * u, at + Vector2(-1, 5) * u, at + Vector2(1, 1) * u]), UiTheme.TEXT)
