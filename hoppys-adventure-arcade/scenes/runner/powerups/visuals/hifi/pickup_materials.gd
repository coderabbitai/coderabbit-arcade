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
 ALBEDO = surface_tint * COLOR.rgb * map * (1.0-glassness*0.55);
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
static func template(variant: String) -> ShaderMaterial:
	if not cache.has(variant):
		var shader := Shader.new()
		shader.code = POOL if variant == "pool" else CODE
		if variant == "glass":
			shader.code = CODE.replace("void fragment(){", "void fragment(){\n ALPHA = 0.84;")
		var result := ShaderMaterial.new()
		result.shader = shader
		if variant != "pool":
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

static func pool(color: Color) -> ShaderMaterial:
	var result := template("pool").duplicate() as ShaderMaterial
	result.set_shader_parameter("tint",color)
	return result
