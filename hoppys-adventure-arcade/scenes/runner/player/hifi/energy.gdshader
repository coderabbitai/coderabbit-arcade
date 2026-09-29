shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform vec4 color : source_color = vec4(0.47,0.88,0.77,0.22);
uniform float clock = 0.0;
uniform float mode = 0.0;
uniform float sphere_radius = 0.0;
uniform float hex_cell_size = 0.09;
varying vec3 surface_position;
void vertex() { surface_position = VERTEX; }
float hex_border(vec2 p) {
	vec2 grid = vec2(1.0, 1.7320508);
	vec2 a = mod(p / hex_cell_size, grid) - grid * 0.5;
	vec2 b = mod(p / hex_cell_size - grid * 0.5, grid) - grid * 0.5;
	vec2 q = abs(dot(a,a) < dot(b,b) ? a : b);
	float edge = (0.5 - max(q.x, dot(q, vec2(0.5, 0.8660254)))) * hex_cell_size;
	float aa = max(fwidth(edge), 0.0005);
	return 1.0 - smoothstep(0.001, 0.001 + aa, abs(edge));
}
float segment_distance(vec2 p, vec2 a, vec2 b) {
	vec2 delta = b - a;
	return length(p - a - delta * clamp(dot(p - a, delta) / dot(delta, delta), 0.0, 1.0));
}
void fragment() {
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.5);
	// UV2 is normalized for spheres and planar across each lens, independent of cloth UVs.
	vec2 uv = UV2;
	float highlight_x = 0.5 + 0.35 * sin(clock * 0.8);
	float sweep = exp(-pow((uv.x - highlight_x) / 0.045, 2.0)) * exp(-pow((uv.y - 0.62) / 0.25, 2.0));
	vec3 axis = abs(normalize(surface_position));
	vec2 panel_plane = surface_position.xy;
	if (axis.x > axis.y && axis.x > axis.z) { panel_plane = surface_position.yz; }
	else if (axis.y > axis.z) { panel_plane = surface_position.xz; }
	float hex = hex_border(panel_plane);
	ALBEDO = color.rgb * 0.85;
	METALLIC = 0.0;
	ROUGHNESS = 0.15;
	EMISSION = color.rgb * (rim * 0.2 + sweep * 0.45) * (1.0 + 0.3 * sin(clock * 4.0));
	ALPHA = color.a * (0.03 + rim * 0.5 + sweep * 0.2);
	if (sphere_radius > 0.0) {
		EMISSION = color.rgb * (rim * 0.6 + hex * 0.55) * (1.0 + 0.3 * sin(clock * 4.0));
		ALPHA = color.a * (0.04 + rim * 0.5 + hex * 0.5);
	}
	if (mode > 1.5 && mode < 2.5) {
		// Mirrored typographic braces: terminals, stems, and a central cusp.
		vec2 q = vec2(abs(UV.x - 0.5), abs(UV.y - 0.5));
		float d = segment_distance(q, vec2(0.16,0.42), vec2(0.25,0.42));
		d = min(d, segment_distance(q, vec2(0.25,0.42), vec2(0.29,0.36)));
		d = min(d, segment_distance(q, vec2(0.29,0.36), vec2(0.29,0.10)));
		d = min(d, segment_distance(q, vec2(0.29,0.10), vec2(0.38,0.0)));
		float brace = 1.0 - smoothstep(0.028, 0.045, d);
		if (brace < 0.5) { discard; }
		ALBEDO = color.rgb;
		EMISSION = color.rgb * (1.0 + 0.3 * sin(clock * 4.0));
	}
	if (mode > 2.5) {
		ALBEDO = color.rgb;
		EMISSION = color.rgb * (0.7 + 0.21 * sin(clock * 4.0));
	}
	if (mode > 1.5) { ALPHA = 1.0; }
}
