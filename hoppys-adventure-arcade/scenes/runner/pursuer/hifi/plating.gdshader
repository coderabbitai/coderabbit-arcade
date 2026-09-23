shader_type spatial;
render_mode cull_back;
uniform sampler2D plating : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normals : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic;
uniform vec4 diff_marks[11];
uniform float clock = 0.0;
uniform float threat = 0.0;
uniform float lens = 0.0;
uniform float flash = 0.0;
uniform float glyph_enabled = 1.0;
varying float front_face;
void vertex() {
	// Per-vertex front-panel tag, not MultiMesh instance colors.
	front_face = COLOR.r;
}
float aa_rect(vec2 uv, vec4 rect, vec2 aa) {
	vec2 enter = smoothstep(rect.xy - aa, rect.xy + aa, uv);
	vec2 leave = 1.0 - smoothstep(rect.zw - aa, rect.zw + aa, uv);
	return enter.x * enter.y * leave.x * leave.y;
}
void fragment() {
	vec2 uv = UV;
	vec2 aa = clamp(fwidth(uv), vec2(0.001), vec2(0.02));
	vec3 metal = texture(plating, uv).rgb * 2.2 + vec3(0.055, 0.070, 0.08);
	NORMAL_MAP = texture(normals, uv).rgb;
	ROUGHNESS = mix(max(texture(roughness_map, uv).r, 0.48), 0.25, lens);
	METALLIC = mix(0.30, 0.6, lens);
	float glyph = 0.0;
	vec2 depth_uv = uv + VIEW.xy * 0.008;
	for (int i = 0; i < 11; i++) {
		glyph = max(glyph, aa_rect(depth_uv, diff_marks[i], aa));
	}
	float mask = glyph * front_face * glyph_enabled;
	// Uniform-driven threat tint avoids per-frame instance-color uploads.
	metal = mix(metal, vec3(0.22, 0.026, 0.017), threat * threat * 0.55 * glyph_enabled);
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 3.0);
	float core = (1.0 - smoothstep(0.06, 0.43, abs(uv.y - 0.5))) * (1.0 - smoothstep(0.34, 0.5, abs(uv.x - 0.5)));
	float lens_energy = clamp(0.08 + core * 0.65 + fresnel * 0.18 + flash * 0.08, 0.0, 0.95);
	ALBEDO = mix(metal, mix(vec3(0.028, 0.009, 0.006), vec3(0.30, 0.047, 0.025), core), lens);
	float pulse = 1.0 + 0.2 * sin(clock * mix(3.14, 12.56, threat));
	float panel_energy = mask * 0.18 * (0.7 + threat * 0.8 + flash) * pulse;
	EMISSION = vec3(1.0, 0.077, 0.047) * mix(panel_energy, lens_energy, lens);
}
