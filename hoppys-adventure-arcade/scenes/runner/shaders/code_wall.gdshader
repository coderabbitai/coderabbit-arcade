shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform float scroll = 0.0;
uniform float clock = 0.0;
uniform float intensity = 0.25;
// Local long axis: Z for corridor PlaneMeshes, X for front-facing QuadMeshes.
uniform vec3 horizontal_axis = vec3(0.0, 0.0, 1.0);
varying vec3 world;
varying float surface_horizontal;
void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface_horizontal = dot(VERTEX, horizontal_axis);
}
void fragment() {
	float column = mod(floor((surface_horizontal - scroll) * 2.0), 192.0);
	float seed = fract(sin(column * 12.9898) * 43758.5453);
	vec2 p = vec2((surface_horizontal-scroll)*2.0, world.y*2.5 + clock*(0.4+seed));
	float glyph = mod(abs(column * 7.0 + floor(p.y) * 13.0), 63.0) + 1.0;
	vec2 tile = vec2(mod(glyph, 8.0), floor(glyph/8.0));
	float ink = texture(atlas, (tile + fract(p))/8.0).a;
	float scan = 0.8 + 0.2 * sin(world.y*110.0);
	float fade = 1.0-smoothstep(22.0, 88.0, -world.z);
	ALBEDO = vec3(0.018, 0.033, 0.05) + vec3(0.388,0.976,0.698)*ink*intensity*scan*fade*(0.3+seed*0.7);
}
