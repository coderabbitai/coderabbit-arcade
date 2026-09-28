extends RefCounted
const Textures = preload("res://scenes/runner/powerups/visuals/hifi/texture_forge.gd")
static var cache: Dictionary = {}
const CODE := """shader_type spatial;
render_mode cull_back;
uniform vec4 tint : source_color;
uniform vec4 emission_tint : source_color;
uniform vec4 inlay_tint : source_color;
uniform sampler2D plating : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normals : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D roughness_map : filter_linear_mipmap, repeat_enable;
uniform float clock = 0.0;
uniform float energy = 0.0;
uniform float range_boost = 1.0;
uniform float glass = 0.0;
uniform float emission_fill = 0.0;
uniform float emission_inset = 0.225;
varying float world_height;
void vertex(){
 world_height = (MODEL_MATRIX * vec4(VERTEX,1.0)).y;
}
void fragment(){
 vec3 map = max(texture(plating, UV).rgb, vec3(0.55));
 float inlay = 1.0-step(0.75,COLOR.a);
 float glassness = max(glass,inlay);
 vec3 surface_tint = mix(tint.rgb,inlay_tint.rgb,inlay);
 float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)),0.0),3.0);
 // One broad band per 1.2 world metres, independent of face chart size.
 float wave = cos(world_height*5.23598776-clock*1.2);
 float aa = max(fwidth(wave),0.03);
 float scan = smoothstep(0.72-aa,0.96+aa,wave);
 ALBEDO = surface_tint * COLOR.rgb * map * (1.0-glassness*0.30);
 METALLIC = mix(0.32, 0.18, glassness);
 ROUGHNESS = mix(min(texture(roughness_map, UV).r, 0.62), 0.19, glassness);
 NORMAL_MAP = texture(normals,UV).rgb;
 NORMAL_MAP_DEPTH = 0.35;
 // Broad central quarter-chart patch survives minification; never a thin border.
 float emission_mask = step(emission_inset,UV.x)*step(UV.x,1.0-emission_inset)*step(emission_inset,UV.y)*step(UV.y,1.0-emission_inset);
 // Bound the complete product, not only range_boost. Preserve hue ratios.
 float strength = min(0.65,energy*clamp(range_boost,1.0,3.0)*(emission_fill+0.10*rim+0.12*scan)*(1.0+0.30*sin(clock*4.0)));
 vec3 glow_tint = mix(emission_tint.rgb,inlay_tint.rgb,inlay);
 EMISSION = emission_mask * glow_tint * strength;
}
void light(){
 // Neutral fill preserves collectible hue under coloured ship lights.
 float light_luma = dot(LIGHT_COLOR,vec3(0.2126,0.7152,0.0722));
 vec3 illumination = mix(LIGHT_COLOR,vec3(light_luma),0.7);
 float wrapped = max(dot(NORMAL,LIGHT),0.0)*0.8+0.2;
 DIFFUSE_LIGHT += illumination*ATTENUATION*wrapped;
}
"""
## Baked Blender pickup props (tools/blender/props): one shared atlas set for all ten kinds. The
## emission map is a grey mask the family colour tints, so a pickup can never glow a hazard hue.
const PROP_MAPS := {
	"albedo_atlas": preload("res://Assets/runner/props/pickup_props_albedo.png"),
	"normal_atlas": preload("res://Assets/runner/props/pickup_props_normal.png"),
	"orm_atlas": preload("res://Assets/runner/props/pickup_props_orm.png"),
	"emission_atlas": preload("res://Assets/runner/props/pickup_props_emission.png"),
}
const PROP_CODE := """shader_type spatial;
render_mode cull_back;
uniform vec4 tint : source_color;
uniform vec4 emission_tint : source_color;
uniform sampler2D albedo_atlas : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D orm_atlas : hint_default_white, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D emission_atlas : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform float clock = 0.0;
uniform float energy = 0.0;
uniform float range_boost = 1.0;
varying float world_height;
void vertex(){
 world_height = (MODEL_MATRIX * vec4(VERTEX,1.0)).y;
}
void fragment(){
 vec3 orm = texture(orm_atlas, UV).rgb;
 // Baked shell and inlay colours; the neutral CREAM tint only warms the shell slightly.
 ALBEDO = max(texture(albedo_atlas, UV).rgb, vec3(0.02)) * mix(vec3(1.0), tint.rgb, 0.12);
 AO = orm.r;
 AO_LIGHT_AFFECT = 0.4;
 METALLIC = min(orm.b, 0.6);
 ROUGHNESS = max(orm.g, 0.18);
 NORMAL_MAP = texture(normal_atlas, UV).rgb;
 float wave = cos(world_height*5.23598776-clock*1.2);
 float aa = max(fwidth(wave),0.03);
 float scan = smoothstep(0.72-aa,0.96+aa,wave);
 // Bound the complete product, not only range_boost; the baked mask limits where it glows.
 float strength = min(0.65, energy*clamp(range_boost,1.0,3.0)*(0.85+0.12*scan)*(1.0+0.30*sin(clock*4.0)));
 EMISSION = texture(emission_atlas, UV).r * emission_tint.rgb * strength;
}
void light(){
 float light_luma = dot(LIGHT_COLOR,vec3(0.2126,0.7152,0.0722));
 vec3 illumination = mix(LIGHT_COLOR,vec3(light_luma),0.7);
 float wrapped = max(dot(NORMAL,LIGHT),0.0)*0.8+0.2;
 DIFFUSE_LIGHT += illumination*ATTENUATION*wrapped;
}
"""
const POOL := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
uniform vec4 tint : source_color;
uniform float clock = 0.0;
void fragment(){
 float radius=length(UV-vec2(0.5))*2.0;
 float falloff=pow(max(0.0,1.0-radius),3.0);
 ALBEDO=tint.rgb;
 ALPHA=falloff*0.24*(0.9+0.1*sin(clock*3.0));
}
"""
## The baked-prop template exists from script load (with the other shared templates warmed by the
## CPU prewarm), so the first pickup spawned during a run never creates a template.
static var _prop_ready: bool = _warm_prop()

static func _warm_prop() -> bool:
	template("prop")
	return true

static func template(variant: String) -> ShaderMaterial:
	if not cache.has(variant):
		var shader := Shader.new()
		shader.code = POOL if variant == "pool" else PROP_CODE if variant == "prop" else CODE
		if variant == "glass":
			shader.code = CODE.replace("void fragment(){", "void fragment(){\n ALPHA = 0.84;")
		var result := ShaderMaterial.new()
		result.shader = shader
		if variant == "prop":
			for key: String in PROP_MAPS: result.set_shader_parameter(key,PROP_MAPS[key])
		elif variant != "pool":
			var maps := Textures.maps()
			result.set_shader_parameter("plating",maps.albedo)
			result.set_shader_parameter("normals",maps.normal)
			result.set_shader_parameter("roughness_map",maps.roughness)
		cache[variant] = result
	return cache[variant]

static func material(color: Color, energy := 0.0, glass := 0.0) -> ShaderMaterial:
	var result := template("glass" if glass > 0.0 else "opaque").duplicate() as ShaderMaterial
	result.set_shader_parameter("tint",color)
	result.set_shader_parameter("emission_tint",color)
	result.set_shader_parameter("inlay_tint",color)
	result.set_shader_parameter("emission_inset",0.225)
	result.set_shader_parameter("energy",minf(energy,0.55))
	result.set_shader_parameter("glass",glass)
	result.set_shader_parameter("emission_fill",0.55 if energy > 0.0 else 0.0)
	return result

## Private material for one baked prop surface (clock and range uniforms), sharing shader and maps.
static func prop(color: Color, energy: float, glow: Color) -> ShaderMaterial:
	var result := template("prop").duplicate() as ShaderMaterial
	result.set_shader_parameter("tint",color)
	result.set_shader_parameter("emission_tint",glow)
	result.set_shader_parameter("energy",minf(energy,0.55))
	return result

static func pool(color: Color) -> ShaderMaterial:
	var result := template("pool").duplicate() as ShaderMaterial
	result.set_shader_parameter("tint",color)
	return result
