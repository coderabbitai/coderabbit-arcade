shader_type spatial;
// Baked Blender hero props (tools/blender/props): one shared four-map atlas set for every hazard.
// Driven by the rig clock uniform only; hit flash and charge only ever brighten the baked emissive mask.
render_mode cull_back, depth_draw_opaque;
uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_atlas : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D emission_atlas : source_color, hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec4 accent : source_color = vec4(1.0,0.30,0.24,1.0);
uniform float emission_gain = 1.0;
uniform float clock = 0.0;
uniform float hit = 0.0;
uniform float charge = 0.0;
uniform float distance_gain = 0.0;
void fragment() {
	vec3 base = texture(albedo_atlas,UV).rgb;
	vec3 orm = texture(orm_atlas,UV).rgb;
	vec3 glow = texture(emission_atlas,UV).rgb;
	float mask = max(glow.r,max(glow.g,glow.b));
	ALBEDO = base;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.35;
	ROUGHNESS = orm.g;
	METALLIC = orm.b;
	NORMAL_MAP = texture(normal_atlas,UV).rgb;
	NORMAL_MAP_DEPTH = 1.0;
	// Threat pulse 0.85..1.15 at 1 Hz; far props keep their masked accents readable.
	float pulse = 1.0 + 0.15*sin(clock*6.28318);
	EMISSION = glow*(emission_gain+charge*1.2)*pulse*(1.0+distance_gain*0.45) + accent.rgb*mask*hit*0.6;
}
