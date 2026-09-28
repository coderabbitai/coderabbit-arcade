shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 color : source_color = vec4(1.0,0.302,0.239,0.35);
uniform float clock = 0.0;
uniform float progress = 0.0;
uniform bool floor_projection = false;
uniform float fill_start = 0.12;
uniform float fill_end = 0.32;
float lane_fill(vec2 uv, float countdown_progress) {
	float across = 1.0-smoothstep(0.72,1.0,abs(uv.x*2.0-1.0));
	float along = mix(0.5,1.0,smoothstep(0.0,1.0,uv.y));
	float end_fade = 1.0-smoothstep(0.9,1.0,uv.y);
	return across*along*end_fade*mix(fill_start,fill_end,countdown_progress);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float rim = pow(1.0-abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float lens = pow(max(0.0, 1.0 - p.x*p.x), 4.0);
	float scan = 0.85 + 0.15 * sin(UV.y * 80.0 - clock * 9.0);
	float mask = lens * (0.85 + rim * 0.15) * scan;
	if (floor_projection) {
		p.y = (UV.y - 0.9) * 30.0;
		float radius = length(p);
		float ring = (1.0 - smoothstep(0.025, 0.065, abs(radius - 0.79)));
		float angle = (atan(p.x, p.y) + 3.14159265) / 6.2831853;
		float countdown = step(angle, 1.0-progress);
		float ticks = step(0.65, fract(angle*24.0));
		mask = lane_fill(UV,progress) + step(0.96,abs(p.x))*0.35 + ring * (0.12 + countdown * 0.88) + ticks * (1.0 - smoothstep(0.008,0.025,abs(radius-0.96)))*0.5;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a * mask * (0.9 + 0.1 * sin(clock * 6.0));
}
