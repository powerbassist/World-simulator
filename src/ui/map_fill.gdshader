// V4.10c, THE MATERIALS -- the project's first canvas_item shader, and on
// purpose its only one for the map's fills. It draws map_fill_mesh.gd's mesh
// (the vertex encoding is documented there) and does three named jobs.
//
// PALETTE. The fill colour is one texel per nation, read by index. A layer
// toggle, a new month or a crossfade frame rewrites 41 texels; the mesh itself
// is built once and never touched again. The texel is the colour MapLayers
// chose, alpha included, read raw (no source_color), as the vertex colour of
// the old draw_colored_polygon call was.
//
// EDGE BAND. Along each nation's 1:50m ring (coast included) the fill deepens
// toward the line: a strip whose inner edge vertex() pushes inward by
// band_px / px_per_deg, so it stays band_px wide on screen at every zoom --
// or less, where its ring is narrower than that (the cap, map_fill_mesh.gd).
//
// PATTERN. A faint diagonal hatch in the fill's alpha, in screen pixels but
// anchored to the land, so it pans with the map instead of swimming over it.
//
// Off (map_view's materials_off seam, the paired probe rows): band_px = 0 makes
// the strip zero-area, pattern_strength = 0 leaves the palette alone -- the
// picture before V4.10c.
//
// Measured (tools/frame_probe.gd, "C materials" rows, paired in one run, three
// runs, 1440p, vsync off): on minus off is -0.2 to -0.7 ms at max zoom, -0.3 to
// +0.3 at the opening fit, -0.9 to +0.5 on the drag -- signs that flip between
// runs, the probe's noise. The band and the hatch cost nothing a frame shows.
// map-platform-model.md §11.
shader_type canvas_item;

uniform sampler2D palette : filter_nearest, repeat_disable;
// Screen pixels per degree (BASE_SCALE * zoom); map_view sets it per re-record.
uniform float px_per_deg = 12.0;
// The materials: values and reasons in map_view.FILL_MATERIAL, set at setup().
// The band at the line is the fill's colour band_shade as bright and band_gain
// times as opaque, easing to nothing at the inner edge.
uniform float band_px;
// map_fill_mesh.gd's CAP_RANGE_DEG: a band vertex's alpha times this is its
// ring's cap in degrees (set with the materials, from the one constant).
uniform float cap_range_deg;
uniform float band_shade;
uniform float band_gain;
uniform float pattern_px = 1.0;
uniform float pattern_strength;

varying flat vec4 v_fill;
varying flat float v_is_band;
varying float v_across;
varying vec2 v_land_px;

void vertex() {
	int index = int(round(COLOR.r * 255.0));
	v_is_band = COLOR.b;
	v_across = COLOR.g;
	VERTEX += UV * min(band_px / px_per_deg, COLOR.a * cap_range_deg);
	v_land_px = VERTEX * px_per_deg;
	v_fill = texelFetch(palette, ivec2(index, 0), 0);
}

void fragment() {
	if (v_is_band > 0.5) {
		float t = 1.0 - clamp(v_across, 0.0, 1.0);
		COLOR = vec4(v_fill.rgb * band_shade, clamp(v_fill.a * band_gain, 0.0, 1.0) * t * t);
	} else {
		float wave = sin((v_land_px.x + v_land_px.y) * (6.2831853 / pattern_px));
		COLOR = vec4(v_fill.rgb, v_fill.a * (1.0 + pattern_strength * wave));
	}
}
