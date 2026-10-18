// V4.10c. The map's border lines -- map_line_mesh.gd's mesh (the vertex
// encoding is documented there). Not a material: what makes this a shader is
// that a line's colour and width must change on hover, zoom and the ground band
// WITHOUT the mesh being re-recorded, so both live in a palette the vertex reads
// by index -- row 0 the colour, row 1 the width in screen pixels (in .r) -- and
// the width becomes geometry here, half each side, over the scale.
//
// Measured (tools/frame_probe.gd, "C max" rows, one run, 1440p): every line on
// the map, outlines and roster, costs inside the run spread at max zoom (all-on
// 1.55 / 1.80 ms, roster lines off 1.51). As per-frame culled polylines the
// roster's lines alone were 0.63 ms there; unculled, 4.1. map-platform-model §11.
shader_type canvas_item;

uniform sampler2D palette : filter_nearest, repeat_disable;
// Screen pixels per degree (BASE_SCALE * zoom); map_view sets it per re-record.
uniform float px_per_deg = 12.0;

void vertex() {
	int index = int(round(COLOR.r * 255.0)) + 256 * int(round(COLOR.g * 255.0));
	float width_px = texelFetch(palette, ivec2(index, 1), 0).r;
	VERTEX += UV * (0.5 * width_px / px_per_deg);
	COLOR = texelFetch(palette, ivec2(index, 0), 0);
}
