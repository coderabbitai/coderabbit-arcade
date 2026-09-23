shader_type spatial;
render_mode cull_back;
uniform sampler2D atlas : source_color, filter_linear_mipmap;
uniform sampler2D normal_atlas : hint_normal, filter_linear_mipmap;
uniform sampler2D rough_atlas : filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.08,0.15,0.21,1.0);
uniform vec4 accent : source_color = vec4(1.0,0.30,0.24,1.0);
uniform vec4 diff_color : source_color = vec4(1.0);
uniform float tile = 0.0;
uniform float emission_gain = 0.0;
uniform float clock = 0.0;
uniform float hit = 0.0;
uniform float charge = 0.0;
uniform float roll_rate = 0.0;
uniform float distance_gain = 0.0;
void vertex() {
	float angle = clock*roll_rate;
	mat2 spin = mat2(vec2(cos(angle),-sin(angle)),vec2(sin(angle),cos(angle)));
	VERTEX.xz = spin*VERTEX.xz;
	NORMAL.xz = spin*NORMAL.xz;
	TANGENT.xz = spin*TANGENT.xz;
	BINORMAL.xz = spin*BINORMAL.xz;
}
void fragment() {
	vec2 uv = vec2((clamp(UV.x,0.008,0.992)+tile)*0.25, UV.y);
	vec4 plate = texture(atlas,uv);
	ALBEDO = tint.rgb * (0.7 + plate.rgb);
	METALLIC = 0.28;
	ROUGHNESS = clamp(texture(rough_atlas,uv).r,0.42,0.75);
	NORMAL_MAP = texture(normal_atlas,uv).rgb;
	NORMAL_MAP_DEPTH = 0.5;
	float mask = plate.a;
	// Recessed second glyph plane gives screens view-dependent depth.
	if (tile > 0.5 && tile < 1.5) {
		vec2 inset = clamp(UV + VIEW.xy * 0.024, vec2(0.01), vec2(0.99));
		float back = texture(atlas,vec2((inset.x+1.0)*0.25,inset.y)).a;
		ALBEDO += accent.rgb*back*0.10;
		// Derivative-filtered + / minus diff marks, independent of atlas resolution.
		vec2 cell = vec2(fract(UV.x*3.0),fract(UV.y*2.0))-0.5;
		float horizontal = max(abs(cell.x)-0.25,abs(cell.y)-0.045);
		float vertical = max(abs(cell.x)-0.045,abs(cell.y)-0.22);
		float symbol = mix(horizontal,min(horizontal,vertical),step(0.5,UV.y));
		float aa = max(fwidth(symbol),0.002);
		float diff_mark = 1.0-smoothstep(-aa,aa,symbol);
		ALBEDO = mix(ALBEDO,diff_color.rgb,diff_mark);

	}
	// Broad atlas accents stay visible at distance without washing the entire object red.
	float pulse = 1.0 + 0.12*sin(clock*6.28318);
	ALBEDO = mix(ALBEDO,accent.rgb*0.55,mask*min(emission_gain,0.7));
	EMISSION = accent.rgb * mask * (emission_gain+charge*0.35+min(emission_gain,0.65)*distance_gain) * pulse + accent.rgb*mask*hit*0.20;
}
