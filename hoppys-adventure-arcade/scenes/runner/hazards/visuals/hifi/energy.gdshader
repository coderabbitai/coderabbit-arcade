shader_type spatial;
render_mode blend_add, depth_draw_never, cull_back, unshaded;
uniform vec4 accent : source_color = vec4(1.0,0.30,0.24,1.0);
uniform float clock = 0.0;
uniform float strength = 0.5;
uniform float glyph = 0.0;
uniform float charge = 0.0;
uniform float distance_gain = 0.0;
uniform sampler2D atlas : source_color, filter_linear;
void fragment() {
	float rim = pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),2.0);
	vec2 drift = vec2(sin(UV.y*28.0-clock*9.0)*0.016,0.0);
	float mask = mix(1.0,texture(atlas,vec2((fract(UV.x+drift.x)+3.0)*0.25,UV.y)).a,glyph);
	float front = (1.0-smoothstep(0.05,0.5,abs(UV.y-0.5)));
	float wave = 0.82+0.18*sin(UV.y*38.0-clock*13.0);
	ALBEDO = accent.rgb*(0.5+rim+front)*wave;
	ALPHA = min(0.85,strength+charge*0.25+distance_gain*0.2)*mask*(0.24+rim*0.5+front*0.26);
}
