extends RefCounted

## The photographic grade -- V5.1a. Every photographic surface (a portrait, a scene
## backdrop, an event-art plate) is drawn through ONE material, so art generated
## over many months and by two image models reads as one library. "Agence de
## presse": a news-photo neutral, the lightest of the three grades the board
## offered -- contrast +5 %, saturation +4 %, no tint, no grain -- because the
## cheapest grade that unifies the set is the one to pay for first.
##
## A runtime material and not a re-bake of the files: 3 190 portraits and 303
## scenes would be a rewrite of every binary in the repo for a change one line
## here can retune, and the originals stay the originals.
##
## Not for the UI's own drawing (icons, the map's raster): those have a palette
## of their own and a contrast boost on them would shift the tokens.

const CONTRAST := 1.05
const SATURATION := 1.04

const CODE := """shader_type canvas_item;

uniform float contrast = 1.05;
uniform float saturation = 1.04;

void fragment() {
	// COLOR already carries the texture times the node's modulate, so a tinted
	// bust keeps its tint through the grade.
	float luma = dot(COLOR.rgb, vec3(0.2126, 0.7152, 0.0722));
	vec3 graded = mix(vec3(luma), COLOR.rgb, saturation);
	graded = (graded - 0.5) * contrast + 0.5;
	COLOR = vec4(clamp(graded, 0.0, 1.0), COLOR.a);
}
"""

static var _material: ShaderMaterial


## The one shared material.
static func material() -> ShaderMaterial:
	if _material == null:
		var shader := Shader.new()
		shader.code = CODE
		_material = ShaderMaterial.new()
		_material.shader = shader
		_material.set_shader_parameter("contrast", CONTRAST)
		_material.set_shader_parameter("saturation", SATURATION)
	return _material


## Grades a rect and hands it back, so a call site reads `parent.add_child(Grade.apply(rect))`.
static func apply(rect: TextureRect) -> TextureRect:
	rect.material = material()
	return rect


static func is_graded(rect: CanvasItem) -> bool:
	return rect.material == material()
