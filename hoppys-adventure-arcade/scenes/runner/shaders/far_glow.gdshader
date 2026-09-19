shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform vec4 color : source_color = vec4(0.388,0.976,0.698,0.3);
void fragment() {
	float radial = pow(max(0.0, 1.0-length(UV*2.0-1.0)), 3.0);
	ALBEDO = color.rgb;
	ALPHA = radial*color.a;
}
