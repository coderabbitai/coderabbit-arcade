shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform float alpha = 0.18;
uniform float screen_alpha = 0.035;
uniform mat4 corridor_frame = mat4(1.0);
varying float wall_distance;
varying float depth_fade;
varying float view_depth;
void vertex() {
	// Preserve the existing billboard, but fade streaks born in the screen corridor.
	vec3 center = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	wall_distance = abs((inverse(corridor_frame)*vec4(center,1.0)).x);
	view_depth = -(VIEW_MATRIX*vec4(center,1.0)).z;
	depth_fade = 1.0-smoothstep(55.0,88.0,view_depth);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment() {
	ALBEDO = vec3(0.475,0.878,0.769);
	ALPHA = mix(alpha,screen_alpha,smoothstep(2.5,3.7,wall_distance))*depth_fade;
	ALPHA *= smoothstep(0.3,1.5,view_depth);
}
