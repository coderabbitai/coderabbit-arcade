shader_type spatial;
render_mode unshaded, cull_disabled;
uniform mat4 bend_frame = mat4(1.0);
uniform float bend = 0.0;
uniform float bend_start = 6.0;
uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform float opacity = 1.0;
uniform float lateral_scroll = 0.0;
uniform float scroll = 0.0;
uniform float clock = 0.0;
uniform float intensity = 0.25;
// Local long axis: Z for corridor PlaneMeshes, X for front-facing QuadMeshes.
uniform vec3 horizontal_axis = vec3(0.0, 0.0, 1.0);
varying vec3 world;
varying float surface_horizontal;
void vertex() {
	vec3 before = (inverse(bend_frame) * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float d = max(0.0, -before.z - bend_start);
	// Convert the world-X offset to local space, including rotated wall planes.
	VERTEX += (inverse(MODEL_MATRIX) * bend_frame * vec4(bend * d * d, 0.0, 0.0, 0.0)).xyz;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_horizontal = dot(VERTEX, horizontal_axis);
}
void fragment() {
	float column = mod(floor((surface_horizontal - scroll - lateral_scroll) * 2.0), 192.0);
	float seed = fract(sin(column * 12.9898) * 43758.5453);
	vec2 p = vec2((surface_horizontal-scroll-lateral_scroll)*2.0, world.y*2.5 + clock*(0.4+seed));
	float glyph = mod(abs(column * 7.0 + floor(p.y) * 13.0), 63.0) + 1.0;
	vec2 tile = vec2(mod(glyph, 8.0), floor(glyph/8.0));
	float ink = texture(atlas, (tile + fract(p))/8.0).a;
	ink *= 1.0 - smoothstep(0.3, 1.5, length(max(fwidth(world), vec3(0.004))));
	ALPHA = opacity;
	float scan = 0.8 + 0.2 * sin(world.y*110.0);
	float fade = 1.0-smoothstep(22.0, 88.0, -world.z);
	ALBEDO = vec3(0.018, 0.033, 0.05) + vec3(0.388,0.976,0.698)*ink*intensity*scan*fade*(0.3+seed*0.7);
}
