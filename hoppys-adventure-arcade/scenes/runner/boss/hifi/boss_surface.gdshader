shader_type spatial;
render_mode cull_back, depth_draw_opaque, ambient_light_disabled;
#define BOSS_SURFACE
#include "../../player/hifi/hoppy_surface.gdshaderinc"

uniform float dissolve : hint_range(0.0, 1.0) = 0.0;
uniform vec4 dissolve_color : source_color = vec4(1.0, 0.302, 0.239, 1.0);
uniform float dissolve_edge : hint_range(0.001, 0.2) = 0.085;
uniform float dissolve_scale : hint_range(1.0, 40.0) = 12.5;
uniform vec3 dissolve_origin = vec3(0.0);
uniform float dissolve_radius = 3.5;
uniform vec4 phase_tint : source_color = vec4(1.0);
varying vec3 boss_position;

void vertex() {
	boss_position = VERTEX;
}
float boss_hash(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}
float boss_noise(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(boss_hash(cell), boss_hash(cell + vec3(1.0, 0.0, 0.0)), f.x),
			mix(boss_hash(cell + vec3(0.0, 1.0, 0.0)), boss_hash(cell + vec3(1.0, 1.0, 0.0)), f.x), f.y),
		mix(mix(boss_hash(cell + vec3(0.0, 0.0, 1.0)), boss_hash(cell + vec3(1.0, 0.0, 1.0)), f.x),
			mix(boss_hash(cell + vec3(0.0, 1.0, 1.0)), boss_hash(cell + vec3(1.0)), f.x), f.y), f.z);
}
void fragment() {
	// Rest-space cells stay fixed while pause, hit-stop and skip drive the progress.
	float outward = clamp(length(boss_position - dissolve_origin) / max(dissolve_radius, 0.01), 0.0, 1.0);
	float noise = boss_noise(boss_position * dissolve_scale) * 0.3 + outward * 0.7;
	if (dissolve >= 1.0 || (dissolve > 0.0 && noise < dissolve)) { discard; }
	float edge = dissolve > 0.0 ? 1.0 - smoothstep(dissolve, dissolve + dissolve_edge, noise) : 0.0;
	vec3 base = texture(albedo_map, UV).rgb * albedo_color.rgb * phase_tint.rgb;
	ALBEDO = mix(base, vec3(1.0), flash * 0.7);
	vec3 orm = texture(orm_map, UV).rgb;
	AO = orm.r;
	AO_LIGHT_AFFECT = 1.0;
	ROUGHNESS = clamp(orm.g * roughness_factor, 0.08, 1.0);
	METALLIC = orm.b * metallic_factor;
	if (has_normal) {
		NORMAL_MAP = texture(normal_map, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	vec3 baked = vec3(0.0);
	if (has_emission) {
		baked = emission_color.rgb * emission_energy;
		if (has_emission_map) { baked *= texture(emission_map, UV).rgb; }
	}
	vec3 facing = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);
	float front = clamp(dot(NORMAL, facing), 0.0, 1.0);
	EMISSION = base * (ambient_fill.rgb * ambient_energy + vec3(front_fill * front)) * orm.r
		+ baked * phase_tint.rgb + vec3(flash * 0.35) + dissolve_color.rgb * edge * 2.5;
}
