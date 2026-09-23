shader_type spatial;
render_mode cull_back, depth_draw_opaque;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_atlas : filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.08,0.15,0.21,1.0);
uniform vec4 accent : source_color = vec4(1.0,0.30,0.24,1.0);
uniform float tile = 0.0;
uniform float emission_gain = 0.0;
uniform float clock = 0.0;
uniform float hit = 0.0;
uniform float charge = 0.0;
varying float local_height;
void vertex() { local_height = VERTEX.y; }
void fragment() {
	vec2 uv = vec2((clamp(UV.x,0.008,0.992)+tile)*0.25, UV.y);
	vec4 plate = texture(atlas,uv);
	ALBEDO = tint.rgb * (0.25 + 0.65*smoothstep(-0.5,0.5,local_height)) * (0.7 + plate.rgb);
	METALLIC = 0.78;
	ROUGHNESS = texture(rough_atlas,uv).r;
	NORMAL_MAP = texture(normal_atlas,uv).rgb;
	NORMAL_MAP_DEPTH = 0.5;
	float mask = plate.a;
	// Recessed second glyph plane gives screens view-dependent depth.
	if (tile > 0.5 && tile < 1.5) {
		vec2 inset = clamp(UV + VIEW.xy * 0.024, vec2(0.01), vec2(0.99));
		float back = texture(atlas,vec2((inset.x+1.0)*0.25,inset.y)).a;
		ALBEDO += accent.rgb*back*0.10;
	}
	float pulse = 1.0 + 0.22*sin(clock*6.28318);
	ALBEDO = mix(ALBEDO,accent.rgb*0.55,mask*min(emission_gain,0.7));

	EMISSION = accent.rgb * mask * (emission_gain+charge*0.35) * pulse + accent.rgb*mask*hit*0.20;
}
