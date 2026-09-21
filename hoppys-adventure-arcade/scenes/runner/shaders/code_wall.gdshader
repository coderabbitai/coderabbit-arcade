shader_type spatial;
render_mode cull_disabled;
uniform mat4 bend_frame = mat4(1.0);
uniform float bend = 0.0;
uniform float bend_start = 6.0;
uniform sampler2D atlas : filter_nearest, repeat_disable;
uniform float lateral_scroll = 0.0;
uniform float scroll = 0.0;
uniform float clock = 0.0;
uniform float intensity = 0.25;
// Opt-in corridor bezel spacing. Shared boss/pickup users have no gap.
uniform float panel_period = 0.0;
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
	// A slower second glyph plane shifts with viewing angle behind the front glass.
	// 0.75 preserves the exact 96 m wrap (192 columns become 144).
	vec2 rear = p*0.75 + vec2(VIEW.x, VIEW.y)*0.18 + vec2(0.0, clock*0.09);
	float rear_glyph = mod(abs(column*11.0+floor(rear.y)*17.0),63.0)+1.0;
	vec2 rear_tile = vec2(mod(rear_glyph,8.0),floor(rear_glyph/8.0));
	float back_ink = texture(atlas,(rear_tile+fract(rear))/8.0).a;
	float panel_mask = 1.0;
	if (panel_period > 0.0) {
		float panel_u = fract((surface_horizontal-scroll)/panel_period);
		panel_mask = smoothstep(0.02,0.07,panel_u) * (1.0-smoothstep(0.93,0.98,panel_u));
	}
	float glass_rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
	float scan = 0.8 + 0.2 * sin(world.y*110.0);
	float fade = 1.0-smoothstep(22.0, 88.0, -world.z);
	ALBEDO = vec3(0.018,0.033,0.05);
	METALLIC = 0.65;
	ROUGHNESS = 0.28;
	EMISSION = vec3(0.388,0.976,0.698) * ((ink+back_ink*0.15)*intensity*scan*(0.3+seed*0.7)+glass_rim*0.025)*fade*panel_mask;
}
