extends RefCounted

## G3 S3, Design's T1 on #441: ONE row grammar for an answer on the Sectors side sheet -- a
## process's ask, a plant closure, a bid, a rescue window. Its button at the left, in a cell of
## its own (a verb never sits straight in a box that cannot wrap: test_i18n_fit), and at the
## right, in the same slots for every answer, its cost, who it pleases and who it angers (a
## glyph and a word each, never the colour alone), and what follows; a LINE between answers so
## they compare. The answers of one list are one class group (PanelKit.same_class).
##
## Its own file, not PanelKit's: panel_kit.gd sits near its size cap, and this is the side
## sheet's grammar, shared by its readers (industry_progress.gd, closure_card.gd,
## sectors_decision.gd). test_panel_kit.gd fails a panel that builds the row itself.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Labels = preload("res://src/ui/labels.gd")

const SLOT_SEPARATION := 12
const GLYPH := 9.0


## The box a question's answers go in; add() rows to it.
static func list(parent: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.set_meta("answer_list", true)
	parent.add_child(box)
	return box


## A LINE under the last row of `list`.
static func rule(list: VBoxContainer) -> void:
	var line := ColorRect.new()
	line.color = UiTheme.LINE
	line.custom_minimum_size.y = 1.0
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	list.add_child(line)


## The frame of one answer under `list` -- a LINE after the one above, `button` in the first
## cell, an empty column of slots -- for an answer that fills its own slots (a counter's chips,
## its cost, its chance). One class with the list's other buttons.
static func shell(list: VBoxContainer, button: Button) -> VBoxContainer:
	if list.get_child_count() > 0:
		rule(list)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", SLOT_SEPARATION)
	row.set_meta("answer_row", true)
	list.add_child(row)
	var cell := VBoxContainer.new()
	row.add_child(cell)
	cell.add_child(button)
	var slots := VBoxContainer.new()
	slots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slots.add_theme_constant_override("separation", 2)
	row.add_child(slots)
	var buttons: Array = list.get_meta("buttons", [])
	buttons.append(button)
	list.set_meta("buttons", buttons)
	PanelKit.same_class(buttons)
	return slots


## One answer under `list`: `button` at the left, then its slots. `offsets` is bloc -> move
## (a positive move pleases); `follows` may be "". Returns the cost's Label, which is also the
## button's money_label (the tests' and the panels' contract).
static func add(list: VBoxContainer, button: Button, cost: String, offsets: Dictionary, follows := "") -> Label:
	var slots := shell(list, button)
	var money := PanelKit.plain_line(slots, cost, PanelKit.Tone.PLAIN)
	button.set_meta("money_label", money)
	_who(slots, offsets, true)
	_who(slots, offsets, false)
	if follows != "":
		PanelKit.plain_line(slots, follows)
	return money


## The two who lines in their own box, for an answer whose figures change under it (a counter's
## pick): empty it and fill it again with `fill_who`.
static func who_box(slots: Control) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	slots.add_child(box)
	return box


static func fill_who(box: Control, offsets: Dictionary) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	_who(box, offsets, true)
	_who(box, offsets, false)


## "Pleases Workers, Students." or "Angers Business.", behind its glyph; nothing when no bloc moves that way.
static func _who(slots: Control, offsets: Dictionary, up: bool) -> void:
	var names := PackedStringArray()
	for bloc in offsets:
		if (float(offsets[bloc]) > 0.0) == up and float(offsets[bloc]) != 0.0:
			names.append(Labels.bloc(String(bloc)))
	if names.is_empty():
		return
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	line.set_meta("who", "pleases" if up else "angers")
	slots.add_child(line)
	line.add_child(Glyph.new(up))
	var words := PanelKit.plain_line(line, (Strings.t("Pleases %s") if up else Strings.t("Angers %s")) % ", ".join(names))
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL


## A small triangle: up in the good tone for who an answer pleases, down in the bad one for who
## it angers. Drawn, not a font glyph: Archivo has no arrowheads to trust.
class Glyph extends Control:
	var up := true

	func _init(pointing_up: bool) -> void:
		up = pointing_up
		custom_minimum_size = Vector2(GLYPH, GLYPH) * UiTheme.text_scale()
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var points := PackedVector2Array([Vector2(0, h), Vector2(w, h), Vector2(w * 0.5, 0)]) if up \
			else PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w * 0.5, h)])
		draw_colored_polygon(points, UiTheme.GOOD if up else UiTheme.BAD)
