uniform sampler2D albedo_map : source_color;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D orm_map : hint_default_white;
uniform float roughness_factor = 1.0;
uniform float metallic_factor = 0.0;
uniform sampler2D normal_map : hint_normal;
uniform float normal_scale = 1.0;
uniform bool has_normal = false;
uniform sampler2D emission_map : source_color;
uniform vec4 emission_color : source_color = vec4(0.0);
uniform float emission_energy = 1.0;
uniform bool has_emission = false;
uniform bool has_emission_map = false;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float chroma_lock : hint_range(0.0, 1.0) = 1.0;
uniform vec4 ambient_fill : source_color = vec4(1.0, 0.941176, 0.827451, 1.0);
uniform float ambient_energy = 0.34;
uniform float light_gain : hint_range(0.0, 1.0) = 0.5;
void fragment() {
	vec4 texel = texture(albedo_map, UV);
#ifdef HOPPY_GLASS
	ALPHA = albedo_color.a * texel.a;
#endif
	vec3 base = texel.rgb * albedo_color.rgb;
	// Distance-filtered cloth weave on orange fabric, absent on fur and goggles.
	float fabric = step(base.g*1.25,base.r)*step(base.b*1.3,base.g);
	vec2 weave_uv = UV*460.0;
	float resolved = 1.0-smoothstep(0.15,0.6,max(fwidth(weave_uv.x),fwidth(weave_uv.y)));
	float weave = sin(weave_uv.x*6.283)*sin(weave_uv.y*6.283);
	base *= 1.0+fabric*weave*resolved*0.055;
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
	EMISSION = base * ambient_fill.rgb * ambient_energy * orm.r + baked + vec3(flash * 0.35);
}
void light() {
	float luma = dot(LIGHT_COLOR, vec3(0.2126, 0.7152, 0.0722));
	vec3 lc = mix(LIGHT_COLOR, vec3(luma), chroma_lock) * light_gain;
	float ndl = max(dot(NORMAL, LIGHT),0.0) * 0.72 + 0.14;
	DIFFUSE_LIGHT += ndl * ATTENUATION * lc;
	vec3 halfway = normalize(LIGHT + VIEW);
	float exponent = mix(64.0, 4.0, ROUGHNESS);
	float specular = pow(max(dot(NORMAL, halfway), 0.0), exponent);
	SPECULAR_LIGHT += specular * ndl * ATTENUATION * LIGHT_COLOR * light_gain * (1.0 - ROUGHNESS) * 0.06;
}
