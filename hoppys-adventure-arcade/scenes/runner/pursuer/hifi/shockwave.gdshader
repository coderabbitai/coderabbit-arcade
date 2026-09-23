shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back;
uniform float clock = 0.0;
uniform float opacity = 0.5;
varying float leading_edge;
void vertex() {
	// Torus lies in XZ before the node rotates it toward the camera.
	float radius = length(VERTEX.xz);
	leading_edge = smoothstep(0.725, 0.764, radius);
}
void fragment() {
	float ripple = 0.9 + 0.1 * sin(UV.x * 24.0 + clock * 8.0);
	float falloff = smoothstep(0.0, 1.0, leading_edge);
	ALBEDO = vec3(1.0, 0.077, 0.047);
	METALLIC = 0.65;
	ROUGHNESS = 0.3;
	EMISSION = ALBEDO * (0.5 + 4.0 * falloff) * ripple;
	ALPHA = opacity * (0.06 + 0.94 * falloff);
}
