extends Control

## G3's glass: the blurred map under a chrome pane (g3-spec.md section 3). PanelKit.pane()
## adds one as the pane's first child; it draws BEHIND its parent (show_behind_parent), so
## the order on screen is this blur, then the pane's own stylebox -- its shadow, the tint,
## the rim -- then the pane's content. Text therefore never sits on the raw map: always on
## the tint over a darkened blur.
##
## Why a child and not a material on the pane itself: a canvas material replaces every
## pixel the item draws, so the pane's rim and shadow would turn into blurred map too. This
## node draws only a mask the pane's own shape (its stylebox's corners, filled white) and
## the shader keeps the mask's alpha, so the antialiased corners survive.
##
## How it blurs is backdrop.gd's shader itself, one kernel for the modal and the panes
## (measured on the Compatibility renderer the game runs): `hint_screen_texture` with
## `filter_linear_mipmap`, the mip near log2(radius), nine taps over it; its tint, black at
## 1 - PANE_BACKDROP_GAIN, is the pane's darkening, and it keeps the mask's alpha. The three panes never overlap and popovers
## are opaque, so the frame's one screen copy serves all three (no BackBufferCopy).
##
## Glass off (UiTheme.glass(), the "Glass" setting): hidden, so nothing reads the screen and
## the pane's theme gives it PANE_SOLID. Re-read on every theme change, which is what a
## settings change triggers (UiTheme.rebuild).

const UiTheme = preload("res://src/ui/ui_theme.gd")
const Backdrop = preload("res://src/ui/backdrop.gd")

## The blur radius in DESIGN pixels: about 30 at 1080p, which scales to 40 at 1440p (the
## spec's two numbers) because the shader converts it to the window's physical pixels.
const BLUR_PX := 30.0


static var _material: ShaderMaterial

## The mask: the pane's own stylebox, filled white, no border, no shadow. Kept on the node,
## not built in _draw(): a StyleBox local to _draw is freed before the renderer draws it.
var _mask: StyleBoxFlat


static func material_for_panes() -> ShaderMaterial:
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = Backdrop.material().shader  # the one blur kernel, its own uniforms here
		_material.set_shader_parameter("blur_px", BLUR_PX)
		# The backdrop's tint mixed toward black is a gain: 1 - alpha of the blurred map is kept.
		_material.set_shader_parameter("tint", Color(0, 0, 0, 1.0 - UiTheme.PANE_BACKDROP_GAIN))
		_material.set_shader_parameter("design_h", float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))
	return _material


func _init() -> void:
	name = "Frost"  # i18n: ok a node name
	show_behind_parent = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	material = material_for_panes()


func _ready() -> void:
	(get_parent() as Control).resized.connect(queue_redraw)
	item_rect_changed.connect(queue_redraw)  # the content margins move this node, not the pane
	_restyle()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED and is_inside_tree():
		_restyle()


func _restyle() -> void:
	visible = UiTheme.glass()
	var pane := (get_parent() as Control).get_theme_stylebox("panel") as StyleBoxFlat
	_mask = StyleBoxFlat.new()
	_mask.bg_color = Color.WHITE
	if pane != null:
		for corner in 4:
			_mask.set_corner_radius(corner, pane.get_corner_radius(corner))
	queue_redraw()


## The whole of the pane, not this node's rect: a PanelContainer fits its children to its
## content area, inside the stylebox's margins, and the blur must reach the rim.
func _draw() -> void:
	draw_style_box(_mask, Rect2(-position, (get_parent() as Control).size))
