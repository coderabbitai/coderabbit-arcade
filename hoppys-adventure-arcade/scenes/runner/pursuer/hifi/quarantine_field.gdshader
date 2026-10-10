shader_type spatial;
// The QUARANTINE containment field the pursuer drops over a caught Hoppy: additive red light, so
// the bars glow and the faint wall reads as a see-through field. Vertex colour carries each
// part's brightness; a scan band climbs the field on `clock`, which the visual ticks (it pauses).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.3, 0.24, 1.0);
uniform float energy = 1.0;
uniform float clock = 0.0;
varying float height;
void vertex() {
	height = VERTEX.y;
}
void fragment() {
	float band = 1.0 - smoothstep(0.0, 0.09, abs(fract(height * 0.8 - clock * 0.7) - 0.5));
	ALBEDO = tint.rgb * COLOR.rgb * energy * (1.0 + 1.6 * band);
}
