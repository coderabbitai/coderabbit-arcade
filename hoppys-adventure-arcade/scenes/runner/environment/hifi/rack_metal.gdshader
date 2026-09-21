shader_type spatial;
render_mode cull_back;
uniform bool module_mode = false;
uniform float bend = 0.0;
uniform float bend_start = 6.0;
uniform float clock = 0.0;
uniform float frame_metallic : hint_range(0.0, 0.35) = 0.28;
uniform vec4 base_tint : source_color = vec4(0.263, 0.329, 0.392, 1.0);
uniform float baked_gain = 0.85;
uniform float rim_gain = 0.10;
uniform float ceiling_gain = 0.60;
varying float overhead;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap_anisotropic, repeat_enable;
// The corridor submits each module's yaw, origin, and its inverse rotation scalars.
// No matrix inversions per vertex, including instanced draws.
vec3 yaw_rotate(vec3 v, float c, float s) {
	return vec3(c*v.x + s*v.z, v.y, -s*v.x + c*v.z);
}
void vertex() {
	overhead = step(6.1, VERTEX.y);
	float source_z = VERTEX.z;
	if (module_mode) { source_z += INSTANCE_CUSTOM.x; }
	float local_yaw = -atan(2.0*bend*max(0.0, -source_z-bend_start));
	float c = cos(local_yaw);
	float s = sin(local_yaw);
	// Rotate the full tangent frame at the vertex, then undo the CPU instance yaw.
	NORMAL = yaw_rotate(NORMAL, c, s);
	TANGENT = yaw_rotate(TANGENT, c, s);
	BINORMAL = yaw_rotate(BINORMAL, c, s);
	if (module_mode) {
		NORMAL = yaw_rotate(NORMAL, INSTANCE_CUSTOM.z, -INSTANCE_CUSTOM.w);
		TANGENT = yaw_rotate(TANGENT, INSTANCE_CUSTOM.z, -INSTANCE_CUSTOM.w);
		BINORMAL = yaw_rotate(BINORMAL, INSTANCE_CUSTOM.z, -INSTANCE_CUSTOM.w);
	}
	if (module_mode) {
		vec3 p = VERTEX + vec3(0.0, 0.0, INSTANCE_CUSTOM.x);
		float d = max(0.0, -p.z - bend_start);
		p.x += bend * d * d;
		p -= vec3(INSTANCE_CUSTOM.y, 0.0, INSTANCE_CUSTOM.x);
		VERTEX = vec3(INSTANCE_CUSTOM.z*p.x - INSTANCE_CUSTOM.w*p.z, p.y, INSTANCE_CUSTOM.w*p.x + INSTANCE_CUSTOM.z*p.z);
	} else {
		float d = max(0.0, -VERTEX.z - bend_start);
		VERTEX.x += bend * d * d;
	}
}
uniform sampler2D circuit_map : filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
	float inset = mix(0.62, 1.0, clamp(COLOR.r / 0.263, 0.0, 1.0));
	float bevel = UV2.x;
	float ao = UV2.y * inset;
	vec3 plating = texture(albedo_map, UV).rgb;
	ALBEDO = base_tint.rgb * plating * inset;
	METALLIC = frame_metallic;
	ROUGHNESS = texture(roughness_map, UV).r;
	NORMAL_MAP = texture(normal_map, UV).rgb;
	NORMAL_MAP_DEPTH = 0.45;
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	float overhead_attenuation = mix(1.0, ceiling_gain, overhead);
	// Low-energy baked bounce reveals solid surfaces independently of Compatibility ambient.
	vec3 baked = base_tint.rgb * plating * baked_gain * ao * (0.75 + bevel*1.5);
	vec3 accent = vec3(0.388,0.976,0.698);
	vec3 detail = accent * (COLOR.a + texture(circuit_map, UV).r * 0.035) * (0.85+0.15*sin(clock*3.14));
	// Tray light bars retain their masked output; only metal fill and rim are attenuated.
	EMISSION = (baked + accent*rim*rim_gain*ao) * overhead_attenuation + detail;
}
