shader_type spatial;
render_mode cull_back;
uniform sampler2D albedo_map : source_color, filter_linear_mipmap;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_map : filter_linear_mipmap;
uniform vec4 base_color : source_color;
uniform vec4 accent : source_color = vec4(0.388,0.976,0.698,1.0);
uniform float clock = 0.0;
uniform float intensity = 1.0;
varying float inset_face;
varying vec2 inset_uv;
void vertex() {
	inset_face = step(0.5,NORMAL.z)*(1.0-step(0.35,VERTEX.z));
	inset_uv = VERTEX.xy+vec2(0.5);
}
void fragment() {
	float strip = (1.0-smoothstep(0.10,0.14,abs(inset_uv.x-0.5))) * step(0.15,inset_uv.y)*step(inset_uv.y,0.85)*inset_face;
	ALBEDO = base_color.rgb*texture(albedo_map,UV).rgb;
	METALLIC = 0.78;
	ROUGHNESS = texture(rough_map,UV).r;
	NORMAL_MAP = texture(normal_map,UV).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	EMISSION = accent.rgb*strip*min(0.5*intensity,0.6)*(0.9+0.1*sin(clock*5.0));
}
