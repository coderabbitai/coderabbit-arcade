shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform float clock = 0.0;
varying float particle_age;
void vertex() {
	particle_age = INSTANCE_CUSTOM.y;
}
void fragment() {
	vec2 aa = max(fwidth(UV), vec2(0.002));
	vec2 p = abs(UV - vec2(0.5));
	float horizontal = (1.0 - smoothstep(0.30 - aa.x, 0.30 + aa.x, p.x)) * (1.0 - smoothstep(0.045 - aa.y, 0.045 + aa.y, p.y));
	float vertical = (1.0 - smoothstep(0.045 - aa.x, 0.045 + aa.x, p.x)) * (1.0 - smoothstep(0.32 - aa.y, 0.32 + aa.y, p.y));
	float tail = (1.0 - smoothstep(0.02, 0.07 + aa.x, p.x)) * smoothstep(0.0, 0.3, UV.y) * (1.0 - smoothstep(0.5, 0.95, UV.y));
	ALBEDO = vec3(1.0, 0.077, 0.047) * 1.2;
	float life_fade = smoothstep(0.0, 0.12, particle_age) * (1.0 - smoothstep(0.6, 1.0, particle_age));
	ALPHA = life_fade * max(max(horizontal, vertical), tail * 0.5) * (0.7 + 0.1 * sin(clock * 6.0));
}
