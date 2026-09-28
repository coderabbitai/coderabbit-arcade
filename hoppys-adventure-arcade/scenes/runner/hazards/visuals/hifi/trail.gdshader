shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;
uniform vec4 accent : source_color = vec4(1.0,0.301961,0.239216,1.0);
uniform float clock = 0.0;
uniform float distance_gain = 0.0;
void fragment() {
	float edge = 1.0-smoothstep(0.08,0.5,abs(UV.x-0.5));
	float tail = smoothstep(0.0,0.8,UV.y);
	ALBEDO = accent.rgb*(0.85+distance_gain*0.25);
	ALPHA = edge*tail*(0.55+0.15*sin(clock*12.0-UV.y*5.0));
}
