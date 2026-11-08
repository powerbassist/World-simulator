extends Button

## A waiting request on a day it offers -- V5.3 b, step 6 (docs/design/v5.3-ab.md section 5, the
## author's "toujours séparé de la prise de rendez-vous"): the asker's face and the last day to
## answer, in the Diary's own cell, and a click books this day. A Button and not more of the
## cell's _draw(): the keyboard reaches it and Enter books, as the mouse does.
##
## A day the Diary refuses keeps its chip, disabled with the sim's reason, and lets the click
## through to the cell, which lists the day and why: never a dead click.

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")
const Portrait = preload("res://src/ui/portrait.gd")
const MoodBadge = preload("res://src/ui/mood_badge.gd")
const DateText = preload("res://src/ui/date_text.gd")

const FACE := Vector2(18, 24)
const HEIGHT := 28.0
const BADGE := 11.0


## `offer` is the grid's {id, person, date}; `row` audience_driver's row_of() for the request,
## {} before its first refresh (a name and no deadline, for one frame at most).
func fill(offer: Dictionary, row: Dictionary) -> void:
	var id := String(offer["id"])
	var date: Dictionary = offer["date"]
	var scale_by := UiTheme.text_scale()
	name = "Chip_%s" % id
	focus_mode = Control.FOCUS_ALL
	clip_contents = true
	custom_minimum_size.y = HEIGHT * scale_by
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := HBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 2)
	var pid := String(offer["person_id"])
	var size_face := FACE * scale_by
	var feel: Dictionary = row.get("feel", {})
	var face: Control = Portrait.framed_for(pid, size_face, MoodBadge.mood_portrait(pid, feel))
	# The asker's mood on their face, as everywhere a person asks (#222, the parent's call).
	if not feel.is_empty():
		MoodBadge.wear(face, feel, BADGE * scale_by)
	face.name = "Face"  # i18n: ok a node name, found by tests
	face.custom_minimum_size = size_face
	box.add_child(face)
	var by := Label.new()
	by.name = "By"  # i18n: ok a node name, found by tests
	by.theme_type_variation = UiTheme.CAPTION
	by.text = Strings.t("by %s") % String(row.get("by", "")) if row.has("by") else ""
	by.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	by.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(by)
	_ignore_mouse(box)
	var who := String(row.get("person", offer["person"]))
	var party := String(row.get("party", {}).get("name", ""))  # i18n: row-ok a party's shown name, from PartyChip.of
	if party != "":
		who = "%s (%s)" % [who, party]
	var wants := String(row.get("wants", ""))
	var day := DateText.day_month_year(int(date["day"]), int(date["year"]), int(date["month"]))
	var free := bool(date.get("free", true))
	disabled = not free
	# Disabled, the press goes to the cell behind it, which lists the day and why.
	mouse_filter = Control.MOUSE_FILTER_STOP if free else Control.MOUSE_FILTER_PASS
	var doing := Strings.t("Click to see them on %s.") % day if free else Strings.t(String(date.get("reason", "")))  # i18n: row-ok the sim's reason, its English the msgid
	tooltip_text = "\n".join(PackedStringArray([who, wants, Strings.t("Answer by %s") % String(row.get("by", "")), doing]))
	accessibility_name = Strings.t("Book here: %s") % who


static func _ignore_mouse(node: Node) -> void:
	for child in node.get_children():
		if child is Control:
			(child as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ignore_mouse(child)
