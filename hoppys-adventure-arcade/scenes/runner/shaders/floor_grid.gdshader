shader_type spatial;
render_mode unshaded, cull_disabled;
uniform float scroll = 0.0;
uniform float cell = 2.0;
uniform float intensity = 0.35;
uniform float beat = 0.0;
uniform float fade_start = 22.0;
uniform float fade_end = 88.0;
uniform vec4 tint : source_color = vec4(0.388, 0.976, 0.698, 1.0);
varying vec3 world;
void vertex() { world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = vec2(world.x, world.z - scroll) / cell;
	vec2 edge = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(0.001));
	float grid = 1.0 - clamp(min(edge.x, edge.y), 0.0, 1.0);
	float lane = 1.0 - smoothstep(0.015, 0.055, min(abs(abs(world.x)-1.0), abs(abs(world.x)-3.0)));
	float fade = 1.0 - smoothstep(fade_start, fade_end, -world.z);
	ALBEDO = vec3(0.025, 0.047, 0.07) + tint.rgb * (grid * 0.45 + lane) * intensity * (1.0 + beat * 0.15) * fade;
}
