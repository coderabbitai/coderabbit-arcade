shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 color : source_color = vec4(0.475,0.878,0.769,0.35);
uniform float clock = 0.0;
void fragment() {
	float rim = pow(1.0-abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float scan = 0.4+0.6*step(0.5, fract(UV.y*48.0-clock));
	ALBEDO = color.rgb;
	ALPHA = color.a * (0.2+rim*0.8)*scan;
}
