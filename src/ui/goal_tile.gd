extends Button

## One goal on the Bills tab -- V5.3 screen 4, the goal panel: a caption ("Deficit") over its
## figure as it stands ("5.05 %"). A toggle in the panel's group: the picked one is the goal the
## list below ranks every measure against (goal_panel.gd). It owns nothing; the panel builds it.

const UiTheme = preload("res://src/ui/ui_theme.gd")

## The goal this tile stands for: "deficit", "unemployment", "bloc:<id>" or "field:<a pledge's field>".
var goal := ""


func _init(goal_id: String, caption: String, figure: String, tip: String) -> void:
	goal = goal_id
	toggle_mode = true
	tooltip_text = tip
	custom_minimum_size = Vector2(112.0 * UiTheme.text_scale(), 58.0 * UiTheme.text_scale())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 8)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)
	var caption_label := Label.new()
	caption_label.text = caption
	caption_label.theme_type_variation = UiTheme.CAPTION
	caption_label.clip_text = true
	caption_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(caption_label)
	var figure_label := Label.new()
	figure_label.text = figure
	figure_label.theme_type_variation = UiTheme.FIGURE
	figure_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(figure_label)
