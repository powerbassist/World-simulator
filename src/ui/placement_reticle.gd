extends Control

## The attention reticle at the cursor while a placement is armed. It is its own
## node because the map's full redraw is ~73 ms at the opening fit: the reticle
## stayed put until a zoom redrew the map, and following the mouse by redrawing the
## map would have cost a frame per move. A child re-records only itself. It follows
## the viewport's motion events in `_input` (not the map's own handler, which a panel
## over the pointer would swallow).
##
## A STATUS tone, the same one that marks a cluster with something waiting (V2.1c's
## rule: one visual language for "we are waiting on you"), not the nation's accent.

const UiTheme = preload("res://src/ui/ui_theme.gd")

## Where the last draw put it, for the test.
var drawn_at := Vector2.ZERO
var _at := Vector2.ZERO


func _init() -> void:
	name = "Reticle"  # i18n: ok
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	set_process_input(false)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	set_process_input(visible)
	if visible:
		_at = get_local_mouse_position()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_at = (event as InputEventMouseMotion).position - global_position
		queue_redraw()


func _draw() -> void:
	drawn_at = _at
	draw_arc(_at, 14.0, 0.0, TAU, 32, UiTheme.WARN, 1.5)
	draw_line(_at - Vector2(20, 0), _at + Vector2(20, 0), UiTheme.WARN, 1.0)
	draw_line(_at - Vector2(0, 20), _at + Vector2(0, 20), UiTheme.WARN, 1.0)
