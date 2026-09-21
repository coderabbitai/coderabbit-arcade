shader_type spatial;
render_mode cull_disabled;
uniform float clock = 0.0;
uniform float floor_metallic : hint_range(0.0, 0.35) = 0.28;
uniform vec4 base_tint : source_color = vec4(0.263, 0.329, 0.392, 1.0);
uniform float baked_gain = 0.255;
uniform float plate_normal_depth = 0.9;
uniform float plate_rivet_radius = 0.085;
uniform vec2 plate_size = vec2(0.5, 0.75);
uniform float plate_groove_width = 0.018;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
uniform mat4 bend_frame = mat4(1.0);
uniform float bend = 0.0;
uniform float bend_start = 6.0;
uniform float scroll = 0.0;
uniform float cell = 2.0;
uniform float intensity = 0.35;
uniform float grid_strength = 0.45;
uniform float beat = 0.0;
uniform float fade_start = 22.0;
uniform float fade_end = 88.0;
uniform vec4 tint : source_color = vec4(0.388, 0.976, 0.698, 1.0);
varying vec3 world;
varying vec3 surface;
void vertex() {
	vec3 before = (inverse(bend_frame) * MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	surface = before;
	float d = max(0.0, -before.z - bend_start);
	// Convert the world-X offset to local space, including rotated wall planes.
	VERTEX += (inverse(MODEL_MATRIX) * bend_frame * vec4(bend * d * d, 0.0, 0.0, 0.0)).xyz;
	world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = vec2(surface.x, surface.z - scroll) / cell;
	vec2 edge = abs(fract(p - 0.5) - 0.5) / max(fwidth(p), vec2(0.004));
	float grid = 1.0 - clamp(min(edge.x, edge.y), 0.0, 1.0);
	float lane = 1.0 - smoothstep(abs(bend) > 0.0 ? 0.02 : 0.015, abs(bend) > 0.0 ? 0.075 : 0.055, min(abs(abs(surface.x)-1.0), abs(abs(surface.x)-3.0)));
	float fade = 1.0 - smoothstep(fade_start, fade_end, -world.z);
	vec2 metal_uv = vec2(surface.x, surface.z-scroll) * 0.5;
	vec3 response = texture(roughness_map, metal_uv).rgb;
	float wear = response.b;
	vec3 plating = texture(albedo_map, metal_uv).rgb;
	vec3 plate_normal = texture(normal_map, metal_uv).rgb;
	float seam = 1.0-smoothstep(0.012,0.032,abs(surface.x));
	// Physical plate grooves are independent of texture mip levels and the 2 m light grid.
	vec2 plate_position = vec2(surface.x + 0.125, surface.z-scroll + 0.25);
	vec2 plate_edge = abs(fract(plate_position/plate_size + 0.5)-0.5)*plate_size;
	float edge_distance = min(plate_edge.x, plate_edge.y);
	float edge_aa = max(fwidth(edge_distance), 0.002);
	float groove = 1.0-smoothstep(plate_groove_width-edge_aa, plate_groove_width+edge_aa, edge_distance);
	float bevel = (1.0-smoothstep(plate_groove_width+0.014-edge_aa, plate_groove_width+0.014+edge_aa, edge_distance))-groove;
	// Half-plate joints and corner fasteners remain visible independently of mip filtering.
	vec2 plate_local = fract(plate_position/plate_size)*plate_size;
	float sub_distance = abs(plate_local.y - plate_size.y*0.5);
	float sub_aa = max(fwidth(sub_distance), 0.002);
	float sub_seam = 1.0-smoothstep(0.009-sub_aa, 0.009+sub_aa, sub_distance);
	float sub_bevel = (1.0-smoothstep(0.023-sub_aa, 0.023+sub_aa, sub_distance))-sub_seam;
	vec2 corner_delta = min(plate_local, plate_size-plate_local)-vec2(0.11);
	float rivet_distance = length(corner_delta);
	float rivet_aa = max(fwidth(rivet_distance), 0.002);
	float rivet = 1.0-smoothstep(plate_rivet_radius-rivet_aa, plate_rivet_radius+rivet_aa, rivet_distance);
	float rivet_core = 1.0-smoothstep(plate_rivet_radius-0.022-rivet_aa, plate_rivet_radius-0.022+rivet_aa, rivet_distance);
	float rivet_rim = max(0.0, rivet-rivet_core);
	float slot_aa = max(fwidth(corner_delta.y), 0.002);
	float slot = rivet_core*(1.0-smoothstep(0.009-slot_aa, 0.009+slot_aa, abs(corner_delta.y)));
	float plate_exposure = max(0.12, 1.0-groove*0.80+bevel*0.75-sub_seam*0.70+sub_bevel*0.8-rivet_core*0.25+rivet_rim*1.2-slot*0.50);
	ALBEDO = base_tint.rgb * plating * plate_exposure;
	METALLIC = floor_metallic;
	ROUGHNESS = response.r;
	NORMAL_MAP = plate_normal;
	NORMAL_MAP_DEPTH = plate_normal_depth;
	// Packed AO and normal-derived edge exposure reveal plating without ambient reflections.
	float bevel_exposure = clamp(1.0 + (plate_normal.r - 0.5)*0.8 + (plate_normal.g - 0.5)*0.6, 0.65, 1.4);
	vec3 baked = base_tint.rgb * plating * baked_gain * response.g * bevel_exposure * plate_exposure * fade;
	EMISSION = baked + tint.rgb * (grid*grid_strength+lane*wear*0.65+seam*0.75) * intensity * (1.0+beat*0.15) * fade * (0.94+0.06*sin(clock*3.14));
}
