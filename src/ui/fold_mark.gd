extends RefCounted

## A fold's chevron (the #441 RECORD, g3-spec "Borderless toggle"): right when closed, down when
## open, so a fold reads as one and never as bold text. A toggle's own look is PanelKit.toggle's;
## this adds the mark and turns it when the button is toggled.

const Icon = preload("res://src/ui/icon.gd")
const UiTheme = preload("res://src/ui/ui_theme.gd")

const ICONS := "res://assets/icons/material/"
const PX := 18


## `fold` shows the chevron for its pressed state now and after each toggle.
static func apply(fold: Button) -> void:
	show_state(fold, fold.button_pressed)
	fold.toggled.connect(func(on: bool) -> void: show_state(fold, on))


static func show_state(fold: Button, open: bool) -> void:
	fold.icon = Icon.load_icon(ICONS + ("expand_more" if open else "chevron_right") + ".svg", UiTheme.TEXT_DIM, PX)
