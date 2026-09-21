shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform float clock = 0.0;
uniform float threat = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float flicker = step(0.96, fract(sin(floor(clock * 17.0) * 91.7) * 43758.5));
	// Zero channel separation: flicker modulates luminance, preserving palette hues.
	float pulse = 1.0 - flicker * (0.04 + 0.08 * clamp(threat, 0.0, 1.0));
	vec3 rgb = texture(screen_texture, uv).rgb;
	float scan = 0.82 + 0.18 * step(0.5, fract((UV.y + clock * 0.02) * 128.0));
	float roll = 1.0 - 0.35 * smoothstep(0.94, 1.0, fract(UV.y - clock * 0.15));
	float grain = fract(sin(dot(floor(UV * 256.0), vec2(12.9898,78.233)) + floor(clock * 12.0)) * 43758.5453);
	float rim = smoothstep(0.42, 0.5, max(abs(UV.x - 0.5), abs(UV.y - 0.5)));
	COLOR = vec4(rgb * pulse * scan * roll * (0.97 + grain * 0.03) + vec3(1.0,0.302,0.239) * rim * 0.07, 1.0);
}
