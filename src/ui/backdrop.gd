extends RefCounted

## The modal backdrop -- the author's pick of 2026-11-13: when a modal is up, the world
## behind it is slightly darkened AND blurred ("a pop up slightly darken and blur
## background"), the lighter of the two strengths he was shown (4 px, 30 %).
##
## ONE shared material, in the way Grade is one material: screen_stack.add() puts it
## on the dim of every modal it hosts, so the term result, the pause menu, a confirm
## card, a phone call and an audience all get it from the same line, and a panel
## sets neither the blur nor the dim (both are the two tokens below).
##
## A LIVE screen-texture shader and not a snapshot taken when the modal opens. A scene
## holds the clock, so a snapshot would hold still too, but it would also need a
## viewport read-back (a stall the game has no other reason to pay) and would go
## stale under a modal that animates (a fade, a card sliding in below it). The live
## sample costs one full-viewport copy and nine taps only while a modal is up; the
## numbers are in the PR (tools/frame_probe.gd, alone).
##
## How it blurs: `hint_screen_texture` with `filter_linear_mipmap` gives the screen
## at lower resolutions for free; sampling a mip near log2(radius) is a box blur of
## that radius, and nine taps spread over that radius smooth the mip's blockiness.
## The project runs the Compatibility renderer, which is the reason the mips are
## relied on (a two-pass kernel would need a SubViewport per modal).

const UiTheme = preload("res://src/ui/ui_theme.gd")

## The two tokens: the dim is the theme's INK at 30 %, the blur 4 px (the lighter of the
## two strengths the author was shown). They live here and not in ui_theme.gd because
## that file is at the size ratchet's 300-line ceiling and this is their one reader; a
## panel never sets either.
const BLUR_PX := 4.0
const DIM := Color(UiTheme.INK.r, UiTheme.INK.g, UiTheme.INK.b, 0.30)

const CODE := """shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float blur_px;
uniform vec4 tint : source_color;
// The project's design height: blur_px is in design pixels, so a 1440p window blurs as
// much of the picture as a 1080p one (SCREEN_PIXEL_SIZE is physical pixels).
uniform float design_h;

void fragment() {
	// The mip whose texel is about the blur radius; the taps are spread over the
	// same radius so the mip's blocks average out instead of showing.
	float radius = blur_px * (1.0 / SCREEN_PIXEL_SIZE.y) / design_h;
	float lod = max(log2(radius) - 0.5, 0.0);
	vec2 px = SCREEN_PIXEL_SIZE * radius * 0.5;
	vec3 sum = vec3(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			sum += textureLod(screen_tex, SCREEN_UV + vec2(float(x), float(y)) * px, lod).rgb;
		}
	}
	vec3 blurred = sum / 9.0;
	// COLOR.a is the rect's own alpha (its modulate), so a fade-in of the modal still fades.
	COLOR = vec4(mix(blurred, tint.rgb, tint.a), COLOR.a);
}
"""

static var _material: ShaderMaterial


## The one shared material, its uniforms the two tokens above.
static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("blur_px", BLUR_PX)
		_material.set_shader_parameter("tint", DIM)
		_material.set_shader_parameter("design_h", float(ProjectSettings.get_setting("display/window/size/viewport_height", 1080)))
	return _material


## Dresses a full-rect rect as a backdrop and hands it back, so a call site reads
## `host.add_child(Backdrop.apply(rect))`. Found again by its material (is_applied), not by
## name: the engine renames a second node of the same name.
static func apply(rect: ColorRect) -> ColorRect:
	rect.material = material()
	return rect


## A fresh copy of the viewport at this point of the draw order, to sit right before a backdrop. A
## screen-reading shader reuses the first copy of the frame, so without it a modal over a modal would
## paint the world as it was BEFORE the lower one (QA's R1: the lower modal vanished).
static func fresh_copy() -> BackBufferCopy:
	var copy := BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	copy.visible = false
	return copy


static func is_applied(rect: CanvasItem) -> bool:
	return rect.material == material()
