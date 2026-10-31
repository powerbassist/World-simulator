extends RefCounted

## The People table's heads -- V5.3-0 (b), docs/design/v5.3-0-readability.md 3.4: a
## group's fold and a column's sort, out of people_panel.gd (the size ratchet) and
## over its state (`_open`, `_sort`). The two kinds of button the panel's read-only
## rule admits; neither ever shares a row with an autowrapping label.

const PanelKit = preload("res://src/ui/panel_kit.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")
const Strings = preload("res://src/ui/strings.gd")


## A group's heading as its fold: "+" folded, "−" open, the count always shown.
## Returns whether the group is open.
static func fold(panel, key: String, text: String) -> bool:
	var open := bool(panel._open.get(key, false))
	var head := Button.new()
	head.flat = true
	head.alignment = HORIZONTAL_ALIGNMENT_LEFT
	head.theme_type_variation = UiTheme.HEADING
	head.text = ("− %s" if open else "+ %s") % text.to_upper()
	head.set_meta(panel.HEAD_META, true)
	head.tooltip_text = Strings.t("Hide") if open else Strings.t("Show")
	head.pressed.connect(func() -> void:
		panel._open[key] = not open
		panel.mark_dirty())
	panel._body.add_child(PanelKit.sized(head))
	return open


## The table's header: Name, Side and Standing sort the groups; "Wants served" is
## a caption.
static func sort_row(panel) -> void:
	var row: HBoxContainer = panel._person_line(panel._body, "", [])
	for col in [["name", Strings.t("Name"), panel.COL_NAME], ["side", Strings.t("Side"), panel.COL_SIDE], ["standing", Strings.t("Standing"), panel.COL_FIGURE]]:
		var key := String(col[0])
		var sort := Button.new()
		sort.flat = true
		sort.theme_type_variation = UiTheme.CAPTION
		sort.text = String(col[1]) if panel._sort != key else "%s ↓" % String(col[1])
		sort.alignment = HORIZONTAL_ALIGNMENT_RIGHT if key == "standing" else HORIZONTAL_ALIGNMENT_LEFT
		sort.custom_minimum_size.x = int(col[2])
		sort.tooltip_text = Strings.t("Sort by this column")
		sort.set_meta(panel.HEAD_META, true)
		sort.pressed.connect(func() -> void:
			panel._sort = key
			panel._refocus = key
			panel.mark_dirty())
		row.add_child(sort)
		# The re-sort rebuilds the table: the pressed header takes focus back.
		if panel._refocus == key:
			panel._refocus = ""
			sort.call_deferred("grab_focus")
	panel._cell(row, Strings.t("Wants served"), 0, UiTheme.CAPTION)


static func sorter(panel, ns) -> Callable:
	match panel._sort:
		"name":
			return func(a, b): return String(a.person_name).naturalnocasecmp_to(String(b.person_name)) < 0
		"side":
			return func(a, b): return panel._party_or_kind_line(ns, a).naturalnocasecmp_to(panel._party_or_kind_line(ns, b)) < 0
	return func(a, b): return float(ns.person_standing.get(a.id, 0.0)) > float(ns.person_standing.get(b.id, 0.0))
