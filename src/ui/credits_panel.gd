extends PanelContainer

## The credits screen.
##
## Not vanity: ATTRIBUTION.md carries the World Bank (CC BY 4.0) and Natural
## Earth credit lines, and both are licence obligations that until now lived
## only in a repository file no player ever sees.
##
## The file is read at runtime rather than transcribed into a string here, so
## there is one place to edit when a source is added and no way for the two
## copies to drift apart.
##
## Built in code, like every other panel here -- see budget_panel.gd's
## placement note.

signal closed

const PanelKit = preload("res://src/ui/panel_kit.gd")
const ATTRIBUTION_PATH := "res://ATTRIBUTION.md"


func _ready() -> void:
	custom_minimum_size = Vector2(560, 360)

	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 16)
	add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	margin.add_child(root)

	PanelKit.line(root, tr("CREDITS"), PanelKit.Tone.PLAIN)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.custom_minimum_size.x = 500
	body.text = _attribution_text()
	scroll.add_child(body)

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(footer)

	var close := Button.new()
	close.text = tr("Close")
	close.pressed.connect(func():
		hide()
		closed.emit()
	)
	footer.add_child(close)


## Falls back to a hardcoded line rather than an empty panel: .md is not a
## recognised Godot resource type, so an export preset without an include
## filter for it would ship a build whose credits screen is blank, which is
## worse than one whose credits screen is terse.
func _attribution_text() -> String:
	var text := FileAccess.get_file_as_string(ATTRIBUTION_PATH)
	if text.strip_edges().is_empty():
		return "Nation economic statistics: World Bank Open Data (CC BY 4.0).\nBorder geometry: Natural Earth, public domain."
	return text
