shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float clock = 0.0;
uniform float threat = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	float shift = sin(uv.y * 80.0 + clock * 13.0) * 0.006 * threat;
	vec3 rgb = texture(screen_texture, uv).rgb;
	rgb.r = texture(screen_texture, uv + vec2(shift, 0.0)).r;
	rgb.b = texture(screen_texture, uv - vec2(shift, 0.0)).b;
	float scan = 0.82 + 0.18 * step(0.5, fract((UV.y + clock * 0.02) * 128.0));
	float roll = 1.0 - 0.35 * smoothstep(0.94, 1.0, fract(UV.y - clock * 0.15));
	COLOR = vec4(rgb * scan * roll, 1.0);
}
