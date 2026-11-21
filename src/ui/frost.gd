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
## How it blurs is backdrop.gd's method, measured on the Compatibility renderer the game
## runs: `hint_screen_texture` with `filter_linear_mipmap` gives the screen at lower
## resolutions for free, the mip near log2(radius) is a box blur of that radius, and nine
## taps spread over it hide the mip's blocks. The three panes never overlap and popovers
## are opaque, so the frame's one screen copy serves all three (no BackBufferCopy).
##
## Glass off (UiTheme.glass(), the "Glass" setting): hidden, so nothing reads the screen and
## the pane's theme gives it PANE_SOLID. Re-read on every theme change, which is what a
## settings change triggers (UiTheme.rebuild).

const UiTheme = preload("res://src/ui/ui_theme.gd")

## The blur radius in DESIGN pixels: about 30 at 1080p, which scales to 40 at 1440p (the
## spec's two numbers) because the shader converts it to the window's physical pixels.
const BLUR_PX := 30.0

const CODE := """shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float blur_px;
uniform float gain;
uniform float design_h;

void fragment() {
	float radius = blur_px * (1.0 / SCREEN_PIXEL_SIZE.y) / design_h;
	float lod = max(log2(radius) - 0.5, 0.0);
	vec2 px = SCREEN_PIXEL_SIZE * radius * 0.5;
	vec3 sum = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			sum += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px, lod).rgb;
		}
	}
	// The mask's alpha is the pane's shape, corners antialiased.
	COLOR = vec4(sum / 9.0 * gain, COLOR.a);
}
"""

static var _material: ShaderMaterial

## The mask: the pane's own stylebox, filled white, no border, no shadow. Kept on the node,
## not built in _draw(): a StyleBox local to _draw is freed before the renderer draws it.
var _mask: StyleBoxFlat


static func material_for_panes() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("blur_px", BLUR_PX)
		_material.set_shader_parameter("gain", UiTheme.PANE_BACKDROP_GAIN)
		_material.set_shader_parameter("design_h", float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))
	return _material


func _init() -> void:
	name = "Frost"
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
