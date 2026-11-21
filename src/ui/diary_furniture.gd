extends RefCounted

## The month page's furniture around the grid (picture A, the author's pick, 2026-11-20): three
## counters over the month (waiting, next in the diary, first answer due), the legend of the
## cells' marks, and the strip under the grid that names next month's dated things so a sparse
## page still reads as the start of a year. Built by diary_grid.gd; reads nothing itself.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const PanelKit = preload("res://src/ui/panel_kit.gd")
const Strings = preload("res://src/ui/strings.gd")
const DiaryDay = preload("res://src/ui/diary_day.gd")

## How many of next month's things the strip names before "+N".
const NEXT_MAX := 4


## A toggle that opens and folds the box it returns, closed at first (the month page's
## "Book an act": the act form behind one button).
static func folded(parent: Control, label: String) -> VBoxContainer:
	var open := PanelKit.sized(Button.new())
	open.name = "BookAnAct"  # i18n: ok a node name, found by tests
	open.text = label
	PanelKit.toggle(open)
	parent.add_child(open)
	var box := VBoxContainer.new()
	box.visible = false
	parent.add_child(box)
	open.toggled.connect(func(on: bool) -> void: box.visible = on)
	return box


## The Diary open on its booking form: the form sits in the "Book an act" fold, and filled out of
## sight it is no landing (#434 pass 2 TAKE 2).
static func open_form(panel: Control, windows) -> void:
	windows.open("calendar")
	(panel.find_child("BookAnAct", true, false) as Button).button_pressed = true


## A counter: a figure over its caption, on a plate. Returns [figure, caption] to fill later.
static func counter(parent: Control, node_name: String) -> Array:
	var plate := PanelContainer.new()
	plate.name = node_name
	plate.theme_type_variation = UiTheme.PLATE
	parent.add_child(plate)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 6)
	plate.add_child(margin)
	margin.add_child(box)
	var figure := Label.new()
	figure.theme_type_variation = UiTheme.LEAD
	box.add_child(figure)
	var caption := Label.new()
	caption.theme_type_variation = UiTheme.CAPTION
	box.add_child(caption)
	return [figure, caption]


## The legend: each mark a cell can carry, drawn as the cell draws it, and its word.
static func legend(parent: Control) -> HFlowContainer:
	var row := HFlowContainer.new()
	row.name = "Legend"  # i18n: ok a node name, found by tests
	row.add_theme_constant_override("h_separation", 12)
	parent.add_child(row)
	for pair in [["tint", "bookable"], ["away", "travel"], ["booking", "booked"],
			["fixed", "fixed"], ["due", "word due"], ["deadline", "answer by"]]:  # i18n: msgid
		var item := HBoxContainer.new()
		item.add_theme_constant_override("separation", 4)
		row.add_child(item)
		var kind := String(pair[0])
		var swatch: Control = Swatch.new() if kind in ["tint", "away"] else DiaryDay.Mark.new()
		swatch.set("kind", kind)
		swatch.custom_minimum_size = Vector2(14, 14) * UiTheme.text_scale()
		item.add_child(swatch)
		var word := Label.new()
		word.theme_type_variation = UiTheme.CAPTION
		word.text = Strings.t(String(pair[1]))
		item.add_child(word)
	return row


## Next month's strip: its name, then up to NEXT_MAX of its dated things as "day text".
## `rows` the grid's [{day, text}] in date order; `month_name` already in words.
static func next_month(box: HFlowContainer, month_name: String, rows: Array) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.theme_type_variation = UiTheme.MICRO
	title.text = Strings.t("Next month")
	box.add_child(title)
	var month := Label.new()
	month.text = month_name
	box.add_child(month)
	if rows.is_empty():
		PanelKit.plain_line(box, Strings.t("nothing dated yet"), PanelKit.Tone.DIM).autowrap_mode = TextServer.AUTOWRAP_OFF
		return
	for i in mini(rows.size(), NEXT_MAX):
		var item := Label.new()
		item.text = "%d · %s" % [int(rows[i]["day"]), String(rows[i]["text"])]  # i18n: row-ok a day number and the grid's words
		item.tooltip_text = item.text
		item.mouse_filter = Control.MOUSE_FILTER_PASS
		box.add_child(item)
	if rows.size() > NEXT_MAX:
		PanelKit.plain_line(box, Strings.tn("+%d more", "+%d more", rows.size() - NEXT_MAX) % (rows.size() - NEXT_MAX), PanelKit.Tone.DIM)


## A legend's swatch for what is not a mark: the tint and the trip's band.
class Swatch extends Control:
	var kind := ""

	func _draw() -> void:
		var r := Rect2(Vector2.ONE, size - Vector2.ONE * 2.0)
		if kind == "tint":
			draw_rect(r, UiTheme.HULL)
			draw_rect(r, Color(UiTheme.accent(), 0.22))
			draw_rect(r, UiTheme.EDGE, false, 1.0)
			return
		# The trip's band, as the cell draws it.
		draw_rect(Rect2(r.position + Vector2(0, r.size.y / 4.0), Vector2(r.size.x, r.size.y / 2.0)), Color(UiTheme.accent(), 0.30))
