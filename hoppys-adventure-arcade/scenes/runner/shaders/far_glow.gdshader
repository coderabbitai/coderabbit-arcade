shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
uniform mat4 bend_frame = mat4(1.0);
uniform float bend = 0.0;
uniform float bend_start = 6.0;
uniform vec4 color : source_color = vec4(0.388,0.976,0.698,0.3);
uniform float clock = 0.0;
uniform float opacity = 1.0;
uniform float arena = 1.0;
void vertex() {
	vec3 before = (inverse(bend_frame) * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = max(0.0, -before.z - bend_start);
	// Convert the world-X offset to local space, including rotated wall planes.
	VERTEX += (inverse(MODEL_MATRIX) * bend_frame * vec4(bend * d * d, 0.0, 0.0, 0.0)).xyz;
}
void fragment() {
	float radial = pow(max(0.0, 1.0-length(UV*2.0-1.0)), 3.0);
	ALBEDO = color.rgb;
	ALPHA = radial*color.a*opacity*arena*(0.96+0.04*sin(clock*1.57));
}
